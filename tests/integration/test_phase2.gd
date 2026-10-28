extends TestCase
## Phase 2 end to end on the real main scene: entering and leaving buildings
## (only from the hexes in front of a door), containers and locks, the
## inventory screen, fog of war, and save/load.

const DT := 1.0 / 30.0
const SAVE_DIR := "user://test_saves"

var main: Node
var world: World
var hud: Hud
var toasts: Array = []
var opened: Array = []


func before_each() -> void:
	GameState.start_new_game()
	SaveManager.save_dir = SAVE_DIR
	main = load("res://scenes/main.tscn").instantiate()
	runner.add_child(main)
	world = main.get_node("World")
	hud = main.get_node("HUD")
	toasts.clear()
	opened.clear()
	Events.toast_requested.connect(_on_toast)
	Events.container_opened.connect(_on_opened)
	await runner.get_tree().process_frame


func after_each() -> void:
	Events.toast_requested.disconnect(_on_toast)
	Events.container_opened.disconnect(_on_opened)
	for slot in SaveManager.slot_ids():
		SaveManager.delete_slot(slot)
	SaveManager.save_dir = "user://saves"
	runner.get_tree().paused = false
	main.queue_free()
	await runner.get_tree().process_frame


func _on_toast(text: String) -> void:
	toasts.append(text)


func _on_opened(c: ContainerState, title: String, opener: CharacterSheet) -> void:
	opened.append([c, title, opener])


func _walk_until_idle(max_seconds: float = 40.0) -> bool:
	var t := 0.0
	while t < max_seconds:
		var moving := false
		for m in world.party.members:
			m._process(DT)
			moving = moving or m.is_moving()
		if not moving:
			return true
		t += DT
	return false


## Lets deferred calls (map changes) run.
func _settle() -> void:
	for i in 3:
		await runner.get_tree().process_frame


func _prop(id: String) -> Prop:
	for p in world.props:
		if p.state_id() == id:
			return p
	return null


func _prop_of_kind(kind: String) -> Prop:
	for p in world.props:
		if p.interaction() == kind:
			return p
	return null


func _load(path: String, entry: String = "door") -> void:
	check(world.load_map(path, entry), "loaded %s" % path)


func test_enter_a_building_and_come_back_out() -> void:
	var cottage := _prop("millbrook_miller")
	check(cottage != null and cottage.is_transition(), "the cottage is a door")
	world.party.select_only(world.party.members[1])
	check(world.party.interact_with(cottage), "order accepted")
	check(_walk_until_idle(), "party gathers at the door")
	await _settle()
	check_eq(world.map.id, "millbrook_miller", "inside the cottage")
	check_eq(world.party.members.size(), GameState.party.size(), "whole party came in")
	var seen := {}
	for m in world.party.members:
		check(world.grid.is_walkable(m.hex), "%s on the floor" % m.sheet.display_name)
		check(not seen.has(m.hex), "no two members share a hex")
		seen[m.hex] = true
	check(not world.backdrop.texture == null and world.backdrop.visible, "room backdrop shown")
	check(not world.fog.enabled, "no fog indoors")
	var way_out := _prop_of_kind("exit")
	check(way_out != null, "there is a way out")
	world.party.select_all()
	check(world.party.interact_with(way_out), "exit order accepted")
	check(_walk_until_idle(), "walks to the door")
	await _settle()
	check_eq(world.map.id, "millbrook_outskirts", "back outside")
	cottage = _prop("millbrook_miller")
	var door: Vector2i = cottage.entry_hex(world.grid)
	var leader := world.party.members[0]
	check(Hex.distance(leader.hex, door) <= 3, "arrived at the cottage door (%d hexes away)" % Hex.distance(leader.hex, door))


func test_buildings_are_entered_only_from_the_door_zone() -> void:
	var cottage := _prop("millbrook_miller")
	var zone := world.door_zone_of(cottage)
	var door: Vector2i = cottage.door_hex(world.grid)
	check(not zone.is_empty(), "the cottage has a door zone")
	for h in zone:
		check(world.grid.is_walkable(h) and not cottage.cells.has(h), "zone hex %s is open ground outside" % h)
		check_eq(Hex.distance(h, door), 1, "zone hex %s touches the door" % h)
	world.party.select_all()
	var leader := world.party.leader()
	# Walking onto the zone with an ordinary move order doesn't go in.
	world.party.move_selected_to(zone[0])
	check(_walk_until_idle(), "party walks to the door")
	await _settle()
	check_eq(world.map.id, "millbrook_outskirts", "a move order onto the zone stays outside")
	world.fog.refresh()
	check_eq(world.door_at(zone[0]), cottage, "the zone belongs to the cottage")
	# Round the back: ground the cottage's picture overlaps (behind its roof).
	var ring: Array[Vector2i] = []
	for c in cottage.cells:
		for n in Hex.neighbors(c):
			if not cottage.cells.has(n) and not ring.has(n) and world.grid.is_walkable(n):
				ring.append(n)
	var behind := ring[0]
	for h in ring:
		if world.grid.hex_to_world(h).y < world.grid.hex_to_world(behind).y:
			behind = h
	check(cottage.sprite_rect().has_point(world.grid.hex_to_world(behind)), "the hex behind is under the picture")
	check(not zone.has(behind), "the hex behind isn't in the door zone")
	world._on_click(world.grid.hex_to_world(behind), false)
	check(leader.pending_interaction == null, "a click behind the cottage is just a move")
	check(_walk_until_idle(), "party walks round the back")
	await _settle()
	check_eq(world.map.id, "millbrook_outskirts", "walking round the cottage stays outside")
	check(Hex.distance(leader.hex, behind) <= 1, "leader got round the back")
	# The walls and roof aren't a way in either.
	world._on_click(world.grid.hex_to_world(cottage.cells[cottage.cells.size() / 2]), false)
	check(leader.pending_interaction == null, "a click on the roof is just a move")
	_walk_until_idle()
	await _settle()
	check_eq(world.map.id, "millbrook_outskirts", "clicking the roof stays outside")
	# Hovering: the zone lights up on the zone, and shows faintly on the building.
	var canvas := runner.get_viewport().get_canvas_transform()
	world._mouse_screen = canvas * world.grid.hex_to_world(zone[0])
	world._refresh_hover(true)
	check_eq(world.cursor.door_zone.size(), zone.size(), "hovering the zone shows it")
	check(world.cursor.door_zone_hot and cottage.highlighted, "and lights it up")
	var roof := Vector2.ZERO
	for c in cottage.cells:
		if cottage.is_opaque_at(world.grid.hex_to_world(c)):
			roof = world.grid.hex_to_world(c)
			break
	world._mouse_screen = canvas * roof
	world._refresh_hover(true)
	check(not world.cursor.door_zone.is_empty() and not world.cursor.door_zone_hot, "the building shows where its door zone is")
	check(not cottage.highlighted, "but isn't something to click")
	# A click on the zone goes in.
	world._on_click(world.grid.hex_to_world(zone[0]), false)
	check(leader.pending_interaction == cottage, "a click on the zone heads for the door")
	check(_walk_until_idle(), "party gathers at the door")
	await _settle()
	check_eq(world.map.id, "millbrook_miller", "inside the cottage")


func test_open_a_container_and_take_everything() -> void:
	_load("res://data/maps/millbrook_miller.json")
	var drawers := _prop("drawers")
	check(drawers != null and drawers.container != null, "drawers are a container")
	var gold_before := GameState.gold
	world.party.select_only(world.party.members[0])
	check(world.party.interact_with(drawers), "order accepted")
	check(_walk_until_idle(), "walks over")
	check_eq(opened.size(), 1, "container opened")
	check(hud._inventory.visible and hud._inventory.container == drawers.container, "shown on the inventory screen")
	check(runner.get_tree().paused, "game paused while the inventory is open")
	var opener: CharacterSheet = opened[0][2]
	hud._inventory._take_all_pressed()
	check_eq(GameState.gold, gold_before + 12, "gold into the purse")
	check_eq(opener.inventory.count("apple"), 5, "apples taken")
	check(drawers.container.inventory.is_empty(), "drawers empty")
	hud._inventory.close()
	check(not runner.get_tree().paused, "unpaused on close")
	# Leave and come back: the drawers stay empty.
	_load(GameConfig.starting_map_path, "millbrook_miller")
	_load("res://data/maps/millbrook_miller.json")
	check(_prop("drawers").container.inventory.is_empty(), "contents persist across map changes")


func test_locked_chest_needs_the_key() -> void:
	_load("res://data/maps/millbrook_reeve.json")
	var box := _prop("strongbox")
	check(box.container.locked, "strongbox starts locked")
	var garrick := world.party.members[0]
	box.interact(garrick)  # Garrick has no key and no thieves' tools
	check(opened.is_empty(), "won't open")
	check(box.container.locked, "still locked")
	check(not toasts.is_empty() and str(toasts.back()).contains("locked"), "says it's locked")
	garrick.sheet.inventory.add_item("reeve_key")
	box.interact(garrick)
	check(not box.container.locked, "the key opens it")
	check_eq(opened.size(), 1, "and it opens")


func test_thieves_tools_pick_a_lock_eventually() -> void:
	_load("res://data/maps/millbrook_smithy.json")
	var chest := _prop("locked_chest")
	var wren: PartyMember = null
	for m in world.party.members:
		if m.sheet.id == "wren":
			wren = m
	for i in 30:  # DC 12 with +5 or so: should succeed well within 30 tries
		if not chest.container.locked:
			break
		chest.interact(wren)
	check(not chest.container.locked, "Wren picks the lock")


func test_inventory_screen_equips_and_updates_the_sidebar() -> void:
	hud.open_inventory()
	check(hud._inventory.visible, "inventory opens")
	var sheet: CharacterSheet = hud._inventory.sheet
	var slot_name := "ring_1"
	sheet.inventory.add_item("ring_of_protection")
	var ring_index := -1
	for i in sheet.inventory.capacity():
		if sheet.inventory.get_at(i) != null and sheet.inventory.get_at(i).id == "ring_of_protection":
			ring_index = i
	var before := sheet.armor_class
	var slot: ItemSlot = hud._inventory._pack[ring_index]
	hud._inventory._on_slot_used(slot)  # right-click equips
	check(sheet.equipped(slot_name) != null, "ring equipped by right-click")
	check_eq(sheet.armor_class, before + 1, "AC up by one")
	var card: PortraitCard = hud._cards[GameState.party.find(sheet)]
	check(card._stats_label.text.contains("AC %d" % sheet.armor_class), "sidebar shows the new AC")
	hud._inventory.close()


func test_fog_reveals_as_the_party_moves() -> void:
	check(world.fog.enabled, "fog on outdoors")
	var far := Hex.offset_to_axial(Vector2i(30, 30))
	check(not world.fog.is_explored(far), "the bridge area starts unexplored")
	world.party.select_all()
	world.party.move_selected_to(far)
	check(_walk_until_idle(), "walks there")
	world.fog.refresh()
	check(world.fog.is_explored(far), "explored after walking there")


func test_save_and_load_restore_the_game() -> void:
	_load("res://data/maps/millbrook_herbalist.json")
	var remedies := _prop("remedies")
	InventoryOps.take_all(remedies.container, GameState.party[1])
	GameState.add_gold(5)
	var gold := GameState.gold
	var spots := world.party_positions()
	check(SaveManager.save_game("slot_1", "Test save", world), "saved")
	check(SaveManager.describe_slot("slot_1").get("exists", false), "slot shows up")
	check_eq(SaveManager.describe_slot("slot_1").get("label"), "Test save", "label kept")
	# Change everything, then load.
	GameState.add_gold(500)
	GameState.party[1].inventory.remove_item("potion_of_healing", 99)
	_load(GameConfig.starting_map_path, "")
	check(SaveManager.load_game("slot_1"), "loaded")
	await _settle()
	check_eq(world.map.id, "millbrook_herbalist", "back in the herbalist's")
	check_eq(GameState.gold, gold, "gold restored")
	check(GameState.party[1].inventory.count("potion_of_healing") >= 2, "taken potions restored")
	check(_prop("remedies").container.inventory.is_empty(), "the shelf is still empty")
	check_eq(world.party_positions(), spots, "everyone where they were")


func test_quicksave_and_quickload() -> void:
	await hud.quicksave()
	check(SaveManager.has_save(SaveManager.QUICKSAVE), "quicksave written")
	var gold := GameState.gold
	GameState.add_gold(99)
	hud.quickload()
	await _settle()
	check_eq(GameState.gold, gold, "quickload restored the purse")


func test_drop_and_pick_up_items() -> void:
	_load("res://data/maps/millbrook_miller.json")
	var m := world.party.members[0]
	var sheet := m.sheet
	hud.open_inventory()
	check(hud._inventory.showing_ground, "with no chest open, the panel shows the ground")
	var ground: ContainerState = hud._inventory.container
	check(ground != null and ground.inventory.is_empty(), "nothing on the ground yet")
	var potion := -1
	for i in sheet.inventory.capacity():
		if sheet.inventory.get_at(i) != null and sheet.inventory.get_at(i).id == "potion_of_healing":
			potion = i
	check_eq(InventoryOps.move(InventoryOps.backpack(sheet, potion), InventoryOps.container_slot(ground, 0)), "",
			"dropped")
	check_eq(sheet.inventory.count("potion_of_healing"), 0, "gone from the backpack")
	var pile: Prop = world.props_by_hex.get(m.hex)
	check(pile != null and pile.def.id == "item_pile", "a pile appears where they stand")
	hud._inventory.close()
	# Leave and come back: the pile is still there with the potion in it.
	_load(GameConfig.starting_map_path, "millbrook_miller")
	_load("res://data/maps/millbrook_miller.json")
	pile = world.props_by_hex.get(m.hex)
	check(pile != null and pile.container.inventory.count("potion_of_healing") == 1, "pile persists")
	# Click it: the leader walks over and it opens like a chest; take everything.
	world.party.select_only(world.party.members[1])
	var had := world.party.members[1].sheet.inventory.count("potion_of_healing")
	check(world.party.interact_with(pile), "order accepted")
	check(_walk_until_idle(), "walks to the pile")
	check_eq(opened.size(), 1, "the pile opens")
	hud._inventory._take_all_pressed()
	check_eq(world.party.members[1].sheet.inventory.count("potion_of_healing"), had + 1, "picked up")
	check(world.props_by_hex.get(m.hex) == null or world.props_by_hex.get(m.hex).def.id != "item_pile",
			"the empty pile disappears")
	hud._inventory.close()
	check(not GameState.to_dict()["maps"].get("millbrook_miller", {}).get("containers", {}).has(
			"ground_%d_%d" % [m.hex.x, m.hex.y]), "empty piles are not saved")


func test_shift_drop_asks_how_many() -> void:
	var sheet := world.party.members[0].sheet
	sheet.inventory.add_item("arrows", 12)
	hud.open_inventory()
	var from := -1
	for i in sheet.inventory.capacity():
		if sheet.inventory.get_at(i) != null and sheet.inventory.get_at(i).id == "arrows":
			from = i
	var to := sheet.inventory.first_free()
	var d := ItemSlot.ask_split(hud, InventoryOps.backpack(sheet, from), InventoryOps.backpack(sheet, to))
	check(d != null, "a stack of 12 asks how many")
	await runner.get_tree().process_frame
	check_eq(d.count(), 6, "starting at half")
	d.set_count(5)
	d.confirm()
	await runner.get_tree().process_frame
	check_eq(sheet.inventory.get_at(to).qty, 5, "5 moved")
	check_eq(sheet.inventory.get_at(from).qty, 7, "7 stayed")
	check(not is_instance_valid(d) or d.is_queued_for_deletion() or not d.is_inside_tree(), "the dialog closes")
	var one := sheet.inventory.first_free()
	sheet.inventory.set_at(one, ItemStack.create("apple", 1))
	check(ItemSlot.ask_split(hud, InventoryOps.backpack(sheet, one), InventoryOps.backpack(sheet, 0)) == null,
			"a single item doesn't ask")
	var c := ItemSlot.ask_split(hud, InventoryOps.backpack(sheet, from), {}, world.party.members[1].sheet)
	var had := world.party.members[1].sheet.inventory.count("arrows")
	c.set_count(2)
	c.cancel()
	await runner.get_tree().process_frame
	check_eq(world.party.members[1].sheet.inventory.count("arrows"), had, "cancel moves nothing")
	hud._inventory.close()


## A chest on the current map with `trap` set, and the party member next to it.
func _trapped_chest(trap: Dictionary) -> Prop:
	var chest: Prop = null
	for p in world.props:
		if p.container != null and not p.container.locked:
			chest = p
			break
	chest.container.trap = trap
	return chest


func test_a_found_trap_asks_what_to_do() -> void:
	_load("res://data/maps/millbrook_miller.json")
	var chest := _trapped_chest({"name": "poison needle", "find_dc": 5, "disarm": {"dc": 1, "ability": "dex",
			"tool": "thieves_tools"}, "save": "con", "save_dc": 12, "damage": "2d6", "damage_type": "poison",
			"state": "armed"})
	var opener := world.party.members[0].sheet
	chest.interact(world.party.members[0])
	check(chest.trap_dialog != null, "the party notices it and is asked")
	check(runner.get_tree().paused, "the game waits for an answer")
	check(opened.is_empty(), "the chest stays shut meanwhile")
	chest.trap_dialog.choose(2)  # leave it
	check(not runner.get_tree().paused, "unpaused again")
	check(opened.is_empty() and Traps.is_found(chest.container.trap), "left alone, still trapped")
	chest.trap_dialog = null
	chest.interact(world.party.members[0])
	check(chest.trap_dialog != null, "asked again next time")
	chest.trap_dialog.choose(0)  # Wren disarms it (DC 1)
	check_eq(chest.container.trap["state"], Traps.DISARMED, "disarmed")
	check_eq(opened.size(), 1, "and the chest opens")
	check_eq(opener.hp_current, opener.hp_max, "nobody hurt")
	hud._inventory.close()


func test_an_unnoticed_trap_goes_off_on_the_opener() -> void:
	_load("res://data/maps/millbrook_miller.json")
	var chest := _trapped_chest({"name": "fire glyph", "find_dc": 40, "save": "dex", "save_dc": 99,
			"damage": "4", "damage_type": "fire", "state": "armed"})
	var opener := world.party.members[0].sheet
	var hp := opener.hp_current
	chest.interact(world.party.members[0])
	check(chest.trap_dialog == null, "no warning")
	check_eq(opener.hp_current, hp - 4, "the opener is burned")
	check(toasts.any(func(t: String) -> bool: return t.contains("fire glyph")), "with a message: %s" % [toasts])
	check_eq(opened.size(), 1, "the chest opens all the same")
	check_eq(chest.container.trap["state"], Traps.SPRUNG, "spent")
	hud._inventory.close()


func test_open_it_anyway() -> void:
	_load("res://data/maps/millbrook_miller.json")
	var chest := _trapped_chest({"name": "poison needle", "find_dc": 5, "save": "con", "save_dc": 99,
			"damage": "3", "damage_type": "poison", "disarm": {"dc": 10, "ability": "dex", "tool": "thieves_tools"},
			"state": "armed"})
	var m := world.party.members[1]
	var hp := m.sheet.hp_current
	chest.interact(m)
	chest.trap_dialog.choose(1)  # open it anyway
	check_eq(m.sheet.hp_current, hp - 3, "the needle pricks %s" % m.sheet.display_name)
	check_eq(opened.size(), 1, "the chest opens")
	hud._inventory.close()


func test_the_framed_inventory_fits_on_screen() -> void:
	var smith: NpcDef = Data.npcs["bram"]  # the biggest stock
	hud._inventory.open_shop(world.party.members[0].sheet, GameState.vendor_stock(smith), "Wares",
			smith.trade_terms())
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	var framed := hud._inventory.get_global_rect().grow(UiTheme.FRAME_OUTSET)
	var screen := Rect2(Vector2.ZERO, hud._inventory.get_viewport_rect().size)
	check(screen.encloses(framed), "frame %s within the screen %s" % [framed, screen])
	hud._inventory.close()

