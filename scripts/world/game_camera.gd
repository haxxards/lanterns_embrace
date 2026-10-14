class_name GameCamera
extends Camera2D
## RTS-style camera: keyboard/edge panning, middle-drag, zoom towards cursor.
## Runs while the game is paused so the player can look around.

## Screen pixels covered by UI on the right edge (the party sidebar).
var right_ui_width: float = 0.0
var bounds := Rect2()

var _drag_panning: bool = false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	zoom = Vector2.ONE * GameConfig.camera_zoom_default
	Events.camera_focus_requested.connect(center_on)


func set_bounds(rect: Rect2) -> void:
	bounds = rect
	_clamp()


func center_on(world_pos: Vector2, instant: bool = false) -> void:
	# Account for the sidebar so the point lands in the middle of the open area.
	var target := world_pos + Vector2(right_ui_width * 0.5 / zoom.x, 0.0)
	if _tween:
		_tween.kill()
	if instant:
		position = target
		_clamp()
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", _clamped(target), 0.35)


func _process(delta: float) -> void:
	var dir := Input.get_vector("cam_pan_left", "cam_pan_right", "cam_pan_up", "cam_pan_down")
	if dir == Vector2.ZERO and GameConfig.camera_edge_pan and not _drag_panning:
		dir = _edge_direction()
	if dir != Vector2.ZERO:
		if _tween:
			_tween.kill()
		position += dir * GameConfig.camera_pan_speed * delta / zoom.x
		_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(mb.position, 1.0 + GameConfig.camera_zoom_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(mb.position, 1.0 / (1.0 + GameConfig.camera_zoom_step))
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_panning = mb.pressed
	elif event is InputEventMouseMotion and _drag_panning:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp()
	elif event.is_action_pressed("cam_zoom_in"):
		zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.0 + GameConfig.camera_zoom_step)
	elif event.is_action_pressed("cam_zoom_out"):
		zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.0 / (1.0 + GameConfig.camera_zoom_step))


## Zooms by `factor`, keeping the world point under `screen_point` fixed.
func zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := _screen_to_world(screen_point)
	var z := clampf(zoom.x * factor, GameConfig.camera_zoom_min, GameConfig.camera_zoom_max)
	zoom = Vector2(z, z)
	position += before - _screen_to_world(screen_point)
	_clamp()


## Screen pixel -> world position (camera is centred, unrotated).
func _screen_to_world(p: Vector2) -> Vector2:
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	return position + (p - size * 0.5) / zoom.x


func _edge_direction() -> Vector2:
	var vp := get_viewport()
	if not get_window().has_focus():
		return Vector2.ZERO
	var size := vp.get_visible_rect().size
	var m := vp.get_mouse_position()
	if m.x < 0 or m.y < 0 or m.x > size.x or m.y > size.y:
		return Vector2.ZERO
	var margin := GameConfig.camera_edge_margin
	var dir := Vector2.ZERO
	if m.x <= margin:
		dir.x = -1
	elif m.x >= size.x - margin:
		dir.x = 1
	if m.y <= margin:
		dir.y = -1
	elif m.y >= size.y - margin:
		dir.y = 1
	return dir


func _clamp() -> void:
	position = _clamped(position)


## Keeps the view over the map (with a little slack), allowing for the sidebar.
func _clamped(p: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO or not is_inside_tree():
		return p
	var view := get_viewport().get_visible_rect().size / zoom
	var slack := 40.0
	var ui := right_ui_width / zoom.x
	var min_x := bounds.position.x - slack + view.x * 0.5
	var max_x := bounds.end.x + slack + ui - view.x * 0.5
	var min_y := bounds.position.y - slack + view.y * 0.5
	var max_y := bounds.end.y + slack - view.y * 0.5
	var out := p
	out.x = clampf(p.x, min_x, max_x) if min_x <= max_x else (min_x + max_x) * 0.5
	out.y = clampf(p.y, min_y, max_y) if min_y <= max_y else (min_y + max_y) * 0.5
	return out
