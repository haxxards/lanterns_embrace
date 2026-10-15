extends TestCase


func test_ability_modifiers() -> void:
	check_eq(Rules.ability_modifier(10), 0, "10")
	check_eq(Rules.ability_modifier(11), 0, "11")
	check_eq(Rules.ability_modifier(8), -1, "8")
	check_eq(Rules.ability_modifier(9), -1, "9")
	check_eq(Rules.ability_modifier(1), -5, "1")
	check_eq(Rules.ability_modifier(17), 3, "17")
	check_eq(Rules.ability_modifier(30), 10, "30")


func test_proficiency_bonus() -> void:
	check_eq(Rules.proficiency_bonus(1), 2, "level 1")
	check_eq(Rules.proficiency_bonus(4), 2, "level 4")
	check_eq(Rules.proficiency_bonus(5), 3, "level 5")
	check_eq(Rules.proficiency_bonus(17), 6, "level 17")
	check_eq(Rules.proficiency_bonus(20), 6, "level 20")


func test_levels_from_xp() -> void:
	check_eq(Rules.level_for_xp(0), 1, "0 xp")
	check_eq(Rules.level_for_xp(299), 1, "299 xp")
	check_eq(Rules.level_for_xp(300), 2, "300 xp")
	check_eq(Rules.level_for_xp(6500), 5, "6500 xp")
	check_eq(Rules.level_for_xp(999999), 20, "cap")
	check_eq(Rules.xp_for_next_level(1), 300, "next after 1")
	check_eq(Rules.xp_for_next_level(20), -1, "none after 20")


func test_character_sheet_round_trip() -> void:
	var d := {
		"schema_version": 1, "id": "test", "name": "Test Hero", "ancestry": "dwarf",
		"class": "cleric", "level": 3, "xp": 900,
		"abilities": {"str": 14, "dex": 8, "con": 16, "int": 10, "wis": 16, "cha": 11},
		"hit_points": {"max": 20, "current": 17}, "armor_class": 18, "speed_ft": 25,
		"inventory": [{"item": "torch", "qty": 3}],
		"art": {"portrait": "res://assets/portraits/odran.png", "sprite": "res://assets/characters/cleric.png"},
	}
	var s := CharacterSheet.from_dict(d)
	check(s.is_valid(), "valid sheet: %s" % ", ".join(s.errors))
	check_eq(s.ability_mod("dex"), -1, "dex mod")
	check_eq(s.proficiency_bonus(), 2, "prof bonus")
	check_eq(s.speed_hexes(5), 5, "25 ft = 5 hexes")
	var out := s.to_dict()
	check_eq(out["hit_points"]["current"], 17, "hp kept")
	check_eq(out["inventory"], d["inventory"], "inventory preserved")


func test_character_sheet_reports_errors() -> void:
	var s := CharacterSheet.from_dict({"id": "x", "abilities": {"str": 40}})
	check(not s.is_valid(), "missing fields / bad scores flagged")
