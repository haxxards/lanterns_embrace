# Items, inventory and containers

Items are defined once in [`data/items/items.json`](../data/items/items.json). Characters,
containers and saves only ever store **stacks**: an item id and a quantity,
`{"item": "potion_of_healing", "qty": 2}`.

## Item fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | Display name. |
| `kind` | string | `weapon`, `ammo`, `armor`, `shield`, `helmet`, `cloak`, `ring`, `amulet`, `boots`, `gloves`, `potion`, `food`, `gear`, `tool`, `book`, `gem`, `key`, `currency`. Mostly descriptive. |
| `slot` | string | Equipment slot it can be worn in: `helmet`, `amulet`, `armor`, `cloak`, `gloves`, `main_hand`, `off_hand`, `boots`, or `ring` (either ring slot). Leave out for items that can't be worn. Any weapon may be tried in the off hand. |
| `icon` | string | 64×64 PNG of the classic icon (see [ASSETS.md](ASSETS.md)). The painted icon, if there is one, has the same file name in `assets/items/painted/` and is used instead when `"art_style"` says so ([PAINTED_STYLE.md](PAINTED_STYLE.md)). |
| `weight` | number | Pounds. |
| `value` | number | Gold pieces (0.1 = 1 sp, 0.01 = 1 cp). |
| `stack` | int | Maximum stack size (default 1). |
| `description` | string | Shown in the tooltip. |
| `magic` | bool | Draws a blue frame in the inventory. |
| `weapon` | object | `category` (`simple`/`martial`), `damage` (dice, e.g. `"1d8"`), `damage_type`, optional `versatile` dice, `properties` (`finesse`, `light`, `thrown`, `two_handed`, `ammunition`), `range` `[normal, long]` in feet, `ammo` item id, and `bonus` for a magic weapon (`1` on a +1 Longsword: +1 to attack and damage rolls, off-hand and thrown attacks included). |
| `armor` | object | Body armour: `type` (`light`/`medium`/`heavy`), `base_ac`, `dex_cap` (medium), `strength` (heavy: below it, speed −10 ft), `stealth_disadvantage`. Shields: `type: "shield"`, `ac_bonus`. |
| `bonuses` | object | Passive bonuses while worn (in any equipment slot); see [Passive bonuses](#passive-bonuses-magic-items). |
| `use` | object | What using it does: `{"heal": "2d4+2"}` (potions, food); `{"buff": {"abilities": {"str": 21}}}`, a score raised until the next long rest (Potion of Hill Giant Strength); `{"throw": {...}}`, a flask thrown in a fight (Holy Water, [below](#flasks-thrown-in-a-fight)); or `{"cast": "<spell id>"}` for a spell scroll (kind `scroll`): read by anyone whose class has the spell, cast at the spell's level with no slot, used up. See [SPELLS.md](SPELLS.md#spell-scrolls). |
| `tool` | string | `lockpick` lets the holder try locks. |

The special item `gold` (kind `currency`) represents coins in containers. Picking it up
adds to the party's shared purse instead of filling a backpack slot.

## Rules that use items (simplified 5e)

All in `scripts/rules/rules.gd` and `scripts/rules/character_sheet.gd`:

- **Armour class:** 10 + Dex unarmoured; with armour, `base_ac` + Dex (light), + Dex up to
  `dex_cap` (medium), or just `base_ac` (heavy). A shield adds its `ac_bonus`; worn items
  add `bonuses.ac`. AC is recalculated whenever equipment changes, so the sheet's
  `armor_class` is derived, not entered.
- **Equipping:** armour and shields need the matching proficiency
  (`proficiencies.armor`: `light`, `medium`, `heavy`, `shields`). Two-handed weapons need
  the off hand free. Only a `light` weapon goes in the off hand, and then the main-hand
  weapon must be light too (two-weapon fighting). Weapons without proficiency can be
  wielded; the attack line simply leaves out the proficiency bonus.
- **Carrying:** capacity is Strength × 15 lb. Going over it halves walking speed.
- **Ability scores:** everything a score decides (modifiers, attacks, saves, carrying,
  the Strength that heavy armour asks for) reads `CharacterSheet.ability_score()`, which
  applies worn items and potions that raise a score. The sheet's own `abilities` stay as
  written.
- **Locks:** a container can be `locked`. A `key` item anywhere in the party opens it.
  Otherwise someone carrying a `lockpick` tool rolls d20 + Dex (+ proficiency with
  `"tools": ["thieves_tools"]`) against `lock_dc` each time they try.

## Passive bonuses (magic items)

`bonuses` on an item applies while it is in any equipment slot. Several worn items add up
(two Rings of Protection give +2), except scores and speed, where the best one counts.

| Key | Example | Effect |
|---|---|---|
| `ac` | `{"ac": 1}` | + to armour class (Rules.armor_class). |
| `saves` | `{"saves": 1}` | + to every saving throw, and to death saves (a natural 1 and 20 still count as rolled). |
| `abilities` | `{"abilities": {"str": 19}}` | The score becomes at least this while worn (5e Gauntlets of Ogre Power, Amulet of Health). A higher score is kept. |
| `speed_ft` | `{"speed_ft": 30}` | Walking speed at least this, and heavy armour or a heavy load no longer slow the wearer (Boots of Striding and Springing). |
| `resist` | `{"resist": ["fire"]}` | Half damage of these types, rounded down (CombatRules.adjust_for_type, which also handles creatures' resistances). |

A raised **Constitution** raises maximum hit points by the new modifier's gain at every
level, as in 5e: an Amulet of Health on a level 3 wizard with Con 13 adds 9. Putting it on
doesn't heal; rest fills the new hit points. Taking it off lowers current hit points only
as far as the new maximum. Saves store the sheet's own maximum (`con_hp` is added back
when the sheet loads with the amulet on).

The item card lists each bonus (`ItemDef.bonus_lines()`), and the inventory's stats panel
shows all six scores, raised ones in blue, with any save bonus and resistances under them.

The magic items so far:

| Item | Bonus | Where |
|---|---|---|
| Ring of Protection | +1 AC, +1 saves | Reeve's strongbox (Millbrook) |
| Cloak of Protection | +1 AC, +1 saves | Traveller's chest at the inn |
| Boots of Striding and Springing | speed at least 30 ft, never slowed | Traveller's chest at the inn |
| Ring of Fire Resistance | resist fire | Wenna's shop |
| Gauntlets of Ogre Power | Str 19 | Bandits' strongbox (old temple road) |
| +1 Longsword | +1 to hit and damage | Mouldering chest in the ruin |
| Amulet of Health | Con 19 | Mouldering chest in the ruin |

## Unidentified magic items

Worn magic and magic weapons found in a chest, a drawer or on a body start **unidentified**
(`ItemDef.starts_unidentified()`: `magic`, and not a potion or scroll, which are known on
sight). A map placement can say `{"item": "...", "identified": true}` to skip that, and
shop stock is always known.

- The stack shows as "Unidentified ring" (or weapon, amulet, boots...) with a blue **?** in
  its corner. Its card shows only what anyone can see (a weapon's damage) and "Value
  unknown". The attack line and the fight log use the same name.
- It works all the same when worn: the bonuses apply, as in 5e. Only the knowledge is
  missing.
- A trader pays a fifth of the usual price for it (`InventoryOps.stack_sell_price`).
- Known and unknown stacks of the same item don't merge.
- **Identifying:** on a **short rest**, each member names one unidentified item they carry
  (worn first), "Elowen studies the unidentified ring: a Ring of Fire Resistance". Or
  **Wenna** names them all for 25 gold each (the `identify` dialogue effect, offered when
  the `unidentified` condition holds).
- Saved as `{"item": "...", "qty": 1, "unidentified": true}`; the key is left out when the
  item is known, so older saves load as before.

## Potions with a lasting effect

`use.buff` keeps its effect in the sheet's `effects` (as `"abilities": {"str": 21}`) until
the next long rest, which clears `effects` (Spellcasting.end_long_rest_effects). Like a
worn item, it makes a score *at least* the number, so a potion that wouldn't raise
anything is refused rather than wasted. In a fight, drinking one is an action, like any
potion.

## Flasks thrown in a fight

An item with `use.throw` gets a **Throw** button on the combat bar (beside spells and
scrolls) for whoever carries it, then a target click, like a spell:

```json
"use": {"throw": {"range_ft": 20, "damage": "2d6", "damage_type": "radiant",
                  "affects": {"types": ["undead", "fiend"]}, "fx": {"color": "#fff2c0"}}}
```

- It is a ranged attack with an improvised weapon: d20 + Dex, no proficiency, out to
  `range_ft` (no long range). Advantage and disadvantage work as for any ranged attack.
- `affects` uses the same creature types as spells ([SPELLS.md](SPELLS.md)); the target
  preview refuses anything else ("Holy Water only works on undead and fiends; Wolf is a
  beast"), so no flask is wasted on it.
- The throw costs the action and the flask, hit or miss. It is not a weapon, so there is
  no Sneak Attack. It flies as a tumbling icon and bursts in `fx.color`.
- Outside a fight, using it from the inventory just says to throw it from the combat bar.

Holy Water is sold by Wenna and kept in the temple's vestry cupboard; Potions of Hill
Giant Strength are in Wenna's shop and the bandits' strongbox.

## The inventory screen

Open it with **I**, the sidebar's **Inventory** button, or by opening a container. The
game pauses while it is open.

- Drag items between backpack slots, equipment slots and the open container. Dropping on
  an occupied slot swaps, or tops up a stack of the same item.
- Drop an item on a sidebar portrait to give it to that character.
- **Shift-drop** a stack to split it: a dialog asks how many (a slider and a number box,
  starting at half; Enter or Esc) and moves, gives, drops, buys or sells just that many.
  Onto an empty slot or more of the same item; an equipment slot always takes one.
  (`InventoryOps.move_some`, `give(..., count)`, `sell(..., count)`, and
  `scripts/ui/quantity_dialog.gd`.)
- With no chest open, the bottom panel shows **the ground** where the character stands.
  Drag items there to drop them; a pile appears on the map. Click a pile later to open it
  like a chest, or right-click its items to pick them up.
- Right-click (or double-click): drink a potion or eat food, put a backpack item on, take
  worn gear off, or take an item out of the container.
- Click a sidebar portrait, or use ◀ ▶, to see another member.

All moves go through `InventoryOps` (`scripts/items/inventory_ops.gd`), which applies
the rules above and returns a message when a move is refused. The screen and the tests use
the same functions.

## Containers on maps

Any prop with `"interaction": "container"` (chests, drawers, cupboards, or a placement
that overrides its type's interaction) holds items:

```json
{"type": "chest", "at": [7, 1], "id": "strongbox", "name": "Reeve's Strongbox",
 "locked": true, "lock_dc": 15, "key": "reeve_key",
 "items": [{"item": "ring_of_protection", "qty": 1}], "gold": 60}
```

Magic in a placement's `items` starts unidentified unless the entry says
`"identified": true` ([below](#unidentified-magic-items)).

`id` must be unique within the map: the contents live in `GameState` under the map id
and this id, so they persist when the party leaves the map and in save games. The map
file only provides the starting contents.

Dropped items are containers too: each pile is stored as `ground_<q>_<r>` (its hex) and
drawn with the `item_pile` prop while it holds anything. Empty piles vanish and are not
saved. `World.ground_pile(hex, create)` returns the pile on a hex.

## Trapped containers

A container placement can carry a `trap` (rules in `scripts/items/traps.gd`):

```json
"trap": {"name": "poison needle", "find_dc": 13,
         "disarm": {"dc": 13, "ability": "dex", "tool": "thieves_tools"},
         "save": "con", "save_dc": 12, "damage": "2d6", "damage_type": "poison",
         "half_on_save": true}
```

When someone goes to open it:

1. **Noticing:** the party's best **passive Perception** (10 + Wis modifier, + proficiency
   with the Perception skill) against `find_dc`. Noticed, the game pauses on a dialog:
   "Garrick Thorne notices a poison needle on the bandits' strongbox."
   - **Disarm it:** the member best at it tries, d20 + `disarm.ability` modifier + proficiency.
     With `"tool": "thieves_tools"` they must carry a lockpick (proficiency from
     `proficiencies.tools`, doubled by Expertise); with `"skill": "arcana"` anyone may try
     (proficiency from `proficiencies.skills`). Success disarms it and the container opens;
     failing by 5 or more sets it off on them; a smaller miss can be tried again.
   - **Open it anyway:** it goes off on the opener, then the container opens.
   - **Leave it alone:** nothing happens; it is still there next time (no second notice).
2. **Unnoticed,** it goes off on whoever opens it, and the container opens.
3. **Going off:** a `save` against `save_dc` (half damage on a success with
   `half_on_save`, else none), then `damage` of `damage_type`, after resistances (a Ring of
   Fire Resistance halves a fire glyph). The trap is then spent.

The trap is checked before the lock. Its state (`armed`, `found`, `disarmed`, `sprung`) is
saved with the container. Two are placed on the old temple road: a poison needle on the
bandits' strongbox (found by the starting party's passive Perception of 13; Wren disarms
it with thieves' tools) and a fire glyph on the ruin's mouldering chest (DC 15 to notice,
so it usually goes off; Elowen can undo it with Arcana once it is found).

