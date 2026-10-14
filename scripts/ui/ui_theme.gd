class_name UiTheme
extends RefCounted
## Shared look for the HUD: dark leather panels, bronze borders, parchment text.

const BG := Color("1c1814")
const BG_LIGHT := Color("2c241b")
const BORDER := Color("6b5636")
const BORDER_LIGHT := Color("a88a56")
const TEXT := Color("e8dcc0")
const TEXT_DIM := Color("b3a585")
const GOLD := Color("e6c26a")
const SELECTED := Color("59e86e")
const HP_FILL := Color("b8322f")
const HP_BG := Color("3a1514")


static func panel_box(bg: Color = BG, border: Color = BORDER, border_w: int = 2,
		radius: int = 4, margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	t.set_stylebox("normal", "Button", panel_box(BG_LIGHT, BORDER, 1, 3, 6))
	t.set_stylebox("hover", "Button", panel_box(Color("3a2f22"), BORDER_LIGHT, 1, 3, 6))
	t.set_stylebox("pressed", "Button", panel_box(Color("4a3b29"), GOLD, 1, 3, 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)

	var bar_bg := panel_box(HP_BG, Color("120807"), 1, 2, 0)
	var bar_fill := panel_box(HP_FILL, Color(0, 0, 0, 0), 0, 2, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", 11)

	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	return t
