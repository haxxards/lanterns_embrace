extends TestCase
## Phase 2 end to end on the real main scene: entering and leaving buildings,
## containers and locks, the inventory screen, fog of war, and save/load.

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
	hud._inventory._take_all()
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
	hud._inventory._take_all()
	check_eq(world.party.members[1].sheet.inventory.count("potion_of_healing"), had + 1, "picked up")
	check(world.props_by_hex.get(m.hex) == null or world.props_by_hex.get(m.hex).def.id != "item_pile",
			"the empty pile disappears")
	hud._inventory.close()
	check(not GameState.to_dict()["maps"].get("millbrook_miller", {}).get("containers", {}).has(
			"ground_%d_%d" % [m.hex.x, m.hex.y]), "empty piles are not saved")
