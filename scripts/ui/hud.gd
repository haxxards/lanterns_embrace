class_name Hud
extends CanvasLayer
## In-game HUD: party sidebar (minimap + portraits + purse), hover info, pause
## banner, toasts, sign/message box, controls help, and the modal screens
## (inventory, Esc menu, save/load). Built in code so the layout is easy to
## read and change in one place. The game pauses while a modal screen is open.

const SIDEBAR_WIDTH := 232.0
const HELP_TEXT := """[b]Controls[/b]
Left click ground  –  move selected
Left click member / portrait  –  select   (Shift: add)
Left drag  –  box select        Ctrl+A  –  select all
1-%d  –  select member        Right click  –  deselect
Left click a sign / chest  –  read / open
Left click the hexes in front of a door  –  go in (point at a building to see them)
Left click a townsperson  –  talk (1-9 picks an answer)
In a fight: click ground to move, an enemy to attack  ·  Space  –  end turn
In a fight: spell and ability buttons in the combat bar, then click a target
I  –  inventory     J  –  journal     B  –  spells     R  –  rest
Esc  –  menu (or cancel a spell's targeting)
F5  –  quicksave        F9  –  quickload
WASD / arrows / screen edge / middle drag  –  pan
Mouse wheel, + / -  –  zoom        C  –  centre on selection
Space  –  pause / resume        G  –  toggle grid
F3  –  hover info        F1  –  toggle this help"""

var world: World

var _root: Control
var _map_label: Label
var _minimap: Minimap
var _party_label: Label
var _cards_box: VBoxContainer
var _cards: Array[PortraitCard] = []
var _info_panel: PanelContainer
var _info_label: Label
var _help_panel: PanelContainer
var _pause_banner: PanelContainer
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _message_panel: PanelContainer
var _message_title: Label
var _message_body: Label
var _gold_label: Label
var _inventory: InventoryScreen
var _menu: GameMenu
var _save_load: SaveLoadScreen
var _dialogue: DialogueWindow
var _journal: JournalScreen
var _spells: SpellsScreen
var _rest: RestDialog
var _game_over: PanelContainer
var _combat_hud: CombatHud
## Pause state from before the first modal screen opened (restored on close).
var _paused_before_modal: Variant = null
## Screenshot of the game view taken when the menu opens (save thumbnail).
var _snapshot: Image


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2  # above the colour grade (layer 1)
	var grade := ColorGrade.new()
	grade.name = "ColorGrade"
	add_child(grade)
	grade.setup(SIDEBAR_WIDTH)
	_build()
	Events.map_loaded.connect(_on_map_loaded)
	Events.selection_changed.connect(_on_selection_changed)
	Events.hover_info_changed.connect(_on_hover_info)
	Events.message_requested.connect(show_message)
	Events.toast_requested.connect(show_toast)
	Events.pause_changed.connect(func(_p: bool) -> void: _update_pause_banner())
	Events.party_order_issued.connect(func() -> void: _message_panel.visible = false)
	Events.container_opened.connect(_on_container_opened)
	Events.dialogue_requested.connect(_on_dialogue_requested)
	Events.party_defeated.connect(_show_game_over)
	GameState.gold_changed.connect(func(g: int) -> void: _gold_label.text = "Gold  %d" % g)
	SaveManager.game_loaded.connect(func(_slot: String) -> void: _close_all_modals())


func bind(w: World) -> void:
	world = w
	world.camera.right_ui_width = SIDEBAR_WIDTH
	_combat_hud.bind(w.combat)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help_panel.visible = not _help_panel.visible
	elif event.is_action_pressed("toggle_debug"):
		_info_panel.visible = not _info_panel.visible
	elif event.is_action_pressed("toggle_inventory"):
		if _inventory.visible:
			_inventory.close()
		elif not _modal_open():
			open_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_journal"):
		if _journal.visible:
			_journal.close()
		elif not _modal_open():
			open_journal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_spells"):
		if _spells.visible:
			_spells.close()
		elif not _modal_open():
			open_spells()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rest"):
		if _rest.visible:
			_rest.close()
		elif not _modal_open():
			open_rest()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_knock_out") and GameConfig.debug_keys and world.party.leader():
		# Testing aid: knock the leader out (Ctrl+K) or kill them (Ctrl+Shift+K),
		# to try healing and the temple's raise dead.
		var s := world.party.leader().sheet
		if Input.is_key_pressed(KEY_SHIFT):
			s.die()
			show_toast("%s is dead. (debug: Ctrl+Shift+K)" % s.display_name)
		else:
			s.damage(s.hp_current)
			show_toast("%s is knocked out. (debug: Ctrl+K)" % s.display_name)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quicksave"):
		quicksave()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quickload"):
		quickload()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		# Esc closes the top-most thing, or opens the menu.
		if world != null and world.combat.active and not world.combat.targeting.is_empty() and not _modal_open():
			world.combat.cancel_targeting()  # stop choosing a target for a spell
		elif _message_panel.visible:
			_message_panel.visible = false
		elif _game_over.visible:
			pass
		elif _dialogue.visible:
			_dialogue.close()
		elif _journal.visible:
			_journal.close()
		elif _spells.visible:
			_spells.close()
		elif _rest.visible:
			_rest.close()
		elif _save_load.visible:
			_save_load.close()
		elif _inventory.visible:
			_inventory.close()
		elif _menu.visible:
			_menu.visible = false
			_on_modal_closed()
		else:
			open_menu()
		get_viewport().set_input_as_handled()


# --- public ------------------------------------------------------------------------

func show_message(title: String, text: String) -> void:
	_message_title.text = title
	_message_body.text = text
	_message_panel.visible = true


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_toast.hide)


## Inventory of the selection's leader (or the first member).
func open_inventory() -> void:
	if world == null or world.party.members.is_empty():
		return
	var m: PartyMember = world.party.leader() if world.party.leader() else world.party.members[0]
	_enter_modal()
	_inventory.open(m.sheet)


func open_menu() -> void:
	# Grab the game view for the save thumbnail before the menu covers it.
	_snapshot = await _capture_view()
	_enter_modal()
	_menu.visible = true
	Audio.play_sfx("ui_open")


## In a fight, saving waits for one of the party's turns, between moves
## (loading carries on that turn from there).
func _can_save() -> bool:
	if GameState.in_combat() and world != null:
		if not world.combat.is_player_turn() or not world.combat.targeting.is_empty():
			show_toast("In a fight, save on one of your turns, between moves.")
			return false
	return true


func quicksave() -> void:
	if not _can_save():
		return
	if world == null or world.map == null:
		return
	var img := _snapshot if _modal_open() else await _capture_view()
	if SaveManager.save_game(SaveManager.QUICKSAVE, "Quicksave", world, img):
		show_toast("Quicksaved.")


func quickload() -> void:
	if not SaveManager.has_save(SaveManager.QUICKSAVE):
		show_toast("No quicksave yet (F5 makes one).")
		return
	if SaveManager.load_game(SaveManager.QUICKSAVE):
		show_toast("Quickloaded.")


## Screenshot of the map area (without the sidebar), or null when headless.
func _capture_view() -> Image:
	if DisplayServer.get_name() == "headless":
		return null  # nothing is drawn, and frame_post_draw never fires
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	var img: Image = tex.get_image() if tex else null
	if img == null or img.is_empty():
		return null
	var w := img.get_width() - int(SIDEBAR_WIDTH * img.get_width() / get_viewport().get_visible_rect().size.x)
	return img.get_region(Rect2i(0, 0, maxi(1, w), img.get_height()))


func _modal_open() -> bool:
	return _inventory.visible or _menu.visible or _save_load.visible or _dialogue.visible \
			or _journal.visible or _spells.visible or _rest.visible or _game_over.visible


## The "PAUSED" banner is only for the player's own pause, not for menus.
func _update_pause_banner() -> void:
	_pause_banner.visible = get_tree().paused and _paused_before_modal == null


func _enter_modal() -> void:
	if not _modal_open() and _paused_before_modal == null:
		_paused_before_modal = get_tree().paused
		world.set_paused(true)
	_update_pause_banner()


func _on_modal_closed() -> void:
	if _modal_open() or _paused_before_modal == null:
		return
	var was: bool = _paused_before_modal
	_paused_before_modal = null
	world.set_paused(was)
	_update_pause_banner()


func _close_all_modals() -> void:
	_inventory.close()
	_save_load.close()
	_dialogue.visible = false
	_journal.visible = false
	_spells.visible = false
	_rest.visible = false
	_game_over.visible = false
	_menu.visible = false
	_on_modal_closed()


func open_journal() -> void:
	_enter_modal()
	_journal.open()


## Spells and abilities of the selection's leader (or the first member).
func open_spells() -> void:
	if world == null or world.party.members.is_empty():
		return
	var m: PartyMember = world.party.leader() if world.party.leader() else world.party.members[0]
	_enter_modal()
	_spells.open(GameState.party, m.sheet)


func open_rest() -> void:
	if world == null:
		return
	_enter_modal()
	_rest.open(world)


func _on_dialogue_requested(npc: Npc, speaker: PartyMember) -> void:
	_enter_modal()
	_dialogue.open(npc, speaker)


## After a conversation: the NPC strolls again, and a shop opens if asked for.
func _on_dialogue_closed(runner: DialogueRunner, npc: Npc) -> void:
	if is_instance_valid(npc):
		npc.end_talk()
		Events.dialogue_ended.emit(npc)
		if runner.wants_shop and npc.def.is_vendor():
			_inventory.open_shop(runner.speaker, GameState.vendor_stock(npc.def),
					"%s's wares" % npc.def.display_name, npc.def.trade_terms())
			return
	_on_modal_closed()


func _show_game_over() -> void:
	if _game_over.visible:
		return
	_dialogue.visible = false
	_inventory.close()
	_enter_modal()
	_game_over.visible = true


## The pile of dropped items under a party member (made on demand).
func _ground_under(sheet: CharacterSheet) -> ContainerState:
	for m in world.party.members:
		if m.sheet == sheet:
			return world.ground_pile(m.hex, true)
	return null


func _on_container_opened(container: ContainerState, title: String, opener: CharacterSheet) -> void:
	_enter_modal()
	_inventory.open(opener, container, title)


func _on_menu_resume() -> void:
	_menu.visible = false
	_on_modal_closed()


func _on_menu_save() -> void:
	if not _can_save():
		return
	_menu.visible = false
	var default := "%s, %s" % [world.map.display_name, Time.get_date_string_from_system()]
	_save_load.open(true, default)


func _on_menu_load() -> void:
	_menu.visible = false
	_save_load.open(false)


func _on_save_requested(slot: String, label: String) -> void:
	if SaveManager.save_game(slot, label, world, _snapshot):
		show_toast("Game saved.")
	_save_load.close()


func _on_load_requested(slot: String) -> void:
	if not SaveManager.load_game(slot):
		show_toast("That save could not be loaded.")


# --- signal handlers ------------------------------------------------------------

func _on_map_loaded(_map_id: String) -> void:
	_map_label.text = world.map.display_name
	_minimap.bind(world)
	_rebuild_cards()


func _rebuild_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for i in world.party.members.size():
		var card := PortraitCard.new()
		card.setup(world.party.members[i], i)
		card.pressed.connect(_on_card_pressed)
		card.double_pressed.connect(_on_card_double_pressed)
		_cards_box.add_child(card)
		_cards.append(card)
	_party_label.text = "Party  %d / %d" % [world.party.members.size(), GameConfig.max_party_size]
	_on_selection_changed(world.party.selected)


func _on_selection_changed(selected: Array) -> void:
	for c in _cards:
		c.set_selected(selected.has(c.member))
	# Clicking portraits while the inventory is open switches whose it shows.
	if _inventory.visible and not selected.is_empty():
		_inventory.show_sheet((selected[0] as PartyMember).sheet)
	if _spells.visible and not selected.is_empty():
		_spells.show_sheet((selected[0] as PartyMember).sheet)


func _on_card_pressed(card: PortraitCard, shift: bool) -> void:
	if shift:
		world.party.toggle(card.member)
	else:
		world.party.select_only(card.member)


func _on_card_double_pressed(card: PortraitCard) -> void:
	world.party.select_only(card.member)
	world.camera.center_on(card.member.global_position)


func _on_hover_info(info: Dictionary) -> void:
	if not info.get("in_bounds", false):
		_info_label.text = "Outside the map"
		return
	var h: Vector2i = info["hex"]
	var cell: Vector2i = info["cell"]
	var lines := PackedStringArray()
	lines.append("Hex  q %d, r %d   (col %d, row %d)" % [h.x, h.y, cell.x, cell.y])
	if info.has("terrain"):
		var t := "%s   cost ×%s" % [info["terrain"], str(info["move_cost"])]
		if not info["walkable"]:
			t += "   (blocked)"
		lines.append(t)
	if info.has("member"):
		lines.append(str(info["member"]))
	elif info.has("prop"):
		lines.append(str(info["prop"]))
	if info.has("action"):
		lines.append(str(info["action"]))
	if info.has("path_hexes"):
		lines.append("Path  %d hexes · %d ft" % [info["path_hexes"], info["path_feet"]])
	_info_label.text = "\n".join(lines)


# --- layout -------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UiTheme.build()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_sidebar()
	_build_left_column()
	_build_top_banners()
	_build_combat()
	_build_message_box()
	_build_modals()


func _build_sidebar() -> void:
	var panel := PanelContainer.new()
	panel.name = "Sidebar"
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER, 2, 0, 10))
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -SIDEBAR_WIDTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_map_label = Label.new()
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_map_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_map_label)

	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.display_width = SIDEBAR_WIDTH - 24.0
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_minimap)

	vbox.add_child(HSeparator.new())
	var party_row := HBoxContainer.new()
	vbox.add_child(party_row)
	_party_label = Label.new()
	_party_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_party_label.add_theme_font_size_override("font_size", 12)
	_party_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_row.add_child(_party_label)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_gold_label.add_theme_font_size_override("font_size", 12)
	_gold_label.text = "Gold  %d" % GameState.gold
	party_row.add_child(_gold_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_cards_box = VBoxContainer.new()
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_cards_box)

	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	vbox.add_child(buttons)
	_add_button(buttons, "Inventory", open_inventory)
	_add_button(buttons, "Journal", open_journal)
	_add_button(buttons, "Spells", open_spells)
	_add_button(buttons, "Rest", open_rest)
	_add_button(buttons, "Menu", open_menu)
	_add_button(buttons, "Select all", func() -> void: world.party.select_all())
	_add_button(buttons, "Pause", func() -> void: world.set_paused(not get_tree().paused))
	_add_button(buttons, "Help", func() -> void: _help_panel.visible = not _help_panel.visible)


func _build_left_column() -> void:
	var column := VBoxContainer.new()
	column.name = "LeftColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_MINSIZE, 10)
	_root.add_child(column)

	_info_panel = PanelContainer.new()
	_info_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.07, 0.06, 0.05, 0.82), UiTheme.BORDER, 1, 4, 8))
	_info_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_info_panel)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.custom_minimum_size = Vector2(250, 0)
	_info_label.text = "Hover the map for details"
	_info_panel.add_child(_info_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_help_panel = PanelContainer.new()
	_help_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.07, 0.06, 0.05, 0.85), UiTheme.BORDER, 1, 4, 10))
	_help_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_help_panel)
	var help := RichTextLabel.new()
	help.bbcode_enabled = true
	help.fit_content = true
	help.scroll_active = false
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.add_theme_font_size_override("normal_font_size", 13)
	help.add_theme_font_size_override("bold_font_size", 14)
	help.add_theme_color_override("default_color", UiTheme.TEXT)
	help.text = HELP_TEXT % mini(9, GameConfig.max_party_size)
	_help_panel.add_child(help)


func _build_top_banners() -> void:
	var stack := VBoxContainer.new()
	stack.name = "TopBanners"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stack.offset_top = 12
	stack.offset_right = -SIDEBAR_WIDTH
	stack.add_theme_constant_override("separation", 8)
	_root.add_child(stack)

	_pause_banner = PanelContainer.new()
	_pause_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_banner.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.1, 0.08, 0.05, 0.9), UiTheme.GOLD, 2, 4, 10))
	var pl := Label.new()
	pl.text = "PAUSED   ·   Space to resume (orders can still be given)"
	pl.add_theme_color_override("font_color", UiTheme.GOLD)
	_pause_banner.add_child(pl)
	_pause_banner.visible = false
	stack.add_child(_pause_banner)

	_toast = PanelContainer.new()
	_toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.1, 0.05, 0.04, 0.85), Color("8c3b2e"), 1, 4, 8))
	_toast_label = Label.new()
	_toast.add_child(_toast_label)
	_toast.visible = false
	stack.add_child(_toast)


## The fight's initiative strip (top), action bar and log (bottom).
func _build_combat() -> void:
	_combat_hud = CombatHud.new()
	_combat_hud.name = "CombatLayer"
	_root.add_child(_combat_hud)
	_combat_hud.offset_right = -SIDEBAR_WIDTH
	var banners := _root.get_node("TopBanners")
	banners.add_child(_combat_hud.order_panel)
	banners.move_child(_combat_hud.order_panel, 0)


func _build_message_box() -> void:
	var center := CenterContainer.new()
	center.name = "MessageLayer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -SIDEBAR_WIDTH
	_root.add_child(center)

	_message_panel = PanelContainer.new()
	_message_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.BG, UiTheme.BORDER_LIGHT, 2, 6, 16))
	_message_panel.visible = false
	_message_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_message_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_message_panel.add_child(vbox)
	_message_title = Label.new()
	_message_title.add_theme_color_override("font_color", UiTheme.GOLD)
	_message_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_message_title)
	_message_body = Label.new()
	_message_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_body.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(_message_body)
	var close := Button.new()
	close.text = "Close  (Esc)"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: _message_panel.visible = false)
	vbox.add_child(close)


## Inventory, menu and save/load screens, centred over the map area.
func _build_modals() -> void:
	var center := CenterContainer.new()
	center.name = "ModalLayer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -SIDEBAR_WIDTH
	_root.add_child(center)
	_inventory = InventoryScreen.new()
	_inventory.name = "Inventory"
	_inventory.ground_provider = _ground_under
	_inventory.closed.connect(_on_modal_closed)
	center.add_child(_inventory)
	_menu = GameMenu.new()
	_menu.name = "GameMenu"
	_menu.resume_requested.connect(_on_menu_resume)
	_menu.save_requested.connect(_on_menu_save)
	_menu.load_requested.connect(_on_menu_load)
	_menu.quicksave_requested.connect(quicksave)
	_menu.quickload_requested.connect(quickload)
	center.add_child(_menu)
	_save_load = SaveLoadScreen.new()
	_save_load.name = "SaveLoad"
	_save_load.closed.connect(_on_modal_closed)
	_save_load.save_requested.connect(_on_save_requested)
	_save_load.load_requested.connect(_on_load_requested)
	center.add_child(_save_load)
	_journal = JournalScreen.new()
	_journal.name = "Journal"
	_journal.closed.connect(_on_modal_closed)
	center.add_child(_journal)
	_spells = SpellsScreen.new()
	_spells.name = "Spells"
	_spells.closed.connect(_on_modal_closed)
	center.add_child(_spells)
	_rest = RestDialog.new()
	_rest.name = "Rest"
	_rest.closed.connect(_on_modal_closed)
	center.add_child(_rest)
	_game_over = _build_game_over()
	center.add_child(_game_over)
	# The conversation panel sits along the bottom of the map area.
	var bottom := Control.new()
	bottom.name = "DialogueLayer"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.offset_right = -SIDEBAR_WIDTH
	_root.add_child(bottom)
	_dialogue = DialogueWindow.new()
	_dialogue.name = "Dialogue"
	bottom.add_child(_dialogue)
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dialogue.offset_left = 24
	_dialogue.offset_right = -24
	_dialogue.offset_bottom = -16
	_dialogue.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialogue.closed.connect(_on_dialogue_closed)
	# The message box stays above the modal screens.
	_root.move_child(_root.get_node("MessageLayer"), -1)


func _build_game_over() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "GameOver"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.08, 0.03, 0.03, 0.97), Color("8c3b2e"), 2, 6, 24))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(340, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "The party has fallen"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("e05a4a"))
	box.add_child(title)
	var text := Label.new()
	text.text = "No one is left standing to carry the fallen to a temple."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	var load_b := Button.new()
	load_b.text = "Load a saved game"
	load_b.focus_mode = Control.FOCUS_NONE
	load_b.pressed.connect(func() -> void: _save_load.open(false))
	box.add_child(load_b)
	var quit_b := Button.new()
	quit_b.text = "Quit to desktop"
	quit_b.focus_mode = Control.FOCUS_NONE
	quit_b.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit_b)
	return panel


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	b.pressed.connect(Audio.play_sfx.bind("ui_click"))
	parent.add_child(b)
