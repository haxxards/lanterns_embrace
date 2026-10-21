# Combat

Fights are turn-based on the hex grid, following the 5e rules in a simplified form. The
code lives in `scripts/combat/`:

| File | Class | What it does |
|---|---|---|
| `combat_manager.gd` | **CombatManager** | The fight: initiative, the turn loop, movement, attacks, opportunity attacks, death saves, spells and features (targeting, conditions, concentration), victory, defeat and getting away, and saving and restoring a fight. A node under `World`. |
| `combat_spells.gd` | **CombatSpells** | Casting in a fight: what can be cast now, areas on the grid, the cursor preview, the effects (see [SPELLS.md](SPELLS.md)). |
| `combat_features.gd` | **CombatFeatures** | Second Wind, Action Surge, Cunning Action, Turn Undead, Preserve Life in a fight. |
| `combat_ai.gd` | **CombatAI** | How creatures take their turns. |
| `combat_rules.gd` | **CombatRules** | The arithmetic, with no positions or nodes: weapon attacks from a sheet, hit chances, attack and damage rolls, damage types, sneak attack, saves, initiative. |
| `combatant.gd` | **Combatant** | One participant's per-turn bookkeeping: movement left, action, bonus action, reaction, dodging, prone, and conditions from spells (asleep, turned, blessed, marked, Shield, concentration). |
| `attack.gd` | **Attack** | One way to attack: to-hit, damage dice, reach or range, ammunition. |
| `creature_def.gd`, `creature_sheet.gd` | **CreatureDef**, **CreatureSheet** | A stat block from `data/creatures/creatures.json`, and a live creature. A `CreatureSheet` *is* a `CharacterSheet`, so combat treats monsters and the party alike. |

On the map, a creature is a `Creature` node (`scripts/world/creature.gd`), an `Actor` like
the party members and townsfolk.

## How a fight starts

- A creature notices the party when a party member who is standing comes within its
  **aggro** range (in hexes) with a clear line of sight (`World.hostiles_noticing`). Its
  whole **encounter group** joins, plus anything else that has noticed the party.
- Clicking a creature also starts a fight.
- Everyone stops where they are, rolls **initiative** (d20 + Dex modifier) and acts in that
  order. Creatures that notice the fight later join at the start of the next round.

A fight can be saved on a party member's turn, between moves; loading carries on that turn
(see [SPELLS.md](SPELLS.md#saving-in-the-middle-of-a-fight)).

## A turn

| | |
|---|---|
| **Movement** | Up to your speed (30 ft = 6 hexes; difficult ground costs double). Click a hex in the shaded area; the path and cost are previewed. You can split movement around your action. |
| **Action** | **Attack** (click an enemy: if it is out of melee reach but you can walk next to it, you walk and then strike; a thrown weapon is thrown when you can't), **Dash** (double movement), **Dodge** (attacks against you have disadvantage until your next turn), **Disengage** (your movement provokes no opportunity attacks), **cast a spell** or **read a scroll** (the spell buttons in the combat bar), **Turn Undead** or **Preserve Life**, or **drink or give a potion** (to yourself or someone next to you, from the inventory screen). |
| **Bonus action** | An **off-hand attack** after attacking with a light melee weapon, if a light weapon is in the other hand (two-weapon fighting: no ability modifier on its damage). Click the enemy again. Or a bonus-action spell (Healing Word, Misty Step), **Second Wind**, or the rogue's **Cunning Action** (Dash or Disengage). |
| **Reaction** | An **opportunity attack**, made automatically when an enemy leaves your melee reach without disengaging. For a wizard, **Shield**, cast automatically when it would turn a hit into a miss. |
| **Free** | The fighter's **Action Surge**: one more action this turn. |
| **End turn** | Space, or the button. |

During a fight every combatant blocks the hex it stands on. Party members walk exactly hex
by hex, not with the free-walking smoothing used when exploring.

## Attacks

- **To hit:** d20 + bonus against the target's armour class. A natural 1 always misses, a
  natural 20 always hits and is a **critical hit** (the damage dice are rolled twice).
- **Party weapons:** the bonus is the ability modifier (Strength; Dexterity for ranged
  weapons; the better of the two for finesse weapons) plus proficiency if trained.
  Versatile weapons use the larger die when the other hand is empty. Bows use up arrows.
- **Advantage** (roll two d20s, keep the higher) for attacking someone **prone** from next
  to them, someone **unconscious** or **asleep**, someone marked by **Guiding Bolt**, and
  for a wolf's **Pack Tactics** (an ally next to the target). **Bless** adds 1d4 to the
  roll. **Disadvantage** (keep the lower) against someone **dodging**, against a
  prone target from range, at **long range**, and for a ranged attack with an enemy next
  to you. Both at once cancel out.
- **Damage types:** creatures can be vulnerable (double), resistant (half) or immune.
  Skeletons are vulnerable to bludgeoning (Odran's mace) and immune to poison.
- **Thrown weapons** (Wren's dagger: 20/60 ft): when the target can't be reached on foot
  this turn, the dagger is thrown instead. It leaves the hand and lands on the target's
  hex, to be picked up from the ground afterwards.
- **Sneak Attack** (Wren): once per turn, extra d6s (1d6 at levels 1–2) with a finesse or
  ranged weapon, when the attack has advantage or an ally is next to the target.
- **On-hit effects:** a wolf's bite knocks the target **prone** unless it makes a DC 11
  Strength save. Standing up costs half the movement at the start of the next turn.
- Hovering an enemy shows the attack and the chance to hit, with the reasons for any
  advantage or disadvantage, in the combat bar.

## Down, dying and dead

- At **0 hit points** a party member falls **unconscious**. On each of their turns they make
  a **death saving throw** (d20): 10 or more is a success, less a failure, a 1 counts as two
  failures and a 20 brings them round with 1 hit point. Three successes and they are
  **stable**; three failures and they **die**.
- A hit on someone who is down is a failed death save (a critical hit, two). A hit from next
  to them is always a critical hit.
- Damage that leaves as much again as their maximum after reaching 0 kills outright.
- **Any healing** wakes someone who is down. The dead need the temple (see
  [NPCS_AND_QUESTS.md](NPCS_AND_QUESTS.md)).
- Creatures simply die at 0 hit points.

## How it ends

- **Victory** when no enemy is left standing. The slain creatures' **XP** is shared equally
  by every party member who isn't dead (5e encounter XP), with level-ups as usual. Anyone
  still down becomes stable and stays down until healed.
- Slain creatures drop their **loot** on the ground (a pile, like dropped items) and stay
  dead: the map remembers them, in saves too. When a whole encounter group is dead,
  the condition `{"defeated": "<group>"}` becomes true, which quests use.
- **Defeat** when no party member is left standing: the game-over screen.
- **Getting away**: from the second round on, if no conscious enemy is within its aggro
  range + 2 hexes of a conscious party member, in sight, the party has escaped. The fight
  ends and the XP of anything slain so far is shared. Walk away (Disengage first, or
  accept the opportunity attacks); creatures that can't see you don't follow.

## Enemy AI

`CombatAI` keeps to a few readable rules:

- **Melee** creatures attack the most wounded enemy next to them; otherwise they walk to the
  cheapest hex from which they can strike (preferring the most wounded target, and for pack
  hunters a target an ally already stands next to), then attack. If nobody is in reach this
  turn, they Dash towards the nearest.
- **Ranged** creatures use their melee weapon on anyone next to them; otherwise they shoot
  the most wounded target in range and in sight, moving first to a spot in range and in
  sight (and not next to the party) if they need to.
- **Turned** undead Dash as far from the cleric as they can and don't attack. **Asleep**
  creatures' turns pass.

## Creatures: `data/creatures/creatures.json`

```json
"wolf": {
	"name": "Wolf", "ac": 13, "hp": 11, "hit_dice": "2d8+2", "speed_ft": 40,
	"abilities": {"str": 12, "dex": 15, "con": 12, "int": 3, "wis": 12, "cha": 6},
	"xp": 50, "traits": ["pack_tactics"],
	"attacks": [
		{"name": "Bite", "to_hit": 4, "damage": "2d4+2", "damage_type": "piercing", "reach_ft": 5,
		 "on_hit": {"save": "str", "dc": 11, "condition": "prone"}}
	],
	"ai": "melee", "aggro": 7,
	"animation": "res://assets/characters/wolf_anim.json"
}
```

| Key | Meaning |
|---|---|
| `ac`, `hp`, `speed_ft`, `abilities` | From the SRD stat block (`hp` is its average). |
| `xp` | Shared by the party when it is slain. |
| `attacks` | `to_hit` and `damage` as written in the stat block; `reach_ft` for melee, or `range_ft: [normal, long]` for ranged. `on_hit` adds a saving throw and a condition (only `prone` so far). |
| `traits` | `pack_tactics` so far. |
| `vulnerable`, `resistant`, `immune` | Damage type lists. |
| `ai` | `melee` or `ranged`. |
| `aggro` | Hexes within which it notices the party (in sight). |
| `animation` | A sprite sheet from `tools/art/blender/render_characters.py`. |
| `loot` | Items dropped when slain: `qty` is a number or dice, `chance` 0–1. A bandit's: `[{"item": "gold", "qty": "2d6"}, {"item": "dagger", "chance": 0.3}, ...]`. |

The five in the game are the SRD **wolf**, **bandit**, **skeleton**, and archer versions of
the bandit (with a shortbow instead of the SRD's light crossbow) and the skeleton.

**Placing them:** a map lists its creatures with an id (unique on the map, so the slain
are remembered), a type, a hex, an encounter group and how far they stroll:

```json
"creatures": [
	{"id": "wolf_1", "type": "wolf", "at": [13, 8], "group": "woods_wolves", "wander": 2}
]
```

## Where to fight

- **The north-west woods** near Millbrook, across the bridge: a pack of three wolves.
- **The Old Temple Road** (`data/maps/old_temple_road.json`, from the waymarker at the end
  of Millbrook's east road): four bandits camped where the road crosses a clearing,
  with their strongbox, and three skeletons among the ruined temple's walls on the hill,
  with an old chest and a carved stone.

## Testing

`tests/unit/test_combat_rules.gd` covers the arithmetic (weapon attacks, hit chances,
critical hits, damage types, death saves, creature sheets, movement range).
`tests/integration/test_combat.gd` fights on the real map with `combat.animate = false`, so
moves resolve at once: noticing, movement limits, attacking, Dash/Dodge/Disengage,
opportunity attacks, the AI, victory with XP and loot, death saves, potions, defeat, and the
road to the old temple. `tests/integration/test_spells.gd` covers spells, features,
scrolls, thrown weapons, getting away and saving mid-fight (see [SPELLS.md](SPELLS.md)).

## Spells and features

Spells, spell slots, scrolls, class features and resting are in [SPELLS.md](SPELLS.md).
