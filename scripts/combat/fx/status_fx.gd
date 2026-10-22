class_name StatusFx
extends Node2D
## A condition shown on a figure for as long as it lasts. It is a child of the
## Actor, so it follows it, and it finds the head and body from the sprite
## sheet's anchors every frame (they move when the figure lies down):
##
##   asleep  "z Z z" drifting up from the head, slowly, over and over (Sleep)
##   held    three bands of violet light around the body, the back of each
##           fainter than the front so they seem to wrap round it, pulsing,
##           with a bright glint running round each (Hold Person)
##
## Actor.show_status() adds and removes them; the Actor also lays a sleeper
## down and tints a held figure.

const SLEEP_COLOR := Color(0.78, 0.86, 1.0)
const HOLD_COLOR := Color("c9a8ff")
## Seconds for one "z" to rise and fade.
const Z_CYCLE := 2.1

var kind: String = "asleep"
var actor: Actor
var _time: float = 0.0
var _head := Vector2(0, -50)
var _height: float = 50.0


static func create(a: Actor, kind_name: String) -> StatusFx:
	var f := StatusFx.new()
	f.actor = a
	f.kind = kind_name
	f.z_index = 5
	f._time = randf() * Z_CYCLE  # sleepers side by side don't snore in time
	return f


func _process(delta: float) -> void:
	_time += delta
	if actor != null and is_instance_valid(actor):
		_head = actor.anchor("head") - actor.global_position
		var center := actor.anchor("center") - actor.global_position
		_height = clampf(absf(center.y) * 2.0, 24.0, 90.0)
	queue_redraw()


func _draw() -> void:
	match kind:
		"held":
			_draw_bands()
		_:
			_draw_zzz()


## Three letters, each a third of a cycle behind the last, rising up and to
## the right of the head, growing as they go and fading at both ends.
func _draw_zzz() -> void:
	var font := ThemeDB.fallback_font
	for k in 3:
		var u := fposmod(_time / Z_CYCLE + k / 3.0, 1.0)
		var pos := _head + Vector2(6.0 + 14.0 * u + sin(u * TAU) * 3.0, -8.0 - 26.0 * u)
		var size := int(lerpf(10.0, 18.0, u))
		var alpha := sin(u * PI)
		var letter := "Z" if k == 1 else "z"
		draw_string_outline(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3,
				Color(0.05, 0.05, 0.12, 0.7 * alpha))
		draw_string(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SLEEP_COLOR, alpha))


## Bands round the body at three heights. Each is an ellipse (the ground seen
## from 45 degrees up makes circles look flat): its far half is drawn faint,
## its near half bright, and a short bright arc runs round it.
func _draw_bands() -> void:
	var rx := clampf(_height * 0.36, 10.0, 24.0)
	var ry := rx * 0.36
	var pulse := 0.75 + 0.25 * sin(_time * 4.0)
	for k in 3:
		var y := -_height * (0.2 + 0.3 * k)
		var center := Vector2(0, y)
		var phase := _time * (2.2 + k * 0.4) + k * 2.1
		_ellipse_arc(center, rx, ry, PI, TAU, Color(HOLD_COLOR, 0.3 * pulse), 2.0)   # behind
		_ellipse_arc(center, rx, ry, 0.0, PI, Color(HOLD_COLOR, 0.85 * pulse), 2.5)  # in front
		_ellipse_arc(center, rx, ry, phase, phase + 0.8, Color(1, 1, 1, 0.9 * pulse), 3.0)


## Part of an ellipse from angle a0 to a1 (0 is to the right, PI/2 the front).
func _ellipse_arc(center: Vector2, rx: float, ry: float, a0: float, a1: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, color, width, true)
