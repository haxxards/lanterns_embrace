class_name CreatureSheet
extends CharacterSheet
## A hostile creature's sheet: a CharacterSheet filled from a CreatureDef, so
## combat code treats party members and monsters alike (hit points, armour
## class, abilities, saving throws, damage). Creatures have no gear: their
## armour class and attacks come from the stat block, and they die at 0 HP.

var def: CreatureDef


static func create(d: CreatureDef) -> CreatureSheet:
	var s := CreatureSheet.new()
	s.def = d
	s.id = d.id
	s.display_name = d.display_name
	s.character_class = "creature"
	s.abilities = d.abilities.duplicate()
	s.hp_max = d.hp
	s.hp_current = d.hp
	s.speed_ft = d.speed_ft
	s.proficiencies = {"saving_throws": d.raw.get("saving_throws", [])}
	for slot in ItemDef.EQUIP_SLOTS:
		s.equipment[slot] = null
	s.inventory = Inventory.new(1)
	s.animation_path = d.animation_path
	s.sprite_path = d.sprite_path
	s.raw = {"features": d.raw.get("traits", [])}
	s.recalculate()
	return s


func recalculate() -> void:
	armor_class = def.armor_class if def != null else 10


## Monsters don't make death saves: at 0 hit points they die.
func damage(amount: int, critical: bool = false) -> void:
	super.damage(amount, critical)
	if hp_current <= 0:
		dead = true


## Creatures add their proficiency only to the saves the stat block lists.
func saving_throw_bonus(ability: String) -> int:
	return ability_mod(ability) + (2 if (proficiencies.get("saving_throws", []) as Array).has(ability) else 0)
