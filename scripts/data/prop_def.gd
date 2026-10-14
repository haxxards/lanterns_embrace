class_name PropDef
extends RefCounted
## One prop type (tree, house, sign...) from data/props/props.json.
##
## Two footprint styles:
## - `footprint` / `footprint_radius`: axial (dq, dr) offsets from the anchor
##   hex. Good for small or round things; the shape is the same anywhere.
## - `footprint_rect`: [cols, rows] of hexes starting at the map's "at" cell
##   (top-left). Used for buildings: the outside is exactly cols x rows hexes,
##   the same size as the building's interior map.

const LAYER_ENTITIES := "entities"  # y-sorted with characters
const LAYER_GROUND := "ground"      # flat on the ground, under characters

var id: String = ""
var display_name: String = ""
var texture_path: String = ""
var texture: Texture2D
## Pixel in the texture placed on the anchor hex centre, or for rect
## footprints on the bottom-centre of the footprint.
var origin: Vector2 = Vector2.ZERO
var footprint: Array[Vector2i] = []
var footprint_rect: Vector2i = Vector2i.ZERO
var layer: String = LAYER_ENTITIES
var blocks_movement: bool = true
var blocks_sight: bool = false
## Movement multiplier applied to footprint hexes when not blocking.
var move_cost: float = 1.0
## Interaction kind ("read", ...) or "" for none.
var interaction: String = ""
## Turn see-through when a party member walks behind it. Defaults to true
## for tall sprites (trees, buildings); override with "fade_when_occluding".
var fade_when_occluding: bool = true
## Entrance, as a pixel in the texture (the door hex is the footprint hex
## nearest to it). Interiors (Phase 2) are entered from here.
var has_door: bool = false
var door_pixel: Vector2 = Vector2.ZERO
var minimap_color: Color = Color(0.3, 0.3, 0.3)

var _fade_override: Variant = null


static func from_dict(prop_id: String, d: Dictionary) -> PropDef:
	var p := PropDef.new()
	p.id = prop_id
	p.display_name = str(d.get("name", prop_id.capitalize()))
	p.texture_path = str(d.get("texture", ""))
	p.origin = JsonUtil.to_vec2(d.get("origin"), Vector2.ZERO)
	p.footprint_rect = JsonUtil.to_vec2i(d.get("footprint_rect"), Vector2i.ZERO)
	var cells := {}
	var radius := int(d.get("footprint_radius", -1))
	if radius >= 0:
		for h in Hex.spiral(Vector2i.ZERO, radius):
			cells[h] = true
	for v in d.get("footprint", []):
		cells[JsonUtil.to_vec2i(v)] = true
	if cells.is_empty() and not p.is_rect():
		cells[Vector2i.ZERO] = true
	for h in cells:
		p.footprint.append(h)
	p.layer = str(d.get("layer", LAYER_ENTITIES))
	p.blocks_movement = bool(d.get("blocks_movement", true))
	p.blocks_sight = bool(d.get("blocks_sight", false))
	p.move_cost = maxf(0.1, float(d.get("move_cost", 1.0)))
	p.interaction = str(d.get("interaction", ""))
	if d.has("door_pixel"):
		p.has_door = true
		p.door_pixel = JsonUtil.to_vec2(d["door_pixel"])
	p.minimap_color = JsonUtil.parse_color(d.get("minimap_color"), p.minimap_color)
	if d.has("fade_when_occluding"):
		p._fade_override = bool(d["fade_when_occluding"])
	return p


func is_rect() -> bool:
	return footprint_rect.x > 0 and footprint_rect.y > 0


## Hexes covered when placed at offset cell `at` (the map file's "at").
func cells_at(at: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_rect():
		for dr in footprint_rect.y:
			for dc in footprint_rect.x:
				out.append(Hex.offset_to_axial(at + Vector2i(dc, dr)))
	else:
		var anchor := Hex.offset_to_axial(at)
		for off in footprint:
			out.append(anchor + off)
	return out


## World point the sprite's `origin` is placed on.
static func placement_point(def: PropDef, cells: Array[Vector2i], anchor: Vector2i, radius: float) -> Vector2:
	if not def.is_rect() or cells.is_empty():
		return Hex.to_pixel(anchor, radius)
	var min_x := INF
	var max_x := -INF
	var max_y := -INF
	for h in cells:
		var p := Hex.to_pixel(h, radius)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	# Bottom-centre of the footprint, half-way between the last row's centres
	# and its bottom corners: where the front wall meets the ground.
	return Vector2((min_x + max_x) * 0.5, max_y + radius * 0.5)


## Footprint hex the door opens from (nearest to the door pixel), or null.
static func door_hex(def: PropDef, cells: Array[Vector2i], anchor: Vector2i, radius: float) -> Variant:
	if not def.has_door or cells.is_empty():
		return null
	var door_world := placement_point(def, cells, anchor, radius) - def.origin + def.door_pixel
	var best: Variant = null
	var best_d := INF
	for h in cells:
		var d := Hex.to_pixel(h, radius).distance_squared_to(door_world)
		if d < best_d:
			best_d = d
			best = h
	return best


## Called once the texture is known (tall sprites fade by default).
func resolve_fade(tall_threshold: float) -> void:
	if _fade_override != null:
		fade_when_occluding = _fade_override
	elif layer == LAYER_GROUND:
		fade_when_occluding = false
	elif texture:
		fade_when_occluding = texture.get_size().y > tall_threshold
