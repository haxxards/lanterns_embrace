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
		for l in p.looks:
			check(l.texture != Data.missing_texture(), "texture for %s exists (%s)" % [p.id, l.texture_path])
		check(p.is_rect() or not p.footprint.is_empty(), "%s has a footprint" % p.id)
	check_eq(Data.props["house_small"].cells_at(Vector2i(3, 4)).size(), 48, "cottage covers 8 x 6 hexes")
	check_eq(Data.props["house_large"].cells_at(Vector2i(3, 5)).size(), 96, "inn covers 12 x 8 hexes")


func test_buildings_are_as_big_outside_as_their_footprint() -> void:
	# The sprite must cover the footprint (which is also the interior size),
	# give or take the half-hex stagger of odd rows and the eaves.
	var hex_w := Hex.SQRT3 * GameConfig.hex_radius
	for building_id in ["house_small", "house_large"]:
		var p: PropDef = Data.props[building_id]
		check(p.is_rect(), "%s has a rectangular footprint" % building_id)
		for l in p.looks:
			_check_building_look(p, l, hex_w)


func _check_building_look(p: PropDef, l: PropDef.Look, hex_w: float) -> void:
	# Measure the solid building only: rendered shadows are semi-transparent.
	var img := l.texture.get_image()
	img.decompress()
	var min_x := img.get_width()
	var max_x := -1
	for x in img.get_width():
		for y in range(0, img.get_height(), 2):
			if img.get_pixel(x, y).a > 0.97:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				break
	var solid_w := max_x - min_x + 1
	var foot_w := p.footprint_rect.x * hex_w
	# Walls match the footprint; roof eaves may overhang by up to a hex in total.
	check(solid_w >= foot_w - hex_w * 0.6 and solid_w <= foot_w + hex_w,
			"%s building width %d px matches its %d-hex footprint (%d px)" % [p.id, solid_w, p.footprint_rect.x, foot_w])
	# The origin (front-wall centre) must sit in the middle of the building.
	check(absf(l.origin.x - (min_x + max_x) * 0.5) <= hex_w * 0.5, "%s origin is centred (%s)" % [p.id, l.texture_path])
	check(l.has_door, "%s has a door (%s)" % [p.id, l.texture_path])


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


func test_every_map_is_sound() -> void:
	var paths := JsonUtil.list_json_files("res://data/maps")
	check(paths.size() >= 6, "outdoor map plus five interiors")
	for path in paths:
		_check_map(path)


func _check_map(path: String) -> void:
	var m := Data.load_map(path)
	check(m.errors.is_empty(), "%s errors: %s" % [path, ", ".join(m.errors)])
	check(m.width > 0 and m.height > 0, "%s has size" % path)
	if not m.backdrop_path.is_empty():
		check(Data.load_texture(m.backdrop_path) != Data.missing_texture(), "%s backdrop exists" % path)
	var g := _map_grid(m)
	var footprint_owner := {}
	for pl in m.placements:
		for cell in pl.cells:
			check(g.in_bounds(cell), "%s: %s at %s stays on the map" % [m.id, pl.def.id, pl.cell])
			if pl.def.blocks_movement:
				check(not footprint_owner.has(cell), "%s: %s overlaps another prop at %s" % [m.id, pl.def.id, cell])
				footprint_owner[cell] = pl
	check(g.is_walkable(m.party_spawn), "%s: spawn is walkable" % m.id)
	for entry in m.entries:
		check(g.is_walkable(m.entries[entry]), "%s: entry '%s' is walkable" % [m.id, entry])
	for pl in m.placements:
		var kind := str(pl.extra.get("interaction", pl.def.interaction))
		if kind.is_empty():
			continue
		var target: Vector2i = pl.anchor
		if pl.def.has_door:
			target = PropDef.door_hex(pl.def, pl.cells, pl.anchor, GameConfig.hex_radius, pl.look)
		var reachable := not pl.def.blocks_movement and g.is_reachable(m.party_spawn, target)
		for n in Hex.neighbors(target):
			if not pl.cells.has(n) and g.is_reachable(m.party_spawn, n):
				reachable = true
				break
		check(reachable, "%s: %s at %s can be reached from spawn" % [m.id, pl.def.id, pl.cell])
		for it in pl.extra.get("items", []):
			check(Data.items.has(str(it.get("item"))), "%s: %s holds unknown item %s" % [m.id, pl.def.id, it])
		if kind == "container" and pl.extra.has("key"):
			check(Data.items.has(str(pl.extra["key"])), "%s: key item %s exists" % [m.id, pl.extra["key"]])


func _map_grid(m: MapData) -> HexGrid:
	var g := HexGrid.new()
	g.setup(m.width, m.height, GameConfig.hex_radius)
	for r in m.height:
		for c in m.width:
			g.set_terrain(Hex.offset_to_axial(Vector2i(c, r)), m.terrain[r * m.width + c])
	for pl in m.placements:
		for cell in pl.cells:
			g.add_prop_cell(cell, pl.def)
	g.rebuild_pathfinding()
	return g


## The inn is furnished by the "bar" and "tables" add-ons on its house.
func test_inn_has_a_bar_and_tables() -> void:
	var outside := Data.load_map(GameConfig.starting_map_path)
	var inn_addons: Array = []
	for pl in outside.placements:
		if pl.extra.get("id") == "millbrook_inn":
			inn_addons = pl.extra.get("addons", [])
	check(inn_addons.has("bar"), "the inn asks for a bar")
	var counts := {}
	for pl in Data.load_map("res://data/maps/millbrook_inn.json").placements:
		counts[pl.def.id] = int(counts.get(pl.def.id, 0)) + 1
	check_eq(counts.get("bar_counter", 0), 1, "a bar counter")
	check_eq(counts.get("bar_back", 0), 1, "shelves behind the bar")
	check(counts.get("table", 0) >= 3, "tables (%d)" % counts.get("table", 0))


## Phase 1 promised that a building is as large inside as outside: every
## building's interior map is exactly its footprint, and its exit leads back
## to that building.
func test_interiors_match_their_buildings() -> void:
	var outside := Data.load_map(GameConfig.starting_map_path)
	var count := 0
	for pl in outside.placements:
		if not pl.extra.has("interior"):
			continue
		count += 1
		var inside := Data.load_map(str(pl.extra["interior"]))
		check_eq(Vector2i(inside.width, inside.height), pl.def.footprint_rect, "%s interior size" % pl.extra.get("name"))
		check(inside.entries.has(str(pl.extra.get("entry", "door"))), "%s has its entry" % inside.id)
		var exits := 0
		for ip in inside.placements:
			if str(ip.extra.get("interaction", ip.def.interaction)) == "exit":
				exits += 1
				check_eq(str(ip.extra.get("map")), GameConfig.starting_map_path, "%s exit map" % inside.id)
				check_eq(str(ip.extra.get("entry")), str(pl.extra.get("id")), "%s exit leads to its building" % inside.id)
		check_eq(exits, 1, "%s has one exit" % inside.id)
	check_eq(count, 5, "five buildings with interiors")
