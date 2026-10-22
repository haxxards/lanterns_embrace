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
## Who it is, for saves: "party:<character id>" or "creature:<spawn id>".
var key: String = ""
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

# Spells and features --------------------------------------------------------
## Asleep (Sleep): skips its turns and can't react; attacks against it have
## advantage, and hits from next to it are critical. Damage wakes it, and it
## wakes by itself after `asleep_rounds` of its turns.
var asleep: bool = false
var asleep_rounds: int = 0
## Turned (Turn Undead) by this cleric: it flees and doesn't attack, until it
## takes damage or `turned_rounds` of its turns have passed.
var turned_by: Combatant = null
var turned_rounds: int = 0
## Paralyzed (Hold Person) by this caster: can't move, act or react, fails
## Strength and Dexterity saves; attacks against it have advantage, and hits
## from within 5 ft are critical. At the end of each of its turns it repeats
## `held_save` against `held_dc` and breaks free on a success.
var held_by: Combatant = null
var held_save: String = ""
var held_dc: int = 0
var held_spell: String = ""
## Blessed (Bless) by this caster: +1d4 to attack rolls and saving throws.
var blessed_by: Combatant = null
## Shield: extra armour class until the start of its next turn.
var shield_ac: int = 0
## Guiding Bolt: the next attack against it has advantage. Lasts until the end
## of the marker's next turn (mark_age counts the marker's turns since).
var marked_by: Combatant = null
var mark_age: int = 0
## A concentration spell it keeps up: {"spell": id, "targets": [Combatant], "rounds": left}.
var concentration: Dictionary = {}
## Spells cast this turn (5e: after a bonus-action spell, any other spell
## this turn must be a cantrip; after a levelled spell, no bonus-action spell).
var cast_bonus_spell: bool = false
var cast_leveled_spell: bool = false


static func for_actor(a: Actor, s: CharacterSheet, side: String) -> Combatant:
	var c := Combatant.new()
	c.actor = a
	c.sheet = s
	c.team = side
	c.key = "creature:%s" % (a as Creature).spawn_id if a is Creature else "party:%s" % s.id
	return c


## Its state as plain data for a save (CombatManager.to_dict): the turn's
## bookkeeping and conditions, with other combatants named by key.
func to_dict() -> Dictionary:
	var d := {
		"key": key, "initiative": initiative, "movement_left": movement_left,
		"action_used": action_used, "bonus_used": bonus_used, "reaction_used": reaction_used,
		"dodging": dodging, "disengaged": disengaged, "prone": prone,
		"sneak_attack_used": sneak_attack_used, "attacked_light": attacked_light,
		"asleep": asleep, "asleep_rounds": asleep_rounds,
		"turned_by": turned_by.key if turned_by != null else "", "turned_rounds": turned_rounds,
		"blessed_by": blessed_by.key if blessed_by != null else "", "shield_ac": shield_ac,
		"held_by": held_by.key if held_by != null else "", "held_save": held_save, "held_dc": held_dc,
		"held_spell": held_spell,
		"marked_by": marked_by.key if marked_by != null else "", "mark_age": mark_age,
		"cast_bonus_spell": cast_bonus_spell, "cast_leveled_spell": cast_leveled_spell,
	}
	if not concentration.is_empty():
		var keys: Array = []
		for t in concentration.get("targets", []):
			keys.append((t as Combatant).key)
		d["concentration"] = {"spell": concentration["spell"], "targets": keys, "rounds": concentration["rounds"]}
	if actor != null and not is_party():
		d["hex"] = [actor.hex.x, actor.hex.y]
		d["hp"] = sheet.hp_current
	return d


## Restores what to_dict saved. `others` maps keys to the restored
## combatants, for the conditions that name someone (Bless, Turn Undead...).
func load_dict(d: Dictionary, others: Dictionary) -> void:
	initiative = int(d.get("initiative", 0))
	movement_left = float(d.get("movement_left", 0.0))
	action_used = bool(d.get("action_used", false))
	bonus_used = bool(d.get("bonus_used", false))
	reaction_used = bool(d.get("reaction_used", false))
	dodging = bool(d.get("dodging", false))
	disengaged = bool(d.get("disengaged", false))
	prone = bool(d.get("prone", false))
	sneak_attack_used = bool(d.get("sneak_attack_used", false))
	attacked_light = bool(d.get("attacked_light", false))
	asleep = bool(d.get("asleep", false))
	asleep_rounds = int(d.get("asleep_rounds", 0))
	turned_by = others.get(str(d.get("turned_by", "")))
	turned_rounds = int(d.get("turned_rounds", 0))
	blessed_by = others.get(str(d.get("blessed_by", "")))
	held_by = others.get(str(d.get("held_by", "")))
	held_save = str(d.get("held_save", ""))
	held_dc = int(d.get("held_dc", 0))
	held_spell = str(d.get("held_spell", ""))
	shield_ac = int(d.get("shield_ac", 0))
	marked_by = others.get(str(d.get("marked_by", "")))
	mark_age = int(d.get("mark_age", 0))
	cast_bonus_spell = bool(d.get("cast_bonus_spell", false))
	cast_leveled_spell = bool(d.get("cast_leveled_spell", false))
	concentration = {}
	var conc: Variant = d.get("concentration")
	if conc is Dictionary:
		var targets: Array[Combatant] = []
		for k in conc.get("targets", []):
			if others.has(str(k)):
				targets.append(others[str(k)])
		concentration = {"spell": str(conc.get("spell", "")), "targets": targets, "rounds": int(conc.get("rounds", 0))}


func is_party() -> bool:
	return team == PARTY


func display_name() -> String:
	return sheet.display_name


func hex() -> Vector2i:
	return actor.hex


## Above 0 hit points (asleep or not).
func is_conscious() -> bool:
	return sheet.hp_current > 0


## Able to take actions and reactions: conscious, awake and not held.
func can_act() -> bool:
	return is_conscious() and not asleep and held_by == null


func is_held() -> bool:
	return held_by != null


## Can't move or act, and so fails Strength and Dexterity saves: down, asleep or held.
func is_incapacitated() -> bool:
	return not is_conscious() or asleep or held_by != null


## Its conditions, for the interface: "asleep", "paralyzed", "prone", "blessed"...
func conditions() -> PackedStringArray:
	var out := PackedStringArray()
	if asleep:
		out.append("asleep")
	if held_by != null:
		out.append("paralyzed")
	if prone:
		out.append("prone")
	if turned_by != null:
		out.append("turned")
	if blessed_by != null:
		out.append("blessed")
	if marked_by != null:
		out.append("marked")
	if dodging:
		out.append("dodging")
	if not concentration.is_empty():
		out.append("concentrating")
	return out


## Armour class against an attack right now (Shield included).
func armor_class() -> int:
	return sheet.armor_class + shield_ac


## An undead creature (Sleep doesn't affect it; Turn Undead does).
func is_undead() -> bool:
	return CreatureTypes.type_of(sheet) == "undead"


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
	shield_ac = 0
	cast_bonus_spell = false
	cast_leveled_spell = false
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
## hexes away: the first that reaches, preferring melee up close (so a dagger
## is stabbed with next to the target and thrown from further away).
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
