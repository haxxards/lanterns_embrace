class_name Rest
extends RefCounted
## Short and long rests (5e SRD, simplified: no clock moves on).
##
## Short rest (an hour): each character spends hit dice (one die of their
## class per level, d8 for a cleric) to heal, rolling die + Constitution each,
## until they are at full health or out of dice. Short-rest features come
## back (Second Wind, Action Surge, Channel Divinity), and a wizard's Arcane
## Recovery returns some spell slots once a day. Someone down but stable wakes
## with 1 hit point first.
##
## Long rest (a night): full hit points, all spell slots and features, half
## the hit dice spent (at least one) back, and the effects that last "until a
## long rest" end. Only under a roof: indoors, or in a room at the inn. The
## dead stay dead; the temple can raise them.


## Why the party can't take a `kind` rest here and now ("" if it can).
static func error(world: World, kind: String) -> String:
	if GameState.in_combat():
		return "You can't rest during a fight."
	if world != null:
		for cr in world.creatures:
			if not cr.is_alive():
				continue
			for m in world.party.members:
				if m.is_alive() and Hex.distance(m.hex, cr.hex) <= cr.def.aggro + 4 \
						and world.line_of_sight(m.hex, cr.hex):
					return "You can't rest with enemies nearby."
		if kind == "long" and world.map != null and world.map.backdrop_path.is_empty():
			return "A long rest needs a roof over your heads: go indoors, or take a room at the inn."
	return ""


## A short rest for every living member. Returns one line per thing that happened.
static func short_rest(party: Array[CharacterSheet], rng: RandomNumberGenerator = null) -> PackedStringArray:
	var out := PackedStringArray()
	for s in party:
		if s.dead:
			continue
		if s.is_down():
			s.heal(1)
			out.append("%s comes round." % s.display_name)
		var healed := 0
		var dice := 0
		while s.hp_current < s.hp_max and s.hit_dice_left() > 0:
			s.hit_dice_used += 1
			dice += 1
			healed += s.heal(maxi(0, Rules.roll(1, Classes.hit_die(s), rng) + s.ability_mod("con")))
		if dice > 0:
			out.append("%s spends %d hit %s and recovers %d hit points." % [s.display_name, dice,
					"die" if dice == 1 else "dice", healed])
		var back := Features.recharge(s, "short")
		if not back.is_empty():
			out.append("%s: %s ready again." % [s.display_name, ", ".join(back)])
		var recovered := _arcane_recovery(s)
		if not recovered.is_empty():
			out.append(recovered)
		# An hour with a magic item in hand is enough to learn what it is (one each).
		var unknown := InventoryOps.unidentified(s)
		if not unknown.is_empty():
			out.append("%s studies %s." % [s.display_name, InventoryOps.identify(unknown[0])])
		s.changed.emit()
	if out.is_empty():
		out.append("The party rests for an hour.")
	return out


## Arcane Recovery: once a day, recover spell slots whose levels add up to at
## most half the wizard level (rounded up), highest first; none above 5th.
@warning_ignore("integer_division")
static func _arcane_recovery(s: CharacterSheet) -> String:
	if not s.has_feature("arcane_recovery") or Features.uses_left(s, "arcane_recovery") <= 0:
		return ""
	var budget := (s.level + 1) / 2
	var got := PackedStringArray()
	for lv in range(5, 0, -1):
		while budget >= lv and int(s.slots_used.get(lv, 0)) > 0:
			s.slots_used[lv] = int(s.slots_used[lv]) - 1
			budget -= lv
			got.append(SpellDef.ordinal(lv))
	if got.is_empty():
		return ""
	Features.spend(s, "arcane_recovery")
	return "%s recovers a %s-level spell slot (Arcane Recovery)." % [s.display_name, ", ".join(got)] \
			if got.size() == 1 else "%s recovers spell slots: %s (Arcane Recovery)." % [s.display_name, ", ".join(got)]


## A long rest for every living member. Returns one line per member.
@warning_ignore("integer_division")
static func long_rest(party: Array[CharacterSheet]) -> PackedStringArray:
	var out := PackedStringArray()
	for s in party:
		if s.dead:
			out.append("%s lies dead; only the temple can help." % s.display_name)
			continue
		Spellcasting.end_long_rest_effects(s)
		s.heal(s.hp_max)
		s.hit_dice_used = maxi(0, s.hit_dice_used - maxi(1, s.level / 2))
		s.slots_used.clear()
		Features.recharge(s, "long")
		s.changed.emit()
		out.append("%s wakes rested: %d/%d hit points%s." % [s.display_name, s.hp_current, s.hp_max,
				", spells restored" if Spellcasting.is_caster(s) else ""])
	return out
