# Assets

The world art is **pre-rendered 3D**, the way the classic isometric RPGs made theirs:
every tree, building, character and ground texture is modelled procedurally in Blender
and rendered with Cycles from the game's camera angle. The portraits are **2D paintings**:
crops of public-domain Old Master portraits that The Metropolitan Museum of Art releases
under CC0. Everything is made by scripts in this repo, so there are no licences to
track, and every file is a drop-in placeholder you can replace with your own art.

| What | Made by | Notes |
|---|---|---|
| Terrain textures | `tools/art/blender/render_terrain.py` | Small 3D ground patches (grass blades, pebbles, leaves, cobbles, rock, rippled water) laid out to wrap at the edges, rendered straight down. |
| Props and buildings | `tools/art/blender/render_props.py` | Oaks, pines and birches (several shapes each) with tens of thousands of leaf cards; thatched, tiled and shingled cottages; a two-storey inn with lit windows; well, bridge, rocks, signpost; set dressing such as reeds, ferns, wildflowers, logs, stumps, barrels, crates, hay, lamp posts, market stalls and a cart. |
| Character sprites | `tools/art/blender/render_characters.py` | Posable 3D figures with class gear. Each is rendered as a sprite sheet: 5 facings × (idle + 8-frame walk), mirrored in game for the other 3 facings. |
| Portraits | `tools/art/portraits/make_portraits.py` | Crops of CC0 public-domain paintings from the Met (see below). |

## Re-rendering

Blender is used as a Python module (`bpy`). It needs **Python 3.13**:

```sh
python3.13 -m venv .venv-art
.venv-art/bin/pip install bpy==5.2.2 numpy pillow
.venv-art/bin/python tools/art/blender/render_all.py                 # everything (~20 min on 4 cores)
.venv-art/bin/python tools/art/blender/render_all.py terrain:grass props:tree_oak characters
```

Rendering a prop writes its looks (texture, anchor pixel `origin`, door pixel) back into
`data/props/props.json`, as a `variants` list when there is more than one. Rendering a
character writes its sprite sheet, a `<class>_anim.json` description, and the static
sprite, and points every character sheet using that class at them (`art.animation`,
`art.sprite_origin`). You never edit those numbers by hand.

### Conventions

- **Scale:** 1 hex = 5 ft = 1.524 m = 55.4 px, so about 36.4 px per metre.
- **Camera:** orthographic, looking north from 45° above the horizon. Models are
  stretched in depth by 1/sin 45° so a building's ground footprint renders at exactly the
  size of its hexes on the top-down grid, while walls and bodies keep their height.
- **Light:** sun from the upper left (shadows fall down-right). Props use a high sun so
  shadows stay compact, and baked shadows are lightened to 60% so they read as soft
  ground shadows. Terrain uses a lower sun for more relief.
- **Terrain:** 512×512 px, seamless, 1 texel per world pixel.

## Portraits

Portraits are head-and-shoulders crops of real paintings (van Dyck, Hals, El Greco,
Rembrandt's circle, Memling and others), which gives the painted look of classic RPG
portraits without any licence strings: The Met's Open Access images of public-domain
works are CC0. `tools/art/portraits/portraits.json` lists each painting by its Met object
number with a crop (face centre and crop height), and `make_portraits.py` downloads the
paintings from the museum's public bucket, crops them to 4:5, lifts dark varnish a little
and writes 256×320 PNGs:

```sh
python3 tools/art/portraits/make_portraits.py              # all of them (needs Pillow)
python3 tools/art/portraits/make_portraits.py wren --sheet /tmp/check.png
```

Besides the four party members there is a small library for later NPCs: `npc_veteran`,
`npc_pickpocket`, `npc_elder`, `npc_merchant`, `npc_priest`, `npc_monk`, `npc_sage`,
`npc_noble`, `npc_villager`, `npc_young_knight`, `npc_warrior` and `npc_bard`. Any of them
can be given to a character with `art.portrait`. [CREDITS.md](../CREDITS.md) lists every
painting.

To use your own, drop in any 4:5 PNG (256×320 recommended; the sidebar shows 64×80).

## Replacing art

Data files reference images by path, so there are two options:

1. **Overwrite the PNG** at the same path. Godot re-imports it automatically.
2. **Point the data at a new file**: change `texture` in `terrain.json` / `props.json`,
   or `art.portrait` / `art.sprite` in a character sheet. Paths can be `res://...` or
   any readable file path (such as `user://...`).

A missing file shows as a magenta checkerboard and logs a warning, so broken references
are easy to spot.

## Specs

| Kind | Location | Size | Notes |
|---|---|---|---|
| Terrain | `assets/terrain/*.png` | 512×512 (other sizes are resized) | Must be **seamless**. Sampled in world space at 1 texel per pixel and blended with neighbouring terrain by `terrain_blend.gdshader`. |
| Props | `assets/props/*.png` | any | `origin` in `props.json` is the pixel placed on the anchor hex centre (trees: trunk base), or for buildings the centre of the front wall's base. Include the ground shadow. |
| Character sprites | `assets/characters/<class>.png` | any | Static fallback (south-east idle). `art.sprite_origin` = feet pixel. Shadow and selection ring are drawn by code. |
| Character animation | `assets/characters/<class>_sheet.png` + `<class>_anim.json` | cells of any size | Rows = facings listed in `directions` (`s, se, e, ne, n`), columns = idle + walk frames. `origin` = feet pixel within a cell (keep it horizontally centred so mirroring works). `cycle_px` = pixels walked per walk cycle. |
| Portraits | `assets/portraits/*.png` | 4:5, 256×320 recommended | Shown at 64×80 in the sidebar (cropped to fill) and larger on the inventory screen. |

Footprints:

| Prop | Footprint |
|---|---|
| tree_oak, tree_pine, tree_birch, rock, sign, well, log, stump, barrels, crates, hay, lamp_post | 1 hex (blocking) |
| bush | 1 hex, walkable but difficult |
| reeds, fern, flowers | 1 hex, walkable (decoration) |
| market_stall | 3×2 hexes |
| cart | 2×1 hexes |
| house_small (cottage) | 8×6 hexes, door from `door_pixel` |
| house_large (inn) | 12×8 hexes, door from `door_pixel` |
| bridge_wood | 8×2 hexes, ground layer, walkable |

Building art must cover its footprint: the walls are `cols × 1.524 m` wide, and roof
eaves may overhang by up to a hex in total. A test checks this. `bridge_planks.png`
(old 2D) is a spare texture for interior floors in Phase 2.
