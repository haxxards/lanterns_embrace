class_name CombatFeatures
extends RefCounted
## Using class features in a fight: Second Wind, Action Surge, Cunning
## Action (Dash or Disengage as a bonus action), Turn Undead and Preserve
## Life. Their uses and recharges are Features'; definitions are in
## data/classes/classes.json.
##
## Cunning Action shows as two abilities, "cunning_dash" and
## "cunning_disengage", both granted by the "cunning_action" feature.

const CUNNING := ["cunning_dash", "cunning_disengage"]


## The feature an ability id belongs to ("cunning_dash" -> "cunning_action").
static func feature_of(ability_id: String) -> String:
	return "cunning_action" if CUNNING.has(ability_id) else ability_id


## Ability ids `c` has from its features, for the combat bar.
static func abilities(c: Combatant) -> Array[String]:
	var out: Array[String] = []
	for f in Features.usable(c.sheet):
		out.append(f)
	if c.sheet.has_feature("cunning_action"):
		out.append_array(CUNNING)
	return out


static func display_name(ability_id: String) -> String:
	match ability_id:
		"cunning_dash":
			return "Dash (bonus)"
		"cunning_disengage":
			return "Disengage (bonus)"
	return Classes.feature_name(ability_id)


static func cost(ability_id: String) -> String:
	if CUNNING.has(ability_id):
		return "bonus"
	return str(Classes.feature(ability_id).get("cost", "action"))


static func tooltip(c: Combatant, ability_id: String) -> String:
	var f := Classes.feature(feature_of(ability_id))
	var text := str(f.get("description", ""))
	var uses := Features.uses_text(c.sheet, ability_id)
	return text + ("\nUses: %s" % uses if not uses.is_empty() else "")


## Why `c` can't use the ability now ("" if it can).
static func error(m: CombatManager, c: Combatant, ability_id: String) -> String:
	if not c.can_act():
		return "%s can't act." % c.display_name()
	match cost(ability_id):
		"action":
			if c.action_used:
				return "%s has already used their action." % c.display_name()
		"bonus":
			if c.bonus_used:
				return "%s has already used their bonus action." % c.display_name()
	if Features.max_uses(c.sheet, ability_id) > 0 and Features.uses_left(c.sheet, ability_id) <= 0:
		return "%s is used up: it comes back after a %s rest." % [display_name(ability_id),
				str(Classes.feature(Features.pool(ability_id)).get("recharge", "long"))]
	match ability_id:
		"second_wind":
			if c.sheet.hp_current >= c.sheet.hp_max:
				return "%s isn't hurt." % c.display_name()
		"action_surge":
			if not c.action_used:
				return "Use your action first; Action Surge gives you another."
		"turn_undead":
			if _undead_in_range(m, c).is_empty():
				return "No undead within %d ft." % (_range(ability_id) * GameConfig.feet_per_hex)
		"preserve_life":
			if _preserve_targets(m, c).is_empty():
				return "Nobody within %d ft is below half their hit points." % (_range(ability_id) * GameConfig.feet_per_hex)
	return ""


## Reach in hexes.
@warning_ignore("integer_division")
static func _range(ability_id: String) -> int:
	return int(Classes.feature(ability_id).get("range_ft", 30)) / maxi(1, GameConfig.feet_per_hex)


static func _undead_in_range(m: CombatManager, c: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var reach := _range("turn_undead")
	for o in m.conscious_enemies_of(c):
		if o.is_undead() and o.turned_by == null and m.distance(o, c) <= reach \
				and m.world.line_of_sight(c.hex(), o.hex()):
			out.append(o)
	return out


static func _preserve_targets(m: CombatManager, c: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var reach := _range("preserve_life")
	for o in m.combatants:
		if o.team == c.team and not o.is_out() and m.distance(o, c) <= reach \
				and o.sheet.hp_current * 2 < o.sheet.hp_max:
			out.append(o)
	return out


## Uses the ability (check error() first).
static func use(m: CombatManager, c: Combatant, ability_id: String) -> void:
	var feature_id := feature_of(ability_id)
	match cost(ability_id):
		"action":
			c.action_used = true
		"bonus":
			c.bonus_used = true
	if Features.max_uses(c.sheet, ability_id) > 0:
		Features.spend(c.sheet, ability_id)
	var name := display_name(ability_id)
	match ability_id:
		"second_wind":
			var amount := Rules.roll_expr(str(Classes.feature(feature_id).get("heal", "1d10")), m.rng) + c.sheet.level
			var healed := c.sheet.heal(amount)
			m.log_line("%s uses Second Wind and recovers %d hit points." % [c.display_name(), healed])
			m.float_text(c, "+%d" % healed, Color(0.5, 1.0, 0.5))
			Audio.play_sfx("potion")
		"action_surge":
			c.action_used = false
			c.attacked_light = false
			m.log_line("%s surges into action: another action this turn." % c.display_name())
			m.float_text(c, name, Color(1.0, 0.85, 0.4), 15)
		"cunning_dash":
			c.movement_left += c.speed_ft()
			m.log_line("%s dashes (Cunning Action)." % c.display_name())
		"cunning_disengage":
			c.disengaged = true
			m.log_line("%s disengages (Cunning Action)." % c.display_name())
		"turn_undead":
			var dc := Spellcasting.save_dc(c.sheet)
			m.log_line("%s presents the holy symbol: Turn Undead!" % c.display_name())
			m.float_text(c, name, Color(1.0, 0.9, 0.5), 15)
			Audio.play_sfx("spell_cast")
			for u in _undead_in_range(m, c):
				var sv := m.save_throw(u, "wis", dc)
				if sv["success"]:
					m.log_line("%s resists (Wisdom save %d vs DC %d)." % [u.display_name(), sv["total"], dc])
					continue
				u.turned_by = c
				u.turned_rounds = 10
				m.log_line("%s is turned and flees (Wisdom save %d vs DC %d)." % [u.display_name(), sv["total"], dc])
				m.float_text(u, "Turned", Color(1.0, 0.9, 0.5), 15)
		"preserve_life":
			var pool := 5 * c.sheet.level
			var lines := PackedStringArray()
			var targets := _preserve_targets(m, c)
			targets.sort_custom(func(a: Combatant, b: Combatant) -> bool:
				return a.sheet.hp_current * b.sheet.hp_max < b.sheet.hp_current * a.sheet.hp_max)
			for t in targets:
				var room := floori(t.sheet.hp_max / 2.0) - t.sheet.hp_current
				var give := mini(pool, room)
				if give <= 0:
					continue
				pool -= give
				t.sheet.heal(give)
				lines.append("%s +%d" % [t.display_name(), give])
				m.float_text(t, "+%d" % give, Color(0.5, 1.0, 0.5))
			m.log_line("%s channels Preserve Life: %s." % [c.display_name(), ", ".join(lines)])
			Audio.play_sfx("potion")
	m.state_changed.emit()
