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
small 5e SRD class and ancestry tables:

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
| `ancestry` | string | `human`, `elf`, `dwarf`, `halfling`, `gnome`, `half-elf`, `half-orc`, `dragonborn`, `tiefling` |
| `class` ● | string | Any SRD class id (`fighter`, `wizard`, `cleric`, `rogue`, ...). |
| `level` | int | 1–20. |
| `xp` | int | Experience points (thresholds in `scripts/rules/rules.gd`). |
| `alignment` | string | Free text. |
| `abilities` ● | object | `str dex con int wis cha`, each 1–30. |
| `hit_points` ● | object | `{ "max": int, "current": int }` |
| `hit_die` | string | e.g. `"d10"` (used for levelling later). |
| `armor_class` | int | Final AC. Will be derived from equipment in Phase 2. |
| `speed_ft` | int | Walking speed. Combat movement = `speed_ft / feet_per_hex` hexes. |
| `size` | string | `small` / `medium`. |
| `proficiencies` | object | `saving_throws`, `skills`, `armor`, `weapons` (string lists). |
| `equipment` | object | Slot → item id: `main_hand`, `off_hand`, `armor` (Phase 2). |
| `inventory` | array | `[{ "item": id, "qty": n }]` (Phase 2). |
| `gold` | int | Starting gold (Phase 2). |
| `spells` | object | `ability`, `cantrips`, `known`, `slots` (`{"1": 2}`) (Phase 4). |
| `features` | array | Class feature ids (Phase 4). |
| `art.portrait` | string | Portrait image, `res://` or any readable path. |
| `art.sprite` | string | Map sprite image. |
| `art.sprite_origin` | [x, y] | Pixel of the sprite that sits on the hex centre (the feet). Default: bottom-centre, 6 px up. |
| `bio` | string | Free text. |

Example: [`data/characters/garrick.json`](../data/characters/garrick.json).
