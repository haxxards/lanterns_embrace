# Character sheets

Party members are plain JSON files, one per character. The game loads every `*.json` in
each folder listed in `character_dirs` in `data/config/game_config.json`:

1. `res://data/characters/`: shipped with the game.
2. `user://characters/`: dropped in by a player or a script without touching the project.
   A sheet here **overrides** a bundled sheet with the same `id`.

`user://` resolves to:

| OS | Path |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\Lantern's Embrace\characters` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Lantern's Embrace/characters` |
| Linux | `~/.local/share/godot/app_userdata/Lantern's Embrace/characters` |

The starting party is the list of ids in `data/party/starting_party.json`. Anything past
`max_party_size` is ignored, with a warning.

## Creating sheets with Python

`tools/make_character.py` fills in the derived numbers (HP, AC, saves, starting kit) from
small 5e SRD class and ancestry tables. Every item it hands out exists in
`data/items/items.json`, and `--validate` checks item ids too:

```sh
# exact scores (str,dex,con,int,wis,cha)
python3 tools/make_character.py --id brena --name "Brena Holt" --class ranger \
    --ancestry human --abilities 12,16,14,10,14,8 --skills survival,perception

# standard array, assigned by class priority
python3 tools/make_character.py --id pip --name "Pip" --class bard --ancestry halfling

# 4d6-drop-lowest, reproducible
python3 tools/make_character.py --id rook --name "Rook" --class fighter --ancestry dwarf \
    --roll --seed 7 --level 3

# check sheets before importing them
python3 tools/make_character.py --validate data/characters/*.json
```

Use `--out path.json` to write somewhere else (for example `user://characters`) or
`--stdout` to pipe the JSON. The tables at the top of the script (`CLASSES`, `ANCESTRIES`,
`ARMOR`) are meant to be edited.

## Fields

Required fields are marked ●. Everything else has a default. Fields the game does not use
yet are kept intact when sheets are saved (`CharacterSheet.to_dict()` round-trips unknown
keys).

| Field | Type | Notes |
|---|---|---|
| `schema_version` | int | `1`. Sheets newer than the game are reported. |
| `id` ● | string | Unique key, used by party lists and saves. |
| `name` ● | string | Display name. |
| `ancestry` | string | `human`, `elf`, `dwarf`, `halfling`, `gnome`, `half-elf`, `half-orc`, `dragonborn`, `tiefling`. Looked up in `data/races/races.json` for the creature type spells check (all are humanoid, so Hold Person works on them) and racial traits (elves and half-elves have Fey Ancestry: magic can't put them to sleep). See [SPELLS.md](SPELLS.md#who-a-spell-works-on-creature-types-and-races). |
| `class` ● | string | Any SRD class id (`fighter`, `wizard`, `cleric`, `rogue`, ...). |
| `level` | int | 1–20. |
| `xp` | int | Experience points (thresholds in `scripts/rules/rules.gd`). |
| `alignment` | string | Free text. |
| `abilities` ● | object | `str dex con int wis cha`, each 1–30. |
| `hit_points` ● | object | `{ "max": int, "current": int }`. `max` is the sheet's own maximum: hit points a worn Amulet of Health adds are put back when the sheet loads ([ITEMS.md](ITEMS.md#passive-bonuses-magic-items)). |
| `hit_die` | string | e.g. `"d10"`: hit points gained per level are half the die + 1 + Con modifier. |
| `dead` | bool | Killed (three failed death saves, or massive damage): only a temple can raise them. Saved with the game. |
| `stable` | bool | At 0 HP but no longer making death saves. |
| `death_saves` | object | `{ "successes": n, "failures": n }` while dying. |
| `armor_class` | int | Written for reference: the game recomputes AC from equipment (see [ITEMS.md](ITEMS.md)) and keeps this field up to date when saving. |
| `speed_ft` | int | Walking speed. Combat movement = `speed_ft / feet_per_hex` hexes. |
| `size` | string | `small` / `medium`. |
| `proficiencies` | object | `saving_throws`, `skills`, `armor` (`light`, `medium`, `heavy`, `shields`), `weapons` (`simple`, `martial` or item ids), `tools` (`thieves_tools`). |
| `equipment` | object | Slot → item id (or `{ "item", "qty" }`), `null` when empty. Slots: `helmet`, `amulet`, `armor`, `cloak`, `gloves`, `main_hand`, `off_hand`, `ring_1`, `ring_2`, `boots`. |
| `inventory` | array | Backpack slots in order: `{ "item": id, "qty": n }` or `null` for an empty slot. The backpack has `backpack_slots` slots (16). |
| `gold` | int | Gold the character brings. It goes into the party's shared purse when they join. |
| `spells` | object | `ability` (`int`, `wis`...; `null` for non-casters), `cantrips` and `known` (spell ids from `data/spells/spells.json`). `slots` (`{"1": 2}`) is only read for classes without a slot table; wizards and clerics use the SRD full-caster table. See [SPELLS.md](SPELLS.md). |
| `features` | array | Class feature ids (defined in `data/classes/classes.json`): `fighting_style_defense`, `second_wind`, `action_surge`, `expertise`, `sneak_attack`, `cunning_action`, `arcane_recovery`, `divine_domain`, `disciple_of_life`, `channel_divinity`, `turn_undead`, `preserve_life`... |
| `slots_used` | object | Spell slots spent since the last long rest, by level: `{"1": 1}`. Written by the game. |
| `feature_uses` | object | Uses spent of limited features, by feature: `{"second_wind": 1}`. Written by the game. |
| `hit_dice_used` | int | Hit dice spent on short rests (half come back on a long rest). Written by the game. |
| `effects` | object | Effects lasting until a long rest: `{"mage_armor": true, "aid": 5, "guidance": true}`, and scores raised by a potion, `{"abilities": {"str": 21}}`. Written by the game. |

**The class table fills in the rest.** On loading, `Classes.grant` adds every feature
and spell the character's class gives by their level (from `data/classes/classes.json`),
so a sheet only needs what it wants beyond that, and an old sheet catches up. Levelling up
grants the next level's features and spells the same way.
| `art.portrait` | string | Portrait image, `res://` or any readable path. |
| `art.sprite` | string | Map sprite image. |
| `art.sprite_origin` | [x, y] | Pixel of the sprite that sits on the hex centre (the feet). Default: bottom-centre, 6 px up. |
| `bio` | string | Free text. |

Example: [`data/characters/garrick.json`](../data/characters/garrick.json).
