extends TestCase
## Phase 4 (first half) on the real main scene: creatures noticing the party,
## initiative and turns, moving and attacking, opportunity attacks, the enemy
## AI, death saves, victory (XP, loot, the slain stay slain), defeat, potions
## in a fight, and no saving mid-fight. Moves resolve instantly
## (combat.animate = false) so the tests are quick and repeatable.

var main: Node
var world: World
var hud: Hud
var combat: CombatManager
var toasts: Array = []


func before_each() -> void:
	GameState.start_new_game()
	main = load("res://scenes/main.tscn").instantiate()
	runner.add_child(main)
	world = main.get_node("World")
	hud = main.get_node("HUD")
	combat = world.combat
	combat.animate = false
	combat.rng.seed = 12345
	toasts.clear()
	Events.toast_requested.connect(_on_toast)
	await runner.get_tree().process_frame


func after_each() -> void:
	Events.toast_requested.disconnect(_on_toast)
	combat.abort()
	runner.get_tree().paused = false
	main.queue_free()
	await runner.get_tree().process_frame


func _on_toast(text: String) -> void:
	toasts.append(text)


func _frames(n: int = 3) -> void:
	for i in n:
		await runner.get_tree().process_frame


## Waits (a few frames at most) until it is a party member's turn.
func _until_player_turn(max_frames: int = 60) -> bool:
	for i in max_frames:
		if combat.is_player_turn() or not combat.active:
			break
		await runner.get_tree().process_frame
	return combat.is_player_turn()


## Places a creature at an offset [col, row] near the party.
func _spawn(type: String, cell: Vector2i, group: String = "test") -> Creature:
	var spawn := {"id": "%s_t%d" % [type, world.creatures.size()], "type": type,
			"hex": Hex.offset_to_axial(cell), "group": group, "wander": 0}
	var cr := Creature.new()
	cr.setup(Data.creatures[type], world.grid, spawn, world.party)
	world.entities.add_child(cr)
	world.creatures.append(cr)
	return cr


## A free hex next to `h` (for setting up who stands where).
func _free_next_to(h: Vector2i) -> Vector2i:
	for n in Hex.neighbors(h):
		if world.grid.is_walkable(n):
			return n
	return h


func _leader_cell() -> Vector2i:
	return Hex.axial_to_offset(world.party.members[0].hex)


func _log_has(fragment: String) -> bool:
	for line in combat.log_lines:
		if line.contains(fragment):
			return true
	return false


func test_a_creature_in_sight_starts_a_fight() -> void:
	var wolf := _spawn("wolf", _leader_cell() + Vector2i(4, 0))
	await _frames()
	check(combat.active and GameState.in_combat(), "the wolf notices the party")
	check_eq(combat.combatants.size(), 5, "four party members and a wolf")
	for i in range(1, combat.combatants.size()):
		check(combat.combatants[i - 1].initiative >= combat.combatants[i].initiative, "initiative order")
	check(wolf.in_combat, "the wolf is fighting")
	check(hud._combat_hud.order_panel.visible, "initiative strip shown")
	check(await _until_player_turn(), "a party member gets a turn")
	await hud.quicksave()
	check(hud._toast_label.text == "You can't save during a fight.", "no saving mid-fight")
	for m in world.party.members:
		check(world.grid.is_occupied(m.hex), "%s blocks their hex in a fight" % m.sheet.display_name)


func test_move_within_movement_and_attack() -> void:
	var bandit := _spawn("bandit", _leader_cell() + Vector2i(5, 0))
	await _frames()
	check(await _until_player_turn(), "a party turn")
	var me := combat.current
	var foe := combat.combatant_of(bandit)
	check_eq(me.movement_left, float(me.speed_ft()), "full movement at the start of the turn")
	# Too far: nothing happens.
	var far := me.hex() + Vector2i(0, 30)
	await combat.player_move(far)
	check_eq(me.movement_left, float(me.speed_ft()), "a move out of range is refused")
	check(not toasts.is_empty() and str(toasts.back()).begins_with("Too far"), "and says why")
	# A two-hex move costs 10 ft.
	var reach := combat.reachable_for(me)
	var dest: Variant = null
	for h in reach:
		if reach[h] == 2.0:
			dest = h
			break
	check(dest != null, "somewhere two hexes away")
	await combat.player_move(dest)
	check_eq(me.hex(), dest, "moved")
	check_eq(me.movement_left, float(me.speed_ft()) - 10.0, "10 ft used")
	# Put the bandit next to us and strike it.
	foe.sheet.armor_class = 1
	bandit.place_at(_free_next_to(me.hex()))
	var hp := foe.sheet.hp_current
	await combat.player_attack(foe)
	check(me.action_used, "the attack used the action")
	check(_log_has(me.display_name() + " hits") or _log_has(me.display_name() + " attacks"), "logged")
	check(foe.sheet.hp_current < hp or foe.sheet.dead or _log_has("miss"), "the bandit is hurt (or it missed on a 1)")
	await combat.player_attack(foe)
	check(foe.sheet.dead or me.off_hand_attack() == null or me.bonus_used or not me.attacked_light,
			"no second attack without an off-hand weapon")


func test_dash_dodge_and_disengage_use_the_action() -> void:
	_spawn("bandit", _leader_cell() + Vector2i(5, 0))
	await _frames()
	check(await _until_player_turn(), "a party turn")
	var me := combat.current
	combat.dash()
	check(me.action_used and me.movement_left == float(me.speed_ft() * 2), "Dash doubles the movement")
	combat.dodge()
	check(not me.dodging, "no Dodge after the action is spent")
	combat.end_turn()
	await _frames()
	check(me != combat.current or not combat.is_player_turn(), "End turn passes the turn on")


func test_leaving_reach_provokes_an_opportunity_attack() -> void:
	var a := _spawn("bandit", _leader_cell() + Vector2i(5, 0))
	await _frames()
	check(await _until_player_turn(), "a party turn")
	var me := combat.current
	var foe := combat.combatant_of(a)
	foe.reaction_used = false
	a.place_at(_free_next_to(me.hex()))
	var away: Variant = null
	var reach := combat.reachable_for(me)
	for h in reach:
		if Hex.distance(h, a.hex) >= 2 and reach[h] <= 2.0:
			away = h
			break
	check(away != null, "a hex out of the bandit's reach")
	await combat.player_move(away)
	check(foe.reaction_used, "the bandit used its reaction")
	check(_log_has("opportunity attack"), "logged as an opportunity attack")


func test_disengage_avoids_opportunity_attacks() -> void:
	var a := _spawn("bandit", _leader_cell() + Vector2i(5, 0))
	await _frames()
	check(await _until_player_turn(), "a party turn")
	var me := combat.current
	var foe := combat.combatant_of(a)
	foe.reaction_used = false
	a.place_at(_free_next_to(me.hex()))
	combat.disengage()
	check(me.disengaged and me.action_used, "disengaged (action used)")
	var reach := combat.reachable_for(me)
	for h in reach:
		if Hex.distance(h, a.hex) >= 2 and reach[h] <= 2.0:
			await combat.player_move(h)
			break
	check(not foe.reaction_used, "no opportunity attack")


func test_wolf_ai_closes_in_and_bites() -> void:
	var wolf := _spawn("wolf", _leader_cell() + Vector2i(5, 1))
	await _frames()
	var w := combat.combatant_of(wolf)
	check(w != null, "the wolf is fighting")
	w.begin_turn()
	await CombatAI.take_turn(combat, w)
	var next_to := false
	for m in world.party.members:
		if Hex.distance(m.hex, wolf.hex) <= 1:
			next_to = true
	check(next_to, "the wolf ran up to someone")
	check(w.action_used, "and bit")
	check(_log_has("Wolf hits") or _log_has("Wolf attacks"), "logged")


func test_archer_ai_shoots_from_range() -> void:
	var archer := _spawn("bandit_archer", _leader_cell() + Vector2i(7, 0))
	await _frames()
	var c := combat.combatant_of(archer)
	check(c != null, "the archer is fighting")
	c.begin_turn()
	await CombatAI.take_turn(combat, c)
	check(c.action_used, "it shot")
	check(_log_has("with Shortbow"), "with its bow")
	var adjacent := false
	for m in world.party.members:
		if Hex.distance(m.hex, archer.hex) <= 1:
			adjacent = true
	check(not adjacent, "from a distance")


func test_victory_shares_xp_drops_loot_and_the_slain_stay_slain() -> void:
	var bandit := _spawn("bandit", _leader_cell() + Vector2i(5, 0), "test_bandits")
	var spawn_id := bandit.spawn_id
	await _frames()
	var xp_before: Array[int] = []
	for s in GameState.party:
		xp_before.append(s.xp)
	var foe := combat.combatant_of(bandit)
	foe.sheet.armor_class = 1
	foe.sheet.hp_current = 1
	var spot := Vector2i.ZERO
	for i in 12:
		if not combat.active:
			break
		if not await _until_player_turn():
			break
		bandit.place_at(_free_next_to(combat.current.hex()))
		spot = bandit.hex
		await combat.player_attack(foe)
		if combat.active:
			combat.end_turn()
		await _frames(2)
	check(not combat.active, "the fight is over")
	check(foe.sheet.dead, "the bandit is dead")
	check(GameState.is_defeated(world.map.id, spawn_id), "remembered as slain")
	check(bool(GameState.flags.get("defeated:test_bandits", false)), "its group is beaten")
	check(not world.creatures.has(bandit), "gone from the map")
	for i in GameState.party.size():
		check_eq(GameState.party[i].xp, xp_before[i] + 6, "%s gets a share of the XP" % GameState.party[i].display_name)
	var pile := world.ground_pile(spot)
	check(pile != null and pile.inventory.count("gold") >= 2, "the bandit dropped its coin")
	for m in world.party.members:
		check(m.smooth_paths and not world.grid.is_occupied(m.hex), "back to free walking")


func test_down_members_make_death_saves() -> void:
	_spawn("skeleton", _leader_cell() + Vector2i(5, 0))
	await _frames()
	check(await _until_player_turn(), "a party turn")
	var me := combat.current
	var other: Combatant = null
	for c in combat.combatants:
		if c.is_party() and c != me:
			other = c
	other.sheet.damage(other.sheet.hp_current)
	check(other.sheet.is_down() and not other.sheet.stable, "%s is dying" % other.display_name())
	for i in 8:
		if not combat.active:
			break
		if _log_has("death save") or _log_has("is stable") or _log_has("rallies") or _log_has("dies"):
			break
		combat.end_turn()
		await _until_player_turn()
	check(_log_has("death save") or _log_has("is stable") or _log_has("rallies") or _log_has("dies"),
			"a death saving throw was rolled")


func test_a_potion_in_a_fight_uses_the_action() -> void:
	_spawn("bandit", _leader_cell() + Vector2i(5, 0))
	await _frames()
	check(await _until_player_turn(), "a party turn")
	var me := combat.current
	me.sheet.damage(3)
	me.sheet.inventory.add_item("potion_of_healing", 2)
	var slot := -1
	for i in me.sheet.inventory.capacity():
		var st := me.sheet.inventory.get_at(i)
		if st != null and st.id == "potion_of_healing":
			slot = i
	var msg := InventoryOps.use(InventoryOps.backpack(me.sheet, slot), me.sheet)
	check(msg.contains("recovers"), "drank it: %s" % msg)
	check(me.action_used, "that was the action")
	me.sheet.damage(2)
	msg = InventoryOps.use(InventoryOps.backpack(me.sheet, slot), me.sheet)
	check(msg.contains("already used"), "no second potion this turn: %s" % msg)


func test_defeat_ends_the_fight_with_game_over() -> void:
	_spawn("wolf", _leader_cell() + Vector2i(5, 0))
	await _frames()
	check(combat.active, "fighting")
	for s in GameState.party:
		s.die()
	await _frames()
	check(not combat.active, "the fight ends")
	check(hud._game_over.visible, "game over")


func test_wolves_wait_in_the_woods() -> void:
	var wolves: Array[Creature] = []
	for cr in world.creatures:
		if cr.group == "woods_wolves":
			wolves.append(cr)
	check_eq(wolves.size(), 3, "three wolves in the north-west woods")
	check(not combat.active, "they don't notice the party at the start")
	GameState.mark_defeated(world.map.id, wolves[0].spawn_id)
	world.load_map(GameConfig.starting_map_path, "")
	var left := 0
	for cr in world.creatures:
		if cr.group == "woods_wolves":
			left += 1
	check_eq(left, 2, "a slain wolf doesn't come back")


func test_the_road_east_leads_to_the_old_temple() -> void:
	var marker: Prop = null
	for p in world.props:
		if p.def.id == "waymarker":
			marker = p
	check(marker != null and marker.is_transition(), "a waymarker at the end of the east road")
	world.load_map(GameConfig.starting_map_path, "east_road")
	check(Hex.distance(world.party.members[0].hex, marker.anchor) <= 4, "arriving by the waymarker")
	world.party.select_all()
	check(world.party.interact_with(marker), "order accepted")
	for i in 600:
		var moving := false
		for m in world.party.members:
			m._process(1.0 / 30.0)
			moving = moving or m.is_moving()
		if not moving:
			break
	await _frames(4)
	check_eq(world.map.id, "old_temple_road", "up the road into the hills")
	var groups := {}
	for cr in world.creatures:
		groups[cr.group] = int(groups.get(cr.group, 0)) + 1
	check_eq(groups.get("road_bandits", 0), 4, "four bandits at the camp")
	check_eq(groups.get("temple_dead", 0), 3, "three skeletons at the ruin")
	check(not combat.active, "nobody notices the party at the map's edge")

