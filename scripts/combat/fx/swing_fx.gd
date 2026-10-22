class_name SwingFx
extends Node2D
## A melee blow as a smear of motion, drawn in screen space:
##
##   slash   a wide sideways crescent swept around the shoulder, past the aim
##   smash   a tall arc from overhead down onto the target (maces, hammers)
##   thrust  a straight jab towards the target (daggers, rapiers, spears)
##   punch   a short jab with a small ring at its end (no weapon)
##   bite    two jaws snapping shut on the target (drawn at the target)
##   claw    three raking lines across the target (drawn at the target)
##
## The crescent is bright and thick at its leading edge and thins and fades
## behind it, like a motion blur. The weapon's own inventory icon rides the
## leading edge, half transparent, so the smear reads as that weapon's swing
## rather than a second weapon. `progress` (0 to 1) sweeps it; `fade` (1 to 0)
## dissolves it; spawn() tweens both and frees the node.

## Inventory icons show weapons lying diagonally, blade up and to the right.
const ICON_ANGLE := -PI / 4.0
const POINTS := 18

var style: String = "slash"
var color: Color = Color(1, 1, 1)
var icon: Texture2D
## Arc radius (or jab length) in pixels.
var radius: float = 40.0
## Direction towards the target (radians, screen space).
var aim: float = 0.0
## Which way a slash sweeps: 1 clockwise on screen, -1 the other way.
var turn: float = 1.0
var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()
var fade: float = 1.0:
	set(value):
		fade = value
		queue_redraw()


## Plays a swing at `at` (the shoulder; the target for bites and claws).
static func spawn(parent: Node, at: Vector2, aim_angle: float, style_name: String, tint: Color, weapon_icon: Texture2D,
		size: float, seconds: float) -> SwingFx:
	var f := SwingFx.new()
	f.position = at
	f.aim = aim_angle
	f.style = style_name
	f.color = tint
	f.icon = weapon_icon
	f.radius = size
	# Swing across the body: sweeping down on the side the target is.
	f.turn = 1.0 if cos(aim_angle) >= 0.0 else -1.0
	f.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "progress", 1.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "fade", 0.0, 0.2)
	tw.tween_callback(f.queue_free)
	return f


func _draw() -> void:
	match style:
		"thrust", "punch":
			_draw_jab()
		"bite":
			_draw_bite()
		"claw":
			_draw_claw()
		_:
			_draw_arc()


## The start and end angle of the sweep, the end unwrapped so that going from
## start to end turns the way `turn` says (not just the shorter way round,
## which would swing a mace over the wrong shoulder).
func _sweep() -> Vector2:
	var start := aim - 1.25 * turn
	var finish := aim + 1.0 * turn
	if style == "smash":
		# From overhead (straight up is -PI/2) down past the aim.
		start = -PI / 2.0 - 0.25 * turn
		finish = aim + 0.35 * turn
	while turn > 0.0 and finish < start:
		finish += TAU
	while turn < 0.0 and finish > start:
		finish -= TAU
	return Vector2(start, finish)


func _draw_arc() -> void:
	var sw := _sweep()
	var lead := lerpf(sw.x, sw.y, progress)
	var tail := lerpf(sw.x, sw.y, maxf(0.0, progress - 0.6))
	var thick := radius * (0.42 if style == "smash" else 0.34)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var colors := PackedColorArray()
	for i in POINTS + 1:
		var u := float(i) / POINTS  # 0 at the tail, 1 at the leading edge
		var a := lerpf(tail, lead, u)
		var dir := Vector2.from_angle(a) * Vector2(1.0, 0.82)  # a little flattened, as seen from above
		outer.append(dir * radius)
		inner.append(dir * (radius - thick * u * u))
	var poly := PackedVector2Array()
	for i in POINTS + 1:
		poly.append(outer[i])
		colors.append(Color(color, 0.85 * pow(float(i) / POINTS, 1.6) * fade))
	for i in range(POINTS, -1, -1):
		poly.append(inner[i])
		colors.append(Color(color, 0.35 * pow(float(i) / POINTS, 2.0) * fade))
	if poly.size() >= 3 and lead != tail:
		draw_polygon(poly, colors)
		draw_polyline(outer.slice(POINTS >> 1), Color(1, 1, 1, 0.7 * fade), 2.0, true)
	_draw_icon(Vector2.from_angle(lead) * Vector2(1.0, 0.82) * radius * 0.62, lead)


func _draw_jab() -> void:
	var dir := Vector2.from_angle(aim)
	var reach := radius * (1.25 if style == "thrust" else 0.7)
	var tip := dir * (8.0 + reach * progress)
	var back := dir * (8.0 + reach * maxf(0.0, progress - 0.55))
	var side := Vector2(-dir.y, dir.x) * (radius * (0.1 if style == "thrust" else 0.16))
	draw_colored_polygon(PackedVector2Array([back + side, tip, back - side]), Color(color, 0.75 * fade))
	draw_line(back, tip, Color(1, 1, 1, 0.8 * fade), 2.0, true)
	if style == "punch":
		draw_arc(tip, 4.0 + 6.0 * progress, 0.0, TAU, 16, Color(color, 0.8 * fade), 2.0, true)
	_draw_icon(tip - dir * 11.0, aim)


## The weapon's icon at `at`, its blade pointing along `angle`.
func _draw_icon(at: Vector2, angle: float) -> void:
	if icon == null:
		return
	var s := clampf(radius * 0.6, 16.0, 28.0)
	draw_set_transform(at, angle - ICON_ANGLE, Vector2.ONE)
	draw_texture_rect(icon, Rect2(Vector2(-s, -s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, 0.55 * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bite() -> void:
	# Upper and lower jaws, each a curved row of fangs, snapping shut on the
	# middle; outlined dark so they show on any ground.
	var gap := radius * 0.6 * (1.0 - progress) + 2.0
	var w := radius * 1.1
	var dark := Color(0.1, 0.05, 0.04, 0.8 * fade)
	var light := Color(color, fade)
	for sgn in [-1.0, 1.0]:  # -1: upper jaw (opens downwards), 1: lower
		var jaw := PackedVector2Array()
		for i in 9:
			var u := float(i) / 8.0
			jaw.append(Vector2(lerpf(-w / 2.0, w / 2.0, u), sgn * (gap + sin(u * PI) * radius * 0.35)))
		draw_polyline(jaw, dark, 5.0, true)
		draw_polyline(jaw, light, 2.5, true)
		for i in 4:
			var base := jaw[1 + i * 2]
			var fang := PackedVector2Array([base + Vector2(-3.0, 0), base + Vector2(3.0, 0),
					base + Vector2(0, -sgn * (7.0 if i in [0, 3] else 5.0))])
			draw_colored_polygon(fang, light)
			draw_polyline(PackedVector2Array([fang[0], fang[2], fang[1]]), dark, 1.2, true)


func _draw_claw() -> void:
	var dir := Vector2.from_angle(aim + 0.6)
	var side := Vector2(-dir.y, dir.x)
	for k in 3:
		var u := clampf(progress * 1.4 - k * 0.2, 0.0, 1.0)
		var start := side * (k - 1) * 7.0 - dir * radius * 0.5
		draw_line(start, start + dir * radius * u, Color(color, 0.9 * fade), 3.0, true)
