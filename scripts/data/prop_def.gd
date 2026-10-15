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


## One look of a prop: its image, pivot and (for buildings) door. A prop type
## can have several looks ("variants"); each placed instance picks one.
class Look:
	var texture_path: String = ""
	var texture: Texture2D
	## Pixel in the texture placed on the anchor hex centre, or for rect
	## footprints on the bottom-centre of the footprint.
	var origin: Vector2 = Vector2.ZERO
	var has_door: bool = false
	## Entrance pixel in the texture; the door hex is the footprint hex nearest to it.
	var door_pixel: Vector2 = Vector2.ZERO

	static func from_dict(d: Dictionary, fallback: Look = null) -> Look:
		var l := Look.new()
		l.texture_path = str(d.get("texture", fallback.texture_path if fallback else ""))
		l.origin = JsonUtil.to_vec2(d.get("origin"), fallback.origin if fallback else Vector2.ZERO)
		if d.has("door_pixel"):
			l.has_door = true
			l.door_pixel = JsonUtil.to_vec2(d["door_pixel"])
		elif fallback:
			l.has_door = fallback.has_door
			l.door_pixel = fallback.door_pixel
		return l


var id: String = ""
var display_name: String = ""
var looks: Array[Look] = []
## Shortcuts to the first look (single-look props use only these).
var texture_path: String = ""
var texture: Texture2D
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
## True if the prop has an entrance (any look defines a door pixel).
## Interiors (Phase 2) are entered from the door hex.
var has_door: bool = false
var minimap_color: Color = Color(0.3, 0.3, 0.3)

var _fade_override: Variant = null


static func from_dict(prop_id: String, d: Dictionary) -> PropDef:
	var p := PropDef.new()
	p.id = prop_id
	p.display_name = str(d.get("name", prop_id.capitalize()))
	var base := Look.from_dict(d)
	for v in d.get("variants", []):
		if v is Dictionary:
			p.looks.append(Look.from_dict(v, base))
	if p.looks.is_empty():
		p.looks.append(base)
	p.texture_path = p.looks[0].texture_path
	p.origin = p.looks[0].origin
	for l in p.looks:
		p.has_door = p.has_door or l.has_door
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
	p.minimap_color = JsonUtil.parse_color(d.get("minimap_color"), p.minimap_color)
	if d.has("fade_when_occluding"):
		p._fade_override = bool(d["fade_when_occluding"])
	return p


## Look `i` (wraps around, so any index is valid).
func look(i: int) -> Look:
	return looks[posmod(i, looks.size())]


## Look picked for an instance at offset cell `cell` when the map doesn't say:
## a stable hash, so the same map always looks the same.
func look_index_for(cell: Vector2i) -> int:
	if looks.size() <= 1:
		return 0
	var h := (cell.x * 73856093) ^ (cell.y * 19349663)
	return posmod(h, looks.size())


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
static func door_hex(def: PropDef, cells: Array[Vector2i], anchor: Vector2i, radius: float,
		look_index: int = 0) -> Variant:
	var l := def.look(look_index)
	if not l.has_door or cells.is_empty():
		return null
	var door_world := placement_point(def, cells, anchor, radius) - l.origin + l.door_pixel
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
	else:
		var tallest := 0.0
		for l in looks:
			if l.texture:
				tallest = maxf(tallest, l.texture.get_size().y)
		fade_when_occluding = tallest > tall_threshold
