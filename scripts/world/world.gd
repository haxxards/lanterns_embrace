class_name World
extends Node2D
## One loaded map: terrain, props, party tokens, camera, and map mouse input.
##
## Mouse controls (BG-style):
##   left click ground    move the selection (group fans out around the target)
##   left click member    select it (Shift: add/remove)
##   left drag            box-select members (Shift: add)
##   left click sign      leader walks over and reads it
##   right click          clear selection

const DRAG_THRESHOLD := 8.0
const NO_HEX := Vector2i(-99999, -99999)

var map: MapData
var grid: HexGrid
var props: Array[Prop] = []
var props_by_hex: Dictionary = {}  # Vector2i -> Prop

var terrain: TerrainRenderer
var grid_lines: GridLines
var cursor: CursorOverlay
var entities: Node2D
var selection_box: SelectionBox
var camera: GameCamera
var party: PartyController

var _hover_hex: Vector2i = NO_HEX
var _hover_prop: Prop = null
var _hover_member: PartyMember = null
var _mouse_screen := Vector2(-1.0, -1.0)
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO
var _left_down: bool = false
var _dragging: bool = false


func _ready() -> void:
	# The world keeps taking input while paused; party tokens opt back into pausing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	terrain = TerrainRenderer.new()
	terrain.name = "Terrain"
	terrain.z_index = -10
	add_child(terrain)
	grid_lines = GridLines.new()
	grid_lines.name = "GridLines"
	grid_lines.z_index = -9
	grid_lines.visible = GameConfig.show_grid_default
	add_child(grid_lines)
	cursor = CursorOverlay.new()
	cursor.name = "Cursor"
	cursor.z_index = -8
	add_child(cursor)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	selection_box = SelectionBox.new()
	selection_box.name = "SelectionBox"
	selection_box.z_index = 50
	add_child(selection_box)
	camera = GameCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	party = PartyController.new()
	party.name = "Party"
	party.entities = entities
	add_child(party)
	Events.selection_changed.connect(func(_s: Array) -> void: _refresh_hover(true))


## Loads a map file and places the current GameState party on it.
func load_map(path: String) -> bool:
	_clear()
	map = Data.load_map(path)
	if map.width == 0 or map.height == 0:
		push_error("World: map %s is empty or unreadable" % path)
		return false
	grid = HexGrid.new()
	grid.setup(map.width, map.height, GameConfig.hex_radius)
	for r in map.height:
		for c in map.width:
			grid.set_terrain(Hex.offset_to_axial(Vector2i(c, r)), map.terrain[r * map.width + c])
	for placement in map.placements:
		_spawn_prop(placement)
	grid.rebuild_pathfinding()

	terrain.build(grid)
	grid_lines.build(grid)
	cursor.grid = grid
	cursor.party = party
	party.grid = grid
	RenderingServer.set_default_clear_color(map.background_color)

	party.spawn_party(GameState.party, map.party_spawn)
	camera.set_bounds(grid.world_bounds())
	camera.center_on(grid.hex_to_world(map.party_spawn), true)
	GameState.current_map_path = path
	Events.map_loaded.emit(map.id)
	return true


func _clear() -> void:
	for p in props:
		p.queue_free()
	props.clear()
	props_by_hex.clear()
	_hover_prop = null
	_hover_member = null
	_hover_hex = NO_HEX


func _spawn_prop(placement: MapData.Placement) -> void:
	var prop := Prop.new()
	prop.setup(placement, grid)
	for cell in prop.cells:
		if not grid.in_bounds(cell):
			push_warning("Prop %s footprint leaves the map at %s" % [prop.name, cell])
			continue
		if props_by_hex.has(cell) and props_by_hex[cell].def.blocks_movement and placement.def.blocks_movement:
			push_warning("Prop %s overlaps %s" % [prop.name, props_by_hex[cell].name])
		grid.add_prop_cell(cell, placement.def)
		props_by_hex[cell] = prop
	entities.add_child(prop)
	props.append(prop)


# --- input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if grid == null:
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif event.is_action_pressed("toggle_pause"):
		set_paused(not get_tree().paused)
	elif event.is_action_pressed("toggle_grid"):
		grid_lines.visible = not grid_lines.visible
	elif event.is_action_pressed("select_all"):
		party.select_all()
	elif event.is_action_pressed("cam_center_selection"):
		focus_selection()
	else:
		for i in 9:
			if event.is_action_pressed("select_member_%d" % (i + 1)):
				party.select_index(i, Input.is_key_pressed(KEY_SHIFT))
				break


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	_mouse_screen = mb.position
	var world_pos := screen_to_world(mb.position)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_left_down = true
			_dragging = false
			_press_screen = mb.position
			_press_world = world_pos
		elif _left_down:
			_left_down = false
			if _dragging:
				_dragging = false
				selection_box.active = false
				party.select_in_rect(Rect2(_press_world, world_pos - _press_world).abs(), mb.shift_pressed)
			else:
				_on_click(world_pos, mb.shift_pressed)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		party.clear_selection()


func _on_mouse_motion(mm: InputEventMouseMotion) -> void:
	_mouse_screen = mm.position
	if _left_down and not _dragging and mm.position.distance_to(_press_screen) > DRAG_THRESHOLD:
		_dragging = true
		selection_box.active = true
	if _dragging:
		selection_box.set_rect(Rect2(_press_world, screen_to_world(mm.position) - _press_world))
	_refresh_hover()


func _on_click(world_pos: Vector2, shift: bool) -> void:
	var member := party.member_at(world_pos)
	if member:
		if shift:
			party.toggle(member)
		else:
			party.select_only(member)
		return
	var prop := _interactable_at(world_pos)
	if prop and party.leader():
		party.interact_with(prop)
		return
	party.move_selected_to(grid.world_to_hex(world_pos))
	_refresh_hover(true)


## Viewport (screen) position -> world position, through the camera.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	Events.pause_changed.emit(paused)


func focus_selection() -> void:
	var list: Array = party.selected if not party.selected.is_empty() else party.members
	if list.is_empty():
		return
	var sum := Vector2.ZERO
	for m in list:
		sum += m.global_position
	camera.center_on(sum / list.size())


## Interactable prop under the cursor: sprite rectangle first, then footprint.
func _interactable_at(world_pos: Vector2) -> Prop:
	for p in props:
		if p.is_interactable() and p.sprite_rect().has_point(world_pos):
			return p
	var under: Prop = props_by_hex.get(grid.world_to_hex(world_pos))
	return under if under and under.is_interactable() else null


# --- hover feedback ----------------------------------------------------------------

func _process(_delta: float) -> void:
	if grid == null:
		return
	# Keep the path preview honest while the party walks.
	if party.leader() and party.leader().is_moving():
		_refresh_hover(true)
	_update_occlusion()


## Fades tall props (trees, buildings) that hide a party member behind them.
func _update_occlusion() -> void:
	for p in props:
		if not p.def.fade_when_occluding:
			continue
		var hide_someone := false
		var rect := p.sprite_rect()
		for m in party.members:
			if p.position.y > m.position.y and rect.intersects(m.pick_rect().grow(-6.0)):
				hide_someone = true
				break
		p.faded = hide_someone


func _refresh_hover(force: bool = false) -> void:
	if grid == null or _mouse_screen.x < 0.0:
		return
	var world_pos := screen_to_world(_mouse_screen)
	var h := grid.world_to_hex(world_pos)
	var member := party.member_at(world_pos)
	var prop := _interactable_at(world_pos)
	if not force and h == _hover_hex and member == _hover_member and prop == _hover_prop:
		return
	if _hover_member and is_instance_valid(_hover_member):
		_hover_member.hovered = false
	if _hover_prop and is_instance_valid(_hover_prop):
		_hover_prop.highlighted = false
	_hover_hex = h
	_hover_member = member
	_hover_prop = prop
	if member:
		member.hovered = true
	if prop:
		prop.highlighted = true

	var info := {
		"hex": h,
		"cell": Hex.axial_to_offset(h),
		"in_bounds": grid.in_bounds(h),
	}
	cursor.preview_path.clear()
	cursor.hover_hex = null
	if grid.in_bounds(h):
		cursor.hover_hex = h
	var t := grid.get_terrain(h)
	if t:
		info["terrain"] = t.display_name
		info["walkable"] = grid.is_walkable(h)
		info["move_cost"] = grid.move_cost(h)
	var any_prop: Prop = props_by_hex.get(h)
	if prop:
		info["prop"] = prop.display_name()
	elif any_prop:
		info["prop"] = any_prop.display_name()
	if member:
		info["member"] = member.sheet.display_name

	var cursor_shape := Input.CURSOR_ARROW
	if member:
		cursor.hover_hex = null
	elif prop:
		cursor.hover_color = CursorOverlay.HOVER_INTERACT
		cursor_shape = Input.CURSOR_POINTING_HAND
	elif party.leader():
		var leader := party.leader()
		var walkable := grid.is_walkable(h)
		cursor.hover_color = CursorOverlay.HOVER_OK if walkable else CursorOverlay.HOVER_BLOCKED
		if walkable and h != leader.hex:
			var path := grid.find_path(leader.hex, h)
			if path.is_empty():
				cursor.hover_color = CursorOverlay.HOVER_BLOCKED
			else:
				cursor.preview_path = path
				info["path_hexes"] = path.size()
				info["path_cost"] = grid.path_cost(path)
				info["path_feet"] = int(grid.path_cost(path) * GameConfig.feet_per_hex)
		elif not walkable:
			cursor_shape = Input.CURSOR_FORBIDDEN
	else:
		cursor.hover_color = CursorOverlay.HOVER_OK
	Input.set_default_cursor_shape(cursor_shape)
	Events.hover_info_changed.emit(info)
