class_name Traps
extends RefCounted
## Traps on containers (see docs/ITEMS.md): noticed by passive Perception,
## disarmed with a check, or set off for a saving throw and damage. The trap
## is a Dictionary on the ContainerState, straight from the map placement,
## plus its "state":
##
##   {"name": "poison needle", "find_dc": 13,
##    "disarm": {"dc": 13, "ability": "dex", "tool": "thieves_tools"},
##    "save": "con", "save_dc": 12, "damage": "2d6", "damage_type": "poison",
##    "half_on_save": true, "state": "armed"}
##
## "disarm" needs either a "tool" (thieves' tools: someone must carry a
## lockpick; proficiency from proficiencies.tools, Expertise doubles it) or a
## "skill" (arcana for a magical glyph: proficiency from proficiencies.skills).
## State: "armed" (not noticed), "found", "disarmed" or "sprung".

const ARMED := "armed"
const FOUND := "found"
const DISARMED := "disarmed"
const SPRUNG := "sprung"


## True while the trap can still go off (armed or found).
static func is_live(trap: Dictionary) -> bool:
	return not trap.is_empty() and str(trap.get("state", ARMED)) in [ARMED, FOUND]


static func is_found(trap: Dictionary) -> bool:
	return str(trap.get("state", ARMED)) == FOUND


## 10 + Wisdom modifier (+ proficiency with the Perception skill).
static func passive_perception(sheet: CharacterSheet) -> int:
	var trained := (sheet.proficiencies.get("skills", []) as Array).has("perception")
	return 10 + sheet.ability_mod("wis") + (sheet.proficiency_bonus() if trained else 0)


## Whoever in `party` (conscious) has the best passive Perception, if it
## reaches the trap's find_dc; else null. Marks the trap found.
static func notice(trap: Dictionary, party: Array[CharacterSheet]) -> CharacterSheet:
	if not is_live(trap) or is_found(trap):
		return null
	var best: CharacterSheet = null
	for s in party:
		if s.is_alive() and (best == null or passive_perception(s) > passive_perception(best)):
			best = s
	if best == null or passive_perception(best) < int(trap.get("find_dc", 10)):
		return null
	trap["state"] = FOUND
	return best


## The bonus `sheet` would add to a disarm check, or -1000 if they can't try
## (the trap wants thieves' tools and they carry none).
static func disarm_bonus(trap: Dictionary, sheet: CharacterSheet) -> int:
	var how: Dictionary = trap.get("disarm", {})
	var bonus := sheet.ability_mod(str(how.get("ability", "dex")))
	if how.has("tool"):
		if not sheet.inventory.has_tool("lockpick"):
			return -1000
		if (sheet.proficiencies.get("tools", []) as Array).has(str(how["tool"])):
			bonus += sheet.proficiency_bonus() * (2 if sheet.has_feature("expertise") else 1)
	elif how.has("skill") and (sheet.proficiencies.get("skills", []) as Array).has(str(how["skill"])):
		bonus += sheet.proficiency_bonus()
	return bonus


## The conscious member best at disarming it, or null if nobody can try.
static func best_disarmer(trap: Dictionary, party: Array[CharacterSheet]) -> CharacterSheet:
	var best: CharacterSheet = null
	for s in party:
		if s.is_alive() and disarm_bonus(trap, s) > -1000 \
				and (best == null or disarm_bonus(trap, s) > disarm_bonus(trap, best)):
			best = s
	return best


## What it takes to disarm, for the dialog: "thieves' tools" / "Arcana".
static func disarm_means(trap: Dictionary) -> String:
	var how: Dictionary = trap.get("disarm", {})
	if how.has("tool"):
		return str(how["tool"]).replace("_", " ").replace("thieves ", "thieves' ")
	return str(how.get("skill", "a steady hand")).capitalize()


## `sheet` tries to disarm it: d20 + disarm_bonus against disarm.dc. Failing
## by 5 or more sets it off on them. Returns {"ok", "sprung", "text"}.
static func try_disarm(trap: Dictionary, sheet: CharacterSheet, rng: RandomNumberGenerator = null) -> Dictionary:
	var dc := int((trap.get("disarm", {}) as Dictionary).get("dc", 10))
	var total := Rules.roll(1, 20, rng) + disarm_bonus(trap, sheet)
	if sheet.effects.has("guidance"):
		total += Rules.roll(1, 4, rng)
		sheet.effects.erase("guidance")
	var name := str(trap.get("name", "trap"))
	if total >= dc:
		trap["state"] = DISARMED
		return {"ok": true, "sprung": false, "text": "%s disarms the %s (%d vs DC %d)." % [sheet.display_name, name,
				total, dc]}
	if total <= dc - 5:
		var hurt := spring(trap, sheet, rng)
		return {"ok": false, "sprung": true, "text": "%s fumbles (%d vs DC %d) and sets off the %s! %s" % [
				sheet.display_name, total, dc, name, hurt]}
	return {"ok": false, "sprung": false, "text": "%s can't disarm the %s this time (%d vs DC %d)." % [
			sheet.display_name, name, total, dc]}


## Sets the trap off on `victim`: a saving throw, then its damage (halved on
## a save if half_on_save, and by resistance). Returns what happened.
static func spring(trap: Dictionary, victim: CharacterSheet, rng: RandomNumberGenerator = null) -> String:
	trap["state"] = SPRUNG
	var dmg := Rules.roll_expr(str(trap.get("damage", "1d6")), rng)
	var save_text := ""
	if trap.has("save"):
		var r := CombatRules.saving_throw(victim, str(trap["save"]), int(trap.get("save_dc", 10)), rng)
		save_text = " %s save %d vs DC %d: %s." % [Rules.ABILITY_NAMES.get(str(trap["save"]), trap["save"]),
				r["total"], int(trap.get("save_dc", 10)), "made it" if r["success"] else "failed"]
		if r["success"]:
			dmg = floori(dmg / 2.0) if bool(trap.get("half_on_save", true)) else 0
	var type := str(trap.get("damage_type", ""))
	var taken := CombatRules.adjust_for_type(victim, dmg, type)
	victim.damage(taken)
	var line := "%s takes %d %s damage%s%s" % [victim.display_name, taken, type,
			" (resisted)" if taken < dmg else "", "." if victim.is_alive() else " and falls!"]
	return line if save_text.is_empty() else "%s %s" % [save_text.strip_edges(), line]
