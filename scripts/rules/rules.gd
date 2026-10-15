class_name Rules
extends RefCounted
## Core numbers from the 5e System Reference Document (SRD 5.1, CC-BY-4.0).
##
## Kept deliberately small and in one place so the rule set can be swapped or
## house-ruled without hunting through the codebase.

const ABILITIES: PackedStringArray = ["str", "dex", "con", "int", "wis", "cha"]
const ABILITY_NAMES := {
	"str": "Strength", "dex": "Dexterity", "con": "Constitution",
	"int": "Intelligence", "wis": "Wisdom", "cha": "Charisma",
}

## Experience needed to reach each level (index 0 = level 1).
const XP_THRESHOLDS: PackedInt32Array = [
	0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000,
	85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000,
]
const MAX_LEVEL := 20


static func ability_modifier(score: int) -> int:
	return floori((score - 10) / 2.0)


@warning_ignore("integer_division")
static func proficiency_bonus(level: int) -> int:
	return 2 + (clampi(level, 1, MAX_LEVEL) - 1) / 4


static func level_for_xp(xp: int) -> int:
	var level := 1
	for i in XP_THRESHOLDS.size():
		if xp >= XP_THRESHOLDS[i]:
			level = i + 1
	return level


## XP required for the next level, or -1 at max level.
static func xp_for_next_level(level: int) -> int:
	return XP_THRESHOLDS[level] if level < MAX_LEVEL else -1


static func format_modifier(m: int) -> String:
	return ("+%d" % m) if m >= 0 else str(m)


## 5e carrying capacity in pounds: Strength score × 15.
static func carrying_capacity(strength: int) -> float:
	return strength * 15.0


## Classes whose "unarmored_defense" feature adds a second ability to AC.
const UNARMORED_DEFENSE := {"barbarian": "con", "monk": "wis"}


## Armour class from worn equipment: armour base (+ Dex, capped for medium
## armour, none for heavy), or 10 + Dex unarmoured (+ Con or Wis with the
## barbarian/monk Unarmored Defense feature); plus a shield and any "ac"
## bonuses on worn items (rings, cloaks...).
static func armor_class(sheet: CharacterSheet) -> int:
	var dex := sheet.ability_mod("dex")
	var ac := 10 + dex
	if (sheet.raw.get("features", []) as Array).has("unarmored_defense") \
			and UNARMORED_DEFENSE.has(sheet.character_class):
		ac += sheet.ability_mod(UNARMORED_DEFENSE[sheet.character_class])
	var armor := sheet.equipped_def("armor")
	if armor != null and armor.is_body_armor():
		var base := int(armor.armor.get("base_ac", 10))
		match str(armor.armor.get("type", "light")):
			"light":
				ac = base + dex
			"medium":
				ac = base + mini(dex, int(armor.armor.get("dex_cap", 2)))
			_:
				ac = base
	for slot in ItemDef.EQUIP_SLOTS:
		var def := sheet.equipped_def(slot)
		if def == null:
			continue
		if def.is_shield() and slot == "off_hand":
			ac += int(def.armor.get("ac_bonus", 2))
		ac += int(def.bonuses.get("ac", 0))
	return ac


## Ability used to attack with `weapon`: Dex for ranged, the better of Str and
## Dex for finesse weapons, otherwise Str.
static func weapon_ability(sheet: CharacterSheet, weapon: ItemDef) -> String:
	if weapon.has_property("ammunition"):
		return "dex"
	if weapon.has_property("finesse") and sheet.ability_mod("dex") > sheet.ability_mod("str"):
		return "dex"
	return "str"


## Parses "2d4+2", "1d8", "d6-1" or "3" into {count, sides, bonus}. Empty on error.
static func parse_dice(expr: String) -> Dictionary:
	var re := RegEx.create_from_string("^\\s*(?:(\\d*)d(\\d+))?\\s*([+-]\\s*\\d+)?\\s*$")
	var flat := RegEx.create_from_string("^\\s*(-?\\d+)\\s*$")
	var m := flat.search(expr)
	if m:
		return {"count": 0, "sides": 0, "bonus": int(m.get_string(1))}
	m = re.search(expr)
	if m == null or m.get_string(2).is_empty():
		return {}
	var count := int(m.get_string(1)) if not m.get_string(1).is_empty() else 1
	var bonus := int(m.get_string(3).replace(" ", "")) if not m.get_string(3).is_empty() else 0
	return {"count": count, "sides": int(m.get_string(2)), "bonus": bonus}


## Rolls a dice expression such as "2d4+2". Invalid expressions roll 0.
static func roll_expr(expr: String, rng: RandomNumberGenerator = null) -> int:
	var d := parse_dice(expr)
	if d.is_empty():
		push_warning("Bad dice expression '%s'" % expr)
		return 0
	return roll(d["count"], d["sides"], rng) + int(d["bonus"])


## d20 + ability modifier (+ proficiency bonus if proficient): a 5e ability check.
static func ability_check(sheet: CharacterSheet, ability: String, proficient: bool,
		rng: RandomNumberGenerator = null) -> int:
	var total := roll(1, 20, rng) + sheet.ability_mod(ability)
	if proficient:
		total += sheet.proficiency_bonus()
	return total


## Rolls `count` dice with `sides` faces. Pass an RNG for reproducible results.
static func roll(count: int, sides: int, rng: RandomNumberGenerator = null) -> int:
	var total := 0
	for _i in count:
		total += rng.randi_range(1, sides) if rng else randi_range(1, sides)
	return total
