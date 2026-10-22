class_name SpellDef
extends RefCounted
## One spell from data/spells/spells.json (see docs/SPELLS.md). A spell is
## data: what it targets, how far it reaches, and what it does (an attack
## roll, a saving throw, damage, healing, or a named effect such as "sleep").
## Spellcasting does the arithmetic; CombatSpells and Abilities cast it.

var id: String = ""
var display_name: String = ""
## 0 for a cantrip.
var level: int = 0
var school: String = ""
var classes: PackedStringArray = PackedStringArray()
## "action", "bonus" or "reaction".
var cast: String = "action"
## Reach in hexes (1 = touch, 0 = self).
var range_hexes: int = 0
## "enemy", "ally", "allies" (several), "self", "area" (a point or a cone) or "hex" (a place).
var target: String = "enemy"
## For target "area": "circle" (around a point) or "cone" (from the caster).
var area_shape: String = ""
## Circle radius, or cone length, in hexes.
var area_size: int = 0
## "ranged" or "melee" for a spell attack roll, "" for none.
var attack: String = ""
## Ability for the saving throw ("dex", "wis"...), "" for none.
var save: String = ""
var half_on_save: bool = false
var damage: String = ""
var damage_type: String = ""
## Damage dice grow at character levels 5, 11 and 17.
var cantrip_dice: bool = false
var heal: String = ""
## Magic Missile's darts and Scorching Ray's rays.
var darts: int = 0
var rays: int = 0
## Named effects: "sleep", "hold", "shield", "bless", "mark", "stabilize",
## "guidance", "mage_armor", "aid", "teleport".
var effect: String = ""
## The condition it imposes ("asleep", "paralyzed"); a creature immune to it is unaffected.
var condition: String = ""
## Who it works on (CreatureTypes.spell_refusal): {"types": [...]} only these
## creature types, {"not_types": [...]} never these, {"not_immune_to": [...]}
## nothing immune to these conditions. {} = anyone.
var affects: Dictionary = {}
## The target repeats the saving throw at the end of each of its turns,
## and shakes the effect off on a success (Hold Person).
var repeat_save: bool = false
var dice: String = ""
var rounds: int = 0
var targets: int = 1
var pool: String = ""
var amount: int = 0
var ac_bonus: int = 0
var concentration: bool = false
## Only makes sense in a fight (Bless, Misty Step).
var combat_only: bool = false
## Listed, but with no effect in the game yet (Light, Mage Hand).
var utility: bool = false
## What each slot level above the spell's own adds: {"damage": "1d6", "darts": 1...}.
var higher: Dictionary = {}
## How it looks in a fight (CombatFx): {"kind": "bolt"/"darts", "color": "#rrggbb"}.
var fx: Dictionary = {}
var description: String = ""


@warning_ignore("integer_division")
static func from_dict(spell_id: String, d: Dictionary) -> SpellDef:
	var s := SpellDef.new()
	var feet := maxi(1, GameConfig.feet_per_hex)
	s.id = spell_id
	s.display_name = str(d.get("name", spell_id.capitalize()))
	s.level = clampi(int(d.get("level", 0)), 0, 9)
	s.school = str(d.get("school", ""))
	s.classes = PackedStringArray(d.get("classes", []))
	s.cast = str(d.get("cast", "action"))
	s.range_hexes = maxi(0, int(d.get("range_ft", 0)) / feet)
	s.target = str(d.get("target", "enemy"))
	var area: Dictionary = d.get("area", {})
	s.area_shape = str(area.get("shape", ""))
	s.area_size = maxi(0, int(area.get("size_ft", 0)) / feet)
	s.attack = str(d.get("attack", ""))
	s.save = str(d.get("save", ""))
	s.half_on_save = bool(d.get("half_on_save", false))
	s.damage = str(d.get("damage", ""))
	s.damage_type = str(d.get("damage_type", ""))
	s.cantrip_dice = bool(d.get("cantrip_dice", false))
	s.heal = str(d.get("heal", ""))
	s.darts = int(d.get("darts", 0))
	s.rays = int(d.get("rays", 0))
	s.effect = str(d.get("effect", ""))
	s.condition = str(d.get("condition", ""))
	s.affects = d.get("affects", {})
	s.repeat_save = bool(d.get("repeat_save", false))
	s.dice = str(d.get("dice", ""))
	s.rounds = int(d.get("rounds", 0))
	s.targets = maxi(1, int(d.get("targets", 1)))
	s.pool = str(d.get("pool", ""))
	s.amount = int(d.get("amount", 0))
	s.ac_bonus = int(d.get("ac", 0))
	s.concentration = bool(d.get("concentration", false))
	s.combat_only = bool(d.get("combat_only", false))
	s.utility = bool(d.get("utility", false))
	s.higher = d.get("higher", {})
	s.fx = d.get("fx", {})
	s.description = str(d.get("description", ""))
	return s


func is_cantrip() -> bool:
	return level == 0


## Needs a creature or a place chosen before casting.
func needs_target() -> bool:
	return target in ["enemy", "ally", "area", "hex"]


## Harms its targets (cast on enemies, or an area that may catch them).
func is_harmful() -> bool:
	return not damage.is_empty() or effect in ["sleep", "hold"]


## "1st", "2nd", "3rd", "4th"...
static func ordinal(n: int) -> String:
	match n:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
	return "%dth" % n


## "Cantrip" or "1st-level evocation".
func level_text() -> String:
	return "Cantrip" if level == 0 else "%s-level" % ordinal(level)


## One line for buttons and lists: time, reach and what it does.
func summary() -> String:
	var parts := PackedStringArray()
	parts.append({"action": "Action", "bonus": "Bonus action", "reaction": "Reaction"}.get(cast, cast))
	if area_shape == "cone" or target == "self" or (range_hexes == 0 and target != "area"):
		parts.append("self")
	elif range_hexes <= 1:
		parts.append("touch")
	else:
		parts.append("%d ft" % (range_hexes * GameConfig.feet_per_hex))
	if area_shape == "cone":
		parts.append("%d-ft cone" % (area_size * GameConfig.feet_per_hex))
	elif area_shape == "circle":
		parts.append("%d-ft radius" % (area_size * GameConfig.feet_per_hex))
	if concentration:
		parts.append("concentration")
	return ", ".join(parts)
