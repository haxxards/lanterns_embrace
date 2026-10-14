class_name TerrainDef
extends RefCounted
## One terrain type from data/terrain/terrain.json.

var id: String = ""
var display_name: String = ""
var symbol: String = ""
var texture_path: String = ""
var texture: Texture2D
var walkable: bool = true
## Movement multiplier: 1 = normal, 2 = difficult terrain (5e).
var move_cost: float = 1.0
var blocks_sight: bool = false
var minimap_color: Color = Color.MAGENTA


static func from_dict(d: Dictionary) -> TerrainDef:
	var t := TerrainDef.new()
	t.id = str(d.get("id", ""))
	t.display_name = str(d.get("name", t.id.capitalize()))
	t.symbol = str(d.get("symbol", ""))
	t.texture_path = str(d.get("texture", ""))
	t.walkable = bool(d.get("walkable", true))
	t.move_cost = maxf(0.1, float(d.get("move_cost", 1.0)))
	t.blocks_sight = bool(d.get("blocks_sight", false))
	t.minimap_color = JsonUtil.parse_color(d.get("minimap_color"), Color(0.4, 0.4, 0.4))
	return t
