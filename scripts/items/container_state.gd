class_name ContainerState
extends RefCounted
## Contents and lock of one container (chest, drawers...) on a map. It lives
## in GameState, not on the prop, so it survives leaving the map and saving.

const MIN_SLOTS := 16

var inventory: Inventory
var locked: bool = false
## Difficulty to pick the lock with thieves' tools; 0 means it can't be picked.
var lock_dc: int = 0
## Item id that opens the lock, or "".
var key_id: String = ""


## Initial state from a map placement: {"items": [...], "gold": n, "locked": true,
## "lock_dc": 15, "key": "reeve_key"}. Magic found this way starts
## unidentified, unless its entry says "identified": true.
static func from_placement(extra: Dictionary) -> ContainerState:
	var c := ContainerState.new()
	var list: Array = (extra.get("items", []) as Array).duplicate()
	if int(extra.get("gold", 0)) > 0:
		list.append({"item": "gold", "qty": int(extra["gold"])})
	c.inventory = Inventory.from_array(list, maxi(MIN_SLOTS, list.size()))
	for i in list.size():
		var st := c.inventory.get_at(i)
		if st != null and not (list[i] is Dictionary and bool(list[i].get("identified", false))):
			st.as_found()
	c.locked = bool(extra.get("locked", false))
	c.lock_dc = int(extra.get("lock_dc", 0))
	c.key_id = str(extra.get("key", ""))
	return c


static func from_dict(d: Dictionary) -> ContainerState:
	var c := ContainerState.new()
	var list: Array = d.get("items", [])
	c.inventory = Inventory.from_array(list, maxi(MIN_SLOTS, list.size()))
	c.locked = bool(d.get("locked", false))
	c.lock_dc = int(d.get("lock_dc", 0))
	c.key_id = str(d.get("key", ""))
	return c


func to_dict() -> Dictionary:
	return {"items": inventory.to_array(), "locked": locked, "lock_dc": lock_dc, "key": key_id}
