extends TestCase
## Pathfinding on small hand-made grids.

var floor_t: TerrainDef
var wall_t: TerrainDef
var mud_t: TerrainDef


func before_each() -> void:
	floor_t = TerrainDef.from_dict({"id": "floor", "symbol": ".", "walkable": true})
	wall_t = TerrainDef.from_dict({"id": "wall", "symbol": "#", "walkable": false})
	mud_t = TerrainDef.from_dict({"id": "mud", "symbol": "m", "walkable": true, "move_cost": 2.0})


func _grid(rows: Array) -> HexGrid:
	var g := HexGrid.new()
	g.setup(str(rows[0]).length(), rows.size(), 32.0)
	var by_symbol := {".": floor_t, "#": wall_t, "m": mud_t}
	for r in rows.size():
		for c in str(rows[r]).length():
			g.set_terrain(Hex.offset_to_axial(Vector2i(c, r)), by_symbol[str(rows[r])[c]])
	g.rebuild_pathfinding()
	return g


func _ax(col: int, row: int) -> Vector2i:
	return Hex.offset_to_axial(Vector2i(col, row))


func test_straight_path() -> void:
	var g := _grid(["......."])
	var p := g.find_path(_ax(0, 0), _ax(6, 0))
	check_eq(p.size(), 6, "six steps")
	check_eq(p[-1], _ax(6, 0), "ends at target")


func test_path_goes_around_wall() -> void:
	var g := _grid([
		".......",
		"...#...",
		"...#...",
		"...#...",
		".......",
	])
	var p := g.find_path(_ax(1, 2), _ax(5, 2))
	check(not p.is_empty(), "path found")
	for h in p:
		check(g.is_walkable(h), "path cell %s walkable" % h)
	var prev := _ax(1, 2)
	for h in p:
		check_eq(Hex.distance(prev, h), 1, "adjacent steps")
		prev = h


func test_unreachable_returns_empty() -> void:
	var g := _grid([
		"..#..",
		"..#..",
		"..#..",
	])
	check(g.find_path(_ax(0, 1), _ax(4, 1)).is_empty(), "wall splits the map")
	check(not g.is_reachable(_ax(0, 1), _ax(4, 1)), "is_reachable agrees")
	check(g.find_path(_ax(0, 1), _ax(2, 1)).is_empty(), "target is a wall")


func test_difficult_terrain_is_avoided_when_cheap() -> void:
	var g := _grid([
		".......",
		".mmmmm.",
		".......",
	])
	var p := g.find_path(_ax(0, 1), _ax(6, 1))
	var through_mud := 0
	for h in p:
		if g.move_cost(h) > 1.0:
			through_mud += 1
	check_eq(through_mud, 0, "detour around mud row")
	check(g.path_cost(p) <= 8.0, "detour cost reasonable (%s)" % g.path_cost(p))


func test_difficult_terrain_costs_double() -> void:
	var g := _grid(["mmmm"])
	var p := g.find_path(_ax(0, 0), _ax(3, 0))
	check_eq(p.size(), 3, "three steps")
	check_eq(g.path_cost(p), 6.0, "each mud hex costs 2")


func test_prop_blocks_and_slows() -> void:
	var g := _grid(["....."])
	var rock := PropDef.from_dict("rock", {"blocks_movement": true})
	var bush := PropDef.from_dict("bush", {"blocks_movement": false, "move_cost": 2.0})
	g.add_prop_cell(_ax(2, 0), bush)
	g.rebuild_pathfinding()
	check(g.is_walkable(_ax(2, 0)), "bush is walkable")
	check_eq(g.move_cost(_ax(2, 0)), 2.0, "bush is difficult")
	g.add_prop_cell(_ax(3, 0), rock)
	g.rebuild_pathfinding()
	check(not g.is_walkable(_ax(3, 0)), "rock blocks")
	check(g.find_path(_ax(0, 0), _ax(4, 0)).is_empty(), "single row is cut by the rock")


func test_world_bounds_cover_all_hexes() -> void:
	var g := _grid(["....", "....", "...."])
	var b := g.world_bounds().grow(0.01)
	for i in g.cell_count():
		var c := g.hex_to_world(g.hex_at_index(i))
		for p in Hex.corners(c, g.radius):
			check(b.has_point(p), "corner %s inside bounds" % p)


func test_world_to_hex_matches_storage() -> void:
	var g := _grid(["....", "....", "...."])
	for i in g.cell_count():
		var h := g.hex_at_index(i)
		check_eq(g.index_of(h), i, "index round trip")
		check_eq(g.world_to_hex(g.hex_to_world(h)), h, "world round trip")
