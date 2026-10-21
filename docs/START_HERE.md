# Start here: a study path through Lantern's Embrace

This is a checklist for learning how the game is built, in the order that makes each step
easy. Work down it stop by stop. Each stop says **what to read**, **which files to open**,
**what to notice**, a few **questions to check yourself**, and a small **experiment** to
try. Tick the boxes as you go (GitHub and most Markdown editors render `- [ ]` as a
checkbox; in a plain text editor, change `[ ]` to `[x]`).

The other documents go deeper on each topic. This one tells you **where to go next**. At
the end, [Where do I find...?](#where-do-i-find) is a lookup table for when you already
know what you want to change.

**Two tips before you start**

- Keep the game open while you read. Most stops ask you to look at something in the running
  game, or to put a `print()` in a function and watch it fire.
- Experiments are meant to be undone. Make them, look, then put the file back with
  `git checkout -- <file>` (or `git stash`).

---

## Stop 0: get it running

- [ ] Install **Godot 4.7** (the standard build, not .NET) and import `project.godot`
      (README, [Running it](../README.md#running-it)).
- [ ] Press **F5** and play for ten minutes. Use the list in
      [What to try](../README.md#what-to-try): cross the bridge, go into the inn, open a chest,
      talk to Tobin, open the journal (J), and pick a fight with the wolves in the north-west
      woods.
- [ ] Press **F1** for the controls, **F3** for the hover info panel (hex coordinates,
      terrain) and **G** for the hex grid. You will use F3 and G throughout.
- [ ] Run the tests once: `tools/run_tests.sh /path/to/godot`. Note that all of them pass,
      so you can tell later if an experiment broke something.

**Check yourself:** can you name the four party members and which one is the rogue? Do you
know which key ends a turn in a fight?

---

## Stop 1: the map of the project

- [ ] Read the README's [Project layout](../README.md#project-layout) and
      [How the pieces fit](../README.md#how-the-pieces-fit).
- [ ] New to Godot? Read [GODOT_GUIDE.md](GODOT_GUIDE.md) section **1. Godot in one page**
      now (nodes, scenes, signals, autoloads, input, pausing). Come back here after.
- [ ] Read GODOT_GUIDE section **2. The shape of this project**: the four layers
      (data → rules and state → world → interface) and the definition/instance split.
- [ ] Open `project.godot` in a text editor. Find:
  - [ ] `run/main_scene`: the scene that starts the game (`scenes/main.tscn`).
  - [ ] `[autoload]`: the six global singletons, in load order: `GameConfig`, `Data`,
        `GameState`, `Events`, `Audio`, `SaveManager`.
  - [ ] `[input]`: every key binding by action name (`toggle_journal`, `quicksave`...).
- [ ] Open `scenes/main.tscn` and `scripts/main.gd`. The whole game is one scene: a `World`
      and a `HUD`. `main.gd` loads the first map and handles map changes.

**Check yourself:** which autoload holds the party and the purse? Which one is only a list of
signals? Why must `GameConfig` load before `Data`?

**Try it:** in `project.godot`, find the `toggle_journal` action and note its key. (Changing
keys is easiest in the editor: Project → Project Settings → Input Map.)

---

## Stop 2: the data the game is made of

Almost everything you see comes from JSON under `data/`. Learning the data first makes the
code much easier to read.

- [ ] Skim GODOT_GUIDE section **7. Data-driven content**.
- [ ] Open each of these and get a feel for the shape (you don't need to read every line):
  - [ ] `data/config/game_config.json`: global tunables (speeds, hex size, fog, camera).
  - [ ] `data/terrain/terrain.json` and `data/props/props.json`: what the ground and the
        objects on it are.
  - [ ] `data/maps/millbrook_outskirts.json`: the village, as rows of text plus a list of
        props, townsfolk and creatures. Read [MAPS.md](MAPS.md) alongside it.
  - [ ] `data/items/items.json` with [ITEMS.md](ITEMS.md).
  - [ ] `data/characters/garrick.json` with [CHARACTER_SHEETS.md](CHARACTER_SHEETS.md), and
        `data/party/starting_party.json`.
  - [ ] `data/npcs/npcs.json`, `data/dialogue/tobin.json`, `data/quests/quests.json`.
  - [ ] `data/creatures/creatures.json`.
  - [ ] `data/audio/audio.json`.
- [ ] Now see how it is loaded: `scripts/autoload/game_config.gd`, then
      `scripts/autoload/data_registry.gd` (`reload()` loads everything; `load_texture()`
      never returns null), then the parsers in `scripts/data/` (`terrain_def.gd`,
      `prop_def.gd`, `map_data.gd`) and `scripts/core/json_util.gd`.

**Check yourself:** what does the letter `f` mean in a map's terrain rows? Where does a
house's door position come from? What is the difference between `Data.characters` and
`GameState.party`?

**Try it:** in `data/config/game_config.json`, double `explore_move_speed`, run, and watch
the party hurry. Put it back.

---

## Stop 3: the hex grid

Everything stands on hexes: movement, fog, doors and fights.

- [ ] Read GODOT_GUIDE section **4. Hex grids** (and Red Blob Games' *Hexagonal Grids* if
      hexes are new to you).
- [ ] Open `scripts/core/hex.gd`: axial and offset coordinates, `neighbors`, `distance`,
      `line`, `spiral`, `to_pixel`/`from_pixel`.
- [ ] Open `scripts/core/hex_grid.gd`: terrain per hex, prop blockers, `is_walkable`,
      `move_cost`, A* pathfinding (`rebuild_pathfinding`, `find_path`), occupied hexes
      (`set_occupied`) and the movement range search used in fights (`reachable_within`).
- [ ] Read the tests that pin these down: `tests/unit/test_hex.gd`,
      `tests/unit/test_hex_grid.gd`.

**Check yourself:** a map file says `"at": [64, 30]`. Is that axial or offset? Which function
converts it? Why does a path through shallow water cost more than one around it?

**Try it:** in the game press **G** and **F3**, hover a few hexes and compare the `q, r`
(axial) and `col, row` (offset) numbers.

---

## Stop 4: rules, items and state (no nodes yet)

This layer is plain GDScript classes (`RefCounted`), so it can be tested without a scene.

- [ ] `scripts/rules/rules.gd`: the 5e numbers (ability modifiers, proficiency, armour
      class, dice with `roll_expr`).
- [ ] `scripts/rules/character_sheet.gd`: a character loaded from JSON. Look at
      `from_dict`/`to_dict`, `recalculate`, `damage`/`heal`/`roll_death_save`, `add_xp`.
- [ ] The item model in `scripts/items/`: `item_def.gd` (a kind of item), `item_stack.gd`
      (a quantity of it), `inventory.gd` (a row of slots), `container_state.gd` (a chest's
      contents) and `inventory_ops.gd`, the heart of it: `move`, `give`, `take_all`, `buy`,
      `sell` and `use`. Every drag on the inventory screen ends up in `InventoryOps.move`.
- [ ] `scripts/autoload/game_state.gd`: the playthrough (party, gold, flags, quests, per-map
      containers, explored fog, slain creatures) and `to_dict`/`load_dict`.
- [ ] `scripts/autoload/events.gd`: the signal hub. Read the comments on each signal.
- [ ] Tests: `tests/unit/test_rules.gd`, `test_items.gd`, `test_fog_and_state.gd`.

**Check yourself:** why is Garrick's armour class 19? What stops Elowen equipping a shield?
Where does picked-up gold go?

**Try it:** in `data/items/items.json`, make `potion_of_healing` heal `"10d4+2"`, drink one in
the game (right-click it in the inventory, I) and watch the HP. Put it back.

---

## Stop 5: the world on screen

- [ ] Read GODOT_GUIDE section **3. Following a click**: *A move order*, *Opening a chest* and
      *Walking through a door*.
- [ ] Open `scripts/world/world.gd` and follow `load_map()` from top to bottom: grid, props,
      ground piles, terrain or backdrop, townsfolk, creatures, party, fog, camera, audio.
      Then `_unhandled_input` → `_on_mouse_button` → `_on_click`.
- [ ] `scripts/world/party_controller.gd`: selection, `move_selected_to`, `interact_with`,
      `_on_member_arrived`.
- [ ] `scripts/world/actor.gd`: anything that walks: the sprite sheet, `follow_path`, the
      smoothed walking in `_process` and `_farthest_clear_index`. Then
      `scripts/world/party_member.gd` (a party member on the map).
- [ ] `scripts/world/prop.gd`: a placed object and its interactions (`interact`,
      `_open_container`, doors and exits).
- [ ] Drawing: GODOT_GUIDE section **5. Drawing the world**, then
      `scripts/world/terrain_renderer.gd` with `terrain_blend.gdshader`,
      `scripts/world/fog_of_war.gd` with `fog_of_war.gdshader`, `game_camera.gd`,
      `cursor_overlay.gd` (hover hex, path preview, movement range) and
      `scripts/ui/color_grade.gd`.
- [ ] Tests: `tests/integration/test_party_movement.gd` drives all of this from code.

**Check yourself:** what happens, function by function, between clicking a chest and its
contents appearing? Why does a map change go through `call_deferred`?

**Try it:** add `print("move to ", target)` at the top of `PartyController.move_selected_to`,
run, click around and watch the Output panel.

---

## Stop 6: the interface

- [ ] Read GODOT_GUIDE section **6. The interface** (Control nodes, drag and drop, tooltips).
- [ ] `scripts/ui/hud.gd`: everything on screen is built in code in `_build()`. Notice
      `_unhandled_input` (keys), `_enter_modal`/`_on_modal_closed` (pausing for windows)
      and the `Events` connections in `_ready`.
- [ ] Then the parts: `portrait_card.gd`, `minimap.gd`, `inventory_screen.gd` with
      `item_slot.gd`, `game_menu.gd`, `save_load_screen.gd`, `dialogue_window.gd`,
      `journal_screen.gd`, `combat_hud.gd`, and the colours in `ui_theme.gd`.

**Check yourself:** how does the HUD learn that the selection changed, without the world
knowing the HUD exists? What pauses the game when the inventory opens?

**Try it:** change `GOLD` in `scripts/ui/ui_theme.gd` to another colour and run.

---

## Stop 7: places (interiors, doors, containers, things on the ground)

- [ ] [MAPS.md](MAPS.md): *Moving between maps*, *Interiors* and *Furnishing add-ons*.
- [ ] `data/maps/millbrook_inn.json`: a backdrop image plus furniture props and a way out.
- [ ] The generators that write the maps: `tools/maps/generate_millbrook.py`,
      `tools/maps/generate_interiors.py` (rooms, furniture, add-ons, who lives where) and
      `tools/maps/generate_old_temple_road.py`.
- [ ] Items on the ground: `World.ground_pile`, `_on_pile_changed` and `_seed_item_pile` in
      `world.gd` (the reeve's key by the well is one).
- [ ] Tests: `tests/integration/test_phase2.gd`; `tests/unit/test_data.gd` checks every map.

**Check yourself:** how does the party know where to stand when it comes out of a building?
Why is the reeve's key not put back after you pick it up and reload the map?

**Try it:** in `generate_interiors.py`, add an item to the miller's drawers, run
`python3 tools/maps/generate_interiors.py`, then open the drawers in the game.

---

## Stop 8: people (townsfolk, dialogue, quests, shops, the temple)

- [ ] Read GODOT_GUIDE *Talking to someone* (section 3), then [DIALOGUE.md](DIALOGUE.md) and
      [NPCS_AND_QUESTS.md](NPCS_AND_QUESTS.md).
- [ ] `scripts/npc/npc_def.gd` and `scripts/npc/npc.gd` (an `Actor` that strolls, blocks
      its hex and starts conversations).
- [ ] `scripts/dialogue/`: `dialogue.gd` (load and check a file), `conditions.gd`,
      `effects.gd`, then `dialogue_runner.gd` (`start`, `options`, `choose`).
- [ ] `scripts/quests/quest_def.gd`, and the quest functions in `game_state.gd`
      (`set_quest_stage`, `check_quests`, `award_xp`).
- [ ] Shops: `open_shop` in `inventory_screen.gd` and `buy`/`sell` in `inventory_ops.gd`.
- [ ] Tests: `tests/unit/test_dialogue_and_quests.gd`, `tests/integration/test_phase3.gd`.

**Check yourself:** why does Aldous greet you differently once you carry his key? Where is the
price of a torch at Tobin's worked out? What does `"auto_if"` do in a quest?

**Try it:** add a new option to the `greet` node in `data/dialogue/pip.json` that goes to a
new node with a line of your own. Run the tests: `test_every_npc_and_dialogue_is_sound`
catches a broken `goto`.

---

## Stop 9: combat

- [ ] Read [COMBAT.md](COMBAT.md) for the rules, then GODOT_GUIDE *A fight* (section 3) and
      *Phase 4, first half* (section 12).
- [ ] In `scripts/combat/`, in this order: `attack.gd`, `creature_def.gd`,
      `creature_sheet.gd`, `combat_rules.gd` (`weapon_attacks`, `hit_chance`, `roll_attack`,
      `roll_damage`), `combatant.gd`, then `combat_manager.gd` (`start`, the turn loop
      `_run`, `move_along`, `attack_with`, `player_move`, `player_attack`) and
      `combat_ai.gd` (`take_turn`).
- [ ] On the map: `scripts/world/creature.gd`; and in `world.gd` the functions
      `hostiles_noticing`, `start_combat`, `on_creature_slain` and `_on_combat_click`.
- [ ] On screen: `scripts/ui/combat_hud.gd` and `scripts/world/floating_text.gd`.
- [ ] Tests: `tests/unit/test_combat_rules.gd` (seeded dice) and
      `tests/integration/test_combat.gd` (whole fights with `combat.animate = false`).

**Check yourself:** why can a `CreatureSheet` be passed anywhere a `CharacterSheet` is
expected? What makes the turn loop wait for you to press Space? What happens when a party
member reaches 0 HP?

**Try it:** in `data/creatures/creatures.json`, give the wolf `"hp": 1` and fight the pack.
Then set its `"aggro"` to `20` and see how early they come for you. Put both back.

---

## Stop 10: saving and loading

- [ ] Read GODOT_GUIDE section **8. Saving and loading**.
- [ ] `scripts/autoload/save_manager.gd` (`save_game`, `load_game`, the slots) and
      `GameState.to_dict`/`load_dict` (which call `CharacterSheet.to_dict`/`from_dict`).
- [ ] Save a game, then open the file. Saves are JSON in `user://saves` (on Linux
      `~/.local/share/godot/app_userdata/Lantern's Embrace/saves/`; the
      [CHARACTER_SHEETS.md](CHARACTER_SHEETS.md) table lists the folder on every OS).

**Check yourself:** where in a save file are the slain wolves remembered? Why can't you save
in the middle of a fight?

---

## Stop 11: art and sound

- [ ] Read GODOT_GUIDE section **10. The asset pipeline**, then [ASSETS.md](ASSETS.md) and
      [AUDIO.md](AUDIO.md).
- [ ] Blender, driven from Python: `tools/art/blender/render_all.py` (the entry point),
      `lib.py` (camera, lights, render helpers), then one renderer that interests you:
      `render_props.py` (trees, houses, the temple, camp gear), `render_characters.py`
      (posable figures and the wolf, walk cycles, sprite sheets), `render_interiors.py`
      (room backdrops, furniture), `render_items.py` (icons) or `render_terrain.py`.
- [ ] The painted item icons: read [PAINTED_STYLE.md](PAINTED_STYLE.md), which walks one
      shield through the whole look step by step. Then `painted.py` (materials and lights),
      `paint_filter.py` (the brush-stroke pass) and `render_items_painted.py` (the models).
      The game picks a style with `GameConfig.styled_path()`.
- [ ] Portraits: `tools/art/portraits/make_portraits.py` and `portraits.json` (crops of CC0
      paintings).
- [ ] Sound: `tools/audio/generate_placeholder_audio.py`, and `scripts/autoload/audio.gd`
      (sounds are asked for by name, never by file).

**Check yourself:** if you replace `assets/props/well.png` with your own picture, what else
needs updating so it stands in the right place? How would you swap the village music for a
real recording?

**Try it:** press Esc in the game and click **Item icons** to flip between the classic and
painted icons, then open the inventory. With the Blender module set up as in ASSETS.md,
`.venv-art/bin/python tools/art/blender/render_all.py props:campfire` re-renders one prop.

---

## Stop 12: the tests

- [ ] Read GODOT_GUIDE section **9. Testing**.
- [ ] `tests/test_runner.gd` (finds and runs every `test_*.gd`, and fails a test on any
      engine error) and `tests/test_case.gd` (`check`, `check_eq`).
- [ ] Read one unit test file and one integration test file side by side, for example
      `tests/unit/test_items.gd` and `tests/integration/test_phase2.gd`. Notice how
      integration tests load `scenes/main.tscn` and drive the real game.

**Try it:** add `check_eq(1 + 1, 3, "arithmetic")` to any test, run the suite, read the
failure, then remove it.

---

## Stop 13: ready to build on it

- [ ] Read GODOT_GUIDE section **12. Before you expand** and **13. Pitfalls we hit**.
- [ ] Do one small change end to end. Each needs only the files listed:
  - [ ] **A new item:** `data/items/items.json` (+ an icon, or reuse one), and put it in a
        chest via a map or `generate_interiors.py`. See [ITEMS.md](ITEMS.md).
  - [ ] **A new sign:** a `"sign"` entry in a map's `props` with `title` and `text`.
  - [ ] **A new townsperson:** `data/npcs/npcs.json`, a file in `data/dialogue/`, and
        `{"id", "at"}` in a map's `"npcs"`. See [NPCS_AND_QUESTS.md](NPCS_AND_QUESTS.md).
  - [ ] **A new quest:** `data/quests/quests.json` plus dialogue effects to start and finish
        it.
  - [ ] **A new encounter:** creatures in a map's `"creatures"` list with a shared
        `group`, and optionally a quest stage with `"auto_if": {"defeated": "<group>"}`. See
        [COMBAT.md](COMBAT.md).
  - [ ] **A new party member:** `tools/make_character.py`, then add the id to
        `data/party/starting_party.json`. See [CHARACTER_SHEETS.md](CHARACTER_SHEETS.md).
- [ ] Run the tests after each change.

---

## Where do I find...?

| I want to... | Look in |
|---|---|
| Change walking speed, hex size, fog sight, camera limits, the colour grade | `data/config/game_config.json` (`explore_move_speed`, `hex_radius`, `fog_of_war`, `camera`, `post`) |
| Change who is in the party at the start | `data/party/starting_party.json` |
| Change a character's stats, gear or portrait | `data/characters/<id>.json` ([CHARACTER_SHEETS.md](CHARACTER_SHEETS.md)) |
| Change an item's numbers, price or icon | `data/items/items.json` ([ITEMS.md](ITEMS.md)) |
| Change a key binding | `project.godot` → `[input]` (or Project Settings → Input Map); the F1 help text is `HELP_TEXT` in `scripts/ui/hud.gd` |
| Change the village layout | `tools/maps/generate_millbrook.py`, then run it (or edit `data/maps/millbrook_outskirts.json` by hand) |
| Change a room's furniture or who lives in it | `tools/maps/generate_interiors.py`, then run it |
| Change the Old Temple Road | `tools/maps/generate_old_temple_road.py`, then run it |
| Change what a prop is (blocks movement, sight, door, interaction) | `data/props/props.json` |
| Change what someone says | `data/dialogue/<npc>.json` ([DIALOGUE.md](DIALOGUE.md)) |
| Change a shop's stock or prices | `"vendor"` in `data/npcs/npcs.json` |
| Change a quest | `data/quests/quests.json` ([NPCS_AND_QUESTS.md](NPCS_AND_QUESTS.md)) |
| Add a dialogue condition or effect | `scripts/dialogue/conditions.gd`, `scripts/dialogue/effects.gd` |
| Change a monster's stats or loot | `data/creatures/creatures.json` ([COMBAT.md](COMBAT.md)) |
| Change how monsters fight | `scripts/combat/combat_ai.gd` |
| Change attack, damage or death-save rules | `scripts/combat/combat_rules.gd`, `scripts/rules/character_sheet.gd` |
| Change what a turn allows (actions, opportunity attacks) | `scripts/combat/combat_manager.gd`, `scripts/combat/combatant.gd` |
| Change armour class or other 5e numbers | `scripts/rules/rules.gd` |
| Change how dragging items works | `scripts/items/inventory_ops.gd` (`move`) |
| Change how the party walks or picks spots | `scripts/world/actor.gd`, `scripts/world/party_controller.gd` |
| Change what clicking does | `scripts/world/world.gd` (`_on_click`, `_on_combat_click`) |
| Change the fog of war | `scripts/world/fog_of_war.gd` and `fog_of_war.gdshader` |
| Change how the ground is painted | `scripts/world/terrain_renderer.gd` and `terrain_blend.gdshader` |
| Change the sidebar, windows or combat bar | `scripts/ui/` (`hud.gd` builds the layout) |
| Change what is saved | `GameState.to_dict`/`load_dict` in `scripts/autoload/game_state.gd` |
| Replace art | the PNGs under `assets/` (same names), or re-render with `tools/art/blender/` ([ASSETS.md](ASSETS.md)) |
| Switch the item icons between classic and painted | `"art_style"` in `data/config/game_config.json` ([PAINTED_STYLE.md](PAINTED_STYLE.md)) |
| Change how the painted icons look | `tools/art/blender/painted.py` and `paint_filter.py` ([PAINTED_STYLE.md](PAINTED_STYLE.md), section 8) |
| Replace a sound or the music | the files under `assets/audio/`, or point `data/audio/audio.json` elsewhere ([AUDIO.md](AUDIO.md)) |
| Find a function by name | your editor's project search, or `grep -rn "func name" scripts/` |

## The documents, and when to read them

| Document | Read it for |
|---|---|
| [README.md](../README.md) | What the game does, controls, what to try, the project layout |
| **START_HERE.md** (this file) | The order to study things in, and where things live |
| [GODOT_GUIDE.md](GODOT_GUIDE.md) | How it all works, with Godot explained along the way |
| [MAPS.md](MAPS.md) | The map format, props, doors and exits, interiors, generators |
| [ITEMS.md](ITEMS.md) | Items, equipment rules, the inventory screen, containers |
| [CHARACTER_SHEETS.md](CHARACTER_SHEETS.md) | Party member JSON and `make_character.py` |
| [DIALOGUE.md](DIALOGUE.md) | Conversation files, conditions and effects |
| [NPCS_AND_QUESTS.md](NPCS_AND_QUESTS.md) | Townsfolk, quests, shops, the temple |
| [COMBAT.md](COMBAT.md) | Fights, creatures, the AI |
| [ASSETS.md](ASSETS.md) | Where the art comes from and how to replace or re-render it |
| [PAINTED_STYLE.md](PAINTED_STYLE.md) | The painted item icons: switching styles, and how the look is made, with the maths |
| [AUDIO.md](AUDIO.md) | Sounds, music and ambience |
