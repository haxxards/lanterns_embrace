extends TestCase
## Validates the shipped data files (terrain, props, characters, maps).


func test_terrain_definitions() -> void:
	check(Data.terrain.size() > 0, "terrain loaded")
	var symbols := {}
	for t: TerrainDef in Data.terrain.values():
		check(not symbols.has(t.symbol), "symbol '%s' unique" % t.symbol)
		symbols[t.symbol] = true
		check(t.texture != Data.missing_texture(), "texture for %s exists (%s)" % [t.id, t.texture_path])


func test_prop_definitions() -> void:
	check(Data.props.size() > 0, "props loaded")
	for p: PropDef in Data.props.values():
		check(p.texture != Data.missing_texture(), "texture for %s exists (%s)" % [p.id, p.texture_path])
		check(not p.footprint.is_empty(), "%s has a footprint" % p.id)
	check_eq(Data.props["house_small"].footprint.size(), 7, "house_small radius-1 footprint")


func test_character_sheets_valid() -> void:
	check(Data.characters.size() >= GameConfig.max_party_size, "enough characters for a full party")
	for s: CharacterSheet in Data.characters.values():
		check(s.is_valid(), "%s: %s" % [s.source_path, ", ".join(s.errors)])
		check(Data.load_texture(s.portrait_path) != Data.missing_texture(), "%s portrait exists" % s.id)
		check(Data.load_texture(s.sprite_path) != Data.missing_texture(), "%s sprite exists" % s.id)


func test_starting_party_respects_max_size() -> void:
	GameState.start_new_game()
	check(GameState.party.size() > 0, "party created")
	check(GameState.party.size() <= GameConfig.max_party_size, "party within max size")


func test_sample_map_is_sound() -> void:
	var m := Data.load_map(GameConfig.starting_map_path)
	check(m.errors.is_empty(), "map errors: %s" % ", ".join(m.errors))
	check(m.width > 0 and m.height > 0, "map has size")
	var g := HexGrid.new()
	g.setup(m.width, m.height, GameConfig.hex_radius)
	for r in m.height:
		for c in m.width:
			g.set_terrain(Hex.offset_to_axial(Vector2i(c, r)), m.terrain[r * m.width + c])
	var footprint_owner := {}
	for pl in m.placements:
		for off in pl.def.footprint:
			var cell: Vector2i = pl.anchor + off
			check(g.in_bounds(cell), "%s at %s stays on the map" % [pl.def.id, pl.anchor])
			if pl.def.blocks_movement:
				check(not footprint_owner.has(cell), "%s overlaps another prop at %s" % [pl.def.id, cell])
				footprint_owner[cell] = pl
			g.add_prop_cell(cell, pl.def)
	g.rebuild_pathfinding()
	check(g.is_walkable(m.party_spawn), "spawn is walkable")
	for pl in m.placements:
		if pl.def.interaction.is_empty() and not pl.def.has_door:
			continue
		var cells: Array[Vector2i] = []
		for off in pl.def.footprint:
			cells.append(pl.anchor + off)
		var target: Vector2i = pl.anchor + pl.def.door if pl.def.has_door else pl.anchor
		var reachable := false
		for n in Hex.neighbors(target):
			if not cells.has(n) and g.is_reachable(m.party_spawn, n):
				reachable = true
				break
		check(reachable, "%s at %s can be reached from spawn" % [pl.def.id, Hex.axial_to_offset(pl.anchor)])
