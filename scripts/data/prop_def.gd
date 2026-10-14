class_name PropDef
extends RefCounted
## One prop type (tree, house, sign...) from data/props/props.json.
##
## Footprints are axial (dq, dr) offsets from the prop's anchor hex, so a
## shape looks the same wherever it is placed.

var id: String = ""
var display_name: String = ""
var texture_path: String = ""
var texture: Texture2D
## Pixel in the texture that sits on the anchor hex centre.
var origin: Vector2 = Vector2.ZERO
var footprint: Array[Vector2i] = []
var blocks_movement: bool = true
var blocks_sight: bool = false
## Movement multiplier applied to footprint hexes when not blocking.
var move_cost: float = 1.0
## Interaction kind ("read", ...) or "" for none.
var interaction: String = ""
## Turn see-through when a party member walks behind it. Defaults to true
## for tall sprites (trees, buildings); override with "fade_when_occluding".
var fade_when_occluding: bool = true
var has_door: bool = false
var door: Vector2i = Vector2i.ZERO
var minimap_color: Color = Color(0.3, 0.3, 0.3)

var _fade_override: Variant = null


static func from_dict(prop_id: String, d: Dictionary) -> PropDef:
	var p := PropDef.new()
	p.id = prop_id
	p.display_name = str(d.get("name", prop_id.capitalize()))
	p.texture_path = str(d.get("texture", ""))
	p.origin = JsonUtil.to_vec2(d.get("origin"), Vector2.ZERO)
	var cells := {}
	var radius := int(d.get("footprint_radius", -1))
	if radius >= 0:
		for h in Hex.spiral(Vector2i.ZERO, radius):
			cells[h] = true
	for v in d.get("footprint", []):
		cells[JsonUtil.to_vec2i(v)] = true
	if cells.is_empty():
		cells[Vector2i.ZERO] = true
	for h in cells:
		p.footprint.append(h)
	p.blocks_movement = bool(d.get("blocks_movement", true))
	p.blocks_sight = bool(d.get("blocks_sight", false))
	p.move_cost = maxf(0.1, float(d.get("move_cost", 1.0)))
	p.interaction = str(d.get("interaction", ""))
	if d.has("door"):
		p.has_door = true
		p.door = JsonUtil.to_vec2i(d["door"])
	p.minimap_color = JsonUtil.parse_color(d.get("minimap_color"), p.minimap_color)
	if d.has("fade_when_occluding"):
		p._fade_override = bool(d["fade_when_occluding"])
	return p


## Called once the texture is known (tall sprites fade by default).
func resolve_fade(tall_threshold: float) -> void:
	if _fade_override != null:
		fade_when_occluding = _fade_override
	elif texture:
		fade_when_occluding = texture.get_size().y > tall_threshold
