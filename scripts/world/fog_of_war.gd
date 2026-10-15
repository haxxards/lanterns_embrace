class_name FogOfWar
extends Node2D
## Fog of war: black where the party has never been, dimmed where it has been
## but can't see right now, clear within sight of any member.
##
## Sight is worked out per hex: everything within `fog_sight_radius` hexes
## that has a clear hex line (Hex.line) to the member, where hexes that block
## sight (buildings, walls) stop the line. Explored hexes are remembered in
## GameState, per map, so they survive map changes and saves.
## The drawing is done by fog_of_war.gdshader from a tiny one-texel-per-hex
## texture, so updating the fog only touches a few thousand bytes.

signal changed

const SHADER := preload("res://scripts/world/fog_of_war.gdshader")
const VISIBLE := 0
const EXPLORED := 128
const UNSEEN := 255

var enabled: bool = false
var grid: HexGrid
var map_id: String = ""
## One byte per hex (grid index order): 1 = explored.
var explored := PackedByteArray()
## One byte per hex: 1 = in sight right now.
var in_sight := PackedByteArray()
## The per-hex texture the shader reads.
var texture: ImageTexture
## Per-hex state as last drawn (VISIBLE / EXPLORED / UNSEEN), for the minimap.
var cell_states := PackedByteArray()

var _members: Array = []
var _dirty: bool = false
var _rect := Rect2()


func setup(g: HexGrid, id: String, on: bool, members: Array) -> void:
	grid = g
	map_id = id
	_members = members
	enabled = on and GameConfig.fog_enabled
	visible = enabled
	explored = GameState.explored_for(map_id, grid.cell_count())
	in_sight.resize(grid.cell_count())
	in_sight.fill(0)
	var img := Image.create(grid.width, grid.height, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("fog_cells", texture)
	mat.set_shader_parameter("grid_size", Vector2(grid.width, grid.height))
	mat.set_shader_parameter("hex_radius", grid.radius)
	mat.set_shader_parameter("explored_dim", GameConfig.fog_explored_dim)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	mat.set_shader_parameter("noise", ImageTexture.create_from_image(noise.get_seamless_image(128, 128)))
	material = mat
	# Cover well past the map edge so nothing outside shows through.
	_rect = grid.world_bounds().grow(grid.radius * 40.0)
	refresh()
	queue_redraw()


## Call when a member enters a new hex; the fog updates once per frame at most.
func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		refresh()


## True if `h` has ever been seen (always true with the fog off).
func is_explored(h: Vector2i) -> bool:
	if not enabled or grid == null or not grid.in_bounds(h):
		return not enabled
	return explored[grid.index_of(h)] == 1


func is_in_sight(h: Vector2i) -> bool:
	if not enabled or grid == null or not grid.in_bounds(h):
		return not enabled
	return in_sight[grid.index_of(h)] == 1


## Recomputes what the party can see and uploads the fog texture.
func refresh() -> void:
	_dirty = false
	if not enabled or grid == null:
		return
	in_sight.fill(0)
	for m in _members:
		if is_instance_valid(m):
			_reveal_from(m.hex, GameConfig.fog_sight_radius)
	var data := PackedByteArray()
	data.resize(grid.cell_count())
	for i in data.size():
		data[i] = VISIBLE if in_sight[i] == 1 else (EXPLORED if explored[i] == 1 else UNSEEN)
	cell_states = data
	texture.update(Image.create_from_data(grid.width, grid.height, false, Image.FORMAT_L8, data))
	GameState.set_explored(map_id, explored)
	changed.emit()


## Sight is round (measured in pixels), not hexagonal, so its edge looks natural.
func _reveal_from(center: Vector2i, radius: int) -> void:
	var origin := grid.hex_to_world(center)
	var reach := (radius + 0.5) * Hex.SQRT3 * grid.radius
	for h in Hex.spiral(center, radius):
		if not grid.in_bounds(h) or grid.hex_to_world(h).distance_to(origin) > reach:
			continue
		var i := grid.index_of(h)
		if in_sight[i] == 1 or not _line_of_sight(center, h):
			continue
		in_sight[i] = 1
		explored[i] = 1


## Clear if no hex strictly between a and b blocks sight (the end hex itself
## may: you can see a wall, just not past it).
func _line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var line := Hex.line(a, b)
	for k in range(1, line.size() - 1):
		if grid.blocks_sight(line[k]):
			return false
	return true


func _draw() -> void:
	if enabled:
		draw_rect(_rect, Color.WHITE)
