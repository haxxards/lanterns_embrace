class_name Attack
extends RefCounted
## One way of attacking: a weapon in hand or a creature's natural attack, with
## its numbers already worked out (to-hit bonus, damage dice + modifier).
## Distances are in hexes (5 ft each).

var name: String = ""
var to_hit: int = 0
## Dice and modifier, e.g. "1d8+3".
var damage: String = "1"
var damage_type: String = ""
## Melee reach in hexes (1 = adjacent). 0 for ranged-only attacks.
var reach: int = 1
## Ranged attacks: normal and long range in hexes (0 = melee).
var range_normal: int = 0
var range_long: int = 0
## Item consumed per shot (arrows), "" for none.
var ammo: String = ""
var finesse: bool = false
var light: bool = false
## A two-weapon fighting attack with the off hand (a bonus action).
var off_hand: bool = false
## Extra effect on a hit, e.g. {"save": "str", "dc": 11, "condition": "prone"}.
var on_hit: Dictionary = {}
## The weapon used, if any.
var weapon: ItemDef = null
## A spell attack (Fire Bolt...): no Sneak Attack, no ammunition.
var spell: bool = false
## A thrown weapon: the equipment slot it leaves ("main_hand"/"off_hand"), else "".
var thrown_from: String = ""


func is_ranged() -> bool:
	return range_normal > 0


## Can hit a target `distance` hexes away (ranged: within long range).
func in_range(distance: int) -> bool:
	if is_ranged():
		return distance <= range_long
	return distance <= reach


func describe() -> String:
	return "%s %s, %s %s" % [name, Rules.format_modifier(to_hit), damage, damage_type]
