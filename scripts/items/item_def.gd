class_name ItemDef
extends RefCounted
## One item type from data/items/items.json (see docs/ITEMS.md).
##
## Item *types* are shared and never change during play; what a character
## carries is a list of ItemStack (type + quantity).

const KIND_CURRENCY := "currency"

## Equipment slots on the paper doll, in display order.
const EQUIP_SLOTS: PackedStringArray = [
	"helmet", "amulet", "armor", "cloak", "gloves",
	"main_hand", "off_hand", "ring_1", "ring_2", "boots",
]
const SLOT_NAMES := {
	"helmet": "Head", "amulet": "Neck", "armor": "Body", "cloak": "Cloak", "gloves": "Hands",
	"main_hand": "Main hand", "off_hand": "Off hand", "ring_1": "Ring", "ring_2": "Ring",
	"boots": "Feet",
}

var id: String = ""
var display_name: String = ""
## weapon, ammo, armor, shield, helmet, cloak, ring, amulet, boots, gloves,
## potion, food, gear, tool, book, gem, key, currency...
var kind: String = "gear"
## Equipment slot it fits ("ring" fits both ring slots), or "" if it can't be worn.
var slot: String = ""
var icon_path: String = ""
var icon: Texture2D
var weight: float = 0.0  # pounds
var value: float = 0.0   # gold pieces
var max_stack: int = 1
var description: String = ""
var magic: bool = false
## Quest items can't be sold.
var quest: bool = false
## Kind-specific blocks, straight from the JSON (see docs/ITEMS.md).
var weapon: Dictionary = {}
var armor: Dictionary = {}
var use: Dictionary = {}
var bonuses: Dictionary = {}
var tool: String = ""


static func from_dict(item_id: String, d: Dictionary) -> ItemDef:
	var it := ItemDef.new()
	it.id = item_id
	it.display_name = str(d.get("name", item_id.capitalize()))
	it.kind = str(d.get("kind", "gear"))
	it.slot = str(d.get("slot", ""))
	it.icon_path = str(d.get("icon", ""))
	it.weight = maxf(0.0, float(d.get("weight", 0.0)))
	it.value = maxf(0.0, float(d.get("value", 0.0)))
	it.max_stack = maxi(1, int(d.get("stack", 1)))
	it.description = str(d.get("description", ""))
	it.magic = bool(d.get("magic", false))
	it.quest = bool(d.get("quest", false))
	it.weapon = d.get("weapon", {})
	it.armor = d.get("armor", {})
	it.use = d.get("use", {})
	it.bonuses = d.get("bonuses", {})
	it.tool = str(d.get("tool", ""))
	return it


func is_currency() -> bool:
	return kind == KIND_CURRENCY


func is_weapon() -> bool:
	return not weapon.is_empty()


func is_body_armor() -> bool:
	return slot == "armor" and not armor.is_empty()


func is_shield() -> bool:
	return str(armor.get("type", "")) == "shield"


func is_usable() -> bool:
	return not use.is_empty()


## Thrown at a creature in a fight from the combat bar (Holy Water).
func is_throwable() -> bool:
	return use.get("throw") is Dictionary


## Whether this item is unknown when found in a chest or on a body: worn magic
## and magic weapons. Potions and scrolls are recognised on sight.
func starts_unidentified() -> bool:
	return magic and not kind in ["potion", "scroll"]


## "Unidentified ring", "Unidentified weapon"...
func unknown_name() -> String:
	return "Unidentified %s" % {"armor": "armour", "helmet": "helm"}.get(kind, kind)


## The card of an unidentified item: what anyone can see (a weapon's
## damage, armour's protection) but not its magic.
func describe_unknown() -> String:
	var lines := PackedStringArray([unknown_name() + "  (magic)"])
	if is_weapon():
		lines.append("Damage: %s %s" % [weapon.get("damage", "1"), weapon.get("damage_type", "")])
	lines.append("It has a magical feel, but what it does is unknown. Study it during a short rest, "
			+ "or ask someone who knows such things.")
	lines.append("Weight %s   Value unknown" % format_weight(weight))
	return "\n".join(lines)


## A magic weapon's bonus to attack and damage rolls (`weapon.bonus`, +1).
func weapon_bonus() -> int:
	return int(weapon.get("bonus", 0)) if is_weapon() else 0


func has_property(property: String) -> bool:
	return (weapon.get("properties", []) as Array).has(property)


## True if the item can go in equipment slot `slot_name` at all (character
## rules such as proficiency are checked by CharacterSheet.can_equip).
func fits_slot(slot_name: String) -> bool:
	if slot.is_empty():
		return false
	if slot == "ring":
		return slot_name == "ring_1" or slot_name == "ring_2"
	if slot_name == "off_hand" and is_weapon():
		return true  # any weapon may be tried in the off hand; rules decide
	return slot == slot_name


## "15 gp", "2 sp", "1 cp".
static func format_value(gp: float) -> String:
	if gp >= 1.0 or gp == 0.0:
		return "%s gp" % _trim(gp)
	if gp >= 0.1:
		return "%s sp" % _trim(gp * 10.0)
	return "%s cp" % _trim(gp * 100.0)


static func format_weight(lb: float) -> String:
	return "%s lb" % _trim(lb)


static func _trim(v: float) -> String:
	return str(int(round(v))) if is_equal_approx(v, round(v)) else ("%.2f" % v).rstrip("0").rstrip(".")


## Multi-line description for tooltips.
func describe() -> String:
	var lines := PackedStringArray()
	var head := display_name
	if magic:
		head += "  (magic)"
	lines.append(head)
	if is_weapon():
		var w := "%s %s" % [weapon.get("damage", "1"), weapon.get("damage_type", "")]
		if weapon.has("versatile"):
			w += ", %s two-handed" % weapon["versatile"]
		lines.append("Damage: " + w)
		var props: Array = weapon.get("properties", [])
		if not props.is_empty():
			lines.append("Properties: " + ", ".join(props.map(func(p: String) -> String: return p.replace("_", "-"))))
		if weapon.has("range"):
			var r: Array = weapon["range"]
			lines.append("Range: %d/%d ft" % [int(r[0]), int(r[1])])
		if weapon_bonus() != 0:
			lines.append("%s to attack and damage rolls" % Rules.format_modifier(weapon_bonus()))
	if is_body_armor():
		var a := "AC %d" % int(armor.get("base_ac", 10))
		match str(armor.get("type", "")):
			"light":
				a += " + Dex"
			"medium":
				a += " + Dex (max %d)" % int(armor.get("dex_cap", 2))
		lines.append("Armour: %s (%s)" % [a, armor.get("type", "")])
	elif is_shield():
		lines.append("Shield: +%d AC" % int(armor.get("ac_bonus", 2)))
	lines.append_array(bonus_lines())
	if use.has("heal"):
		lines.append("Use: heals %s" % use["heal"])
	var buff: Dictionary = use.get("buff", {})
	var scores: Dictionary = buff.get("abilities", {})
	for ab in Rules.ABILITIES:
		if scores.has(ab):
			lines.append("Use: %s %d until a long rest (if lower)" % [Rules.ABILITY_NAMES[ab], int(scores[ab])])
	if is_throwable():
		var t: Dictionary = use["throw"]
		var whom := ""
		var only: Array = (t.get("affects", {}) as Dictionary).get("types", [])
		if not only.is_empty():
			whom = " to %s only" % " and ".join(PackedStringArray(only.map(
					func(x: Variant) -> String: return str(x) if str(x) == "undead" else str(x) + "s")))
		lines.append("Use: thrown in a fight (%d ft): %s %s damage%s" % [int(t.get("range_ft", 20)),
				t.get("damage", "1"), t.get("damage_type", ""), whom])
	if use.has("cast"):
		var spell: SpellDef = Data.spells.get(str(use["cast"]))
		if spell != null:
			lines.append("Use: casts %s (%s spell; %s)" % [spell.display_name, " or ".join(spell.classes),
					spell.level_text().to_lower()])
	if not description.is_empty():
		lines.append(description)
	lines.append("Weight %s   Value %s" % [format_weight(weight), format_value(value)])
	return "\n".join(lines)


## One line per passive bonus in `bonuses` (see docs/ITEMS.md), for the
## item card: "+1 AC while worn", "Strength 19 while worn (if lower)"...
func bonus_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if bonuses.has("ac"):
		out.append("%s AC while worn" % Rules.format_modifier(int(bonuses["ac"])))
	if bonuses.has("saves"):
		out.append("%s to saving throws while worn" % Rules.format_modifier(int(bonuses["saves"])))
	var scores: Dictionary = bonuses.get("abilities", {})
	for ab in Rules.ABILITIES:
		if scores.has(ab):
			out.append("%s %d while worn (if lower)" % [Rules.ABILITY_NAMES[ab], int(scores[ab])])
	if bonuses.has("speed_ft"):
		out.append("Walking speed at least %d ft; armour and load don't slow you" % int(bonuses["speed_ft"]))
	var resist: Array = bonuses.get("resist", [])
	if not resist.is_empty():
		out.append("Resistance to %s damage while worn" % " and ".join(PackedStringArray(resist)))
	return out
