class_name Spellcasting
extends RefCounted
## A character's spellcasting (5e SRD): the spells they know, their spell
## slots, the spell attack bonus and save DC, how a spell's dice grow with
## character level (cantrips) or slot level (upcasting), and the effects that
## only touch character sheets (healing, stabilising, lasting buffs), which
## work the same in and out of a fight. Positions, attack rolls and areas are
## CombatSpells' job.

## Spell slots of a full caster (wizard, cleric) at each character level:
## index 0 is level 1; each entry lists slots of the 1st, 2nd... spell level.
const FULL_CASTER_SLOTS := [
	[2], [3], [4, 2], [4, 3], [4, 3, 2], [4, 3, 3], [4, 3, 3, 1], [4, 3, 3, 2], [4, 3, 3, 3, 1],
	[4, 3, 3, 3, 2], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1],
	[4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1, 1], [4, 3, 3, 3, 3, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 3, 2, 2, 1, 1],
]


## The casting ability ("int", "wis"), or "" for characters who don't cast.
static func ability(sheet: CharacterSheet) -> String:
	var sp: Variant = sheet.raw.get("spells")
	var a := str(sp.get("ability", "")) if sp is Dictionary and sp.get("ability") != null else ""
	if a.is_empty():
		var casting: Dictionary = Classes.info(sheet.character_class).get("spellcasting", {})
		a = str(casting.get("ability", ""))
	return a


static func is_caster(sheet: CharacterSheet) -> bool:
	return not ability(sheet).is_empty() and not known_ids(sheet).is_empty()


## Proficiency bonus + casting ability modifier.
static func attack_bonus(sheet: CharacterSheet) -> int:
	return sheet.proficiency_bonus() + sheet.ability_mod(ability(sheet))


## 8 + proficiency bonus + casting ability modifier.
static func save_dc(sheet: CharacterSheet) -> int:
	return 8 + attack_bonus(sheet)


## Cantrips first, then spells by level, as ids.
static func known_ids(sheet: CharacterSheet) -> Array[String]:
	var out: Array[String] = []
	var sp: Variant = sheet.raw.get("spells")
	if not sp is Dictionary:
		return out
	for key in ["cantrips", "known"]:
		var list: Variant = sp.get(key, [])
		if list is Array:
			for s in list:
				if Data.spells.has(str(s)) and not out.has(str(s)):
					out.append(str(s))
	return out


## The spells a character knows, cantrips first, then by level and name.
static func known(sheet: CharacterSheet) -> Array[SpellDef]:
	var out: Array[SpellDef] = []
	for spell_id in known_ids(sheet):
		out.append(Data.spells[spell_id])
	out.sort_custom(func(a: SpellDef, b: SpellDef) -> bool:
		return a.display_name < b.display_name if a.level == b.level else a.level < b.level)
	return out


static func knows(sheet: CharacterSheet, spell_id: String) -> bool:
	return known_ids(sheet).has(spell_id)


## Whether the spell is on the character's class list (needed to read a scroll).
static func on_class_list(sheet: CharacterSheet, spell: SpellDef) -> bool:
	return spell.classes.has(sheet.character_class)


# --- slots --------------------------------------------------------------------------

## Most slots per spell level: {1: 2, 2: 0...}, from the class's table (full
## casters) or, for anything else, the sheet's own "slots".
static func slots_max(sheet: CharacterSheet) -> Dictionary:
	var out := {}
	var casting: Dictionary = Classes.info(sheet.character_class).get("spellcasting", {})
	if str(casting.get("slots", "")) == "full":
		var row: Array = FULL_CASTER_SLOTS[clampi(sheet.level, 1, 20) - 1]
		for i in row.size():
			out[i + 1] = int(row[i])
		return out
	var sp: Variant = sheet.raw.get("spells")
	var raw_slots: Variant = sp.get("slots", {}) if sp is Dictionary else {}
	if raw_slots is Dictionary:
		for k in raw_slots:
			out[int(k)] = int(raw_slots[k])
	return out


static func slots_left(sheet: CharacterSheet, slot_level: int) -> int:
	return maxi(0, int(slots_max(sheet).get(slot_level, 0)) - int(sheet.slots_used.get(slot_level, 0)))


## The lowest slot level, at least `spell_level`, with a slot left; 0 if none.
static func slot_for(sheet: CharacterSheet, spell_level: int) -> int:
	var levels: Array = slots_max(sheet).keys()
	levels.sort()
	for lv in levels:
		if int(lv) >= spell_level and slots_left(sheet, int(lv)) > 0:
			return int(lv)
	return 0


static func spend_slot(sheet: CharacterSheet, slot_level: int) -> void:
	sheet.slots_used[slot_level] = int(sheet.slots_used.get(slot_level, 0)) + 1
	sheet.changed.emit()


## "1st 1/2   2nd 2/2" for lists and tooltips; "" for non-casters.
static func slots_text(sheet: CharacterSheet) -> String:
	var parts := PackedStringArray()
	var mx := slots_max(sheet)
	var levels: Array = mx.keys()
	levels.sort()
	for lv in levels:
		if int(mx[lv]) > 0:
			parts.append("%s %d/%d" % [SpellDef.ordinal(int(lv)), slots_left(sheet, int(lv)), int(mx[lv])])
	return "   ".join(parts)


# --- what a spell does at a given level ----------------------------------------------

## 1 below character level 5, then 2, 3 and 4 at levels 5, 11 and 17.
static func cantrip_tier(sheet: CharacterSheet) -> int:
	return 1 + (1 if sheet.level >= 5 else 0) + (1 if sheet.level >= 11 else 0) + (1 if sheet.level >= 17 else 0)


## `expr` with `extra` dice added `times` times: "3d6" + 2 × "1d6" -> "5d6".
## Dice of a different size are not mixed (the extra is ignored, with a warning).
static func add_dice(expr: String, extra: String, times: int) -> String:
	if times <= 0 or extra.is_empty():
		return expr
	var a := Rules.parse_dice(expr)
	var b := Rules.parse_dice(extra)
	if a.is_empty() or b.is_empty() or (int(a["sides"]) != int(b["sides"]) and int(a["count"]) > 0):
		push_warning("Can't add %s to %s" % [extra, expr])
		return expr
	var count := int(a["count"]) + int(b["count"]) * times
	var bonus := int(a["bonus"]) + int(b["bonus"]) * times
	var sides := int(b["sides"]) if int(a["count"]) == 0 else int(a["sides"])
	return "%dd%d%s" % [count, sides, Rules.format_modifier(bonus) if bonus != 0 else ""]


## Damage dice for one hit (or dart, or ray) of `spell` cast by `caster` with a
## slot of `slot_level`.
static func damage_expr(spell: SpellDef, caster: CharacterSheet, slot_level: int) -> String:
	var expr := spell.damage
	if spell.is_cantrip() and spell.cantrip_dice:
		var d := Rules.parse_dice(expr)
		if not d.is_empty():
			var bonus := int(d["bonus"])
			expr = "%dd%d%s" % [int(d["count"]) * cantrip_tier(caster), int(d["sides"]),
					Rules.format_modifier(bonus) if bonus != 0 else ""]
	return add_dice(expr, str(spell.higher.get("damage", "")), slot_level - spell.level)


## Numbers that grow with the slot: darts, rays, targets, the Sleep pool, Aid's amount.
static func scaled(spell: SpellDef, key: String, slot_level: int) -> Variant:
	var above := maxi(0, slot_level - spell.level)
	match key:
		"darts":
			return spell.darts + int(spell.higher.get("darts", 0)) * above
		"rays":
			return spell.rays + int(spell.higher.get("rays", 0)) * above
		"targets":
			return spell.targets + int(spell.higher.get("targets", 0)) * above
		"amount":
			return spell.amount + int(spell.higher.get("amount", 0)) * above
		"pool":
			return add_dice(spell.pool, str(spell.higher.get("pool", "")), above)
	return 0


## Hit points a healing spell restores: its dice (more with a higher slot) +
## the casting modifier, + 2 + slot level with Disciple of Life (1st level and up).
static func heal_amount(spell: SpellDef, caster: CharacterSheet, slot_level: int,
		rng: RandomNumberGenerator = null) -> int:
	var expr := add_dice(spell.heal, str(spell.higher.get("heal", "")), slot_level - spell.level)
	var total := Rules.roll_expr(expr, rng) + caster.ability_mod(ability(caster))
	if spell.level >= 1 and caster.has_feature("disciple_of_life"):
		total += 2 + slot_level
	return maxi(1, total)


## Why `sheet` can't cast `spell` at all right now ("" if it can): conscious,
## and a slot to spend unless it's a cantrip or read from a scroll.
static func cast_error(sheet: CharacterSheet, spell: SpellDef, from_scroll: bool = false) -> String:
	if not sheet.is_alive():
		return "%s can't cast while down." % sheet.display_name
	if from_scroll:
		if not on_class_list(sheet, spell):
			return "%s can't read a %s scroll: it isn't a %s spell." % [sheet.display_name,
					spell.display_name, sheet.character_class]
		return ""
	if not knows(sheet, spell.id):
		return "%s doesn't know %s." % [sheet.display_name, spell.display_name]
	if not spell.is_cantrip() and slot_for(sheet, spell.level) == 0:
		return "No %s-level slots left. A long rest restores them." % SpellDef.ordinal(spell.level)
	return ""


# --- effects on character sheets (in or out of a fight) -------------------------------

## Applies a spell's effect that only needs the target's sheet. Returns a
## short description ("Garrick regains 7 hit points."), or "" if the spell
## has no such effect (attacks, areas, teleports are CombatSpells').
static func apply_to_sheet(spell: SpellDef, caster: CharacterSheet, target: CharacterSheet, slot_level: int,
		rng: RandomNumberGenerator = null) -> String:
	if not spell.heal.is_empty():
		if target.dead:
			return "%s is beyond healing." % target.display_name
		var healed := target.heal(heal_amount(spell, caster, slot_level, rng))
		Audio.play_sfx("potion")
		return "%s regains %d hit points." % [target.display_name, healed]
	match spell.effect:
		"stabilize":
			if not target.is_down():
				return "%s isn't dying." % target.display_name
			target.stable = true
			target.changed.emit()
			return "%s is stable." % target.display_name
		"guidance":
			target.effects["guidance"] = true
			target.changed.emit()
			return "%s is guided: +1d4 to their next ability check." % target.display_name
		"mage_armor":
			var armor := target.equipped_def("armor")
			if armor != null and armor.is_body_armor():
				return "%s is wearing armour; Mage Armor needs none." % target.display_name
			target.effects["mage_armor"] = true
			target.recalculate()
			target.changed.emit()
			return "%s is warded: armour class %d until a long rest." % [target.display_name, target.armor_class]
		"aid":
			var amount := int(scaled(spell, "amount", slot_level))
			var had := int(target.effects.get("aid", 0))
			if had >= amount:
				return "%s is already aided." % target.display_name
			target.effects["aid"] = amount
			target.hp_max += amount - had
			if not target.dead:
				target.hp_current += amount - had
			target.changed.emit()
			return "%s gains %d hit points until a long rest." % [target.display_name, amount - had]
	return ""


## Ends the effects that last until a long rest (Mage Armor, Aid, Guidance).
static func end_long_rest_effects(sheet: CharacterSheet) -> void:
	if sheet.effects.has("aid"):
		sheet.hp_max = maxi(1, sheet.hp_max - int(sheet.effects["aid"]))
		sheet.hp_current = mini(sheet.hp_current, sheet.hp_max)
	sheet.effects.clear()
	sheet.recalculate()
