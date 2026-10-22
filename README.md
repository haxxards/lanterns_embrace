# Lantern's Embrace

A party-based RPG skeleton for **Godot 4.7** (GDScript), in the spirit of the classic
isometric party RPGs: a sidebar of portraits, a party you steer around towns and
wilderness, and everything snapped to a **fixed hex grid**. Exploration is real-time;
combat will switch to turn-based when a fight starts.

The goal of this repository is to be a *core engine*: each system exists in a minimal,
data-driven form you can extend, not a finished game.

![Village overview](docs/images/phase1_overview.jpg)
![A fight at the bandit camp: initiative along the top, the combat log and action bar below](docs/images/phase4_fight.jpg)
![Choosing where to move: the shaded hexes are within this turn's movement](docs/images/phase4_move.jpg)
![Aiming Burning Hands: the cone catches two bandits, with spell buttons in the combat bar](docs/images/phase4_burning_hands.jpg)
![The spells and abilities screen: Odran choosing whom to heal with Cure Wounds](docs/images/phase4_spells_screen.jpg)
![Talking to the innkeeper behind his bar](docs/images/phase3_dialogue.jpg)
![The Temple of the Dawn: Father Anselm offers to raise a fallen companion](docs/images/phase3_temple.jpg)
![Buying from the innkeeper](docs/images/phase3_shop.jpg)
![Inventory and paper doll with a shelf of remedies open](docs/images/phase2_inventory.jpg)
![The party crossing the bridge](docs/images/walk.gif)

New to the project and want to study how it is made? Start with
**[docs/START_HERE.md](docs/START_HERE.md)**, a step-by-step checklist that takes you through
the code and data in order and has a "where do I find..." table. It leans on
**[docs/GODOT_GUIDE.md](docs/GODOT_GUIDE.md)**, which explains how everything works, with
Godot explained along the way.

## Status: Phase 4 complete (combat, spells and abilities)

### Attack animations (samples to build on)

- **Melee attacks swing the weapon, ranged attacks shoot, spells fly.** The attacker leans
  back and lunges; a swing smear sweeps from their shoulder with the equipped weapon's
  icon along its edge (slash, overhead smash, thrust, punch, or a wolf's bite); arrows
  and thrown daggers fly on an arc from the hand; Fire Bolt and Guiding Bolt fly from the
  staff or hand; and Magic Missile's darts fan out and strike one by one. Hits flash and
  flinch the target, misses make it sidestep, and the damage appears as the blow lands.
- Effects start from the characters' hands, exported from the 3D models for every facing.
  An `"fx"` entry in the item, creature or spell data changes how an attack looks. See
  [docs/COMBAT_FX.md](docs/COMBAT_FX.md), which also explains how to add an effect.

![A sword swing](docs/images/fx_sword.gif) ![Magic Missile](docs/images/fx_magic_missile.gif)

### Phase 4, second half: spells and abilities

- **Spellcasting** (5e SRD): Elowen the wizard and Odran the cleric cast 16 spells, from
  data in [`data/spells/spells.json`](data/spells/spells.json): Fire Bolt, Sacred Flame,
  Guidance, Spare the Dying, Magic Missile, Burning Hands, Sleep, Shield, Mage Armor, Bless,
  Cure Wounds, Healing Word, Guiding Bolt, and from level 3 Scorching Ray, Misty Step and
  Aid. Spell attack bonus and save DC from the casting ability, cantrips that grow at
  levels 5, 11 and 17, and casting with a higher slot for more dice, darts or targets.
  See [docs/SPELLS.md](docs/SPELLS.md).
- **Spell slots** from the SRD full-caster table, shown as pips on the portraits, the
  spells screen and the combat bar; they come back on a long rest.
- **Casting in a fight:** spell, feature and scroll buttons in the combat bar (greyed out
  with the reason when they can't be used). Targeted spells preview on the map: areas (a
  circle for Sleep, a 60° cone for Burning Hands) light up amber, or red when the cast won't work, with who would be
  caught and the chance to hit. Conditions (asleep, turned, blessed, marked by Guiding
  Bolt), concentration with Constitution saves, the bonus-action spell rule, and Shield
  cast for the wizard as a reaction when it would turn a hit into a miss.
- **Class features from a class table** ([`data/classes/classes.json`](data/classes/classes.json)),
  gained on level-up with the new spells and slots: Second Wind and Action Surge (fighter),
  Expertise and Cunning Action (rogue), Arcane Recovery (wizard), Disciple of Life and
  Channel Divinity: Turn Undead and Preserve Life (Life cleric).
- **Spells and abilities screen** (B, or the sidebar's Spells button): each member's casting
  numbers, slots, hit dice, spells, features and scrolls, with healing and lasting spells
  (and Second Wind, Preserve Life) usable outside a fight.
- **Resting** (R, or the sidebar's Rest button): a short rest spends hit dice and brings
  back short-rest features; a long rest restores everything but needs a roof (indoors, or
  a room at Tobin's inn). Not with enemies about.
- **Spell scrolls** (Cure Wounds, Magic Missile, Burning Hands), with icons in both art
  styles: read by anyone with the spell on their class list, no slot needed. Wenna sells
  them and two chests on the Old Temple Road hold them.
- **Sleep and Hold Person, shown on the figures:** a glittering mist settles and sleepers
  lie down under a drifting Zzz (an ally can spend an action to wake them); Hold Person
  binds a humanoid in bands of light until it saves at the end of a turn or the caster's
  concentration breaks. Every creature now has a type and race (wolves are beasts, bandits
  humans, skeletons undead; elves can't be magically slept), and spells say who they work
  on, so Hold Person refuses a wolf and the cursor says why. Elowen starts with a scroll
  of Hold Person to try it. See [docs/SPELLS.md](docs/SPELLS.md#sleep-and-hold-person).
- **The rest of combat:** thrown weapons (Wren throws her dagger when she can't reach; it
  lands at the target's feet), **getting away** from a fight by breaking line of sight or
  distance, and **saving mid-fight** on a party member's turn (the fight resumes on load).

### Painted item icons

- **Two looks for every item icon:** the original *classic* renders, and a *painted* set
  with more detailed models, worn edges, grime in the crevices, warm and cool light, brush
  strokes and an inked outline, closer to hand-painted fantasy RPG icons. `"art_style"` in
  `game_config.json` picks one, and the Esc menu's **Item icons** button flips between
  them in the game. [docs/PAINTED_STYLE.md](docs/PAINTED_STYLE.md) explains, step by step
  and with the maths, how the look is made and how its settings were chosen.

![Item icons, classic and painted](docs/images/painted_style/icons_compared.png)

### Phase 4, first half: combat

- **Turn-based fights on the hex grid** (5e, simplified). When creatures see the party
  within their aggro range, everyone rolls initiative and takes turns: movement up to their
  speed (difficult ground costs double), one action (Attack, Dash, Dodge, Disengage, or a
  potion), an off-hand attack as a bonus action with two light weapons, and a reaction for
  opportunity attacks. Click a shaded hex to move, an enemy to attack (stepping up first if
  needed), Space to end the turn. See [docs/COMBAT.md](docs/COMBAT.md).
- **The 5e attack rules:** d20 + bonus against AC, natural 1s and 20s, critical hits,
  advantage and disadvantage (prone, dodging, long range, shooting with an enemy adjacent,
  Pack Tactics), damage vulnerabilities and immunities, ammunition, versatile weapons,
  Sneak Attack, and the Defense fighting style. Hovering an enemy shows the attack and its
  chance to hit.
- **Down, dying and dead:** at 0 HP a party member falls unconscious and makes death saving
  throws on their turns. Any healing gets them up; three failures (or massive damage) and
  only the temple can raise them. The fight is lost only when nobody is left standing.
- **Enemies:** wolves, bandits, bandit archers, skeletons and skeleton archers, from SRD
  stat blocks in [`data/creatures/creatures.json`](data/creatures/creatures.json), with
  rendered, animated sprites. Melee foes close in on the most wounded (wolves hunt as a
  pack); archers keep their distance and shoot.
- **Victory** shares the slain creatures' XP, and they drop their loot on the ground. The
  dead stay dead (in saves too), and beaten groups can complete quests.
- **The combat interface:** an initiative strip along the top, an action bar with movement
  and actions left, a combat log, the reachable hexes shaded, floating damage numbers,
  health bars over enemies, and a few new sounds.
- **New places and quests:** a wolf pack in the woods north-west of Millbrook (Aldous pays a
  bounty), and the **Old Temple Road**, a new map reached from the waymarker at the end of
  the east road, where bandits hold a camp (Bram wants the road open) and skeletons walk
  in a ruined temple (Father Anselm asks you to give them rest).

### Phase 3: people

- **Townsfolk:** seven NPCs with their own rendered, animated sprites and painted portraits:
  an innkeeper behind his bar, a bard, a blacksmith, a herbalist, a miller, the reeve and
  a priest. They stroll near their spots, block the hex they stand on, turn to face you,
  and are hidden in the fog like everything else. Defined in
  [`data/npcs/npcs.json`](data/npcs/npcs.json), see
  [docs/NPCS_AND_QUESTS.md](docs/NPCS_AND_QUESTS.md).
- **Branching dialogue**, in-house (no addons): JSON conversation graphs with conditions
  (flags, quests, items, gold, who's in the party, who's talking, someone hurt or fallen)
  and effects (items, gold, quest stages, XP, healing, raising the fallen). Click someone
  to walk over and talk; pick answers with the mouse or the number keys. See
  [docs/DIALOGUE.md](docs/DIALOGUE.md).
- **Quests and a journal** (J): staged quests whose entries fill the journal, stages that
  advance by themselves (pick up the lost key and the journal notes it), and quest XP for
  every living member, with level-ups and hit points per level. Four quests in Millbrook:
  the reeve's lost key, a fever draught for the miller's wife, a lantern for the temple's
  altar, and a rumour for later.
- **Vendors:** the innkeeper, the blacksmith and the herbalist trade on the inventory
  screen. Drag to buy a stack or right-click to buy one; drag or right-click your own
  items to sell. Each vendor has their own markup and buying rate, and quest items can't
  be sold. What you sell stays on their shelf, in saves too.
- **The Temple of the Dawn**, a new building with its own nave: Father Anselm heals for
  10 gold and raises the fallen for 100. Characters at 0 HP are **fallen** (greyed out,
  can't act). The game is over only when the whole party is down, with a screen to load a
  save. Until combat arrives, Ctrl+K knocks out the selected leader for testing
  (`debug_keys` in the config).
- **Map items:** maps can leave items lying on the ground (the reeve's key by the well),
  which behave exactly like dropped items.
- **Whole buildings in the fog:** once you see any part of a building, all of it shows,
  rather than its roof vanishing into the unexplored dark behind it.

### Phase 2: items and places

- **Items:** 34 item types with 5e SRD numbers (weapons, armour, shields, rings, cloaks,
  potions, food, tools, gems, keys), each with a pre-rendered icon. Defined in
  [`data/items/items.json`](data/items/items.json), see [docs/ITEMS.md](docs/ITEMS.md).
- **Inventory and paper doll** (I): ten equipment slots around a large portrait, a 16-slot
  backpack, drag and drop, stacking, and right-click to drink, equip or take off. Armour
  class, attack line, carried weight and speed update live. Drop an item on a sidebar
  portrait to give it to that character.
- **Simplified 5e equipment rules:** armour and shield proficiency, two-handed weapons,
  light weapons for two-weapon fighting, Strength for heavy armour, carrying capacity.
- **Shared party gold**, shown in the sidebar. Coins found in containers go straight into
  the purse.
- **Containers:** chests, drawers, cupboards and a crate of apples, opened on the inventory
  screen with a "Take all" button. Locked ones need their key, or someone with thieves'
  tools to win a lock-picking roll. Contents are remembered.
- **Dropping and picking up items:** the inventory's ground panel shows what lies at the
  character's feet. Dropped items form a pile on the map that stays there (and in saves)
  until picked up.
- **Building interiors as separate maps**, each exactly the size of its building
  (cottages 8×6 hexes, the inn 12×8, the temple 8×8). Click the ground right in front of
  a door (point at a building to see where) and the party gathers there and goes in;
  anywhere else, the party just walks, so it can go all the way round a building. The way
  out leads back to the same door. Six pre-rendered rooms (an inn with a bar, a smithy
  with a forge, three cottages, a temple nave) with furniture the party walks around. Furnishing add-ons ("bar", "tables:4") lay
  out a tavern in any house.
- **Fog of war:** black where nobody has been, dimmed where the party has been but can't
  see now, with line of sight blocked by buildings. On the minimap too. Off indoors, and
  configurable (`fog_of_war` in the config).
- **Save and load:** an Esc menu with save and load screens (named slots with thumbnails,
  map, date, play time and party), F5 quicksave and F9 quickload. Saves are JSON in
  `user://saves`.
- **Drop-in audio:** music, ambience loops and sound effects requested by name through the
  `Audio` autoload and [`data/audio/audio.json`](data/audio/audio.json), with synthesised
  placeholders. See [docs/AUDIO.md](docs/AUDIO.md).

### Phase 1: movement

- **Hex grid everywhere, invisible on the ground:** pointy-top hexes, axial coordinates,
  A* pathfinding. The ground is painted as one seamless, blended surface, so hexes only
  appear as movement feedback: the hovered target and the path. `G` shows the full grid
  for debugging. Difficult terrain (shallows, brambles) costs double, and paths route
  around it when that's cheaper.
- **Click-to-move like Baldur's Gate:** click a spot, and the click snaps to the hex
  under the cursor. Characters walk in straight lines wherever the ground is clear and
  costs no more, rather than zig-zagging hex to hex, and always stop on a hex centre.
- **Party of up to 4.** The limit is set in config, and members are loaded from
  importable **JSON character sheets** (5e SRD-style numbers).
- **Selection:** click, Shift-click, drag a box, click portraits, number keys,
  Ctrl+A.
- **Group orders:** the leader walks to the clicked hex and the others take the
  nearest free hexes around it, keeping roughly their left/right arrangement. No two
  members ever end on the same hex. Orders can be changed mid-walk.
- **Real-time pause** (Space): you can keep issuing orders while paused.
- **Walk-to-interact:** click a signpost and the leader walks over and reads it.
- **Camera:** WASD/arrows, screen-edge and middle-drag panning; zoom towards the cursor.
- **Minimap** with live party dots and the camera rectangle; click or drag on it to pan.
- **Hover info:** hex coordinates, terrain, move cost, and path length in hexes and feet.
- **Occlusion fade:** trees and buildings turn see-through when someone walks behind them.
- **Buildings sized to their interiors:** each building's footprint is a rectangle of
  hexes (cottage 8×6, inn 12×8), and its interior map uses exactly those dimensions.
- **Sample map** "Millbrook Outskirts" (84×56 hexes): a forest, a river with a wooden
  bridge and a slow ford, and a village square with an inn, four cottages and a well,
  plus a rocky outcrop.
- **Pre-rendered 3D art**, made the way classic isometric RPGs did it: terrain, trees,
  buildings and characters are modelled procedurally in Blender and rendered with Cycles
  by scripts in this repo. Every image is a drop-in replacement (see
  [docs/ASSETS.md](docs/ASSETS.md)).
  - **Painted portraits:** crops of public-domain Old Master paintings, released as CC0
    by The Metropolitan Museum of Art, plus a dozen spare portraits for future NPCs.
  - **Animated characters:** a walk cycle in 8 facings (5 rendered, 3 mirrored), with
    frames advanced by distance walked so feet don't slide.
  - **Animated water:** the river and ford drift and glint.
  - **Variety and set dressing:** several looks per prop type (three oaks, two pines,
    birches, three cottage designs...), plus reeds, ferns, wildflowers, logs, stumps,
    barrels, crates, hay, lamp posts, market stalls and a cart.
  - **Colour grade:** a subtle warm grade and vignette over the game view (`post` in
    `game_config.json`).
- **65 automated tests**, run headless.

## Running it

1. Install **Godot 4.7** (the standard build; .NET is not needed).
2. In the Project Manager, choose **Import** and pick `project.godot` in this folder.
   The first import of the textures takes a few seconds.
3. Press **F5** (or the ▶ button).

## Controls

| Input | Action |
|---|---|
| Left click ground | Move the selected members |
| Left click member / portrait | Select (Shift adds or removes) |
| Left drag | Box select (Shift adds) |
| Right click | Clear selection |
| `1`–`4` | Select a party member (Shift toggles) |
| Ctrl+A | Select the whole party |
| Left click a signpost | Leader walks over and reads it |
| Left click a chest, drawers, cupboard | Leader walks over and opens it |
| Left click the hexes in front of a door, or a way out | The party gathers at the door and goes through (pointing at a building lights up its door hexes; clicking the building itself only walks there) |
| Left click a person | Leader walks over and talks to them |
| Left click a creature | Start a fight |
| In a fight: left click ground / an enemy | Move within the shaded area / attack (stepping up first if needed) |
| In a fight: Space | End the turn |
| In a fight: a spell or ability button, then a target | Cast or use it (right click or Esc cancels the targeting) |
| `1`–`9` in a conversation | Pick an answer (or click it) |
| `I` | Inventory (drag to move or equip, right-click to use) |
| `J` | Journal: quests and XP |
| `B` | Spells and abilities: slots, spells, features, scrolls; cast healing outside a fight |
| `R` | Rest: short or long |
| Esc | Menu: save, load, quicksave, quickload, item icon style, quit (also closes windows) |
| F5 / F9 | Quicksave / quickload |
| Double-click a portrait | Centre the camera on that member |
| WASD / arrows / screen edge / middle drag | Pan |
| Mouse wheel, `+` / `-` | Zoom |
| `C` | Centre on the selection |
| Space | Pause / resume |
| `G` | Toggle the debug hex grid |
| F3 | Toggle the hover info panel |
| F1 | Toggle the controls help |
| Ctrl+K / Ctrl+Shift+K | Debug: knock out / kill the selected leader (with `debug_keys` on) |

## What to try

- Walk the whole party across the **bridge**, then send them through the **southern ford**
  (the light-blue shallows). They slow down in the water, and the path preview turns amber
  over difficult terrain.
- Send someone diagonally across open grass: they walk straight there, not hex by hex.
- Click deep water or a house: the party goes to the nearest reachable ground instead.
- Select one member (`2`) and send them somewhere, then Shift-click a portrait and move both.
- Walk behind the inn or into the forest to see the occlusion fade.
- Pause with Space, queue up orders, and resume.
- Walk into **The Lantern & Thistle** (the big inn) or any cottage. Inside, open the
  drawers and chests. The **Reeve's strongbox** is locked: let Wren pick it, or find the
  reeve's key. The **smithy** has a locked chest too.
- Talk to **Aldous**, the reeve, by the well. His key lies on the cobbles nearby. Give
  it back for 40 gold and 150 XP, or keep it and open his strongbox.
- Talk to **Wenna** the herbalist (south-west cottage) and take her draught to **Hob**
  the miller (west of the square).
- Visit **Father Anselm** at the temple (up the lane north-east of the square) and ask
  what the temple needs. **Tobin** at the inn sells the lantern.
- Party members have their own lines: Anselm and Wenna know Odran, Bram talks shop with
  Garrick, and Pip's song means something to Elowen.
- Press Ctrl+K to knock someone out and give them a potion, or Ctrl+Shift+K to kill them
  and pay the temple to raise them. Knock out everyone to see the game-over screen.
- Cross the bridge and head into the **north-west woods** to meet the wolves. Let Garrick
  hold the line and Wren flank for Sneak Attack, and watch for wolves knocking people prone.
- Take the **waymarker at the end of the east road** to the Old Temple Road. Rest at
  Tobin's first. The bandits' archers keep their distance; the skeletons at the ruin fear
  Odran's mace (bludgeoning).
- Press **I**, drag a ring onto a ring slot and watch the AC change, or give someone a
  potion by dropping it on their portrait.
- Save with Esc → Save game, change things, and load it back.
- Walk right round the back of the inn: nothing happens until you click one of the two
  hexes in front of its door (point at the inn to see them).
- Press Esc and click **Item icons** to flip between the classic and painted icons, then
  open the inventory (I).
- In a fight, put the wolves to sleep with Elowen's **Sleep** (watch the circle: allies in
  it fall asleep too), or line up a **Burning Hands** cone. Bless the front line with
  Odran, then patch them up with **Healing Word** as a bonus action.
- After a fight, press **R** for a short rest, or **B** to cast Cure Wounds. Take a room at
  Tobin's for a long rest to get the spell slots back.
- Save in the middle of a fight on one of your turns, and load it back.

All the feel-related numbers are in [`data/config/game_config.json`](data/config/game_config.json):

| Key | Meaning |
|---|---|
| `max_party_size` | Party limit (sidebar and hotkeys adapt) |
| `hex_radius` | Hex size in pixels (centre to corner) |
| `feet_per_hex` | 5e distance per hex (5 ft) |
| `explore_move_speed` | Walking speed in pixels per second |
| `show_grid_default` | Debug grid lines on at start (off: hexes only show for movement) |
| `backpack_slots`, `save_slots` | Backpack size and number of save slots |
| `fog_of_war.*` | Fog on/off, sight radius in hexes, darkness of explored ground |
| `audio_volume_db.*` | Volume per audio bus |
| `terrain_blend.*` | How terrain types blend: weight-map resolution, blur, edge warp and noise |
| `post.*` | Colour grade: contrast, saturation, warmth, vignette (or `enabled: false`) |
| `art_style.items` | Item icons: `"painted"` or `"classic"` ([docs/PAINTED_STYLE.md](docs/PAINTED_STYLE.md)) |
| `camera.*` | Pan speed, edge scrolling, zoom limits |

## Project layout

```
assets/            Placeholder art (terrain, props, characters, portraits, item icons in
                   items/ and painted ones in items/painted/)
data/
  config/          game_config.json: global tunables
  characters/      Character sheets (JSON), one per file
  party/           starting_party.json: who you start with
  terrain/         terrain.json: terrain types, symbols, movement cost, texture
  props/           props.json: trees, houses, signs, furniture... (sprite, footprint, flags)
  items/           items.json: every item (docs/ITEMS.md)
  audio/           audio.json: sound names -> files (docs/AUDIO.md)
  maps/            The village, the Old Temple Road and six interiors (terrain rows, props,
                   townsfolk, creatures), see docs/MAPS.md
  npcs/            npcs.json: townsfolk, their sprites, dialogue and shops (docs/NPCS_AND_QUESTS.md)
  creatures/       creatures.json: hostile creatures' stat blocks (docs/COMBAT.md)
  dialogue/        One conversation graph per speaker (docs/DIALOGUE.md)
  quests/          quests.json: quest stages, journal entries and XP
docs/              START_HERE.md (study checklist), GODOT_GUIDE.md, plus format references
                   (maps, items, characters, dialogue, NPCs and quests, combat, assets, audio)
scenes/main.tscn   Entry scene: World + HUD
scripts/
  autoload/        GameConfig, Data (registry), GameState, Events (signal hub), Audio,
                   SaveManager
  core/            Hex math, HexGrid (terrain + A*), JSON helpers
  data/            TerrainDef, PropDef, MapData parsers
  rules/           Rules (5e SRD numbers), CharacterSheet
  items/           ItemDef, ItemStack, Inventory, ContainerState, InventoryOps (incl. buy/sell)
  dialogue/        Dialogue, DialogueRunner, Conditions, Effects
  quests/          QuestDef
  npc/             NpcDef, Npc
  combat/          CombatManager, CombatAI, CombatRules, Combatant, Attack, CreatureDef,
                   CreatureSheet
  world/           World, TerrainRenderer (+ blend shader), FogOfWar (+ shader), Actor,
                   PartyMember, PartyController, Creature, Prop, camera, overlays
  ui/              HUD, portrait cards, minimap, inventory/shop screen, item slots,
                   dialogue window, journal, combat HUD, menus, theme
tests/             Headless test runner, unit and integration tests
tools/             make_character.py, art renderers (tools/art/blender, classic and painted),
                   painted-style diagram makers (tools/art/docs), portrait cropper
                   (tools/art/portraits), map generators (tools/maps), sound synthesiser
                   (tools/audio), run_tests.sh
```

### How the pieces fit

- `World` owns one map. It builds a `HexGrid` from a `MapData`, spawns `Prop`s and the
  party (`PartyController` → `PartyMember` tokens), and turns mouse input into orders.
- `TerrainRenderer` paints the ground from the same grid: it bakes terrain weight maps
  from the hexes (with noise so edges are organic) and a shader
  (`terrain_blend.gdshader`) blends the terrain textures in world space.
- `HexGrid` is pure logic: terrain per hex, prop blockers, movement cost and A*. Combat,
  fog of war and AI will query the same grid.
- `Events` is the signal hub, so the world never holds UI references. The HUD listens
  for `selection_changed`, `hover_info_changed`, `message_requested` and so on.
- `GameState` holds the playthrough (party sheets, purse, current map, container contents,
  explored fog, quests, story flags) and serialises to a dictionary, which is exactly what
  a save file holds. `SaveManager` writes and reads the slots.
- People: `Npc` and `PartyMember` share the `Actor` base (sprite, facing, walking). A
  conversation is a `DialogueRunner` (pure logic) shown by the `DialogueWindow`.
- Fights: `CombatManager` runs the turn loop as a coroutine, `CombatRules` does the dice,
  and `CombatAI` plays the creatures. A `CreatureSheet` is a `CharacterSheet`, so monsters
  and the party share hit points, armour class, saves and damage.
- Items: `ItemDef` is a type from items.json, `ItemStack` a quantity of one, `Inventory` a
  row of slots. `InventoryOps` applies the rules for every move, for the UI and the tests.

[docs/GODOT_GUIDE.md](docs/GODOT_GUIDE.md) walks through all of this in more depth.

## Extending

- **New party member:** run `python3 tools/make_character.py --id ... --class ...` and add
  the id to `data/party/starting_party.json`. See [docs/CHARACTER_SHEETS.md](docs/CHARACTER_SHEETS.md).
- **New map:** copy `data/maps/millbrook_outskirts.json` and edit the text rows, then point
  `starting_map` at it. See [docs/MAPS.md](docs/MAPS.md).
- **New townsperson, conversation or quest:** an entry in `data/npcs/npcs.json`, a file in
  `data/dialogue/`, a stage list in `data/quests/quests.json`, and `{"id", "at"}` in a
  map's `"npcs"`. See [docs/NPCS_AND_QUESTS.md](docs/NPCS_AND_QUESTS.md).
- **New terrain or prop:** add an entry to `data/terrain/terrain.json` or `data/props/props.json`.
- **Real art:** overwrite the PNGs, or change the paths in the JSON. See [docs/ASSETS.md](docs/ASSETS.md).
  A new item icon can come in both styles: see [docs/PAINTED_STYLE.md](docs/PAINTED_STYLE.md), section 9.

## Tests

```sh
tools/run_tests.sh /path/to/godot     # or: GODOT=/path/to/godot tools/run_tests.sh
```

This runs `res://tests/test_runner.tscn` headless and exits non-zero on failure. Unit
tests cover hex math, pathfinding, rules, items and equipment rules, armour class, dice,
fog of war, save data round trips, and data validation (every texture and icon exists,
no map has overlapping props, everything interactable is reachable, every interior matches
its building). Integration tests drive the real main scene: group moves, redirects
mid-walk, sign interaction, pause, box select, mouse routing, smoothed walking, going in and
out of a cottage, emptying drawers, keys and lock-picking, the inventory screen, fog
reveal, saving and loading, and quicksave. Phase 3 adds tests for every condition and
effect, whole conversations and quests played through the dialogue runner, XP and
levelling, buying and selling, the temple's healing and raising, defeat, and checks that
every dialogue link, item and quest reference is valid. In the running game it checks
that every NPC can be reached, walking up to the innkeeper and shopping, the key by the
well, entering the temple, the journal and the game-over screen. Phase 4 adds the combat
arithmetic (weapon attacks, hit chances, critical hits, damage types, death saves,
movement range) and fights on the real map: noticing the party, movement limits,
attacking, Dash, Dodge and Disengage, opportunity attacks, the wolf and archer AI, victory
with XP and loot, death saves, potions mid-fight, defeat, and the road to the old temple.
Its second half adds the spell rules (slots, dice, healing, level-up grants, features,
rests) and spells, features, scrolls, thrown weapons, getting away and saving mid-fight on
the real map. Any engine or script error raised during a test fails that test.

## Roadmap

This order follows the plan agreed before Phase 1. **[docs/TODO.md](docs/TODO.md)** lists
every item of that plan and every request since, each flagged **COMPLETE**, **PENDING** or
**NOT STARTED**. See the end of [docs/GODOT_GUIDE.md](docs/GODOT_GUIDE.md) for how Phases 3
and 4 were added.

1. ~~**Foundation:** hex grid, pathfinding, party selection and movement, camera, minimap, sample map~~
2. ~~**Items and places:** item and equipment data, inventory and paper doll, chests and
   drawers, gold, building interiors as separate maps (door transitions), fog of war,
   save/load with a basic slot menu, and minimal drop-in audio hooks.~~
3. ~~**People:** NPCs, a branching dialogue system (in-house, no addons), quests, vendors
   (buy and sell), temple revival (paid service, game over only when the whole party is down).~~
4. ~~**Combat:** hostile actions trigger turn-based mode, with initiative, movement and
   actions on hexes. Also weapons and armour, spells and abilities, enemies and AI, death,
   XP and levelling.~~
   - ~~First half: turns, movement, attacks, enemies and AI, XP from fights, death saves.~~
   - ~~Second half: spells and cantrips, spell slots, spell scrolls, resting, class features.~~

Out of scope for now: character creation and cutscenes.

## Credits

See [CREDITS.md](CREDITS.md). Rules numbers come from the 5e System Reference Document
5.1 (CC-BY-4.0). The world art and the sounds were generated for this project by the
scripts in `tools/`; the portraits are CC0 paintings from The Metropolitan Museum of Art.
