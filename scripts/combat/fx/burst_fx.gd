class_name BurstFx
extends Node2D
## A flash where something lands or gathers, drawn in screen space:
##
##   hit     a quick flash and a spray of sparks of different lengths
##   charge  a glow swelling at a caster's hand or staff before a spell leaves
##   dust    a flattened ring on the ground (a heavy blow, a missed arrow)
##   shatter shards of light flying apart and a broken ring (a spell resisted
##           or shaken off: Hold Person)
##
## `size` scales it (a critical hit is bigger). `progress` (0 to 1) plays it;
## spawn() tweens it and frees the node.

var style: String = "hit"
var color: Color = Color(1, 1, 1)
var size: float = 1.0
var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()
## Fixed spark directions and lengths, so a burst doesn't flicker as it redraws.
var _sparks := PackedFloat32Array()
var _lengths := PackedFloat32Array()


static func spawn(parent: Node, at: Vector2, style_name: String, tint: Color, scale_by: float = 1.0,
		seconds: float = 0.3) -> BurstFx:
	var f := BurstFx.new()
	f.position = at
	f.style = style_name
	f.color = tint
	f.size = scale_by
	for i in 8:
		f._sparks.append(TAU * i / 8.0 + randf_range(-0.35, 0.35))
		f._lengths.append(randf_range(5.0, 14.0))
	f.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "progress", 1.0, maxf(0.01, seconds)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(f.queue_free)
	return f


func _draw() -> void:
	var a := 1.0 - progress
	match style:
		"charge":
			# Swells for the first two thirds, then fades as the spell leaves.
			var grow := minf(1.0, progress * 1.5)
			var r := 4.0 + 10.0 * grow * size
			var alpha := 1.0 if progress < 0.66 else (1.0 - progress) * 3.0
			draw_circle(Vector2.ZERO, r * 1.8, Color(color, 0.2 * alpha))
			draw_circle(Vector2.ZERO, r, Color(color, 0.55 * alpha))
			draw_circle(Vector2.ZERO, r * 0.45, Color(color.lightened(0.7), alpha))
		"shatter":
			var r := (8.0 + 22.0 * progress) * size
			for i in _sparks.size():  # the ring, broken into pieces flying outwards
				var mid := _sparks[i]
				draw_arc(Vector2.ZERO, r, mid - 0.22, mid + 0.22, 4, Color(color, 0.9 * a), 2.5, true)
				var d := Vector2.from_angle(mid + 0.4)
				draw_line(d * r * 0.6, d * (r * 0.6 + _lengths[i] * 0.6), Color(color.lightened(0.5), a), 1.5, true)
		"dust":
			var r := (8.0 + 18.0 * progress) * size
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(color, 0.6 * a), 3.0 * a + 1.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_:
			# The flash is over in the first half; the sparks fly on and shrink.
			var flash := maxf(0.0, 1.0 - progress * 2.2)
			draw_circle(Vector2.ZERO, 13.0 * size * (0.6 + 0.4 * progress), Color(color, 0.22 * flash))
			draw_circle(Vector2.ZERO, 6.0 * size * (1.0 - 0.5 * progress), Color(color.lightened(0.75), 0.9 * flash))
			for i in _sparks.size():
				var d := Vector2.from_angle(_sparks[i])
				var r0 := (4.0 + 18.0 * progress) * size
				var r1 := r0 + _lengths[i] * size * a
				draw_line(d * r0, d * r1, Color(color.lightened(0.35), a), 1.6, true)
