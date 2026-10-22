class_name ProjectileFx
extends Node2D
## Something flying from an attacker to a target, drawn in screen space:
##
##   arrow   a shaft with a head and fletching, pointing the way it flies,
##           along a low arc
##   thrown  the weapon's own icon, spinning, along a higher arc
##   bolt    a glowing ball with a fading trail, in a straight line (spells)
##   dart    a small glowing streak with a long trail on a curving path
##           (Magic Missile: several fan out and converge on the target)
##   ribbon  a slow, broad streamer of light that curls on its way (Hold Person)
##
## The path is a quadratic Bézier curve: from `start` to `end`, pulled towards
## a `control` point. Raising the control point above the midpoint gives an
## arc; pushing it sideways gives a curve. `t` (0 to 1) is how far along it
## is; spawn() tweens it, after an optional delay, and frees the node at the
## end. The node stays at the origin of its parent and draws in its parent's
## coordinates.

const TRAIL := 14

var kind: String = "bolt"
var color: Color = Color(1, 1, 1)
var icon: Texture2D
var start: Vector2
var control: Vector2
var end: Vector2
var t: float = 0.0:
	set(value):
		t = value
		_trail.append(point(t))
		if _trail.size() > (TRAIL if kind in ["dart", "ribbon"] else TRAIL >> 1):
			_trail.remove_at(0)
		queue_redraw()
var fade: float = 1.0:
	set(value):
		fade = value
		queue_redraw()

var _trail := PackedVector2Array()


## Launches one. `arc` lifts the path's middle (pixels up), `bend` pushes it
## sideways (pixels, + to the left of the flight). Returns the node.
static func spawn(parent: Node, kind_name: String, from: Vector2, to: Vector2, tint: Color, item_icon: Texture2D,
		seconds: float, delay: float = 0.0, arc: float = 0.0, bend: float = 0.0) -> ProjectileFx:
	var f := ProjectileFx.new()
	f.kind = kind_name
	f.color = tint
	f.icon = item_icon
	f.start = from
	f.end = to
	var mid := (from + to) / 2.0
	var along := (to - from).normalized()
	f.control = mid + Vector2(0, -arc) + Vector2(along.y, -along.x) * bend
	f.process_mode = Node.PROCESS_MODE_PAUSABLE
	f.visible = delay <= 0.0
	parent.add_child(f)
	var tw := f.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(f.show)
	tw.tween_property(f, "t", 1.0, maxf(0.01, seconds))
	tw.tween_property(f, "fade", 0.0, 0.12)
	tw.tween_callback(f.queue_free)
	return f


## The point a fraction `u` of the way along the curve.
func point(u: float) -> Vector2:
	return start.lerp(control, u).lerp(control.lerp(end, u), u)


## Seconds to fly `from` -> `to` at `speed` pixels a second (at least `shortest`).
static func flight_time(from: Vector2, to: Vector2, speed: float, shortest: float = 0.12) -> float:
	return maxf(shortest, from.distance_to(to) / maxf(1.0, speed))


func _draw() -> void:
	if _trail.is_empty():
		return
	var p := _trail[_trail.size() - 1]
	var heading := (point(minf(1.0, t + 0.02)) - point(maxf(0.0, t - 0.02)))
	var angle := heading.angle() if heading.length() > 0.01 else (end - start).angle()
	match kind:
		"arrow":
			_draw_trail(1.5, 0.25)
			var d := Vector2.from_angle(angle)
			var side := Vector2(-d.y, d.x)
			draw_line(p - d * 30.0, p - d * 5.0, Color(0.1, 0.07, 0.04, 0.6 * fade), 4.0, true)  # dark edge
			draw_line(p - d * 30.0, p - d * 5.0, Color(0.55, 0.38, 0.22, fade), 2.5, true)
			draw_colored_polygon(PackedVector2Array([p, p - d * 9.0 + side * 4.5, p - d * 9.0 - side * 4.5]),
					Color(0.82, 0.84, 0.88, fade))
			for s in [-1.0, 1.0]:
				draw_line(p - d * 27.0, p - d * 34.0 + side * 5.0 * s, Color(0.9, 0.22, 0.16, fade), 2.5, true)
		"thrown":
			_draw_trail(1.0, 0.18)
			if icon != null:
				var size := 28.0
				draw_set_transform(p, t * TAU * 2.5, Vector2.ONE)
				draw_texture_rect(icon, Rect2(Vector2(-size, -size) / 2.0, Vector2(size, size)), false, Color(1, 1, 1, fade))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"ribbon":
			_draw_trail(7.0, 0.55)
			draw_circle(p, 9.0, Color(color, 0.3 * fade))
			draw_circle(p, 4.5, Color(color.lightened(0.6), fade))
		"dart":
			_draw_trail(4.0, 0.7)
			draw_circle(p, 7.0, Color(color, 0.3 * fade))
			draw_circle(p, 3.5, Color(color.lightened(0.6), fade))
		_:  # bolt
			_draw_trail(6.0, 0.55)
			draw_circle(p, 11.0, Color(color, 0.28 * fade))
			draw_circle(p, 6.5, Color(color, 0.8 * fade))
			draw_circle(p, 3.5, Color(color.lightened(0.7), fade))


## The recent path as a line that thins and fades towards its tail.
func _draw_trail(width: float, alpha: float) -> void:
	var n := _trail.size()
	for i in range(1, n):
		var u := float(i) / n
		var tint := Color(1, 1, 1) if kind == "arrow" or kind == "thrown" else color
		draw_line(_trail[i - 1], _trail[i], Color(tint, alpha * u * fade), maxf(1.0, width * u), true)
