class_name CombatFx
extends RefCounted
## How attacks and spells look in a fight. Purely visual: CombatManager rolls
## first, then plays the matching effect and applies the result when it lands.
##
## Every attack is three beats, grounded in the attacker's figure:
##   1. Wind-up: the attacker leans back (archers draw; casters gather a glow
##      at the staff or hand).
##   2. Release: a lunge forward with a swing smear from the shoulder, or a
##      projectile leaving the hand ("anchors" in the sprite sheet's JSON say
##      where hands, focus and body are in each facing).
##   3. Impact: on a hit a burst and a flash, and the target flinches away;
##      on a miss the target sidesteps (or the shot flies past).
##
## The look comes from the weapon, creature attack or spell (style_for); an
## "fx" block in the data overrides it:
##   items.json      "weapon": {..., "fx": {"swing": "slash"}}
##   creatures.json  "attacks": [{..., "fx": {"swing": "bite"}}]
##   spells.json     "fx": {"kind": "darts", "color": "#b49aff"}
## docs/COMBAT_FX.md describes each effect and how to add one. Nothing plays
## when CombatManager.animate is off (the tests), and every wait is a combat
## pause, so effects freeze with the game.

const DAMAGE_COLORS := {
	"fire": "#ff7a2a", "radiant": "#ffe08a", "force": "#b49aff", "cold": "#9fe0ff",
	"lightning": "#c8dcff", "thunder": "#c0c8ff", "necrotic": "#8ad08a", "acid": "#b0e040",
	"poison": "#80c040", "psychic": "#ff8ad8",
}
const STEEL := Color("e8eef5")
const SWING_STYLES := ["slash", "smash", "thrust", "punch", "bite", "claw"]
const ARROW_SPEED := 900.0
const THROW_SPEED := 620.0
const BOLT_SPEED := 720.0
const DART_SPEED := 560.0


## What `attack` looks like: {"kind": a SwingFx style, "arrow", "thrown" or
## "bolt"; "color": Color; "icon": the weapon's Texture2D or null; "size":
## swing radius in pixels; "hand": the anchor it leaves from}.
static func style_for(attack: Attack, attacker_is_party: bool = true) -> Dictionary:
	var fx: Dictionary = attack.fx.duplicate()
	if attack.weapon != null and attack.weapon.weapon.get("fx") is Dictionary:
		fx.merge(attack.weapon.weapon["fx"])
	var icon: Texture2D = attack.weapon.icon if attack.weapon != null else null
	if icon == null and not attack.spell:  # a creature's weapon with the same name as an item
		var same: ItemDef = Data.items.get(attack.name.to_lower())
		icon = same.icon if same != null else null
	var out := {"kind": "", "color": STEEL, "icon": icon, "size": 46.0,
			"hand": "weapon" if attacker_is_party else ("off" if attack.is_ranged() else "weapon")}
	if attack.spell:
		out["kind"] = str(fx.get("kind", "bolt"))
		out["color"] = Color(str(fx.get("color", DAMAGE_COLORS.get(attack.damage_type, "#ffffff"))))
		out["hand"] = "focus"
	elif attack.thrown_from != "":
		out["kind"] = "thrown"
		out["hand"] = "off" if attack.thrown_from == "off_hand" else "weapon"
	elif attack.is_ranged():
		out["kind"] = str(fx.get("kind", "arrow"))
	else:
		var kind := str(fx.get("swing", ""))
		if kind.is_empty():
			var lname := attack.name.to_lower()
			if attack.weapon == null and attacker_is_party:
				kind = "punch"
			elif lname.contains("bite"):
				kind = "bite"
			elif lname.contains("claw"):
				kind = "claw"
			else:
				kind = {"piercing": "thrust", "bludgeoning": "smash"}.get(attack.damage_type, "slash")
		out["kind"] = kind
		if attack.off_hand:
			out["hand"] = "off"
		if attack.weapon != null and attack.weapon.has_property("two_handed"):
			out["size"] = 56.0
		elif attack.light:
			out["size"] = 38.0
		if kind in ["bite", "claw"]:
			out["color"] = Color("f2e6d0")
	if fx.has("color") and not attack.spell:
		out["color"] = Color(str(fx["color"]))
	return out


## Plays `attack` from `attacker` at `target` and returns as it lands (the
## caller then applies the hit). `hit` and `crit` choose the impact.
static func play_attack(m: CombatManager, attacker: Combatant, target: Combatant, attack: Attack, hit: bool,
		crit: bool) -> void:
	if not _can_play(m, attacker, target):
		return
	var st := style_for(attack, attacker.is_party())
	match str(st["kind"]):
		"arrow", "thrown":
			await _shoot(m, attacker, target, st, hit, crit)
		"bolt":
			await _cast_bolt(m, attacker, target, st, hit, crit)
		_:
			await _strike(m, attacker, target, st, hit, crit)


## Magic Missile and the like: `count` darts from the caster's focus that fan
## out and converge on `target`. Returns, for each dart, the seconds from now
## until it lands (all 0 when nothing plays); the caller waits for each and
## applies its damage.
static func launch_darts(m: CombatManager, caster: Combatant, target: Combatant, count: int, spell: SpellDef) -> Array[float]:
	var arrivals: Array[float] = []
	if not _can_play(m, caster, target):
		for i in count:
			arrivals.append(0.0)
		return arrivals
	var color := Color(str(spell.fx.get("color", DAMAGE_COLORS.get(spell.damage_type, "#ffffff"))))
	var a := caster.actor
	var dir := _dir(a.anchor("focus"), target.actor.anchor("center"))
	a.nudge(-dir * 3.0 + Vector2(0, -3), 0.2, 0.3, Vector2(0.97, 1.04))  # rise, and settle as they fly
	BurstFx.spawn(m.world.fx, a.anchor("focus"), "charge", color, 1.0, 0.36)
	var from := a.anchor("focus")
	var to := target.actor.anchor("center")
	var flight := ProjectileFx.flight_time(from, to, DART_SPEED, 0.3)
	for i in count:
		var delay := 0.24 + i * 0.1
		var spread := (i - (count - 1) / 2.0) * 34.0 + randf_range(-8.0, 8.0)
		var aim := to + Vector2(randf_range(-5, 5), randf_range(-6, 6))
		ProjectileFx.spawn(m.world.fx, "dart", from, aim, color, null, flight, delay, 10.0, spread)
		arrivals.append(delay + flight)
	return arrivals


## A dart (or any spell effect without an attack roll) landing on `target`.
static func spell_impact(m: CombatManager, target: Combatant, color: Color, from: Vector2) -> void:
	if not m.animate or target == null or not is_instance_valid(target.actor):
		return
	BurstFx.spawn(m.world.fx, target.actor.anchor("center"), "hit", color, 0.8, 0.25)
	_flinch(target, _dir(from, target.actor.global_position), false, color)


# --- the three kinds of attack -------------------------------------------------------------

## Melee: lean back, lunge with a swing smear from the shoulder, impact.
static func _strike(m: CombatManager, attacker: Combatant, target: Combatant, st: Dictionary, hit: bool,
		crit: bool) -> void:
	var a := attacker.actor
	var kind := str(st["kind"])
	var hand := a.anchor(str(st["hand"]))
	var pivot := hand.lerp(a.anchor("head"), 0.45)  # about the shoulder
	var dir := _dir(pivot, target.actor.anchor("center"))
	var heavy := kind == "smash" or float(st["size"]) > 50.0
	a.nudge(-dir * (7.0 if heavy else 5.0) + (Vector2(0, -3) if kind == "smash" else Vector2.ZERO),
			0.16 if heavy else 0.12, 0.0, Vector2(1.04, 0.96))
	await m.pause(0.16 if heavy else 0.12)
	if not _can_play(m, attacker, target):
		return
	a.nudge(dir * 12.0, 0.07, 0.0, Vector2(0.97, 1.04))
	if kind in ["bite", "claw"]:
		SwingFx.spawn(m.world.fx, target.actor.anchor("center"), dir.angle(), kind, st["color"], null, 24.0, 0.18)
	else:
		SwingFx.spawn(m.world.fx, pivot + dir * 14.0, dir.angle(), kind, st["color"], st["icon"], float(st["size"]),
				0.2 if heavy else 0.17)
	await m.pause(0.1)
	if not _can_play(m, attacker, target):
		return
	_impact(m, attacker, target, st, hit, crit, kind == "smash")
	a.nudge(Vector2.ZERO, 0.22)
	await m.pause(0.12)


## Bows and thrown weapons: draw back, release, the shot flies, impact.
static func _shoot(m: CombatManager, attacker: Combatant, target: Combatant, st: Dictionary, hit: bool,
		crit: bool) -> void:
	var a := attacker.actor
	var thrown := str(st["kind"]) == "thrown"
	var from := a.anchor(str(st["hand"]))
	var to := target.actor.anchor("center")
	var dir := _dir(from, to)
	a.nudge(-dir * (6.0 if thrown else 4.0), 0.18, 0.0, Vector2(1.03, 0.97))
	await m.pause(0.18)
	if not _can_play(m, attacker, target):
		return
	var dest := to if hit else _miss_point(from, to)
	var speed := THROW_SPEED if thrown else ARROW_SPEED
	var flight := ProjectileFx.flight_time(from, dest, speed)
	var arc := from.distance_to(dest) * (0.22 if thrown else 0.1)
	ProjectileFx.spawn(m.world.fx, str(st["kind"]), from, dest, st["color"], st["icon"], flight, 0.0, arc)
	a.nudge(dir * 4.0, 0.06, 0.2)
	await m.pause(flight)
	if not _can_play(m, attacker, target):
		return
	if hit:
		_impact(m, attacker, target, st, true, crit, false)
	else:
		BurstFx.spawn(m.world.fx, dest + Vector2(0, 14), "dust", Color("b8a888"), 0.6, 0.35)
		_impact(m, attacker, target, st, false, false, false)


## Spell attacks (Fire Bolt, Guiding Bolt, Scorching Ray): a glow gathers at
## the focus, a bolt flies straight, a burst in the spell's colour.
static func _cast_bolt(m: CombatManager, attacker: Combatant, target: Combatant, st: Dictionary, hit: bool,
		crit: bool) -> void:
	var a := attacker.actor
	var from := a.anchor("focus")
	var to := target.actor.anchor("center")
	var dir := _dir(from, to)
	a.nudge(-dir * 3.0 + Vector2(0, -3), 0.2, 0.0, Vector2(0.97, 1.04))
	BurstFx.spawn(m.world.fx, from, "charge", st["color"], 1.0, 0.3)
	await m.pause(0.2)
	if not _can_play(m, attacker, target):
		return
	var dest := to if hit else _miss_point(from, to)
	var flight := ProjectileFx.flight_time(from, dest, BOLT_SPEED, 0.16)
	ProjectileFx.spawn(m.world.fx, "bolt", from, dest, st["color"], null, flight)
	a.nudge(Vector2.ZERO, 0.2)
	await m.pause(flight)
	if not _can_play(m, attacker, target):
		return
	_impact(m, attacker, target, st, hit, crit, false)


# --- helpers --------------------------------------------------------------------------

static func _can_play(m: CombatManager, a: Combatant, b: Combatant) -> bool:
	return m.animate and m.world != null and m.world.fx != null and m.in_fight(a) and m.in_fight(b) \
			and is_instance_valid(a.actor) and is_instance_valid(b.actor)


static func _dir(from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	return d.normalized() if d.length() > 0.5 else Vector2.RIGHT


## Where a missed shot ends: past the target and off to one side.
static func _miss_point(from: Vector2, to: Vector2) -> Vector2:
	var d := _dir(from, to)
	var side := Vector2(-d.y, d.x) * (22.0 if randf() < 0.5 else -22.0)
	return to + d * 46.0 + side


## The blow lands: a burst and a flash and a flinch, or a sidestep.
static func _impact(m: CombatManager, attacker: Combatant, target: Combatant, st: Dictionary, hit: bool, crit: bool,
		heavy: bool) -> void:
	var away := _dir(attacker.actor.global_position, target.actor.global_position)
	var t := target.actor
	if not hit:
		t.nudge(Vector2(-away.y, away.x) * 6.0, 0.08, 0.22)
		return
	var color: Color = st["color"] if str(st["kind"]) == "bolt" else Color("ffd9a0")
	BurstFx.spawn(m.world.fx, t.anchor("center"), "hit", color, 1.5 if crit else 1.0, 0.3 if crit else 0.24)
	if heavy:
		BurstFx.spawn(m.world.fx, t.global_position + Vector2(0, 2), "dust", Color("c8b898"), 1.2, 0.4)
	_flinch(target, away, crit, color)


static func _flinch(target: Combatant, away: Vector2, crit: bool, color: Color) -> void:
	var t := target.actor
	t.flash(Color(2.2, 1.6, 1.5) if crit else Color(1.8, 1.45, 1.35).lerp(color * 1.8, 0.25), 0.22)
	t.nudge(away * (8.0 if crit else 5.0), 0.06, 0.22, Vector2(1.03, 0.97))
