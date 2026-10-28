class_name InventoryScreen
extends PanelContainer
## Inventory and paper doll for one party member, plus the open container
## (chest, drawers...) when there is one, or otherwise the ground at the
## member's feet. Opened with I, the sidebar button, or by opening a
## container. The HUD pauses the game while it is open.
##
## Mouse: drag items between slots (equip, swap, stack), drop an item on a
## sidebar portrait to give it away, drag it to the ground panel to drop it,
## right-click (or double-click) to use a potion, equip a backpack item, take
## off worn gear or take from a chest or the ground.

signal closed

const PORTRAIT_SIZE := Vector2(168, 210)
const LEFT_SLOTS := ["helmet", "armor", "cloak", "gloves", "ring_1"]
const RIGHT_SLOTS := ["amulet", "ring_2", "boots"]
const HAND_SLOTS := ["main_hand", "off_hand"]
const PACK_COLUMNS := 4
## Numbers that magic raised, in the stats panel.
const MAGIC_TEXT := Color(0.56, 0.72, 1.0)
const HINT := "Drag to move, equip or drop on the ground  ·  Shift-drag to split a stack  ·  right-click to use, equip or take  ·  drop on a portrait to give"
const HINT_SHOP := "Drag from the stock to buy the stack, into it to sell  ·  right-click buys one or sells  ·  prices in gold pieces"
const CONTAINER_COLUMNS := 8

var sheet: CharacterSheet
var container: ContainerState
## Gives the pile on the ground under a character: Callable(sheet) -> ContainerState.
var ground_provider: Callable
## True when the bottom panel shows the ground rather than an opened container.
var showing_ground: bool = false
## Trade terms while a shop is open (the bottom panel is the vendor's stock).
var trade: Dictionary = {}

var _name_label: Label
var _class_label: Label
var _portrait: TextureRect
var _equip: Dictionary = {}  # slot name -> ItemSlot
var _pack_grid: GridContainer
var _pack: Array[ItemSlot] = []
var _stats: RichTextLabel
var _gold_label: Label
var _container_box: VBoxContainer
var _container_title: Label
var _container_grid: GridContainer
var _container_slots: Array[ItemSlot] = []
var _take_all: Button
var _hint: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 14))
	_build()
	GameState.gold_changed.connect(func(_g: int) -> void: _refresh())


## Shows `s`'s inventory, with `c` open beside it if given (otherwise the ground).
func open(s: CharacterSheet, c: ContainerState = null, title: String = "") -> void:
	_set_trade({})
	showing_ground = c == null
	show_sheet(s)
	if c != null:
		set_container(c, title)
	if not visible:
		Audio.play_sfx("ui_open")
	visible = true


## Opens a vendor's shop: their stock below, `s`'s backpack above. Dragging
## from the stock buys, dragging into it sells.
func open_shop(s: CharacterSheet, stock: ContainerState, title: String, terms: Dictionary) -> void:
	showing_ground = false
	_set_trade(terms)
	show_sheet(s)
	set_container(stock, title)
	if not visible:
		Audio.play_sfx("ui_open")
	visible = true


func _set_trade(terms: Dictionary) -> void:
	trade = terms
	_take_all.visible = trade.is_empty()
	_hint.text = HINT_SHOP if not trade.is_empty() else HINT
	for slot in _all_slots():
		slot.trade = trade


func close() -> void:
	if not visible:
		return
	set_container(null)
	_set_trade({})
	visible = false
	closed.emit()


func show_sheet(s: CharacterSheet) -> void:
	# CharacterSheet.changed also fires for backpack changes.
	if sheet != null and sheet.changed.is_connected(_refresh):
		sheet.changed.disconnect(_refresh)
	sheet = s
	sheet.changed.connect(_refresh)
	for slot_name in _equip:
		(_equip[slot_name] as ItemSlot).ref = InventoryOps.equip_slot(sheet, slot_name)
	_resize_slots(_pack_grid, _pack, sheet.inventory.capacity())
	for i in _pack.size():
		_pack[i].ref = InventoryOps.backpack(sheet, i)
	if showing_ground:
		_show_ground()
	_refresh()


## The bottom panel shows what lies on the ground where the character stands.
func _show_ground() -> void:
	var pile: ContainerState = ground_provider.call(sheet) if ground_provider.is_valid() else null
	set_container(pile, "On the ground")


func set_container(c: ContainerState, title: String = "") -> void:
	if container != null and container.inventory.changed.is_connected(_refresh):
		container.inventory.changed.disconnect(_refresh)
	container = c
	_container_box.visible = c != null
	if c == null:
		return
	c.inventory.changed.connect(_refresh)
	_container_title.text = title
	_resize_slots(_container_grid, _container_slots, c.inventory.capacity())
	for i in _container_slots.size():
		_container_slots[i].ref = InventoryOps.shop_slot(c, i, trade) if not trade.is_empty() \
				else InventoryOps.container_slot(c, i)
		_container_slots[i].trade = trade
	_refresh()


func _refresh() -> void:
	if sheet == null:
		return
	_name_label.text = sheet.display_name
	_class_label.text = sheet.summary()
	_portrait.texture = Data.load_texture(sheet.portrait_path)
	for slot in _equip.values():
		(slot as ItemSlot).refresh()
	for slot in _pack:
		slot.refresh()
	for slot in _container_slots:
		slot.refresh()
	var weight := sheet.carried_weight()
	var cap := sheet.carrying_capacity()
	var weight_text := "%s / %s" % [ItemDef.format_weight(weight).trim_suffix(" lb"), ItemDef.format_weight(cap)]
	if sheet.is_overloaded():
		weight_text = "[color=#e05a4a]%s  (overloaded)[/color]" % weight_text
	_stats.text = "[b]AC %d[/b]      HP %d / %d      Speed %d ft\n%s\n%s\nCarrying %s" % [
		sheet.armor_class, sheet.hp_current, sheet.hp_max, sheet.effective_speed_ft(),
		_scores_text(), sheet.attack_summary(), weight_text]
	_gold_label.text = "Party gold: %d" % GameState.gold


## "Str 19  Dex 12 ...": scores raised by magic (gauntlets, a potion) in blue;
## then any save bonus and resistances from worn items.
func _scores_text() -> String:
	var parts := PackedStringArray()
	for ab in Rules.ABILITIES:
		var score := sheet.ability_score(ab)
		var text := "%s %d" % [ab.capitalize(), score]
		if score > int(sheet.abilities.get(ab, 10)):
			text = "[color=%s]%s[/color]" % [MAGIC_TEXT.to_html(false), text]
		parts.append(text)
	var line := "  ".join(parts)
	var extras := PackedStringArray()
	if sheet.item_bonus("saves") != 0:
		extras.append("Saves %s" % Rules.format_modifier(sheet.item_bonus("saves")))
	if not sheet.resistances().is_empty():
		extras.append("Resists %s" % ", ".join(sheet.resistances()))
	if not extras.is_empty():
		line += "\n[color=%s]%s[/color]" % [MAGIC_TEXT.to_html(false), "      ".join(extras)]
	return line


func _all_slots() -> Array[ItemSlot]:
	var out: Array[ItemSlot] = []
	for slot in _equip.values():
		out.append(slot)
	out.append_array(_pack)
	out.append_array(_container_slots)
	return out


func _on_slot_used(slot: ItemSlot) -> void:
	var st := slot.stack()
	if st == null or st.def == null:
		return
	var err := ""
	match str(slot.ref.get("kind")):
		"container", "equip":
			err = InventoryOps.give(slot.ref, sheet)  # take it / take it off / buy it
		"backpack":
			if not trade.is_empty() and container != null:
				err = InventoryOps.sell(slot.ref, InventoryOps.shop_slot(container, 0, trade))
				if not err.is_empty():
					Audio.play_sfx("error")
					Events.toast_requested.emit(err)
				return
			if st.def.is_usable():
				var msg := InventoryOps.use(slot.ref, sheet)
				if not msg.is_empty():
					Events.toast_requested.emit(msg)
				return
			var target := _slot_for(st.def)
			if target.is_empty():
				return
			err = InventoryOps.move(slot.ref, InventoryOps.equip_slot(sheet, target))
	if not err.is_empty():
		Audio.play_sfx("error")
		Events.toast_requested.emit(err)


## Equipment slot a backpack item would go to on right-click.
func _slot_for(def: ItemDef) -> String:
	if def.slot == "ring":
		return "ring_1" if sheet.equipped("ring_1") == null else "ring_2"
	return def.slot


func _take_all_pressed() -> void:
	if container == null:
		return
	var err := InventoryOps.take_all(container, sheet)
	if not err.is_empty():
		Events.toast_requested.emit(err)


func _cycle(step: int) -> void:
	var party := GameState.party
	if party.is_empty():
		return
	var i := party.find(sheet)
	show_sheet(party[posmod(i + step, party.size())])


# --- layout -------------------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	header.add_child(_button("◀", _cycle.bind(-1)))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(names)
	_name_label = _label("", 20, UiTheme.GOLD)
	names.add_child(_name_label)
	_class_label = _label("", 13, UiTheme.TEXT_DIM)
	names.add_child(_class_label)
	header.add_child(_button("▶", _cycle.bind(1)))
	_gold_label = _label("", 15, UiTheme.GOLD)
	header.add_child(_gold_label)
	header.add_child(_button("Close  (I)", close))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)

	# Paper doll: slots either side of the portrait, hands underneath.
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 10)
	body.add_child(doll)
	doll.add_child(_slot_column(LEFT_SLOTS))
	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 10)
	doll.add_child(middle)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.panel_box(Color("15110d"), UiTheme.BORDER, 2, 3, 3))
	middle.add_child(frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.custom_minimum_size = PORTRAIT_SIZE
	frame.add_child(_portrait)
	var hands := HBoxContainer.new()
	hands.alignment = BoxContainer.ALIGNMENT_CENTER
	hands.add_theme_constant_override("separation", 14)
	middle.add_child(hands)
	for slot_name in HAND_SLOTS:
		hands.add_child(_make_equip_slot(slot_name))
	doll.add_child(_slot_column(RIGHT_SLOTS))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	right.add_child(_label("Backpack", 14, UiTheme.TEXT_DIM))
	_pack_grid = GridContainer.new()
	_pack_grid.columns = PACK_COLUMNS
	_pack_grid.add_theme_constant_override("h_separation", 6)
	_pack_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_pack_grid)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.custom_minimum_size = Vector2(300, 0)
	_stats.add_theme_font_size_override("normal_font_size", 13)
	_stats.add_theme_font_size_override("bold_font_size", 14)
	_stats.add_theme_color_override("default_color", UiTheme.TEXT)
	right.add_child(_stats)

	_container_box = VBoxContainer.new()
	_container_box.add_theme_constant_override("separation", 6)
	_container_box.visible = false
	root.add_child(_container_box)
	_container_box.add_child(HSeparator.new())
	var crow := HBoxContainer.new()
	_container_box.add_child(crow)
	_container_title = _label("", 15, UiTheme.GOLD)
	_container_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(_container_title)
	_take_all = _button("Take all", _take_all_pressed)
	crow.add_child(_take_all)
	_container_grid = GridContainer.new()
	_container_grid.columns = CONTAINER_COLUMNS
	_container_grid.add_theme_constant_override("h_separation", 6)
	_container_grid.add_theme_constant_override("v_separation", 6)
	_container_box.add_child(_container_grid)

	_hint = _label(HINT, 12, UiTheme.TEXT_DIM)
	root.add_child(_hint)


func _slot_column(slot_names: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	for slot_name in slot_names:
		col.add_child(_make_equip_slot(slot_name))
	return col


func _make_equip_slot(slot_name: String) -> ItemSlot:
	var s := ItemSlot.new()
	s.name = "Equip_" + slot_name
	s.placeholder = ItemDef.SLOT_NAMES.get(slot_name, slot_name)
	s.used.connect(_on_slot_used)
	_equip[slot_name] = s
	return s


## Makes `grid` hold exactly `count` ItemSlots.
func _resize_slots(grid: GridContainer, list: Array[ItemSlot], count: int) -> void:
	while list.size() < count:
		var s := ItemSlot.new()
		s.used.connect(_on_slot_used)
		grid.add_child(s)
		list.append(s)
	while list.size() > count:
		list.pop_back().queue_free()


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b
