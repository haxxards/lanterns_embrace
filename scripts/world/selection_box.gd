class_name SelectionBox
extends Node2D
## Rubber-band rectangle for drag-selecting party members (world space).

var rect := Rect2()
var active: bool = false:
	set(value):
		active = value
		queue_redraw()


func set_rect(r: Rect2) -> void:
	rect = r.abs()
	queue_redraw()


func _draw() -> void:
	if active:
		draw_rect(rect, Color(0.35, 0.95, 0.45, 0.12), true)
		draw_rect(rect, Color(0.35, 0.95, 0.45, 0.9), false, 1.5)
