class_name CombatManager
extends Node
## Turn-based combat on the hex grid (5e, simplified).
##
## World starts a fight when hostiles notice the party. Everyone rolls
## initiative; then, in order, each combatant gets a turn: movement up to its
## speed, one action (Attack, Dash, Dodge, Disengage, a spell, a potion...), a
## bonus action (an off-hand attack, a bonus-action spell, Second Wind...),
## and one reaction per round (an opportunity attack, or Shield). Party
## members are driven by the player through World's clicks and the HUD's
## combat bar; creatures by CombatAI. Party members at 0 HP make death saving
## throws on their turns. The fight ends when one side has no one standing
## (victory shares the slain creatures' XP), or when the party gets far
## enough away that no foe can see it (escape).
##
## Spells and features are cast through use_ability(); those that need a
## target put the fight in targeting mode (World sends the next click to
## confirm_target). CombatSpells and CombatFeatures carry out their effects.
##
## The turn loop is a coroutine (_run) that awaits the player's End Turn or
## the AI's moves, so the flow reads top to bottom. A fight can be saved on a
## party member's turn (to_dict) and resumed from a save (restore).

signal started
signal ended(victory: bool)
## The fight was stopped without a result (a game loaded, the map left).
signal aborted
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
## The ability waiting for a target: {"kind": "spell"/"feature"/"scroll", "id"...}
## (see use_ability), or {} when clicks act normally.
var targeting: Dictionary = {}
## Whether the last attack_with hit.
var last_hit: bool = false

var _waiting_player: bool = false
var _index: int = -1
## Bumped whenever a fight starts, is restored or is aborted. A turn still
## playing out from before (say a game was loaded mid-move) sees the change
## and stops, instead of carrying on in the new fight.
var _generation: int = 0


func setup(w: World) -> void:
	world = w
	rng.randomize()
	Events.party_defeated.connect(_on_party_defeated)


func _on_party_defeated() -> void:
	if active:
		_finish("defeat")


# --- starting and ending -------------------------------------------------------

## Starts a fight between the party and `hostiles` (Creature nodes).
func start(hostiles: Array) -> void:
	if active or hostiles.is_empty():
		return
	active = true
	_generation += 1
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
	aborted.emit()
	_player_done.emit()


# --- saving and loading a fight -----------------------------------------------------

## The fight as plain data, for a save made on a party member's turn: the
## order with each combatant's turn state and conditions, the creatures' hit
## points and hexes, whose turn it is, the round and the log. Party members'
## sheets and hexes are saved with the rest of the game (GameState).
func to_dict() -> Dictionary:
	var list: Array = []
	for c in combatants:
		if not c.is_out() and is_instance_valid(c.actor):
			list.append(c.to_dict())
	return {"round": round_number, "current": current.key if current != null else "", "xp_pool": xp_pool,
			"combatants": list, "log": Array(log_lines.slice(maxi(0, log_lines.size() - 20)))}


## Picks up a fight saved by to_dict, once World has loaded the map and placed
## the party and the creatures. The saved turn carries on where it was.
## Returns false (and starts nothing) if no one from the save is here.
func restore(d: Dictionary) -> bool:
	if active:
		return false
	var actors := {}
	for m in world.party.members:
		actors["party:%s" % m.sheet.id] = m
	for cr in world.creatures:
		if cr.is_alive():
			actors["creature:%s" % cr.spawn_id] = cr
	# Creatures back where they stood: all lifted off the grid first, so two
	# that swapped places don't free each other's hex.
	var moved: Array[Creature] = []
	for e in d.get("combatants", []):
		var cr: Creature = actors.get(str(e.get("key", ""))) as Creature
		if cr != null and e.has("hex"):
			cr.occupies = false
			moved.append(cr)
	for e in d.get("combatants", []):
		var cr: Creature = actors.get(str(e.get("key", ""))) as Creature
		if cr != null and e.has("hex"):
			cr.place_at(JsonUtil.to_vec2i(e["hex"]))
	for cr in moved:
		cr.occupies = true
	var made := {}
	var order: Array[Combatant] = []
	for e in d.get("combatants", []):
		var a: Actor = actors.get(str(e.get("key", "")))
		if a == null or (a is PartyMember and (a as PartyMember).sheet.dead):
			continue
		var c: Combatant
		if a is Creature:
			var cr := a as Creature
			cr.in_combat = true
			cr.sheet.hp_current = clampi(int(e.get("hp", cr.sheet.hp_max)), 1, cr.sheet.hp_max)
			cr.sheet.changed.emit()
			c = Combatant.for_actor(cr, cr.sheet, Combatant.HOSTILE)
		else:
			c = Combatant.for_actor(a, (a as PartyMember).sheet, Combatant.PARTY)
		made[c.key] = c
		order.append(c)
	var has_party := false
	var has_foe := false
	for c in order:
		has_party = has_party or c.is_party()
		has_foe = has_foe or not c.is_party()
	if not has_party or not has_foe:
		return false
	for e in d.get("combatants", []):
		var c: Combatant = made.get(str(e.get("key", "")))
		if c != null:
			c.load_dict(e, made)
	active = true
	_generation += 1
	GameState.combat = self
	combatants = order
	round_number = int(d.get("round", 1))
	xp_pool = int(d.get("xp_pool", 0))
	log_lines = PackedStringArray(d.get("log", []))
	current = made.get(str(d.get("current", "")))
	_index = combatants.find(current) if current != null else -1
	busy = false
	world.party.halt()
	for n in world.npcs:
		n.hold()
	_log("[i]The fight goes on (loaded from a save).[/i]")
	started.emit()
	state_changed.emit()
	_run.call_deferred(current != null)
	return true


func _cleanup() -> void:
	active = false
	_generation += 1
	busy = false
	_waiting_player = false
	targeting = {}
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


## Ends the fight: "victory" (no foe standing), "defeat" (no party member
## standing) or "escape" (the party got out of sight). XP for the creatures
## slain is shared on a victory or an escape.
@warning_ignore("integer_division")
func _finish(outcome: String) -> void:
	if not active:
		return
	for c in combatants:
		if c.is_party() and c.sheet.is_down():
			c.sheet.stable = true
			c.sheet.changed.emit()
	_cleanup()
	for n in world.npcs:
		n.end_talk()
	if outcome == "defeat":
		_log("[b]The party has fallen.[/b]")
	else:
		var sharers: Array[CharacterSheet] = []
		for s in GameState.party:
			if not s.dead:
				sharers.append(s)
		var share := xp_pool / maxi(1, sharers.size()) if not sharers.is_empty() else 0
		var head := "Victory!" if outcome == "victory" else "You got away."
		var xp_text := " %d XP each." % share if share > 0 or outcome == "victory" else ""
		_log("[b]%s[/b]%s" % [head, xp_text])
		Events.toast_requested.emit(head + xp_text)
		if share > 0:
			for s in sharers:
				if s.add_xp(share) > 0:
					Events.toast_requested.emit(s.level_up_message())
		world.party.select_all()
	ended.emit(outcome == "victory")
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
		_finish("victory")
		return true
	if not party_up:
		_finish("defeat")
		return true
	return false


## From the second round on: if no conscious foe is within its aggro range
## (+2) of a conscious party member, with a clear line of sight, the party
## has got away and the fight ends. Returns true if it did.
func _check_escape() -> bool:
	if round_number < 2:
		return false
	for e in combatants:
		if e.is_party() or not e.is_conscious() or e.is_out() or not is_instance_valid(e.actor):
			continue
		var reach := ((e.sheet as CreatureSheet).def.aggro if e.sheet is CreatureSheet else 7) + 2
		for p in combatants:
			if p.is_party() and p.is_conscious() and is_instance_valid(p.actor) \
					and Hex.distance(p.hex(), e.hex()) <= reach and world.line_of_sight(p.hex(), e.hex()):
				return false
	_finish("escape")
	return true


# --- the turn loop ----------------------------------------------------------------

## The fight's turn loop. `resume`: carry on the turn of `current` restored
## from a save, instead of starting a new round.
func _run(resume: bool = false) -> void:
	var gen := _generation
	busy = true
	if not resume:
		await _settle()
		if not active or gen != _generation:
			return
	for c in combatants:
		if is_instance_valid(c.actor):
			c.actor.smooth_paths = false
			c.actor.occupies = true
	busy = false
	if resume and current != null:
		await _turn(current, false)
		if not active or gen != _generation or _check_end():
			return
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
			if _check_escape():
				return
		var c := combatants[_index]
		if c.is_out() or not is_instance_valid(c.actor):
			skipped += 1
			continue
		skipped = 0
		await _turn(c, true)
		if not active or gen != _generation:
			return
		if _check_end():
			return


## One combatant's turn. `fresh` starts it; false carries on a turn restored
## from a save (its movement and actions as they were).
func _turn(c: Combatant, fresh: bool) -> void:
	current = c
	if fresh:
		c.begin_turn()
		if not _start_of_turn(c):  # asleep: the turn passes
			_end_of_turn(c)
			state_changed.emit()
			return
	_set_active_ring(c, true)
	var players_turn := c.is_party() and c.can_act()
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
		elif c.sheet.is_down() and not c.sheet.stable:
			await _death_save(c)
	else:
		await _pause(AI_PAUSE)
		if in_fight(c):
			await CombatAI.take_turn(self, c)
	if not in_fight(c):
		return
	cancel_targeting()
	_set_active_ring(c, false)
	_end_of_turn(c)


## Effects that count down at the start of a turn: concentration, being
## turned, sleep. Returns false if `c` sleeps through the turn.
func _start_of_turn(c: Combatant) -> bool:
	if not c.concentration.is_empty():
		c.concentration["rounds"] = int(c.concentration["rounds"]) - 1
		if int(c.concentration["rounds"]) <= 0:
			end_concentration(c, "%s's %s wears off." % [c.display_name(), _spell_name(str(c.concentration["spell"]))])
	if c.turned_by != null:
		c.turned_rounds -= 1
		if c.turned_rounds <= 0:
			c.turned_by = null
			_log("%s is no longer turned." % c.display_name())
	if c.asleep:
		c.asleep_rounds -= 1
		if c.asleep_rounds > 0:
			_log("%s sleeps." % c.display_name())
			_float(c, "Zzz", Color(0.7, 0.8, 1.0), 15)
			return false
		c.asleep = false
		_log("%s wakes up." % c.display_name())
	return true


## Guiding Bolt's mark lasts until the end of the marker's next turn.
func _end_of_turn(c: Combatant) -> void:
	for o in combatants:
		if o.marked_by == c:
			if o.mark_age >= 1:
				o.marked_by = null
			else:
				o.mark_age += 1


func _spell_name(spell_id: String) -> String:
	var s: SpellDef = Data.spells.get(spell_id)
	return s.display_name if s != null else spell_id


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
	if not in_fight(c):
		return
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


## Whether `c` is in the fight going on now (false once it has ended, or
## when `c` belongs to a fight replaced by one loaded from a save).
func in_fight(c: Combatant) -> bool:
	return active and c != null and combatants.has(c)


func combatant_of(actor: Node) -> Combatant:
	for c in combatants:
		if c.actor == actor:
			return c
	return null


## Whoever stands on `h` and is still in the fight, or null.
func combatant_at_hex(h: Vector2i) -> Combatant:
	for c in combatants:
		if not c.is_out() and is_instance_valid(c.actor) and c.actor.hex == h:
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
	elif target.asleep:
		adv.append("target asleep")
	if target.marked_by != null:
		adv.append("guiding bolt")
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
## off-hand attack once the action is spent), or null. A weapon is only
## thrown when the target can't be reached for a melee attack this turn.
func usable_attack(c: Combatant, target: Combatant) -> Attack:
	var dist := distance(c, target)
	if not c.action_used:
		var a := c.attack_for(dist)
		if a != null and a.thrown_from != "" and not _approach_plan(c, target).is_empty():
			return null  # walk up and strike instead
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
	var hp := "%d/%d HP, AC %d" % [target.sheet.hp_current, target.sheet.hp_max, target.armor_class()]
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
	var chance := CombatRules.hit_chance_blessed(a.to_hit, target.armor_class(), adv["adv"]) if c.blessed_by != null \
			else CombatRules.hit_chance(a.to_hit, target.armor_class(), adv["adv"])
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
	var me := current
	busy = true
	await move_along(me, me.actor.path_to(h))
	if not in_fight(me):
		return
	busy = false
	state_changed.emit()
	_check_end()


## The player clicked an enemy: attack it, stepping up first if a melee
## attack needs it and the movement allows.
func player_attack(target: Combatant) -> void:
	if not is_player_turn() or target == null or not target.is_hostile_to(current):
		return
	var me := current
	var a := usable_attack(me, target)
	busy = true
	if a == null and not me.action_used:
		var plan := _approach_plan(me, target)
		if plan.is_empty():
			busy = false
			Events.toast_requested.emit("%s is out of reach." % target.display_name())
			return
		await move_along(me, me.actor.path_to(plan["hex"]))
		if not in_fight(me):
			return
		if me.is_conscious():
			a = usable_attack(me, target)
	if a == null:
		busy = false
		if me.action_used and me.is_conscious():
			Events.toast_requested.emit("%s has no attack left this turn." % me.display_name())
		return
	await attack_with(me, target, a)
	if not in_fight(me):
		return
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


# --- spells, features and scrolls ------------------------------------------------------------

## The spells, features and scrolls `c` could use, for the combat bar. Each is
## {"kind": "spell"/"feature"/"scroll", "id", "slot" (spells: the slot level),
## "item" (scrolls), "name", "cost", "error" ("" if usable now), "tooltip",
## "needs_target"}. Reaction and no-effect spells are left out.
func abilities_for(c: Combatant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if c == null or not c.is_party():
		return out
	for spell in Spellcasting.known(c.sheet):
		if spell.utility or spell.cast == "reaction":
			continue
		var lowest := CombatSpells.slot_level(c, spell)
		out.append(_spell_ability(c, spell, lowest, ""))
		if not spell.is_cantrip():  # casting with a higher slot, when there is one
			var levels: Array = Spellcasting.slots_max(c.sheet).keys()
			levels.sort()
			for lv in levels:
				if int(lv) > maxi(lowest, spell.level) and Spellcasting.slots_left(c.sheet, int(lv)) > 0:
					out.append(_spell_ability(c, spell, int(lv), ""))
	for f in CombatFeatures.abilities(c):
		out.append({"kind": "feature", "id": f, "name": CombatFeatures.display_name(f), "cost": CombatFeatures.cost(f),
				"error": _turn_error(c) if not _turn_error(c).is_empty() else CombatFeatures.error(self, c, f),
				"tooltip": CombatFeatures.tooltip(c, f), "needs_target": false})
	var seen := {}
	for st in c.sheet.inventory.slots:
		if st == null or st.def == null or not st.def.use.has("cast") or seen.has(st.id):
			continue
		seen[st.id] = true
		var spell: SpellDef = Data.spells.get(str(st.def.use["cast"]))
		if spell != null:
			out.append(_spell_ability(c, spell, spell.level, st.id))
	return out


func _spell_ability(c: Combatant, spell: SpellDef, slot: int, scroll_item: String) -> Dictionary:
	var err := _turn_error(c)
	if err.is_empty():
		err = CombatSpells.error(c, spell, scroll_item)
	var name := spell.display_name
	if not scroll_item.is_empty():
		name = "Scroll: %s" % spell.display_name
	elif not spell.is_cantrip() and slot > spell.level:
		name = "%s (%s)" % [spell.display_name, SpellDef.ordinal(slot)]
	var tip := "%s · %s\n%s" % [spell.level_text(), spell.summary(), spell.description]
	if not scroll_item.is_empty():
		tip += "\nRead from the scroll (used up); no slot needed."
	elif not spell.is_cantrip():
		tip += "\nUses a %s-level slot. Slots: %s" % [SpellDef.ordinal(maxi(slot, spell.level)),
				Spellcasting.slots_text(c.sheet)]
	return {"kind": "scroll" if not scroll_item.is_empty() else "spell", "id": spell.id, "slot": slot,
			"item": scroll_item, "name": name, "cost": spell.cast, "error": err, "tooltip": tip,
			"needs_target": spell.needs_target()}


func _turn_error(c: Combatant) -> String:
	if not is_player_turn() or c != current:
		return "Wait for %s's turn." % c.display_name()
	return ""


## Why `ab` (from abilities_for) can't be used now, rechecked ("" if it can).
func ability_error(ab: Dictionary) -> String:
	if current == null:
		return "No one's turn."
	var err := _turn_error(current)
	if not err.is_empty():
		return err
	if str(ab.get("kind")) == "feature":
		return CombatFeatures.error(self, current, str(ab["id"]))
	var spell: SpellDef = Data.spells.get(str(ab.get("id")))
	if spell == null:
		return "Unknown spell."
	if str(ab.get("item", "")) != "" and not current.sheet.has_item(str(ab["item"])):
		return "%s has no such scroll." % current.display_name()
	return CombatSpells.error(current, spell, str(ab.get("item", "")))


## The player picked an ability on the combat bar: use it now, or wait for a
## target (the next map click goes to confirm_target).
func use_ability(ab: Dictionary) -> void:
	var err := ability_error(ab)
	if not err.is_empty():
		Events.toast_requested.emit(err)
		return
	if str(ab["kind"]) == "feature":
		cancel_targeting()
		CombatFeatures.use(self, current, str(ab["id"]))
		_check_end()
		return
	if bool(ab.get("needs_target", false)):
		targeting = ab.duplicate()
		set_hint("%s: choose a target (right-click or Esc to cancel)." % str(ab["name"]))
		state_changed.emit()
		return
	await _cast_now(ab, current.hex(), null)


func cancel_targeting() -> void:
	if targeting.is_empty():
		return
	targeting = {}
	set_hint("")
	state_changed.emit()


## What the targeted ability would do at `h` / on `who`: {"ok", "text", "hexes"}.
func preview_target(h: Vector2i, who: Combatant) -> Dictionary:
	if targeting.is_empty() or current == null:
		var none: Array[Vector2i] = []
		return {"ok": false, "text": "", "hexes": none}
	var spell: SpellDef = Data.spells.get(str(targeting["id"]))
	var slot := CombatSpells.slot_level(current, spell, str(targeting.get("item", "")), int(targeting.get("slot", 0)))
	return CombatSpells.preview(self, current, spell, slot, h, who)


## A map click while targeting: cast if the target is good, else say why.
func confirm_target(h: Vector2i, who: Combatant) -> void:
	if targeting.is_empty() or not is_player_turn():
		return
	var p := preview_target(h, who)
	if not p["ok"]:
		Events.toast_requested.emit(str(p["text"]))
		return
	var ab := targeting
	targeting = {}
	set_hint("")
	await _cast_now(ab, h, who)


func _cast_now(ab: Dictionary, h: Vector2i, who: Combatant) -> void:
	var err := ability_error(ab)
	if not err.is_empty():
		Events.toast_requested.emit(err)
		return
	var spell: SpellDef = Data.spells[str(ab["id"])]
	var item := str(ab.get("item", ""))
	var slot := CombatSpells.slot_level(current, spell, item, int(ab.get("slot", 0)))
	var me := current
	busy = true
	await CombatSpells.cast(self, me, spell, slot, h, who, item)
	if not in_fight(me):
		return
	busy = false
	state_changed.emit()
	_check_end()


# Public helpers for CombatSpells and CombatFeatures.
func log_line(text: String) -> void:
	_log(text)


func float_text(c: Combatant, text: String, color: Color, size: int = 18) -> void:
	_float(c, text, color, size)


func pause(seconds: float) -> void:
	await _pause(seconds)


# --- moving and attacking (shared by the player and the AI) -----------------------------

## Walks `c` along `path` one hex at a time while its movement lasts. Leaving
## an enemy's reach provokes an opportunity attack (unless disengaged).
func move_along(c: Combatant, path: Array[Vector2i]) -> void:
	var feet := float(maxi(1, GameConfig.feet_per_hex))
	for step in path:
		if not in_fight(c) or not c.is_conscious():
			return
		var cost := world.grid.move_cost(step) * feet
		if cost > c.movement_left + 0.01 or world.grid.is_occupied(step):
			return
		var from := c.hex()
		if not c.disengaged:
			for e in combatants:
				if not e.is_hostile_to(c) or not e.can_act() or e.is_out() or e.reaction_used \
						or e.turned_by != null:
					continue
				var m := e.melee_attack()
				if m != null and Hex.distance(e.hex(), from) <= m.reach and Hex.distance(e.hex(), step) > m.reach:
					e.reaction_used = true
					_log("%s leaves %s's reach: opportunity attack!" % [c.display_name(), e.display_name()])
					await attack_with(e, c, m, true)
					if not in_fight(c) or not c.is_conscious():
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
## off-hand attack, the bonus action; for an opportunity attack, `reaction`;
## nothing when `costs` is false, for spell attacks the cast already paid
## for). Bless adds 1d4 to the roll; a Shield spell may turn a hit into a
## miss; a thrown weapon lands at the target's feet. Returns false if it
## couldn't attack; last_hit says whether it hit.
func attack_with(attacker: Combatant, target: Combatant, attack: Attack, reaction: bool = false,
		costs: bool = true) -> bool:
	last_hit = false
	if not in_fight(attacker) or not in_fight(target) or attacker.is_out() or target.is_out():
		return false
	if attack.ammo != "" and attacker.is_party():
		if attacker.sheet.inventory.remove_item(attack.ammo, 1) <= 0:
			var ammo_def: ItemDef = Data.items.get(attack.ammo)
			var ammo_name := ammo_def.display_name.to_lower() if ammo_def else attack.ammo
			_log("%s is out of %s." % [attacker.display_name(), ammo_name])
			Events.toast_requested.emit("%s is out of %s." % [attacker.display_name(), ammo_name])
			return false
	if costs and not reaction:  # an opportunity attack costs the reaction, not the action
		if attack.off_hand:
			attacker.bonus_used = true
		else:
			attacker.action_used = true
			attacker.attacked_light = attack.light and not attack.is_ranged()
	var dist := distance(attacker, target)
	var adv := advantage(attacker, target, attack)
	if target.marked_by != null:
		target.marked_by = null  # Guiding Bolt's advantage is used up
	var bless := Rules.roll(1, 4, rng) if attacker.blessed_by != null else 0
	var ac := target.armor_class()
	var r := CombatRules.roll_attack(attack.to_hit + bless, ac, adv["adv"], rng)
	var crit: bool = r["crit"]
	if r["hit"] and not crit and _shield_reaction(target, int(r["total"]), ac):
		ac = target.armor_class()
		r["hit"] = false
	if r["hit"] and (not target.is_conscious() or target.asleep) and dist <= 1:
		crit = true  # a hit within 5 ft on someone unconscious (or asleep) is a critical hit
	attacker.actor.face_towards(target.actor.position)
	await CombatFx.play_attack(self, attacker, target, attack, r["hit"], crit)
	if not in_fight(attacker) or not in_fight(target):
		return false  # a game was loaded while the blow played out
	if attack.thrown_from != "" and attacker.is_party():
		_land_thrown(attacker, target, attack)
	var roll_text := "%d%s%s%s" % [r["d20"], Rules.format_modifier(attack.to_hit),
			" + %d bless" % bless if bless > 0 else "",
			"" if adv["adv"] == 0 else (" with advantage" if adv["adv"] > 0 else " with disadvantage")]
	if not r["hit"]:
		if attack.spell:
			_log("%s's %s misses %s: %s = %d vs AC %d." % [attacker.display_name(), attack.name, target.display_name(),
					roll_text, r["total"], ac])
		else:
			_log("%s attacks %s with %s: %s = %d vs AC %d, miss." % [attacker.display_name(), target.display_name(),
					attack.name, roll_text, r["total"], ac])
		_float(target, "Miss", Color(0.85, 0.85, 0.85))
		Audio.play_sfx("swing_miss")
		state_changed.emit()
		return true
	last_hit = true
	var dmg := CombatRules.roll_damage(attack.damage, crit, rng)
	var notes := PackedStringArray()
	if crit:
		notes.append("critical hit")
	if _sneak_attack_applies(attacker, target, attack, adv["adv"]):
		attacker.sneak_attack_used = true
		dmg += CombatRules.roll_damage(CombatRules.sneak_attack_dice(attacker.sheet), crit, rng)
		notes.append("sneak attack")
	var what := "%s hits %s with %s: %s = %d vs AC %d" % [attacker.display_name(), target.display_name(),
			attack.name, roll_text, r["total"], ac]
	deal_damage(target, dmg, attack.damage_type, crit, what, notes)
	if target.is_conscious() and not target.is_out() and not attack.on_hit.is_empty():
		_apply_on_hit(target, attack.on_hit)
	state_changed.emit()
	return true


## Takes `amount` of `damage_type` damage off `target`, after its
## resistances, and logs it as "<what>, N damage (notes)." Damage wakes the
## asleep, ends being turned, and makes a concentrating caster save. Returns
## the damage dealt.
@warning_ignore("integer_division")
func deal_damage(target: Combatant, amount: int, damage_type: String, crit: bool = false, what: String = "",
		notes: PackedStringArray = PackedStringArray()) -> int:
	var dmg := CombatRules.adjust_for_type(target.sheet, amount, damage_type)
	if dmg > amount:
		notes.append("vulnerable")
	elif dmg < amount:
		notes.append("resisted" if dmg > 0 else "immune")
	var was_down := not target.is_conscious()
	target.sheet.damage(dmg, crit)
	if not what.is_empty():
		_log("%s, %d %s damage%s." % [what, dmg, damage_type, "" if notes.is_empty() else " (%s)" % ", ".join(notes)])
	_float(target, ("Critical! -%d" if crit else "-%d") % dmg, Color(1.0, 0.85, 0.3) if crit else Color(1.0, 0.4, 0.3),
			20 if crit else 18)
	Audio.play_sfx("hit")
	if dmg > 0:
		if target.asleep:
			target.asleep = false
			if target.is_conscious():
				_log("%s wakes up." % target.display_name())
		if target.turned_by != null:
			target.turned_by = null
		if not target.concentration.is_empty():
			if not target.is_conscious():
				end_concentration(target, "%s loses concentration." % target.display_name())
			else:
				var sv := save_throw(target, "con", maxi(10, dmg / 2))
				if not sv["success"]:
					end_concentration(target, "%s loses concentration (Constitution save %d)." % [
							target.display_name(), sv["total"]])
	if target.is_party():
		_after_party_hit(target, was_down)
	elif target.sheet.dead:
		_on_slain(target)
	return dmg


## A saving throw by `c`, with Bless's 1d4 if blessed.
func save_throw(c: Combatant, ability: String, dc: int) -> Dictionary:
	var extra := Rules.roll(1, 4, rng) if c.blessed_by != null else 0
	return CombatRules.saving_throw(c.sheet, ability, dc, rng, extra)


## Ends `c`'s concentration spell (Bless leaves its targets).
func end_concentration(c: Combatant, message: String = "") -> void:
	if c.concentration.is_empty():
		return
	for t in c.concentration.get("targets", []):
		if t is Combatant and t.blessed_by == c:
			t.blessed_by = null
	c.concentration = {}
	if not message.is_empty():
		_log(message)
	state_changed.emit()


## Shield, cast for a party wizard as a reaction when +5 armour class would
## turn a hit (that isn't a natural 20) into a miss. Returns true if cast.
func _shield_reaction(target: Combatant, total: int, ac: int) -> bool:
	var shield: SpellDef = Data.spells.get("shield")
	if shield == null or not target.is_party() or not target.can_act() or target.reaction_used:
		return false
	if total >= ac + shield.ac_bonus or not Spellcasting.knows(target.sheet, "shield"):
		return false
	var slot := Spellcasting.slot_for(target.sheet, shield.level)
	if slot == 0:
		return false
	Spellcasting.spend_slot(target.sheet, slot)
	target.reaction_used = true
	target.shield_ac = shield.ac_bonus
	_log("%s casts Shield: armour class %d until their next turn." % [target.display_name(), target.armor_class()])
	_float(target, "Shield!", Color(0.6, 0.8, 1.0), 16)
	Audio.play_sfx("spell_cast")
	return true


## A thrown weapon leaves the thrower's hand and lands on the target's hex.
func _land_thrown(attacker: Combatant, target: Combatant, attack: Attack) -> void:
	var st := attacker.sheet.equipped(attack.thrown_from)
	if st == null:
		return
	var item_id := st.id
	if st.qty > 1:
		st.qty -= 1
		attacker.sheet.changed.emit()
	else:
		attacker.sheet.unequip(attack.thrown_from)
	var pile := world.ground_pile(target.hex(), true)
	if pile != null:
		pile.inventory.add(ItemStack.create(item_id, 1))


func _sneak_attack_applies(attacker: Combatant, target: Combatant, attack: Attack, adv: int) -> bool:
	if attack.spell or attacker.sneak_attack_used or not CombatRules.has_feature(attacker.sheet, "sneak_attack"):
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
		var sv := save_throw(target, str(effect["save"]), int(effect.get("dc", 10)))
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
