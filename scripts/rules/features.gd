class_name Features
extends RefCounted
## Class features with limited uses (Second Wind, Action Surge, Channel
## Divinity, Arcane Recovery...). Their definitions are in
## data/classes/classes.json; how many uses a character has spent lives on
## the sheet (feature_uses) and comes back on a short or long rest. Some
## features draw on another's uses: Turn Undead and Preserve Life both spend
## Channel Divinity.


## The feature whose uses `feature_id` spends (itself, or its "uses_from").
static func pool(feature_id: String) -> String:
	return str(Classes.feature(feature_id).get("uses_from", feature_id))


## Uses per recharge (0 for passive features).
static func max_uses(sheet: CharacterSheet, feature_id: String) -> int:
	var uses: Variant = Classes.feature(pool(feature_id)).get("uses", 0)
	if uses is Dictionary:  # {"1": 1, "6": 2}: the highest level reached
		var best := 0
		for lv in uses:
			if sheet.level >= int(lv):
				best = int(uses[lv])
		return best
	return int(uses)


static func uses_left(sheet: CharacterSheet, feature_id: String) -> int:
	var p := pool(feature_id)
	return maxi(0, max_uses(sheet, feature_id) - int(sheet.feature_uses.get(p, 0)))


static func spend(sheet: CharacterSheet, feature_id: String) -> void:
	var p := pool(feature_id)
	sheet.feature_uses[p] = int(sheet.feature_uses.get(p, 0)) + 1
	sheet.changed.emit()


## Features the character can choose to use (they have a "cost"), in sheet order.
static func usable(sheet: CharacterSheet) -> Array[String]:
	var out: Array[String] = []
	for f in sheet.raw.get("features", []):
		if Classes.feature(str(f)).has("cost"):
			out.append(str(f))
	return out


## Restores the uses of features that recharge on `kind` ("short" or "long";
## a long rest restores everything). Returns their names.
static func recharge(sheet: CharacterSheet, kind: String) -> PackedStringArray:
	var names := PackedStringArray()
	for p in sheet.feature_uses.keys():
		var when := str(Classes.feature(p).get("recharge", "long"))
		if kind == "long" or when == "short":
			if int(sheet.feature_uses[p]) > 0:
				names.append(Classes.feature_name(p))
			sheet.feature_uses.erase(p)
	return names


## "Second Wind: 1/1 (short rest)" for lists and tooltips.
static func uses_text(sheet: CharacterSheet, feature_id: String) -> String:
	var mx := max_uses(sheet, feature_id)
	if mx <= 0:
		return ""
	var when := str(Classes.feature(pool(feature_id)).get("recharge", "long"))
	return "%d/%d, back after a %s rest" % [uses_left(sheet, feature_id), mx, when]
