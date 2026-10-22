class_name CombatHud
extends Control
## The fight's interface: the initiative order (order_panel, which the HUD puts
## along the top), the combat log at the bottom left, and the action bar for
## the party member whose turn it is: movement and actions left, Dash, Dodge,
## Disengage and End turn, a row of their spells, features and scrolls
## (CombatManager.abilities_for), and a hint for what clicking would do.

const CARD_SIZE := Vector2(58, 58)

var combat: CombatManager
## The initiative strip (placed by the HUD in its top banner stack).
var order_panel: PanelContainer

var _order: HBoxContainer
var _bar: PanelContainer
var _who: Label
var _status: Label
var _hint: Label
var _buttons: Dictionary = {}
## The current member's spells, features and scrolls; rebuilt when they change.
var _abilities: HFlowContainer
var _abilities_key: String = ""
var _log_panel: PanelContainer
var _log: RichTextLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_set_shown(false)


func bind(c: CombatManager) -> void:
	combat = c
	c.started.connect(_on_started)
	c.ended.connect(_on_ended)
	c.aborted.connect(_on_aborted)
	c.state_changed.connect(_refresh)
	c.logged.connect(_on_logged)
	c.hint_changed.connect(func(text: String) -> void: _hint.text = text)


func _set_shown(on: bool) -> void:
	order_panel.visible = on
	_bar.visible = on
	_log_panel.visible = on


func _on_started() -> void:
	_log.clear()
	for line in combat.log_lines:
		_log.append_text(line + "\n")
	_set_shown(true)
	_refresh()


func _on_ended(_victory: bool) -> void:
	_abilities_key = ""
	_bar.visible = false
	order_panel.visible = false
	_hint.text = ""
	# The log stays up a moment so the last blows can be read.
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(_hide_log_if_idle)


## A fight stopped without a result (a game loaded mid-fight): everything goes at once.
func _on_aborted() -> void:
	_abilities_key = ""
	_hint.text = ""
	_set_shown(false)


func _hide_log_if_idle() -> void:
	if combat == null or not combat.active:
		_log_panel.visible = false


func _on_logged(text: String) -> void:
	_log.append_text(text + "\n")


func _refresh() -> void:
	if combat == null or not combat.active:
		return
	_rebuild_order()
	var c := combat.current
	if c == null:
		_who.text = "Rolling initiative..."
		_status.text = ""
		_set_buttons_enabled(false)
		return
	var mine := combat.is_player_turn()
	_who.text = "%s's turn" % c.display_name() if c.is_party() else "%s is acting..." % c.display_name()
	_who.add_theme_color_override("font_color", UiTheme.GOLD if c.is_party() else Color("e07a5a"))
	if c.is_party():
		var parts := PackedStringArray()
		parts.append("Movement %d ft" % roundi(maxf(0.0, c.movement_left)))
		parts.append("Action: %s" % ("used" if c.action_used else "ready"))
		parts.append("Bonus: %s" % ("used" if c.bonus_used else "ready"))
		var slots := Spellcasting.slots_text(c.sheet)
		if not slots.is_empty() and Spellcasting.is_caster(c.sheet):
			parts.append("Slots %s" % slots)
		if c.off_hand_attack() != null:
			var off_ready := c.attacked_light and not c.bonus_used
			parts.append("Off hand: %s" % ("ready" if off_ready else ("used" if c.bonus_used else "after a light attack")))
		if c.dodging:
			parts.append("Dodging")
		if c.disengaged:
			parts.append("Disengaged")
		if c.blessed_by != null:
			parts.append("Blessed")
		if not c.concentration.is_empty():
			parts.append("Concentrating")
		_status.text = "   ·   ".join(parts)
	else:
		_status.text = "Round %d" % combat.round_number
	_set_buttons_enabled(mine)
	if mine:
		for key in ["dash", "dodge", "disengage"]:
			(_buttons[key] as Button).disabled = c.action_used
	_rebuild_abilities(c if mine else null)


## One button per spell, feature and scroll of the member whose turn it is,
## disabled (with the reason as its tooltip) when it can't be used now.
func _rebuild_abilities(c: Combatant) -> void:
	var list: Array[Dictionary] = []
	if c != null:
		list = combat.abilities_for(c)
	var key := ""
	for ab in list:
		key += "%s|%s|%s|%s;" % [ab["name"], ab["error"], ab["kind"], str(combat.targeting.get("name", ""))]
	if key == _abilities_key:
		return
	_abilities_key = key
	for child in _abilities.get_children():
		child.queue_free()
	_abilities.visible = not list.is_empty()
	for ab in list:
		var b := Button.new()
		b.text = str(ab["name"])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		var err := str(ab["error"])
		b.disabled = not err.is_empty()
		b.tooltip_text = str(ab["tooltip"]) + ("

" + err if not err.is_empty() else "")
		if not combat.targeting.is_empty() and combat.targeting.get("name") == ab["name"]:
			b.add_theme_color_override("font_color", UiTheme.GOLD)
		b.pressed.connect(func() -> void:
			Audio.play_sfx("ui_click")
			combat.use_ability(ab))
		_abilities.add_child(b)


func _set_buttons_enabled(on: bool) -> void:
	for b: Button in _buttons.values():
		b.disabled = not on


func _rebuild_order() -> void:
	for child in _order.get_children():
		child.queue_free()
	for c in combat.combatants:
		if c.is_out():
			continue
		_order.add_child(_order_card(c, c == combat.current))


func _order_card(c: Combatant, current: bool) -> Control:
	var panel := PanelContainer.new()
	var border := UiTheme.GOLD if current else (UiTheme.BORDER if c.is_party() else Color("8c3b2e"))
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.08, 0.07, 0.06, 0.92), border,
			3 if current else 1, 3, 3))
	var conds := c.conditions()
	panel.tooltip_text = "%s  ·  %s  ·  initiative %d  ·  %d/%d HP%s" % [c.display_name(),
			CreatureTypes.describe(c.sheet), c.initiative, c.sheet.hp_current, c.sheet.hp_max,
			"\n" + ", ".join(conds) if not conds.is_empty() else ""]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var pic := TextureRect.new()
	pic.custom_minimum_size = CARD_SIZE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if c.is_party() else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = Data.load_texture(c.sheet.portrait_path if c.is_party() else c.sheet.sprite_path)
	if not c.is_conscious():
		pic.modulate = Color(0.45, 0.4, 0.4)
	elif c.is_held():
		pic.modulate = Color(0.8, 0.72, 1.1)
	elif c.asleep:
		pic.modulate = Color(0.65, 0.72, 0.95)
	box.add_child(pic)
	var tag := "Zzz" if c.asleep else ("Held" if c.is_held() else "")
	if not tag.is_empty():  # a badge on the portrait
		var badge := Label.new()
		badge.text = tag
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", StatusFx.HOLD_COLOR if c.is_held() else StatusFx.SLEEP_COLOR)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("outline_size", 4)
		badge.position = Vector2(3, 1)
		pic.add_child(badge)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(CARD_SIZE.x, 5)
	bar.show_percentage = false
	bar.max_value = c.sheet.hp_max
	bar.value = c.sheet.hp_current
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.HP_FILL if not c.is_party() else Color("4fae4f")
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiTheme.HP_BG
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	box.add_child(bar)
	return panel


func _build() -> void:
	order_panel = PanelContainer.new()
	order_panel.name = "Initiative"
	order_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	order_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	order_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.1, 0.08, 0.06, 0.75), UiTheme.BORDER, 1, 4, 6))
	_order = HBoxContainer.new()
	_order.add_theme_constant_override("separation", 6)
	order_panel.add_child(_order)

	_bar = PanelContainer.new()
	_bar.name = "ActionBar"
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.1, 0.08, 0.06, 0.94), UiTheme.BORDER_LIGHT, 2, 6, 10))
	add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_bottom = -14
	_bar.custom_minimum_size = Vector2(640, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_bar.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	_who = Label.new()
	_who.add_theme_font_size_override("font_size", 16)
	top.add_child(_who)
	_status = Label.new()
	_status.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for spec in [["dash", "Dash", "Double your movement this turn (uses your action)"],
			["dodge", "Dodge", "Attacks against you have disadvantage until your next turn (uses your action)"],
			["disengage", "Disengage", "Move without provoking opportunity attacks this turn (uses your action)"],
			["end", "End turn  (Space)", "Finish this character's turn"]]:
		var b := Button.new()
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.focus_mode = Control.FOCUS_NONE
		if spec[0] == "end":
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		_buttons[spec[0]] = b
	(_buttons["dash"] as Button).pressed.connect(func() -> void: combat.dash())
	(_buttons["dodge"] as Button).pressed.connect(func() -> void: combat.dodge())
	(_buttons["disengage"] as Button).pressed.connect(func() -> void: combat.disengage())
	(_buttons["end"] as Button).pressed.connect(func() -> void: combat.end_turn())
	_abilities = HFlowContainer.new()
	_abilities.add_theme_constant_override("h_separation", 6)
	_abilities.add_theme_constant_override("v_separation", 6)
	_abilities.visible = false
	v.add_child(_abilities)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", UiTheme.TEXT)
	_hint.text = ""
	_hint.custom_minimum_size = Vector2(0, 20)
	v.add_child(_hint)

	_log_panel = PanelContainer.new()
	_log_panel.name = "CombatLog"
	_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_log_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.06, 0.05, 0.04, 0.8), UiTheme.BORDER, 1, 4, 8))
	add_child(_log_panel)
	_log_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log_panel.offset_left = 12
	_log_panel.offset_bottom = -150
	_log_panel.custom_minimum_size = Vector2(420, 170)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.custom_minimum_size = Vector2(404, 154)
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_font_size_override("bold_font_size", 12)
	_log.add_theme_color_override("default_color", UiTheme.TEXT)
	_log_panel.add_child(_log)
