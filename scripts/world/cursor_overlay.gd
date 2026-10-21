class_name CursorOverlay
extends Node2D
## Ground-level feedback drawn under the characters: hovered hex, the path
## preview for the selected leader, where each walking member will stop, and
## a building's door zone (the hexes in front of its door that take you in).

const HOVER_OK := Color(1.0, 1.0, 1.0, 0.85)
const HOVER_BLOCKED := Color(0.95, 0.3, 0.25, 0.85)
const HOVER_INTERACT := Color(1.0, 0.82, 0.35, 0.95)
const PATH_COLOR := Color(0.55, 1.0, 0.55, 0.9)
const PATH_DIFFICULT := Color(1.0, 0.75, 0.3, 0.95)
const DEST_COLOR := Color(0.35, 0.95, 0.45, 0.7)
const REACH_FILL := Color(0.45, 0.85, 1.0, 0.13)
const DOOR_FILL := Color(1.0, 0.82, 0.35, 0.22)

var grid: HexGrid
var party: PartyController
var hover_hex: Variant = null
var hover_color := HOVER_OK
var preview_path: Array[Vector2i] = []
## In a fight: hexes the active combatant can still reach ({hex: cost}).
var reachable: Dictionary = {}
## A building's door zone, shown while the mouse is on the building (a hint)
## or on the zone itself (hot: a click goes in).
var door_zone: Array[Vector2i] = []
var door_zone_hot: bool = false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	var r := grid.radius
	for h in reachable:
		draw_colored_polygon(Hex.corners(grid.hex_to_world(h), r * 0.92), REACH_FILL)
	var strength := 1.0 if door_zone_hot else 0.55
	for h in door_zone:
		draw_colored_polygon(Hex.corners(grid.hex_to_world(h), r * 0.92), Color(DOOR_FILL, DOOR_FILL.a * strength))
		_hex_outline(h, r * 0.92, Color(HOVER_INTERACT, HOVER_INTERACT.a * strength), 2.0)
	if party:
		for m in party.members:
			if m.is_moving() and m.destination != m.hex:
				_hex_outline(m.destination, r * 0.62, DEST_COLOR, 2.0)
	for i in preview_path.size():
		var h := preview_path[i]
		var col := PATH_DIFFICULT if grid.move_cost(h) > 1.0 else PATH_COLOR
		if i == preview_path.size() - 1:
			_hex_outline(h, r * 0.8, col, 2.0)
		else:
			draw_circle(grid.hex_to_world(h), 3.5, col)
	if hover_hex != null:
		_hex_outline(hover_hex, r - 1.0, hover_color, 2.0)


func _hex_outline(h: Vector2i, radius: float, color: Color, width: float) -> void:
	var pts := Hex.corners(grid.hex_to_world(h), radius)
	pts.append(pts[0])
	draw_polyline(pts, color, width, true)
