class_name Abilities
extends RefCounted
## Spells, scrolls and class features used outside a fight, from the spells
## screen (B): healing, stabilising, the buffs that last until a long rest
## (Mage Armor, Aid, Guidance), Second Wind and Preserve Life. In a fight the
## combat bar does this instead, with the action economy, range and targets
## on the grid (CombatManager.use_ability). Outside a fight the party stands
## together, so range doesn't matter.


## Why `caster` can't cast `spell` outside a fight ("" if they can).
## `from_scroll`: read from a scroll (no slot, but it must be a class spell).
static func spell_error(caster: CharacterSheet, spell: SpellDef, from_scroll: bool = false) -> String:
	if GameState.in_combat():
		return "In a fight, use the combat bar."
	if spell.utility:
		return "%s has no effect in the game yet." % spell.display_name
	if spell.cast == "reaction":
		return "%s is cast for you in a fight, as a reaction." % spell.display_name
	if spell.combat_only or spell.is_harmful() or spell.target in ["enemy", "area", "hex"]:
		return "%s is only useful in a fight." % spell.display_name
	return Spellcasting.cast_error(caster, spell, from_scroll)


## The spell is cast on one party member the player picks (else on the
## caster, or on several at once).
static func picks_target(spell: SpellDef) -> bool:
	return spell.target == "ally"


## Why casting `spell` on `target` would be wasted ("" if it would help).
static func target_error(spell: SpellDef, target: CharacterSheet) -> String:
	if target.dead:
		return "%s is dead; only the temple can help." % target.display_name
	if not spell.heal.is_empty() and target.hp_current >= target.hp_max:
		return "%s is not hurt." % target.display_name
	match spell.effect:
		"stabilize":
			if not target.is_down() or target.stable:
				return "%s isn't dying." % target.display_name
		"guidance":
			if target.effects.has("guidance"):
				return "%s is already guided." % target.display_name
		"mage_armor":
			if target.effects.has("mage_armor"):
				return "%s is already warded." % target.display_name
			var armor := target.equipped_def("armor")
			if armor != null and armor.is_body_armor():
				return "%s is wearing armour; Mage Armor needs none." % target.display_name
	return ""


## The slot a cast would use: `wanted` if it is high enough and has a slot
## left, else the lowest that does; 0 for cantrips and scrolls (which use none).
static func slot_for(caster: CharacterSheet, spell: SpellDef, wanted: int = 0, from_scroll: bool = false) -> int:
	if from_scroll or spell.is_cantrip():
		return 0
	if wanted >= spell.level and Spellcasting.slots_left(caster, wanted) > 0:
		return wanted
	return Spellcasting.slot_for(caster, spell.level)


## Casts `spell` outside a fight: on `target` (picks_target spells), on
## several members (Aid), or on the caster. Spends the slot, unless it is a
## cantrip or `from_scroll`. Returns {"ok": bool, "text": what happened or why not}.
static func cast(caster: CharacterSheet, spell: SpellDef, target: CharacterSheet, party: Array[CharacterSheet],
		wanted_slot: int = 0, from_scroll: bool = false) -> Dictionary:
	var err := spell_error(caster, spell, from_scroll)
	if not err.is_empty():
		return {"ok": false, "text": err}
	var slot := slot_for(caster, spell, wanted_slot, from_scroll)
	var effective := spell.level if from_scroll else slot  # what the spell scales with
	var targets: Array[CharacterSheet] = []
	if spell.target == "allies":
		for s in party:
			if not s.dead and targets.size() < int(Spellcasting.scaled(spell, "targets", effective)):
				targets.append(s)
	else:
		targets.append(target if picks_target(spell) and target != null else caster)
	if targets.size() == 1:
		var why := target_error(spell, targets[0])
		if not why.is_empty():
			return {"ok": false, "text": why}
	if slot > 0:
		Spellcasting.spend_slot(caster, slot)
	Audio.play_sfx("spell_cast")
	var lines := PackedStringArray()
	for t in targets:
		lines.append(Spellcasting.apply_to_sheet(spell, caster, t, effective))
	var how := " from a scroll" if from_scroll else (" (%s-level slot)" % SpellDef.ordinal(slot) if slot > spell.level else "")
	return {"ok": true, "text": "%s casts %s%s: %s" % [caster.display_name, spell.display_name, how, " ".join(lines)]}


## Reads the scroll `item_id` from `reader`'s backpack, casting its spell on
## `target` (see cast()); the scroll is used up only if the spell works.
static func read_scroll(reader: CharacterSheet, item_id: String, target: CharacterSheet,
		party: Array[CharacterSheet]) -> Dictionary:
	var def: ItemDef = Data.items.get(item_id)
	var spell: SpellDef = Data.spells.get(str(def.use.get("cast", ""))) if def != null else null
	if spell == null or not reader.inventory.has(item_id):
		return {"ok": false, "text": "%s has no such scroll." % reader.display_name}
	var result := cast(reader, spell, target, party, 0, true)
	if result["ok"]:
		reader.inventory.remove_item(item_id, 1)
		reader.changed.emit()
		result["text"] = str(result["text"]).replace(" casts %s from a scroll" % spell.display_name,
				" reads a scroll of %s" % spell.display_name)
	return result


## Scrolls in `sheet`'s backpack, one per kind: [{"item": id, "spell": SpellDef, "count": n}].
static func scrolls(sheet: CharacterSheet) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for st in sheet.inventory.slots:
		if st == null or st.def == null or not st.def.use.has("cast") or seen.has(st.id):
			continue
		seen[st.id] = true
		var spell: SpellDef = Data.spells.get(str(st.def.use["cast"]))
		if spell != null:
			out.append({"item": st.id, "spell": spell, "count": sheet.inventory.count(st.id)})
	return out


# --- class features ---------------------------------------------------------------------

## Why `sheet` can't use `feature_id` outside a fight ("" if they can).
static func feature_error(sheet: CharacterSheet, feature_id: String, party: Array[CharacterSheet]) -> String:
	var f := Classes.feature(feature_id)
	var name := Classes.feature_name(feature_id)
	if GameState.in_combat():
		return "In a fight, use the combat bar."
	if f.get("on") == "short_rest":
		return "%s happens by itself during a short rest." % name
	if not f.has("cost"):
		return "%s is always at work; there is nothing to use." % name
	if bool(f.get("combat_only", false)):
		return "%s is only useful in a fight." % name
	if not sheet.is_alive():
		return "%s can't use %s while down." % [sheet.display_name, name]
	if Features.max_uses(sheet, feature_id) > 0 and Features.uses_left(sheet, feature_id) <= 0:
		return "No uses of %s left: back after a %s rest." % [Classes.feature_name(Features.pool(feature_id)),
				str(Classes.feature(Features.pool(feature_id)).get("recharge", "long"))]
	match feature_id:
		"second_wind":
			if sheet.hp_current >= sheet.hp_max:
				return "%s is not hurt." % sheet.display_name
		"preserve_life":
			if _below_half(party).is_empty():
				return "No one is below half their hit points."
	return ""


## Uses a feature outside a fight. Returns {"ok", "text"} like cast().
static func use_feature(sheet: CharacterSheet, feature_id: String, party: Array[CharacterSheet],
		rng: RandomNumberGenerator = null) -> Dictionary:
	var err := feature_error(sheet, feature_id, party)
	if not err.is_empty():
		return {"ok": false, "text": err}
	if Features.max_uses(sheet, feature_id) > 0:
		Features.spend(sheet, feature_id)
	match feature_id:
		"second_wind":
			var dice := str(Classes.feature(feature_id).get("heal", "1d10"))
			var healed := sheet.heal(Rules.roll_expr(dice, rng) + sheet.level)
			Audio.play_sfx("potion")
			return {"ok": true, "text": "%s uses Second Wind and recovers %d hit points." % [sheet.display_name, healed]}
		"preserve_life":
			var pool := 5 * sheet.level
			var lines := PackedStringArray()
			for t in _below_half(party):
				var give := mini(pool, floori(t.hp_max / 2.0) - t.hp_current)
				if give <= 0:
					continue
				pool -= give
				t.heal(give)
				lines.append("%s +%d" % [t.display_name, give])
			Audio.play_sfx("spell_cast")
			return {"ok": true, "text": "%s channels Preserve Life: %s." % [sheet.display_name, ", ".join(lines)]}
	return {"ok": false, "text": "%s can't be used here." % Classes.feature_name(feature_id)}


## Living members under half their hit points, the worst off first.
static func _below_half(party: Array[CharacterSheet]) -> Array[CharacterSheet]:
	var out: Array[CharacterSheet] = []
	for s in party:
		if not s.dead and s.hp_current * 2 < s.hp_max:
			out.append(s)
	out.sort_custom(func(a: CharacterSheet, b: CharacterSheet) -> bool:
		return a.hp_current * b.hp_max < b.hp_current * a.hp_max)
	return out
