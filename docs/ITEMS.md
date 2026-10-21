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
| `weapon` | object | `category` (`simple`/`martial`), `damage` (dice, e.g. `"1d8"`), `damage_type`, optional `versatile` dice, `properties` (`finesse`, `light`, `thrown`, `two_handed`, `ammunition`), `range` `[normal, long]` in feet, `ammo` item id. |
| `armor` | object | Body armour: `type` (`light`/`medium`/`heavy`), `base_ac`, `dex_cap` (medium), `strength` (heavy: below it, speed −10 ft), `stealth_disadvantage`. Shields: `type: "shield"`, `ac_bonus`. |
| `bonuses` | object | Passive bonuses while worn. `{"ac": 1}` is implemented. |
| `use` | object | What using it does. `{"heal": "2d4+2"}` is implemented (potions, food). |
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
- **Locks:** a container can be `locked`. A `key` item anywhere in the party opens it.
  Otherwise someone carrying a `lockpick` tool rolls d20 + Dex (+ proficiency with
  `"tools": ["thieves_tools"]`) against `lock_dc` each time they try.

## The inventory screen

Open it with **I**, the sidebar's **Inventory** button, or by opening a container. The
game pauses while it is open.

- Drag items between backpack slots, equipment slots and the open container. Dropping on
  an occupied slot swaps, or tops up a stack of the same item.
- Drop an item on a sidebar portrait to give it to that character.
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

`id` must be unique within the map: the contents live in `GameState` under the map id
and this id, so they persist when the party leaves the map and in save games. The map
file only provides the starting contents.

Dropped items are containers too: each pile is stored as `ground_<q>_<r>` (its hex) and
drawn with the `item_pile` prop while it holds anything. Empty piles vanish and are not
saved. `World.ground_pile(hex, create)` returns the pile on a hex.
