class_name HexGrid
extends RefCounted
## Logical map: terrain per hex, prop blockers, and A* pathfinding.
##
## Cells are addressed by axial Vector2i. Storage is a flat array in odd-r
## offset order (row * width + col), which matches the map text layout.

var width: int = 0
var height: int = 0
var radius: float = 32.0

var _terrain: Array[TerrainDef] = []
var _prop_blocks: PackedByteArray = PackedByteArray()
var _prop_sight: PackedByteArray = PackedByteArray()
var _prop_cost: PackedFloat32Array = PackedFloat32Array()
## Hexes taken by standing creatures (NPCs): not walkable while occupied.
var _occupied: Dictionary = {}  # Vector2i -> true
var _astar := AStar2D.new()


func setup(map_width: int, map_height: int, hex_radius: float) -> void:
	width = map_width
	height = map_height
	radius = hex_radius
	var n := width * height
	_terrain.resize(n)
	_prop_blocks.resize(n)
	_prop_blocks.fill(0)
	_prop_sight.resize(n)
	_prop_sight.fill(0)
	_prop_cost.resize(n)
	_prop_cost.fill(1.0)


# --- addressing --------------------------------------------------------------

func in_bounds(h: Vector2i) -> bool:
	var o := Hex.axial_to_offset(h)
	return o.x >= 0 and o.y >= 0 and o.x < width and o.y < height


func index_of(h: Vector2i) -> int:
	var o := Hex.axial_to_offset(h)
	return o.y * width + o.x


@warning_ignore("integer_division")
func hex_at_index(i: int) -> Vector2i:
	return Hex.offset_to_axial(Vector2i(i % width, i / width))


func cell_count() -> int:
	return width * height


func hex_to_world(h: Vector2i) -> Vector2:
	return Hex.to_pixel(h, radius)


func world_to_hex(p: Vector2) -> Vector2i:
	return Hex.from_pixel(p, radius)


## World-space rectangle covering every hex of the map.
func world_bounds() -> Rect2:
	var w := Hex.SQRT3 * radius
	return Rect2(-w * 0.5, -radius, w * (width + 0.5), radius * (1.5 * (height - 1) + 2.0))


# --- terrain & blockers --------------------------------------------------------

func set_terrain(h: Vector2i, t: TerrainDef) -> void:
	if in_bounds(h):
		_terrain[index_of(h)] = t


func get_terrain(h: Vector2i) -> TerrainDef:
	return _terrain[index_of(h)] if in_bounds(h) else null


func add_prop_cell(h: Vector2i, def: PropDef) -> void:
	if not in_bounds(h):
		return
	var i := index_of(h)
	if def.blocks_movement:
		_prop_blocks[i] = 1
	else:
		_prop_cost[i] = maxf(_prop_cost[i], def.move_cost)
	if def.blocks_sight:
		_prop_sight[i] = 1


func is_walkable(h: Vector2i) -> bool:
	if not in_bounds(h) or _occupied.has(h):
		return false
	return is_ground_walkable(h)


## Walkable terrain and no blocking prop, ignoring creatures standing there.
func is_ground_walkable(h: Vector2i) -> bool:
	if not in_bounds(h):
		return false
	var i := index_of(h)
	var t := _terrain[i]
	return t != null and t.walkable and _prop_blocks[i] == 0


## Marks a hex as taken by a creature (or frees it). Pathfinding goes around
## occupied hexes without rebuilding the graph.
func set_occupied(h: Vector2i, occupied: bool) -> void:
	if not in_bounds(h):
		return
	if occupied:
		_occupied[h] = true
	else:
		_occupied.erase(h)
	var i := index_of(h)
	if _astar.has_point(i):
		_astar.set_point_disabled(i, occupied)


func is_occupied(h: Vector2i) -> bool:
	return _occupied.has(h)


func blocks_sight(h: Vector2i) -> bool:
	if not in_bounds(h):
		return true
	var i := index_of(h)
	var t := _terrain[i]
	return (t != null and t.blocks_sight) or _prop_sight[i] == 1


## Movement multiplier for entering `h` (1 = normal, 2 = difficult).
func move_cost(h: Vector2i) -> float:
	if not in_bounds(h):
		return INF
	var i := index_of(h)
	var t := _terrain[i]
	return (t.move_cost if t != null else 1.0) * _prop_cost[i]


# --- pathfinding ---------------------------------------------------------------

## Rebuilds the A* graph. Call after terrain or blockers change.
func rebuild_pathfinding() -> void:
	_astar.clear()
	_astar.reserve_space(cell_count())
	for i in cell_count():
		var h := hex_at_index(i)
		if is_ground_walkable(h):
			_astar.add_point(i, hex_to_world(h), move_cost(h))
	for i in cell_count():
		if not _astar.has_point(i):
			continue
		var h := hex_at_index(i)
		for n in Hex.neighbors(h):
			if in_bounds(n):
				var j := index_of(n)
				if j > i and _astar.has_point(j):
					_astar.connect_points(i, j, true)
	for h in _occupied:
		_astar.set_point_disabled(index_of(h), true)


## Hex path from `from` to `to`, excluding `from`. Empty if unreachable.
## Entering difficult terrain costs more, so paths route around it when cheap.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to or not in_bounds(from) or not in_bounds(to):
		return out
	var a := index_of(from)
	var b := index_of(to)
	if not _astar.has_point(a) or not _astar.has_point(b):
		return out
	var ids := _astar.get_id_path(a, b)
	for k in range(1, ids.size()):
		out.append(hex_at_index(ids[k]))
	return out


func is_reachable(from: Vector2i, to: Vector2i) -> bool:
	return from == to or not find_path(from, to).is_empty()


## Total movement cost of a path in hexes (difficult terrain counts double).
func path_cost(path: Array[Vector2i]) -> float:
	var total := 0.0
	for h in path:
		total += move_cost(h)
	return total


## Walkable hexes within `max_radius` of `target`, nearest first.
func walkable_near(target: Vector2i, max_radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in Hex.spiral(target, max_radius):
		if is_walkable(h):
			out.append(h)
	return out
