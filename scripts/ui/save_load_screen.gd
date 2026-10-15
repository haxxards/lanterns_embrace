class_name SaveLoadScreen
extends PanelContainer
## The save and load menus: one row per slot with a thumbnail, the save's
## name, map, date, play time and party. Save mode adds a name field; saving
## over an existing slot asks once ("Overwrite?") before replacing it.

signal closed
signal save_requested(slot: String, label: String)
signal load_requested(slot: String)

const THUMB := Vector2(160, 90)

var saving: bool = true

var _title: Label
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _rows: VBoxContainer
var _armed_slot: String = ""  # slot whose "Overwrite?" was clicked once


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 14))
	custom_minimum_size = Vector2(720, 560)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", UiTheme.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var back := Button.new()
	back.text = "Back  (Esc)"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(close)
	head.add_child(back)
	_name_row = HBoxContainer.new()
	_name_row.add_theme_constant_override("separation", 8)
	root.add_child(_name_row)
	var l := Label.new()
	l.text = "Save name"
	_name_row.add_child(l)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_row.add_child(_name_edit)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)


func open(save_mode: bool, default_name: String = "") -> void:
	saving = save_mode
	_title.text = "Save Game" if saving else "Load Game"
	_name_row.visible = saving
	_name_edit.text = default_name
	_armed_slot = ""
	_rebuild()
	visible = true


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _rebuild() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for slot in SaveManager.slot_ids():
		if saving and slot == SaveManager.QUICKSAVE:
			continue  # the quicksave is written with F5 only
		_rows.add_child(_make_row(SaveManager.describe_slot(slot)))


func _make_row(info: Dictionary) -> Control:
	var slot: String = info["slot"]
	var exists: bool = info["exists"]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG_LIGHT, UiTheme.BORDER, 1, 4, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.panel_box(Color("15110d"), UiTheme.BORDER, 1, 2, 0))
	row.add_child(frame)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = THUMB
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.texture = SaveManager.load_thumbnail(slot) if exists else null
	frame.add_child(thumb)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var slot_name := "Quicksave" if slot == SaveManager.QUICKSAVE else "Slot %s" % slot.trim_prefix("slot_")
	var title := Label.new()
	title.add_theme_color_override("font_color", UiTheme.GOLD if exists else UiTheme.TEXT_DIM)
	title.text = "%s  ·  %s" % [slot_name, info.get("label", "")] if exists else "%s  ·  empty" % slot_name
	text.add_child(title)
	if exists:
		var when := Time.get_datetime_string_from_unix_time(int(info.get("saved_at", 0)), true)
		var details := Label.new()
		details.add_theme_font_size_override("font_size", 12)
		details.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		details.text = "%s   ·   %s   ·   played %s\n%s" % [info.get("map_name", ""), when,
				SaveManager.format_playtime(int(info.get("playtime", 0))), ", ".join(info.get("party", []))]
		text.add_child(details)
	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(buttons)
	var main := Button.new()
	main.focus_mode = Control.FOCUS_NONE
	main.custom_minimum_size = Vector2(110, 0)
	if saving:
		main.text = "Overwrite?" if exists and _armed_slot == slot else "Save here"
		main.pressed.connect(_on_save_pressed.bind(slot, exists))
	else:
		main.text = "Load"
		main.disabled = not exists
		main.pressed.connect(func() -> void: load_requested.emit(slot))
	buttons.add_child(main)
	if exists:
		var del := Button.new()
		del.text = "Delete"
		del.focus_mode = Control.FOCUS_NONE
		del.pressed.connect(_on_delete.bind(slot))
		buttons.add_child(del)
	return panel


func _on_save_pressed(slot: String, exists: bool) -> void:
	if exists and _armed_slot != slot:
		_armed_slot = slot
		_rebuild()
		return
	_armed_slot = ""
	save_requested.emit(slot, _name_edit.text)


func _on_delete(slot: String) -> void:
	SaveManager.delete_slot(slot)
	_rebuild()
