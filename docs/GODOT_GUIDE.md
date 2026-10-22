# How this game is built in Godot

A guided tour of Lantern's Embrace for someone who wants to follow along with what has
been built and learn enough Godot to extend it. It explains the Godot ideas the project
relies on, how the pieces of this codebase fit together, how to add content without
writing code, and what to learn before tackling the next phases.

Everything here refers to real files in the repository. Paths are relative to the project
root (`res://` in Godot terms).

Studying the project from scratch? [START_HERE.md](START_HERE.md) is a checklist that walks
you through this guide and the code in a sensible order, one stop at a time.

**Contents**

1. [Godot in one page](#1-godot-in-one-page)
2. [The shape of this project](#2-the-shape-of-this-project)
3. [Following a click: the main loops](#3-following-a-click-the-main-loops)
4. [Hex grids](#4-hex-grids)
5. [Drawing the world](#5-drawing-the-world)
6. [The interface](#6-the-interface)
7. [Data-driven content](#7-data-driven-content)
8. [Saving and loading](#8-saving-and-loading)
9. [Testing](#9-testing)
10. [The asset pipeline](#10-the-asset-pipeline)
11. [A reading order for the code](#11-a-reading-order-for-the-code)
12. [Before you expand: what to learn next](#12-before-you-expand-what-to-learn-next)
13. [Pitfalls we hit, so you don't have to](#13-pitfalls-we-hit-so-you-dont-have-to)
14. [Glossary and further reading](#14-glossary-and-further-reading)

---

## 1. Godot in one page

### Nodes, scenes and the scene tree

A running Godot game is a **tree of nodes**. Each node has one job: `Sprite2D` draws a
texture, `Camera2D` decides what part of the world is on screen, `AudioStreamPlayer`
plays a sound, `Button` is a clickable button, and a plain `Node` does nothing on its own
but can carry a script.

A **scene** (`.tscn` file) is a saved branch of that tree. Scenes can be instanced inside
other scenes, which is how Godot projects are usually composed. This project is unusual in
that it has only one real scene, `scenes/main.tscn`:

```
Main  (Node, scripts/main.gd)
├── World  (Node2D, scripts/world/world.gd)
└── HUD    (CanvasLayer, scripts/ui/hud.gd)
```

Everything else (the terrain, every tree and house, the party, the sidebar, the inventory
screen) is **created in code** by those scripts: `var prop := Prop.new()`, then
`add_child(prop)`. That was a deliberate choice for this skeleton: you can read how
everything is put together in one place without opening the editor. In your own additions
you are free to build scenes in the editor instead (see [§12](#12-before-you-expand-what-to-learn-next));
both styles mix well.

### Scripts and classes

A GDScript file is a class. `extends Node2D` says which node type it builds on, and
`class_name World` gives it a global name, so other scripts can write `World.new()` or
declare `var world: World`. Scripts without `class_name` are referenced by path.

There are three kinds of base class you will see here, and choosing between them matters:

| Base | Lives in the tree? | Freed how | Used here for |
|---|---|---|---|
| `Node` (and `Node2D`, `Control`...) | Yes | `queue_free()` | Things that are drawn, take input or run every frame: `World`, `PartyMember`, `Prop`, `Hud`. |
| `RefCounted` | No | Automatically, when nothing references it | Plain data and logic: `HexGrid`, `CharacterSheet`, `Inventory`, `ItemDef`, `Rules`. |
| `Resource` | No | Reference counted | Data you want the editor to save and edit (`.tres`). Not used yet, see [§12](#12-before-you-expand-what-to-learn-next). |

Most of the game's logic is in `RefCounted` classes with no node at all, which keeps it
easy to test.

### The node lifecycle

Godot calls these methods on a node if the script defines them:

| Method | When |
|---|---|
| `_init()` | When the object is created (before it is in the tree). |
| `_ready()` | Once, after the node and its children have entered the tree. Build children here. |
| `_process(delta)` | Every frame. `delta` is the frame time in seconds. `PartyMember` walks here. |
| `_input(event)` / `_unhandled_input(event)` | Input events. "Unhandled" only sees events the UI did not consume (see below). |
| `_draw()` | When the node needs repainting (after `queue_redraw()`). `CursorOverlay`, `Minimap` and `ItemSlot` draw with it. |
| `_notification(what)` | Low-level engine notifications, e.g. `NOTIFICATION_DRAG_END` in `ItemSlot`. |

### Signals

A **signal** is an event a node or object can emit; anything can connect a function to
it. `PartyMember` declares `signal arrived(member)` and emits it when a walk ends;
`PartyController` connects `_on_member_arrived` to it. Signals keep the emitter ignorant
of who is listening.

This project also has a **signal hub**, the `Events` autoload
(`scripts/autoload/events.gd`): game code emits `Events.toast_requested.emit("Can't reach
that.")` and the HUD, which connected to that signal, shows it. World code never holds a
reference to UI code, so either can change without breaking the other.

### Autoloads (singletons)

Scripts listed under `[autoload]` in `project.godot` are created once at start-up, before
the main scene, and are reachable from anywhere by name:

| Autoload | Job |
|---|---|
| `GameConfig` | Reads `data/config/game_config.json`: every tunable number. |
| `Data` | Loads and indexes static data: terrain, props, items, character templates; caches textures. |
| `GameState` | The playthrough: party, purse, current map, containers, explored fog, flags. |
| `Events` | The signal hub. |
| `Audio` | Plays sounds by name. |
| `SaveManager` | Save slots on disk. |

The order matters: `Data` uses `GameConfig`, so `GameConfig` comes first.

### Input

Keys are bound to named **actions** in `project.godot` (`[input]`): `toggle_pause`,
`toggle_inventory`, `quicksave`... Code asks `event.is_action_pressed("quicksave")`
rather than checking for F5, so rebinding is a settings change.

Godot delivers each input event in this order: `_input()` on every node, then the **GUI**
(Control nodes under the mouse), then `_unhandled_input()`. A `Control` with
`mouse_filter = MOUSE_FILTER_STOP` consumes mouse events over it. That is why clicking the
sidebar never moves the party: the sidebar stops the click before `World._unhandled_input`
sees it.

### Pausing

`get_tree().paused = true` stops `_process` on every node whose `process_mode` is
"pausable". The party tokens are pausable; `World`, the HUD and the camera are set to
`PROCESS_MODE_ALWAYS`, so you can still pan and give orders while paused (the
Baldur's Gate behaviour). The inventory and menus pause the game the same way.

### 2D drawing order

- `z_index` orders siblings and children: the terrain is at -10, ground props -9, the hex
  cursor -7, the fog of war +40.
- `y_sort_enabled` on the `Entities` node sorts its children by their y position every
  frame, so a character walking north of a tree is drawn behind it, and south of it in front.
  Every prop and character puts its "feet" at its node position for exactly this reason.
- `CanvasLayer` nodes draw independently of the camera. The HUD is a CanvasLayer (layer 2),
  so it stays put while the world scrolls. The colour grade is another one (layer 1).

### Shaders and materials

A **shader** is a small GPU program that decides the colour of every pixel a node draws.
Assign it through a `ShaderMaterial` on the node (`material = mat`) and feed it data with
`mat.set_shader_parameter(...)`. This project uses three `canvas_item` shaders (blended
terrain, fog of war and the colour grade); see [§5](#5-drawing-the-world).

### Files: `res://`, `user://` and importing

- `res://` is the project folder. It is read-only in an exported game.
- `user://` is a per-user writable folder: saves go to `user://saves`, and extra character
  sheets can be dropped into `user://characters`.
- Godot **imports** assets: a PNG is converted to an engine texture the first time the
  editor sees it, with settings in the `.png.import` file next to it. Keep the `.import`
  files in git. The `.uid` files next to scripts are stable IDs Godot 4.4+ uses to find
  resources even after they move. Keep those too.
- Plain data (JSON) is read with `FileAccess` and `JSON` (see `scripts/core/json_util.gd`).

---

## 2. The shape of this project

```
   data/*.json (terrain, props, items, maps, characters, npcs, dialogue, quests, audio, config)
                 │  read once at start
                 ▼
        ┌──────────────────┐     ┌──────────────────────────────┐
        │ GameConfig, Data │     │ GameState (the playthrough)  │
        │ (static content) │     │ party sheets, purse, map,    │
        └────────┬─────────┘     │ containers, explored fog,    │
                 │               │ quests, story flags          │
                 │               └───────┬──────────────▲───────┘
                 ▼                       │              │ SaveManager
        ┌──────────────────────────────────────────┐    │ to_dict / load_dict
        │ World (one loaded map)                   │    │
        │  HexGrid ─ terrain, blockers, A*         │────┘
        │  TerrainRenderer / backdrop ─ the ground │
        │  Props ─ trees, houses, chests, doors    │
        │  PartyController → PartyMembers (Actors) │
        │  Npcs (Actors) ─ townsfolk               │
        │  Creatures (Actors) ─ foes               │
        │  CombatManager ─ turn-based fights       │
        │  FogOfWar, Camera                        │
        └───────────────┬──────────────────────────┘
                        │ Events (signals)
                        ▼
        ┌──────────────────────────────────────────┐
        │ HUD: sidebar, portraits, minimap, toasts,│
        │ inventory and shop screen, dialogue      │
        │ window, journal, combat HUD, menus,      │
        │ save/load                                │
        └──────────────────────────────────────────┘
```

Four layers, each depending only on the ones above it:

1. **Data** (`scripts/data`, `scripts/autoload/data_registry.gd`, `game_config.gd`): parses
   JSON into typed definitions (`TerrainDef`, `PropDef`, `ItemDef`, `MapData`). Definitions
   never change during play.
2. **Rules and state** (`scripts/rules`, `scripts/items`, `scripts/dialogue`,
   `scripts/quests`, `game_state.gd`): character sheets, inventories, the 5e numbers,
   dialogue logic, quests, everything that must be saved. Pure logic, no nodes.
3. **World** (`scripts/world`): turns a map into nodes, handles map input, moves the party.
4. **UI** (`scripts/ui`): shows state and sends orders back to the world.

The split between a *definition* (shared, read-only: "what is a longsword") and an
*instance* (per-copy, mutable: "Garrick's longsword, quantity 1") appears everywhere:
`ItemDef`/`ItemStack`, `PropDef`/`Prop`, the template sheets in `Data.characters` versus
the live copies in `GameState.party` (`Data.new_character()` makes a copy).

---

## 3. Following a click: the main loops

### A move order

1. The mouse button arrives in `World._unhandled_input` (`scripts/world/world.gd`). The
   HUD did not consume it, so it is over the map.
2. `screen_to_world()` converts the screen position to world coordinates through the
   camera's canvas transform. `HexGrid.world_to_hex()` turns that into a hex.
3. `_on_click()` checks, in order: a party member under the cursor (select it), an
   interactable prop (walk to it), otherwise ground: `party.move_selected_to(hex)`.
4. `PartyController.move_selected_to()` (`scripts/world/party_controller.gd`) gives the
   leader the clicked hex and each other selected member the nearest free hex around it,
   then calls `member.follow_path(grid.find_path(...))`.
5. Each `PartyMember._process(delta)` (`scripts/world/party_member.gd`) moves along its path,
   cutting corners where the ground allows a straight line, picks the right animation frame
   and facing, and emits `hex_entered` and finally `arrived`.
6. `hex_entered` marks the fog of war dirty; it recomputes sight once per frame at most.

### Opening a chest

1. The click finds a `Prop` whose `interaction()` is `"container"`. The world calls
   `party.interact_with(prop)`, which walks the leader to a hex next to it and remembers the
   prop in `pending_interaction`.
2. On `arrived`, `PartyController._on_member_arrived()` calls `prop.interact(member)`.
3. `Prop._open_container()` (`scripts/world/prop.gd`) deals with the lock (key in the party,
   or a thieves' tools roll with `Rules.ability_check`), plays a sound, and emits
   `Events.container_opened(state, title, opener)`.
4. The HUD hears it, pauses the game and opens the `InventoryScreen` with the container
   attached. Dragging items calls `InventoryOps.move()`; the screen redraws when the
   inventories emit `changed`.
5. The contents are a `ContainerState` that lives in `GameState`, not on the prop, so
   emptying a chest is remembered when you leave the map and in save games.

### Walking through a door

1. A house prop has `"interaction": "enter"` and its placement names an `interior` map and
   an `entry`. When a map loads, `World._build_door_zones()` records each building's
   **door zone**: the walkable hexes touching its door hex, outside its footprint
   (`Prop.approach_hexes`). Only a click on a door zone hex goes in (`World.door_at`);
   buildings are left out of `_interactable_at`, so a click on a wall, a roof or the ground
   behind a building's picture is an ordinary move. Pointing at a building shows its zone
   faintly (`CursorOverlay.door_zone`); pointing at the zone lights it up.
   `interact_with()` then sends the leader to the door and the rest of the party to gather
   nearby.
2. When the last member stops, the door's `interact()` emits
   `Events.map_change_requested(path, entry)`.
3. `scripts/main.gd` handles it with `call_deferred`: the request comes from inside a
   party member's signal, and changing maps frees that member, so the change must wait until
   the current frame's callbacks have finished.
4. `World.load_map(path, entry)` clears the old props, builds the new grid, draws the
   backdrop (interiors) or blended terrain, spawns the townsfolk and then the party at the
   entry, sets up fog, music and ambience, and emits `Events.map_loaded`. The HUD rebuilds
   the portraits and minimap on that signal.

### A fight

1. Every frame while exploring, `World._process` asks `hostiles_noticing()`: is a creature
   within its `aggro` hexes of a standing party member, with a clear line of sight? If so
   `start_combat()` collects its encounter group and calls `combat.start(foes)`.
2. `CombatManager.start` halts the party, rolls initiative for everyone, sorts them, and
   defers `_run()`, the turn loop.
3. For a party member's turn, `_run` selects them and `await`s `_player_done`. Meanwhile
   `World` routes clicks: ground → `player_move(hex)`, which walks a path hex by hex with
   `move_along()` (checking opportunity attacks as each hex is left), and an enemy →
   `player_attack(target)`, which may walk next to it first and then calls
   `attack_with()`.
4. `attack_with()` works out advantage from the positions, rolls with `CombatRules`, applies
   damage to the target's sheet, logs a line, plays the lunge and the floating number, and
   handles someone going down or a creature being slain (loot, XP pool, the group's
   `defeated` flag).
5. Space (or the button) emits `_player_done`; `_run` moves on. A creature's turn is
   `await CombatAI.take_turn(self, c)`, which uses the same `move_along` and `attack_with`.
6. After each turn `_check_end()` looks for a side with nobody standing: victory shares the
   XP; defeat leaves the game-over screen to `Events.party_defeated`.

### Talking to someone

1. `World._on_click()` finds a visible `Npc` under the cursor (`npc_at()`), tells it to
   `hold()` still, and calls `party.interact_with(npc)`. This is the same call a chest
   gets: `interact_with` only asks its target for `approach_hexes()`, `is_adjacent_to()`
   and `interact()`, so a `Prop` and an `Npc` both work. GDScript calls methods by name
   at run time, so the two classes need no shared base beyond `Node2D` ("duck typing").
   Inside, the target is held in a `Variant` variable so the type checker allows calls
   that `Node2D` itself doesn't declare.
2. The leader walks to a free hex beside the NPC. The NPC's own hex is blocked:
   `HexGrid.set_occupied()` disables that A* point while someone stands on it.
3. On arrival `Npc.interact()` turns both to face each other and emits
   `Events.dialogue_requested(npc, member)`.
4. The HUD pauses the game and opens the `DialogueWindow`, which creates a
   `DialogueRunner` (`scripts/dialogue/dialogue_runner.gd`) for the NPC's dialogue file.
   The runner picks the start node (the first entry whose condition holds), and lists
   the options whose `"if"` holds (`Conditions.check`).
5. Choosing an option applies its effects (`Effects.apply`: gold, items, quest stages,
   healing) and moves to its `goto` node. The effects' messages become toasts.
6. When the conversation ends, the window emits `closed(runner, npc)`. The HUD lets the NPC
   wander again and, if the last option asked for the shop, opens the inventory screen in
   trade mode with the vendor's stock (`GameState.vendor_stock`). Dragging between the
   stock and a backpack then goes through `InventoryOps.buy` / `sell`.
7. A quest stage change (`GameState.set_quest_stage`) writes the journal, and a finished
   quest calls `award_xp`, which levels characters up through `CharacterSheet.add_xp`.

---

## 4. Hex grids

Everything that matters for rules happens on hexes: walkability, movement cost, sight,
where props stand. Read [Red Blob Games' hex guide](https://www.redblobgames.com/grids/hexagons/),
which the code follows closely.

- **Axial coordinates** `(q, r)` (a `Vector2i`) are used for all maths: neighbours,
  distance, lines, rings (`scripts/core/hex.gd`).
- **Offset coordinates** `[col, row]` ("odd-r": odd rows shifted half a hex right) are used
  for storage and in map files, because they match the rows of text in the JSON.
  `Hex.offset_to_axial()` and `axial_to_offset()` convert.
- **Pixels**: `Hex.to_pixel()` / `from_pixel()` with pointy-top hexes of radius 32 px.
- `HexGrid` (`scripts/core/hex_grid.gd`) stores terrain and prop blockers per hex in flat
  arrays, and builds an `AStar2D` graph whose point weights are the movement costs, so
  difficult terrain is avoided when a detour is cheaper.

The party walks smoothly between hexes, but every walk starts and ends on a hex centre,
and the hex under a member's feet is always known (`PartyMember.hex`). Turn-based combat
can switch smoothing off (`smooth_paths = false`) for strict hex-by-hex steps.

---

## 5. Drawing the world

### Pre-rendered art

Like the classic isometric RPGs, the art is 3D rendered to 2D images ahead of time
(Blender, see [§10](#10-the-asset-pipeline)). The camera angle is an oblique 45° view whose
depth is stretched so that a building's ground footprint lines up exactly with the
top-down hex grid. That is what lets game logic stay on a flat hex grid while the pictures
have height.

### Seamless terrain: a splat-map shader

Outdoors, the ground is one big rectangle drawn by `TerrainRenderer`
(`scripts/world/terrain_renderer.gd`) with `terrain_blend.gdshader`:

1. Every terrain texture goes into one `Texture2DArray` (one layer per terrain).
2. On the CPU, "splat" images are baked: for every 12 world pixels, which terrain is there
   (each terrain one colour channel), with noise warping the lookup so edges are organic.
3. The shader samples the splats (blurred by bilinear filtering, so they blend), adds
   noise, and mixes the terrain layers by weight. Textures are sampled in world space, so
   grass continues seamlessly across hexes. Water layers drift and glint using `TIME`.

### Fog of war: per-hex data, smooth picture

`FogOfWar` (`scripts/world/fog_of_war.gd`) computes, per hex, *in sight* or *explored*
(with line of sight along `Hex.line`, blocked by buildings). It writes one byte per hex
into a tiny texture (84×56 texels for the sample map). `fog_of_war.gdshader` then, for
every screen pixel, works out which hex the pixel is in (the same maths as
`Hex.from_pixel`, in GLSL) and averages a ring of samples, giving soft edges. Updating the
fog costs a few thousand bytes, not a full-screen image.

This pattern, *simulate on a coarse grid on the CPU and make it pretty on the GPU*, is
worth remembering for future effects (spell areas, light, danger zones).

### Interiors: backdrops

Interior maps draw a single pre-rendered room picture (`backdrop`) instead of terrain.
Furniture is separate props so y-sorting keeps working: a character behind a table is
drawn behind it.

### Occlusion fade and the colour grade

`World._update_occlusion()` makes a tall prop translucent while a party member is behind
it. `ColorGrade` (`scripts/ui/color_grade.gd`) is a full-screen `ColorRect` on its own
CanvasLayer whose shader reads the screen (`hint_screen_texture`) and applies contrast,
saturation, warmth and a vignette.

---

## 6. The interface

### Built from Control nodes

The HUD (`scripts/ui/hud.gd`) builds its layout in code from **containers**: `VBoxContainer`
and `HBoxContainer` stack children, `GridContainer` makes grids, `CenterContainer` centres
the inventory screen, `PanelContainer` draws a background. Containers size and place
their children for you; you rarely set positions by hand. Anchors
(`set_anchors_and_offsets_preset`) pin a control to an edge of the screen. The look comes
from a `Theme` (`scripts/ui/ui_theme.gd`) and `StyleBoxFlat` panels.

### Drag and drop

Godot's `Control` has built-in drag and drop, used by the inventory
(`scripts/ui/item_slot.gd`):

```gdscript
func _get_drag_data(at_position):        # start dragging: return what is dragged
    set_drag_preview(icon_control)
    return {"ref": ref}

func _can_drop_data(at_position, data):  # hovering: may it drop here?
    return data is Dictionary and data.has("ref")

func _drop_data(at_position, data):      # dropped
    var err := InventoryOps.move(data["ref"], ref)
```

`PortraitCard` implements just the last two, so dropping an item on a sidebar portrait
gives it to that character. The UI never changes inventories itself: it calls
`InventoryOps`, which applies the rules and returns a reason when a move is refused. The
tests call the same functions, so the rules are tested without the UI.

### Custom tooltips and drawing

`ItemSlot` draws itself in `_draw()` (frame, icon, stack count) and overrides
`_make_custom_tooltip()` to show item stats in a styled panel.

---

## 7. Data-driven content

Most content needs no code. Each file has a reference doc:

| To add | Edit | Docs |
|---|---|---|
| A party member | a JSON sheet (or `tools/make_character.py`) | [CHARACTER_SHEETS.md](CHARACTER_SHEETS.md) |
| An item | `data/items/items.json` + a 64×64 icon | [ITEMS.md](ITEMS.md) |
| A prop type | `data/props/props.json` + an image | [ASSETS.md](ASSETS.md), [MAPS.md](MAPS.md) |
| A terrain | `data/terrain/terrain.json` + a seamless texture | [MAPS.md](MAPS.md) |
| A map or interior | `data/maps/*.json` (or the generators in `tools/maps/`) | [MAPS.md](MAPS.md) |
| A sound | `data/audio/audio.json` + a file | [AUDIO.md](AUDIO.md) |
| A tunable | `data/config/game_config.json` | [README](../README.md) |

The JSON is parsed in one place per kind (`ItemDef.from_dict`, `PropDef.from_dict`,
`MapData.load_file`...), with defaults for everything optional and readable errors for
mistakes. When you add a field, add it there, document it, and add a check in
`tests/unit/test_data.gd`.

Per-instance data on a map placement (`"name"`, `"items"`, `"interior"`...) is passed
through to the `Prop` as `extra`, so a new interaction kind can read its own keys without
changing the map parser.

---

## 8. Saving and loading

The rule that makes saving simple: **everything that must survive lives in `GameState`,
and `GameState` turns into a plain Dictionary.**

- `GameState.to_dict(positions, camera)` gathers the party sheets (`CharacterSheet.to_dict()`,
  which includes equipment and backpack), the purse, the current map, every container's
  contents, the explored-fog masks (base64), play time and flags.
- `SaveManager.save_game()` (`scripts/autoload/save_manager.gd`) adds a `meta` block (label,
  map name, date, party) and writes the whole thing as JSON to `user://saves/slot_N.json`,
  plus a PNG thumbnail.
- `SaveManager.load_game()` calls `GameState.load_dict()`, which rebuilds the party and the
  container states and stores the saved positions in `pending_positions`; `Main` then
  reloads the map, and `World.load_map()` places everyone on their saved hexes.

Map *contents* are not saved: maps are reloaded from their files, and only what changed
(containers, fog) is layered on top from `GameState`. When you add something that changes
during play (an NPC's mood, a door that's been unlocked, a quest stage), give it a home in
`GameState` (`flags` is there for simple cases), include it in `to_dict`/`load_dict`, and
add a line to `test_game_state_round_trip`.

The save format has a `version`. If you change its meaning later, bump
`GameState.SAVE_VERSION` and convert old saves in `load_dict`.

---

## 9. Testing

`tools/run_tests.sh /path/to/godot` runs `tests/test_runner.tscn` headless (no window).
The runner finds every `test_*.gd` under `tests/unit` and `tests/integration`, runs each
`test_*` method, and fails a test if any engine or script error is logged while it runs
(through a custom `Logger`), so a typo in a rarely used path cannot pass silently.

- **Unit tests** build objects directly: a `HexGrid`, a `CharacterSheet` from
  `Data.new_character("garrick")`, an `Inventory`. They are fast and precise.
- **Integration tests** instance the real `main.tscn` and drive it: issue orders, step
  `PartyMember._process(DT)` manually so walks are deterministic, wait for deferred calls
  with `await get_tree().process_frame`, and check the outcome. `test_phase2.gd` walks the
  party into a cottage and out again, empties drawers, picks a lock, and saves and loads.

A test is a method that calls `check(condition, message)` or `check_eq(actual, expected,
message)`. Add one for every new rule; it is the cheapest documentation of how the rule is
meant to behave.

---

## 10. The asset pipeline

None of the art is hand-painted; it is all regenerated by scripts, which means any piece
can be changed by editing code and re-running:

| Assets | Script | Notes |
|---|---|---|
| Terrain, props, buildings, characters, item icons, interiors | `tools/art/blender/render_all.py` | Blender as a Python module (`bpy`), Cycles renderer. Writes origins and door pixels back into the JSON. |
| Portraits | `tools/art/portraits/make_portraits.py` | Crops CC0 paintings from The Met. |
| Sounds | `tools/audio/generate_placeholder_audio.py` | Synthesised with numpy/scipy. |
| Maps | `tools/maps/generate_millbrook.py`, `generate_interiors.py` | Write the JSON maps. |

Every asset is a drop-in placeholder: replace the PNG/OGG at the same path, or point the
JSON at a new file. [ASSETS.md](ASSETS.md) lists sizes and pivots.

**Art styles.** The item icons exist twice: `assets/items/longsword.png` (classic) and
`assets/items/painted/longsword.png` (painted). The JSON always names the classic file;
when the game loads a texture it passes the path through `GameConfig.styled_path()`,
which swaps in the style's subfolder if `"art_style"` in `game_config.json` asks for it
and the file exists. Changing style while the game runs is `Data.set_art_style()`, which
reloads the icons and emits `Events.art_style_changed` so the inventory slots redraw: the
same "emit a signal, let the UI react" pattern as everywhere else. How the painted look
itself is made is in [PAINTED_STYLE.md](PAINTED_STYLE.md).

---

## 11. A reading order for the code

Roughly 9,400 lines of GDScript (and 2,500 of tests). In this order, each file only depends
on ones you have already read. ([START_HERE.md](START_HERE.md) turns this into a checklist,
with what to notice in each file, questions and small experiments.)

1. `project.godot`: autoloads and input actions.
2. `scripts/core/hex.gd`, then `hex_grid.gd`: the grid everything stands on.
3. `scripts/autoload/game_config.gd`, `data_registry.gd`, `scripts/data/*.gd`: how JSON
   becomes definitions.
4. `scripts/rules/rules.gd`, `character_sheet.gd`, then `scripts/items/*.gd`: the rules and
   the item model. `inventory_ops.gd` is the heart of the inventory.
5. `scripts/autoload/game_state.gd`, `events.gd`, `save_manager.gd`, `audio.gd`.
6. `scripts/main.gd`, then `scripts/world/world.gd`: how a map is loaded and how input
   becomes orders.
7. `actor.gd`, then `party_member.gd`, `party_controller.gd`, `prop.gd`: walking,
   orders, interactions. Then `scripts/npc/npc.gd`.
8. `scripts/dialogue/` (`conditions.gd`, `effects.gd`, `dialogue.gd`, `dialogue_runner.gd`)
   and `scripts/quests/quest_def.gd`, with the quest half of `game_state.gd`.
9. `scripts/combat/`: `attack.gd`, `creature_def.gd`, `creature_sheet.gd`,
   `combat_rules.gd`, `combatant.gd`, then `combat_manager.gd` and `combat_ai.gd`; and
   `scripts/world/creature.gd`.
10. `terrain_renderer.gd` + `terrain_blend.gdshader`, `fog_of_war.gd` + `.gdshader`.
11. `scripts/ui/hud.gd`, then `portrait_card.gd`, `minimap.gd`, `inventory_screen.gd`,
    `item_slot.gd`, `dialogue_window.gd`, `journal_screen.gd`, `combat_hud.gd`,
    `game_menu.gd`, `save_load_screen.gd`.
12. `tests/integration/test_phase2.gd`, `test_phase3.gd` and `test_combat.gd`: the whole
    game driven from code.

Keep the game running while you read: hover with F3 on to see hex coordinates, and put
`print()` calls or breakpoints (click left of a line number in the script editor) in the
functions above to watch them fire.

---

## 12. Before you expand: what to learn next

### GDScript skills worth having

- **Static typing** (`var hp: int`, `func heal(amount: int) -> int`, `Array[ItemStack]`).
  The project is typed throughout; the editor then catches mistakes as you type and code
  runs faster. Learn how typed arrays and `Variant` interact (see [§13](#13-pitfalls-we-hit-so-you-dont-have-to)).
- **Signals and `await`**: `await get_tree().create_timer(1.0).timeout`, awaiting your own
  signals, and functions that become coroutines when they contain `await`.
- **`call_deferred`** for anything that changes the tree while signals are firing.
- **Resources** (`extends Resource`, `@export` properties, `.tres` files): an alternative
  to JSON when you want the editor's inspector to edit data. Dialogue trees and spells are
  good candidates if you prefer authoring in the editor; JSON stays better if a Python tool
  writes the data.
- **Scenes in the editor**: building UI panels visually (with `@onready var x := $Path`
  references) is often faster than the code-built HUD once layouts get complex. A dialogue
  window is a good first editor-built scene.

### Where the next phases plug in

**Phase 3 (done): how people were added**

This is the plan that was followed, kept here as a worked example of growing the
codebase. [DIALOGUE.md](DIALOGUE.md) and [NPCS_AND_QUESTS.md](NPCS_AND_QUESTS.md) have the
data formats.

- *An `Actor` base class* (`scripts/world/actor.gd`) took the sprite sheet, facing and
  smooth hex walking out of `PartyMember`. `PartyMember` and `Npc` both extend it. They
  override small virtual methods: `move_speed()`, `_can_stand(hex)` and
  `_on_hex_changed()`. That is how an NPC keeps its hex marked as occupied while it
  walks.
- *NPC data* (`data/npcs/npcs.json`, `NpcDef`) is separate from character sheets.
  Townsfolk don't need ability scores until combat, and a sheet can be linked later.
- *Dialogue* is a JSON graph walked by `DialogueRunner`, a `RefCounted` with no UI. The
  unit tests play whole conversations through it without a scene. Conditions and effects
  are small dictionaries interpreted by two static classes, so a new kind is one more
  `match` branch.
- *Quests* are ordered stages in `GameState.quests` (saved). Stages advance through
  dialogue effects, or by themselves through an `auto_if` condition checked whenever a
  character sheet changes.
- *Vendors* reuse the inventory screen: a shop is a `ContainerState` plus a "trade" terms
  dictionary on the slot references. `InventoryOps.move` sees the terms and buys or sells
  instead of moving.
- *The temple* is just dialogue: options gated on `{"fallen": true, "gold": 100}` with
  `take_gold` and `revive` effects. `GameState` watches every sheet's `changed` signal and
  emits `Events.party_defeated` when nobody is left standing.

**Phase 4, first half (done): how combat was added**

[COMBAT.md](COMBAT.md) has the rules and the data formats. The shape of the code:

- *A monster is a character sheet.* `CreatureSheet extends CharacterSheet`, filled from a
  stat block (`CreatureDef`). It overrides only what differs (armour class from the stat
  block, death at 0 HP). Everything that deals with hit points, saves and damage then
  works on both without `if monster:` branches. This is inheritance used for its proper
  job: a creature really *is* a sheet with a few rules changed.
- *Rules without positions.* `CombatRules` is static functions over sheets and numbers
  (attack rolls, damage dice, hit chances, damage types). The unit tests check it with a
  seeded `RandomNumberGenerator`, so "a 20 always crits" is a test, not a hope.
- *A coroutine for the turn loop.* `CombatManager._run()` is a `while` loop that `await`s:
  the player's End Turn (a signal), a creature's walk (`await actor.arrived`), a pause
  (`await get_tree().create_timer(...).timeout`). The flow of a round reads top to bottom
  instead of being spread over callbacks. `abort()` sets `active = false` and emits the
  awaited signal, so the loop wakes up, sees the flag and returns.
- *Per-turn state on a small object.* `Combatant` wraps an `Actor` and its sheet with
  movement left, action/bonus/reaction used, dodging, prone. It resets in
  `begin_turn()`.
- *Occupancy and strict steps.* During a fight every actor sets `occupies = true` (its
  hex is disabled in the A* graph) and `smooth_paths = false` (exact hex steps).
  `HexGrid.reachable_within()` is a small Dijkstra search that gives the shaded movement
  area and the cost of each hex.
- *Input routing.* `World` checks `combat.active` first: clicks become `player_move` or
  `player_attack`, and Space becomes End Turn. The HUD's `CombatHud` only listens to the
  manager's signals (`started`, `turn_started`, `state_changed`, `logged`, `hint_changed`).
- *Tests at speed.* `combat.animate = false` makes moves teleport and pauses vanish, so an
  integration test can play several rounds in a few frames. A fixed `rng.seed` makes the
  rounds repeatable.

**Phase 4, second half (done): how spells and abilities were added**

[SPELLS.md](SPELLS.md) has the rules and the data formats. The shape of the code:

- *Spells are data, effects are named.* `data/spells/spells.json` holds range, area,
  attack or save, damage or healing dice, and what higher slots add. `SpellDef` turns feet
  into hexes on loading. Only the handful of special effects (`sleep`, `bless`, `shield`,
  `teleport`...) need code, each a `match` branch; a new damage or healing spell is just
  a new entry.
- *Three layers, by what they need.* `Spellcasting` works on sheets alone (slots, DC,
  dice, healing, buffs), so the spells screen and the fight share it. `CombatSpells` adds
  positions (ranges, lines of sight, areas from `Hex.spiral` and a cone of dot products,
  the cursor preview). `CombatManager` keeps the turn: `use_ability()` either casts at
  once or enters *targeting*, and `World` sends the next click to `confirm_target()`.
  Spell attacks go through the same `attack_with` as swords, so advantage, critical hits,
  logging and the slain are handled once.
- *A class table, not class code.* `data/classes/classes.json` lists what each level
  grants; `Classes.grant(sheet)` adds what's missing, on loading and on levelling up.
  `Features` counts uses by "pool", so Turn Undead and Preserve Life both spend Channel
  Divinity without knowing about each other.
- *Conditions live on `Combatant`*, the per-fight object (asleep, turned, blessed, marked,
  Shield, concentration). Those that last beyond a fight (Mage Armor, Aid, Guidance) live
  on the sheet's `effects` and end on a long rest.
- *Saving a coroutine's state.* A turn loop that `await`s can't be saved as such, so
  `CombatManager.to_dict()` saves the *data* it works on (order, whose turn, each
  combatant's state, creature hit points and hexes) and `restore()` rebuilds it and
  starts the loop with `_run(true)`, which resumes the saved turn instead of starting a
  round. A generation counter, bumped on every start, restore and abort, plus
  `in_fight(c)` checks after each `await`, stop a turn left over from before a load from
  acting in the new fight.
- *Out of combat is its own small class.* `Abilities` casts from the spells screen and
  the inventory with no positions or action economy, using the same `Spellcasting`
  arithmetic.

**Attack effects (done): drawing with `_draw()`**

[COMBAT_FX.md](COMBAT_FX.md) has the details. The Godot ideas behind it:

- *Custom drawing.* `SwingFx`, `ProjectileFx` and `BurstFx` are plain `Node2D`s that
  override `_draw()` and use `draw_polygon` (with a colour per vertex, for the fading
  smear), `draw_line`, `draw_circle`, `draw_arc` and `draw_texture_rect`. A property with
  a setter that calls `queue_redraw()` (`progress`, `t`) makes them redraw whenever a
  `Tween` changes it, so the whole animation is one `tween_property` call.
- *`draw_set_transform`* rotates and squashes what follows (an icon along the swing, a
  dust ring flattened by the 45° view); set it back to identity afterwards.
- *Tweens on the sprite, not the node.* `Actor.nudge()` moves and scales only the child
  `Sprite2D`, so the actor's hex, position and hover ring stay put while it lunges, and
  `self_modulate` flashes it without disturbing a `modulate` fade.
- *Waiting without blocking.* The director (`CombatFx`) `await`s combat pauses between
  beats. Each effect animates itself, and nothing waits on a node that might be freed
  (a map change frees the effect layer), so a load mid-swing can't leave a coroutine
  hanging.

### Things to keep doing

- Put new tunables in `game_config.json`, not as constants.
- Emit `Events` signals for things the UI should react to; don't reach into the HUD.
- Keep rules in `RefCounted` classes with tests; keep nodes thin.
- When something is saved, test the round trip.

---

## 13. Pitfalls we hit, so you don't have to

- **Don't name a method `get_stack()`**: it is a built-in GDScript function (the call
  stack), and the parser then rejects calls to yours. The same goes for other built-ins
  such as `print`, `str`, `range`, `len` and `load`. Also avoid reusing the names of the
  base class's own methods (`get_name`, `get_class`...).
- **"The shortest way round" isn't always the way you want.** `lerp_angle` takes the
  shorter turn between two angles, so an overhead blow aimed down-left swung over the
  wrong shoulder. When the direction matters, unwrap the end angle (add or take away
  2π) and use `lerpf` (see `SwingFx._sweep`).
- **Typed arrays and ternaries**: `var a: Array[Vector2i] = [x] if c else other` fails,
  because `[x]` is an untyped `Array`. Build the typed array first and `append`.
- **Multi-line lambdas inside a call's parentheses** are easy to get wrong; prefer a named
  method and `connect(_on_thing.bind(arg))`.
- **Nodes made but never added to the tree leak.** A `Label` built in `_ready()` "for
  later" and only added on demand is never freed if it is never added: the headless test
  run reports it as leaked `CanvasItem`s at exit. Add it straight away (hidden if need
  be).
- **Freeing nodes from inside their own signals** crashes or misbehaves. Use
  `call_deferred` (see `Main._on_map_change_requested`).
- **Mouse positions**: an event's `position` is in viewport (screen) space. Convert with
  `get_viewport().get_canvas_transform().affine_inverse() * pos` before comparing with
  world positions.
- **UI eating clicks, or not**: every `Control` defaults to `MOUSE_FILTER_STOP`. Labels and
  decorative panels inside clickable areas need `MOUSE_FILTER_IGNORE`; panels that must
  block the map need `STOP`.
- **Headless mode** (tests, servers) has no renderer: `RenderingServer.frame_post_draw`
  never fires and viewport images are empty. Check `DisplayServer.get_name() == "headless"`
  before waiting on drawing.
- **Integer division** warns (`5 / 2` is 2). Divide by `2.0`, or add
  `@warning_ignore("integer_division")` when integer division is intended.
- **JSON numbers are floats**: `JSON.parse_string("3")` gives `3.0`. Wrap reads in `int()`
  where an integer is meant, as the parsers here do.
- **Freed nodes in typed arrays**: `array.has(node)` on an `Array[Node2D]` raises an error
  if `node` has been freed. Check `is_instance_valid(node)` first.
- **Disabled A\* points are forgotten on rebuild**: `HexGrid.rebuild_pathfinding()`
  re-creates the points, so it re-applies the occupied hexes afterwards. Any state you
  keep "on top of" an `AStar2D` needs the same care.
- **Timers ignore the pause by default**: `get_tree().create_timer(t)` keeps counting while
  the tree is paused (its `process_always` argument defaults to true). The combat's pauses
  use `create_timer(t, false)`, so opening the menu really stops a creature mid-turn.
- **Casting a literal to a typed array**: `[step] as Array[Vector2i]` does not make a typed
  array. Declare it: `var one: Array[Vector2i] = [step]`.
- **`%` with an Array**: `"seen: %s" % some_array` treats the array as the list of format
  arguments. Wrap it: `"seen: %s" % [some_array]`.
- **Fog drawn over tall sprites**: fog is per hex, but a building's roof is drawn over the
  hexes behind it. `FogOfWar` reveals the hexes under a building's picture together with
  the building (`Prop.covered_hexes()` samples the sprite's alpha), so roofs don't vanish
  into the dark.

---

## 14. Glossary and further reading

| Term | Meaning |
|---|---|
| Autoload | A script or scene created at start-up and reachable by name everywhere. |
| CanvasItem | Base of everything 2D that draws (Node2D and Control). |
| CanvasLayer | A separate 2D drawing layer, unaffected by the world camera. |
| Control | Base of UI nodes. |
| Definition / instance | Shared, read-only type (`ItemDef`) versus a mutable copy (`ItemStack`). |
| Deferred call | A call queued to run at the end of the current frame. |
| RefCounted | An object freed automatically when unreferenced; not in the scene tree. |
| Signal | An event an object emits and others connect to. |
| Splat map | Texture whose channels are blend weights between terrains. |
| Y-sort | Drawing children in order of their y position, for depth. |

Official documentation (godotengine.org/docs, "stable" version):

- *Getting started → Step by step*: nodes, scenes, scripting, signals.
- *Scripting → GDScript reference* and *Static typing in GDScript*.
- *Tutorials → 2D*: canvas layers, custom drawing in 2D, 2D movement.
- *Tutorials → UI*: containers, themes, size and anchors.
- *Tutorials → Shaders → Your first 2D shader* and the *CanvasItem shaders* reference.
- *Tutorials → Inputs*: the InputEvent page explains the event order used above.
- *Tutorials → I/O → Saving games*.

And for hexes, Red Blob Games: *Hexagonal Grids* (redblobgames.com/grids/hexagons).
