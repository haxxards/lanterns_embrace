extends TestCase
## Phase 4 (second half) on the real main scene: spells and class features
## from the combat bar (targeting, areas, sleep, concentration, Shield as a
## reaction, the bonus-action spell rule, Guiding Bolt's mark), Turn Undead,
## scrolls, thrown weapons, getting away, saving and loading mid-fight, and
## the spells screen and resting outside a fight. Moves resolve instantly
## (combat.animate = false).

const SAVE_DIR := "user://test_saves_spells"

var main: Node
var world: World
var hud: Hud
var combat: CombatManager
var toasts: Array = []


func before_each() -> void:
	GameState.start_new_game()
	SaveManager.save_dir = SAVE_DIR
	main = load("res://scenes/main.tscn").instantiate()
	runner.add_child(main)
	world = main.get_node("World")
	hud = main.get_node("HUD")
	combat = world.combat
	combat.animate = false
	combat.rng.seed = 4242
	toasts.clear()
	Events.toast_requested.connect(_on_toast)
	await runner.get_tree().process_frame


func after_each() -> void:
	Events.toast_requested.disconnect(_on_toast)
	combat.abort()
	runner.get_tree().paused = false
	main.queue_free()
	for slot in SaveManager.slot_ids():
		SaveManager.delete_slot(slot)
	SaveManager.save_dir = "user://saves"
	await runner.get_tree().process_frame


func _on_toast(text: String) -> void:
	toasts.append(text)


func _frames(n: int = 3) -> void:
	for i in n:
		await runner.get_tree().process_frame


func _until_player_turn(max_frames: int = 60) -> bool:
	for i in max_frames:
		if combat.is_player_turn() or not combat.active:
			break
		await runner.get_tree().process_frame
	return combat.is_player_turn()


func _leader_cell() -> Vector2i:
	return Hex.axial_to_offset(world.party.members[0].hex)


func _spawn(type: String, cell: Vector2i, group: String = "test") -> Creature:
	var spawn := {"id": "%s_t%d" % [type, world.creatures.size()], "type": type,
			"hex": Hex.offset_to_axial(cell), "group": group, "wander": 0}
	var cr := Creature.new()
	cr.setup(Data.creatures[type], world.grid, spawn, world.party)
	world.entities.add_child(cr)
	world.creatures.append(cr)
	return cr


## Starts a fight with one creature, kept asleep (its turns pass) unless `awake`.
func _fight(type: String, awake: bool = false) -> Combatant:
	var cr := _spawn(type, _leader_cell() + Vector2i(5, 0))
	await _frames()
	var foe := combat.combatant_of(cr)
	if foe != null and not awake:
		foe.asleep = true
		foe.asleep_rounds = 99
	return foe


## Ends the other members' turns until it is `member_id`'s.
func _turn_of(member_id: String) -> Combatant:
	for i in 30:
		if not await _until_player_turn():
			return null
		if combat.current.sheet.id == member_id:
			return combat.current
		combat.end_turn()
		await _frames(1)
	return null


func _member(member_id: String) -> Combatant:
	for c in combat.combatants:
		if c.is_party() and c.sheet.id == member_id:
			return c
	return null


## The combat bar entry for `id` (the first: lowest slot), or {}.
func _ability(c: Combatant, id: String, kind: String = "") -> Dictionary:
	for ab in combat.abilities_for(c):
		if ab["id"] == id and (kind.is_empty() or ab["kind"] == kind):
			return ab
	return {}


## A free hex `dist` hexes from `from`, in sight of it, at least `clear` hexes from every party member.
func _hex_at(from: Vector2i, dist: int, clear: int = 0) -> Variant:
	for h in Hex.ring(from, dist):
		if not world.grid.is_walkable(h) or world.grid.is_occupied(h) or not world.line_of_sight(from, h):
			continue
		var ok := true
		for m in world.party.members:
			if Hex.distance(m.hex, h) < clear:
				ok = false
		if ok:
			return h
	return null


func _log_has(fragment: String) -> bool:
	for line in combat.log_lines:
		if line.contains(fragment):
			return true
	return false


# --- spells in a fight ------------------------------------------------------------------

func test_fire_bolt_then_magic_missile() -> void:
	var foe: Combatant = await _fight("bandit")
	foe.sheet.hp_max = 200
	foe.sheet.hp_current = 200
	var me := await _turn_of("elowen")
	check(me != null, "Elowen gets a turn")
	var fb := _ability(me, "fire_bolt")
	check(not fb.is_empty() and str(fb["error"]).is_empty() and fb["needs_target"], "Fire Bolt is on the bar")
	await combat.use_ability(fb)
	check(not combat.targeting.is_empty(), "waiting for a target")
	check(combat.preview_target(foe.hex(), foe)["ok"], "the bandit is a good target")
	check(not combat.preview_target(_member("garrick").hex(), _member("garrick"))["ok"], "Garrick isn't")
	await combat.confirm_target(foe.hex(), foe)
	check(_log_has("Fire Bolt"), "cast")
	check(me.action_used and combat.targeting.is_empty(), "the action is spent, targeting over")
	check(not str(_ability(me, "magic_missile")["error"]).is_empty(), "no second action spell this turn")
	combat.end_turn()
	await _frames(1)
	me = await _turn_of("elowen")
	var hp := foe.sheet.hp_current
	await combat.use_ability(_ability(me, "magic_missile"))
	await combat.confirm_target(foe.hex(), foe)
	check(hp - foe.sheet.hp_current >= 6, "three darts never miss: %d damage" % (hp - foe.sheet.hp_current))
	check_eq(Spellcasting.slots_left(me.sheet, 1), 1, "a 1st-level slot spent")


func test_burning_hands_cone() -> void:
	var foe: Combatant = await _fight("bandit")
	foe.sheet.hp_max = 200
	foe.sheet.hp_current = 200
	var me := await _turn_of("elowen")
	var spot: Variant = _hex_at(me.hex(), 1)
	check(spot != null, "room in front of Elowen")
	foe.actor.place_at(spot)
	await combat.use_ability(_ability(me, "burning_hands"))
	var p := combat.preview_target(spot, foe)
	check(p["ok"] and (p["hexes"] as Array).has(spot), "the cone covers the hex in front")
	check(str(p["text"]).contains(foe.display_name()), "and names who it catches: %s" % p["text"])
	await combat.confirm_target(spot, foe)
	check(foe.sheet.hp_current < 200, "the bandit is burned")
	check(_log_has("Dexterity save"), "a Dexterity save was rolled")
	check_eq(Spellcasting.slots_left(me.sheet, 1), 1, "a slot spent")


func test_sleep_and_waking() -> void:
	var foe: Combatant = await _fight("wolf", true)
	var me := await _turn_of("elowen")
	check(me != null, "Elowen's turn")
	var far: Variant = _hex_at(me.hex(), 12, 6)
	check(far != null, "a spot well away from the party")
	foe.actor.place_at(far)
	foe.sheet.hp_current = 1
	await combat.use_ability(_ability(me, "sleep"))
	await combat.confirm_target(foe.hex(), null)
	check(foe.asleep, "the wolf falls asleep")
	for c in combat.combatants:
		if c.is_party():
			check(not c.asleep, "%s was outside the circle" % c.display_name())
	foe.sheet.hp_current = 5
	combat.deal_damage(foe, 1, "fire")
	check(not foe.asleep, "damage wakes it")


func test_shield_turns_a_hit_into_a_miss() -> void:
	var foe: Combatant = await _fight("bandit")
	check(await _until_player_turn(), "the fight is on")
	var elowen := _member("elowen")
	var attack := foe.melee_attack()
	var shielded := false
	for i in 60:
		elowen.sheet.heal(99)
		elowen.reaction_used = false
		elowen.shield_ac = 0
		elowen.sheet.slots_used.clear()
		combat.rng.seed = 1000 + i
		await combat.attack_with(foe, elowen, attack, false, false)
		if elowen.shield_ac > 0:
			shielded = true
			break
	check(shielded, "Shield was cast when it would turn a hit into a miss")
	check(elowen.reaction_used and Spellcasting.slots_left(elowen.sheet, 1) == 1, "with the reaction and a slot")
	check(_log_has("casts Shield"), "and logged")


func test_bless_needs_concentration() -> void:
	await _fight("bandit")
	var me := await _turn_of("odran")
	var ab := _ability(me, "bless")
	check(not ab.is_empty() and not ab["needs_target"], "Bless picks its targets itself")
	await combat.use_ability(ab)
	var blessed := 0
	for c in combat.combatants:
		if c.blessed_by == me:
			blessed += 1
	check(blessed >= 1 and blessed <= 3, "up to three allies blessed (%d)" % blessed)
	check_eq(str(me.concentration.get("spell", "")), "bless", "Odran concentrates on it")
	combat.end_concentration(me)
	for c in combat.combatants:
		check(c.blessed_by == null, "%s's blessing ends with the concentration" % c.display_name())


func test_bonus_action_spell_then_only_cantrips() -> void:
	await _fight("bandit")
	var me := await _turn_of("odran")
	var garrick := _member("garrick")
	garrick.sheet.damage(4)
	var hp := garrick.sheet.hp_current
	await combat.use_ability(_ability(me, "healing_word"))
	await combat.confirm_target(garrick.hex(), garrick)
	check(garrick.sheet.hp_current > hp, "Healing Word heals Garrick")
	check(me.bonus_used and not me.action_used, "as a bonus action")
	check(str(_ability(me, "cure_wounds")["error"]).contains("only a cantrip"), "then no levelled spell")
	check(str(_ability(me, "sacred_flame")["error"]).is_empty(), "but a cantrip is fine")


func test_guiding_bolt_marks_its_target() -> void:
	var foe: Combatant = await _fight("bandit")
	foe.sheet.hp_max = 200
	foe.sheet.hp_current = 200
	var me := await _turn_of("odran")
	await combat.use_ability(_ability(me, "guiding_bolt"))
	await combat.confirm_target(foe.hex(), foe)
	check(_log_has("Guiding Bolt"), "cast")
	check(combat.last_hit == (foe.marked_by == me), "a hit marks the target for the next attack")


func test_scroll_in_a_fight_needs_no_slot() -> void:
	GameState.member("elowen").inventory.add_item("scroll_of_magic_missile", 1)
	GameState.member("garrick").inventory.add_item("scroll_of_magic_missile", 1)
	var foe: Combatant = await _fight("bandit")
	foe.sheet.hp_max = 200
	foe.sheet.hp_current = 200
	var me := await _turn_of("elowen")
	var ab := _ability(me, "magic_missile", "scroll")
	check(not ab.is_empty() and str(ab["error"]).is_empty(), "the scroll is on Elowen's bar")
	check(not str(_ability(_member("garrick"), "magic_missile", "scroll")["error"]).is_empty(),
			"Garrick can't read it")
	await combat.use_ability(ab)
	await combat.confirm_target(foe.hex(), foe)
	check(foe.sheet.hp_current < 200, "the darts strike")
	check(not me.sheet.inventory.has("scroll_of_magic_missile"), "the scroll is used up")
	check_eq(Spellcasting.slots_left(me.sheet, 1), 2, "no slot spent")


# --- class features ----------------------------------------------------------------------

func test_fighter_and_rogue_features() -> void:
	GameState.member("garrick").add_xp(300)
	GameState.member("wren").add_xp(300)
	await _fight("bandit")
	var g := await _turn_of("garrick")
	g.sheet.damage(5)
	var hp := g.sheet.hp_current
	var sw := _ability(g, "second_wind")
	check(str(sw.get("error", "?")).is_empty(), "Second Wind is ready")
	await combat.use_ability(sw)
	check(g.bonus_used and g.sheet.hp_current > hp, "Second Wind heals, as a bonus action")
	check(not str(_ability(g, "action_surge")["error"]).is_empty(), "Action Surge waits until the action is used")
	g.action_used = true
	await combat.use_ability(_ability(g, "action_surge"))
	check(not g.action_used, "Action Surge: another action")
	check(not str(_ability(g, "action_surge")["error"]).is_empty(), "once per rest")
	combat.end_turn()
	await _frames(1)
	var w := await _turn_of("wren")
	var before := w.movement_left
	await combat.use_ability(_ability(w, "cunning_dash"))
	check(is_equal_approx(w.movement_left, before + w.speed_ft()) and w.bonus_used, "Cunning Action: Dash as a bonus action")
	check(not str(_ability(w, "cunning_disengage")["error"]).is_empty(), "one bonus action a turn")


func test_turn_undead_makes_skeletons_flee() -> void:
	GameState.member("odran").add_xp(300)
	var foe: Combatant = await _fight("skeleton", true)
	foe.sheet.abilities["wis"] = -30  # it can't make the save
	var me := await _turn_of("odran")
	check(me != null, "Odran's turn")
	var near: Variant = _hex_at(me.hex(), 4)
	foe.actor.place_at(near)
	var ab := _ability(me, "turn_undead")
	check(str(ab.get("error", "?")).is_empty(), "Turn Undead is ready: %s" % ab.get("error", "missing"))
	await combat.use_ability(ab)
	check(foe.turned_by == me, "the skeleton is turned")
	check_eq(Features.uses_left(me.sheet, "preserve_life"), 0, "Channel Divinity is spent")
	var dist := Hex.distance(me.hex(), foe.hex())
	combat.end_turn()
	await _frames(1)
	await _turn_of("odran")
	check(Hex.distance(me.hex(), foe.hex()) > dist, "it fled on its turn")


# --- the rest of combat ---------------------------------------------------------------------

func test_a_thrown_dagger_lands_by_the_target() -> void:
	var foe: Combatant = await _fight("bandit")
	foe.sheet.hp_max = 200
	foe.sheet.hp_current = 200
	var w := await _turn_of("wren")
	var spot: Variant = _hex_at(w.hex(), 3)
	check(spot != null, "a spot three hexes away")
	foe.actor.place_at(spot)
	w.movement_left = 0  # no stepping up to stab
	await combat.player_attack(foe)
	check(_log_has("thrown"), "Wren throws her dagger")
	check(w.sheet.equipped("off_hand") == null, "it left her hand")
	var pile := world.ground_pile(foe.hex())
	check(pile != null and pile.inventory.has("dagger"), "and lies at the bandit's feet")


func test_getting_away_ends_the_fight() -> void:
	var foe: Combatant = await _fight("wolf")
	check(await _until_player_turn(), "the fight is on")
	var far: Variant = _hex_at(world.party.members[0].hex, 16, 12)
	check(far != null, "somewhere far off")
	foe.actor.place_at(far)
	for i in 16:
		if not combat.active:
			break
		if combat.is_player_turn():
			combat.end_turn()
		await _frames(1)
	check(not combat.active, "the fight is over")
	check(_log_has("got away"), "the party got away")


func test_save_and_load_in_the_middle_of_a_fight() -> void:
	var wolf: Creature = world.creatures[0]
	wolf.place_at(Hex.offset_to_axial(_leader_cell() + Vector2i(5, 0)))
	await _frames()
	check(combat.active, "a wolf from the map starts a fight")
	var foe := combat.combatant_of(wolf)
	foe.asleep = true
	foe.asleep_rounds = 99
	check(await _until_player_turn(), "a party turn")
	var me := combat.current
	var key := me.key
	var step: Variant = _hex_at(me.hex(), 1)
	await combat.player_move(step)
	var left := me.movement_left
	foe.sheet.hp_current = 5
	var count := combat.combatants.size()
	var round_no := combat.round_number
	await hud.quicksave()
	check_eq(hud._toast_label.text, "Quicksaved.", "saving is allowed on a party turn")
	check(SaveManager.read_slot(SaveManager.QUICKSAVE).has("combat"), "the fight is in the save")
	combat.abort()
	check(not hud._combat_hud.order_panel.visible, "stopping a fight hides the combat bar")
	me.sheet.damage(3)
	check(SaveManager.load_game(SaveManager.QUICKSAVE), "loads")
	await _frames(4)
	check(combat.active, "the fight goes on after loading")
	check(hud._combat_hud.order_panel.visible, "with the combat bar back")
	check_eq(combat.combatants.size(), count, "with everyone")
	check(combat.current != null and combat.current.key == key, "on the same member's turn")
	check(combat.current != null and is_equal_approx(combat.current.movement_left, left), "with the movement left")
	check(combat.current != null and combat.current.hex() == step, "where they stood")
	check_eq(combat.round_number, round_no, "in the same round")
	var foe2: Combatant = null
	for c in combat.combatants:
		if not c.is_party():
			foe2 = c
	check(foe2 != null and foe2.sheet.hp_current == 5 and foe2.asleep, "the wolf as it was: hurt and asleep")
	check(await _until_player_turn(), "and it's the player's move")
	combat.end_turn()
	await _frames(2)
	check(combat.active and combat.current != null and combat.current.key != key, "the turn passes on as usual")
	combat.rng.seed = 7
	await hud.quicksave()
	check(hud._toast_label.text == "Quicksaved." or not combat.is_player_turn(), "saving still works")


func test_no_saving_during_an_enemy_turn_or_targeting() -> void:
	await _fight("bandit")
	var me := await _turn_of("elowen")
	await combat.use_ability(_ability(me, "fire_bolt"))
	await hud.quicksave()
	check(hud._toast_label.text.contains("between moves"), "not while choosing a target")
	check(not SaveManager.has_save(SaveManager.QUICKSAVE), "nothing saved")


# --- outside a fight ------------------------------------------------------------------

func test_spells_screen_casts_healing() -> void:
	var garrick := GameState.member("garrick")
	var odran := GameState.member("odran")
	garrick.damage(6)
	var hp := garrick.hp_current
	hud.open_spells()
	var screen: SpellsScreen = hud._spells
	check(screen.visible and runner.get_tree().paused, "the spells screen opens and pauses the game")
	screen.show_sheet(odran)
	var cure: SpellDef = Data.spells["cure_wounds"]
	screen._begin_cast(cure, 1, "")
	check(screen._target_bar.visible, "it asks whom to heal")
	screen._finish_cast(cure, 1, "", garrick)
	check(garrick.hp_current > hp, "Cure Wounds healed Garrick")
	check_eq(Spellcasting.slots_left(odran, 1), 1, "with a slot")
	check(screen._result.text.contains("regains"), "the result is shown: %s" % screen._result.text)
	check(SpellsScreen.slot_pips(odran).contains("●○"), "slot pips: %s" % SpellsScreen.slot_pips(odran))
	screen.close()
	check(not runner.get_tree().paused, "closing unpauses")


func test_resting() -> void:
	var garrick := GameState.member("garrick")
	garrick.damage(6)
	hud.open_rest()
	var dialog: RestDialog = hud._rest
	check(dialog.visible, "the rest dialog opens")
	check(dialog._long_b.disabled and dialog._long_b.tooltip_text.contains("roof"), "no long rest outdoors")
	check(not dialog._short_b.disabled, "a short rest is fine")
	dialog._rest("short")
	check_eq(garrick.hit_dice_used, 1, "Garrick spent a hit die")
	dialog.close()
	var near: Variant = _hex_at(world.party.members[0].hex, 9, 8)
	check(near != null, "a spot just beyond a wolf's notice")
	_spawn("wolf", Hex.axial_to_offset(near))
	await _frames()
	check(not combat.active, "the wolf hasn't noticed the party")
	check(Rest.error(world, "short").contains("enemies"), "but there's no resting with it nearby")
	Effects.apply([{"long_rest": true}], garrick)
	check_eq(garrick.hp_current, garrick.hp_max, "a room at the inn is a long rest")
	check_eq(garrick.hit_dice_used, 0, "hit dice back")


func test_reading_a_scroll_from_the_inventory() -> void:
	var odran := GameState.member("odran")
	odran.damage(5)
	odran.inventory.add_item("scroll_of_cure_wounds", 1)
	var slot := -1
	for i in odran.inventory.capacity():
		var st := odran.inventory.get_at(i)
		if st != null and st.id == "scroll_of_cure_wounds":
			slot = i
	var msg := InventoryOps.use(InventoryOps.backpack(odran, slot), odran)
	check(msg.contains("reads a scroll"), "Odran reads it: %s" % msg)
	check(not odran.inventory.has("scroll_of_cure_wounds"), "used up")
	var garrick := GameState.member("garrick")
	garrick.inventory.add_item("scroll_of_cure_wounds", 1)
	garrick.damage(2)
	for i in garrick.inventory.capacity():
		var st := garrick.inventory.get_at(i)
		if st != null and st.id == "scroll_of_cure_wounds":
			slot = i
	msg = InventoryOps.use(InventoryOps.backpack(garrick, slot), garrick)
	check(msg.contains("fighter spell"), "Garrick can't: %s" % msg)


# --- how it looks (CombatFx) -------------------------------------------------------------

func test_effects_play_and_clean_up() -> void:
	var foe: Combatant = await _fight("bandit")
	foe.sheet.hp_max = 200
	foe.sheet.hp_current = 200
	var me := await _turn_of("elowen")
	combat.animate = true
	var garrick := _member("garrick")
	foe.actor.place_at(_hex_at(garrick.hex(), 1))
	var hp := foe.sheet.hp_current
	foe.sheet.armor_class = 0
	var done := [false]
	var swing := func() -> void:
		await combat.attack_with(garrick, foe, garrick.attacks()[0], false, false)
		done[0] = true
	swing.call()
	check(foe.sheet.hp_current == hp, "the damage waits for the blow to land")
	var seen := false
	for i in 240:
		seen = seen or world.fx.get_child_count() > 0
		if done[0]:
			break
		await _frames(1)
	check(seen, "the swing was on screen (after the wind-up)")
	check(done[0], "the attack finished")
	check(foe.sheet.hp_current < hp or not combat.last_hit, "and then hit")
	foe.actor.place_at(_hex_at(me.hex(), 5))
	hp = foe.sheet.hp_current
	await CombatSpells.cast(combat, me, Data.spells["magic_missile"], 1, foe.hex(), foe)
	check(hp - foe.sheet.hp_current >= 6, "every dart landed (%d damage)" % (hp - foe.sheet.hp_current))
	await runner.get_tree().create_timer(1.0).timeout
	check_eq(world.fx.get_child_count(), 0, "the effects free themselves")


func test_loading_mid_swing_stops_the_old_blow() -> void:
	var foe: Combatant = await _fight("bandit")
	check(await _until_player_turn(), "a party turn")
	combat.animate = true
	var garrick := _member("garrick")
	foe.actor.place_at(_hex_at(garrick.hex(), 1))
	var hp := foe.sheet.hp_current
	var result := [null]
	var swing := func() -> void:
		result[0] = await combat.attack_with(garrick, foe, garrick.attacks()[0], false, false)
	swing.call()
	combat.abort()  # as loading a game does
	await runner.get_tree().create_timer(0.8).timeout
	check_eq(result[0], false, "the interrupted attack gives up")
	check_eq(foe.sheet.hp_current, hp, "and does no damage")


func test_anchors_follow_the_facing() -> void:
	var m: PartyMember = world.party.members[0]
	var anim: Dictionary = JsonUtil.load_json(m.sheet.raw["art"]["animation"])
	var rows: Array = anim["directions"]
	m.face_towards(m.position + Vector2(100, 0))
	var east: Array = anim["anchors"]["weapon"][rows.find("e")]
	var off := m.anchor("weapon") - m.global_position
	check(off.is_equal_approx(Vector2(float(east[0]), float(east[1]))), "facing east: the sheet's east row %s" % off)
	m.face_towards(m.position + Vector2(-100, 0))
	off = m.anchor("weapon") - m.global_position
	check(off.is_equal_approx(Vector2(-float(east[0]), float(east[1]))), "facing west: mirrored %s" % off)

