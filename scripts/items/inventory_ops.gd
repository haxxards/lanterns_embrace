class_name InventoryOps
extends RefCounted
## Moving items between backpacks, equipment slots and containers, with the
## game's rules applied. The inventory screen's drag and drop and the tests
## both go through these functions, so the rules live in one place.
##
## A slot reference is a small Dictionary:
##   {"kind": "backpack",  "sheet": CharacterSheet, "index": int}
##   {"kind": "equip",     "sheet": CharacterSheet, "slot": String}
##   {"kind": "container", "container": ContainerState, "index": int}
## A vendor's stock is a container ref with "trade" terms added
## ({"markup", "buy_rate", "vendor"}): moving out of it buys, into it sells.
## Every function returns "" on success or a message explaining the refusal.


static func backpack(sheet: CharacterSheet, index: int) -> Dictionary:
	return {"kind": "backpack", "sheet": sheet, "index": index}


static func equip_slot(sheet: CharacterSheet, slot: String) -> Dictionary:
	return {"kind": "equip", "sheet": sheet, "slot": slot}


static func container_slot(container: ContainerState, index: int) -> Dictionary:
	return {"kind": "container", "container": container, "index": index}


static func shop_slot(stock: ContainerState, index: int, terms: Dictionary) -> Dictionary:
	return {"kind": "container", "container": stock, "index": index, "trade": terms}


# --- prices ---------------------------------------------------------------------

## What the party pays per item: value × markup, at least 1 gp.
static func buy_price(def: ItemDef, terms: Dictionary) -> int:
	return maxi(1, ceili(def.value * float(terms.get("markup", 1.0))))


## What the party gets per item: value × buy_rate, rounded down.
static func sell_price(def: ItemDef, terms: Dictionary) -> int:
	return floori(def.value * float(terms.get("buy_rate", 0.5)))


static func can_sell(def: ItemDef) -> bool:
	return def != null and def.value > 0.0 and not def.is_currency() and not def.quest


static func stack_at(ref: Dictionary) -> ItemStack:
	match str(ref.get("kind", "")):
		"backpack":
			return (ref["sheet"] as CharacterSheet).inventory.get_at(int(ref["index"]))
		"equip":
			return (ref["sheet"] as CharacterSheet).equipped(str(ref["slot"]))
		"container":
			return (ref["container"] as ContainerState).inventory.get_at(int(ref["index"]))
	return null


static func _put(ref: Dictionary, stack: ItemStack) -> void:
	match str(ref.get("kind", "")):
		"backpack":
			(ref["sheet"] as CharacterSheet).inventory.set_at(int(ref["index"]), stack)
		"equip":
			(ref["sheet"] as CharacterSheet).equip(str(ref["slot"]), stack)
		"container":
			(ref["container"] as ContainerState).inventory.set_at(int(ref["index"]), stack)


static func same_slot(a: Dictionary, b: Dictionary) -> bool:
	if a.get("kind") != b.get("kind"):
		return false
	match str(a.get("kind")):
		"equip":
			return a["sheet"] == b["sheet"] and a["slot"] == b["slot"]
		"backpack":
			return a["sheet"] == b["sheet"] and a["index"] == b["index"]
	return a.get("container") == b.get("container") and a.get("index") == b.get("index")


## Why `stack` can't be placed at `ref` (ignoring what is there now), or "".
static func can_place(ref: Dictionary, stack: ItemStack) -> String:
	if stack == null:
		return ""
	match str(ref.get("kind", "")):
		"equip":
			return (ref["sheet"] as CharacterSheet).can_equip(str(ref["slot"]), stack)
		"backpack":
			return ""  # gold is turned into purse gold, anything else fits
	return ""


## Moves the stack at `from` onto `to`: places, merges or swaps. Out of a
## shop it buys, into a shop it sells.
static func move(from: Dictionary, to: Dictionary) -> String:
	var moving := stack_at(from)
	if moving == null or same_slot(from, to):
		return ""
	if from.has("trade") or to.has("trade"):
		if from.has("trade") and to.has("trade"):
			return ""
		if from.has("trade"):
			return buy(from, to["sheet"] if to.has("sheet") else null)
		return sell(from, to)
	# Gold never sits in a backpack: it goes to the shared purse.
	if moving.def != null and moving.def.is_currency() and to.get("kind") != "container":
		GameState.add_gold(moving.qty)
		_put(from, null)
		Audio.play_sfx("coins")
		return ""
	var target := stack_at(to)
	var err := can_place(to, moving)
	if not err.is_empty():
		return err
	# Equipment slots hold a single item; take one off a stack (e.g. daggers).
	if to.get("kind") == "equip" and moving.qty > 1:
		if target != null:
			var home := _free_backpack_slot(to["sheet"])
			if home.is_empty():
				return "No room in the backpack for the %s." % target.display_name()
			_put(home, target)
		moving.qty -= 1
		_put(from, moving)  # re-set so listeners hear about the change
		_put(to, ItemStack.create(moving.id, 1))
		_equip_sound(to)
		return ""
	if target != null and target.can_merge(moving):
		var room := target.max_stack() - target.qty
		var n := mini(room, moving.qty)
		if n <= 0:
			return ""
		target.qty += n
		moving.qty -= n
		_put(to, target)
		_put(from, moving if moving.qty > 0 else null)
		Audio.play_sfx("item_drop")
		return ""
	if target != null:
		var back := can_place(from, target)
		if not back.is_empty():
			return back
	# Swap. Clear the source first so equipment rules see the hands as they will be.
	_put(from, null)
	_put(to, moving)
	_put(from, target)
	if to.get("kind") == "equip" or from.get("kind") == "equip":
		_equip_sound(to if to.get("kind") == "equip" else from)
	else:
		Audio.play_sfx("item_drop")
	return ""


## Moves the stack at `from` into another character's backpack (wherever it fits).
static func give(from: Dictionary, to_sheet: CharacterSheet) -> String:
	var moving := stack_at(from)
	if moving == null:
		return ""
	if from.has("trade"):
		return buy(from, to_sheet, 1)  # a right-click buys one at a time
	if from.get("kind") != "container" and from.get("sheet") == to_sheet and from.get("kind") == "backpack":
		return ""
	if moving.def != null and moving.def.is_currency():
		return move(from, backpack(to_sheet, 0))
	if not to_sheet.inventory.can_fit(moving):
		return "%s's backpack is full." % to_sheet.display_name
	_put(from, null)
	to_sheet.inventory.add(moving)
	Audio.play_sfx("item_drop")
	return ""


## Takes everything out of a container: gold to the purse, items to `sheet`.
static func take_all(container: ContainerState, sheet: CharacterSheet) -> String:
	var full := false
	for i in container.inventory.capacity():
		var st := container.inventory.get_at(i)
		if st == null:
			continue
		if st.def != null and st.def.is_currency():
			GameState.add_gold(st.qty)
			container.inventory.set_at(i, null)
			Audio.play_sfx("coins")
			continue
		var left := sheet.inventory.add(st)
		if left > 0:
			full = true
			st.qty = left
			container.inventory.set_at(i, st)
		else:
			container.inventory.set_at(i, null)
	Audio.play_sfx("item_pickup")
	return "%s's backpack is full." % sheet.display_name if full else ""


## Buys as much of the shop stack at `from` as the purse allows (at most
## `limit` when given), into the buyer's backpack.
@warning_ignore("integer_division")
static func buy(from: Dictionary, buyer: CharacterSheet, limit: int = -1) -> String:
	var st := stack_at(from)
	if st == null or st.def == null or buyer == null:
		return ""
	var terms: Dictionary = from["trade"]
	var unit := buy_price(st.def, terms)
	var n := mini(st.qty if limit < 0 else mini(limit, st.qty), GameState.gold / unit)
	if n <= 0:
		return "You can't afford the %s (%d gp)." % [st.def.display_name, unit]
	var left := buyer.inventory.add(ItemStack.create(st.id, n))
	var bought := n - left
	if bought <= 0:
		return "%s's backpack is full." % buyer.display_name
	GameState.add_gold(-bought * unit)
	st.qty -= bought
	_put(from, st if st.qty > 0 else null)
	Audio.play_sfx("coins")
	return ""


## Sells the stack at `from` to the shop whose stock is `to`.
static func sell(from: Dictionary, to: Dictionary) -> String:
	var st := stack_at(from)
	if st == null:
		return ""
	var terms: Dictionary = to["trade"]
	if not can_sell(st.def):
		return "%s doesn't want that." % str(terms.get("vendor", "The trader"))
	var stock: ContainerState = to["container"]
	if not stock.inventory.can_fit(st):
		return "%s has no room for more." % str(terms.get("vendor", "The trader"))
	var price := sell_price(st.def, terms) * st.qty
	_put(from, null)
	stock.inventory.add(st)
	GameState.add_gold(price)
	Audio.play_sfx("coins")
	return ""


## Uses a consumable (drinks a potion, eats an apple). Returns what happened.
static func use(ref: Dictionary, sheet: CharacterSheet) -> String:
	var st := stack_at(ref)
	if st == null or st.def == null:
		return ""
	if not st.def.is_usable():
		return "%s can't be used like that." % st.def.display_name
	if sheet.dead:
		return "%s is beyond a potion's help." % sheet.display_name
	if GameState.in_combat():
		var err: String = GameState.combat.item_use_error(sheet)
		if not err.is_empty():
			return err
	var msg := ""
	if st.def.use.has("heal"):
		if sheet.hp_current >= sheet.hp_max:
			return "%s is not hurt." % sheet.display_name
		var healed := sheet.heal(Rules.roll_expr(str(st.def.use["heal"])))
		msg = "%s uses the %s and recovers %d hit points." % [sheet.display_name, st.def.display_name, healed]
		Audio.play_sfx("potion")
	st.qty -= 1
	_put(ref, st if st.qty > 0 else null)
	if GameState.in_combat():
		GameState.combat.item_used(sheet)  # drinking or giving a potion is an action
	return msg


static func _free_backpack_slot(sheet: CharacterSheet) -> Dictionary:
	var i := sheet.inventory.first_free()
	return backpack(sheet, i) if i >= 0 else {}


static func _equip_sound(ref: Dictionary) -> void:
	var st := stack_at(ref)
	var heavy := st != null and st.def != null and (st.def.is_body_armor() or st.def.is_shield())
	Audio.play_sfx("equip_armor" if heavy else "equip")
