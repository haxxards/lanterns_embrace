extends TestCase
## Fog of war visibility and GameState save data.


## Stands in for a PartyMember: the fog only reads `hex`.
class Looker:
	extends Node
	var hex: Vector2i


var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()


func _open_grid(size: int) -> HexGrid:
	var g := HexGrid.new()
	g.setup(size, size, 32.0)
	var grass: TerrainDef = Data.terrain["grass"]
	for i in g.cell_count():
		g.set_terrain(g.hex_at_index(i), grass)
	return g


func test_fog_reveals_within_sight_and_remembers() -> void:
	var g := _open_grid(30)
	var wall := TerrainDef.new()
	wall.walkable = false
	wall.blocks_sight = true
	var eye := Looker.new()
	eye.hex = Hex.offset_to_axial(Vector2i(5, 15))
	# A wall two hexes east of the looker, rows 10..20.
	for r in range(10, 21):
		g.set_terrain(Hex.offset_to_axial(Vector2i(7, r)), wall)
	var fog := FogOfWar.new()
	_nodes.append(fog)
	_nodes.append(eye)
	fog.setup(g, "fog_test_%d" % randi(), true, [eye])
	check(fog.is_in_sight(eye.hex), "own hex visible")
	check(fog.is_in_sight(Hex.offset_to_axial(Vector2i(5, 15 - GameConfig.fog_sight_radius))), "edge of sight visible")
	check(not fog.is_explored(Hex.offset_to_axial(Vector2i(5, 15 - GameConfig.fog_sight_radius - 2))), "beyond sight unseen")
	check(fog.is_in_sight(Hex.offset_to_axial(Vector2i(7, 15))), "the wall itself is seen")
	check(not fog.is_explored(Hex.offset_to_axial(Vector2i(9, 15))), "behind the wall stays dark")
	var first := Hex.offset_to_axial(Vector2i(3, 15))
	eye.hex = Hex.offset_to_axial(Vector2i(25, 3))
	fog.refresh()
	check(not fog.is_in_sight(first), "old spot out of sight now")
	check(fog.is_explored(first), "but remembered as explored")


func test_fog_disabled_means_everything_seen() -> void:
	var g := _open_grid(10)
	var fog := FogOfWar.new()
	_nodes.append(fog)
	fog.setup(g, "fog_off", false, [])
	check(fog.is_explored(Vector2i(3, 3)) and fog.is_in_sight(Vector2i(3, 3)), "no fog")


func test_game_state_round_trip() -> void:
	GameState.start_new_game()
	GameState.add_gold(17)
	var g := GameState.party[0]
	g.hp_current = 4
	g.inventory.add_item("garnet", 3)
	var box := ContainerState.from_placement({"items": [{"item": "apple", "qty": 2}], "locked": true, "lock_dc": 14})
	GameState.set_container("some_map", "box", box)
	var mask := GameState.explored_for("some_map", 12)
	mask[5] = 1
	GameState.set_explored("some_map", mask)
	GameState.flags["met_reeve"] = true
	var saved := GameState.to_dict({g.id: Vector2i(7, 9)}, Vector2(100, 200))
	var gold := GameState.gold
	# Through JSON text, exactly as a save file stores it.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	GameState.start_new_game()
	check(GameState.load_dict(parsed), "loads")
	check_eq(GameState.gold, gold, "gold")
	var g2 := GameState.member(g.id)
	check_eq(g2.hp_current, 4, "hit points")
	check_eq(g2.inventory.count("garnet"), 3, "backpack")
	check_eq(g2.equipped("armor").id, "chain_mail", "equipment")
	check_eq(g2.armor_class, 18, "AC recomputed")
	var box2 := GameState.get_container("some_map", "box")
	check(box2 != null and box2.locked and box2.lock_dc == 14, "container lock")
	check_eq(box2.inventory.count("apple"), 2, "container contents")
	check_eq(GameState.explored_for("some_map", 12)[5], 1, "explored mask")
	check_eq(GameState.pending_positions.get(g.id), Vector2i(7, 9), "position")
	check_eq(GameState.pending_camera, Vector2(100, 200), "camera")
	check(GameState.flags.get("met_reeve", false), "flags")
	GameState.start_new_game()
