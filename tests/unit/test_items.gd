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
