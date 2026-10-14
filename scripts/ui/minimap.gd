class_name Minimap
extends Control
## Overview of the current map: terrain and props baked into a small image,
## live party dots and the camera's view rectangle. Click or drag to pan.

const IMAGE_WIDTH := 256

## On-screen width; height follows the map's aspect ratio.
var display_width: float = 188.0
var world: World
var _texture: ImageTexture
var _dragging: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func bind(w: World) -> void:
	world = w
	rebuild()


## Re-bakes the terrain image. Call after the map changes.
func rebuild() -> void:
	if world == null or world.grid == null:
		return
	var grid := world.grid
	var bounds := grid.world_bounds()
	var img_w := IMAGE_WIDTH
	var img_h := maxi(1, roundi(IMAGE_WIDTH * bounds.size.y / bounds.size.x))
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var bg := world.map.background_color
	for y in img_h:
		for x in img_w:
			var p := bounds.position + Vector2((x + 0.5) / img_w, (y + 0.5) / img_h) * bounds.size
			var h := grid.world_to_hex(p)
			var col := bg
			var t := grid.get_terrain(h)
			if t:
				col = t.minimap_color
				var prop: Prop = world.props_by_hex.get(h)
				if prop:
					col = prop.def.minimap_color
			img.set_pixel(x, y, col)
	_texture = ImageTexture.create_from_image(img)
	custom_minimum_size = Vector2(display_width, roundf(display_width * img_h / img_w))
	queue_redraw()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.6))
	if _texture == null or world == null or world.grid == null:
		return
	draw_texture_rect(_texture, r, false)
	for m in world.party.members:
		var p := _world_to_mini(m.global_position)
		draw_circle(p, 3.2, Color(0, 0, 0, 0.8))
		draw_circle(p, 2.2, UiTheme.SELECTED if m.selected else Color.WHITE)
	var cam := world.camera
	var view := get_viewport_rect().size / cam.zoom
	var tl := _world_to_mini(cam.position - view * 0.5)
	var br := _world_to_mini(cam.position + view * 0.5)
	draw_rect(Rect2(tl, br - tl).intersection(r), Color(1, 1, 1, 0.9), false, 1.0)
	draw_rect(r, UiTheme.BORDER_LIGHT, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if world == null or world.grid == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_pan_to(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan_to(event.position)
		accept_event()


func _pan_to(local: Vector2) -> void:
	world.camera.center_on(_mini_to_world(local), true)


func _world_to_mini(p: Vector2) -> Vector2:
	var b := world.grid.world_bounds()
	return (p - b.position) / b.size * size


func _mini_to_world(p: Vector2) -> Vector2:
	var b := world.grid.world_bounds()
	return b.position + p / size * b.size
