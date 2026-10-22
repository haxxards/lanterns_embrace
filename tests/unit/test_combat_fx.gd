extends TestCase
## How attacks look (CombatFx.style_for): the swing, shot or spell effect
## picked for each weapon, creature attack and spell, the data overrides, and
## the attack anchors exported into every animated sprite sheet.


func before_each() -> void:
	GameState.start_new_game()


func _attack(list: Array[Attack], fragment: String) -> Attack:
	for a in list:
		if a.name.contains(fragment):
			return a
	return null


func _creature_attack(type: String, fragment: String) -> Attack:
	return _attack((Data.creatures[type] as CreatureDef).attacks(), fragment)


func test_party_weapons() -> void:
	var garrick := CombatRules.weapon_attacks(GameState.member("garrick"))
	var sword := CombatFx.style_for(garrick[0])
	check_eq(sword["kind"], "slash", "a longsword slashes")
	check(sword["icon"] != null, "with the longsword's icon riding the swing")
	var odran := CombatFx.style_for(CombatRules.weapon_attacks(GameState.member("odran"))[0])
	check_eq(odran["kind"], "smash", "a mace (bludgeoning) smashes down")
	var wren := CombatRules.weapon_attacks(GameState.member("wren"))
	var stab := CombatFx.style_for(_attack(wren, "Shortsword"))
	check(stab["kind"] == "thrust" and float(stab["size"]) < 46.0, "a light piercing blade thrusts, short: %s" % stab)
	var off := CombatFx.style_for(_attack(wren, "off hand"))
	check_eq(off["hand"], "off", "the off-hand dagger strikes from the other hand")
	var thrown := CombatFx.style_for(_attack(wren, "thrown"))
	check(thrown["kind"] == "thrown" and thrown["hand"] == "off" and thrown["icon"] != null,
			"a thrown dagger spins from the off hand: %s" % thrown)
	var staff := CombatFx.style_for(CombatRules.weapon_attacks(GameState.member("elowen"))[0])
	check_eq(staff["kind"], "slash", "the quarterstaff's \"fx\" override sweeps instead of smashing")


func test_unarmed_two_handed_and_bows() -> void:
	var garrick := GameState.member("garrick")
	garrick.equip("main_hand", ItemStack.create("greataxe"))
	check_eq(float(CombatFx.style_for(CombatRules.weapon_attacks(garrick)[0])["size"]), 56.0, "two-handed: a wider arc")
	garrick.equip("main_hand", null)
	garrick.equip("off_hand", null)
	check_eq(CombatFx.style_for(CombatRules.weapon_attacks(garrick)[0])["kind"], "punch", "no weapon: a punch")
	var wren := GameState.member("wren")
	wren.equip("main_hand", ItemStack.create("shortbow"))
	wren.equip("off_hand", null)
	var bow := CombatFx.style_for(CombatRules.weapon_attacks(wren)[0])
	check(bow["kind"] == "arrow" and bow["hand"] == "weapon", "a party bow shoots from the weapon hand: %s" % bow)


func test_creature_attacks() -> void:
	check_eq(CombatFx.style_for(_creature_attack("wolf", "Bite"), false)["kind"], "bite", "a wolf bites")
	check_eq(CombatFx.style_for(_creature_attack("bandit", "Scimitar"), false)["kind"], "slash", "a scimitar slashes")
	var sword := CombatFx.style_for(_creature_attack("skeleton", "Shortsword"), false)
	check(sword["kind"] == "thrust" and sword["icon"] != null, "a skeleton's shortsword thrusts, with the item's icon")
	var bow := CombatFx.style_for(_creature_attack("bandit_archer", "Shortbow"), false)
	check(bow["kind"] == "arrow" and bow["hand"] == "off", "archers shoot from their bow hand: %s" % bow)


func test_spell_effects() -> void:
	var elowen := GameState.member("elowen")
	var c := Combatant.for_actor(null, elowen, Combatant.PARTY)
	var fire := CombatFx.style_for(CombatSpells.spell_attack(c, Data.spells["fire_bolt"], 0))
	check(fire["kind"] == "bolt" and fire["hand"] == "focus", "Fire Bolt: a bolt from the staff")
	check(fire["color"].is_equal_approx(Color("#ff7a2a")), "in its colour from spells.json")
	var guide := CombatFx.style_for(CombatSpells.spell_attack(Combatant.for_actor(null, GameState.member("odran"),
			Combatant.PARTY), Data.spells["guiding_bolt"], 1))
	check(guide["color"].is_equal_approx(Color("#ffe9a0")), "Guiding Bolt is pale gold")
	check_eq(str((Data.spells["magic_missile"] as SpellDef).fx.get("kind", "")), "darts", "Magic Missile flies as darts")
	var plain := Attack.new()
	plain.spell = true
	plain.damage_type = "cold"
	check(CombatFx.style_for(plain)["color"].is_equal_approx(Color(CombatFx.DAMAGE_COLORS["cold"])),
			"a spell without \"fx\" takes its damage type's colour")


func test_every_sheet_has_attack_anchors() -> void:
	for path in DirAccess.get_files_at("res://assets/characters"):
		if not path.ends_with("_anim.json"):
			continue
		var d: Dictionary = JsonUtil.load_json("res://assets/characters/" + path)
		var rows: int = (d.get("directions", []) as Array).size()
		var anchors: Dictionary = d.get("anchors", {})
		for kind in ["weapon", "off", "focus", "head", "center"]:
			check(anchors.has(kind) and (anchors[kind] as Array).size() == rows,
					"%s has a %s anchor for each of its %d facings" % [path, kind, rows])
		if anchors.has("head"):
			check(float(anchors["head"][0][1]) < 0.0, "%s: the head is above the feet" % path)
