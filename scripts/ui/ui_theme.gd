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

## The gilded frame (rendered by tools/art/blender/render_ui.py; the numbers
## must match it): a 9-slice whose FRAME_CORNER-pixel corners keep their
## ornaments, drawn FRAME_OUTSET pixels outside the panel so the moulding's
## outer edge is the panel's edge. The moulding is FRAME_BAND pixels wide.
const FRAME_TEXTURE := "res://assets/ui/frame_gold.png"
const FRAME_CORNER := 150
const FRAME_OUTSET := 30
const FRAME_BAND := 26
## The crest at the middle of each side, and where the moulding's centre line
## runs through it: {side: Vector2(along, across)} in its picture.
const FRAME_CRESTS := {
	"top": Vector2(100, 46), "bottom": Vector2(100, 38),
	"left": Vector2(46, 100), "right": Vector2(38, 100),
}

## The crest pictures, loaded once: {side: Texture2D}.
static var _crests: Dictionary = {}


static func panel_box(bg: Color = BG, border: Color = BORDER, border_w: int = 2,
		radius: int = 4, margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## The ornate gilded frame for a window (the inventory screen). Content sits
## `content_margin` pixels inside the panel's edge, clear of the corner
## rosettes. Falls back to a plain panel if the picture is missing.
static func ornate_frame(content_margin: int = 46) -> StyleBox:
	if not ResourceLoader.exists(FRAME_TEXTURE):
		return panel_box(BG, BORDER_LIGHT, 2, 6, 14)
	var sb := StyleBoxTexture.new()
	sb.texture = load(FRAME_TEXTURE)
	sb.set_texture_margin_all(FRAME_CORNER)
	sb.set_expand_margin_all(FRAME_OUTSET)
	sb.set_content_margin_all(content_margin)
	return sb


## Draws the crests at the middle of each side of `rect` (in `ci`'s own
## coordinates), over the moulding of an ornate_frame. Call from _draw().
static func draw_frame_crests(ci: CanvasItem, rect: Rect2) -> void:
	var line := FRAME_BAND / 2.0  # the moulding's centre line, inside the edge
	var mid := rect.get_center()
	var anchors := {
		"top": Vector2(mid.x, rect.position.y + line), "bottom": Vector2(mid.x, rect.end.y - line),
		"left": Vector2(rect.position.x + line, mid.y), "right": Vector2(rect.end.x - line, mid.y),
	}
	if _crests.is_empty():
		for side in FRAME_CRESTS:
			var path := "res://assets/ui/frame_gold_crest_%s.png" % side
			if ResourceLoader.exists(path):
				_crests[side] = load(path)
	for side in _crests:
		ci.draw_texture(_crests[side], anchors[side] - FRAME_CRESTS[side])


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
