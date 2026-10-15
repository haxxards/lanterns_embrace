class_name JournalScreen
extends PanelContainer
## The quest journal (J): quests in progress, then finished ones, and the
## entries written so far for the one selected. Also each member's XP.

signal closed

var _list: ItemList
var _entries: RichTextLabel
var _xp: Label
var _ids: Array[String] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 14))
	custom_minimum_size = Vector2(760, 480)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "Journal"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_b := Button.new()
	close_b.text = "Close  (J)"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	head.add_child(close_b)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(320, 0)
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_selected)
	body.add_child(_list)
	_entries = RichTextLabel.new()
	_entries.bbcode_enabled = true
	_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries.add_theme_font_size_override("normal_font_size", 14)
	_entries.add_theme_color_override("default_color", UiTheme.TEXT)
	body.add_child(_entries)
	_xp = Label.new()
	_xp.add_theme_font_size_override("font_size", 12)
	_xp.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	root.add_child(_xp)


func open() -> void:
	_list.clear()
	_ids.clear()
	for state in ["active", "done"]:
		for quest_id in GameState.quest_log:
			if GameState.quest_state(quest_id) != state:
				continue
			var q: QuestDef = Data.quests.get(quest_id)
			if q == null:
				continue
			_ids.append(quest_id)
			var i := _list.add_item(q.display_name if state == "active" else "%s  (done)" % q.display_name)
			_list.set_item_custom_fg_color(i, UiTheme.TEXT if state == "active" else UiTheme.TEXT_DIM)
	var parts := PackedStringArray()
	for s in GameState.party:
		var next := Rules.xp_for_next_level(s.level)
		parts.append("%s  L%d  %d%s XP" % [s.id.capitalize(), s.level, s.xp,
				"" if next < 0 else " / %d" % next])
	_xp.text = "   ·   ".join(parts)
	if _ids.is_empty():
		_entries.text = "[i]No entries yet. Talk to people around Millbrook.[/i]"
	else:
		_list.select(0)
		_on_selected(0)
	visible = true
	Audio.play_sfx("ui_open")


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _on_selected(i: int) -> void:
	var quest_id := _ids[i]
	var q: QuestDef = Data.quests[quest_id]
	var lines := PackedStringArray(["[b]%s[/b]\n" % q.display_name])
	for stage_id in GameState.quest_log.get(quest_id, []):
		var st := q.stage(str(stage_id))
		lines.append("•  " + str(st.get("journal", "")))
	if GameState.quest_state(quest_id) == "done":
		lines.append("\n[color=#b3a585]Completed. +%d XP each.[/color]" % q.xp)
	_entries.text = "\n".join(lines)
