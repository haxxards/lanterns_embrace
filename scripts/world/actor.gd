class_name Actor
extends Node2D
## Anything that walks the hex grid with an animated sprite: party members
## (PartyMember) and townsfolk (Npc). Handles the sprite-sheet animation
## (8 facings, walk frames advanced by distance), walking along hex paths, and
## the shadow and ring under the feet. Subclasses decide speed and rings.
##
## Paths come from the hex grid, but while exploring the walk is smoothed:
## the actor heads straight for the farthest path hex it can reach in a clear
## line (no blocked or costlier ground in between), so movement looks like
## free walking rather than hex-to-hex zig-zags. Walks always end on a hex
## centre. `hex` is the hex currently under the actor's feet.

signal arrived(actor: Actor)
signal hex_entered(actor: Actor, hex: Vector2i)

const RING_RX := 19.0
const RING_RY := 9.0
## Screen direction sectors (0 = east, clockwise) -> sheet row name and mirror.
const FACINGS := [["e", false], ["se", false], ["s", false], ["se", true],
		["e", true], ["ne", true], ["n", false], ["ne", false]]

var hex: Vector2i
## Final hex of the current path (equals `hex` when idle).
var destination: Vector2i
var path: Array[Vector2i] = []
## Straight-line smoothing; turn off for strict hex-by-hex steps (combat).
var smooth_paths: bool = true
## Marks the hex it stands on as taken in the grid, so others path around it
## (townsfolk and creatures always; party members during a fight).
var occupies: bool = false:
	set(value):
		if value == occupies:
			return
		occupies = value
		if _grid != null:
			_grid.set_occupied(hex, value)
var hovered: bool = false:
	set(value):
		hovered = value
		queue_redraw()

var _grid: HexGrid
var _sprite: Sprite2D
## Sprite-sheet animation (empty when the actor only has a static sprite).
var _anim: Dictionary = {}
var _facing: int = 1  # south-east
var _stride: float = 0.0
var _moving: bool = false
var _walk_time: float = 0.0
## Path hex currently walked towards in a straight line (null = pick one).
var _aim: Variant = null
## Where the sprite sits relative to the feet when standing still (moved for
## someone lying on the ground).
var _sprite_rest := Vector2.ZERO
## The combat body motion playing (nudge), if any.
var _nudge_tween: Tween
var _flash_tween: Tween


## Creates the sprite: an animation sheet if `animation_path` loads, else a
## static image with its feet at `sprite_origin` (or bottom-centre).
func _setup_sprite(animation_path: String, sprite_path: String, sprite_origin: Variant) -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	add_child(_sprite)
	if not _setup_animation(animation_path):
		_sprite.texture = Data.load_texture(sprite_path)
		var size := _sprite.texture.get_size()
		var origin: Vector2 = sprite_origin if sprite_origin != null else Vector2(size.x * 0.5, size.y - 6.0)
		_sprite.offset = -origin


## Loads a sprite sheet: rows are facings, columns idle + walk frames.
func _setup_animation(path: String) -> bool:
	if path.is_empty():
		return false
	var d: Variant = JsonUtil.load_json(path)
	if not d is Dictionary or not d.has("texture"):
		return false
	var tex := Data.load_texture(str(d["texture"]))
	if tex == Data.missing_texture():
		return false
	_anim = d
	_sprite.texture = tex
	_sprite.hframes = int(d.get("columns", 1))
	_sprite.vframes = (d.get("directions", ["se"]) as Array).size()
	_sprite.offset = -JsonUtil.to_vec2(d.get("origin"), Vector2.ZERO)
	_update_frame()
	return true


func is_animated() -> bool:
	return not _anim.is_empty()


## Shows the frame for the current facing and walk progress.
func _update_frame() -> void:
	if _anim.is_empty():
		return
	var facing: Array = FACINGS[_facing]
	var rows: Array = _anim.get("directions", [])
	var row := maxi(0, rows.find(facing[0]))
	var col := int(_anim.get("idle_column", 0))
	if _moving:
		var walk: Array = _anim.get("walk_columns", [])
		if not walk.is_empty():
			var cycle := maxf(1.0, float(_anim.get("cycle_px", 100.0)))
			col = int(walk[int(_stride / cycle * walk.size()) % walk.size()])
	_sprite.frame = row * _sprite.hframes + col
	_sprite.flip_h = facing[1]


## Teleports to `h`, cancelling any movement.
func place_at(h: Vector2i) -> void:
	if occupies and _grid != null:
		_grid.set_occupied(hex, false)
		_grid.set_occupied(h, true)
	hex = h
	destination = h
	path.clear()
	_aim = null
	_moving = false
	position = _grid.hex_to_world(h)
	_sprite.position = _sprite_rest
	_update_frame()


## Starts walking `new_path` (which excludes the current hex).
func follow_path(new_path: Array[Vector2i]) -> void:
	path = new_path.duplicate()
	destination = path.back() if not path.is_empty() else hex
	_aim = null
	_moving = true


## Stops at the centre of the current hex.
func stop() -> void:
	follow_path([])


func is_moving() -> bool:
	return _moving


## Walking speed in pixels per second. Subclasses override.
func move_speed() -> float:
	return GameConfig.explore_move_speed


## Turns to look at a world position (e.g. someone talking to us).
func face_towards(world_pos: Vector2) -> void:
	_face(world_pos - position)
	_update_frame()


## A point on the figure as a world position, for the current facing: "weapon"
## (the weapon hand), "off" (the other hand; archers hold their bow there),
## "focus" (a staff's crystal; else the weapon hand), "head" or "center".
## They come from the sheet's "anchors" (tools/art/blender/export_anchors.py),
## in pixels from the feet per facing row; mirrored facings flip x. Sprites
## without them get rough guesses from the sprite's size.
func anchor(kind: String) -> Vector2:
	var facing: Array = FACINGS[_facing]
	var rows: Array = _anim.get("directions", [])
	var row := rows.find(facing[0])
	var list: Variant = (_anim.get("anchors", {}) as Dictionary).get(kind)
	var off: Vector2
	if list is Array and row >= 0 and row < (list as Array).size():
		off = JsonUtil.to_vec2(list[row])
		if facing[1]:
			off.x = -off.x
	else:
		var h := _sprite.get_rect().size.y if _sprite != null and _sprite.texture != null else 56.0
		var side := -1.0 if _sprite != null and _sprite.flip_h else 1.0
		off = {"weapon": Vector2(0.22 * h * side, -0.45 * h), "off": Vector2(-0.22 * h * side, -0.45 * h),
				"focus": Vector2(0.22 * h * side, -0.5 * h), "head": Vector2(0, -0.9 * h)}.get(kind, Vector2(0, -0.5 * h))
	return global_position + (_sprite.position if _sprite != null else Vector2.ZERO) + off


## Combat body language (CombatFx): moves the sprite `offset` from where it
## rests, scaled by `squash` (about the feet), over `out_s` seconds; then,
## when `back_s` > 0, back to rest over `back_s`. The actor's hex and position
## don't change. nudge(Vector2.ZERO, t) settles it back.
func nudge(offset: Vector2, out_s: float, back_s: float = 0.0, squash: Vector2 = Vector2.ONE) -> void:
	if _sprite == null:
		return
	if _nudge_tween != null:
		_nudge_tween.kill()
	_nudge_tween = create_tween()
	_nudge_tween.set_parallel(true)
	_nudge_tween.tween_property(_sprite, "position", _sprite_rest + offset, maxf(0.01, out_s)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_nudge_tween.tween_property(_sprite, "scale", squash, maxf(0.01, out_s))
	if back_s > 0.0:
		_nudge_tween.chain().tween_property(_sprite, "position", _sprite_rest, back_s) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_nudge_tween.tween_property(_sprite, "scale", Vector2.ONE, back_s)


## Tints the sprite `color` (above 1 brightens) and fades back over `seconds`.
func flash(color: Color, seconds: float) -> void:
	if _sprite == null:
		return
	if _flash_tween != null:
		_flash_tween.kill()
	_sprite.self_modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "self_modulate", Color.WHITE, maxf(0.01, seconds))


## World rectangle used for mouse picking (sprite plus the hex below it).
func pick_rect() -> Rect2:
	var r := _sprite.get_rect()
	return Rect2(global_position + r.position, r.size).grow(2.0)


func _process(delta: float) -> void:
	if not _moving:
		return
	_walk_time += delta
	var budget := move_speed() * delta
	while budget > 0.0:
		if path.is_empty():
			# Settle on the centre of the hex we ended in.
			budget = _walk_towards(_grid.hex_to_world(hex), budget)
			if budget >= 0.0:
				_finish_walk()
			break
		if _aim == null:
			_aim = path[_farthest_clear_index()]
		budget = _walk_towards(_grid.hex_to_world(_aim), budget)
		if budget < 0.0:
			break
		# Reached the aim point: drop it and everything before it.
		path = path.slice(path.find(_aim) + 1)
		_aim = null
	if _moving:
		if is_animated():
			_update_frame()
		else:
			_sprite.position.y = -absf(sin(_walk_time * 11.0)) * 2.5


## Moves towards `target` using up to `budget` pixels of movement. Returns the
## budget left on arrival, or -1 if the target was not reached this frame.
## Difficult terrain is walked at reduced speed so its cost is visible.
func _walk_towards(target: Vector2, budget: float) -> float:
	var slow := maxf(1.0, _grid.move_cost(hex))
	var dist := position.distance_to(target)
	_face(target - position)
	if dist * slow <= budget:
		_stride += dist
		position = target
		_update_hex()
		return budget - dist * slow
	_stride += budget / slow
	position = position.move_toward(target, budget / slow)
	_update_hex()
	return -1.0


## Keeps `hex` in sync with the feet and trims path hexes already walked over.
func _update_hex() -> void:
	var h := _grid.world_to_hex(position)
	if h == hex or not _can_stand(h):
		return
	var old := hex
	hex = h
	_on_hex_changed(old, h)
	hex_entered.emit(self, hex)
	var i := path.find(h)
	var aim_i := path.find(_aim) if _aim != null else -1
	if i >= 0 and (aim_i < 0 or i < aim_i):
		path = path.slice(i + 1)


## Whether this actor may count `h` as its hex (walkable ground, and not
## taken by someone else).
func _can_stand(h: Vector2i) -> bool:
	if occupies:
		return _grid.is_ground_walkable(h) and (h == hex or not _grid.is_occupied(h))
	return _grid.is_walkable(h)


## Called when the feet cross into a new hex; moves the grid blocker along.
func _on_hex_changed(old: Vector2i, new: Vector2i) -> void:
	if occupies:
		_grid.set_occupied(old, false)
		_grid.set_occupied(new, true)


## Path to `to` from where it stands (its own hex counts as free).
func path_to(to: Vector2i) -> Array[Vector2i]:
	if occupies:
		_grid.set_occupied(hex, false)
	var p := _grid.find_path(hex, to)
	if occupies:
		_grid.set_occupied(hex, true)
	return p


## Index of the farthest upcoming path hex reachable in a straight, clear line.
func _farthest_clear_index() -> int:
	if not smooth_paths:
		return 0
	var best := 0
	var max_cost := _grid.move_cost(hex)
	for k in mini(path.size(), 12):
		max_cost = maxf(max_cost, _grid.move_cost(path[k]))
		if k > 0:
			if not _segment_clear(position, _grid.hex_to_world(path[k]), max_cost):
				break
			best = k
	return best


## True if a body walking from a to b only crosses walkable ground no costlier
## than `max_cost`, with a little clearance either side.
func _segment_clear(a: Vector2, b: Vector2, max_cost: float) -> bool:
	var length := a.distance_to(b)
	if length < 1.0:
		return true
	var dir := (b - a) / length
	var side := Vector2(-dir.y, dir.x) * _grid.radius * 0.3
	var step := _grid.radius * 0.3
	var t := 0.0
	while t <= length:
		var p := a + dir * t
		for offset in [Vector2.ZERO, side, -side]:
			var h := _grid.world_to_hex(p + offset)
			if not _can_stand(h) or _grid.move_cost(h) > max_cost + 0.001:
				return false
		t += step
	return true


func _finish_walk() -> void:
	_moving = false
	_sprite.position = _sprite_rest
	destination = hex
	_update_frame()
	arrived.emit(self)


## Turns towards a movement direction (screen space).
func _face(delta: Vector2) -> void:
	if delta.length() < 0.5:
		return
	if is_animated():
		_facing = posmod(roundi(delta.angle() / (PI / 4.0)), 8)
	elif absf(delta.x) > 0.5:
		_sprite.flip_h = delta.x < 0.0


## Shadow under the feet; subclasses add rings with _draw_ring().
func _draw() -> void:
	_draw_ellipse(Vector2(0, 1), RING_RX - 3.0, RING_RY - 1.5, Color(0, 0, 0, 0.35), true)


func _draw_ring(color: Color, width: float) -> void:
	_draw_ellipse(Vector2(0, 1), RING_RX, RING_RY, color, false, width)


func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color, filled: bool,
		width: float = 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		draw_polyline(pts, color, width, true)
