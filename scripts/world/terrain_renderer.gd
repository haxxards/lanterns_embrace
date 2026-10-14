class_name TerrainRenderer
extends Node2D
## Draws the hex terrain as textured polygons, in chunks for view culling.
##
## Each hex samples its terrain texture in world space, so neighbouring hexes
## of the same terrain blend into one seamless surface; the hex shape only
## shows where terrain types meet. Any seamless texture can be dropped in.

const CHUNK_SIZE := 16  # chunk edge length in offset cells
## Hexes are drawn very slightly enlarged so float rounding never leaves cracks.
const OVERDRAW := 0.75


## One chunk of terrain. Godot caches the draw commands until queue_redraw().
class Chunk:
	extends Node2D

	var grid: HexGrid
	var cells: Array[Vector2i] = []

	func _draw() -> void:
		var r := grid.radius + OVERDRAW
		for h in cells:
			var t := grid.get_terrain(h)
			if t == null:
				continue
			var pts := Hex.corners(grid.hex_to_world(h), r)
			if t.texture:
				var tex_size := t.texture.get_size()
				var uvs := PackedVector2Array()
				for p in pts:
					uvs.append(p / tex_size)
				draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, t.texture)
			else:
				draw_colored_polygon(pts, t.minimap_color)


@warning_ignore("integer_division")
func build(grid: HexGrid) -> void:
	for child in get_children():
		child.queue_free()
	# Repeat lets world-space UVs run past 1.0 and wrap seamlessly.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var chunks := {}
	for i in grid.cell_count():
		var h := grid.hex_at_index(i)
		var o := Hex.axial_to_offset(h)
		var key := Vector2i(o.x / CHUNK_SIZE, o.y / CHUNK_SIZE)
		if not chunks.has(key):
			var chunk := Chunk.new()
			chunk.grid = grid
			chunk.name = "Chunk_%d_%d" % [key.x, key.y]
			chunks[key] = chunk
		chunks[key].cells.append(h)
	for key in chunks:
		add_child(chunks[key])
