class_name CreatureDef
extends RefCounted
## A kind of hostile creature from data/creatures/creatures.json: a 5e SRD
## stat block plus how it behaves (ai, aggro) and what it drops (loot).

var id: String = ""
var display_name: String = ""
## SRD creature type: "beast", "humanoid", "undead"... (Sleep and Turn Undead check it).
var creature_type: String = ""
var armor_class: int = 10
var hp: int = 1
var speed_ft: int = 30
var abilities: Dictionary = {}
var xp: int = 0
var traits: PackedStringArray = PackedStringArray()
## Damage types it takes double from / half from / none from.
var vulnerable: PackedStringArray = PackedStringArray()
var resistant: PackedStringArray = PackedStringArray()
var immune: PackedStringArray = PackedStringArray()
## Raw attack entries (see attacks()).
var attack_data: Array = []
## "melee": closes in and strikes. "ranged": keeps its distance and shoots.
var ai: String = "melee"
## Hexes: how close the party may come (in sight) before it attacks.
var aggro: int = 7
var animation_path: String = ""
var sprite_path: String = ""
## [{"item": id, "qty": "2d6" or 3, "chance": 0.3}]
var loot: Array = []
var raw: Dictionary = {}


static func from_dict(creature_id: String, d: Dictionary) -> CreatureDef:
	var c := CreatureDef.new()
	c.raw = d
	c.id = creature_id
	c.display_name = str(d.get("name", creature_id.capitalize()))
	c.creature_type = str(d.get("type", ""))
	c.armor_class = int(d.get("ac", 10))
	c.hp = maxi(1, int(d.get("hp", 1)))
	c.speed_ft = int(d.get("speed_ft", 30))
	var abil: Dictionary = d.get("abilities", {})
	for ab in Rules.ABILITIES:
		c.abilities[ab] = int(abil.get(ab, 10))
	c.xp = int(d.get("xp", 0))
	c.traits = PackedStringArray(d.get("traits", []))
	c.vulnerable = PackedStringArray(d.get("vulnerable", []))
	c.resistant = PackedStringArray(d.get("resistant", []))
	c.immune = PackedStringArray(d.get("immune", []))
	c.attack_data = d.get("attacks", [])
	c.ai = str(d.get("ai", "melee"))
	c.aggro = int(d.get("aggro", 7))
	c.animation_path = str(d.get("animation", ""))
	c.sprite_path = str(d.get("sprite", c.animation_path.replace("_anim.json", ".png")))
	c.loot = d.get("loot", [])
	return c


func has_trait(t: String) -> bool:
	return traits.has(t)


## The stat block's attacks, ready to roll.
@warning_ignore("integer_division")
func attacks() -> Array[Attack]:
	var out: Array[Attack] = []
	var feet := maxi(1, GameConfig.feet_per_hex)
	for e in attack_data:
		var a := Attack.new()
		a.name = str(e.get("name", "Attack"))
		a.to_hit = int(e.get("to_hit", 0))
		a.damage = str(e.get("damage", "1"))
		a.damage_type = str(e.get("damage_type", ""))
		if e.has("range_ft"):
			var r: Array = e["range_ft"]
			a.range_normal = maxi(1, int(r[0]) / feet)
			a.range_long = maxi(a.range_normal, int(r[1]) / feet)
			a.reach = 0
		else:
			a.reach = maxi(1, int(e.get("reach_ft", 5)) / feet)
		a.on_hit = e.get("on_hit", {})
		a.fx = e.get("fx", {})
		out.append(a)
	return out
