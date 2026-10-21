class_name CharacterSheet
extends RefCounted
## A party member's character sheet, loaded from JSON (see docs/CHARACTER_SHEETS.md).
##
## The raw dictionary is kept so fields this version of the game does not use
## yet survive a load/save round trip; spells and features are read from it
## (raw["spells"], raw["features"]; see Spellcasting, Features, Classes).
## Equipment and the backpack are live objects (ItemStack / Inventory); armour
## class and speed are derived from them by recalculate().

## Emitted when equipment, backpack contents or hit points change.
signal changed

const SCHEMA_VERSION := 1

var id: String = ""
var display_name: String = ""
var ancestry: String = ""
var character_class: String = ""
var level: int = 1
var xp: int = 0
var abilities: Dictionary = {}
var hp_max: int = 1
var hp_current: int = 1
## At 0 hit points a character is unconscious ("down"). Three failed death
## saves, or one blow that leaves as much damage again as their maximum,
## kills them: then only a temple can raise them.
var dead: bool = false
## Down but no longer dying (three successful death saves, or the fight ended).
var stable: bool = false
var death_successes: int = 0
var death_failures: int = 0
## Derived from equipment (see Rules.armor_class); kept current by recalculate().
var armor_class: int = 10
## Base walking speed from the sheet; see effective_speed_ft() for penalties.
var speed_ft: int = 30
var proficiencies: Dictionary = {}
## Equipment slot (ItemDef.EQUIP_SLOTS) -> ItemStack, or null when empty.
var equipment: Dictionary = {}
var inventory: Inventory
## Gold the character brings along; moved into the party purse on joining.
var gold: int = 0
var portrait_path: String = ""
var sprite_path: String = ""
## Optional sprite-sheet description (facings x walk frames), see docs/ASSETS.md.
var animation_path: String = ""
## Pixel in the sprite that sits on the hex centre (the character's feet).
var sprite_origin: Variant = null
## Spell slots spent since the last long rest: {spell level: count}.
var slots_used: Dictionary = {}
## Uses of limited features spent since they last recharged: {feature id: count}.
var feature_uses: Dictionary = {}
## Hit dice spent on short rests (a character has one per level).
var hit_dice_used: int = 0
## Magic that lasts until a long rest or until used: {"mage_armor": true,
## "aid": 5, "guidance": true}.
var effects: Dictionary = {}
## What the last level-up brought (feature and spell names), for messages.
var level_up_gains: PackedStringArray = PackedStringArray()
var errors: PackedStringArray = PackedStringArray()
var source_path: String = ""
var raw: Dictionary = {}


static func from_dict(d: Dictionary, path: String = "") -> CharacterSheet:
	var s := CharacterSheet.new()
	s.raw = d.duplicate(true)
	s.source_path = path
	for key in ["id", "name", "class", "abilities", "hit_points"]:
		if not d.has(key):
			s.errors.append("missing required field '%s'" % key)
	if int(d.get("schema_version", SCHEMA_VERSION)) > SCHEMA_VERSION:
		s.errors.append("schema_version %s is newer than this game supports (%d)"
				% [d.get("schema_version"), SCHEMA_VERSION])
	s.id = str(d.get("id", path.get_file().get_basename()))
	s.display_name = str(d.get("name", s.id.capitalize()))
	s.ancestry = str(d.get("ancestry", "human"))
	s.character_class = str(d.get("class", "fighter"))
	s.level = clampi(int(d.get("level", 1)), 1, Rules.MAX_LEVEL)
	s.xp = maxi(0, int(d.get("xp", 0)))
	var abil: Dictionary = d.get("abilities", {})
	for ab in Rules.ABILITIES:
		var v := int(abil.get(ab, 10))
		if v < 1 or v > 30:
			s.errors.append("ability '%s' out of range: %d" % [ab, v])
		s.abilities[ab] = clampi(v, 1, 30)
	var hp: Dictionary = d.get("hit_points", {})
	s.hp_max = maxi(1, int(hp.get("max", 1)))
	s.hp_current = clampi(int(hp.get("current", s.hp_max)), 0, s.hp_max)
	s.dead = bool(d.get("dead", false))
	s.stable = bool(d.get("stable", s.hp_current == 0))
	var saves: Dictionary = d.get("death_saves", {})
	s.death_successes = int(saves.get("successes", 0))
	s.death_failures = int(saves.get("failures", 0))
	s.speed_ft = maxi(0, int(d.get("speed_ft", 30)))
	s.proficiencies = d.get("proficiencies", {})
	s.gold = maxi(0, int(d.get("gold", 0)))
	var eq: Dictionary = d.get("equipment", {}) if d.get("equipment") is Dictionary else {}
	for slot in ItemDef.EQUIP_SLOTS:
		s.equipment[slot] = ItemStack.from_variant(eq.get(slot))
	for slot in eq:
		if not ItemDef.EQUIP_SLOTS.has(str(slot)):
			s.errors.append("unknown equipment slot '%s'" % slot)
	s.inventory = Inventory.from_array(d.get("inventory", []), GameConfig.backpack_slots)
	s.inventory.changed.connect(s._on_items_changed)
	for stack in s.all_items():
		if not stack.is_valid():
			s.errors.append("unknown item '%s'" % stack.id)
	var used: Dictionary = d.get("slots_used", {}) if d.get("slots_used") is Dictionary else {}
	for k in used:
		s.slots_used[int(k)] = int(used[k])
	s.feature_uses = (d.get("feature_uses", {}) as Dictionary).duplicate() if d.get("feature_uses") is Dictionary else {}
	s.hit_dice_used = clampi(int(d.get("hit_dice_used", 0)), 0, s.level)
	s.effects = (d.get("effects", {}) as Dictionary).duplicate() if d.get("effects") is Dictionary else {}
	Classes.grant(s)  # catch up with the class table (features and spells by level)
	s.recalculate()
	var art: Dictionary = d.get("art", {})
	s.portrait_path = str(art.get("portrait", ""))
	s.sprite_path = str(art.get("sprite", ""))
	s.animation_path = str(art.get("animation", ""))
	if art.has("sprite_origin"):
		s.sprite_origin = JsonUtil.to_vec2(art["sprite_origin"])
	return s


static func load_file(path: String) -> CharacterSheet:
	var d: Variant = JsonUtil.load_json(path)
	if not d is Dictionary:
		var bad := CharacterSheet.new()
		bad.source_path = path
		bad.errors.append("could not parse JSON")
		return bad
	return from_dict(d, path)


## Serialises back to the JSON layout, keeping unknown fields intact.
func to_dict() -> Dictionary:
	var d := raw.duplicate(true)
	d["schema_version"] = SCHEMA_VERSION
	d["id"] = id
	d["name"] = display_name
	d["ancestry"] = ancestry
	d["class"] = character_class
	d["level"] = level
	d["xp"] = xp
	d["abilities"] = abilities.duplicate()
	d["hit_points"] = {"max": hp_max, "current": hp_current}
	d["dead"] = dead
	d["stable"] = stable
	d["death_saves"] = {"successes": death_successes, "failures": death_failures}
	d["armor_class"] = armor_class
	d["speed_ft"] = speed_ft
	d["gold"] = gold
	var eq := {}
	for slot in ItemDef.EQUIP_SLOTS:
		var st: ItemStack = equipment.get(slot)
		eq[slot] = (st.id if st.qty == 1 else st.to_variant()) if st != null else null
	d["equipment"] = eq
	d["inventory"] = inventory.to_array()
	var used := {}
	for k in slots_used:
		if int(slots_used[k]) > 0:
			used[str(k)] = int(slots_used[k])
	d["slots_used"] = used
	d["feature_uses"] = feature_uses.duplicate()
	d["hit_dice_used"] = hit_dice_used
	d["effects"] = effects.duplicate()
	return d


func is_valid() -> bool:
	return errors.is_empty()


func ability_mod(ability: String) -> int:
	return Rules.ability_modifier(int(abilities.get(ability, 10)))


func proficiency_bonus() -> int:
	return Rules.proficiency_bonus(level)


func has_feature(feature_id: String) -> bool:
	return (raw.get("features", []) as Array).has(feature_id)


## Hit dice not yet spent (one per level; a long rest returns half).
func hit_dice_left() -> int:
	return maxi(0, level - hit_dice_used)


## Conscious: above 0 hit points.
func is_alive() -> bool:
	return hp_current > 0


func is_dead() -> bool:
	return dead


## Unconscious at 0 hit points, but not dead.
func is_down() -> bool:
	return hp_current <= 0 and not dead


## Bonus to a saving throw: the ability modifier, plus proficiency for the
## saves the class is proficient in.
func saving_throw_bonus(ability: String) -> int:
	var prof := (proficiencies.get("saving_throws", []) as Array).has(ability)
	return ability_mod(ability) + (proficiency_bonus() if prof else 0)


## Combat movement per turn, in hexes.
@warning_ignore("integer_division")
func speed_hexes(feet_per_hex: int) -> int:
	return speed_ft / maxi(1, feet_per_hex)


# --- equipment & items -----------------------------------------------------------

func equipped(slot: String) -> ItemStack:
	return equipment.get(slot)


## The ItemDef in `slot`, or null.
func equipped_def(slot: String) -> ItemDef:
	var st: ItemStack = equipment.get(slot)
	return st.def if st != null else null


## Every stack the character carries, worn or in the backpack.
func all_items() -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for slot in ItemDef.EQUIP_SLOTS:
		if equipment.get(slot) != null:
			out.append(equipment[slot])
	for st in inventory.slots:
		if st != null:
			out.append(st)
	return out


func has_item(item_id: String) -> bool:
	for st in all_items():
		if st.id == item_id:
			return true
	return false


func is_proficient_with(def: ItemDef) -> bool:
	if def == null:
		return false
	if def.is_weapon():
		var list: Array = proficiencies.get("weapons", [])
		return list.has(def.id) or list.has(str(def.weapon.get("category", "")))
	if def.is_shield():
		return (proficiencies.get("armor", []) as Array).has("shields")
	if def.is_body_armor():
		return (proficiencies.get("armor", []) as Array).has(str(def.armor.get("type", "")))
	return true


## Why `stack` can't go in `slot` right now, or "" if it can. Simplified 5e:
## armour and shields need proficiency, two-handed weapons need both hands,
## and only light weapons can be paired for two-weapon fighting.
func can_equip(slot: String, stack: ItemStack) -> String:
	if stack == null:
		return ""
	var def := stack.def
	if def == null or not def.fits_slot(slot):
		return "%s can't be worn there." % stack.display_name()
	if (def.is_body_armor() or def.is_shield()) and not is_proficient_with(def):
		var what := "shields" if def.is_shield() else "%s armour" % def.armor.get("type", "")
		return "%s isn't trained to use %s." % [display_name, what]
	var main := equipped_def("main_hand") if slot != "main_hand" else null
	var off := equipped_def("off_hand") if slot != "off_hand" else null
	if slot == "off_hand":
		if main != null and main.has_property("two_handed"):
			return "The %s needs both hands." % main.display_name
		if def.is_weapon():
			if not def.has_property("light"):
				return "Only a light weapon can be held in the off hand."
			if main != null and not main.has_property("light"):
				return "Fighting with two weapons needs a light weapon in the main hand too."
	if slot == "main_hand" and def.has_property("two_handed") and off != null:
		return "Free the off hand first: the %s needs both hands." % def.display_name
	if slot == "main_hand" and off != null and off.is_weapon() and not def.has_property("light"):
		return "With a weapon in the off hand, the main-hand weapon must be light."
	return ""


## Puts `stack` in `slot` (call can_equip first) and returns what was there.
func equip(slot: String, stack: ItemStack) -> ItemStack:
	var old: ItemStack = equipment.get(slot)
	equipment[slot] = stack
	_on_items_changed()
	return old


func unequip(slot: String) -> ItemStack:
	return equip(slot, null)


func recalculate() -> void:
	armor_class = Rules.armor_class(self)


func carried_weight() -> float:
	var w := 0.0
	for st in all_items():
		w += st.weight()
	return w


func carrying_capacity() -> float:
	return Rules.carrying_capacity(int(abilities.get("str", 10)))


func is_overloaded() -> bool:
	return carried_weight() > carrying_capacity()


## Walking speed after armour and load penalties (5e: heavy armour without
## the Strength for it costs 10 ft; here, carrying more than the capacity
## halves speed).
@warning_ignore("integer_division")
func effective_speed_ft() -> int:
	var speed := speed_ft
	var armor := equipped_def("armor")
	if armor != null and int(abilities.get("str", 10)) < int(armor.armor.get("strength", 0)):
		speed -= 10
	if is_overloaded():
		speed = speed / 2
	return maxi(0, speed)


## Adds experience; levels up when a threshold is crossed: more hit points, a
## hit die, and whatever the class table grants at the new level (features,
## spells, spell slots; see Classes). Returns how many levels were gained;
## level_up_gains names what came with them.
@warning_ignore("integer_division")
func add_xp(amount: int) -> int:
	xp = maxi(0, xp + amount)
	var gained := 0
	level_up_gains = PackedStringArray()
	while level < Rules.MAX_LEVEL and xp >= Rules.XP_THRESHOLDS[level]:
		level += 1
		gained += 1
		# 5e fixed hit points per level: half the hit die + 1, plus Con.
		var hp := maxi(1, Classes.hit_die(self) / 2 + 1 + ability_mod("con"))
		hp_max += hp
		if is_alive():
			hp_current += hp
		level_up_gains.append_array(Classes.grant(self))
		var slots := Spellcasting.slots_text(self)
		if not slots.is_empty() and Spellcasting.is_caster(self):
			level_up_gains.append("spell slots %s" % slots)
	recalculate()
	changed.emit()
	return gained


## "Elowen reaches level 2! New: Mage Armor, spell slots 1st 3/3."
func level_up_message() -> String:
	var msg := "%s reaches level %d!" % [display_name, level]
	if not level_up_gains.is_empty():
		msg += " New: %s." % ", ".join(level_up_gains)
	return msg


## Takes damage (never below 0). At 0 hit points a character is down. Damage
## that leaves as much again as the maximum kills outright (5e massive damage),
## and any hit on someone already down is a failed death save (two for a
## critical hit).
func damage(amount: int, critical: bool = false) -> void:
	if dead or amount <= 0:
		return
	if hp_current <= 0:
		add_death_failures(2 if critical else 1)
		return
	var overflow := amount - hp_current
	hp_current = maxi(0, hp_current - amount)
	if hp_current == 0:
		stable = false
		death_successes = 0
		death_failures = 0
		if overflow >= hp_max:
			dead = true
	changed.emit()


## Restores up to `amount` hit points; returns how many were restored. Wakes
## someone who is down; does nothing for the dead.
func heal(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var before := hp_current
	hp_current = clampi(hp_current + amount, 0, hp_max)
	if hp_current != before:
		if before <= 0:
			_clear_death_saves()
		changed.emit()
	return hp_current - before


## Brought back from the dead (a temple's raise dead) with `hp` hit points.
func revive(hp: int = 1) -> void:
	dead = false
	_clear_death_saves()
	hp_current = clampi(hp, 1, hp_max)
	changed.emit()


func die() -> void:
	hp_current = 0
	dead = true
	changed.emit()


func add_death_failures(n: int) -> void:
	death_failures = mini(3, death_failures + n)
	stable = false
	if death_failures >= 3:
		dead = true
	changed.emit()


## One death saving throw (d20, no modifiers): 10 or more succeeds, a 1 counts
## as two failures, and a 20 brings the character round with 1 hit point.
## Three successes and they are stable. Returns what happened.
func roll_death_save(rng: RandomNumberGenerator = null) -> String:
	var d := Rules.roll(1, 20, rng)
	if d == 20:
		heal(1)
		return "rallies"
	if d == 1:
		add_death_failures(2)
	elif d < 10:
		add_death_failures(1)
	else:
		death_successes += 1
		if death_successes >= 3:
			stable = true
		changed.emit()
	if dead:
		return "dies"
	if stable:
		return "stable"
	return "success" if d >= 10 else "failure"


func _clear_death_saves() -> void:
	stable = false
	death_successes = 0
	death_failures = 0


## Weapon attack bonus and damage with the main-hand weapon (or unarmed).
func attack_summary() -> String:
	var w := equipped_def("main_hand")
	if w == null:
		return "Unarmed  %s to hit, 1 + Str damage" % Rules.format_modifier(
				ability_mod("str") + proficiency_bonus())
	var ability := Rules.weapon_ability(self, w)
	var bonus := ability_mod(ability) + (proficiency_bonus() if is_proficient_with(w) else 0)
	var dmg := "%s%s" % [w.weapon.get("damage", "1"), Rules.format_modifier(ability_mod(ability))]
	return "%s  %s to hit, %s %s" % [w.display_name, Rules.format_modifier(bonus), dmg,
			w.weapon.get("damage_type", "")]


func _on_items_changed() -> void:
	recalculate()
	changed.emit()


func summary() -> String:
	return "Level %d %s %s" % [level, ancestry.capitalize(), character_class.capitalize()]
