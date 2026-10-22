extends TestCase
## Phase 4 (second half) rules without the scene: the spell data, spell slots
## by level, attack bonus and save DC, dice that grow (cantrips, upcasting),
## healing, what a level-up grants, class feature uses, short and long
## rests, lasting effects, and spells, features and scrolls used outside a
## fight (Abilities).


func before_each() -> void:
	GameState.start_new_game()


## Sets a sheet's level directly (no hit points gained) and grants what the class table gives.
func _at_level(s: CharacterSheet, level: int) -> CharacterSheet:
	s.level = level
	Classes.grant(s)
	return s


func test_spell_data_loads() -> void:
	for spell_id in ["fire_bolt", "sacred_flame", "guidance", "spare_the_dying", "magic_missile", "burning_hands",
			"sleep", "shield", "mage_armor", "bless", "cure_wounds", "healing_word", "guiding_bolt",
			"scorching_ray", "misty_step", "aid"]:
		check(Data.spells.has(spell_id), "spell %s is defined" % spell_id)
	var bh: SpellDef = Data.spells["burning_hands"]
	check(bh.area_shape == "cone" and bh.area_size == 3, "Burning Hands: a 15-ft cone = 3 hexes")
	var sleep: SpellDef = Data.spells["sleep"]
	check(sleep.area_shape == "circle" and sleep.area_size == 4 and sleep.range_hexes == 18,
			"Sleep: 20-ft radius (4 hexes) up to 90 ft (18 hexes)")
	check_eq((Data.spells["fire_bolt"] as SpellDef).range_hexes, 24, "Fire Bolt reaches 120 ft")
	check((Data.spells["shield"] as SpellDef).cast == "reaction", "Shield is a reaction")
	check((Data.spells["healing_word"] as SpellDef).cast == "bonus", "Healing Word is a bonus action")
	check((Data.spells["bless"] as SpellDef).concentration, "Bless needs concentration")


func test_full_caster_slot_table() -> void:
	var elowen := GameState.member("elowen")
	check_eq(Spellcasting.slots_max(elowen), {1: 2}, "level 1: two 1st-level slots")
	_at_level(elowen, 3)
	check_eq(Spellcasting.slots_max(elowen), {1: 4, 2: 2}, "level 3: four 1st, two 2nd")
	_at_level(elowen, 5)
	check_eq(Spellcasting.slots_max(elowen), {1: 4, 2: 3, 3: 2}, "level 5: 4/3/2")
	check_eq(Spellcasting.slots_max(GameState.member("garrick")), {}, "a fighter has no slots")
	check(not Spellcasting.is_caster(GameState.member("garrick")), "Garrick doesn't cast")


func test_attack_bonus_and_save_dc() -> void:
	var elowen := GameState.member("elowen")
	check_eq(Spellcasting.ability(elowen), "int", "wizards cast with Intelligence")
	check_eq(Spellcasting.attack_bonus(elowen), 5, "Int 17 (+3) + proficiency 2")
	check_eq(Spellcasting.save_dc(elowen), 13, "8 + 5")
	var odran := GameState.member("odran")
	check_eq(Spellcasting.ability(odran), "wis", "clerics cast with Wisdom")
	check_eq(Spellcasting.save_dc(odran), 13, "8 + Wis 16 (+3) + 2")


func test_cantrip_damage_grows_at_levels_5_11_17() -> void:
	var elowen := GameState.member("elowen")
	var fire: SpellDef = Data.spells["fire_bolt"]
	var expected := {1: "1d10", 4: "1d10", 5: "2d10", 11: "3d10", 17: "4d10"}
	for lv in expected:
		elowen.level = lv
		check_eq(Spellcasting.damage_expr(fire, elowen, 0), expected[lv], "Fire Bolt at level %d" % lv)


func test_upcasting_adds_dice_and_targets() -> void:
	var elowen := GameState.member("elowen")
	var bh: SpellDef = Data.spells["burning_hands"]
	check_eq(Spellcasting.damage_expr(bh, elowen, 1), "3d6", "Burning Hands, 1st-level slot")
	check_eq(Spellcasting.damage_expr(bh, elowen, 2), "4d6", "+1d6 per slot level above 1st")
	check_eq(Spellcasting.scaled(Data.spells["magic_missile"], "darts", 3), 5, "Magic Missile: 3 darts + 1 per level")
	check_eq(Spellcasting.scaled(Data.spells["sleep"], "pool", 2), "7d8", "Sleep: 5d8 + 2d8")
	check_eq(Spellcasting.scaled(Data.spells["aid"], "amount", 3), 10, "Aid: 5 + 5 with a 3rd-level slot")
	check_eq(Spellcasting.scaled(Data.spells["bless"], "targets", 2), 4, "Bless: one more target")
	check_eq(Spellcasting.add_dice("1d8", "1d8", 2), "3d8", "adding dice")


func test_healing_adds_the_casting_modifier_and_disciple_of_life() -> void:
	var odran := GameState.member("odran")
	check(odran.has_feature("disciple_of_life"), "the class table gave Odran Disciple of Life")
	var cure: SpellDef = Data.spells["cure_wounds"]
	for slot in [1, 2]:
		var a := RandomNumberGenerator.new()
		a.seed = 99
		var dice := Rules.roll_expr("%dd8" % slot, a)
		var b := RandomNumberGenerator.new()
		b.seed = 99
		check_eq(Spellcasting.heal_amount(cure, odran, slot, b), dice + 3 + 2 + slot,
				"Cure Wounds (slot %d): dice + Wis 3 + Disciple of Life (2 + slot)" % slot)


func test_slots_run_out_and_scrolls_need_the_class_list() -> void:
	var elowen := GameState.member("elowen")
	var mm: SpellDef = Data.spells["magic_missile"]
	check_eq(Spellcasting.cast_error(elowen, mm), "", "a slot is free")
	Spellcasting.spend_slot(elowen, 1)
	Spellcasting.spend_slot(elowen, 1)
	check(Spellcasting.cast_error(elowen, mm).contains("No 1st-level slots"), "out of slots")
	check_eq(Spellcasting.cast_error(elowen, Data.spells["fire_bolt"]), "", "cantrips need no slot")
	check_eq(Spellcasting.cast_error(elowen, mm, true), "", "a scroll needs no slot")
	check(not Spellcasting.cast_error(GameState.member("garrick"), mm, true).is_empty(),
			"a fighter can't read a wizard's scroll")
	check(not Spellcasting.cast_error(elowen, Data.spells["cure_wounds"], true).is_empty(),
			"a wizard can't read a cleric's scroll")
	check_eq(Spellcasting.slot_for(elowen, 1), 0, "no slot left to use")


func test_level_up_grants_features_spells_and_slots() -> void:
	var elowen := GameState.member("elowen")
	check(not Spellcasting.knows(elowen, "mage_armor"), "Mage Armor comes at level 2")
	check_eq(elowen.add_xp(300), 1, "300 XP: level 2")
	check(Spellcasting.knows(elowen, "mage_armor"), "Elowen learns Mage Armor")
	check(elowen.level_up_message().contains("Mage Armor") and elowen.level_up_message().contains("1st 3/3"),
			"the level-up message names it and the slots: %s" % elowen.level_up_message())
	elowen.add_xp(600)
	check(elowen.level == 3 and Spellcasting.knows(elowen, "scorching_ray") and Spellcasting.knows(elowen, "misty_step"),
			"level 3: 2nd-level spells")
	check_eq(Spellcasting.slots_left(elowen, 2), 2, "and two 2nd-level slots")
	var odran := GameState.member("odran")
	odran.add_xp(300)
	for f in ["channel_divinity", "turn_undead", "preserve_life"]:
		check(odran.has_feature(f), "Odran at level 2: %s" % f)
	var garrick := GameState.member("garrick")
	garrick.add_xp(300)
	check(garrick.has_feature("action_surge"), "Garrick at level 2: Action Surge")
	check_eq(garrick.hit_dice_left(), 2, "a hit die per level")
	var wren := GameState.member("wren")
	wren.add_xp(300)
	check(wren.has_feature("cunning_action"), "Wren at level 2: Cunning Action")


func test_feature_uses_and_recharge() -> void:
	var garrick := GameState.member("garrick")
	check_eq(Features.uses_left(garrick, "second_wind"), 1, "Second Wind: once")
	Features.spend(garrick, "second_wind")
	check_eq(Features.uses_left(garrick, "second_wind"), 0, "spent")
	check(Features.recharge(garrick, "short").has("Second Wind"), "a short rest brings it back")
	check_eq(Features.uses_left(garrick, "second_wind"), 1, "ready again")
	var odran := _at_level(GameState.member("odran"), 2)
	Features.spend(odran, "turn_undead")
	check_eq(Features.uses_left(odran, "preserve_life"), 0, "Turn Undead and Preserve Life share Channel Divinity")
	var elowen := GameState.member("elowen")
	Features.spend(elowen, "arcane_recovery")
	Features.recharge(elowen, "short")
	check_eq(Features.uses_left(elowen, "arcane_recovery"), 0, "Arcane Recovery only comes back on a long rest")
	Features.recharge(elowen, "long")
	check_eq(Features.uses_left(elowen, "arcane_recovery"), 1, "long rest")


func test_short_rest_spends_hit_dice_and_recovers_slots() -> void:
	var garrick := GameState.member("garrick")
	garrick.damage(8)
	Features.spend(garrick, "second_wind")
	var elowen := GameState.member("elowen")
	Spellcasting.spend_slot(elowen, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lines := Rest.short_rest(GameState.party, rng)
	check_eq(garrick.hit_dice_used, 1, "Garrick spent his one hit die")
	check(garrick.hp_current > garrick.hp_max - 8, "and healed")
	check_eq(Features.uses_left(garrick, "second_wind"), 1, "Second Wind is back")
	check_eq(Spellcasting.slots_left(elowen, 1), 2, "Arcane Recovery got the slot back")
	check(" ".join(lines).contains("Arcane Recovery"), "and says so: %s" % " ".join(lines))
	Spellcasting.spend_slot(elowen, 1)
	Rest.short_rest(GameState.party, rng)
	check_eq(Spellcasting.slots_left(elowen, 1), 1, "only once a day")
	garrick.heal(garrick.hp_max)
	garrick.damage(5)
	Rest.short_rest(GameState.party, rng)
	check_eq(garrick.hp_current, garrick.hp_max - 5, "no hit dice left, no healing")


func test_long_rest_restores_everything_and_ends_effects() -> void:
	var elowen := GameState.member("elowen")
	var ac := elowen.armor_class
	var mage_armor: SpellDef = Data.spells["mage_armor"]
	Spellcasting.apply_to_sheet(mage_armor, elowen, elowen, 1)
	check_eq(elowen.armor_class, 13 + elowen.ability_mod("dex"), "Mage Armor: 13 + Dex")
	var odran := _at_level(GameState.member("odran"), 3)
	var garrick := GameState.member("garrick")
	var hp_max := garrick.hp_max
	Spellcasting.apply_to_sheet(Data.spells["aid"], odran, garrick, 2)
	check_eq(garrick.hp_max, hp_max + 5, "Aid: +5 maximum hit points")
	Spellcasting.spend_slot(elowen, 1)
	garrick.damage(10)
	garrick.hit_dice_used = 1
	Features.spend(garrick, "second_wind")
	Rest.long_rest(GameState.party)
	check_eq(elowen.armor_class, ac, "Mage Armor ends")
	check_eq(garrick.hp_max, hp_max, "Aid ends")
	check_eq(garrick.hp_current, garrick.hp_max, "full hit points")
	check_eq(garrick.hit_dice_used, 0, "hit dice back")
	check_eq(Spellcasting.slots_left(elowen, 1), 2, "slots back")
	check_eq(Features.uses_left(garrick, "second_wind"), 1, "features back")


func test_guidance_and_expertise_add_to_checks() -> void:
	var wren := GameState.member("wren")
	var a := RandomNumberGenerator.new()
	a.seed = 5
	var b := RandomNumberGenerator.new()
	b.seed = 5
	var plain := Rules.ability_check(wren, "dex", true, a)
	check_eq(Rules.ability_check(wren, "dex", true, b, true), plain + wren.proficiency_bonus(),
			"Expertise doubles the proficiency bonus")
	Spellcasting.apply_to_sheet(Data.spells["guidance"], GameState.member("odran"), wren, 0)
	check(wren.effects.has("guidance"), "guided")
	Rules.ability_check(wren, "dex", true)
	check(not wren.effects.has("guidance"), "Guidance is used up by the next check")


func test_lasting_effects_survive_a_save() -> void:
	var elowen := GameState.member("elowen")
	Spellcasting.spend_slot(elowen, 1)
	Features.spend(elowen, "arcane_recovery")
	elowen.hit_dice_used = 1
	Spellcasting.apply_to_sheet(Data.spells["mage_armor"], elowen, elowen, 1)
	var copy := CharacterSheet.from_dict(elowen.to_dict())
	check_eq(Spellcasting.slots_left(copy, 1), 1, "spent slots are saved")
	check_eq(Features.uses_left(copy, "arcane_recovery"), 0, "feature uses are saved")
	check_eq(copy.hit_dice_used, 1, "spent hit dice are saved")
	check_eq(copy.armor_class, elowen.armor_class, "Mage Armor is saved")


func test_casting_outside_a_fight() -> void:
	var odran := GameState.member("odran")
	var garrick := GameState.member("garrick")
	var cure: SpellDef = Data.spells["cure_wounds"]
	var r := Abilities.cast(odran, cure, garrick, GameState.party)
	check(not r["ok"] and str(r["text"]).contains("not hurt"), "no healing the unhurt: %s" % r["text"])
	check_eq(Spellcasting.slots_left(odran, 1), 2, "and no slot spent")
	garrick.damage(9)
	r = Abilities.cast(odran, cure, garrick, GameState.party)
	check(r["ok"] and garrick.hp_current > garrick.hp_max - 9, "Cure Wounds heals Garrick: %s" % r["text"])
	check_eq(Spellcasting.slots_left(odran, 1), 1, "a slot is spent")
	check(Abilities.spell_error(GameState.member("elowen"), Data.spells["magic_missile"]).contains("fight"),
			"attack spells wait for a fight")
	check(Abilities.spell_error(odran, Data.spells["bless"]).contains("fight"), "so does Bless")
	check(not Abilities.picks_target(Data.spells["shield"]), "Shield isn't cast on someone")
	garrick.damage(4)
	r = Abilities.use_feature(garrick, "second_wind", GameState.party)
	check(r["ok"] and Features.uses_left(garrick, "second_wind") == 0, "Second Wind outside a fight: %s" % r["text"])
	check(not Abilities.use_feature(garrick, "second_wind", GameState.party)["ok"], "but only once")
	check(Abilities.feature_error(GameState.member("elowen"), "arcane_recovery", GameState.party).contains("short rest"),
			"Arcane Recovery happens during a short rest")


func test_preserve_life_heals_up_to_half() -> void:
	var odran := _at_level(GameState.member("odran"), 2)
	var garrick := GameState.member("garrick")
	check(not Abilities.use_feature(odran, "preserve_life", GameState.party)["ok"], "nobody is badly hurt")
	garrick.damage(garrick.hp_max - 1)
	var r := Abilities.use_feature(odran, "preserve_life", GameState.party)
	check(r["ok"], "Preserve Life: %s" % r["text"])
	check_eq(garrick.hp_current, mini(1 + 10, floori(garrick.hp_max / 2.0)), "up to half his maximum, from 5 × level")
	check_eq(Features.uses_left(odran, "turn_undead"), 0, "Channel Divinity is spent")


func test_reading_scrolls() -> void:
	var odran := GameState.member("odran")
	var garrick := GameState.member("garrick")
	odran.inventory.add_item("scroll_of_cure_wounds", 1)
	garrick.damage(6)
	var r := Abilities.read_scroll(odran, "scroll_of_cure_wounds", garrick, GameState.party)
	check(r["ok"] and str(r["text"]).contains("reads a scroll"), "Odran reads the scroll: %s" % r["text"])
	check(not odran.inventory.has("scroll_of_cure_wounds"), "the scroll is used up")
	check_eq(Spellcasting.slots_left(odran, 1), 2, "no slot spent")
	garrick.inventory.add_item("scroll_of_cure_wounds", 1)
	r = Abilities.read_scroll(garrick, "scroll_of_cure_wounds", garrick, GameState.party)
	check(not r["ok"] and garrick.inventory.has("scroll_of_cure_wounds"), "a fighter can't read it: %s" % r["text"])
	var elowen := GameState.member("elowen")
	elowen.inventory.add_item("scroll_of_magic_missile", 2)
	var kinds := {}
	for sc in Abilities.scrolls(elowen):
		kinds[sc["item"]] = int(sc["count"])
	check(kinds.has("scroll_of_hold_person"), "Elowen starts with a scroll of Hold Person")
	check_eq(kinds.get("scroll_of_magic_missile", 0), 2, "one entry per kind of scroll, with how many")
	r = Abilities.read_scroll(elowen, "scroll_of_magic_missile", null, GameState.party)
	check(not r["ok"] and elowen.inventory.count("scroll_of_magic_missile") == 2, "Magic Missile waits for a fight")
