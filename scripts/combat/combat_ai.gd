class_name CombatAI
extends RefCounted
## How hostile creatures fight. Simple, readable rules rather than search:
##
## melee ("ai": "melee")
##   - next to someone: hit the most wounded of them;
##   - otherwise walk to the cheapest hex next to a target (preferring the most
##     wounded, and for pack hunters a target an ally already stands next to),
##     then attack;
##   - nobody reachable this turn: Dash towards the nearest.
## ranged ("ai": "ranged")
##   - someone next to it: fight with its melee weapon;
##   - someone in normal range and in sight: shoot the most wounded;
##   - otherwise move to a hex in range and in sight (not next to the party),
##     then shoot; failing that, close in.


static func take_turn(m: CombatManager, c: Combatant) -> void:
	if m.conscious_enemies_of(c).is_empty() or not c.is_conscious():
		return
	var def := (c.sheet as CreatureSheet).def if c.sheet is CreatureSheet else null
	if def != null and def.ai == "ranged" and c.ranged_attack() != null:
		await _ranged_turn(m, c)
	else:
		await _melee_turn(m, c)


static func _melee_turn(m: CombatManager, c: Combatant) -> void:
	var melee := c.melee_attack()
	if melee == null:
		return
	var targets := m.conscious_enemies_of(c)
	var adjacent := _within(c.hex(), targets, melee.reach)
	if adjacent.is_empty():
		var plan := _best_approach(m, c, targets, melee.reach)
		if plan.is_empty():
			await _close_in(m, c, targets, true)
			return
		await m.move_along(c, c.actor.path_to(plan["hex"]))
		if not m.active or not c.is_conscious():
			return
		adjacent = _within(c.hex(), m.conscious_enemies_of(c), melee.reach)
	if adjacent.is_empty() or c.action_used:
		return
	await m.attack_with(c, _pick(m, c, adjacent), melee)


static func _ranged_turn(m: CombatManager, c: Combatant) -> void:
	var bow := c.ranged_attack()
	var melee := c.melee_attack()
	var targets := m.conscious_enemies_of(c)
	var adjacent := _within(c.hex(), targets, 1)
	if not adjacent.is_empty() and melee != null:
		await m.attack_with(c, _pick(m, c, adjacent), melee)
		return
	var shootable := _shootable(m, c.hex(), targets, bow.range_normal)
	if shootable.is_empty():
		var spot: Variant = _firing_position(m, c, targets, bow.range_normal)
		if spot == null:
			await _close_in(m, c, targets, false)
			return
		await m.move_along(c, c.actor.path_to(spot))
		if not m.active or not c.is_conscious():
			return
		shootable = _shootable(m, c.hex(), m.conscious_enemies_of(c), bow.range_normal)
		if shootable.is_empty():
			shootable = _shootable(m, c.hex(), m.conscious_enemies_of(c), bow.range_long)
	if shootable.is_empty() or c.action_used:
		return
	await m.attack_with(c, _pick(m, c, shootable), bow)


## Targets within `reach` hexes of `h`.
static func _within(h: Vector2i, targets: Array[Combatant], reach: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for t in targets:
		if Hex.distance(h, t.hex()) <= reach:
			out.append(t)
	return out


static func _shootable(m: CombatManager, h: Vector2i, targets: Array[Combatant], max_range: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for t in targets:
		if Hex.distance(h, t.hex()) <= max_range and m.world.line_of_sight(h, t.hex()):
			out.append(t)
	return out


## Who to hit: the most wounded, with pack hunters favouring a target an ally
## already flanks (advantage).
static func _pick(m: CombatManager, c: Combatant, options: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	var best_score := INF
	var pack := CombatRules.has_feature(c.sheet, "pack_tactics")
	for t in options:
		var score := float(t.sheet.hp_current)
		if pack and m._ally_next_to(t, c):
			score -= 100.0
		if score < best_score:
			best_score = score
			best = t
	return best


## The cheapest reachable hex (this turn) from which a target is in reach.
static func _best_approach(m: CombatManager, c: Combatant, targets: Array[Combatant], reach: int) -> Dictionary:
	var hexes := m.reachable_for(c)
	var best: Dictionary = {}
	var best_score := INF
	var pack := CombatRules.has_feature(c.sheet, "pack_tactics")
	for h in hexes:
		for t in targets:
			if Hex.distance(h, t.hex()) > reach:
				continue
			var score: float = hexes[h] + t.sheet.hp_current * 0.5
			if pack and m._ally_next_to(t, c):
				score -= 20.0
			if score < best_score:
				best_score = score
				best = {"hex": h, "target": t}
	return best


## A reachable hex (this turn) with a target in range and in sight, not next
## to any of them; the cheapest such. Null if none.
static func _firing_position(m: CombatManager, c: Combatant, targets: Array[Combatant], range_hexes: int) -> Variant:
	var hexes := m.reachable_for(c)
	var best: Variant = null
	var best_cost := INF
	for h in hexes:
		if hexes[h] >= best_cost or not _within(h, targets, 1).is_empty():
			continue
		if not _shootable(m, h, targets, range_hexes).is_empty():
			best = h
			best_cost = hexes[h]
	return best


## Heads for the nearest target, dashing if allowed and nothing else to do.
static func _close_in(m: CombatManager, c: Combatant, targets: Array[Combatant], dash: bool) -> void:
	var best_path: Array[Vector2i] = []
	var best_len := 1 << 30
	for t in targets:
		for n in Hex.neighbors(t.hex()):
			if not m.world.grid.is_walkable(n):
				continue
			var p := c.actor.path_to(n)
			if not p.is_empty() and p.size() < best_len:
				best_len = p.size()
				best_path = p
	if best_path.is_empty():
		return
	if dash:
		m.ai_dash(c)
	await m.move_along(c, best_path)
