class_name ItemStack
extends RefCounted
## A quantity of one item type: what fills a backpack, equipment or container slot.

var id: String = ""
var qty: int = 1
## Resolved type, or null if `id` is not in items.json.
var def: ItemDef
## False for magic found in a chest or on a body until someone studies it on
## a short rest or pays to have it named (see docs/ITEMS.md). It works all
## the same; only its name, card and price are hidden.
var identified: bool = true


static func create(item_id: String, quantity: int = 1) -> ItemStack:
	var s := ItemStack.new()
	s.id = item_id
	s.qty = maxi(1, quantity)
	s.def = Data.items.get(item_id)
	return s


## Reads the JSON forms used by sheets, maps and saves:
## "dagger", {"item": "dagger", "qty": 2}, {"item": "amulet_of_health",
## "qty": 1, "unidentified": true}, or null (empty slot).
static func from_variant(v: Variant) -> ItemStack:
	if v is String and not (v as String).is_empty():
		return create(v)
	if v is Dictionary and (v as Dictionary).has("item"):
		var s := create(str(v["item"]), int(v.get("qty", 1)))
		s.identified = not bool(v.get("unidentified", false))
		return s
	return null


func to_variant() -> Dictionary:
	var d := {"item": id, "qty": qty}
	if not identified:
		d["unidentified"] = true
	return d


func copy() -> ItemStack:
	var s := create(id, qty)
	s.identified = identified
	return s


## Hides what a magic item is, if its kind starts unknown when found (see
## ItemDef.starts_unidentified). Returns itself.
func as_found() -> ItemStack:
	if def != null and def.starts_unidentified():
		identified = false
	return self


func is_valid() -> bool:
	return def != null


func max_stack() -> int:
	return def.max_stack if def else 1


func can_merge(other: ItemStack) -> bool:
	return other != null and other.id == id and max_stack() > 1 and other.identified == identified


func weight() -> float:
	return (def.weight if def else 0.0) * qty


## The item's name as the party knows it ("Unidentified ring" until known).
func item_name() -> String:
	if def == null:
		return id
	return def.display_name if identified else def.unknown_name()


## The tooltip card: the full one, or what can be seen of an unknown item.
func describe() -> String:
	if def == null:
		return id
	return def.describe() if identified else def.describe_unknown()


func display_name() -> String:
	var n := item_name()
	return n if qty == 1 else "%s ×%d" % [n, qty]
