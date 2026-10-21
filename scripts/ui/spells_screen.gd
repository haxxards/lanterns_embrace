class_name SpellsScreen
extends PanelContainer
## Spells and abilities (B): one party member at a time, their casting
## numbers, spell slots, hit dice, the spells they know, their class features
## and the scrolls they carry. Outside a fight, healing and buffs can be cast
## from here (Abilities has the rules); a spell for one person asks whom to
## cast it on. In a fight this is a reference: the combat bar casts.

signal closed

var party: Array[CharacterSheet] = []
var sheet: CharacterSheet

var _members: HBoxContainer
var _stats: Label
var _slots: Label
var _rows: VBoxContainer
var _detail: RichTextLabel
var _target_bar: HBoxContainer
var _target_label: Label
var _result: Label
## The cast waiting for a target: {"spell": SpellDef, "slot": int, "item": scroll id or ""}.
var _pending: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 14))
	custom_minimum_size = Vector2(800, 520)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "Spells and abilities"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_b := Button.new()
	close_b.text = "Close  (B)"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	head.add_child(close_b)
	_members = HBoxContainer.new()
	_members.add_theme_constant_override("separation", 6)
	root.add_child(_members)
	_stats = _label("", 13, UiTheme.TEXT)
	root.add_child(_stats)
	_slots = _label("", 13, UiTheme.GOLD)
	root.add_child(_slots)
	root.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.custom_minimum_size = Vector2(270, 0)
	_detail.add_theme_font_size_override("normal_font_size", 13)
	_detail.add_theme_color_override("default_color", UiTheme.TEXT)
	body.add_child(_detail)
	_target_bar = HBoxContainer.new()
	_target_bar.add_theme_constant_override("separation", 6)
	_target_bar.visible = false
	root.add_child(_target_bar)
	_target_label = _label("", 14, UiTheme.GOLD)
	_target_bar.add_child(_target_label)
	_result = _label("", 13, UiTheme.TEXT_DIM)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_result)


## Opens on `who` (one of `members`).
func open(members: Array[CharacterSheet], who: CharacterSheet) -> void:
	party = members
	_result.text = "In a fight, cast from the combat bar; this list is for reference." if GameState.in_combat() \
			else "Healing and lasting spells can be cast from here. Fight spells are cast from the combat bar."
	show_sheet(who if who != null else party[0])
	visible = true
	Audio.play_sfx("ui_open")


func close() -> void:
	if visible:
		visible = false
		_pending = {}
		closed.emit()


func show_sheet(s: CharacterSheet) -> void:
	sheet = s
	_pending = {}
	_refresh()


func _refresh() -> void:
	_build_members()
	_build_header()
	_build_rows()
	_build_target_bar()


func _build_members() -> void:
	for c in _members.get_children():
		c.queue_free()
	for s in party:
		var b := Button.new()
		b.text = s.display_name
		b.toggle_mode = true
		b.button_pressed = s == sheet
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(show_sheet.bind(s))
		_members.add_child(b)


func _build_header() -> void:
	var parts := PackedStringArray(["%s, level %d %s" % [sheet.display_name, sheet.level,
			str(Classes.info(sheet.character_class).get("name", sheet.character_class.capitalize()))]])
	var ab := Spellcasting.ability(sheet)
	if Spellcasting.is_caster(sheet):
		parts.append("casts with %s" % Rules.ABILITY_NAMES.get(ab, ab))
		parts.append("spell attack %s" % Rules.format_modifier(Spellcasting.attack_bonus(sheet)))
		parts.append("save DC %d" % Spellcasting.save_dc(sheet))
	parts.append("hit dice %d/%d (d%d)" % [sheet.hit_dice_left(), sheet.level, Classes.hit_die(sheet)])
	_stats.text = "   ·   ".join(parts)
	_slots.text = "Spell slots   " + slot_pips(sheet) if Spellcasting.is_caster(sheet) else ""
	_slots.visible = not _slots.text.is_empty()


## "1st ●●○   2nd ●●" (filled: left, hollow: spent).
static func slot_pips(s: CharacterSheet) -> String:
	var parts := PackedStringArray()
	var mx := Spellcasting.slots_max(s)
	var levels: Array = mx.keys()
	levels.sort()
	for lv in levels:
		var total := int(mx[lv])
		if total <= 0:
			continue
		var left := Spellcasting.slots_left(s, int(lv))
		parts.append("%s %s%s" % [SpellDef.ordinal(int(lv)), "●".repeat(left), "○".repeat(total - left)])
	return "   ".join(parts)


func _build_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var spells := Spellcasting.known(sheet)
	var level := -1
	for spell in spells:
		if spell.level != level:
			level = spell.level
			_section("Cantrips" if level == 0 else "%s-level spells" % SpellDef.ordinal(level))
		_spell_row(spell, "")
	var feats := PackedStringArray()
	for f in sheet.raw.get("features", []):
		feats.append(str(f))
	if not feats.is_empty():
		_section("Class features")
		for f in feats:
			_feature_row(f)
	var scrolls := Abilities.scrolls(sheet)
	if not scrolls.is_empty():
		_section("Scrolls")
		for sc in scrolls:
			_spell_row(sc["spell"], str(sc["item"]), int(sc["count"]))
	if spells.is_empty() and feats.is_empty() and scrolls.is_empty():
		_rows.add_child(_label("Nothing here yet.", 13, UiTheme.TEXT_DIM))
	_show_detail("", "")


func _section(text: String) -> void:
	var l := _label(text, 14, UiTheme.GOLD)
	_rows.add_child(l)


## A spell (or, with `item`, a scroll of it): its name, what kind of cast it
## is, and Cast buttons (one per slot level it could use).
func _spell_row(spell: SpellDef, item: String, count: int = 0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_rows.add_child(row)
	var name := spell.display_name if item.is_empty() else "Scroll of %s  ×%d" % [spell.display_name, count]
	var name_b := _flat_button(name)
	name_b.pressed.connect(_show_spell.bind(spell, item))
	row.add_child(name_b)
	row.add_child(_label(spell.summary(), 12, UiTheme.TEXT_DIM))
	var err := Abilities.spell_error(sheet, spell, not item.is_empty())
	if not item.is_empty() or spell.is_cantrip():
		row.add_child(_action_button("Read" if not item.is_empty() else "Cast", err,
				_begin_cast.bind(spell, 0, item)))
		return
	var levels: Array = Spellcasting.slots_max(sheet).keys()
	levels.sort()
	var any := false
	for lv in levels:
		if int(lv) < spell.level or int(Spellcasting.slots_max(sheet)[lv]) <= 0:
			continue
		any = true
		var why := err
		if why.is_empty() and Spellcasting.slots_left(sheet, int(lv)) <= 0:
			why = "No %s-level slots left. A long rest restores them." % SpellDef.ordinal(int(lv))
		var label := "Cast" if int(lv) == spell.level else SpellDef.ordinal(int(lv))
		var b := _action_button(label, why, _begin_cast.bind(spell, int(lv), ""))
		if int(lv) > spell.level:
			b.tooltip_text = (why + "\n" if not why.is_empty() else "") + "With a %s-level slot: %s" % [
					SpellDef.ordinal(int(lv)), _higher_text(spell, int(lv))]
		row.add_child(b)
	if not any:
		row.add_child(_action_button("Cast", err if not err.is_empty() else "No slots of that level.", Callable()))


func _feature_row(feature_id: String) -> void:
	var f := Classes.feature(feature_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_rows.add_child(row)
	var name_b := _flat_button(Classes.feature_name(feature_id))
	name_b.pressed.connect(_show_detail.bind(Classes.feature_name(feature_id), _feature_text(feature_id)))
	row.add_child(name_b)
	var uses := Features.uses_text(sheet, feature_id)
	row.add_child(_label(uses if not uses.is_empty() else ("passive" if not f.has("cost") else ""), 12,
			UiTheme.TEXT_DIM))
	if f.has("cost") or f.get("on") == "short_rest":
		row.add_child(_action_button("Use", Abilities.feature_error(sheet, feature_id, party),
				_use_feature.bind(feature_id)))


func _feature_text(feature_id: String) -> String:
	var f := Classes.feature(feature_id)
	var lines := PackedStringArray([str(f.get("description", ""))])
	var uses := Features.uses_text(sheet, feature_id)
	if not uses.is_empty():
		lines.append("\nUses: %s." % uses)
	if f.has("cost"):
		lines.append("Costs: %s in a fight." % {"action": "an action", "bonus": "a bonus action",
				"free": "nothing"}.get(str(f["cost"]), str(f["cost"])))
	return "\n".join(lines)


func _show_spell(spell: SpellDef, item: String) -> void:
	var lines := PackedStringArray()
	lines.append("[i]%s%s[/i]" % [spell.level_text(), (" " + spell.school) if not spell.school.is_empty() else ""])
	lines.append(spell.summary())
	lines.append("")
	lines.append(spell.description)
	if not spell.higher.is_empty() and not spell.is_cantrip():
		lines.append("\n[color=#b3a585]Higher slots: %s.[/color]" % _higher_text(spell, spell.level + 1))
	if not item.is_empty():
		lines.append("\n[color=#b3a585]Reading the scroll uses it up; no slot is needed. Only a %s can read it.[/color]"
				% " or ".join(spell.classes))
	_show_detail(spell.display_name, "\n".join(lines))


## What casting with a slot of `slot` adds, for tooltips: "4 darts", "+1d8 healing".
func _higher_text(spell: SpellDef, slot: int) -> String:
	var parts := PackedStringArray()
	if spell.higher.has("damage"):
		parts.append("%s damage" % Spellcasting.damage_expr(spell, sheet, slot))
	if spell.higher.has("heal"):
		parts.append("%s healing" % Spellcasting.add_dice(spell.heal, str(spell.higher["heal"]), slot - spell.level))
	for key in ["darts", "rays", "targets", "amount"]:
		if spell.higher.has(key):
			parts.append("%d %s" % [int(Spellcasting.scaled(spell, key, slot)),
					{"amount": "extra hit points"}.get(key, key)])
	if spell.higher.has("pool"):
		parts.append("%s hit points' worth" % str(Spellcasting.scaled(spell, "pool", slot)))
	return ", ".join(parts) if not parts.is_empty() else "no change"


func _show_detail(title: String, text: String) -> void:
	if title.is_empty():
		_detail.text = "[i]Click a name for its description.[/i]"
		return
	_detail.text = "[b][color=#e6c26a]%s[/color][/b]\n%s" % [title, text]


# --- casting ------------------------------------------------------------------------------

func _begin_cast(spell: SpellDef, slot: int, item: String) -> void:
	if Abilities.picks_target(spell):
		_pending = {"spell": spell, "slot": slot, "item": item}
		_build_target_bar()
		return
	_finish_cast(spell, slot, item, sheet)


func _finish_cast(spell: SpellDef, slot: int, item: String, target: CharacterSheet) -> void:
	_pending = {}
	var result := Abilities.read_scroll(sheet, item, target, party) if not item.is_empty() \
			else Abilities.cast(sheet, spell, target, party, slot)
	_report(result)


func _use_feature(feature_id: String) -> void:
	_report(Abilities.use_feature(sheet, feature_id, party))


func _report(result: Dictionary) -> void:
	_result.text = str(result["text"])
	_result.add_theme_color_override("font_color", UiTheme.TEXT if result["ok"] else Color("e08a6a"))
	if not result["ok"]:
		Audio.play_sfx("error")
	_refresh()


func _build_target_bar() -> void:
	for c in _target_bar.get_children():
		if c != _target_label:
			c.queue_free()
	_target_bar.visible = not _pending.is_empty()
	if _pending.is_empty():
		return
	var spell: SpellDef = _pending["spell"]
	_target_label.text = "Cast %s on:" % spell.display_name
	for s in party:
		var b := _action_button(s.display_name, Abilities.target_error(spell, s),
				_finish_cast.bind(spell, int(_pending["slot"]), str(_pending["item"]), s))
		_target_bar.add_child(b)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void:
		_pending = {}
		_build_target_bar())
	_target_bar.add_child(cancel)


# --- widgets ------------------------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _flat_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(230, 0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", UiTheme.TEXT)
	return b


## A button that is greyed out, with the reason as its tooltip, when `why` isn't "".
func _action_button(text: String, why: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not why.is_empty() or not action.is_valid()
	b.tooltip_text = why
	if action.is_valid():
		b.pressed.connect(action)
		b.pressed.connect(Audio.play_sfx.bind("ui_click"))
	return b
