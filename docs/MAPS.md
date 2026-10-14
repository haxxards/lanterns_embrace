# Map format

Maps are JSON files under `data/maps/`. The starting map is set by `starting_map` in
`data/config/game_config.json`.

```jsonc
{
  "schema_version": 1,
  "id": "millbrook_outskirts",
  "name": "Millbrook Outskirts",          // shown above the minimap
  "background_color": "#141a10",           // colour outside the map
  "spawns": { "party": [3, 20] },          // [col, row]
  "terrain": [ "fffff....~~~...", ... ],   // one string per row
  "prop_legend": { "T": "tree_oak", "P": "tree_pine", "b": "bush", "o": "rock" },
  "prop_layer": [ "T  P   b       ", ... ], // optional, same grid as terrain
  "props": [                               // larger or unique props
    { "type": "house_small", "at": [36, 16], "name": "Miller's Cottage" },
    { "type": "sign", "at": [4, 18], "title": "Weathered Signpost", "text": "WEST ROAD\n..." }
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
| `=` | Bridge | yes | 1 |
| `-` | Shallows | yes | 2 (difficult) |
| `~` | Deep water | no | - |
| `^` | Rock outcrop | no | - |

Add terrain by adding an entry with a new one-character `symbol`.

## Props

Prop types live in `data/props/props.json`:

- `texture` and `origin`: the image and the pixel that sits on the anchor hex centre.
- `footprint`: axial `[dq, dr]` offsets from the anchor (axial so shapes don't change
  between odd and even rows), or `footprint_radius` for a filled hexagon.
- `blocks_movement`, `move_cost` (non-blocking props such as brambles), `blocks_sight`.
- `interaction`: `"read"` shows the instance's `title` and `text`. More kinds come later.
- `door`: axial offset of the entrance (used for building interiors in Phase 2).
- `fade_when_occluding`: override the automatic see-through behaviour.

The six axial directions are `[1,0]` E, `[1,-1]` NE, `[0,-1]` NW, `[-1,0]` W,
`[-1,1]` SW, `[0,1]` SE.

Per-instance keys in a map's `props` entry (`name`, `title`, `text`, ...) are passed to the
prop as-is, so new interaction types can read their own keys.

The automated tests (`tests/unit/test_data.gd`) check the starting map: no unknown
symbols, props stay on the map and don't overlap, the spawn is walkable, and every sign and
door can be reached from the spawn.
