class_name RestDialog
extends PanelContainer
## Resting (R): a short rest (spend hit dice, short-rest features come back)
## or a long rest (everything back; only under a roof). Rest has the rules;
## this shows what each does, why one isn't possible here, and the results.

signal closed

var world: World

var _short_b: Button
var _long_b: Button
var _text: RichTextLabel


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 14))
	custom_minimum_size = Vector2(520, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "Rest"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_b := Button.new()
	close_b.text = "Close  (R)"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	head.add_child(close_b)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(490, 0)
	_text.add_theme_font_size_override("normal_font_size", 14)
	_text.add_theme_color_override("default_color", UiTheme.TEXT)
	root.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	root.add_child(buttons)
	_short_b = _button("Short rest  (an hour)", buttons)
	_short_b.pressed.connect(_rest.bind("short"))
	_long_b = _button("Long rest  (a night)", buttons)
	_long_b.pressed.connect(_rest.bind("long"))


func open(w: World) -> void:
	world = w
	_text.text = _explain()
	_update_buttons()
	visible = true
	Audio.play_sfx("ui_open")


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _explain() -> String:
	var lines := PackedStringArray()
	lines.append("[b]Short rest[/b]: each member spends hit dice (one per level, back half on a long rest) "
			+ "to heal, and Second Wind, Action Surge and Channel Divinity come back. A wizard recovers "
			+ "some spell slots once a day (Arcane Recovery).")
	lines.append("[b]Long rest[/b]: full hit points, every spell slot and feature, and half the hit dice. "
			+ "Only under a roof: indoors, or a room at the inn.")
	lines.append("")
	for s in GameState.party:
		var bits := PackedStringArray(["HP %d/%d" % [s.hp_current, s.hp_max] if not s.dead else "dead",
				"hit dice %d/%d" % [s.hit_dice_left(), s.level]])
		if Spellcasting.is_caster(s):
			bits.append("slots " + SpellsScreen.slot_pips(s))
		lines.append("[color=#e6c26a]%s[/color]   %s" % [s.display_name, "   ".join(bits)])
	return "\n".join(lines)


func _update_buttons() -> void:
	for pair in [[_short_b, "short"], [_long_b, "long"]]:
		var b: Button = pair[0]
		var err := Rest.error(world, pair[1])
		b.disabled = not err.is_empty()
		b.tooltip_text = err


func _rest(kind: String) -> void:
	var err := Rest.error(world, kind)
	if not err.is_empty():
		Events.toast_requested.emit(err)
		return
	var lines := Rest.short_rest(GameState.party) if kind == "short" else Rest.long_rest(GameState.party)
	Audio.play_sfx("ui_open")
	_text.text = "[b]%s[/b]\n%s\n\n%s" % ["After a short rest:" if kind == "short" else "After a long rest:",
			"\n".join(lines), _explain().get_slice("\n\n", 1)]
	_update_buttons()


func _button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b
