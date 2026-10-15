class_name PartyController
extends Node
## Owns the party tokens on the current map: selection, move orders and
## walk-to-interact. Exploration rules: members may pass through each other
## while walking, but no two members end a move on the same hex.

## How far from the clicked hex group members may be placed.
const FORMATION_RADIUS := 4

var grid: HexGrid
var entities: Node2D
var members: Array[PartyMember] = []
## Selected members, always kept in party (portrait) order.
var selected: Array[PartyMember] = []
## A door or exit the party is gathering at; fires once everyone has stopped.
var _waiting_transition: Prop = null


## Places the party around `spawn`, or on saved hexes ({member id: hex}).
func spawn_party(sheets: Array[CharacterSheet], spawn: Vector2i, positions: Dictionary = {}) -> void:
	for m in members:
		m.queue_free()
	members.clear()
	selected.clear()
	_waiting_transition = null
	var taken := {}
	for sheet in sheets:
		var saved: Variant = positions.get(sheet.id)
		var slot: Variant = saved if saved != null and grid.is_walkable(saved) and not taken.has(saved) \
				else _nearest_free(spawn, taken, spawn)
		if slot == null:
			push_error("No free hex near spawn %s for %s" % [spawn, sheet.display_name])
			continue
		taken[slot] = true
		var m := PartyMember.new()
		m.setup(sheet, grid, slot)
		m.arrived.connect(_on_member_arrived)
		entities.add_child(m)
		members.append(m)
	select_all()


# --- selection -----------------------------------------------------------------

func leader() -> PartyMember:
	return selected[0] if not selected.is_empty() else null


func select_only(m: PartyMember) -> void:
	_set_selection([m])


func toggle(m: PartyMember) -> void:
	var s := selected.duplicate()
	if s.has(m):
		s.erase(m)
	else:
		s.append(m)
	_set_selection(s)


func select_all() -> void:
	_set_selection(members.duplicate())


func clear_selection() -> void:
	_set_selection([])


func select_index(i: int, additive: bool) -> void:
	if i < 0 or i >= members.size():
		return
	if additive:
		toggle(members[i])
	else:
		select_only(members[i])


## Box selection in world space.
func select_in_rect(rect: Rect2, additive: bool) -> void:
	var picked: Array = selected.duplicate() if additive else []
	for m in members:
		# A member counts when the box covers their feet or body centre.
		if rect.has_point(m.global_position) or rect.has_point(m.global_position + Vector2(0, -24)):
			if not picked.has(m):
				picked.append(m)
	if not picked.is_empty() or not additive:
		_set_selection(picked)


func member_at(world_pos: Vector2) -> PartyMember:
	var best: PartyMember = null
	for m in members:
		# Prefer the front-most (lowest on screen) token when sprites overlap.
		if m.pick_rect().has_point(world_pos) and (best == null or m.position.y > best.position.y):
			best = m
	return best


func _set_selection(list: Array) -> void:
	selected.clear()
	for m in members:  # keep party order
		if list.has(m):
			selected.append(m)
	for m in members:
		m.selected = selected.has(m)
	Events.selection_changed.emit(selected)


# --- orders ----------------------------------------------------------------------

## Sends the selection towards `target`. The leader takes the target (or the
## nearest free hex); the others take nearby free hexes, keeping roughly their
## current left/right arrangement. Returns false if nobody could move.
func move_selected_to(target: Vector2i) -> bool:
	if selected.is_empty():
		return false
	_waiting_transition = null
	var any_moved := _move_group(selected.duplicate(), target, _hexes_held_by_others(selected))
	if any_moved:
		Events.party_order_issued.emit()
	else:
		Events.toast_requested.emit("Can't reach that.")
	return any_moved


## Moves `group` to free hexes around `target`, nearest first. Returns true if
## anyone could move.
func _move_group(group: Array[PartyMember], target: Vector2i, taken: Dictionary) -> bool:
	var candidates := grid.walkable_near(target, FORMATION_RADIUS)
	var any_moved := false
	for m in group:
		var dest: Variant = _pick_slot(m, target, candidates, taken)
		if dest == null:
			continue
		taken[dest] = true
		m.pending_interaction = null
		m.follow_path(grid.find_path(m.hex, dest))
		any_moved = true
	return any_moved


## Walks the leader next to `prop` and triggers its interaction on arrival.
## For doors and exits the whole party gathers there first.
func interact_with(prop: Prop) -> bool:
	var actor := leader()
	if actor == null:
		return false
	_waiting_transition = null
	var taken := _hexes_held_by_others([actor])
	var best_path: Array[Vector2i] = []
	var best_hex: Variant = null
	var best_cost := INF
	for h in prop.approach_hexes(grid):
		if taken.has(h):
			continue
		if h == actor.hex:
			best_hex = h
			best_path = []
			break
		var p := grid.find_path(actor.hex, h)
		if p.is_empty():
			continue
		var cost := grid.path_cost(p)
		if cost < best_cost:
			best_cost = cost
			best_hex = h
			best_path = p
	if best_hex == null:
		Events.toast_requested.emit("Can't reach %s." % prop.display_name())
		return false
	Events.party_order_issued.emit()
	actor.follow_path(best_path)
	actor.pending_interaction = prop
	if prop.is_transition():
		var others: Array[PartyMember] = []
		for m in members:
			if m != actor:
				others.append(m)
		_move_group(others, best_hex, {best_hex: true})
	return true


func _pick_slot(m: PartyMember, target: Vector2i, candidates: Array[Vector2i],
		taken: Dictionary) -> Variant:
	var best: Variant = null
	var best_key := Vector2(INF, INF)
	for c in candidates:  # nearest rings first
		if taken.has(c):
			continue
		var key := Vector2(Hex.distance(c, target), Hex.distance(c, m.hex))
		if key.x > best_key.x:
			break
		if key < best_key and grid.is_reachable(m.hex, c):
			best_key = key
			best = c
	return best


func _hexes_held_by_others(group: Array) -> Dictionary:
	var taken := {}
	for m in members:
		if not group.has(m):
			taken[m.destination] = true
			taken[m.hex] = true
	return taken


func _nearest_free(center: Vector2i, taken: Dictionary, reachable_from: Vector2i) -> Variant:
	for h in grid.walkable_near(center, 6):
		if not taken.has(h) and grid.is_reachable(reachable_from, h):
			return h
	return null


func _on_member_arrived(m: PartyMember) -> void:
	var prop := m.pending_interaction
	m.pending_interaction = null
	if prop != null and is_instance_valid(prop) and prop.is_adjacent_to(m.hex):
		if prop.is_transition():
			_waiting_transition = prop
		else:
			prop.interact(m)
	if _waiting_transition != null and is_instance_valid(_waiting_transition) and not _anyone_moving():
		var door := _waiting_transition
		_waiting_transition = null
		door.interact(m)


func _anyone_moving() -> bool:
	for m in members:
		if m.is_moving():
			return true
	return false
