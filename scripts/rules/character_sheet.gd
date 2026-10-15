class_name CharacterSheet
extends RefCounted
## A party member's character sheet, loaded from JSON (see docs/CHARACTER_SHEETS.md).
##
## The raw dictionary is kept so fields this version of the game does not use
## yet (inventory, spells, features...) survive a load/save round trip.

const SCHEMA_VERSION := 1

var id: String = ""
var display_name: String = ""
var ancestry: String = ""
var character_class: String = ""
var level: int = 1
var xp: int = 0
var abilities: Dictionary = {}
var hp_max: int = 1
var hp_current: int = 1
var armor_class: int = 10
var speed_ft: int = 30
var portrait_path: String = ""
var sprite_path: String = ""
## Optional sprite-sheet description (facings x walk frames), see docs/ASSETS.md.
var animation_path: String = ""
## Pixel in the sprite that sits on the hex centre (the character's feet).
var sprite_origin: Variant = null
var errors: PackedStringArray = PackedStringArray()
var source_path: String = ""
var raw: Dictionary = {}


static func from_dict(d: Dictionary, path: String = "") -> CharacterSheet:
	var s := CharacterSheet.new()
	s.raw = d.duplicate(true)
	s.source_path = path
	for key in ["id", "name", "class", "abilities", "hit_points"]:
		if not d.has(key):
			s.errors.append("missing required field '%s'" % key)
	if int(d.get("schema_version", SCHEMA_VERSION)) > SCHEMA_VERSION:
		s.errors.append("schema_version %s is newer than this game supports (%d)"
				% [d.get("schema_version"), SCHEMA_VERSION])
	s.id = str(d.get("id", path.get_file().get_basename()))
	s.display_name = str(d.get("name", s.id.capitalize()))
	s.ancestry = str(d.get("ancestry", "human"))
	s.character_class = str(d.get("class", "fighter"))
	s.level = clampi(int(d.get("level", 1)), 1, Rules.MAX_LEVEL)
	s.xp = maxi(0, int(d.get("xp", 0)))
	var abil: Dictionary = d.get("abilities", {})
	for ab in Rules.ABILITIES:
		var v := int(abil.get(ab, 10))
		if v < 1 or v > 30:
			s.errors.append("ability '%s' out of range: %d" % [ab, v])
		s.abilities[ab] = clampi(v, 1, 30)
	var hp: Dictionary = d.get("hit_points", {})
	s.hp_max = maxi(1, int(hp.get("max", 1)))
	s.hp_current = clampi(int(hp.get("current", s.hp_max)), 0, s.hp_max)
	s.armor_class = int(d.get("armor_class", 10 + s.ability_mod("dex")))
	s.speed_ft = maxi(0, int(d.get("speed_ft", 30)))
	var art: Dictionary = d.get("art", {})
	s.portrait_path = str(art.get("portrait", ""))
	s.sprite_path = str(art.get("sprite", ""))
	s.animation_path = str(art.get("animation", ""))
	if art.has("sprite_origin"):
		s.sprite_origin = JsonUtil.to_vec2(art["sprite_origin"])
	return s


static func load_file(path: String) -> CharacterSheet:
	var d: Variant = JsonUtil.load_json(path)
	if not d is Dictionary:
		var bad := CharacterSheet.new()
		bad.source_path = path
		bad.errors.append("could not parse JSON")
		return bad
	return from_dict(d, path)


## Serialises back to the JSON layout, keeping unknown fields intact.
func to_dict() -> Dictionary:
	var d := raw.duplicate(true)
	d["schema_version"] = SCHEMA_VERSION
	d["id"] = id
	d["name"] = display_name
	d["ancestry"] = ancestry
	d["class"] = character_class
	d["level"] = level
	d["xp"] = xp
	d["abilities"] = abilities.duplicate()
	d["hit_points"] = {"max": hp_max, "current": hp_current}
	d["armor_class"] = armor_class
	d["speed_ft"] = speed_ft
	return d


func is_valid() -> bool:
	return errors.is_empty()


func ability_mod(ability: String) -> int:
	return Rules.ability_modifier(int(abilities.get(ability, 10)))


func proficiency_bonus() -> int:
	return Rules.proficiency_bonus(level)


func is_alive() -> bool:
	return hp_current > 0


## Combat movement per turn, in hexes.
@warning_ignore("integer_division")
func speed_hexes(feet_per_hex: int) -> int:
	return speed_ft / maxi(1, feet_per_hex)


func summary() -> String:
	return "Level %d %s %s" % [level, ancestry.capitalize(), character_class.capitalize()]
