class_name ItemStack
extends RefCounted
## A quantity of one item type: what fills a backpack, equipment or container slot.

var id: String = ""
var qty: int = 1
## Resolved type, or null if `id` is not in items.json.
var def: ItemDef


static func create(item_id: String, quantity: int = 1) -> ItemStack:
	var s := ItemStack.new()
	s.id = item_id
	s.qty = maxi(1, quantity)
	s.def = Data.items.get(item_id)
	return s


## Reads the JSON forms used by sheets, maps and saves:
## "dagger", {"item": "dagger", "qty": 2}, or null (empty slot).
static func from_variant(v: Variant) -> ItemStack:
	if v is String and not (v as String).is_empty():
		return create(v)
	if v is Dictionary and (v as Dictionary).has("item"):
		return create(str(v["item"]), int(v.get("qty", 1)))
	return null


func to_variant() -> Dictionary:
	return {"item": id, "qty": qty}


func copy() -> ItemStack:
	return create(id, qty)


func is_valid() -> bool:
	return def != null


func max_stack() -> int:
	return def.max_stack if def else 1


func can_merge(other: ItemStack) -> bool:
	return other != null and other.id == id and max_stack() > 1


func weight() -> float:
	return (def.weight if def else 0.0) * qty


func display_name() -> String:
	var n := def.display_name if def else id
	return n if qty == 1 else "%s ×%d" % [n, qty]
