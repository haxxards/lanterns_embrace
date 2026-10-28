extends TestCase
## Items, inventories, equipment rules, armour class, gold and dice.


func _sheet(id: String) -> CharacterSheet:
	return Data.new_character(id)


func test_item_definitions_are_valid() -> void:
	check(Data.items.size() >= 30, "items loaded")
	for id in Data.items:
		var it: ItemDef = Data.items[id]
		check(it.icon != Data.missing_texture(), "%s has an icon" % id)
		check(it.slot.is_empty() or it.slot == "ring" or ItemDef.EQUIP_SLOTS.has(it.slot), "%s slot '%s'" % [id, it.slot])
		if it.is_weapon():
			check(not Rules.parse_dice(str(it.weapon.get("damage", ""))).is_empty(), "%s damage dice" % id)
		if it.use.has("heal"):
			check(not Rules.parse_dice(str(it.use["heal"])).is_empty(), "%s heal dice" % id)
		if it.is_body_armor():
			check(int(it.armor.get("base_ac", 0)) > 10, "%s base AC" % id)


func test_sheets_reference_real_items_and_ac_matches() -> void:
	for id in Data.characters:
		var template: CharacterSheet = Data.characters[id]
		check(template.is_valid(), "%s: %s" % [id, ", ".join(template.errors)])
		# The AC written in each bundled sheet must agree with its equipment.
		check_eq(template.armor_class, int(template.raw.get("armor_class", -1)), "%s AC from equipment" % id)


func test_dice_expressions() -> void:
	check_eq(Rules.parse_dice("2d4+2"), {"count": 2, "sides": 4, "bonus": 2}, "2d4+2")
	check_eq(Rules.parse_dice("d6"), {"count": 1, "sides": 6, "bonus": 0}, "d6")
	check_eq(Rules.parse_dice("1d8 - 1"), {"count": 1, "sides": 8, "bonus": -1}, "1d8 - 1")
	check_eq(Rules.parse_dice("3"), {"count": 0, "sides": 0, "bonus": 3}, "flat 3")
	check(Rules.parse_dice("banana").is_empty(), "nonsense rejected")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 50:
		var v := Rules.roll_expr("2d4+2", rng)
		check(v >= 4 and v <= 10, "2d4+2 in range (%d)" % v)


func test_inventory_stacks_and_slots() -> void:
	var inv := Inventory.new(4)
	check_eq(inv.add_item("potion_of_healing", 3), 0, "fits")
	check_eq(inv.add_item("potion_of_healing", 9), 0, "tops up then spills into a new slot")
	check_eq(inv.get_at(0).qty, 10, "first stack full (max 10)")
	check_eq(inv.get_at(1).qty, 2, "second stack")
	check_eq(inv.add_item("longsword"), 0, "sword fits")
	check_eq(inv.add_item("shield"), 0, "shield fits")
	check_eq(inv.add_item("mace"), 1, "no room left")
	check(not inv.can_fit(ItemStack.create("mace")), "can_fit agrees")
	check_eq(inv.remove_item("potion_of_healing", 11), 11, "removed across stacks")
	check_eq(inv.count("potion_of_healing"), 1, "one left")
	var again := Inventory.from_array(inv.to_array(), 4)
	check_eq(again.to_array(), inv.to_array(), "JSON round trip keeps slot positions")


func test_equipment_rules() -> void:
	var garrick := _sheet("garrick")
	var wren := _sheet("wren")
	var elowen := _sheet("elowen")
	var mail := ItemStack.create("chain_mail")
	check(not wren.can_equip("armor", mail).is_empty(), "rogue can't wear heavy armour")
	check(garrick.can_equip("armor", mail).is_empty(), "fighter can")
	check(not elowen.can_equip("off_hand", ItemStack.create("shield")).is_empty(), "wizard has no shield training")
	check(not garrick.can_equip("main_hand", ItemStack.create("shortbow")).is_empty(), "bow needs the shield hand free")
	check(not garrick.can_equip("off_hand", ItemStack.create("longsword")).is_empty(), "only light weapons off-hand")
	check(wren.can_equip("off_hand", ItemStack.create("dagger")).is_empty(), "dagger with a shortsword is fine")
	check(garrick.can_equip("ring_2", ItemStack.create("ring_of_protection")).is_empty(), "rings fit either ring slot")
	check(not garrick.can_equip("helmet", ItemStack.create("ring_of_protection")).is_empty(), "but not on the head")


func test_armor_class_follows_equipment() -> void:
	var g := _sheet("garrick")
	check_eq(g.armor_class, 19, "chain mail + shield + Defense fighting style")
	var err := InventoryOps.move(InventoryOps.equip_slot(g, "armor"), InventoryOps.backpack(g, g.inventory.first_free()))
	check_eq(err, "", "armour taken off")
	check_eq(g.armor_class, 10 + g.ability_mod("dex") + 2, "unarmoured + shield")
	g.inventory.add_item("ring_of_protection")
	var ring_slot := -1
	for i in g.inventory.capacity():
		var st := g.inventory.get_at(i)
		if st != null and st.id == "ring_of_protection":
			ring_slot = i
	check_eq(InventoryOps.move(InventoryOps.backpack(g, ring_slot), InventoryOps.equip_slot(g, "ring_1")), "", "ring on")
	check_eq(g.armor_class, 10 + g.ability_mod("dex") + 3, "ring adds 1")
	var w := _sheet("wren")
	check_eq(w.armor_class, 11 + w.ability_mod("dex"), "light armour adds full Dex")


func test_moving_items_swaps_and_stacks() -> void:
	var w := _sheet("wren")
	# Wren carries two daggers in the backpack and one in the off hand.
	var pack := -1
	for i in w.inventory.capacity():
		if w.inventory.get_at(i) != null and w.inventory.get_at(i).id == "dagger":
			pack = i
	check(pack >= 0, "daggers in pack")
	check_eq(InventoryOps.move(InventoryOps.equip_slot(w, "off_hand"), InventoryOps.backpack(w, pack)), "", "stack")
	check_eq(w.inventory.get_at(pack).qty, 3, "three daggers stacked")
	check(w.equipped("off_hand") == null, "off hand empty")
	check_eq(InventoryOps.move(InventoryOps.backpack(w, pack), InventoryOps.equip_slot(w, "off_hand")), "", "equip one")
	check_eq(w.equipped("off_hand").qty, 1, "one dagger in hand")
	check_eq(w.inventory.get_at(pack).qty, 2, "two left in pack")
	var refused := InventoryOps.move(InventoryOps.equip_slot(w, "armor"), InventoryOps.equip_slot(w, "helmet"))
	check(not refused.is_empty(), "armour can't go on the head")
	check_eq(w.equipped("armor").id, "leather", "and stays put")


func test_giving_and_using_items() -> void:
	var g := _sheet("garrick")
	var e := _sheet("elowen")
	var potion := -1
	for i in g.inventory.capacity():
		if g.inventory.get_at(i) != null and g.inventory.get_at(i).id == "potion_of_healing":
			potion = i
	check_eq(InventoryOps.give(InventoryOps.backpack(g, potion), e), "", "given")
	check_eq(e.inventory.count("potion_of_healing"), 2, "Elowen has two now")
	check_eq(g.inventory.count("potion_of_healing"), 0, "Garrick none")
	e.hp_current = 1
	for i in e.inventory.capacity():
		if e.inventory.get_at(i) != null and e.inventory.get_at(i).id == "potion_of_healing":
			var msg := InventoryOps.use(InventoryOps.backpack(e, i), e)
			check(msg.contains("recovers"), "drank it: %s" % msg)
			break
	check(e.hp_current >= 5 and e.hp_current <= e.hp_max, "healed 2d4+2 (now %d)" % e.hp_current)
	check_eq(e.inventory.count("potion_of_healing"), 1, "one used up")


func test_gold_goes_to_the_party_purse() -> void:
	GameState.start_new_game()
	var expected := 0
	for id in ["garrick", "elowen", "odran", "wren"]:
		expected += int((Data.characters[id] as CharacterSheet).raw.get("gold", 0))
	check_eq(GameState.gold, expected, "starting gold pooled")
	var box := ContainerState.from_placement({"items": [{"item": "garnet", "qty": 1}], "gold": 30})
	check_eq(InventoryOps.take_all(box, GameState.party[0]), "", "took everything")
	check_eq(GameState.gold, expected + 30, "gold into the purse")
	check(box.inventory.is_empty(), "box empty")
	check_eq(GameState.party[0].inventory.count("gold"), 0, "no gold item in the backpack")
	check(GameState.spend_gold(10), "can spend")
	check(not GameState.spend_gold(100000), "can't overspend")


func test_carrying_too_much_slows_down() -> void:
	var e := _sheet("elowen")
	check_eq(e.carrying_capacity(), 120.0, "Str 8 x 15")
	check(not e.is_overloaded(), "light load")
	e.inventory.add_item("chain_mail")
	e.inventory.add_item("chain_mail")
	e.inventory.add_item("chain_mail")
	check(e.is_overloaded(), "three coats of mail is too much")
	check_eq(e.effective_speed_ft(), int(e.speed_ft / 2.0), "speed halved")


# --- passive magic item bonuses ---------------------------------------------------

## Puts item `id` on `sheet` in `slot` (straight onto the sheet, as the
## paper doll would after its checks).
func _wear(sheet: CharacterSheet, slot: String, id: String) -> void:
	sheet.equip(slot, ItemStack.create(id))


func test_gauntlets_raise_strength_to_19() -> void:
	var e := _sheet("elowen")  # Str 8
	var before := e.carrying_capacity()
	_wear(e, "gloves", "gauntlets_of_ogre_power")
	check_eq(e.ability_score("str"), 19, "Strength 19 while worn")
	check_eq(e.ability_mod("str"), 4, "and the modifier with it")
	check_eq(int(e.abilities["str"]), 8, "the sheet's own score is unchanged")
	check_eq(e.carrying_capacity(), 19 * 15.0, "carries like Str 19 (was %s)" % before)
	var g := _sheet("garrick")
	g.abilities["str"] = 20
	_wear(g, "gloves", "gauntlets_of_ogre_power")
	check_eq(g.ability_score("str"), 20, "a higher score is kept")
	e.unequip("gloves")
	check_eq(e.ability_score("str"), 8, "back to 8 when taken off")


func test_heavy_armour_strength_counts_the_gauntlets() -> void:
	var e := _sheet("elowen")
	e.equip("armor", ItemStack.create("chain_mail"))  # needs Str 13
	var slowed := e.effective_speed_ft()
	_wear(e, "gloves", "gauntlets_of_ogre_power")
	check_eq(e.effective_speed_ft(), slowed + 10, "strong enough for chain mail now")


func test_protection_items_add_to_saving_throws() -> void:
	var g := _sheet("garrick")
	var wis := g.saving_throw_bonus("wis")
	var con := g.saving_throw_bonus("con")
	_wear(g, "ring_1", "ring_of_protection")
	check_eq(g.saving_throw_bonus("wis"), wis + 1, "ring: +1 to Wisdom saves")
	check_eq(g.saving_throw_bonus("con"), con + 1, "and to the proficient ones")
	_wear(g, "cloak", "cloak_of_protection")
	check_eq(g.saving_throw_bonus("wis"), wis + 2, "ring and cloak stack")
	check_eq(g.item_bonus("saves"), 2, "item_bonus sums what is worn")


func test_protection_helps_death_saves() -> void:
	var g := _sheet("garrick")
	_wear(g, "ring_1", "ring_of_protection")
	g.hp_current = 0
	# Find a seed whose first d20 is a 9: a failure bare, a success with the ring.
	var rng := RandomNumberGenerator.new()
	var seed_found := -1
	for s in 500:
		rng.seed = s
		if Rules.roll(1, 20, rng) == 9:
			seed_found = s
			break
	check(seed_found >= 0, "found a seed that rolls 9")
	rng.seed = seed_found
	check_eq(g.roll_death_save(rng), "success", "9 + 1 = 10 succeeds")
	check_eq(g.death_successes, 1, "counted as a success")


func test_magic_weapon_adds_to_attack_and_damage() -> void:
	var g := _sheet("garrick")
	var plain: Attack = CombatRules.weapon_attacks(g)[0]
	g.equip("main_hand", ItemStack.create("longsword_plus_one"))
	var magic: Attack = CombatRules.weapon_attacks(g)[0]
	check_eq(magic.to_hit, plain.to_hit + 1, "+1 to hit")
	var p := Rules.parse_dice(plain.damage)
	var m := Rules.parse_dice(magic.damage)
	check_eq(m["bonus"], int(p["bonus"]) + 1, "+1 damage (%s vs %s)" % [magic.damage, plain.damage])
	check(g.attack_summary().contains(Rules.format_modifier(plain.to_hit + 1)), "the stats line shows it: %s"
			% g.attack_summary())
	check(Data.items["longsword_plus_one"].describe().contains("+1 to attack and damage rolls"), "item card")


func test_boots_keep_walking_speed() -> void:
	var g := _sheet("garrick")
	g.speed_ft = 25
	_wear(g, "boots", "boots_of_striding_and_springing")
	check_eq(g.effective_speed_ft(), 30, "at least 30 ft")
	for i in 4:
		g.inventory.add_item("chain_mail")
	check(g.is_overloaded(), "overloaded")
	check_eq(g.effective_speed_ft(), 30, "but not slowed")
	g.speed_ft = 35
	check_eq(g.effective_speed_ft(), 35, "a faster walker keeps their speed")
	g.unequip("boots")
	check_eq(g.effective_speed_ft(), 17, "halved again without them")


func test_ring_of_fire_resistance_halves_fire_damage() -> void:
	var e := _sheet("elowen")
	check_eq(CombatRules.adjust_for_type(e, 9, "fire"), 9, "no resistance bare")
	_wear(e, "ring_2", "ring_of_fire_resistance")
	check_eq(e.resistances(), PackedStringArray(["fire"]), "resists fire")
	check_eq(CombatRules.adjust_for_type(e, 9, "fire"), 4, "half, rounded down")
	check_eq(CombatRules.adjust_for_type(e, 9, "cold"), 9, "other types in full")


func test_amulet_of_health_raises_hit_points_by_level() -> void:
	var e := _sheet("elowen")  # Con 13 (+1)
	e.add_xp(Rules.XP_THRESHOLDS[2])  # level 3
	var base_max := e.hp_max
	var hp := e.hp_current
	_wear(e, "amulet", "amulet_of_health")
	check_eq(e.ability_score("con"), 19, "Con 19")
	check_eq(e.hp_max, base_max + 3 * 3, "+3 per level (Con +1 -> +4)")
	check_eq(e.hp_current, hp, "putting it on doesn't heal")
	e.hp_current = e.hp_max
	var saved := e.to_dict()
	check_eq(int(saved["hit_points"]["max"]), base_max, "saves keep the sheet's own maximum")
	var loaded := CharacterSheet.from_dict(saved)
	check_eq(loaded.hp_max, base_max + 9, "loaded with the amulet on")
	check_eq(loaded.hp_current, base_max + 9, "current hit points kept")
	e.add_xp(Rules.XP_THRESHOLDS[3] - e.xp)  # level 4
	check_eq(e.con_hp, 4 * 3, "the amulet's share grows with level")
	check_eq(e.hp_current, e.hp_max, "and a level-up brings it")
	e.unequip("amulet")
	check_eq(e.con_hp, 0, "taken off")
	check_eq(e.hp_current, e.hp_max, "current capped at the new maximum")


func test_item_cards_list_the_bonuses() -> void:
	var lines := (Data.items["ring_of_protection"] as ItemDef).describe()
	check(lines.contains("+1 AC while worn"), "AC line")
	check(lines.contains("+1 to saving throws while worn"), "saves line")
	check((Data.items["gauntlets_of_ogre_power"] as ItemDef).describe().contains("Strength 19 while worn"), "Str line")
	check((Data.items["amulet_of_health"] as ItemDef).describe().contains("Constitution 19"), "Con line")
	check((Data.items["boots_of_striding_and_springing"] as ItemDef).describe().contains("at least 30 ft"), "speed")
	check((Data.items["ring_of_fire_resistance"] as ItemDef).describe().contains("Resistance to fire damage"), "resist")


# --- usable items ------------------------------------------------------------------

func _use(sheet: CharacterSheet, id: String) -> String:
	for i in sheet.inventory.capacity():
		var st := sheet.inventory.get_at(i)
		if st != null and st.id == id:
			return InventoryOps.use(InventoryOps.backpack(sheet, i), sheet)
	return "(no %s)" % id


func test_hill_giant_strength_lasts_until_a_long_rest() -> void:
	var w := _sheet("wren")  # Str 8
	w.inventory.add_item("potion_of_hill_giant_strength", 2)
	var msg := _use(w, "potion_of_hill_giant_strength")
	check(msg.contains("Strength 21 until a long rest"), "drunk: %s" % msg)
	check_eq(w.ability_score("str"), 21, "Strength 21")
	check_eq(w.inventory.count("potion_of_hill_giant_strength"), 1, "one used")
	msg = _use(w, "potion_of_hill_giant_strength")
	check(msg.contains("already as strong"), "a second does nothing: %s" % msg)
	check_eq(w.inventory.count("potion_of_hill_giant_strength"), 1, "and isn't wasted")
	var loaded := CharacterSheet.from_dict(w.to_dict())
	check_eq(loaded.ability_score("str"), 21, "kept in a save")
	Rest.long_rest([w] as Array[CharacterSheet])
	check_eq(w.ability_score("str"), 8, "gone after a long rest")
	_wear(w, "gloves", "gauntlets_of_ogre_power")
	w.inventory.add_item("potion_of_hill_giant_strength")
	_use(w, "potion_of_hill_giant_strength")
	check_eq(w.ability_score("str"), 21, "the potion beats the gauntlets")
	check(Data.items["potion_of_hill_giant_strength"].describe().contains("Strength 21 until a long rest"), "card")


func test_holy_water_waits_for_a_fight() -> void:
	var o := _sheet("odran")
	o.inventory.add_item("holy_water", 1)
	var msg := _use(o, "holy_water")
	check(msg.contains("combat bar"), "thrown from the combat bar: %s" % msg)
	check_eq(o.inventory.count("holy_water"), 1, "not used up")
	var card := (Data.items["holy_water"] as ItemDef).describe()
	check(card.contains("thrown in a fight (20 ft): 2d6 radiant damage to undead and fiends only"), card)



# --- splitting stacks ----------------------------------------------------------------

func _slot_of(sheet: CharacterSheet, id: String) -> int:
	for i in sheet.inventory.capacity():
		var st := sheet.inventory.get_at(i)
		if st != null and st.id == id:
			return i
	return -1


func test_moving_part_of_a_stack() -> void:
	var w := _sheet("wren")
	w.inventory.add_item("arrows", 20)
	var from := InventoryOps.backpack(w, _slot_of(w, "arrows"))
	var empty := w.inventory.first_free()
	check_eq(InventoryOps.move_some(from, InventoryOps.backpack(w, empty), 7), "", "split off 7")
	check_eq(w.inventory.get_at(empty).qty, 7, "7 in the new slot")
	check_eq(InventoryOps.stack_at(from).qty, 13, "13 left behind")
	check_eq(InventoryOps.move_some(from, InventoryOps.backpack(w, empty), 3), "", "top up with 3 more")
	check_eq(w.inventory.get_at(empty).qty, 10, "10 there now")
	check_eq(w.inventory.count("arrows"), 20, "none lost")
	var other := _slot_of(w, "dagger")
	check(not InventoryOps.move_some(from, InventoryOps.backpack(w, other), 2).is_empty(), "not onto another item")
	check_eq(InventoryOps.move_some(from, InventoryOps.backpack(w, empty), 99), "", "more than the stack: all of it")
	check(InventoryOps.stack_at(from) == null, "source emptied")
	check_eq(w.inventory.get_at(empty).qty, 20, "all 20 together")
	var box := ContainerState.from_placement({"items": []})
	check_eq(InventoryOps.move_some(InventoryOps.backpack(w, empty), InventoryOps.container_slot(box, 0), 5), "",
			"put 5 in a chest")
	check_eq(box.inventory.count("arrows"), 5, "the chest has 5")
	check_eq(w.inventory.count("arrows"), 15, "Wren keeps 15")


func test_an_equipment_slot_takes_one_from_a_split() -> void:
	var w := _sheet("wren")
	w.inventory.add_item("dagger", 1)
	w.unequip("off_hand")
	var from := InventoryOps.backpack(w, _slot_of(w, "dagger"))
	var had := InventoryOps.stack_at(from).qty
	check_eq(InventoryOps.move_some(from, InventoryOps.equip_slot(w, "off_hand"), 2), "", "equipped")
	check_eq(w.equipped("off_hand").qty, 1, "a hand holds one")
	check_eq(InventoryOps.stack_at(from).qty, had - 1, "the rest stay")


func test_giving_buying_and_selling_part_of_a_stack() -> void:
	GameState.start_new_game()
	var g: CharacterSheet = GameState.member("garrick")
	var e: CharacterSheet = GameState.member("elowen")
	g.inventory.add_item("torch", 6)
	var from := InventoryOps.backpack(g, _slot_of(g, "torch"))
	var torches := InventoryOps.stack_at(from).qty
	var e_had := e.inventory.count("torch")
	check_eq(InventoryOps.give(from, e, 2), "", "gave 2")
	check_eq(e.inventory.count("torch"), e_had + 2, "Elowen has 2 more")
	check_eq(g.inventory.count("torch"), torches - 2, "Garrick 2 fewer")
	var terms := {"markup": 1.0, "buy_rate": 0.5, "vendor": "Tobin"}
	var stock := ContainerState.from_placement({"items": [{"item": "arrows", "qty": 40}]})
	var gold := GameState.gold
	var price := InventoryOps.buy_price(Data.items["arrows"], terms)
	check_eq(InventoryOps.move_some(InventoryOps.shop_slot(stock, 0, terms),
			InventoryOps.backpack(g, g.inventory.first_free()), 10), "", "bought 10")
	check_eq(stock.inventory.count("arrows"), 30, "30 left in the shop")
	check_eq(GameState.gold, gold - 10 * price, "paid for 10")
	gold = GameState.gold
	var arrows := InventoryOps.backpack(g, _slot_of(g, "arrows"))
	var sell_each := InventoryOps.sell_price(Data.items["arrows"], terms)
	check_eq(InventoryOps.move_some(arrows, InventoryOps.shop_slot(stock, 5, terms), 4), "", "sold 4")
	check_eq(GameState.gold, gold + 4 * sell_each, "paid for 4")
	check_eq(stock.inventory.count("arrows"), 34, "the shop has them")
	check_eq(g.inventory.count("arrows"), 6, "6 kept")


# --- unidentified magic items ----------------------------------------------------------

func test_magic_found_in_a_chest_is_unidentified() -> void:
	var box := ContainerState.from_placement({"items": [{"item": "ring_of_fire_resistance", "qty": 1},
			{"item": "potion_of_hill_giant_strength", "qty": 1}, {"item": "longsword", "qty": 1},
			{"item": "amulet_of_health", "qty": 1, "identified": true}]})
	var ring := box.inventory.get_at(0)
	check(not ring.identified, "the ring is unknown")
	check(box.inventory.get_at(1).identified, "potions are known on sight")
	check(box.inventory.get_at(2).identified, "so is plain steel")
	check(box.inventory.get_at(3).identified, "a placement can say it is known")
	check_eq(ring.item_name(), "Unidentified ring", "masked name")
	check(not ring.describe().contains("fire"), "the card hides the magic: %s" % ring.describe())
	check(ring.describe().contains("Value unknown"), "and the price")
	var again := ContainerState.from_dict(box.to_dict())
	check(not again.inventory.get_at(0).identified, "saved as unidentified")
	check(again.inventory.get_at(3).identified, "and the known one as known")
	var known := ItemStack.create("ring_of_fire_resistance")
	check(not known.can_merge(ring), "known and unknown don't stack")
	var terms := {"buy_rate": 0.5}
	check_eq(InventoryOps.stack_sell_price(known, terms), 300, "known: half its value")
	check_eq(InventoryOps.stack_sell_price(ring, terms), 60, "unknown: a fifth of that")
	var e := _sheet("elowen")
	e.equip("ring_1", ring)
	check(e.resistances().has("fire"), "it works while unknown")


func test_a_short_rest_names_one_item_each() -> void:
	var e := _sheet("elowen")
	var g := _sheet("garrick")
	for id in ["ring_of_fire_resistance", "gauntlets_of_ogre_power"]:
		var st := ItemStack.create(id).as_found()
		e.inventory.add(st)
	var sword := ItemStack.create("longsword_plus_one").as_found()
	g.equip("main_hand", sword)
	check(g.attack_summary().begins_with("Unidentified weapon"), "the stats call it what it looks like: %s"
			% g.attack_summary())
	check(CombatRules.weapon_attacks(g)[0].name.begins_with("Unidentified weapon"), "and so does the fight log")
	var lines := Rest.short_rest([e, g] as Array[CharacterSheet])
	var text := "\n".join(lines)
	check(text.contains("Garrick Thorne studies the unidentified weapon: a +1 Longsword"), text)
	check(sword.identified, "the sword is known now")
	check_eq(InventoryOps.unidentified(e).size(), 1, "Elowen learned one of her two")
	Rest.short_rest([e] as Array[CharacterSheet])
	check(InventoryOps.unidentified(e).is_empty(), "and the other on the next rest")


func test_wenna_names_items_for_gold() -> void:
	GameState.start_new_game()
	var w: CharacterSheet = GameState.member("wren")
	check(not Conditions.check({"unidentified": true}), "nothing unknown yet")
	w.inventory.add(ItemStack.create("amulet_of_health").as_found())
	w.inventory.add(ItemStack.create("ring_of_fire_resistance").as_found())
	check(Conditions.check({"unidentified": true}), "now there is")
	GameState.gold = 30
	var msgs := Effects.apply({"identify": "all", "cost_each": 25}, w)
	check_eq(GameState.gold, 5, "paid for one")
	check(msgs[0].contains("Amulet of Health"), "named the first: %s" % msgs)
	check_eq(InventoryOps.unidentified(w).size(), 1, "couldn't afford the second")
	var d := Data.dialogue("res://data/dialogue/wenna.json")
	check(d.nodes.has("identify"), "Wenna offers it")


# --- traps -------------------------------------------------------------------------------

func _needle(find_dc: int = 13, disarm_dc: int = 13) -> Dictionary:
	return {"name": "poison needle", "find_dc": find_dc, "disarm": {"dc": disarm_dc, "ability": "dex",
			"tool": "thieves_tools"}, "save": "con", "save_dc": 12, "damage": "2d6", "damage_type": "poison",
			"half_on_save": true, "state": Traps.ARMED}


func test_noticing_a_trap() -> void:
	var party: Array[CharacterSheet] = [_sheet("garrick"), _sheet("elowen"), _sheet("odran"), _sheet("wren")]
	check_eq(Traps.passive_perception(party[3]), 13, "Wren: 10 + Wis 1 + Perception 2")
	check_eq(Traps.passive_perception(party[1]), 11, "Elowen: untrained")
	var hidden := _needle(15)
	check(Traps.notice(hidden, party) == null, "DC 15 goes unnoticed")
	check_eq(hidden["state"], Traps.ARMED, "still armed")
	var plain := _needle(13)
	var who := Traps.notice(plain, party)
	check(who != null and Traps.passive_perception(who) >= 13, "DC 13 is noticed")
	check(Traps.is_found(plain) and Traps.is_live(plain), "found, and still dangerous")
	check(Traps.notice(plain, party) == null, "noticed only once")


func test_who_can_disarm_a_trap() -> void:
	var party: Array[CharacterSheet] = [_sheet("garrick"), _sheet("elowen"), _sheet("wren")]
	var needle := _needle()
	check_eq(Traps.disarm_bonus(needle, party[0]), -1000, "Garrick has no thieves' tools")
	check_eq(Traps.disarm_bonus(needle, party[2]), 3 + 2 * 2, "Wren: Dex 3 + proficiency twice (Expertise)")
	check(Traps.best_disarmer(needle, party) == party[2], "so Wren tries")
	var glyph := {"name": "fire glyph", "disarm": {"dc": 14, "ability": "int", "skill": "arcana"}}
	check_eq(Traps.disarm_bonus(glyph, party[1]), 3 + 2, "Elowen: Int 3 + Arcana 2")
	check(Traps.best_disarmer(glyph, party) == party[1], "a glyph is Elowen's to undo")
	check_eq(Traps.disarm_means(needle), "thieves' tools", "named for the dialog")
	check_eq(Traps.disarm_means(glyph), "Arcana", "and the glyph")


func test_disarming_succeeds_fails_or_sets_it_off() -> void:
	var w := _sheet("wren")
	var easy := _needle(13, 1)
	check(Traps.try_disarm(easy, w)["ok"], "DC 1: disarmed")
	check_eq(easy["state"], Traps.DISARMED, "and stays so")
	check(not Traps.is_live(easy), "no longer a danger")
	# Fail by less than 5: nothing happens. Pre-roll the d20 with the same seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var d20 := Rules.roll(1, 20, rng)
	rng.seed = 77
	var close := _needle(13, d20 + Traps.disarm_bonus(_needle(), w) + 2)
	var r := Traps.try_disarm(close, w, rng)
	check(not r["ok"] and not r["sprung"], "missed by 2: try again later (%s)" % r["text"])
	check(Traps.is_live(close), "still armed")
	var hp := w.hp_current
	var hard := _needle(13, 60)
	r = Traps.try_disarm(hard, w)
	check(r["sprung"], "missed by 5 or more: it goes off (%s)" % r["text"])
	check(w.hp_current < hp or w.hp_current == hp and str(r["text"]).contains("takes 0"), "Wren is hurt")
	check_eq(hard["state"], Traps.SPRUNG, "spent")


func test_a_sprung_trap_hurts_and_resistance_helps() -> void:
	var e := _sheet("elowen")
	e.hp_max = 100
	e.hp_current = 100
	var glyph := {"name": "fire glyph", "save": "dex", "save_dc": 99, "damage": "10", "damage_type": "fire"}
	var text := Traps.spring(glyph, e)
	check_eq(e.hp_current, 90, "10 fire damage on a failed save: %s" % text)
	check(text.contains("Dexterity save") and text.contains("failed"), "the save is shown")
	_wear(e, "ring_1", "ring_of_fire_resistance")
	glyph["state"] = Traps.ARMED
	text = Traps.spring(glyph, e)
	check_eq(e.hp_current, 85, "the ring halves it: %s" % text)
	check(text.contains("resisted"), "and says so")
	var box := ContainerState.from_placement({"items": [], "trap": _needle()})
	box.trap["state"] = Traps.FOUND
	var again := ContainerState.from_dict(box.to_dict())
	check_eq(again.trap["state"], Traps.FOUND, "a found trap is saved as found")
	check(ContainerState.from_placement({"items": []}).trap.is_empty(), "no trap by default")
