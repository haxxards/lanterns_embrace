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
	p.extra = extra
	placements.append(p)
