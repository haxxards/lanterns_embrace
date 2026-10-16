extends TestCase
## Phase 4 rules without the scene: weapon attacks from the party's gear,
## hit chances, critical hits, damage types, creature sheets, death saves,
## and movement ranges on the grid.


func before_each() -> void:
	GameState.start_new_game()


func _attack_named(list: Array[Attack], fragment: String) -> Attack:
	for a in list:
		if a.name.contains(fragment):
			return a
	return null


func test_party_weapon_attacks() -> void:
	var garrick := GameState.member("garrick")
	var g := CombatRules.weapon_attacks(garrick)
	check_eq(g.size(), 1, "Garrick: longsword only (a shield in the other hand)")
	check_eq(g[0].to_hit, 5, "Str +3, proficiency +2")
	check_eq(g[0].damage, "1d8+3", "one-handed longsword")
	check(not g[0].is_ranged() and g[0].reach == 1, "melee, reach 1 hex")
	var wren := CombatRules.weapon_attacks(GameState.member("wren"))
	check_eq(wren.size(), 2, "Wren: shortsword and an off-hand dagger")
	var sword := _attack_named(wren, "Shortsword")
	check(sword != null and sword.to_hit == 5 and sword.damage == "1d6+3", "finesse uses Dex +3: %s" % [sword.describe() if sword else "none"])
	var off := _attack_named(wren, "off hand")
	check(off != null and off.off_hand and off.damage == "1d4", "off hand adds no modifier: %s" % [off.describe() if off else "none"])
	var elowen := CombatRules.weapon_attacks(GameState.member("elowen"))
	check_eq(elowen[0].damage, "1d8-1", "quarterstaff in both hands (versatile), Str -1")
	GameState.member("wren").equip("main_hand", ItemStack.create("shortbow"))
	GameState.member("wren").equip("off_hand", null)
	var bow := CombatRules.weapon_attacks(GameState.member("wren"))[0]
	check(bow.is_ranged() and bow.range_normal == 16 and bow.range_long == 64, "shortbow 80/320 ft = 16/64 hexes")
	check_eq(bow.ammo, "arrows", "uses arrows")


func test_fighting_style_defense() -> void:
	var g := GameState.member("garrick")
	check_eq(g.armor_class, 19, "chain mail 16 + shield 2 + Defense 1")
	g.unequip("armor")
	check_eq(g.armor_class, 10 + g.ability_mod("dex") + 2, "Defense needs armour")


func test_hit_chance() -> void:
	check(is_equal_approx(CombatRules.hit_chance(5, 13, 0), 0.65), "+5 vs AC 13: 65%")
	check(is_equal_approx(CombatRules.hit_chance(5, 13, 1), 1.0 - 0.35 * 0.35), "advantage")
	check(is_equal_approx(CombatRules.hit_chance(5, 13, -1), 0.65 * 0.65), "disadvantage")
	check(is_equal_approx(CombatRules.hit_chance(20, 5, 0), 0.95), "a 1 always misses")
	check(is_equal_approx(CombatRules.hit_chance(0, 40, 0), 0.05), "a 20 always hits")


func test_attack_rolls_natural_ones_and_twenties() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var saw_crit := false
	var saw_one := false
	for i in 400:
		var r := CombatRules.roll_attack(30, 10, 0, rng)
		if r["d20"] == 20:
			saw_crit = true
			check(r["crit"] and r["hit"], "20 is a critical hit")
		if r["d20"] == 1:
			saw_one = true
			check(not r["hit"], "1 misses even with +30")
	check(saw_crit and saw_one, "both came up in 400 rolls")
	var adv_total := 0
	var dis_total := 0
	for i in 400:
		adv_total += CombatRules.roll_attack(0, 10, 1, rng)["d20"]
		dis_total += CombatRules.roll_attack(0, 10, -1, rng)["d20"]
	check(adv_total > dis_total + 400 * 4, "advantage rolls high, disadvantage low (%d vs %d)" % [adv_total, dis_total])


func test_critical_hits_double_the_dice() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hi := 0
	var lo := 999
	for i in 300:
		var d := CombatRules.roll_damage("1d6+2", true, rng)
		hi = maxi(hi, d)
		lo = mini(lo, d)
	check(lo >= 4 and hi <= 14 and hi > 8, "2d6+2 on a crit (%d-%d)" % [lo, hi])


func test_damage_types() -> void:
	var skel := CreatureSheet.create(Data.creatures["skeleton"])
	check_eq(CombatRules.adjust_for_type(skel, 5, "bludgeoning"), 10, "skeletons are vulnerable to bludgeoning")
	check_eq(CombatRules.adjust_for_type(skel, 5, "poison"), 0, "and immune to poison")
	check_eq(CombatRules.adjust_for_type(skel, 5, "slashing"), 5, "slashing is normal")
	check_eq(CombatRules.adjust_for_type(GameState.member("garrick"), 5, "poison"), 5, "the party has no immunities")


func test_creature_sheets() -> void:
	for id in Data.creatures:
		var def: CreatureDef = Data.creatures[id]
		check(not def.attacks().is_empty(), "%s has attacks" % id)
		check(def.xp > 0 and def.hp > 0, "%s has XP and hit points" % id)
		check(def.ai in ["melee", "ranged"], "%s ai is known" % id)
		for e in def.loot:
			check(Data.items.has(str(e["item"])), "%s drops a real item: %s" % [id, e["item"]])
	var wolf := CreatureSheet.create(Data.creatures["wolf"])
	check_eq(wolf.armor_class, 13, "wolf AC")
	check_eq(wolf.hp_current, 11, "wolf HP")
	check_eq(wolf.effective_speed_ft(), 40, "wolf speed")
	check(CombatRules.has_feature(wolf, "pack_tactics"), "pack tactics")
	var bite := wolf.def.attacks()[0]
	check(bite.to_hit == 4 and bite.damage == "2d4+2" and bite.reach == 1, "bite")
	check_eq(str(bite.on_hit.get("condition")), "prone", "knocks prone")
	wolf.damage(20)
	check(wolf.dead, "creatures die at 0 hit points")
	var archer := Data.creatures["bandit_archer"] as CreatureDef
	var c := Combatant.for_actor(null, CreatureSheet.create(archer), Combatant.HOSTILE)
	check(c.ranged_attack() != null and c.melee_attack() != null, "an archer has a bow and a dagger")
	check(c.attack_for(1).name == "Dagger", "prefers the dagger up close")
	check(c.attack_for(10).name == "Shortbow", "the bow at range")
	check_eq(c.attack_for(70), null, "nothing beyond long range")


func test_down_dying_and_dead() -> void:
	var odran := GameState.member("odran")
	odran.damage(odran.hp_current)
	check(odran.is_down() and not odran.dead, "at 0 HP: unconscious")
	odran.damage(1)
	check_eq(odran.death_failures, 1, "a hit while down is a failed death save")
	odran.damage(1, true)
	check_eq(odran.death_failures, 3, "a critical hit counts twice")
	check(odran.dead, "three failures: dead")
	check_eq(odran.heal(5), 0, "the dead can't be healed")
	odran.revive(1)
	check(odran.is_alive() and not odran.dead and odran.death_failures == 0, "raised")
	var wren := GameState.member("wren")
	wren.damage(wren.hp_current + wren.hp_max)
	check(wren.dead, "massive damage kills outright")
	var elowen := GameState.member("elowen")
	elowen.damage(elowen.hp_current)
	elowen.heal(3)
	check(elowen.is_alive() and elowen.hp_current == 3, "healing wakes the unconscious")


func test_death_saving_throws() -> void:
	var rng := RandomNumberGenerator.new()
	var outcomes := {}
	for seed_value in 60:
		GameState.start_new_game()
		var s := GameState.member("garrick")
		s.damage(s.hp_current)
		rng.seed = seed_value
		var result := ""
		for i in 10:
			result = s.roll_death_save(rng)
			if result in ["rallies", "dies", "stable"]:
				break
		outcomes[result] = true
		match result:
			"rallies":
				check(s.is_alive() and s.hp_current == 1, "a 20 brings them round with 1 HP")
			"dies":
				check(s.dead and s.death_failures >= 3, "three failures")
			"stable":
				check(s.stable and s.death_successes >= 3 and s.is_down(), "three successes: stable")
	check(outcomes.has("dies") and outcomes.has("stable"), "both ends seen: %s" % [outcomes.keys()])


func test_turn_bookkeeping() -> void:
	var c := Combatant.for_actor(null, GameState.member("garrick"), Combatant.PARTY)
	c.begin_turn()
	check_eq(c.movement_left, 30.0, "30 ft to move")
	c.action_used = true
	c.prone = true
	c.begin_turn()
	check(not c.action_used and not c.prone, "a new turn: action back, stood up")
	check_eq(c.movement_left, 15.0, "standing up cost half the movement")


func test_reachable_within() -> void:
	var grid := HexGrid.new()
	grid.setup(10, 10, 32.0)
	var grass: TerrainDef = Data.terrain_by_symbol["."]
	var shallows: TerrainDef = Data.terrain_by_symbol["-"]
	for r in 10:
		for q in 10:
			grid.set_terrain(Hex.offset_to_axial(Vector2i(q, r)), grass)
	grid.set_terrain(Hex.offset_to_axial(Vector2i(5, 4)), shallows)
	grid.rebuild_pathfinding()
	var start := Hex.offset_to_axial(Vector2i(4, 4))
	var reach := grid.reachable_within(start, 2)
	check_eq(reach[start], 0.0, "start costs nothing")
	for h in reach:
		check(Hex.distance(start, h) <= 2, "nothing beyond 2 hexes")
	check_eq(reach.get(Hex.offset_to_axial(Vector2i(5, 4))), 2.0, "difficult ground costs double")
	var blocker := Hex.offset_to_axial(Vector2i(3, 4))
	grid.set_occupied(blocker, true)
	check(not grid.reachable_within(start, 2).has(blocker), "occupied hexes can't be entered")
