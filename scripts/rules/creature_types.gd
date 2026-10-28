class_name CreatureTypes
extends RefCounted
## What kind of creature a sheet is, for the rules that care: its 5e creature
## type ("humanoid", "beast", "undead"...), its race, and the conditions it
## can't suffer. Party members get their type and traits from their
## ancestry (data/races/races.json: an elf is a humanoid with Fey Ancestry);
## creatures from their stat block (data/creatures/creatures.json: "type",
## "race", "condition_immunities").
##
## Spells say who they work on with "affects" (see spell_refusal):
##   Hold Person  {"types": ["humanoid"]}            humanoids only
##   Sleep        {"not_types": ["undead"],          not undead, nor anything
##                 "not_immune_to": ["charmed"]}     that can't be charmed
## and the condition they impose ("asleep", "paralyzed"), which a creature or
## race may be immune to. A "Hold Monster" is the same spell data with
## {"not_types": ["undead"]}.


## "humanoid", "beast", "undead"... ("humanoid" for a party member of unknown race).
static func type_of(sheet: CharacterSheet) -> String:
	if sheet is CreatureSheet:
		return (sheet as CreatureSheet).def.creature_type
	return str(race_info(sheet).get("type", "humanoid"))


## The race id ("elf", "human"), or "" for creatures without one.
static func race_of(sheet: CharacterSheet) -> String:
	if sheet is CreatureSheet:
		return (sheet as CreatureSheet).def.race
	return sheet.ancestry


## The race's entry in races.json ({} if none).
static func race_info(sheet: CharacterSheet) -> Dictionary:
	return Data.races.get(race_of(sheet), {}) if not sheet is CreatureSheet else {}


## Racial trait ids ("fey_ancestry"...).
static func traits_of(sheet: CharacterSheet) -> PackedStringArray:
	return PackedStringArray(race_info(sheet).get("traits", []))


## Every condition the creature can't suffer, from its stat block or its race's traits.
static func condition_immunities(sheet: CharacterSheet) -> PackedStringArray:
	var out := PackedStringArray()
	if sheet is CreatureSheet:
		out.append_array((sheet as CreatureSheet).def.condition_immunities)
	for t in traits_of(sheet):
		out.append_array(PackedStringArray((Data.race_traits.get(t, {}) as Dictionary).get("condition_immunities", [])))
	return out


static func immune_to(sheet: CharacterSheet, condition: String) -> bool:
	return condition_immunities(sheet).has(condition)


## Whether its race gives advantage on saves against `condition`.
static func save_advantage(sheet: CharacterSheet, condition: String) -> bool:
	if condition.is_empty():
		return false
	for t in traits_of(sheet):
		if PackedStringArray((Data.race_traits.get(t, {}) as Dictionary).get("save_advantage", [])).has(condition):
			return true
	return false


## The trait that makes it immune to `condition`, by name ("Fey Ancestry"), or "".
static func immunity_source(sheet: CharacterSheet, condition: String) -> String:
	for t in traits_of(sheet):
		var info: Dictionary = Data.race_traits.get(t, {})
		if PackedStringArray(info.get("condition_immunities", [])).has(condition):
			return str(info.get("name", t))
	return ""


## "humanoid (elf)", "beast", "undead".
static func describe(sheet: CharacterSheet) -> String:
	var t := type_of(sheet)
	var r := race_of(sheet)
	return t if r.is_empty() else "%s (%s)" % [t, r]


## Why `spell` has no effect on `sheet` ("" if it works): the wrong creature
## type, a type it never works on, or an immunity to the condition it imposes
## (or to one that rules it out, as Sleep is ruled out by charm immunity).
static func spell_refusal(spell: SpellDef, sheet: CharacterSheet) -> String:
	var who := sheet.display_name
	var by_type := type_refusal(spell.display_name, spell.affects, sheet)
	if not by_type.is_empty():
		return by_type
	if not spell.condition.is_empty() and immune_to(sheet, spell.condition):
		var source := immunity_source(sheet, spell.condition)
		return "%s can't be %s%s." % [who, spell.condition, " (%s)" % source if not source.is_empty() else ""]
	for c in spell.affects.get("not_immune_to", []):
		if immune_to(sheet, str(c)):
			return "%s can't be %s, so %s has no hold on it." % [who, c, spell.display_name]
	return ""


## Why `what` (a spell, Holy Water) does nothing to `sheet` by its creature
## type ("" if it works): `affects` lists "types" it works on only, and
## "not_types" it never works on.
static func type_refusal(what: String, affects: Dictionary, sheet: CharacterSheet) -> String:
	var t := type_of(sheet)
	var only := PackedStringArray(affects.get("types", []))
	if not only.is_empty() and not only.has(t):
		return "%s only works on %s; %s is %s." % [what, _plural(only), sheet.display_name, _a(t)]
	if PackedStringArray(affects.get("not_types", [])).has(t):
		return "%s doesn't work on %s; %s is %s." % [what, _plural([t]), sheet.display_name, _a(t)]
	return ""


static func _plural(types: Array) -> String:
	var words := PackedStringArray()
	for t in types:
		var s := str(t)
		words.append(s if s == "undead" else s + "s")
	return " and ".join(words)


## "a beast", "an elemental", "undead".
static func _a(word: String) -> String:
	if word == "undead" or word.is_empty():
		return word if not word.is_empty() else "something else"
	return ("an " if word.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + word
