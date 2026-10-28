class_name QuantityDialog
extends Control
## "How many?" for splitting a stack: a slider and a number box from 1 to the
## stack's size, OK and Cancel. Opened by Shift-dropping a stack (ItemSlot,
## PortraitCard). It sits on its own canvas layer over everything, keeps
## working while the game is paused, takes Enter and Esc for itself, and
## frees itself when answered.

signal chosen(count: int)
signal cancelled

var max_count: int = 1
var _slider: HSlider
var _spin: SpinBox
var _ok: Button
var _verb: String = "Move"
var _layer: CanvasLayer
var _syncing: bool = false


## Opens the dialog above `near` (any node in the tree): `title` names the
## item and what happens ("Drop how many Arrows?"), `verb` labels the OK
## button ("Drop 12"). It starts at half the stack, rounded up.
static func ask(near: Node, title: String, verb: String, count_max: int) -> QuantityDialog:
	var d := QuantityDialog.new()
	d.max_count = maxi(1, count_max)
	d._verb = verb
	d._layer = CanvasLayer.new()
	d._layer.layer = 90
	d._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	near.get_tree().root.add_child(d._layer)
	d._layer.add_child(d)
	d._build(title)
	return d


func _build(title: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind it is clickable meanwhile
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
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", UiTheme.GOLD)
	label.add_theme_font_size_override("font_size", 16)
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.max_value = max_count
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_slider)
	_spin = SpinBox.new()
	_spin.min_value = 1
	_spin.max_value = max_count
	_spin.step = 1
	_spin.select_all_on_focus = true
	row.add_child(_spin)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var cancel_b := Button.new()
	cancel_b.text = "Cancel"
	cancel_b.pressed.connect(cancel)
	buttons.add_child(cancel_b)
	_ok = Button.new()
	_ok.pressed.connect(confirm)
	buttons.add_child(_ok)
	_slider.value_changed.connect(_set_count)
	_spin.value_changed.connect(_set_count)
	_set_count(ceili(max_count / 2.0))
	_spin.get_line_edit().call_deferred("grab_focus")
	Audio.play_sfx("ui_open")


func count() -> int:
	return int(_spin.value)


func _set_count(v: float) -> void:
	if _syncing:
		return
	_syncing = true  # the slider and the box set each other; once is enough
	var n := clampi(int(v), 1, max_count)
	_slider.value = n
	_spin.value = n
	_spin.get_line_edit().text = str(n)  # a focused box keeps its old text otherwise
	_ok.text = "%s %d" % [_verb, n]
	_syncing = false


func set_count(n: int) -> void:
	_set_count(n)


func confirm() -> void:
	if _layer == null:
		return  # already answered
	_spin.apply()  # a number typed but not yet entered
	var n := count()
	_close()
	chosen.emit(n)


func cancel() -> void:
	if _layer == null:
		return
	_close()
	cancelled.emit()


func _close() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
		_layer = null


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		confirm()
