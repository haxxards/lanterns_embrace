class_name Inventory
extends RefCounted
## A fixed number of slots holding ItemStacks (or null when empty), used for
## backpacks and containers. Slot positions are kept, like a BG backpack.

signal changed

var slots: Array[ItemStack] = []


func _init(capacity: int = 16) -> void:
	slots.resize(maxi(0, capacity))


func capacity() -> int:
	return slots.size()


func get_at(i: int) -> ItemStack:
	return slots[i] if i >= 0 and i < slots.size() else null


## Puts `stack` (or null) in slot `i`, returning what was there.
func set_at(i: int, stack: ItemStack) -> ItemStack:
	var old := slots[i]
	slots[i] = stack
	changed.emit()
	return old


func first_free() -> int:
	return slots.find(null)


func is_empty() -> bool:
	for s in slots:
		if s != null:
			return false
	return true


## Adds as much of `stack` as fits: tops up existing stacks of the same item
## first, then fills empty slots. Returns the quantity that did not fit.
func add(stack: ItemStack) -> int:
	if stack == null:
		return 0
	var left := stack.qty
	if stack.max_stack() > 1:
		for s in slots:
			if left > 0 and s != null and s.can_merge(stack):
				var moved := mini(left, s.max_stack() - s.qty)
				s.qty += moved
				left -= moved
	while left > 0:
		var i := first_free()
		if i < 0:
			break
		var put := mini(left, stack.max_stack())
		slots[i] = ItemStack.create(stack.id, put)
		left -= put
	if left != stack.qty:
		changed.emit()
	return left


func add_item(item_id: String, qty: int = 1) -> int:
	return add(ItemStack.create(item_id, qty))


## True if all of `stack` would fit.
func can_fit(stack: ItemStack) -> bool:
	var room := 0
	for s in slots:
		if s == null:
			room += stack.max_stack()
		elif s.can_merge(stack):
			room += s.max_stack() - s.qty
		if room >= stack.qty:
			return true
	return false


## Removes up to `qty` of an item, last slots first. Returns how many were removed.
func remove_item(item_id: String, qty: int = 1) -> int:
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		var s := slots[i]
		if removed >= qty or s == null or s.id != item_id:
			continue
		var take := mini(qty - removed, s.qty)
		s.qty -= take
		removed += take
		if s.qty <= 0:
			slots[i] = null
	if removed > 0:
		changed.emit()
	return removed


func count(item_id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s.id == item_id:
			n += s.qty
	return n


func has(item_id: String) -> bool:
	return count(item_id) > 0


func has_tool(tool_kind: String) -> bool:
	for s in slots:
		if s != null and s.def != null and s.def.tool == tool_kind:
			return true
	return false


func total_weight() -> float:
	var w := 0.0
	for s in slots:
		if s != null:
			w += s.weight()
	return w


## Moves everything into `other` where it fits. Returns true if all moved.
func transfer_all_to(other: Inventory) -> bool:
	var all_moved := true
	for i in slots.size():
		var s := slots[i]
		if s == null:
			continue
		var left := other.add(s)
		if left > 0:
			all_moved = false
			s.qty = left
		else:
			slots[i] = null
	changed.emit()
	return all_moved


## JSON form: a list of {"item", "qty"} or null, trailing empty slots trimmed.
func to_array() -> Array:
	var out: Array = []
	for s in slots:
		out.append(s.to_variant() if s != null else null)
	while not out.is_empty() and out.back() == null:
		out.pop_back()
	return out


## Builds an inventory from the JSON form. Grows past `capacity` rather than
## dropping items if the list is longer.
static func from_array(list: Variant, capacity: int) -> Inventory:
	var arr: Array = list if list is Array else []
	var inv := Inventory.new(maxi(capacity, arr.size()))
	for i in arr.size():
		inv.slots[i] = ItemStack.from_variant(arr[i])
	return inv
