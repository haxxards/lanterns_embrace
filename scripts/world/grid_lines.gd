class_name GridLines
extends Node2D
## Faint hex outlines over walkable ground. Built once per map, toggled with G.

var line_color := Color(0.0, 0.0, 0.0, 0.3)
var _segments := PackedVector2Array()


func build(grid: HexGrid) -> void:
	_segments.clear()
	for i in grid.cell_count():
		var h := grid.hex_at_index(i)
		if not grid.is_walkable(h):
			continue
		var pts := Hex.corners(grid.hex_to_world(h), grid.radius)
		for e in 6:
			# Each shared edge is drawn once: by its east/south side owner, or by
			# this hex when the neighbour across the edge has no grid line.
			var other := Hex.neighbor(h, Hex.EDGE_DIRECTION[e])
			if e < 3 or not grid.is_walkable(other):
				_segments.append(pts[e])
				_segments.append(pts[(e + 1) % 6])
	queue_redraw()


func _draw() -> void:
	if _segments.size() >= 2:
		draw_multiline(_segments, line_color, 1.0)
