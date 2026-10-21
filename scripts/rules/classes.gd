class_name Classes
extends RefCounted
## The class table (data/classes/classes.json): what each class gains at each
## level. A character's sheet lists its features and spells; Classes.grant()
## adds whatever the table says it should have by its level, so a sheet
## written for level 1 (or an old save) catches up, and a level-up brings the
## new features and spells.


static func info(class_id: String) -> Dictionary:
	return Data.classes.get(class_id, {})


static func feature(feature_id: String) -> Dictionary:
	return Data.features.get(feature_id, {})


static func feature_name(feature_id: String) -> String:
	return str(feature(feature_id).get("name", feature_id.capitalize()))


## Hit die sides for the class (d10 -> 10), falling back to the sheet's "hit_die".
static func hit_die(sheet: CharacterSheet) -> int:
	var die := str(info(sheet.character_class).get("hit_die", sheet.raw.get("hit_die", "d8")))
	return maxi(1, int(die.trim_prefix("d")))


## Features and spells the table grants from level 1 up to `level`, in order.
static func grants_up_to(class_id: String, level: int) -> Dictionary:
	var feats: Array[String] = []
	var spell_ids: Array[String] = []
	var c := info(class_id)
	for lv in range(1, level + 1):
		for f in (c.get("features", {}) as Dictionary).get(str(lv), []):
			feats.append(str(f))
		for sp in (c.get("spells", {}) as Dictionary).get(str(lv), []):
			spell_ids.append(str(sp))
	return {"features": feats, "spells": spell_ids}


## Adds to `sheet` every feature and spell its class should have by its level
## that it doesn't have yet. Returns the names of what was added.
static func grant(sheet: CharacterSheet) -> PackedStringArray:
	var added := PackedStringArray()
	if info(sheet.character_class).is_empty():
		return added
	var g := grants_up_to(sheet.character_class, sheet.level)
	var feats: Array = sheet.raw.get("features", [])
	for f in g["features"]:
		if not feats.has(f):
			feats.append(f)
			added.append(feature_name(f))
	sheet.raw["features"] = feats
	if not (g["spells"] as Array).is_empty():
		var sp: Dictionary = sheet.raw.get("spells", {}) if sheet.raw.get("spells") is Dictionary else {}
		var cantrips: Array = sp.get("cantrips", []) if sp.get("cantrips") is Array else []
		var known: Array = sp.get("known", []) if sp.get("known") is Array else []
		for spell_id in g["spells"]:
			var def: SpellDef = Data.spells.get(spell_id)
			if def == null:
				push_warning("Class %s grants unknown spell '%s'" % [sheet.character_class, spell_id])
				continue
			var list: Array = cantrips if def.is_cantrip() else known
			if not list.has(spell_id):
				list.append(spell_id)
				added.append(def.display_name)
		sp["cantrips"] = cantrips
		sp["known"] = known
		var casting: Dictionary = info(sheet.character_class).get("spellcasting", {})
		if sp.get("ability") == null or str(sp.get("ability", "")).is_empty():
			sp["ability"] = str(casting.get("ability", ""))
		sheet.raw["spells"] = sp
	return added
