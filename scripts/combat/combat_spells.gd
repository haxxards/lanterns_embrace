class_name CombatSpells
extends RefCounted
## Casting a spell in a fight: whether it can be cast now (the action
## economy, slots, the bonus-action spell rule), which targets and hexes it
## would affect (with a preview for the cursor), and what it does. The
## arithmetic is Spellcasting's; CombatManager provides attacks, damage,
## saving throws and the log.
##
## Areas on the hex grid: a "circle" is every hex within its radius of the
## chosen point; a "cone" is every hex within its length of the caster whose
## direction is within 30 degrees of the aim (a 60-degree wedge).

const CONE_HALF_ANGLE := 31.0  # degrees; a hair over 30 so hexes on the edge count


## Why `c` can't cast `spell` right now ("" if it can). `scroll_item` names
## the scroll it would be read from, if any.
static func error(c: Combatant, spell: SpellDef, scroll_item: String = "") -> String:
	if spell.utility:
		return "%s has no effect in the game yet." % spell.display_name
	if spell.cast == "reaction":
		return "%s is cast for you automatically, as a reaction." % spell.display_name
	if not c.can_act():
		return "%s can't act." % c.display_name()
	var e := Spellcasting.cast_error(c.sheet, spell, not scroll_item.is_empty())
	if not e.is_empty():
		return e
	if spell.cast == "bonus":
		if c.bonus_used:
			return "%s has already used their bonus action." % c.display_name()
		if c.cast_leveled_spell:
			return "After casting a spell of 1st level or higher, no bonus-action spell this turn."
	else:
		if c.action_used:
			return "%s has already used their action." % c.display_name()
		if c.cast_bonus_spell and not spell.is_cantrip():
			return "After a bonus-action spell, only a cantrip this turn."
	return ""


## The slot level a cast would use: the scroll's own level, 0 for a cantrip,
## else `wanted` (or the lowest with a slot left).
static func slot_level(c: Combatant, spell: SpellDef, scroll_item: String = "", wanted: int = 0) -> int:
	if not scroll_item.is_empty():
		return spell.level
	if spell.is_cantrip():
		return 0
	if wanted >= spell.level and Spellcasting.slots_left(c.sheet, wanted) > 0:
		return wanted
	return Spellcasting.slot_for(c.sheet, spell.level)


# --- areas ----------------------------------------------------------------------------

## Hexes of a cone `length` long from `origin` towards `aim`.
static func cone(grid: HexGrid, origin: Vector2i, aim: Vector2i, length: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if aim == origin:
		return out
	var o := grid.hex_to_world(origin)
	var dir := (grid.hex_to_world(aim) - o).normalized()
	var limit := cos(deg_to_rad(CONE_HALF_ANGLE))
	for h in Hex.spiral(origin, length):
		if h == origin or not grid.in_bounds(h):
			continue
		var v := (grid.hex_to_world(h) - o).normalized()
		if v.dot(dir) >= limit:
			out.append(h)
	return out


## Hexes within `radius` of `center`.
static func circle(grid: HexGrid, center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in Hex.spiral(center, radius):
		if grid.in_bounds(h):
			out.append(h)
	return out


## The hexes `spell` covers when aimed at `aim` by `c`.
static func area_hexes(m: CombatManager, c: Combatant, spell: SpellDef, aim: Vector2i) -> Array[Vector2i]:
	match spell.area_shape:
		"cone":
			return cone(m.world.grid, c.hex(), aim, spell.area_size)
		"circle":
			return circle(m.world.grid, aim, spell.area_size)
	var one: Array[Vector2i] = [aim]
	return one


## Everyone (friend or foe) standing in `hexes`, still in the fight.
static func combatants_in(m: CombatManager, hexes: Array[Vector2i]) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for o in m.combatants:
		if not o.is_out() and is_instance_valid(o.actor) and hexes.has(o.hex()):
			out.append(o)
	return out


## Allies of `c` (itself included) within `spell`'s range, nearest first, up to its number of targets.
static func nearby_allies(m: CombatManager, c: Combatant, spell: SpellDef, slot: int) -> Array[Combatant]:
	var allies: Array[Combatant] = []
	for o in m.combatants:
		if o.team == c.team and not o.is_out() and is_instance_valid(o.actor) \
				and m.distance(o, c) <= maxi(1, spell.range_hexes):
			allies.append(o)
	allies.sort_custom(func(a: Combatant, b: Combatant) -> bool: return m.distance(a, c) < m.distance(b, c))
	return allies.slice(0, int(Spellcasting.scaled(spell, "targets", slot)))


## Who Sleep would put to sleep, given the hit points `pool` rolled: the
## conscious, awake, living (not undead) in the area, fewest hit points first.
static func sleep_victims(m: CombatManager, hexes: Array[Vector2i], center: Vector2i, pool: int) -> Array[Combatant]:
	var cands: Array[Combatant] = []
	for o in combatants_in(m, hexes):
		if o.is_conscious() and not o.asleep and not o.is_undead():
			cands.append(o)
	cands.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.sheet.hp_current != b.sheet.hp_current:
			return a.sheet.hp_current < b.sheet.hp_current
		return Hex.distance(a.hex(), center) < Hex.distance(b.hex(), center))
	var out: Array[Combatant] = []
	for o in cands:
		if o.sheet.hp_current > pool:
			break
		pool -= o.sheet.hp_current
		out.append(o)
	return out


# --- choosing a target -------------------------------------------------------------------

## What casting `spell` at hex `h` (with `who` standing there, or null) would
## do: {"ok": bool, "text": String, "hexes": Array[Vector2i]}. "text" says
## why not, or what will happen.
static func preview(m: CombatManager, c: Combatant, spell: SpellDef, slot: int, h: Vector2i,
		who: Combatant) -> Dictionary:
	var hexes: Array[Vector2i] = []
	var dist := Hex.distance(c.hex(), h)
	var feet := GameConfig.feet_per_hex
	match spell.target:
		"enemy", "ally":
			hexes.append(h)
			if who == null:
				return _no(hexes, "Choose a %s for %s." % ["foe" if spell.target == "enemy" else "companion", spell.display_name])
			if (spell.target == "enemy") != who.is_hostile_to(c):
				return _no(hexes, "%s works on %s." % [spell.display_name, "foes" if spell.target == "enemy" else "companions"])
			if dist > maxi(1, spell.range_hexes):
				return _no(hexes, "%s is out of range (%d ft)." % [who.display_name(), maxi(1, spell.range_hexes) * feet])
			if dist > 1 and not m.world.line_of_sight(c.hex(), h):
				return _no(hexes, "No clear line to %s." % who.display_name())
			if spell.target == "enemy":
				return {"ok": true, "hexes": hexes, "text": _enemy_text(m, c, spell, slot, who)}
			var why := _ally_error(spell, who)
			if not why.is_empty():
				return _no(hexes, why)
			return {"ok": true, "hexes": hexes, "text": "%s on %s." % [spell.display_name, who.display_name()]}
		"area":
			hexes = area_hexes(m, c, spell, h)
			if spell.area_shape == "circle":
				if dist > spell.range_hexes:
					return _no(hexes, "Too far: %s reaches %d ft." % [spell.display_name, spell.range_hexes * feet])
				if not m.world.line_of_sight(c.hex(), h):
					return _no(hexes, "No clear line to that spot.")
			elif hexes.is_empty():
				return _no(hexes, "Aim the cone away from %s." % c.display_name())
			var caught := combatants_in(m, hexes)
			var names := PackedStringArray()
			for o in caught:
				names.append(o.display_name())
			if spell.effect == "sleep":
				return {"ok": true, "hexes": hexes, "text": "Sleep: %s in the area (fewest hit points sleep first)."
						% (", ".join(names) if not names.is_empty() else "nobody")}
			return {"ok": true, "hexes": hexes, "text": "%s catches: %s." % [spell.display_name,
					", ".join(names) if not names.is_empty() else "nobody"]}
		"hex":
			hexes.append(h)
			if dist > spell.range_hexes:
				return _no(hexes, "Too far: %s reaches %d ft." % [spell.display_name, spell.range_hexes * feet])
			if not m.world.grid.is_ground_walkable(h) or m.world.grid.is_occupied(h) or h == c.hex():
				return _no(hexes, "Choose an empty spot.")
			if not m.world.line_of_sight(c.hex(), h):
				return _no(hexes, "You must see the spot.")
			return {"ok": true, "hexes": hexes, "text": "Step to this spot."}
	return {"ok": true, "hexes": hexes, "text": spell.display_name}


static func _no(hexes: Array[Vector2i], text: String) -> Dictionary:
	return {"ok": false, "hexes": hexes, "text": text}


static func _ally_error(spell: SpellDef, who: Combatant) -> String:
	if who.is_out():
		return "%s is dead." % who.display_name()
	match spell.effect:
		"stabilize":
			if not who.sheet.is_down() or who.sheet.stable:
				return "%s isn't dying." % who.display_name()
		"mage_armor":
			var armor := who.sheet.equipped_def("armor")
			if armor != null and armor.is_body_armor():
				return "%s is wearing armour." % who.display_name()
	if not spell.heal.is_empty() and who.sheet.hp_current >= who.sheet.hp_max:
		return "%s isn't hurt." % who.display_name()
	return ""


## "Fire Bolt the wolf: 65% to hit, 1d10 fire" and the like.
static func _enemy_text(m: CombatManager, c: Combatant, spell: SpellDef, slot: int, who: Combatant) -> String:
	var dmg := Spellcasting.damage_expr(spell, c.sheet, slot)
	if not spell.attack.is_empty():
		var a := spell_attack(c, spell, slot)
		var adv := m.advantage(c, who, a)
		var chance := CombatRules.hit_chance_blessed(a.to_hit, who.armor_class(), adv["adv"]) if c.blessed_by != null \
				else CombatRules.hit_chance(a.to_hit, who.armor_class(), adv["adv"])
		var rays := int(Spellcasting.scaled(spell, "rays", slot))
		return "%s %s: %d%% to hit%s, %s %s" % [spell.display_name, who.display_name(), roundi(chance * 100.0),
				" (%d rays)" % rays if rays > 1 else "", dmg, spell.damage_type]
	if spell.darts > 0:
		var darts := int(Spellcasting.scaled(spell, "darts", slot))
		return "%s %s: %d darts, %s %s each, never miss" % [spell.display_name, who.display_name(), darts, dmg, spell.damage_type]
	if not spell.save.is_empty():
		return "%s %s: %s save against DC %d, or %s %s" % [spell.display_name, who.display_name(),
				Rules.ABILITY_NAMES.get(spell.save, spell.save), Spellcasting.save_dc(c.sheet), dmg, spell.damage_type]
	return "%s %s" % [spell.display_name, who.display_name()]


## A spell attack as an Attack, so it shares advantage and the attack roll.
static func spell_attack(c: Combatant, spell: SpellDef, slot: int) -> Attack:
	var a := Attack.new()
	a.name = spell.display_name
	a.to_hit = Spellcasting.attack_bonus(c.sheet)
	a.damage = Spellcasting.damage_expr(spell, c.sheet, slot)
	a.damage_type = spell.damage_type
	a.spell = true
	if spell.attack == "melee":
		a.reach = 1
	else:
		a.reach = 0
		a.range_normal = maxi(1, spell.range_hexes)
		a.range_long = a.range_normal
	return a


# --- casting -------------------------------------------------------------------------------

## Casts `spell` (check error() and preview() first): pays for it, then does
## what it does to `who` / around `h`.
static func cast(m: CombatManager, c: Combatant, spell: SpellDef, slot: int, h: Vector2i, who: Combatant,
		scroll_item: String = "") -> void:
	if spell.cast == "bonus":
		c.bonus_used = true
		c.cast_bonus_spell = true
	else:
		c.action_used = true
	if not spell.is_cantrip():
		c.cast_leveled_spell = true
	if not scroll_item.is_empty():
		c.sheet.inventory.remove_item(scroll_item, 1)
	elif not spell.is_cantrip():
		Spellcasting.spend_slot(c.sheet, slot)
	var how := ""
	if not scroll_item.is_empty():
		how = " from a scroll"
	elif slot > spell.level and not spell.is_cantrip():
		how = " with a %s-level slot" % SpellDef.ordinal(slot)
	if who != null and who != c:
		c.actor.face_towards(who.actor.position)
	elif h != c.hex():
		c.actor.face_towards(m.world.grid.hex_to_world(h))
	Audio.play_sfx("spell_cast")
	m.float_text(c, spell.display_name, Color(0.75, 0.85, 1.0), 15)
	var dc := Spellcasting.save_dc(c.sheet)
	if not spell.attack.is_empty():
		m.log_line("%s casts %s%s." % [c.display_name(), spell.display_name, how])
		for i in maxi(1, int(Spellcasting.scaled(spell, "rays", slot))):
			if who == null or who.is_out() or not m.in_fight(c):
				break
			await m.attack_with(c, who, spell_attack(c, spell, slot), false, false)
			if m.last_hit and spell.effect == "mark" and not who.is_out():
				who.marked_by = c
				who.mark_age = 0
				m.log_line("%s glows: the next attack against it has advantage." % who.display_name())
	elif spell.darts > 0 and who != null:
		var darts := int(Spellcasting.scaled(spell, "darts", slot))
		var total := 0
		for i in darts:
			total += Rules.roll_expr(spell.damage, m.rng)
		await m.pause(0.2)
		m.deal_damage(who, total, spell.damage_type, false,
				"%s casts %s%s: %d darts strike %s" % [c.display_name(), spell.display_name, how, darts, who.display_name()])
	elif not spell.save.is_empty() and not spell.damage.is_empty():
		var targets: Array[Combatant] = []
		if spell.target == "area":
			targets = combatants_in(m, area_hexes(m, c, spell, h))
			targets.erase(c)
		elif who != null:
			targets.append(who)
		m.log_line("%s casts %s%s." % [c.display_name(), spell.display_name, how])
		var rolled := Rules.roll_expr(Spellcasting.damage_expr(spell, c.sheet, slot), m.rng)
		await m.pause(0.2)
		for t in targets:
			if t.is_out():
				continue
			var sv := m.save_throw(t, spell.save, dc)
			var save_text := "%s save %d vs DC %d" % [Rules.ABILITY_NAMES.get(spell.save, spell.save), sv["total"], dc]
			if sv["success"] and not spell.half_on_save:
				m.log_line("%s avoids it (%s)." % [t.display_name(), save_text])
				m.float_text(t, "Saved", Color(0.85, 0.85, 0.85))
				continue
			var dmg := floori(rolled / 2.0) if sv["success"] else rolled
			m.deal_damage(t, dmg, spell.damage_type, false, "%s is caught (%s%s)" % [t.display_name(), save_text,
					", half" if sv["success"] else ""])
	else:
		await _cast_effect(m, c, spell, slot, h, who, how)
	m.state_changed.emit()


## Healing, buffs, Sleep, Bless, Aid, Misty Step.
static func _cast_effect(m: CombatManager, c: Combatant, spell: SpellDef, slot: int, h: Vector2i, who: Combatant,
		how: String) -> void:
	var head := "%s casts %s%s" % [c.display_name(), spell.display_name, how]
	match spell.effect:
		"sleep":
			var hexes := area_hexes(m, c, spell, h)
			var pool := Rules.roll_expr(str(Spellcasting.scaled(spell, "pool", slot)), m.rng)
			var victims := sleep_victims(m, hexes, h, pool)
			var names := PackedStringArray()
			for v in victims:
				v.asleep = true
				v.asleep_rounds = 10
				names.append(v.display_name())
				m.float_text(v, "Asleep", Color(0.7, 0.8, 1.0), 16)
			m.log_line("%s (%d hit points' worth): %s." % [head, pool,
					"%s falls asleep" % ", ".join(names) if not names.is_empty() else "nobody falls asleep"])
		"bless":
			var allies := nearby_allies(m, c, spell, slot)
			m.end_concentration(c)
			var names := PackedStringArray()
			for a in allies:
				a.blessed_by = c
				names.append(a.display_name())
				m.float_text(a, "Blessed", Color(1.0, 0.9, 0.5), 15)
			c.concentration = {"spell": spell.id, "targets": allies, "rounds": spell.rounds}
			m.log_line("%s: %s blessed (+1d4 to attacks and saves)." % [head, ", ".join(names)])
		"aid":
			var lines := PackedStringArray()
			for a in nearby_allies(m, c, spell, slot):
				lines.append(Spellcasting.apply_to_sheet(spell, c.sheet, a.sheet, slot, m.rng))
				m.float_text(a, "Aid", Color(0.6, 1.0, 0.6), 15)
			m.log_line("%s: %s" % [head, " ".join(lines)])
		"teleport":
			c.actor.place_at(h)
			c.actor.hex_entered.emit(c.actor, h)
			m.log_line("%s and steps through the mist." % head)
		_:
			var target := who if who != null else c
			var text := Spellcasting.apply_to_sheet(spell, c.sheet, target.sheet, slot, m.rng)
			m.log_line("%s: %s" % [head, text])
			if not spell.heal.is_empty():
				m.float_text(target, "Healed", Color(0.5, 1.0, 0.5), 16)
	await m.pause(0.2)
