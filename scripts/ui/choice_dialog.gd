class_name ChoiceDialog
extends Control
## A question with a few answers as buttons ("Disarm it", "Open it anyway",
## "Leave it"), for moments that need a decision outside dialogue, such as
## a trap found on a chest. Like QuantityDialog it sits on its own canvas
## layer and frees itself when answered; it also pauses the game while open
## (restoring whatever pause state there was). Esc picks the last answer.

signal chosen(index: int)

var _layer: CanvasLayer
var _was_paused: bool = false
var _count: int = 0


## Opens the dialog: `title` in gold, `text` under it, one button per entry
## of `answers` (in order; the first is focused).
static func ask(near: Node, title: String, text: String, answers: PackedStringArray) -> ChoiceDialog:
	var d := ChoiceDialog.new()
	d._layer = CanvasLayer.new()
	d._layer.layer = 90
	d._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	near.get_tree().root.add_child(d._layer)
	d._layer.add_child(d)
	d._was_paused = near.get_tree().paused
	near.get_tree().paused = true
	d._build(title, text, answers)
	return d


func _build(title: String, text: String, answers: PackedStringArray) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.build()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 14))
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := Label.new()
	head.text = title
	head.add_theme_color_override("font_color", UiTheme.GOLD)
	head.add_theme_font_size_override("font_size", 18)
	box.add_child(head)
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(410, 0)
	body.add_theme_color_override("font_color", UiTheme.TEXT)
	box.add_child(body)
	_count = answers.size()
	for i in answers.size():
		var b := Button.new()
		b.text = answers[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(choose.bind(i))
		box.add_child(b)
		if i == 0:
			b.call_deferred("grab_focus")
	Audio.play_sfx("ui_open")


## Answers with `index` (what a button press does).
func choose(index: int) -> void:
	if _layer == null:
		return  # already answered
	var tree := get_tree()
	_layer.queue_free()
	_layer = null
	tree.paused = _was_paused
	chosen.emit(index)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		choose(_count - 1)
