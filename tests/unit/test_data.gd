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
		check(p.is_rect() or not p.footprint.is_empty(), "%s has a footprint" % p.id)
	check_eq(Data.props["house_small"].cells_at(Vector2i(3, 4)).size(), 48, "cottage covers 8 x 6 hexes")
	check_eq(Data.props["house_large"].cells_at(Vector2i(3, 5)).size(), 96, "inn covers 12 x 8 hexes")


func test_buildings_are_as_big_outside_as_their_footprint() -> void:
	# The sprite must cover the footprint (which is also the interior size),
	# give or take the half-hex stagger of odd rows and the eaves.
	var hex_w := Hex.SQRT3 * GameConfig.hex_radius
	for p: PropDef in Data.props.values():
		if not p.is_rect() or p.layer != PropDef.LAYER_ENTITIES:
			continue
		var tex_w := p.texture.get_size().x
		var foot_w := p.footprint_rect.x * hex_w
		check(absf(tex_w - foot_w) <= hex_w * 0.6,
				"%s sprite width %d matches its %d-hex footprint (%d px)" % [p.id, tex_w, p.footprint_rect.x, foot_w])
		check(p.has_door, "%s has a door" % p.id)


func test_door_hex_is_on_the_front_row() -> void:
	var def: PropDef = Data.props["house_small"]
	for at in [Vector2i(10, 10), Vector2i(10, 11)]:  # both row parities
		var cells := def.cells_at(at)
		var door: Variant = PropDef.door_hex(def, cells, Hex.offset_to_axial(at), GameConfig.hex_radius)
		check(door != null, "door found")
		check_eq(Hex.axial_to_offset(door).y, at.y + def.footprint_rect.y - 1, "door on the bottom row")


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
		for cell in pl.cells:
			check(g.in_bounds(cell), "%s at %s stays on the map" % [pl.def.id, pl.cell])
			if pl.def.blocks_movement:
				check(not footprint_owner.has(cell), "%s overlaps another prop at %s" % [pl.def.id, cell])
				footprint_owner[cell] = pl
			g.add_prop_cell(cell, pl.def)
	g.rebuild_pathfinding()
	check(g.is_walkable(m.party_spawn), "spawn is walkable")
	for pl in m.placements:
		if pl.def.interaction.is_empty() and not pl.def.has_door:
			continue
		var target: Vector2i = pl.anchor
		if pl.def.has_door:
			target = PropDef.door_hex(pl.def, pl.cells, pl.anchor, GameConfig.hex_radius)
		var reachable := false
		for n in Hex.neighbors(target):
			if not pl.cells.has(n) and g.is_reachable(m.party_spawn, n):
				reachable = true
				break
		check(reachable, "%s at %s can be reached from spawn" % [pl.def.id, pl.cell])
