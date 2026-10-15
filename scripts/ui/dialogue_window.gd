class_name DialogueWindow
extends PanelContainer
## The conversation panel along the bottom of the map: the NPC's portrait,
## name and line, and numbered answers (click, or press 1-9). Esc walks away.
## Shows a DialogueRunner; the rules of the conversation live there.

signal closed(runner: DialogueRunner, npc: Npc)

const PORTRAIT_SIZE := Vector2(116, 145)

var runner: DialogueRunner
var npc: Npc

var _portrait: TextureRect
var _name: Label
var _title: Label
var _text: RichTextLabel
var _options: VBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.09, 0.075, 0.06, 0.97), UiTheme.BORDER_LIGHT, 2, 6, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.panel_box(Color("15110d"), UiTheme.BORDER, 2, 3, 2))
	left.add_child(frame)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = PORTRAIT_SIZE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(_portrait)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	right.add_child(head)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 18)
	_name.add_theme_color_override("font_color", UiTheme.GOLD)
	head.add_child(_name)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_title.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_color_override("default_color", UiTheme.TEXT)
	right.add_child(_text)
	right.add_child(HSeparator.new())
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 2)
	right.add_child(_options)


## Starts talking to `who` with `speaker` doing the talking.
func open(who: Npc, speaker: PartyMember) -> void:
	npc = who
	runner = DialogueRunner.new()
	runner.start(Data.dialogue(who.def.dialogue_path), who.def, speaker.sheet)
	_portrait.texture = Data.load_texture(who.def.portrait_path)
	visible = true
	Audio.play_sfx("ui_open")
	_show()


func _show() -> void:
	for m in runner.messages:
		Events.toast_requested.emit(m)
	if runner.finished:
		close()
		return
	_name.text = runner.speaker_name()
	_title.text = npc.def.title if runner.speaker_name() == npc.def.display_name else ""
	_text.text = runner.text()
	for c in _options.get_children():
		c.queue_free()
	var n := 1
	for opt in runner.options():
		var b := Button.new()
		b.text = "%d.  %s" % [n, opt["text"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", UiTheme.TEXT)
		b.add_theme_color_override("font_hover_color", UiTheme.GOLD)
		b.pressed.connect(choose.bind(int(opt["index"])))
		_options.add_child(b)
		n += 1


## Picks an option by its index in the node (see DialogueRunner.options()).
func choose(index: int) -> void:
	Audio.play_sfx("ui_click")
	runner.choose(index)
	_show()


## Picks the n-th visible option (1-based), as the number keys do.
func choose_number(n: int) -> void:
	var opts := runner.options()
	if n >= 1 and n <= opts.size():
		choose(int(opts[n - 1]["index"]))


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit(runner, npc)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).physical_keycode
	if k >= KEY_1 and k <= KEY_9:
		choose_number(k - KEY_0)
		get_viewport().set_input_as_handled()
