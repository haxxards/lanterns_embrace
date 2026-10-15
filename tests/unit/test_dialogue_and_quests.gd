extends TestCase
## Phase 3 rules without the scene: dialogue conditions and effects, the
## dialogue runner, quests and XP, vendor prices, the temple, and the data
## files that drive them.


func before_each() -> void:
	GameState.start_new_game()
	GameState.add_gold(-GameState.gold)  # start with an empty purse


func _runner(npc_id: String, speaker: CharacterSheet = null) -> DialogueRunner:
	var def: NpcDef = Data.npcs[npc_id]
	var r := DialogueRunner.new()
	r.start(Data.dialogue(def.dialogue_path), def, speaker if speaker != null else GameState.party[0])
	return r


## Index of the option on offer whose text contains `fragment`, or -2.
func _option(r: DialogueRunner, fragment: String) -> int:
	for o in r.options():
		if str(o["text"]).contains(fragment):
			return int(o["index"])
	return -2


func _choose(r: DialogueRunner, fragment: String) -> void:
	var i := _option(r, fragment)
	check(i != -2, "option '%s' on offer at %s:%s" % [fragment, r.dialogue.id, r.node_id])
	if i != -2:
		r.choose(i)


# --- data ---------------------------------------------------------------------------

func _walk_conditions(cond: Variant, out: Array) -> void:
	if cond is Array:
		for c in cond:
			_walk_conditions(c, out)
	elif cond is Dictionary:
		out.append(cond)
		for key in ["all", "any", "not"]:
			if cond.has(key):
				_walk_conditions(cond[key], out)


func _check_condition_refs(where: String, cond: Variant) -> void:
	var all: Array = []
	_walk_conditions(cond, all)
	for c: Dictionary in all:
		for key in ["item", "not_item"]:
			if c.has(key):
				check(Data.items.has(str(c[key])), "%s: unknown item '%s'" % [where, c[key]])
		if c.has("quest"):
			var q: QuestDef = Data.quests.get(str(c["quest"]))
			check(q != null, "%s: unknown quest '%s'" % [where, c["quest"]])
			for key in ["is", "is_not"]:
				if q != null and c.has(key) and not str(c[key]) in ["not_started", "active", "done"]:
					check(q.stage_index(str(c[key])) >= 0, "%s: quest %s has no stage '%s'" % [where, q.id, c[key]])
		if c.has("member"):
			check(Data.characters.has(str(c["member"])), "%s: unknown member '%s'" % [where, c["member"]])


func _check_effect_refs(where: String, effects: Variant) -> void:
	for e in (effects if effects is Array else [effects]):
		if not e is Dictionary:
			continue
		for key in ["give_item", "take_item"]:
			if e.has(key):
				check(Data.items.has(str(e[key])), "%s: unknown item '%s'" % [where, e[key]])
		if e.has("quest"):
			var q: QuestDef = Data.quests.get(str(e["quest"]))
			check(q != null and q.stage_index(str(e.get("stage", "started"))) >= 0,
					"%s: unknown quest stage %s/%s" % [where, e["quest"], e.get("stage", "started")])


func test_every_npc_and_dialogue_is_sound() -> void:
	check(Data.npcs.size() >= 7, "townsfolk loaded")
	for npc_id in Data.npcs:
		var def: NpcDef = Data.npcs[npc_id]
		check(ResourceLoader.exists(def.portrait_path), "%s portrait exists" % npc_id)
		check(ResourceLoader.exists(def.animation_path) or FileAccess.file_exists(def.animation_path),
				"%s animation exists" % npc_id)
		var d := Data.dialogue(def.dialogue_path)
		check(d != null and d.errors.is_empty(), "%s dialogue loads cleanly: %s" % [npc_id, d.errors if d else "null"])
		if d == null:
			continue
		if d.start is Array:
			for s in d.start:
				_check_condition_refs("%s start" % npc_id, s.get("if"))
		for node_id in d.nodes:
			var node: Dictionary = d.nodes[node_id]
			var where := "%s:%s" % [npc_id, node_id]
			check(node.has("text"), "%s has text" % where)
			_check_effect_refs(where, node.get("do", []))
			for opt in node.get("options", []):
				check(opt.has("text"), "%s option has text" % where)
				_check_condition_refs(where, opt.get("if"))
				_check_effect_refs(where, opt.get("do", []))
				if opt.get("shop", false):
					check(def.is_vendor(), "%s offers a shop but %s is not a vendor" % [where, npc_id])
		if def.is_vendor():
			for e in def.vendor.get("stock", []):
				var item: ItemDef = Data.items.get(str(e["item"]))
				check(item != null and item.value > 0, "%s sells a real, priced item: %s" % [npc_id, e["item"]])


func test_every_quest_is_sound() -> void:
	for quest_id in Data.quests:
		var q: QuestDef = Data.quests[quest_id]
		check(not q.stages.is_empty(), "%s has stages" % quest_id)
		for st in q.stages:
			check(not str(st.get("journal", "")).is_empty(), "%s/%s has a journal entry" % [quest_id, st.get("id")])
			_check_condition_refs("quest %s" % quest_id, st.get("auto_if"))


func test_every_npc_lives_somewhere() -> void:
	var placed := {}
	for path in ["res://data/maps/millbrook_outskirts.json", "res://data/maps/millbrook_inn.json",
			"res://data/maps/millbrook_miller.json", "res://data/maps/millbrook_herbalist.json",
			"res://data/maps/millbrook_smithy.json", "res://data/maps/millbrook_reeve.json",
			"res://data/maps/millbrook_temple.json"]:
		var m := Data.load_map(path)
		check(m.errors.is_empty(), "%s loads: %s" % [path, m.errors])
		for s in m.npc_spawns:
			check(Data.npcs.has(s["id"]), "%s places a known NPC '%s'" % [m.id, s["id"]])
			check(not placed.has(s["id"]), "%s is placed only once" % s["id"])
			placed[s["id"]] = m.id
	for npc_id in Data.npcs:
		check(placed.has(npc_id), "%s is placed on a map" % npc_id)


# --- conditions and effects ---------------------------------------------------------

func test_conditions() -> void:
	var garrick := GameState.member("garrick")
	var wren := GameState.member("wren")
	check(Conditions.check(null), "no condition holds")
	check(Conditions.check({}), "empty condition holds")
	check(not Conditions.check({"flag": "x"}), "unset flag")
	GameState.flags["x"] = true
	check(Conditions.check({"flag": "x"}) and not Conditions.check({"not_flag": "x"}), "set flag")
	check(Conditions.check({"quest": "wennas_remedy", "is": "not_started"}), "quest not started")
	GameState.set_quest_stage("wennas_remedy", "started")
	check(Conditions.check({"quest": "wennas_remedy", "is": "active"}), "quest active")
	check(Conditions.check({"quest": "wennas_remedy", "is": "started"}), "quest at a stage")
	check(Conditions.check({"quest": "wennas_remedy", "is_not": "done"}), "quest not done")
	check(not Conditions.check({"item": "garnet"}), "nobody has a garnet")
	wren.inventory.add_item("garnet", 2)
	check(Conditions.check({"item": "garnet", "qty": 2}), "two garnets between them")
	check(not Conditions.check({"item": "garnet", "qty": 3}), "not three")
	check(not Conditions.check({"not_item": "garnet"}), "not_item")
	GameState.add_gold(15)
	check(Conditions.check({"gold": 15}) and not Conditions.check({"gold": 16}), "gold")
	check(Conditions.check({"member": "odran"}), "Odran is with us")
	check(not Conditions.check({"member": "nobody"}), "unknown member")
	check(Conditions.check({"speaker": "garrick"}, garrick) and not Conditions.check({"speaker": "wren"}, garrick),
			"speaker")
	check(not Conditions.check({"hurt": true}) and Conditions.check({"hurt": false}), "nobody hurt")
	garrick.damage(3)
	check(Conditions.check({"hurt": true}), "Garrick hurt")
	check(not Conditions.check({"fallen": true}), "nobody fallen")
	wren.damage(999)
	check(Conditions.check({"fallen": true}), "Wren fallen")
	check(not Conditions.check({"member": "wren"}), "the fallen don't count as members")
	check(Conditions.check({"any": [{"flag": "nope"}, {"flag": "x"}]}), "any")
	check(not Conditions.check({"all": [{"flag": "nope"}, {"flag": "x"}]}), "all")
	check(Conditions.check({"not": {"flag": "nope"}}), "not")
	check(Conditions.check([{"flag": "x"}, {"gold": 1}]), "a list means all")
	GameState.flags["seen:tobin:greet"] = true
	check(Conditions.check({"visited": "greet"}, null, "tobin"), "visited")
	check(not Conditions.check({"visited": "greet"}, null, "pip"), "visited is per dialogue")


func test_effects() -> void:
	var elowen := GameState.member("elowen")
	var msgs := Effects.apply([{"give_item": "garnet", "qty": 2}, {"give_gold": 20}, {"set_flag": "met"}], elowen)
	check_eq(elowen.inventory.count("garnet"), 2, "items go to the speaker")
	check_eq(GameState.gold, 20, "gold")
	check(GameState.flags.has("met"), "flag set")
	check_eq(msgs.size(), 2, "messages for the item and the gold: %s" % msgs)
	Effects.apply([{"take_item": "garnet"}, {"take_gold": 5}, {"clear_flag": "met"}], elowen)
	check_eq(GameState.party_item_count("garnet"), 1, "one garnet taken")
	check_eq(GameState.gold, 15, "gold taken")
	check(not GameState.flags.has("met"), "flag cleared")
	Effects.apply({"quest": "light_for_the_dawn", "stage": "started"}, elowen)
	check_eq(GameState.quest_stage("light_for_the_dawn"), "started", "quest effect")
	var xp_before := elowen.xp
	Effects.apply({"xp": 25}, elowen)
	check_eq(elowen.xp, xp_before + 25, "xp effect")
	check_eq(Effects.apply({"toast": "Hello"}, elowen), PackedStringArray(["Hello"]), "toast")


func test_give_item_spills_over_to_whoever_has_room() -> void:
	var garrick := GameState.member("garrick")
	while garrick.inventory.first_free() >= 0:
		garrick.inventory.add_item("longsword")  # one per slot
	var others_before := GameState.party_item_count("reeve_key")
	Effects.apply({"give_item": "reeve_key"}, garrick)
	check_eq(GameState.party_item_count("reeve_key"), others_before + 1, "someone else carries it")
	check_eq(garrick.inventory.count("reeve_key"), 0, "not Garrick, whose pack is full")


# --- the dialogue runner and quests ----------------------------------------------

func test_the_reeves_key_from_start_to_finish() -> void:
	var r := _runner("aldous")
	check_eq(r.node_id, "intro", "Aldous opens with his trouble")
	_choose(r, "keep an eye out")
	check_eq(GameState.quest_state("the_reeves_key"), "active", "quest started")
	check_eq(r.node_id, "thanks", "moves on")
	_choose(r, "look around")
	check(r.finished, "conversation over")
	r = _runner("aldous")
	check_eq(r.node_id, "searching", "asks after the key")
	# Picking up the key moves the quest on by itself ("auto_if").
	GameState.member("wren").inventory.add_item("reeve_key")
	check_eq(GameState.quest_stage("the_reeves_key"), "found", "found stage reached on its own")
	r = _runner("aldous")
	check_eq(r.node_id, "return", "he spots the key")
	var gold := GameState.gold
	var xp: Array[int] = []
	for s in GameState.party:
		xp.append(s.xp)
	_choose(r, "Here you are")
	check_eq(GameState.quest_state("the_reeves_key"), "done", "quest done")
	check_eq(GameState.gold, gold + 40, "paid 40 gold")
	check_eq(GameState.party_item_count("reeve_key"), 0, "key handed over")
	for i in GameState.party.size():
		check_eq(GameState.party[i].xp, xp[i] + 150, "%s gains the quest XP" % GameState.party[i].display_name)
	check_eq(GameState.quest_log["the_reeves_key"], ["started", "found", "done"], "journal entries in order")
	check(r.messages.size() >= 2, "messages for the gold and the key: %s" % r.messages)
	check_eq(_runner("aldous").node_id, "after", "afterwards he's grateful")


func test_bringing_the_key_before_being_asked() -> void:
	GameState.member("garrick").inventory.add_item("reeve_key")
	check_eq(GameState.quest_state("the_reeves_key"), "not_started", "finding it doesn't start the quest")
	var r := _runner("aldous")
	check_eq(r.node_id, "return", "he spots the key straight away")
	_choose(r, "Here you are")
	check_eq(GameState.quest_state("the_reeves_key"), "done", "and the quest is done")


func test_the_miller_gets_his_remedy() -> void:
	var r := _runner("hob")
	check_eq(_option(r, "Three drops"), -2, "nothing to deliver yet")
	r = _runner("wenna")
	_choose(r, "take your remedy")
	check_eq(GameState.quest_state("wennas_remedy"), "active", "Wenna asks for help")
	check_eq(GameState.party_item_count("wenna_remedy"), 1, "and hands over the draught")
	check(not InventoryOps.can_sell(Data.items["wenna_remedy"]), "quest items can't be sold")
	r = _runner("hob")
	var gold := GameState.gold
	_choose(r, "Three drops")
	check_eq(GameState.quest_state("wennas_remedy"), "done", "delivered")
	check_eq(GameState.gold, gold + 20, "Hob pays")
	check_eq(GameState.party_item_count("wenna_remedy"), 0, "draught gone")


func test_light_for_the_dawn() -> void:
	var r := _runner("anselm", GameState.member("garrick"))
	if r.node_id == "odran":
		r.choose(-1)  # "Continue."
	check_eq(r.node_id, "greet", "Anselm greets us")
	_choose(r, "anything the temple needs")
	check_eq(GameState.quest_stage("light_for_the_dawn"), "started", "quest given")
	_choose(r, "find one")
	check_eq(_option(r, "lantern for the altar"), -2, "no lantern yet")
	GameState.member("elowen").inventory.add_item("lantern")
	_choose(r, "lantern for the altar")
	check_eq(GameState.quest_state("light_for_the_dawn"), "done", "done")
	check_eq(GameState.party_item_count("lantern"), 0, "lantern given")
	check_eq(GameState.party_item_count("potion_of_greater_healing"), 1, "blessed with a potion")


func test_dialogue_fills_in_names_and_offers_farewell() -> void:
	var r := _runner("pip")
	check(not r.text().contains("{"), "placeholders filled: %s" % r.text())
	check(not r.options().is_empty(), "options on offer")
	var d := Dialogue.new()
	d.id = "test"
	d.start = "a"
	d.nodes = {"a": {"text": "Hello {leader}, I am {npc}.", "next": "b"}, "b": {"text": "Bye."}}
	var t := DialogueRunner.new()
	t.start(d, Data.npcs["pip"], GameState.member("wren"))
	check_eq(t.text(), "Hello %s, I am Pip Fairweather." % GameState.member("wren").display_name, "text filled")
	check_eq(t.options()[0]["text"], "Continue.", "a node with next offers Continue")
	t.choose(-1)
	check_eq(t.node_id, "b", "continued")
	check_eq(t.options()[0]["text"], "Farewell.", "a node with no options offers Farewell")
	t.choose(-1)
	check(t.finished, "and that ends it")
	check(GameState.flags.has("seen:test:a") and GameState.flags.has("seen:test:b"), "visited nodes remembered")


func test_validate_catches_broken_gotos() -> void:
	var d := Dialogue.new()
	d.id = "broken"
	d.start = "a"
	d.nodes = {"a": {"text": "x", "options": [{"text": "y", "goto": "missing"}]}}
	d.validate()
	check_eq(d.errors.size(), 1, "one bad goto found")


# --- xp and levels ------------------------------------------------------------------

func test_xp_levels_up_and_the_fallen_get_none() -> void:
	var garrick := GameState.member("garrick")
	var wren := GameState.member("wren")
	var level := garrick.level
	var hp_max := garrick.hp_max
	var need: int = Rules.XP_THRESHOLDS[level] - garrick.xp
	wren.damage(999)
	var wren_xp := wren.xp
	GameState.award_xp(need)
	check_eq(garrick.level, level + 1, "Garrick levels up")
	check(garrick.hp_max > hp_max, "and gains hit points")
	check_eq(wren.xp, wren_xp, "the fallen gain nothing")


# --- vendors ------------------------------------------------------------------------

func test_buying_and_selling() -> void:
	var tobin: NpcDef = Data.npcs["tobin"]
	var terms := tobin.trade_terms()
	var stock := GameState.vendor_stock(tobin)
	var torch: ItemDef = Data.items["torch"]
	var i := -1
	for k in stock.inventory.capacity():
		var st := stock.inventory.get_at(k)
		if st != null and st.id == "lantern":
			i = k
	check(i >= 0, "Tobin sells lanterns")
	var lantern: ItemDef = Data.items["lantern"]
	var price := InventoryOps.buy_price(lantern, terms)
	check(price >= 1, "lanterns have a price")
	var buyer := GameState.member("elowen")
	var shop := InventoryOps.shop_slot(stock, i, terms)
	var free := buyer.inventory.first_free()
	var err := InventoryOps.move(shop, InventoryOps.backpack(buyer, free))
	check(not err.is_empty(), "can't afford it with an empty purse")
	GameState.add_gold(price * 2 - 1)
	var had := stock.inventory.get_at(i).qty
	err = InventoryOps.move(shop, InventoryOps.backpack(buyer, free))
	check(err.is_empty(), "bought: %s" % err)
	check_eq(buyer.inventory.count("lantern"), 1, "as many as we could afford (one)")
	check_eq(GameState.gold, price - 1, "paid")
	check_eq(stock.inventory.get_at(i).qty, had - 1, "one fewer on the shelf")
	# Selling: a torch from Elowen's pack goes to Tobin for value × buy_rate.
	buyer.inventory.add_item("torch", 2)
	var gold := GameState.gold
	var at := -1
	for k in buyer.inventory.capacity():
		var st := buyer.inventory.get_at(k)
		if st != null and st.id == "torch":
			at = k
	var to := InventoryOps.shop_slot(stock, 0, terms)
	err = InventoryOps.move(InventoryOps.backpack(buyer, at), to)
	check(err.is_empty(), "sold: %s" % err)
	check_eq(GameState.gold, gold + InventoryOps.sell_price(torch, terms) * 2, "paid for both torches")
	check_eq(buyer.inventory.count("torch"), 0, "torches gone")
	# Quest items stay with the party.
	buyer.inventory.add_item("reeve_key")
	for k in buyer.inventory.capacity():
		var st := buyer.inventory.get_at(k)
		if st != null and st.id == "reeve_key":
			at = k
	err = InventoryOps.move(InventoryOps.backpack(buyer, at), to)
	check(not err.is_empty() and buyer.inventory.count("reeve_key") == 1, "won't buy the reeve's key")


func test_vendor_stock_is_saved() -> void:
	var bram: NpcDef = Data.npcs["bram"]
	var stock := GameState.vendor_stock(bram)
	stock.inventory.set_at(0, null)
	GameState.set_quest_stage("wennas_remedy", "started")
	var saved := GameState.to_dict()
	GameState.start_new_game()
	check_eq(GameState.quest_state("wennas_remedy"), "not_started", "fresh game")
	GameState.load_dict(saved)
	check(GameState.vendor_stock(bram).inventory.get_at(0) == null, "Bram's shelf remembers the sale")
	check_eq(GameState.quest_stage("wennas_remedy"), "started", "quests saved")
	check_eq(GameState.quest_log["wennas_remedy"], ["started"], "journal saved")


# --- the temple ---------------------------------------------------------------------

func test_temple_heals_and_raises_for_a_fee() -> void:
	var garrick := GameState.member("garrick")
	var wren := GameState.member("wren")
	garrick.damage(5)
	var r := _runner("anselm", garrick)
	if r.node_id == "odran":
		r.choose(-1)
	check_eq(_option(r, "(10 gold)"), -2, "can't pay for healing with an empty purse")
	check(_option(r, "Heal our wounds") != -2, "but can ask")
	GameState.add_gold(200)
	r = _runner("anselm", garrick)
	_choose(r, "(10 gold)")
	check_eq(garrick.hp_current, garrick.hp_max, "healed")
	check_eq(GameState.gold, 190, "for 10 gold")
	wren.damage(999)
	check(not wren.is_alive(), "Wren has fallen")
	r.choose(-1)  # back to the greeting
	_choose(r, "(100 gold)")
	check(wren.is_alive() and wren.hp_current == 1, "raised with 1 hit point")
	check_eq(GameState.gold, 90, "for 100 gold")


func test_party_defeated_when_everyone_falls() -> void:
	var fired := [0]
	var on_defeat := func() -> void: fired[0] += 1
	Events.party_defeated.connect(on_defeat)
	for s in GameState.party:
		check_eq(fired[0], 0, "not while someone stands")
		s.damage(999)
	Events.party_defeated.disconnect(on_defeat)
	check(fired[0] >= 1, "defeat announced")
