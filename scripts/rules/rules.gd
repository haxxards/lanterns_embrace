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


## Rolls `count` dice with `sides` faces. Pass an RNG for reproducible results.
static func roll(count: int, sides: int, rng: RandomNumberGenerator = null) -> int:
	var total := 0
	for _i in count:
		total += rng.randi_range(1, sides) if rng else randi_range(1, sides)
	return total
