extends TestCase
## Creature types and races (CreatureTypes): what each party member and
## creature is, the conditions they can't suffer, and which spells work on
## them (Sleep, Hold Person). Also Hold Person's data and the held state in
## a saved fight.


func before_each() -> void:
	GameState.start_new_game()


func _creature(type: String) -> CreatureSheet:
	return CreatureSheet.create(Data.creatures[type])


func test_party_types_come_from_their_race() -> void:
	for id in ["garrick", "elowen", "odran", "wren"]:
		check_eq(CreatureTypes.type_of(GameState.member(id)), "humanoid", "%s is humanoid" % id)
	check_eq(CreatureTypes.race_of(GameState.member("elowen")), "elf", "Elowen is an elf")
	check_eq(CreatureTypes.describe(GameState.member("odran")), "humanoid (dwarf)", "described with the race")
	check(CreatureTypes.traits_of(GameState.member("elowen")).has("fey_ancestry"), "elves have Fey Ancestry")


func test_creature_types_races_and_immunities() -> void:
	check_eq(CreatureTypes.describe(_creature("wolf")), "beast", "a wolf is a beast, no race")
	check_eq(CreatureTypes.describe(_creature("bandit")), "humanoid (human)", "a bandit is a human")
	check_eq(CreatureTypes.type_of(_creature("skeleton")), "undead", "a skeleton is undead")
	check(CreatureTypes.immune_to(_creature("skeleton"), "poisoned"), "skeletons can't be poisoned")
	check(not CreatureTypes.immune_to(_creature("skeleton"), "paralyzed"), "but can be paralyzed")


func test_fey_ancestry() -> void:
	var elowen := GameState.member("elowen")
	check(CreatureTypes.immune_to(elowen, "asleep"), "magic can't put an elf to sleep")
	check_eq(CreatureTypes.immunity_source(elowen, "asleep"), "Fey Ancestry", "and says why")
	check(CreatureTypes.save_advantage(elowen, "charmed"), "advantage on saves against being charmed")
	check(not CreatureTypes.immune_to(GameState.member("garrick"), "asleep"), "a human can sleep")


func test_hold_person_works_only_on_humanoids() -> void:
	var hold: SpellDef = Data.spells["hold_person"]
	check_eq(CreatureTypes.spell_refusal(hold, _creature("bandit")), "", "bandits are humanoids")
	check_eq(CreatureTypes.spell_refusal(hold, GameState.member("garrick")), "", "so is Garrick")
	var wolf := CreatureTypes.spell_refusal(hold, _creature("wolf"))
	check(wolf.contains("humanoids") and wolf.contains("beast"), "not a wolf: %s" % wolf)
	check(not CreatureTypes.spell_refusal(hold, _creature("skeleton")).is_empty(), "not a skeleton")


func test_sleep_spares_undead_and_elves() -> void:
	var sleep: SpellDef = Data.spells["sleep"]
	check_eq(CreatureTypes.spell_refusal(sleep, _creature("wolf")), "", "wolves sleep")
	check_eq(CreatureTypes.spell_refusal(sleep, GameState.member("garrick")), "", "so does Garrick")
	check(CreatureTypes.spell_refusal(sleep, _creature("skeleton")).contains("undead"), "the undead don't")
	check(CreatureTypes.spell_refusal(sleep, GameState.member("elowen")).contains("Fey Ancestry"), "nor elves")


func test_a_hold_monster_is_just_data() -> void:
	var monster := SpellDef.from_dict("hold_monster", {"name": "Hold Monster", "level": 5, "save": "wis",
			"effect": "hold", "condition": "paralyzed", "affects": {"not_types": ["undead"]}})
	check_eq(CreatureTypes.spell_refusal(monster, _creature("wolf")), "", "holds a wolf")
	check(not CreatureTypes.spell_refusal(monster, _creature("skeleton")).is_empty(), "but not the undead")


func test_hold_person_data_and_class_tables() -> void:
	var hold: SpellDef = Data.spells["hold_person"]
	check(hold.level == 2 and hold.save == "wis" and hold.condition == "paralyzed", "2nd level, Wisdom save, paralyzed")
	check(hold.concentration and hold.repeat_save and hold.rounds == 10, "concentration, a save each turn, a minute")
	check_eq(int(Spellcasting.scaled(hold, "targets", 3)), 2, "one more humanoid per slot level above 2nd")
	var elowen := GameState.member("elowen")
	elowen.level = 3
	Classes.grant(elowen)
	check(Spellcasting.knows(elowen, "hold_person"), "wizards learn it at level 3")
	check(elowen.inventory.has("scroll_of_hold_person"), "and Elowen starts with a scroll of it")


func test_held_state_survives_a_save() -> void:
	var caster := Combatant.for_actor(null, GameState.member("odran"), Combatant.PARTY)
	var foe := Combatant.for_actor(null, _creature("bandit"), Combatant.HOSTILE)
	foe.key = "creature:b1"
	foe.held_by = caster
	foe.held_save = "wis"
	foe.held_dc = 13
	foe.held_spell = "hold_person"
	foe.asleep = true
	check(not foe.can_act() and foe.is_incapacitated(), "held: can't act")
	check(foe.conditions().has("paralyzed") and foe.conditions().has("asleep"), "conditions listed")
	var copy := Combatant.for_actor(null, foe.sheet, Combatant.HOSTILE)
	copy.load_dict(foe.to_dict(), {caster.key: caster})
	check(copy.held_by == caster and copy.held_dc == 13 and copy.held_spell == "hold_person", "held state restored")
