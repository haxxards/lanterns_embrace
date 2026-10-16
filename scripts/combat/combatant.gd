class_name Combatant
extends RefCounted
## Someone taking part in a fight: a party member or a creature, with the
## per-turn bookkeeping 5e needs (movement left, action, bonus action,
## reaction, and conditions such as dodging or prone).

const PARTY := "party"
const HOSTILE := "hostile"

var actor: Actor
var sheet: CharacterSheet
var team: String = PARTY
var initiative: int = 0
## Feet of movement left this turn.
var movement_left: float = 0.0
var action_used: bool = false
var bonus_used: bool = false
var reaction_used: bool = false
## Dodge: attacks against it have disadvantage until its next turn.
var dodging: bool = false
## Disengage: its movement provokes no opportunity attacks this turn.
var disengaged: bool = false
var prone: bool = false
var sneak_attack_used: bool = false
## Made a light-weapon attack with the main hand this turn (enables the off hand).
var attacked_light: bool = false


static func for_actor(a: Actor, s: CharacterSheet, side: String) -> Combatant:
	var c := Combatant.new()
	c.actor = a
	c.sheet = s
	c.team = side
	return c


func is_party() -> bool:
	return team == PARTY


func display_name() -> String:
	return sheet.display_name


func hex() -> Vector2i:
	return actor.hex


## Able to act: above 0 hit points.
func is_conscious() -> bool:
	return sheet.hp_current > 0


## Gone from the fight for good: a dead party member or a slain creature.
func is_out() -> bool:
	return sheet.dead


## Walking speed in feet this turn (armour and load penalties included).
func speed_ft() -> int:
	return sheet.effective_speed_ft()


func is_hostile_to(other: Combatant) -> bool:
	return team != other.team


func begin_turn() -> void:
	movement_left = float(speed_ft())
	action_used = false
	bonus_used = false
	reaction_used = false
	dodging = false
	disengaged = false
	sneak_attack_used = false
	attacked_light = false
	if prone and is_conscious():
		prone = false  # standing up costs half the movement
		movement_left -= speed_ft() / 2.0


## The attacks it can make: a creature's stat block, or a party member's
## main-hand weapon (or fists), plus the off hand for two-weapon fighting.
func attacks() -> Array[Attack]:
	if sheet is CreatureSheet:
		return (sheet as CreatureSheet).def.attacks()
	return CombatRules.weapon_attacks(sheet)


## The attack used for a normal Attack action against a target `distance`
## hexes away: the first that reaches, preferring melee up close.
func attack_for(distance: int) -> Attack:
	var best: Attack = null
	for a in attacks():
		if a.off_hand or not a.in_range(distance):
			continue
		if best == null or (distance <= 1 and not a.is_ranged() and best.is_ranged()):
			best = a
	return best


func off_hand_attack() -> Attack:
	for a in attacks():
		if a.off_hand:
			return a
	return null


func melee_attack() -> Attack:
	for a in attacks():
		if not a.is_ranged() and not a.off_hand:
			return a
	return null


func ranged_attack() -> Attack:
	for a in attacks():
		if a.is_ranged():
			return a
	return null
