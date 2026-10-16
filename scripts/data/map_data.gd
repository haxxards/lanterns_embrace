class_name MapData
extends RefCounted
## A parsed map file (see docs/MAPS.md for the format).
##
## Terrain and the prop layer are rows of characters in odd-r offset layout:
## every odd row is drawn half a hex to the right. Coordinates in the file
## ("at", "spawns") are offset [col, row]; they are converted to axial here.

## A single placed prop: definition plus per-instance data from the map file.
class Placement:
	var def: PropDef
	var cell: Vector2i            # offset [col, row] from the file ("at")
	var anchor: Vector2i          # the same cell in axial coordinates
	var cells: Array[Vector2i] = []  # axial hexes covered by the footprint
	var look: int = 0             # which variant (look) of the prop
	var extra: Dictionary = {}

var id: String = ""
var display_name: String = ""
var width: int = 0
var height: int = 0
var background_color: Color = Color(0.08, 0.1, 0.06)
## Terrain per offset cell, row-major; null where the symbol is unknown.
var terrain: Array[TerrainDef] = []
var placements: Array[Placement] = []
var party_spawn: Vector2i = Vector2i.ZERO  # axial
## Named arrival points (axial), e.g. "door" inside a building. Buildings on
## the map also act as entries: an entry named after a prop's "id" is the
## ground in front of its door.
var entries: Dictionary = {}
## Townsfolk to place: [{"id": npc id, "hex": axial Vector2i}].
var npc_spawns: Array[Dictionary] = []
## Hostile creatures: [{"id": spawn id, "type": creature id, "hex": axial,
## "group": encounter group, "wander": hexes}].
var creature_spawns: Array[Dictionary] = []
## Names from data/audio/audio.json ("" = silence).
var music: String = ""
var ambience: String = ""
## False turns fog of war off for this map (small interiors).
var fog: bool = true
## Optional pre-rendered picture of the whole map (interiors) drawn instead of
## blended terrain. `backdrop_origin` is its pixel at the centre of hex [0, 0].
var backdrop_path: String = ""
var backdrop_origin: Vector2 = Vector2.ZERO
var errors: PackedStringArray = PackedStringArray()


static func load_file(path: String, terrain_by_symbol: Dictionary, props: Dictionary) -> MapData:
	var m := MapData.new()
	var d: Variant = JsonUtil.load_json(path)
	if not d is Dictionary:
		m.errors.append("could not read map %s" % path)
		return m
	m.id = str(d.get("id", path.get_file().get_basename()))
	m.display_name = str(d.get("name", m.id.capitalize()))
	m.background_color = JsonUtil.parse_color(d.get("background_color"), m.background_color)

	var rows: Array = d.get("terrain", [])
	m.height = rows.size()
	for row in rows:
		m.width = maxi(m.width, str(row).length())
	m.terrain.resize(m.width * m.height)
	for r in m.height:
		var row := str(rows[r])
		for c in m.width:
			var sym := row[c] if c < row.length() else " "
			var t: TerrainDef = terrain_by_symbol.get(sym)
			if t == null and sym != " ":
				m.errors.append("unknown terrain symbol '%s' at [%d, %d]" % [sym, c, r])
			m.terrain[r * m.width + c] = t

	var legend: Dictionary = d.get("prop_legend", {})
	var layer: Array = d.get("prop_layer", [])
	for r in layer.size():
		var row := str(layer[r])
		for c in row.length():
			var sym := row[c]
			if sym == " " or sym == ".":
				continue
			if not legend.has(sym):
				m.errors.append("prop_layer symbol '%s' at [%d, %d] has no legend entry" % [sym, c, r])
				continue
			m._add_placement(props, str(legend[sym]), Vector2i(c, r), {})

	for entry in d.get("props", []):
		if not entry is Dictionary or not entry.has("type"):
			m.errors.append("prop entry without a type: %s" % str(entry))
			continue
		var extra: Dictionary = entry.duplicate()
		extra.erase("type")
		extra.erase("at")
		m._add_placement(props, str(entry["type"]), JsonUtil.to_vec2i(entry.get("at")), extra)

	var spawns: Dictionary = d.get("spawns", {})
	m.party_spawn = Hex.offset_to_axial(JsonUtil.to_vec2i(spawns.get("party"), Vector2i.ZERO))
	var entries: Dictionary = d.get("entries", {})
	for entry_name in entries:
		m.entries[str(entry_name)] = Hex.offset_to_axial(JsonUtil.to_vec2i(entries[entry_name]))
	for entry in d.get("npcs", []):
		if not entry is Dictionary or not entry.has("id"):
			m.errors.append("npc entry without an id: %s" % str(entry))
			continue
		m.npc_spawns.append({"id": str(entry["id"]), "hex": Hex.offset_to_axial(JsonUtil.to_vec2i(entry.get("at")))})
	for entry in d.get("creatures", []):
		if not entry is Dictionary or not entry.has("type"):
			m.errors.append("creature entry without a type: %s" % str(entry))
			continue
		var spawn_id := str(entry.get("id", "%s_%d" % [entry["type"], m.creature_spawns.size()]))
		m.creature_spawns.append({"id": spawn_id, "type": str(entry["type"]),
				"hex": Hex.offset_to_axial(JsonUtil.to_vec2i(entry.get("at"))),
				"group": str(entry.get("group", spawn_id)), "wander": int(entry.get("wander", 1))})
	m.music = str(d.get("music", ""))
	m.ambience = str(d.get("ambience", ""))
	m.fog = bool(d.get("fog", true))
	var backdrop: Variant = d.get("backdrop")
	if backdrop is Dictionary:
		m.backdrop_path = str(backdrop.get("texture", ""))
		m.backdrop_origin = JsonUtil.to_vec2(backdrop.get("origin"))
	return m


func _add_placement(props: Dictionary, type_id: String, cell: Vector2i, extra: Dictionary) -> void:
	var def: PropDef = props.get(type_id)
	if def == null:
		errors.append("unknown prop type '%s' at %s" % [type_id, cell])
		return
	var p := Placement.new()
	p.def = def
	p.cell = cell
	p.anchor = Hex.offset_to_axial(cell)
	p.cells = def.cells_at(cell)
	p.look = int(extra["variant"]) if extra.has("variant") else def.look_index_for(cell)
	p.extra = extra
	placements.append(p)
