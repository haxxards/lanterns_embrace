# Map format

Maps are JSON files under `data/maps/`. The starting map is set by `starting_map` in
`data/config/game_config.json`.

```jsonc
{
  "schema_version": 1,
  "id": "millbrook_outskirts",
  "name": "Millbrook Outskirts",          // shown above the minimap
  "background_color": "#141a10",           // colour outside the map
  "music": "village", "ambience": "outdoors",  // names from data/audio/audio.json
  "fog": true,                             // fog of war on this map (default true)
  "spawns": { "party": [4, 30] },          // [col, row], used for a new game
  "entries": { "well": [64, 31] },         // optional named arrival points
  "terrain": [ "fffff....~~~...", ... ],   // one string per row
  "prop_legend": { "T": "tree_oak", "P": "tree_pine", "B": "tree_birch", "b": "bush", "o": "rock",
                   "r": "reeds", "n": "fern", "w": "flowers", "L": "log", "s": "stump" },
  "prop_layer": [ "T  P   b       ", ... ], // optional, same grid as terrain
  "props": [                               // larger or unique props
    { "type": "house_small", "at": [47, 21], "name": "Miller's Cottage",  // top-left of 8x6
      "id": "millbrook_miller", "interior": "res://data/maps/millbrook_miller.json", "entry": "door" },
    { "type": "bridge_wood", "at": [24, 30] },
    { "type": "sign", "at": [4, 27], "title": "Weathered Signpost", "text": "WEST ROAD\n..." }
  ]
}
```

## The grid in text form

Each character is one hex. Rows use the **odd-r** layout: every *odd* row (1, 3, 5...)
is drawn half a hex to the right, so a column of characters zig-zags slightly on screen.

```
row 0:  . . . .
row 1:   . . . .      <- shifted right by half a hex
row 2:  . . . .
```

Coordinates in the file (`at`, `spawns`) are `[col, row]`, i.e. character position in
the strings, counting from 0. Internally the game uses axial coordinates. The hover info
panel (F3) shows both, which makes it easy to find a spot while editing.

## Terrain symbols

Symbols come from `data/terrain/terrain.json`:

| Symbol | Terrain | Walkable | Cost |
|---|---|---|---|
| `.` | Grass | yes | 1 |
| `f` | Forest floor | yes | 1 |
| `,` | Dirt road | yes | 1 |
| `:` | Riverbank sand | yes | 1 |
| `#` | Cobblestone | yes | 1 |
| `=` | Bridge deck (drawn as water; the bridge sprite covers it) | yes | 1 |
| `-` | Shallows | yes | 2 (difficult) |
| `~` | Deep water | no | - |
| `^` | Rock outcrop | no | - |
| `_` | Floor (interiors; the backdrop is drawn instead of the texture) | yes | 1 |

Add terrain by adding an entry with a new one-character `symbol`.

The hex grid is not drawn on the ground. Terrain is blended into one surface, so
the text rows describe *what* each hex is (walkable, cost) while the edges between
terrains come out organic. A map can use up to 12 different terrain textures. Blending is
tuned by `terrain_blend` in `game_config.json`.

## Props

Prop types live in `data/props/props.json`:

- `texture` and `origin`: the image, and the pixel that sits on the anchor hex centre
  (for rectangular footprints, on the bottom-centre of the footprint).
- `variants`: optional list of looks (`{"texture", "origin", "door_pixel"}`) for one prop
  type, such as three oak shapes or three cottage designs. Each placed instance picks a look
  from a stable hash of its cell, so the map looks the same every time. Set `"variant": n`
  on a `props` entry to choose one explicitly.
- `footprint`: axial `[dq, dr]` offsets from the anchor (axial so shapes don't change
  between odd and even rows), or `footprint_radius` for a filled hexagon.
- `footprint_rect`: `[cols, rows]` for buildings. The map's `at` is the **top-left** cell
  and the building covers exactly cols × rows hexes. A building's interior map uses the
  same cols × rows, so it is as large outside as inside (a test checks this).
- `layer`: `"entities"` (default, y-sorted with characters) or `"ground"` (flat, under
  characters, e.g. the bridge).
- `blocks_movement`, `move_cost` (non-blocking props such as brambles), `blocks_sight`.
- `interaction`: what clicking it does (a placement can override it with its own
  `"interaction"`):
  - `"read"` shows the instance's `title` and `text`;
  - `"container"` opens it on the inventory screen (`items`, `gold`, `locked`, `lock_dc`,
    `key`; see [ITEMS.md](ITEMS.md));
  - `"enter"` takes the party into the instance's `interior` map, arriving at its `entry`;
  - `"exit"` takes the party to the instance's `map`, arriving at its `entry`.
- `door_pixel`: where the door is drawn in the texture. The door hex is the footprint hex
  nearest to it, and characters enter from the hexes in front of it.
- `fade_when_occluding`: override the automatic see-through behaviour.

The six axial directions are `[1,0]` E, `[1,-1]` NE, `[0,-1]` NW, `[-1,0]` W,
`[-1,1]` SW, `[0,1]` SE.

Per-instance keys in a map's `props` entry (`name`, `title`, `text`, ...) are passed to the
prop as-is, so new interaction types can read their own keys.

## Moving between maps

Doors and exits are ordinary props. Clicking one sends the leader to it and the rest of
the party to gather nearby; once everyone has stopped, the map changes. Where the party
arrives is an **entry** on the target map, looked up in this order:

1. a name in the target map's `entries` (`"door"` inside every building);
2. the `id` of a prop on the target map: the party arrives in front of that building's
   door (so an interior's exit says `"entry": "millbrook_miller"` to come out of the Miller's
   Cottage);
3. otherwise `spawns.party`.

## Interiors

Interior maps use a pre-rendered **backdrop** instead of blended terrain:

```jsonc
"backdrop": { "texture": "res://assets/interiors/cottage_plaster.png", "origin": [79, 120] },
"fog": false,
"terrain": [ "________", ... ]      // all floor; furniture props block movement
```

`origin` is the backdrop pixel that sits on the centre of hex [0, 0]. Furniture (tables,
beds, chests...) are props, so characters walk in front of and behind them correctly. The
five Millbrook interiors are written by `tools/maps/generate_interiors.py`, which reads
the backdrop list from `assets/interiors/backdrops.json` (made by the Blender room renderer)
and checks that nothing overlaps and that every free hex can be reached from the door.

### Furnishing add-ons

A house can ask for furnishing sets that the interior generator lays out automatically
around the room's own furniture, keeping the door, the hearth and aisles clear:

| Add-on | Places |
|---|---|
| `bar` | Shelves of bottles against the back wall (`bar_back`), the counter two rows in front with room for a barkeep between, and kegs beside the shelves. |
| `tables:N` | N tables with benches (2×2 hexes each), spread out with a walkable ring around each. Plain `tables` means two. |

List them on the house in the village map (in `generate_millbrook.py`:
`building(..., addons=["bar", "tables:4"])`, which writes `"addons"` on the placement), or
on the room's entry in `generate_interiors.py`. The inn uses `bar` and `tables:4`. Any
cottage can be turned into a tavern the same way; the generator checks that a bar and two
tables fit in every room style. New add-ons are functions in the `ADDONS` table.

## Generators and checks

The sample map is generated by `tools/maps/generate_millbrook.py` (river, roads,
village, set dressing and scatter). The JSON it writes can still be edited by hand, and
re-running the script regenerates it from scratch.

The automated tests (`tests/unit/test_data.gd`) check every map in `data/maps/`: no
unknown symbols, props stay on the map and don't overlap, the spawn and entries are
walkable, every interactable prop can be reached from the spawn, container items exist,
and each building's interior matches its footprint and leads back out to it.
