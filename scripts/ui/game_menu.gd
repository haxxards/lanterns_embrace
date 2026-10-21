class_name GameMenu
extends PanelContainer
## The Esc menu: resume, save, load, quicksave/quickload, the item icon style
## and quit.

signal resume_requested
signal save_requested
signal load_requested
signal quicksave_requested
signal quickload_requested

var _style_button: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 18))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(260, 0)
	add_child(box)
	var title := Label.new()
	title.text = "Lantern's Embrace"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	box.add_child(title)
	box.add_child(HSeparator.new())
	_add(box, "Resume  (Esc)", resume_requested.emit)
	_add(box, "Save game", save_requested.emit)
	_add(box, "Load game", load_requested.emit)
	_add(box, "Quicksave  (F5)", quicksave_requested.emit)
	_add(box, "Quickload  (F9)", quickload_requested.emit)
	box.add_child(HSeparator.new())
	_style_button = _add(box, "", _next_icon_style)
	_style_button.tooltip_text = "Switch between the classic and the painted item icons.\n" \
			+ "The style the game starts with is \"art_style\" in data/config/game_config.json."
	_update_style_button()
	box.add_child(HSeparator.new())
	_add(box, "Quit to desktop", func() -> void: get_tree().quit())


func _add(box: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_on_pressed.bind(action))
	box.add_child(b)
	return b


## Cycles the item icons through the art styles (classic -> painted -> ...).
func _next_icon_style() -> void:
	var styles := GameConfig.ART_STYLES
	var next := styles[(styles.find(GameConfig.art_style_of("items")) + 1) % styles.size()]
	Data.set_art_style("items", next)
	_update_style_button()


func _update_style_button() -> void:
	_style_button.text = "Item icons: %s" % GameConfig.art_style_of("items").capitalize()


func _on_pressed(action: Callable) -> void:
	Audio.play_sfx("ui_click")
	action.call()
