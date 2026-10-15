class_name Hud
extends CanvasLayer
## In-game HUD: party sidebar (minimap + portraits), hover info, pause banner,
## toasts, sign/message box and the controls help. Built in code so the
## layout is easy to read and change in one place.

const SIDEBAR_WIDTH := 232.0
const HELP_TEXT := """[b]Controls[/b]
Left click ground  –  move selected
Left click member / portrait  –  select   (Shift: add)
Left drag  –  box select        Ctrl+A  –  select all
1-%d  –  select member        Right click  –  deselect
Left click a sign  –  walk over and read it
WASD / arrows / screen edge / middle drag  –  pan
Mouse wheel, + / -  –  zoom        C  –  centre on selection
Space  –  pause / resume        G  –  toggle grid
F3  –  hover info        F1  –  toggle this help"""

var world: World

var _root: Control
var _map_label: Label
var _minimap: Minimap
var _party_label: Label
var _cards_box: VBoxContainer
var _cards: Array[PortraitCard] = []
var _info_panel: PanelContainer
var _info_label: Label
var _help_panel: PanelContainer
var _pause_banner: PanelContainer
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _message_panel: PanelContainer
var _message_title: Label
var _message_body: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2  # above the colour grade (layer 1)
	var grade := ColorGrade.new()
	grade.name = "ColorGrade"
	add_child(grade)
	grade.setup(SIDEBAR_WIDTH)
	_build()
	Events.map_loaded.connect(_on_map_loaded)
	Events.selection_changed.connect(_on_selection_changed)
	Events.hover_info_changed.connect(_on_hover_info)
	Events.message_requested.connect(show_message)
	Events.toast_requested.connect(show_toast)
	Events.pause_changed.connect(func(p: bool) -> void: _pause_banner.visible = p)
	Events.party_order_issued.connect(func() -> void: _message_panel.visible = false)


func bind(w: World) -> void:
	world = w
	world.camera.right_ui_width = SIDEBAR_WIDTH


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help_panel.visible = not _help_panel.visible
	elif event.is_action_pressed("toggle_debug"):
		_info_panel.visible = not _info_panel.visible
	elif event.is_action_pressed("ui_cancel") and _message_panel.visible:
		_message_panel.visible = false
		get_viewport().set_input_as_handled()


# --- public ------------------------------------------------------------------------

func show_message(title: String, text: String) -> void:
	_message_title.text = title
	_message_body.text = text
	_message_panel.visible = true


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_toast.hide)


# --- signal handlers ------------------------------------------------------------

func _on_map_loaded(_map_id: String) -> void:
	_map_label.text = world.map.display_name
	_minimap.bind(world)
	_rebuild_cards()


func _rebuild_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for i in world.party.members.size():
		var card := PortraitCard.new()
		card.setup(world.party.members[i], i)
		card.pressed.connect(_on_card_pressed)
		card.double_pressed.connect(_on_card_double_pressed)
		_cards_box.add_child(card)
		_cards.append(card)
	_party_label.text = "Party  %d / %d" % [world.party.members.size(), GameConfig.max_party_size]
	_on_selection_changed(world.party.selected)


func _on_selection_changed(selected: Array) -> void:
	for c in _cards:
		c.set_selected(selected.has(c.member))


func _on_card_pressed(card: PortraitCard, shift: bool) -> void:
	if shift:
		world.party.toggle(card.member)
	else:
		world.party.select_only(card.member)


func _on_card_double_pressed(card: PortraitCard) -> void:
	world.party.select_only(card.member)
	world.camera.center_on(card.member.global_position)


func _on_hover_info(info: Dictionary) -> void:
	if not info.get("in_bounds", false):
		_info_label.text = "Outside the map"
		return
	var h: Vector2i = info["hex"]
	var cell: Vector2i = info["cell"]
	var lines := PackedStringArray()
	lines.append("Hex  q %d, r %d   (col %d, row %d)" % [h.x, h.y, cell.x, cell.y])
	if info.has("terrain"):
		var t := "%s   cost ×%s" % [info["terrain"], str(info["move_cost"])]
		if not info["walkable"]:
			t += "   (blocked)"
		lines.append(t)
	if info.has("member"):
		lines.append(str(info["member"]))
	elif info.has("prop"):
		lines.append(str(info["prop"]))
	if info.has("path_hexes"):
		lines.append("Path  %d hexes · %d ft" % [info["path_hexes"], info["path_feet"]])
	_info_label.text = "\n".join(lines)


# --- layout -------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UiTheme.build()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_sidebar()
	_build_left_column()
	_build_top_banners()
	_build_message_box()


func _build_sidebar() -> void:
	var panel := PanelContainer.new()
	panel.name = "Sidebar"
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER, 2, 0, 10))
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -SIDEBAR_WIDTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_map_label = Label.new()
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_map_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_map_label)

	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.display_width = SIDEBAR_WIDTH - 24.0
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_minimap)

	vbox.add_child(HSeparator.new())
	_party_label = Label.new()
	_party_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_party_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_party_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_cards_box = VBoxContainer.new()
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_cards_box)

	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	vbox.add_child(buttons)
	_add_button(buttons, "Select all", func() -> void: world.party.select_all())
	_add_button(buttons, "Grid", func() -> void: world.grid_lines.visible = not world.grid_lines.visible)
	_add_button(buttons, "Pause", func() -> void: world.set_paused(not get_tree().paused))
	_add_button(buttons, "Help", func() -> void: _help_panel.visible = not _help_panel.visible)


func _build_left_column() -> void:
	var column := VBoxContainer.new()
	column.name = "LeftColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_MINSIZE, 10)
	_root.add_child(column)

	_info_panel = PanelContainer.new()
	_info_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.07, 0.06, 0.05, 0.82), UiTheme.BORDER, 1, 4, 8))
	_info_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_info_panel)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.custom_minimum_size = Vector2(250, 0)
	_info_label.text = "Hover the map for details"
	_info_panel.add_child(_info_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_help_panel = PanelContainer.new()
	_help_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.07, 0.06, 0.05, 0.85), UiTheme.BORDER, 1, 4, 10))
	_help_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_help_panel)
	var help := RichTextLabel.new()
	help.bbcode_enabled = true
	help.fit_content = true
	help.scroll_active = false
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.add_theme_font_size_override("normal_font_size", 13)
	help.add_theme_font_size_override("bold_font_size", 14)
	help.add_theme_color_override("default_color", UiTheme.TEXT)
	help.text = HELP_TEXT % mini(9, GameConfig.max_party_size)
	_help_panel.add_child(help)


func _build_top_banners() -> void:
	var stack := VBoxContainer.new()
	stack.name = "TopBanners"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stack.offset_top = 12
	stack.offset_right = -SIDEBAR_WIDTH
	stack.add_theme_constant_override("separation", 8)
	_root.add_child(stack)

	_pause_banner = PanelContainer.new()
	_pause_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_banner.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.1, 0.08, 0.05, 0.9), UiTheme.GOLD, 2, 4, 10))
	var pl := Label.new()
	pl.text = "PAUSED   ·   Space to resume (orders can still be given)"
	pl.add_theme_color_override("font_color", UiTheme.GOLD)
	_pause_banner.add_child(pl)
	_pause_banner.visible = false
	stack.add_child(_pause_banner)

	_toast = PanelContainer.new()
	_toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.1, 0.05, 0.04, 0.85), Color("8c3b2e"), 1, 4, 8))
	_toast_label = Label.new()
	_toast.add_child(_toast_label)
	_toast.visible = false
	stack.add_child(_toast)


func _build_message_box() -> void:
	var center := CenterContainer.new()
	center.name = "MessageLayer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -SIDEBAR_WIDTH
	_root.add_child(center)

	_message_panel = PanelContainer.new()
	_message_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 16))
	_message_panel.visible = false
	_message_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_message_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_message_panel.add_child(vbox)
	_message_title = Label.new()
	_message_title.add_theme_color_override("font_color", UiTheme.GOLD)
	_message_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_message_title)
	_message_body = Label.new()
	_message_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_body.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(_message_body)
	var close := Button.new()
	close.text = "Close  (Esc)"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: _message_panel.visible = false)
	vbox.add_child(close)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
