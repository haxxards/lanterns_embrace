class_name CombatManager
extends Node
## Turn-based combat on the hex grid (5e, simplified).
##
## World starts a fight when hostiles notice the party. Everyone rolls
## initiative; then, in order, each combatant gets a turn: movement up to its
## speed, one action (Attack, Dash, Dodge, Disengage, or drinking a potion), a
## bonus action (an off-hand attack after attacking with a light weapon), and
## one reaction per round (an opportunity attack when an enemy leaves its
## reach). Party members are driven by the player through World's clicks and
## the HUD's combat bar; creatures by CombatAI. Party members at 0 HP make
## death saving throws on their turns. The fight ends when one side has no
## one standing: victory shares the slain creatures' XP among the party.
##
## The turn loop is a coroutine (_run) that awaits the player's End Turn or
## the AI's moves, so the flow reads top to bottom.

signal started
signal ended(victory: bool)
signal turn_started(c: Combatant)
## Anything the combat HUD shows changed (movement, actions, hit points, order).
signal state_changed
signal logged(text: String)
## Hover hint for the combat bar ("Bite the wolf: 65% to hit").
signal hint_changed(text: String)
signal _player_done

const AI_PAUSE := 0.35
const LOG_LINES := 60

var world: World
var active: bool = false
## Everyone in the fight, in initiative order (the slain stay, marked out).
var combatants: Array[Combatant] = []
var current: Combatant = null
var round_number: int = 0
## True while a move or attack is playing out; input waits.
var busy: bool = false
## Walk and pause on screen. Tests turn this off so everything resolves at once.
var animate: bool = true
var rng := RandomNumberGenerator.new()
var log_lines: PackedStringArray = PackedStringArray()
## XP of the creatures slain so far, shared out on victory.
var xp_pool: int = 0

var _waiting_player: bool = false
var _index: int = -1


func setup(w: World) -> void:
	world = w
	rng.randomize()
	Events.party_defeated.connect(_on_party_defeated)


func _on_party_defeated() -> void:
	if active:
		_finish(false)


# --- starting and ending -------------------------------------------------------

## Starts a fight between the party and `hostiles` (Creature nodes).
func start(hostiles: Array) -> void:
	if active or hostiles.is_empty():
		return
	active = true
	GameState.combat = self
	combatants.clear()
	log_lines.clear()
	round_number = 0
	xp_pool = 0
	_index = -1
	current = null
	world.party.halt()
	for n in world.npcs:
		n.hold()
	for m in world.party.members:
		if m.sheet.dead:
			continue
		if m.sheet.hp_current <= 0:
			m.sheet.stable = true  # already down before the fight began
		combatants.append(Combatant.for_actor(m, m.sheet, Combatant.PARTY))
	for cr in hostiles:
		_add_creature(cr)
	for c in combatants:
		c.initiative = CombatRules.initiative(c.sheet, rng)
	combatants.sort_custom(_by_initiative)
	var order := PackedStringArray()
	for c in combatants:
		order.append("%s %d" % [c.display_name(), c.initiative])
	_log("[b]Combat![/b] Initiative: %s." % ", ".join(order))
	Audio.play_sfx("combat_start")
	started.emit()
	state_changed.emit()
	_run.call_deferred()


func _add_creature(cr: Creature) -> Combatant:
	cr.in_combat = true
	var c := Combatant.for_actor(cr, cr.sheet, Combatant.HOSTILE)
	combatants.append(c)
	return c


func _by_initiative(a: Combatant, b: Combatant) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	if a.sheet.ability_mod("dex") != b.sheet.ability_mod("dex"):
		return a.sheet.ability_mod("dex") > b.sheet.ability_mod("dex")
	return a.is_party() and not b.is_party()


## Stops a fight without a result (loading a game, leaving the map).
func abort() -> void:
	if not active:
		return
	_cleanup()
	_player_done.emit()


func _cleanup() -> void:
	active = false
	busy = false
	_waiting_player = false
	if GameState.combat == self:
		GameState.combat = null
	for c in combatants:
		if not is_instance_valid(c.actor):
			continue
		c.actor.smooth_paths = true
		c.prone = false
		if c.actor is Creature:
			(c.actor as Creature).active = false
			(c.actor as Creature).in_combat = false
		else:
			c.actor.occupies = false
	current = null


@warning_ignore("integer_division")
func _finish(victory: bool) -> void:
	if not active:
		return
	for c in combatants:
		if c.is_party() and c.sheet.is_down():
			c.sheet.stable = true
			c.sheet.changed.emit()
	_cleanup()
	for n in world.npcs:
		n.end_talk()
	if victory:
		var sharers: Array[CharacterSheet] = []
		for s in GameState.party:
			if not s.dead:
				sharers.append(s)
		var share := xp_pool / maxi(1, sharers.size()) if not sharers.is_empty() else 0
		_log("[b]Victory![/b] %d XP each." % share)
		Events.toast_requested.emit("Victory! %d XP each." % share)
		for s in sharers:
			if s.add_xp(share) > 0:
				Events.toast_requested.emit("%s reaches level %d!" % [s.display_name, s.level])
		world.party.select_all()
	else:
		_log("[b]The party has fallen.[/b]")
	ended.emit(victory)
	state_changed.emit()
	_player_done.emit()


## Ends the fight if one side has no one left standing. Returns true if it ended.
func _check_end() -> bool:
	if not active:
		return true
	var party_up := false
	var foes_up := false
	for c in combatants:
		if c.is_conscious():
			if c.is_party():
				party_up = true
			else:
				foes_up = true
	if not foes_up:
		_finish(true)
		return true
	if not party_up:
		_finish(false)
		return true
	return false


# --- the turn loop ----------------------------------------------------------------

func _run() -> void:
	busy = true
	await _settle()
	if not active:
		return
	for c in combatants:
		c.actor.smooth_paths = false
		c.actor.occupies = true
	busy = false
	var skipped := 0
	while active:
		if skipped > combatants.size():
			_check_end()  # nobody left who can take a turn
			return
		_index += 1
		if _index >= combatants.size():
			_index = 0
		if _index == 0:
			round_number += 1
			_join_newcomers()
		var c := combatants[_index]
		if c.is_out() or not is_instance_valid(c.actor):
			skipped += 1
			continue
		skipped = 0
		current = c
		c.begin_turn()
		_set_active_ring(c, true)
		var players_turn := c.is_party() and c.is_conscious()
		if players_turn:
			world.party.select_only(c.actor)
			_waiting_player = true
		turn_started.emit(c)
		state_changed.emit()
		if animate:
			world.camera.center_on(c.actor.global_position)
		if c.is_party():
			if players_turn:
				await _player_done
				_waiting_player = false
			elif not c.sheet.stable:
				await _death_save(c)
		else:
			await _pause(AI_PAUSE)
			if active:
				await CombatAI.take_turn(self, c)
		if not active:
			return
		_set_active_ring(c, false)
		if _check_end():
			return


## Waits until nobody is mid-stride (everyone stands on a hex centre).
func _settle() -> void:
	for c in combatants:
		c.actor.stop()
	if not animate:
		for c in combatants:
			c.actor.place_at(c.actor.hex)
		return
	var guard := 0
	while guard < 300:
		var moving := false
		for c in combatants:
			if is_instance_valid(c.actor) and c.actor.is_moving():
				moving = true
		if not moving:
			return
		guard += 1
		await get_tree().process_frame


func _pause(seconds: float) -> void:
	if animate and seconds > 0.0:
		await get_tree().create_timer(seconds, false).timeout  # waits out the pause menu


func _set_active_ring(c: Combatant, on: bool) -> void:
	if c.actor is Creature:
		(c.actor as Creature).active = on


## Creatures that notice the fight at the start of a round join in (they act last).
func _join_newcomers() -> void:
	for cr in world.hostiles_noticing(self):
		var c := _add_creature(cr)
		c.initiative = CombatRules.initiative(c.sheet, rng)
		c.actor.smooth_paths = false
		_log("%s joins the fight." % c.display_name())


func _death_save(c: Combatant) -> void:
	await _pause(0.4)
	var result := c.sheet.roll_death_save(rng)
	match result:
		"rallies":
			_log("%s rallies and gets back up with 1 hit point!" % c.display_name())
			_float(c, "Rallies!", Color(0.5, 1.0, 0.5))
		"dies":
			_log("%s fails a death save and dies." % c.display_name())
			_float(c, "Dies", Color(0.9, 0.2, 0.2))
		"stable":
			_log("%s is stable." % c.display_name())
			_float(c, "Stable", Color(0.85, 0.85, 0.85))
		_:
			_log("%s makes a death save: %s (%d ✓, %d ✗)." % [c.display_name(), result,
					c.sheet.death_successes, c.sheet.death_failures])
			_float(c, "Death save: " + result, Color(0.9, 0.85, 0.7), 14)
	state_changed.emit()
	await _pause(0.5)


# --- queries --------------------------------------------------------------------------

func is_player_turn() -> bool:
	return active and _waiting_player and not busy and current != null and current.is_party()


func combatant_of(actor: Node) -> Combatant:
	for c in combatants:
		if c.actor == actor:
			return c
	return null


## Conscious opponents of `c`.
func conscious_enemies_of(c: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for o in combatants:
		if o.is_hostile_to(c) and o.is_conscious() and not o.is_out():
			out.append(o)
	return out


func distance(a: Combatant, b: Combatant) -> int:
	return Hex.distance(a.hex(), b.hex())


## Hexes `c` can still walk to this turn: {hex: cost in hexes}.
func reachable_for(c: Combatant) -> Dictionary:
	var budget := c.movement_left / float(maxi(1, GameConfig.feet_per_hex))
	return world.grid.reachable_within(c.hex(), budget)


## Advantage (+1), disadvantage (-1) or neither (0) for an attack, and why.
func advantage(attacker: Combatant, target: Combatant, attack: Attack, from_hex: Variant = null) -> Dictionary:
	var at: Vector2i = from_hex if from_hex != null else attacker.hex()
	var dist := Hex.distance(at, target.hex())
	var adv := PackedStringArray()
	var dis := PackedStringArray()
	if not target.is_conscious():
		adv.append("target down")
	if target.prone:
		if dist <= 1:
			adv.append("target prone")
		else:
			dis.append("target prone")
	if attacker.prone:
		dis.append("prone")
	if target.dodging and target.is_conscious():
		dis.append("dodging")
	if CombatRules.has_feature(attacker.sheet, "pack_tactics") and _ally_next_to(target, attacker):
		adv.append("pack tactics")
	if attack.is_ranged():
		if dist > attack.range_normal:
			dis.append("long range")
		for o in conscious_enemies_of(attacker):
			if Hex.distance(o.hex(), at) <= 1:
				dis.append("enemy adjacent")
				break
	var n := (1 if not adv.is_empty() else 0) - (1 if not dis.is_empty() else 0)
	var why := PackedStringArray()
	why.append_array(adv)
	why.append_array(dis)
	return {"adv": n, "why": why}


## True if a conscious ally of `attacker` (not the attacker) stands next to `target`.
func _ally_next_to(target: Combatant, attacker: Combatant) -> bool:
	for o in combatants:
		if o != attacker and o.team == attacker.team and o.is_conscious() and not o.is_out() \
				and Hex.distance(o.hex(), target.hex()) <= 1:
			return true
	return false


## The attack the current combatant would use on `target` right now (an
## off-hand attack once the action is spent), or null.
func usable_attack(c: Combatant, target: Combatant) -> Attack:
	var dist := distance(c, target)
	if not c.action_used:
		var a := c.attack_for(dist)
		if a != null and (not a.is_ranged() or world.line_of_sight(c.hex(), target.hex())):
			return a
		return null
	var off := c.off_hand_attack()
	if not c.bonus_used and c.attacked_light and off != null and off.in_range(dist):
		return off
	return null


## What clicking `target` would do, for the hover hint and the info panel.
func describe_attack(c: Combatant, target: Combatant) -> String:
	var name := target.display_name()
	var hp := "%d/%d HP, AC %d" % [target.sheet.hp_current, target.sheet.hp_max, target.sheet.armor_class]
	var a := usable_attack(c, target)
	var from: Variant = null
	if a == null and not c.action_used:
		var plan := _approach_plan(c, target)
		if plan.is_empty():
			return "%s (%s): out of reach" % [name, hp]
		a = plan["attack"]
		from = plan["hex"]
	if a == null:
		return "%s (%s): no attack left this turn" % [name, hp]
	var adv := advantage(c, target, a, from)
	var chance := CombatRules.hit_chance(a.to_hit, target.sheet.armor_class, adv["adv"])
	var extra := ""
	if not (adv["why"] as PackedStringArray).is_empty():
		extra = "  (%s)" % ", ".join(adv["why"])
	var verb := "Move in, then %s" % a.name.to_lower() if from != null else a.name
	return "%s %s: %d%% to hit, %s%s   [%s]" % [verb, name, roundi(chance * 100.0), a.damage, extra, hp]


## For a melee attack out of reach: the cheapest hex within this turn's
## movement from which `target` can be struck. {} if none.
func _approach_plan(c: Combatant, target: Combatant) -> Dictionary:
	var melee := c.melee_attack()
	if melee == null:
		return {}
	var reach := reachable_for(c)
	var best: Variant = null
	var best_cost := INF
	for h in reach:
		if Hex.distance(h, target.hex()) <= melee.reach and reach[h] < best_cost:
			best = h
			best_cost = reach[h]
	if best == null:
		return {}
	return {"hex": best, "attack": melee, "cost": best_cost}


# --- player actions ---------------------------------------------------------------------

func end_turn() -> void:
	if is_player_turn():
		_player_done.emit()


func dash() -> void:
	if is_player_turn() and _use_action(current, "dashes"):
		current.movement_left += current.speed_ft()
		state_changed.emit()


func dodge() -> void:
	if is_player_turn() and _use_action(current, "takes the Dodge action"):
		current.dodging = true
		state_changed.emit()


func disengage() -> void:
	if is_player_turn() and _use_action(current, "disengages"):
		current.disengaged = true
		state_changed.emit()


func _use_action(c: Combatant, what: String) -> bool:
	if c.action_used:
		Events.toast_requested.emit("%s has already used their action." % c.display_name())
		return false
	c.action_used = true
	_log("%s %s." % [c.display_name(), what])
	return true


## The player clicked the ground: walk there if this turn's movement allows.
func player_move(h: Vector2i) -> void:
	if not is_player_turn() or h == current.hex():
		return
	var reach := reachable_for(current)
	if not reach.has(h):
		Events.toast_requested.emit("Too far: %d ft of movement left." % roundi(current.movement_left))
		return
	busy = true
	await move_along(current, current.actor.path_to(h))
	busy = false
	state_changed.emit()
	_check_end()


## The player clicked an enemy: attack it, stepping up first if a melee
## attack needs it and the movement allows.
func player_attack(target: Combatant) -> void:
	if not is_player_turn() or target == null or not target.is_hostile_to(current):
		return
	var a := usable_attack(current, target)
	busy = true
	if a == null and not current.action_used:
		var plan := _approach_plan(current, target)
		if plan.is_empty():
			busy = false
			Events.toast_requested.emit("%s is out of reach." % target.display_name())
			return
		await move_along(current, current.actor.path_to(plan["hex"]))
		if active and current.is_conscious():
			a = usable_attack(current, target)
	if a == null:
		busy = false
		if active and current.action_used and current.is_conscious():
			Events.toast_requested.emit("%s has no attack left this turn." % current.display_name())
		return
	await attack_with(current, target, a)
	busy = false
	state_changed.emit()
	_check_end()


## Whether `sheet` may drink or be given a potion now: on the current party
## member's turn, by them or someone next to them, with their action unused.
func item_use_error(sheet: CharacterSheet) -> String:
	if not is_player_turn():
		return "Wait for your turn."
	if current.action_used:
		return "%s has already used their action." % current.display_name()
	if sheet != current.sheet:
		var other: Combatant = null
		for c in combatants:
			if c.sheet == sheet:
				other = c
		if other == null or distance(other, current) > 1:
			return "%s is too far away to help %s." % [current.display_name(), sheet.display_name]
	return ""


func item_used(_sheet: CharacterSheet) -> void:
	if current != null:
		current.action_used = true
		state_changed.emit()


# --- moving and attacking (shared by the player and the AI) -----------------------------

## Walks `c` along `path` one hex at a time while its movement lasts. Leaving
## an enemy's reach provokes an opportunity attack (unless disengaged).
func move_along(c: Combatant, path: Array[Vector2i]) -> void:
	var feet := float(maxi(1, GameConfig.feet_per_hex))
	for step in path:
		if not active or not c.is_conscious():
			return
		var cost := world.grid.move_cost(step) * feet
		if cost > c.movement_left + 0.01 or world.grid.is_occupied(step):
			return
		var from := c.hex()
		if not c.disengaged:
			for e in combatants:
				if not e.is_hostile_to(c) or not e.is_conscious() or e.is_out() or e.reaction_used:
					continue
				var m := e.melee_attack()
				if m != null and Hex.distance(e.hex(), from) <= m.reach and Hex.distance(e.hex(), step) > m.reach:
					e.reaction_used = true
					_log("%s leaves %s's reach: opportunity attack!" % [c.display_name(), e.display_name()])
					await attack_with(e, c, m, true)
					if not active or not c.is_conscious():
						return
		c.movement_left -= cost
		if animate:
			var one: Array[Vector2i] = [step]
			c.actor.follow_path(one)
			await c.actor.arrived
		else:
			c.actor.place_at(step)
			c.actor.hex_entered.emit(c.actor, step)
		state_changed.emit()


## Dash for the AI (the player uses dash()).
func ai_dash(c: Combatant) -> void:
	if not c.action_used:
		c.action_used = true
		c.movement_left += c.speed_ft()
		_log("%s dashes." % c.display_name())


## Makes one attack and applies the result. Uses the action (or, for an
## off-hand attack, the bonus action; for an opportunity attack, `reaction`).
## Returns false if it couldn't attack.
func attack_with(attacker: Combatant, target: Combatant, attack: Attack, reaction: bool = false) -> bool:
	if not active or attacker.is_out() or target.is_out():
		return false
	if attack.ammo != "" and attacker.is_party():
		if attacker.sheet.inventory.remove_item(attack.ammo, 1) <= 0:
			var ammo_def: ItemDef = Data.items.get(attack.ammo)
			var ammo_name := ammo_def.display_name.to_lower() if ammo_def else attack.ammo
			_log("%s is out of %s." % [attacker.display_name(), ammo_name])
			Events.toast_requested.emit("%s is out of %s." % [attacker.display_name(), ammo_name])
			return false
	if not reaction:  # an opportunity attack costs the reaction, not the action
		if attack.off_hand:
			attacker.bonus_used = true
		else:
			attacker.action_used = true
			attacker.attacked_light = attack.light and not attack.is_ranged()
	var dist := distance(attacker, target)
	var adv := advantage(attacker, target, attack)
	var ac := target.sheet.armor_class
	var r := CombatRules.roll_attack(attack.to_hit, ac, adv["adv"], rng)
	var crit: bool = r["crit"]
	if r["hit"] and not target.is_conscious() and dist <= 1:
		crit = true  # a hit within 5 ft on someone unconscious is a critical hit
	attacker.actor.face_towards(target.actor.position)
	await _lunge(attacker, target, attack)
	var roll_text := "%d%s%s" % [r["d20"], Rules.format_modifier(attack.to_hit), "" if adv["adv"] == 0 else
			(" with advantage" if adv["adv"] > 0 else " with disadvantage")]
	if not r["hit"]:
		_log("%s attacks %s with %s: %s = %d vs AC %d, miss." % [attacker.display_name(), target.display_name(),
				attack.name, roll_text, r["total"], ac])
		_float(target, "Miss", Color(0.85, 0.85, 0.85))
		Audio.play_sfx("swing_miss")
		state_changed.emit()
		return true
	var dmg := CombatRules.roll_damage(attack.damage, crit, rng)
	var notes := PackedStringArray()
	if crit:
		notes.append("critical hit")
	if _sneak_attack_applies(attacker, target, attack, adv["adv"]):
		attacker.sneak_attack_used = true
		dmg += CombatRules.roll_damage(CombatRules.sneak_attack_dice(attacker.sheet), crit, rng)
		notes.append("sneak attack")
	var before := dmg
	dmg = CombatRules.adjust_for_type(target.sheet, dmg, attack.damage_type)
	if dmg > before:
		notes.append("vulnerable")
	elif dmg < before:
		notes.append("resisted" if dmg > 0 else "immune")
	var was_down := not target.is_conscious()
	target.sheet.damage(dmg, crit)
	_log("%s hits %s with %s: %s = %d vs AC %d, %d %s damage%s." % [attacker.display_name(),
			target.display_name(), attack.name, roll_text, r["total"], ac, dmg, attack.damage_type,
			"" if notes.is_empty() else " (%s)" % ", ".join(notes)])
	_float(target, ("Critical! -%d" if crit else "-%d") % dmg, Color(1.0, 0.85, 0.3) if crit else Color(1.0, 0.4, 0.3),
			20 if crit else 18)
	Audio.play_sfx("hit")
	if target.is_party():
		_after_party_hit(target, was_down)
	elif target.sheet.dead:
		_on_slain(target)
	if target.is_conscious() and not attack.on_hit.is_empty():
		_apply_on_hit(target, attack.on_hit)
	state_changed.emit()
	return true


func _sneak_attack_applies(attacker: Combatant, target: Combatant, attack: Attack, adv: int) -> bool:
	if attacker.sneak_attack_used or not CombatRules.has_feature(attacker.sheet, "sneak_attack"):
		return false
	if not (attack.finesse or attack.is_ranged()) or adv < 0:
		return false
	return adv > 0 or _ally_next_to(target, attacker)


func _after_party_hit(target: Combatant, was_down: bool) -> void:
	var s := target.sheet
	if s.dead:
		_log("[color=#e05a4a]%s is killed![/color]" % target.display_name())
		_float(target, "Killed", Color(0.9, 0.2, 0.2))
	elif was_down:
		_log("%s, already down, suffers a failed death save (%d ✗)." % [target.display_name(), s.death_failures])
	elif not s.is_alive():
		target.prone = false
		_log("[color=#e0a04a]%s falls unconscious![/color]" % target.display_name())
		_float(target, "Down!", Color(0.95, 0.6, 0.3))


func _apply_on_hit(target: Combatant, effect: Dictionary) -> void:
	if effect.has("save"):
		var sv := CombatRules.saving_throw(target.sheet, str(effect["save"]), int(effect.get("dc", 10)), rng)
		if sv["success"]:
			return
	if str(effect.get("condition", "")) == "prone" and not target.prone:
		target.prone = true
		_log("%s is knocked prone." % target.display_name())
		_float(target, "Prone", Color(0.9, 0.8, 0.5), 15)


func _on_slain(target: Combatant) -> void:
	var cr := target.actor as Creature
	xp_pool += cr.def.xp if cr != null else 0
	_log("[color=#a0d070]%s is slain.[/color]" % target.display_name())
	if cr != null:
		world.on_creature_slain(cr)


## A short step towards the target and back (melee) or a pause (ranged).
func _lunge(attacker: Combatant, target: Combatant, attack: Attack) -> void:
	if not animate:
		return
	var a := attacker.actor
	if attack.is_ranged():
		await _pause(0.25)
		return
	var start := a.position
	var dir := (target.actor.position - start).normalized()
	var tw := a.create_tween()
	tw.tween_property(a, "position", start + dir * 12.0, 0.1)
	tw.tween_property(a, "position", start, 0.14)
	await tw.finished


func _float(c: Combatant, text: String, color: Color, size: int = 18) -> void:
	if is_instance_valid(c.actor):
		FloatingText.spawn(world, c.actor.global_position + Vector2(0, -58), text, color, size)


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > LOG_LINES:
		log_lines = log_lines.slice(log_lines.size() - LOG_LINES)
	logged.emit(text)


func set_hint(text: String) -> void:
	hint_changed.emit(text)
