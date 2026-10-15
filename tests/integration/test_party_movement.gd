extends TestCase
## Runs the real main scene and drives the party through the public API and
## simulated mouse input. Movement is stepped manually for determinism.

const DT := 1.0 / 30.0

var main: Node
var world: World
var messages: Array = []
var toasts: Array = []


func before_each() -> void:
	GameState.start_new_game()
	main = load("res://scenes/main.tscn").instantiate()
	runner.add_child(main)
	world = main.get_node("World")
	messages.clear()
	toasts.clear()
	Events.message_requested.connect(_on_message)
	Events.toast_requested.connect(_on_toast)
	await runner.get_tree().process_frame


func after_each() -> void:
	Events.message_requested.disconnect(_on_message)
	Events.toast_requested.disconnect(_on_toast)
	runner.get_tree().paused = false
	main.queue_free()
	await runner.get_tree().process_frame


func _on_message(title: String, text: String) -> void:
	messages.append([title, text])


func _on_toast(text: String) -> void:
	toasts.append(text)


func _ax(col: int, row: int) -> Vector2i:
	return Hex.offset_to_axial(Vector2i(col, row))


## Nearest hex to [col, row] that is walkable with walkable neighbours, so tests
## don't depend on exactly where the map's trees and rocks are.
func _open(col: int, row: int) -> Vector2i:
	for h in Hex.spiral(_ax(col, row), 6):
		var ok := world.grid.is_walkable(h)
		for n in Hex.neighbors(h):
			ok = ok and world.grid.is_walkable(n)
		if ok:
			return h
	return _ax(col, row)


## Steps every member until nobody is walking. Returns false on timeout.
func _walk_until_idle(max_seconds: float = 40.0) -> bool:
	var t := 0.0
	while t < max_seconds:
		var moving := false
		for m in world.party.members:
			m._process(DT)
			moving = moving or m.is_moving()
		if not moving:
			return true
		t += DT
	return false


func _distinct_hexes() -> bool:
	var seen := {}
	for m in world.party.members:
		if seen.has(m.hex):
			return false
		seen[m.hex] = true
	return true


func _click_screen(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		runner.get_viewport().push_input(ev, true)


func test_party_spawns_selected_on_distinct_hexes() -> void:
	var party := world.party
	check_eq(party.members.size(), GameState.party.size(), "one token per party member")
	check_eq(party.selected.size(), party.members.size(), "whole party selected at start")
	check(_distinct_hexes(), "no two members share a hex")
	for m in party.members:
		check(world.grid.is_walkable(m.hex), "%s stands on walkable ground" % m.sheet.display_name)


func test_group_move_fans_out_around_target() -> void:
	var target := _open(14, 36)
	check(world.grid.is_walkable(target), "test target is walkable")
	check(world.party.move_selected_to(target), "order accepted")
	check(_walk_until_idle(), "party arrives")
	check_eq(world.party.leader().hex, target, "leader stands on the target")
	check(_distinct_hexes(), "members end on distinct hexes")
	for m in world.party.members:
		check(Hex.distance(m.hex, target) <= PartyController.FORMATION_RADIUS, "%s near target" % m.sheet.display_name)


func test_clicking_water_moves_to_nearest_ground() -> void:
	var water := Vector2i(-1, -1)
	for i in world.grid.cell_count():
		var h := world.grid.hex_at_index(i)
		var t := world.grid.get_terrain(h)
		if t and t.id == "water" and Hex.distance(h, world.party.leader().hex) < 30:
			water = h
			break
	check(water != Vector2i(-1, -1), "found a water hex")
	world.party.move_selected_to(water)
	check(_walk_until_idle(), "party arrives")
	check(Hex.distance(world.party.leader().hex, water) <= 2, "leader stops at the bank")


func test_unreachable_order_shows_toast() -> void:
	var before := world.party.leader().hex
	check(not world.party.move_selected_to(Vector2i(500, 500)), "order rejected")
	check(not toasts.is_empty(), "player told it can't be reached")
	check_eq(world.party.leader().hex, before, "nobody moved")


func test_single_member_moves_alone() -> void:
	var party := world.party
	party.select_only(party.members[1])
	var others := {}
	for m in party.members:
		others[m] = m.hex
	var target := _open(10, 34)
	party.move_selected_to(target)
	check(_walk_until_idle(), "arrives")
	check_eq(party.members[1].hex, target, "selected member moved")
	for m in party.members:
		if m != party.members[1]:
			check_eq(m.hex, others[m], "%s stayed put" % m.sheet.display_name)


func test_redirect_mid_walk_keeps_path_contiguous() -> void:
	var leader := world.party.leader()
	var visited: Array[Vector2i] = [leader.hex]
	leader.hex_entered.connect(func(_m: PartyMember, h: Vector2i) -> void: visited.append(h))
	world.party.move_selected_to(_open(20, 24))
	for i in 20:
		for m in world.party.members:
			m._process(DT)
	var second := _open(6, 36)
	world.party.move_selected_to(second)
	check(_walk_until_idle(), "arrives after redirect")
	check_eq(leader.hex, second, "leader reached the new target")
	for i in range(1, visited.size()):
		check_eq(Hex.distance(visited[i - 1], visited[i]), 1, "step %d is to a neighbour" % i)


func test_sign_interaction_shows_message() -> void:
	var sign: Prop = null
	for p in world.props:
		if p.is_interactable():
			sign = p
			break
	check(sign != null, "map has a sign")
	world.party.select_only(world.party.members[0])
	check(world.party.interact_with(sign), "interaction order accepted")
	check(_walk_until_idle(), "walks to the sign")
	check(sign.is_adjacent_to(world.party.members[0].hex), "stands next to the sign")
	check_eq(messages.size(), 1, "sign text shown once")


func test_pause_freezes_party_but_not_input() -> void:
	world.set_paused(true)
	var m := world.party.members[0]
	check(not m.can_process(), "party tokens pause")
	check(world.can_process(), "world input keeps running")
	check(world.camera.can_process(), "camera keeps running")
	world.set_paused(false)
	check(m.can_process(), "party resumes")


func test_box_select_and_clear() -> void:
	var party := world.party
	party.clear_selection()
	check(party.selected.is_empty(), "cleared")
	var a := party.members[0].global_position
	party.select_in_rect(Rect2(a - Vector2(4, 4), Vector2(8, 8)), false)
	check_eq(party.selected.size(), 1, "box around one member selects one")
	party.select_in_rect(Rect2(world.grid.world_bounds()), false)
	check_eq(party.selected.size(), party.members.size(), "box around everyone selects all")


func test_mouse_clicks_route_correctly() -> void:
	await runner.get_tree().process_frame
	var vp_size := runner.get_viewport().get_visible_rect().size
	var leader := world.party.leader()
	var start := leader.hex
	# Empty sidebar space must not reach the map.
	_click_screen(Vector2(vp_size.x - 20.0, vp_size.y - 140.0))
	check(not leader.is_moving(), "sidebar click does not move the party")
	check_eq(world.party.selected.size(), world.party.members.size(), "sidebar click keeps selection")
	# A click on open ground does.
	var ground := world.grid.hex_to_world(_open(12, 35))
	var screen := runner.get_viewport().get_canvas_transform() * ground
	_click_screen(screen)
	check(leader.is_moving() or leader.hex != start, "map click moves the party")


func test_walks_end_on_hex_centres_and_stay_on_ground() -> void:
	var leader := world.party.leader()
	var entered: Array[Vector2i] = []
	leader.hex_entered.connect(func(_m: PartyMember, h: Vector2i) -> void: entered.append(h))
	world.party.move_selected_to(_open(45, 31))  # across the bridge
	check(_walk_until_idle(), "party crosses the river")
	for h in entered:
		check(world.grid.is_walkable(h), "walked over walkable ground at %s" % h)
	for m in world.party.members:
		check(m.position.is_equal_approx(world.grid.hex_to_world(m.hex)), "%s stands on a hex centre" % m.sheet.display_name)
	check(_distinct_hexes(), "members end on distinct hexes")


func test_smoothed_walk_is_straighter_than_hex_steps() -> void:
	var party := world.party
	party.select_only(party.members[0])
	var leader := party.leader()
	var target := _open(5, 22)  # due north: hex steps would zig-zag
	var hex_path := world.grid.find_path(leader.hex, target)
	check(hex_path.size() >= 5, "target is a few hexes away")
	var hex_len := 0.0
	var prev := world.grid.hex_to_world(leader.hex)
	for h in hex_path:
		hex_len += prev.distance_to(world.grid.hex_to_world(h))
		prev = world.grid.hex_to_world(h)
	party.move_selected_to(target)
	var walked := 0.0
	var last := leader.position
	for i in 900:
		leader._process(DT)
		walked += last.distance_to(leader.position)
		last = leader.position
		if not leader.is_moving():
			break
	check_eq(leader.hex, target, "arrived")
	check(walked < hex_len - 5.0, "smoothed walk (%.0f px) shorter than hex steps (%.0f px)" % [walked, hex_len])


func test_members_animate_and_face_their_walk() -> void:
	var m := world.party.members[0]
	check(m.is_animated(), "party member uses its sprite sheet")
	world.party.select_only(m)
	world.party.move_selected_to(_open(16, 30))  # east along the road
	var frames := {}
	for i in 30:
		m._process(DT)
		frames[m._sprite.frame] = true
	check([7, 0, 1].has(m._facing), "faces east-ish while walking east (sector %d)" % m._facing)
	check(frames.size() >= 4, "walk cycle advances (%d distinct frames)" % frames.size())
	check(_walk_until_idle(), "arrives")
	check_eq(m._sprite.frame % m._sprite.hframes, 0, "idle frame on arrival")
	world.party.move_selected_to(_open(4, 30))  # back west
	for i in 20:
		m._process(DT)
	check([3, 4, 5].has(m._facing), "faces west-ish walking west (sector %d)" % m._facing)
	check(m._sprite.flip_h, "west facings mirror the east-facing rows")
