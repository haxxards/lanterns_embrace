class_name CombatRules
extends RefCounted
## The 5e arithmetic of a fight, with no nodes or positions: weapon attacks
## from a character sheet, attack rolls with advantage and disadvantage,
## critical hits, damage types, sneak attack, saving throws and initiative.
## CombatManager decides *when* each applies (it knows who stands where).


## The attacks a party member can make with what they hold: the main-hand
## weapon (or an unarmed strike), the off-hand weapon when both are light
## (two-weapon fighting, a bonus action), and throwing a weapon with the
## "thrown" property (a dagger) from either hand, as the Attack action.
static func weapon_attacks(sheet: CharacterSheet) -> Array[Attack]:
	var out: Array[Attack] = []
	var main := sheet.equipped_def("main_hand")
	var off := sheet.equipped_def("off_hand")
	if main == null or not main.is_weapon():
		var a := Attack.new()
		a.name = "Unarmed strike"
		a.to_hit = sheet.ability_mod("str") + sheet.proficiency_bonus()
		a.damage = str(maxi(1, 1 + sheet.ability_mod("str")))
		a.damage_type = "bludgeoning"
		out.append(a)
	else:
		out.append(_weapon_attack(sheet, main, false, off == null))
	if main != null and off != null and main.has_property("light") and off.is_weapon() and off.has_property("light"):
		out.append(_weapon_attack(sheet, off, true, false))
	for slot in ["main_hand", "off_hand"]:
		var w := sheet.equipped_def(slot)
		if w != null and w.is_weapon() and w.has_property("thrown") and w.weapon.has("range"):
			out.append(_thrown_attack(sheet, w, slot))
	return out


## Throwing `w` from `slot`: a ranged attack with the weapon's own numbers.
@warning_ignore("integer_division")
static func _thrown_attack(sheet: CharacterSheet, w: ItemDef, slot: String) -> Attack:
	var a := _weapon_attack(sheet, w, false, false)
	var feet := maxi(1, GameConfig.feet_per_hex)
	var r: Array = w.weapon["range"]
	a.name = "%s (thrown)" % w.display_name
	a.range_normal = maxi(1, int(r[0]) / feet)
	a.range_long = maxi(a.range_normal, int(r[1]) / feet)
	a.reach = 0
	a.light = false  # a throw doesn't set up an off-hand attack
	a.thrown_from = slot
	return a


@warning_ignore("integer_division")
static func _weapon_attack(sheet: CharacterSheet, w: ItemDef, off_hand: bool, both_hands: bool) -> Attack:
	var a := Attack.new()
	a.weapon = w
	a.name = w.display_name + (" (off hand)" if off_hand else "")
	var mod := sheet.ability_mod(Rules.weapon_ability(sheet, w))
	a.to_hit = mod + (sheet.proficiency_bonus() if sheet.is_proficient_with(w) else 0)
	var dice := str(w.weapon.get("damage", "1"))
	if both_hands and w.weapon.has("versatile"):
		dice = str(w.weapon["versatile"])
	# The off-hand attack adds no ability modifier to damage (unless negative).
	var dmg_mod := mod if (not off_hand or mod < 0) else 0
	a.damage = dice + (Rules.format_modifier(dmg_mod) if dmg_mod != 0 else "")
	a.damage_type = str(w.weapon.get("damage_type", ""))
	a.finesse = w.has_property("finesse")
	a.light = w.has_property("light")
	a.off_hand = off_hand
	if w.has_property("ammunition"):
		var feet := maxi(1, GameConfig.feet_per_hex)
		var r: Array = w.weapon.get("range", [80, 320])
		a.range_normal = maxi(1, int(r[0]) / feet)
		a.range_long = maxi(a.range_normal, int(r[1]) / feet)
		a.reach = 0
		a.ammo = str(w.weapon.get("ammo", ""))
	else:
		a.reach = 2 if w.has_property("reach") else 1
	return a


## Chance (0-1) that `to_hit` reaches armour class `ac`, with advantage (+1)
## or disadvantage (-1). A 1 always misses and a 20 always hits.
static func hit_chance(to_hit: int, ac: int, adv: int) -> float:
	var p := clampf((21.0 - float(ac - to_hit)) / 20.0, 0.05, 0.95)
	if adv > 0:
		return 1.0 - (1.0 - p) * (1.0 - p)
	if adv < 0:
		return p * p
	return p


## Rolls to hit: {d20, rolls, total, hit, crit}. Advantage rolls two d20 and
## keeps the higher, disadvantage the lower.
static func roll_attack(to_hit: int, ac: int, adv: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var rolls: Array[int] = [Rules.roll(1, 20, rng)]
	if adv != 0:
		rolls.append(Rules.roll(1, 20, rng))
	var d20: int = rolls.max() if adv > 0 else rolls.min()
	var total := d20 + to_hit
	var crit := d20 == 20
	var hit := crit or (d20 != 1 and total >= ac)
	return {"d20": d20, "rolls": rolls, "total": total, "hit": hit, "crit": crit}


## Rolls damage dice; a critical hit rolls the dice twice (not the modifier).
static func roll_damage(expr: String, crit: bool, rng: RandomNumberGenerator = null) -> int:
	var d := Rules.parse_dice(expr)
	if d.is_empty():
		return 0
	var count: int = d["count"] * (2 if crit else 1)
	return maxi(0, Rules.roll(count, d["sides"], rng) + int(d["bonus"]))


## Damage after the target's vulnerabilities, resistances and immunities.
static func adjust_for_type(sheet: CharacterSheet, amount: int, damage_type: String) -> int:
	if not sheet is CreatureSheet or damage_type.is_empty():
		return amount
	var def := (sheet as CreatureSheet).def
	if def.immune.has(damage_type):
		return 0
	if def.vulnerable.has(damage_type):
		return amount * 2
	if def.resistant.has(damage_type):
		return floori(amount / 2.0)
	return amount


## Rogue Sneak Attack dice for the character's level ("1d6" at levels 1-2).
@warning_ignore("integer_division")
static func sneak_attack_dice(sheet: CharacterSheet) -> String:
	return "%dd6" % ((sheet.level + 1) / 2)


static func has_feature(sheet: CharacterSheet, feature: String) -> bool:
	return (sheet.raw.get("features", []) as Array).has(feature)


## d20 + save bonus (+ `extra`, e.g. Bless's 1d4) against `dc`: {roll, total, success}.
static func saving_throw(sheet: CharacterSheet, ability: String, dc: int,
		rng: RandomNumberGenerator = null, extra: int = 0) -> Dictionary:
	var r := Rules.roll(1, 20, rng)
	var total := r + sheet.saving_throw_bonus(ability) + extra
	return {"roll": r, "total": total, "success": total >= dc}


## Chance (0-1) to hit with a Bless die (1d4) added to the roll.
static func hit_chance_blessed(to_hit: int, ac: int, adv: int) -> float:
	var p := 0.0
	for k in range(1, 5):
		p += hit_chance(to_hit + k, ac, adv)
	return p / 4.0


## d20 + Dexterity modifier.
static func initiative(sheet: CharacterSheet, rng: RandomNumberGenerator = null) -> int:
	return Rules.roll(1, 20, rng) + sheet.ability_mod("dex")
