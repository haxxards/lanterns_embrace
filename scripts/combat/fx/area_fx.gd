class_name AreaFx
extends Node2D
## An effect spread over an area of hexes, drawn in its parent's coordinates
## (the World's fx layer):
##
##   mist  a soft, glittering haze that drifts down over the area, lingers
##         and fades (Sleep)
##
## The hexes are filled edge to edge (so the haze has the same shape as the
## targeting preview), with a few soft wisps drifting over them and sparkles
## that twinkle at their own pace. The haze fades in over the first third of
## `progress`, holds, and fades out over the last third; spawn() tweens it
## and frees the node.

var style: String = "mist"
var color: Color = Color(0.6, 0.7, 1.0)
var radius: float = 30.0
var points := PackedVector2Array()
var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()
## Sparkle offsets and phases (fixed, so they don't jump as it redraws).
var _sparks := PackedVector2Array()
var _phases := PackedFloat32Array()


static func spawn(parent: Node, hex_centers: PackedVector2Array, hex_radius: float, tint: Color,
		seconds: float) -> AreaFx:
	var f := AreaFx.new()
	f.points = hex_centers
	f.radius = hex_radius
	f.color = tint
	for p in hex_centers:
		for k in 3:
			f._sparks.append(p + Vector2(randf_range(-0.7, 0.7), randf_range(-0.5, 0.5)) * hex_radius)
			f._phases.append(randf() * TAU)
	f.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "progress", 1.0, maxf(0.01, seconds))
	tw.tween_callback(f.queue_free)
	return f


func _draw() -> void:
	var fade := minf(1.0, minf(progress * 3.0, (1.0 - progress) * 3.0))
	var drift := Vector2(0, -10.0 + 14.0 * progress)  # settles downwards
	for p in points:
		draw_colored_polygon(Hex.corners(p, radius), Color(color, 0.14 * fade))
	for i in range(0, points.size(), 3):  # wisps
		var w := points[i] + drift * 2.0 + Vector2(sin(progress * 3.0 + i) * 8.0, 0)
		draw_set_transform(w, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, radius * 1.3, Color(color.lightened(0.4), 0.08 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in _sparks.size():
		var twinkle := 0.5 + 0.5 * sin(progress * 14.0 + _phases[i])
		var at := _sparks[i] + drift * 1.5
		draw_circle(at, 1.6 + 1.2 * twinkle, Color(1, 1, 1, 0.8 * twinkle * fade))
