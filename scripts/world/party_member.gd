class_name PartyMember
extends Node2D
## A party member's token on the map: walks hex to hex along a path.
##
## `hex` is the member's logical cell. While walking it is the cell being
## entered, so a new order issued mid-step continues smoothly from there.

signal arrived(member: PartyMember)
signal hex_entered(member: PartyMember, hex: Vector2i)

const SELECT_COLOR := Color(0.35, 0.95, 0.45)
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const RING_RX := 19.0
const RING_RY := 9.0

var sheet: CharacterSheet
var hex: Vector2i
## Final hex of the current path (equals `hex` when idle).
var destination: Vector2i
var path: Array[Vector2i] = []
## Prop to interact with on arrival, if any.
var pending_interaction: Prop = null

var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()
var hovered: bool = false:
	set(value):
		hovered = value
		queue_redraw()

var _grid: HexGrid
var _sprite: Sprite2D
var _moving: bool = false
var _walk_time: float = 0.0


func setup(character: CharacterSheet, grid: HexGrid, start: Vector2i) -> void:
	sheet = character
	_grid = grid
	name = "Member_%s" % character.id
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_sprite = Sprite2D.new()
	_sprite.texture = Data.load_texture(character.sprite_path)
	_sprite.centered = false
	var size := _sprite.texture.get_size()
	var origin: Vector2 = character.sprite_origin if character.sprite_origin != null \
			else Vector2(size.x * 0.5, size.y - 6.0)
	_sprite.offset = -origin
	add_child(_sprite)
	place_at(start)


## Teleports to `h`, cancelling any movement.
func place_at(h: Vector2i) -> void:
	hex = h
	destination = h
	path.clear()
	_moving = false
	position = _grid.hex_to_world(h)
	_sprite.position = Vector2.ZERO


## Starts walking `new_path` (which excludes the current hex).
func follow_path(new_path: Array[Vector2i]) -> void:
	path = new_path.duplicate()
	destination = path.back() if not path.is_empty() else hex
	_moving = true


func stop() -> void:
	path.clear()
	destination = hex


func is_moving() -> bool:
	return _moving


## World rectangle used for mouse picking (sprite plus the hex below it).
func pick_rect() -> Rect2:
	return Rect2(global_position + _sprite.offset, _sprite.texture.get_size()).grow(2.0)


func _process(delta: float) -> void:
	if not _moving:
		return
	_walk_time += delta
	var budget := GameConfig.explore_move_speed * delta
	while budget > 0.0:
		var target := _grid.hex_to_world(hex)
		# Difficult terrain is walked at reduced speed so the cost is visible.
		var slow := maxf(1.0, _grid.move_cost(hex))
		var dist := position.distance_to(target)
		if dist * slow <= budget:
			position = target
			budget -= dist * slow
			if path.is_empty():
				_finish_walk()
				break
			hex = path.pop_front()
			hex_entered.emit(self, hex)
		else:
			_face(target.x - position.x)
			position = position.move_toward(target, budget / slow)
			budget = 0.0
	if _moving:
		_sprite.position.y = -absf(sin(_walk_time * 11.0)) * 2.5


func _finish_walk() -> void:
	_moving = false
	_sprite.position = Vector2.ZERO
	destination = hex
	arrived.emit(self)


func _face(dx: float) -> void:
	if absf(dx) > 0.5:
		_sprite.flip_h = dx < 0.0


func _draw() -> void:
	_draw_ellipse(Vector2(0, 1), RING_RX - 3.0, RING_RY - 1.5, Color(0, 0, 0, 0.35), true)
	if selected:
		_draw_ellipse(Vector2(0, 1), RING_RX, RING_RY, SELECT_COLOR, false, 2.0)
	elif hovered:
		_draw_ellipse(Vector2(0, 1), RING_RX, RING_RY, HOVER_COLOR, false, 1.5)


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
