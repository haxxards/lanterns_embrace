extends TestCase
## Phase 3 end to end on the real main scene: townsfolk on the maps, walking
## up and talking, a shop opened from a conversation, the reeve's key lying by
## the well, the temple, the journal and the game-over screen.

const DT := 1.0 / 30.0

var main: Node
var world: World
var hud: Hud
var toasts: Array = []


func before_each() -> void:
	GameState.start_new_game()
	main = load("res://scenes/main.tscn").instantiate()
	runner.add_child(main)
	world = main.get_node("World")
	hud = main.get_node("HUD")
	toasts.clear()
	Events.toast_requested.connect(_on_toast)
	await runner.get_tree().process_frame


func after_each() -> void:
	Events.toast_requested.disconnect(_on_toast)
	runner.get_tree().paused = false
	main.queue_free()
	await runner.get_tree().process_frame


func _on_toast(text: String) -> void:
	toasts.append(text)


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


func _settle() -> void:
	for i in 3:
		await runner.get_tree().process_frame


func _load(path: String, entry: String = "door") -> void:
	check(world.load_map(path, entry), "loaded %s" % path)


func _prop(id: String) -> Prop:
	for p in world.props:
		if p.state_id() == id:
			return p
	return null


func test_townsfolk_stand_on_every_map_and_can_be_reached() -> void:
	for path in ["res://data/maps/millbrook_outskirts.json", "res://data/maps/millbrook_inn.json",
			"res://data/maps/millbrook_miller.json", "res://data/maps/millbrook_herbalist.json",
			"res://data/maps/millbrook_smithy.json", "res://data/maps/millbrook_temple.json"]:
		_load(path, "")
		check_eq(world.npcs.size(), world.map.npc_spawns.size(), "%s: every NPC spawned" % world.map.id)
		var leader := world.party.members[0]
		for n in world.npcs:
			check(world.grid.is_occupied(n.hex), "%s blocks the hex they stand on" % n.def.id)
			check(not world.grid.is_walkable(n.hex), "%s: nobody else can stand there" % n.def.id)
			var reachable := false
			for h in n.approach_hexes(world.grid):
				if h == leader.hex or not world.grid.find_path(leader.hex, h).is_empty():
					reachable = true
					break
			check(reachable, "%s on %s can be walked up to" % [n.def.id, world.map.id])


func test_walk_up_and_talk_then_shop() -> void:
	_load("res://data/maps/millbrook_inn.json")
	var tobin := world.npc("tobin")
	check(tobin != null, "Tobin keeps the inn")
	var leader := world.party.members[0]
	world.party.select_only(leader)
	tobin.hold()
	check(world.party.interact_with(tobin), "order accepted")
	check(_walk_until_idle(), "walks over")
	check(Hex.distance(leader.hex, tobin.hex) <= 1, "stands next to Tobin")
	check(hud._dialogue.visible, "the dialogue window opens")
	check(runner.get_tree().paused, "the game pauses while talking")
	check_eq(hud._dialogue.runner.npc.id, "tobin", "talking to Tobin")
	check(not hud._dialogue._text.text.is_empty(), "he says something")
	# Pick "show me your wares" (whichever number it is).
	var shop_index := -1
	for o in hud._dialogue.runner.options():
		var node_opts: Array = hud._dialogue.runner.node().get("options", [])
		if int(o["index"]) >= 0 and bool(node_opts[int(o["index"])].get("shop", false)):
			shop_index = int(o["index"])
	check(shop_index >= 0, "Tobin offers his wares")
	hud._dialogue.choose(shop_index)
	check(not hud._dialogue.visible, "the conversation closes")
	check(hud._inventory.visible and not hud._inventory.trade.is_empty(), "his shop opens")
	check(runner.get_tree().paused, "still paused while shopping")
	# Buy one torch with a right-click.
	GameState.add_gold(10)
	var gold_before := GameState.gold
	var stock: ContainerState = hud._inventory.container
	var torch_slot: ItemSlot = null
	for slot in hud._inventory._all_slots():
		var st: ItemStack = slot.stack()
		if slot.ref.get("container") == stock and st != null and st.id == "torch":
			torch_slot = slot
	check(torch_slot != null, "torches on the shelf")
	var buyer: CharacterSheet = hud._inventory.sheet
	var had := buyer.inventory.count("torch")
	hud._inventory._on_slot_used(torch_slot)
	check_eq(buyer.inventory.count("torch"), had + 1, "bought one torch")
	check(GameState.gold < gold_before, "and paid for it")
	hud._inventory.close()
	check(not runner.get_tree().paused, "unpaused afterwards")
	check(not tobin.talking, "Tobin goes back to his business")


func test_the_reeves_key_lies_by_the_well_once() -> void:
	var pile_prop: Prop = null
	for p in world.props:
		if p.def.id == "item_pile":
			pile_prop = p
	check(pile_prop != null, "a pile of something on the cobbles")
	if pile_prop == null:
		return
	var h: Vector2i = pile_prop.anchor
	var pile := world.ground_pile(h)
	check(pile != null and pile.inventory.count("reeve_key") == 1, "the reeve's key")
	var wren := GameState.member("wren")
	InventoryOps.take_all(pile, wren)
	await _settle()
	check_eq(wren.inventory.count("reeve_key"), 1, "picked up")
	check(not is_instance_valid(pile_prop) or not world.props.has(pile_prop), "nothing left on the ground")
	_load("res://data/maps/millbrook_inn.json")
	_load(GameConfig.starting_map_path, "millbrook_inn")
	var again := world.ground_pile(h)
	check(again == null or again.inventory.is_empty(), "the key doesn't come back")
	var aldous := world.npc("aldous")
	check(aldous != null and Hex.distance(aldous.hex, h) <= 6, "Aldous waits near the well")


func test_the_temple_has_a_priest() -> void:
	_load(GameConfig.starting_map_path, "millbrook_inn")
	var temple := _prop("millbrook_temple")
	check(temple != null and temple.is_transition(), "the temple has a door")
	world.party.select_all()
	check(world.party.interact_with(temple), "order accepted")
	check(_walk_until_idle(60.0), "the party walks to the temple")
	await _settle()
	check_eq(world.map.id, "millbrook_temple", "inside the temple")
	check(world.npc("anselm") != null, "Father Anselm is there")
	check_eq(world.map.ambience, "", "no fireplace crackle in the nave")


func test_journal_lists_quests() -> void:
	hud.open_journal()
	check(hud._journal.visible, "journal opens with no quests")
	hud._journal.close()
	GameState.set_quest_stage("wennas_remedy", "started")
	GameState.set_quest_stage("the_undying_lantern", "rumour")
	hud.open_journal()
	check_eq(hud._journal._list.item_count, 2, "two quests listed")
	check(hud._journal._entries.text.length() > 0, "entries shown")
	check(runner.get_tree().paused, "paused while reading")
	hud._journal.close()
	check(not runner.get_tree().paused, "unpaused after")


func test_game_over_when_everyone_falls() -> void:
	for s in GameState.party:
		s.damage(999)
	await _settle()
	check(hud._game_over.visible, "game over screen")
	check(runner.get_tree().paused, "the world stops")
	for m in world.party.members:
		check(not m.is_alive(), "%s has fallen" % m.sheet.display_name)
	check(world.party.living().is_empty(), "nobody can be ordered about")


func test_the_fallen_stay_behind() -> void:
	var wren := world.party.members[3]
	wren.sheet.damage(999)
	world.party.select_all()
	check(not wren.selected, "the fallen can't be selected")
	check_eq(world.party.living().size(), 3, "three still standing")
	wren.sheet.heal(1)
	check(wren.is_alive(), "back on their feet")
