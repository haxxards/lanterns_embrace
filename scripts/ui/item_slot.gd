class_name ItemSlot
extends Control
## One square on the inventory screen: a backpack slot, an equipment slot or a
## container slot. Shows the item's icon and count, a tooltip with its stats,
## and does drag and drop through Godot's built-in Control drag API:
##   _get_drag_data   -> starts a drag (returns what is being dragged)
##   _can_drop_data   -> asked while hovering: may this be dropped here?
##   _drop_data       -> the drop itself
## The actual rules are in InventoryOps.

signal used(slot: ItemSlot)

const SIZE := Vector2(56, 56)

## Where this slot points (see InventoryOps): backpack, equip or container.
var ref: Dictionary = {}
## Text shown in an empty equipment slot ("Head", "Off hand"...).
var placeholder: String = ""
## In a shop: trade terms. Shop slots show what an item costs; the party's own
## slots mention what it would sell for.
var trade: Dictionary = {}

var _hover: bool = false
var _drop_ok: Variant = null  # null = no drag over us, else true/false


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(value: bool) -> void:
	_hover = value
	if not value:
		_drop_ok = null
	queue_redraw()


func stack() -> ItemStack:
	return InventoryOps.stack_at(ref)


func refresh() -> void:
	var st := stack()
	tooltip_text = st.def.describe() if st != null and st.def != null else (placeholder if not placeholder.is_empty() else "")
	if st != null and st.def != null and not trade.is_empty():
		if ref.has("trade"):
			tooltip_text += "\nPrice: %d gp each" % InventoryOps.buy_price(st.def, trade)
		elif InventoryOps.can_sell(st.def):
			tooltip_text += "\nSells for %d gp each" % InventoryOps.sell_price(st.def, trade)
		else:
			tooltip_text += "\nCan't be sold"
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var border := UiTheme.BORDER
	if _drop_ok != null:
		border = UiTheme.SELECTED if _drop_ok else Color("b8322f")
	elif _hover:
		border = UiTheme.BORDER_LIGHT
	draw_rect(r, Color("15110d"))
	draw_rect(r.grow(-1), Color("221b14"), false, 1.0)
	draw_rect(r, border, false, 2.0 if _drop_ok != null or _hover else 1.0)
	var st := stack()
	var font := get_theme_default_font()
	if st == null:
		if not placeholder.is_empty():
			draw_string(font, Vector2(0, size.y * 0.5 + 4), placeholder, HORIZONTAL_ALIGNMENT_CENTER,
					size.x, 10, Color(UiTheme.TEXT_DIM, 0.55))
		return
	var icon: Texture2D = st.def.icon if st.def != null else Data.missing_texture()
	var inner := r.grow(-4)
	var tex_size := icon.get_size()
	var scale := minf(inner.size.x / tex_size.x, inner.size.y / tex_size.y)
	var draw_size := tex_size * scale
	draw_texture_rect(icon, Rect2(inner.position + (inner.size - draw_size) * 0.5, draw_size), false)
	if st.def != null and st.def.magic:
		draw_rect(r.grow(-2), Color(0.45, 0.6, 1.0, 0.5), false, 1.0)
	if ref.has("trade") and st.def != null:
		var price := "%dg" % InventoryOps.buy_price(st.def, ref["trade"])
		draw_string_outline(font, Vector2(3, 13), price, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(font, Vector2(3, 13), price, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.GOLD)
	if st.qty > 1:
		var t := str(st.qty)
		draw_string_outline(font, Vector2(0, size.y - 4), t, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, 3, Color.BLACK)
		draw_string(font, Vector2(0, size.y - 4), t, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, UiTheme.TEXT)


func _get_drag_data(_at_position: Vector2) -> Variant:
	var st := stack()
	if st == null or st.def == null:
		return null
	var holder := Control.new()
	var icon := TextureRect.new()
	icon.texture = st.def.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = SIZE
	icon.position = -SIZE * 0.5
	icon.modulate.a = 0.85
	holder.add_child(icon)
	set_drag_preview(holder)
	Audio.play_sfx("item_pickup")
	return {"ref": ref}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("ref")):
		return false
	var moving := InventoryOps.stack_at(data["ref"])
	_drop_ok = InventoryOps.can_place(ref, moving).is_empty()
	queue_redraw()
	return true  # a refused drop still lands, so the reason can be shown


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_ok = null
	var err := InventoryOps.move(data["ref"], ref)
	if not err.is_empty():
		Audio.play_sfx("error")
		Events.toast_requested.emit(err)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drop_ok = null
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
			if stack() != null:
				used.emit(self)
				accept_event()


## Tooltips styled like the rest of the HUD.
func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.is_empty():
		return null
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.08, 0.065, 0.05, 0.96), UiTheme.BORDER_LIGHT, 1, 4, 8))
	var label := Label.new()
	label.text = for_text
	label.add_theme_color_override("font_color", UiTheme.TEXT)
	label.add_theme_font_size_override("font_size", 13)
	label.custom_minimum_size = Vector2(240, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	return panel
