class_name PortraitCard
extends PanelContainer
## Sidebar card for one party member: portrait, name, HP, quick stats.
## Click selects (Shift adds), double-click centres the camera on them.
## Dropping an item from the inventory screen on a card gives it to them.

signal pressed(card: PortraitCard, shift: bool)
signal double_pressed(card: PortraitCard)

const PORTRAIT_SIZE := Vector2(64, 80)

var member: PartyMember
var index: int = 0

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _hp_bar: ProgressBar
var _hp_label: Label
var _stats_label: Label
var _hovered: bool = false
var _selected: bool = false


func setup(m: PartyMember, i: int) -> void:
	member = m
	index = i
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, 96)
	_style_normal = UiTheme.panel_box(UiTheme.BG_LIGHT, UiTheme.BORDER, 2, 4, 6)
	_style_hover = UiTheme.panel_box(Color("342a1f"), UiTheme.BORDER_LIGHT, 2, 4, 6)
	_style_selected = UiTheme.panel_box(Color("23301f"), UiTheme.SELECTED, 2, 4, 6)
	add_theme_stylebox_override("panel", _style_normal)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var portrait := TextureRect.new()
	portrait.texture = Data.load_texture(m.sheet.portrait_path)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	var name_label := _label(m.sheet.display_name, 14, UiTheme.GOLD)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	name_row.add_child(_label(str(i + 1), 11, UiTheme.TEXT_DIM))  # hotkey hint
	col.add_child(_label(m.sheet.summary(), 11, UiTheme.TEXT_DIM))

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 14)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hp_bar)
	_hp_label = _label("", 10, UiTheme.TEXT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar.add_child(_hp_label)

	_stats_label = _label("", 11, UiTheme.TEXT_DIM)
	col.add_child(_stats_label)

	m.sheet.changed.connect(refresh)
	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))
	refresh()


func set_selected(value: bool) -> void:
	_selected = value
	_update_style()


func refresh() -> void:
	var s := member.sheet
	_hp_bar.max_value = s.hp_max
	_hp_bar.value = s.hp_current
	_hp_label.text = "HP %d / %d" % [s.hp_current, s.hp_max] if s.is_alive() else _down_text(s)
	modulate = Color.WHITE if s.is_alive() else Color(0.6, 0.55, 0.55)
	_stats_label.text = "AC %d   Speed %d ft" % [s.armor_class, s.effective_speed_ft()]


func _exit_tree() -> void:
	if member != null and is_instance_valid(member) and member.sheet.changed.is_connected(refresh):
		member.sheet.changed.disconnect(refresh)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("ref")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var err := InventoryOps.give(data["ref"], member.sheet)
	if not err.is_empty():
		Audio.play_sfx("error")
		Events.toast_requested.emit(err)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.double_click:
				double_pressed.emit(self)
			else:
				pressed.emit(self, mb.shift_pressed)
			accept_event()


func _on_hover_changed(value: bool) -> void:
	_hovered = value
	_update_style()


func _update_style() -> void:
	var sb := _style_selected if _selected else (_style_hover if _hovered else _style_normal)
	add_theme_stylebox_override("panel", sb)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Long text trims with "…" instead of widening the sidebar.
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	return l


## "Dead", "Unconscious (stable)" or "Dying" with the death saves so far.
func _down_text(s: CharacterSheet) -> String:
	if s.dead:
		return "Dead"
	if s.stable:
		return "Unconscious"
	return "Dying  %d✓ %d✗" % [s.death_successes, s.death_failures]
