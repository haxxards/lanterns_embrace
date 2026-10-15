class_name Prop
extends Node2D
## A placed map object (tree, house, sign...). Its node position is the
## anchor hex centre, which is also the point used for y-sorting.

var def: PropDef
var look: PropDef.Look
var look_index: int = 0
var anchor: Vector2i
var cells: Array[Vector2i] = []
## Per-instance data from the map file ("name", "title", "text"...).
var extra: Dictionary = {}
var highlighted: bool = false:
	set(value):
		highlighted = value
		_update_modulate()
## See-through while a party member is behind it.
var faded: bool = false:
	set(value):
		if value != faded:
			faded = value
			_update_modulate()

var _sprite: Sprite2D


func setup(placement: MapData.Placement, grid: HexGrid) -> void:
	def = placement.def
	look_index = placement.look
	look = def.look(look_index)
	anchor = placement.anchor
	extra = placement.extra
	cells = placement.cells.duplicate()
	name = "%s_%d_%d" % [def.id, placement.cell.x, placement.cell.y]
	# Rect footprints (buildings) sit on their footprint's bottom edge, which is
	# also their y-sort point; other props sit on their anchor hex.
	position = PropDef.placement_point(def, cells, anchor, grid.radius)
	_sprite = Sprite2D.new()
	_sprite.texture = look.texture
	_sprite.centered = false
	_sprite.offset = -look.origin
	add_child(_sprite)


## Hex the entrance opens from (buildings), or null.
func door_hex(grid: HexGrid) -> Variant:
	return PropDef.door_hex(def, cells, anchor, grid.radius, look_index)


func _update_modulate() -> void:
	var c := Color(1.25, 1.2, 1.05) if highlighted else Color.WHITE
	c.a = 0.45 if faded else 1.0
	modulate = c


func display_name() -> String:
	return str(extra.get("name", extra.get("title", def.display_name)))


func is_interactable() -> bool:
	return not def.interaction.is_empty()


## World-space rectangle covered by the sprite.
func sprite_rect() -> Rect2:
	return Rect2(global_position + _sprite.offset, _sprite.texture.get_size())


## Walkable hexes touching the footprint: where a character stands to interact.
func approach_hexes(grid: HexGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		for n in Hex.neighbors(c):
			if not cells.has(n) and not out.has(n) and grid.is_walkable(n):
				out.append(n)
	return out


func is_adjacent_to(h: Vector2i) -> bool:
	for c in cells:
		if Hex.distance(c, h) == 1:
			return true
	return false


## Runs this prop's interaction for `actor`. Extend the match for new kinds.
func interact(_actor: Node) -> void:
	match def.interaction:
		"read":
			Events.message_requested.emit(str(extra.get("title", display_name())),
					str(extra.get("text", "The writing is too faded to read.")))
		_:
			push_warning("Prop %s has unknown interaction '%s'" % [name, def.interaction])
