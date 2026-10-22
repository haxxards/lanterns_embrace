# TODO guide: every item, and where it stands

Every item we have discussed for this project, from the four-phase plan agreed before
Phase 1 to the requests made along the way, with a flag:

- **COMPLETE**: works end to end and is covered by tests.
- **PENDING**: being worked on now, or partly done. The note says what's left.
- **NOT STARTED**: not begun. The note says why (out of scope, deferred, or a known gap).

This file is updated as each item is finished, so it always shows where the project is.

**Contents:** [At a glance](#at-a-glance) ·
[Ground rules](#ground-rules-your-answers-before-phase-1) ·
[Phase 1](#phase-1-foundation) · [Phase 2](#phase-2-items-and-places) ·
[Phase 3](#phase-3-people) · [Phase 4, part 1](#phase-4-part-1-combat) ·
[Phase 4, part 2](#phase-4-part-2-spells-rests-class-features) ·
[Requests along the way](#requests-along-the-way) ·
[Added without being asked](#added-without-being-asked) ·
[Changed from the proposal](#changed-from-the-original-proposal) ·
[Not started](#not-started-ideas-and-gaps)

## At a glance

- Phase 1, Foundation - **COMPLETE**
- Phase 2, Items and places - **COMPLETE** (spell scrolls moved to Phase 4, part 2)
- Phase 3, People - **COMPLETE**
- Phase 4, part 1, Combat - **COMPLETE**
- Phase 4, part 2, Spells, rests, class features and the rest of combat - **COMPLETE**

Nothing is **PENDING** at the moment: every planned item is either complete or listed
under [Not started](#not-started-ideas-and-gaps).

---

## Ground rules (your answers before Phase 1)

- Latest stable Godot, GDScript - **COMPLETE** (Godot 4.7, GDScript only)
- 2D - **COMPLETE** (pre-rendered 3D art shown as 2D sprites, as Baldur's Gate did)
- CC0 assets where needed, otherwise self-made - **COMPLETE** (art rendered by scripts in the
  repo; CC0 portraits from the Met; synthesised sounds; see [CREDITS.md](../CREDITS.md))
- Hex grid everywhere - **COMPLETE** (outdoors, indoors and in fights)
- Real-time exploring, turn-based once hostile - **COMPLETE**
- Loose 5e rules, no strict IP - **COMPLETE** (SRD 5.1 numbers only)
- Party of 4, easy for a developer to change - **COMPLETE** (`max_party_size` in
  `game_config.json`, `data/party/starting_party.json`)
- Character sheets as importable JSON, writable from Python - **COMPLETE**
  (`tools/make_character.py`, [CHARACTER_SHEETS.md](CHARACTER_SHEETS.md))
- Separate maps for building interiors - **COMPLETE**
- Save/load with a rudimentary slot menu - **COMPLETE**
- Dialogue with no addons - **COMPLETE** (the project has no addons at all)
- Drop-in replaceable placeholders - **COMPLETE**
- XP - **COMPLETE** (from quests and fights)
- Levelling - **COMPLETE**: a level-up adds hit points and a hit die, the proficiency bonus
  and Sneak Attack dice grow, and the class table grants new features, spells and spell
  slots ([SPELLS.md](SPELLS.md)). Choosing spells yourself at a level-up is
  [not started](#not-started-ideas-and-gaps).
- Fog of war - **COMPLETE**
- Minimal audio - **COMPLETE**
- Character creation - **NOT STARTED** (out of scope, as agreed)
- Cutscenes - **NOT STARTED** (out of scope, as agreed)

---

## Phase 1: Foundation

- Hex grid (`scripts/core/hex.gd`, `hex_grid.gd`) - **COMPLETE**
- Pathfinding, weighted by terrain cost - **COMPLETE**
- Camera: pan with keys, screen edge and middle drag; zoom - **COMPLETE**
- Party selection: click, Shift-click, box select, number keys - **COMPLETE**
- Portrait sidebar - **COMPLETE**
- Click to move, the group fanning out around the target - **COMPLETE**
- An outdoor map with trees, a river, houses and signs (Millbrook Outskirts) - **COMPLETE**
- Minimap - **COMPLETE**

## Phase 2: Items and places

- Item and equipment data (34 items with SRD numbers; 37 with Phase 4's scrolls) - **COMPLETE**
- Inventory and equipment screen (paper doll, backpack, drag and drop) - **COMPLETE**
- Chests and drawers (plus cupboards and a crate) - **COMPLETE**
- Gold, as a shared party purse - **COMPLETE**
- Entering building interiors - **COMPLETE** (from the hexes in front of the door)
- Fog of war (from your answers) - **COMPLETE**
- Save/load with slots (from your answers) - **COMPLETE**
- Audio hooks (from your answers) - **COMPLETE**
- Bar and table add-ons for a house (your request) - **COMPLETE**
- Dropping and picking up items (your request) - **COMPLETE**
- Spell scrolls - moved to Phase 4, part 2 (your request) - **COMPLETE** there
- "The rest of Phase 2", to revisit later - **NOT STARTED**: you didn't name items. The
  item system's known gaps are listed under [Not started](#not-started-ideas-and-gaps).

## Phase 3: People

- NPCs: 7 townsfolk with their own sprites and portraits - **COMPLETE**
- Branching dialogue with conditions and effects - **COMPLETE**
- Quests and a journal (7 quests) - **COMPLETE**
- Vendors that buy and sell (innkeeper, blacksmith, herbalist) - **COMPLETE**
- Temple revival; game over only when the whole party is down - **COMPLETE**

## Phase 4, part 1: Combat

- Turn-based fights triggered by hostility - **COMPLETE**
- Initiative - **COMPLETE**
- Movement and actions on hexes: Attack, Dash, Dodge, Disengage, potions, off-hand attacks,
  opportunity attacks - **COMPLETE**
- Weapon and armour stats in combat (finesse, versatile, ranged, ammunition, damage
  types) - **COMPLETE**
- Advantage and disadvantage, critical hits - **COMPLETE**
- Sneak Attack (rogue) and the Defense fighting style (fighter) - **COMPLETE**
- Enemies and AI: wolves, bandits, bandit archers, skeletons, skeleton archers - **COMPLETE**
- Death saving throws, massive damage, death and game over - **COMPLETE**
- XP from fights, shared by the party - **COMPLETE**
- The Old Temple Road map and its three combat quests - **COMPLETE**

## Phase 4, part 2: Spells, rests, class features

### Spells and cantrips
- Spell data in `data/spells/spells.json` ([SPELLS.md](SPELLS.md)) - **COMPLETE**
- Spell attack bonus and saving-throw DC from the casting ability - **COMPLETE**
- Cantrips Fire Bolt, Sacred Flame, Spare the Dying and Guidance - **COMPLETE**
- Cantrip damage growing at levels 5, 11 and 17 - **COMPLETE**
- Level 1 spells: Magic Missile, Burning Hands, Sleep, Shield, Mage Armor, Bless, Cure
  Wounds, Healing Word, Guiding Bolt - **COMPLETE**
- Level 2 spells for casters who reach level 3: Scorching Ray, Misty Step, Aid - **COMPLETE**
- Casting with a higher-level slot (upcasting) - **COMPLETE**
- Concentration (Bless) - **COMPLETE**
- Conditions from spells and features: asleep, turned (also blessed, and Guiding Bolt's
  mark) - **COMPLETE**
- Spell areas on the hex grid (circle, cone), previewed before casting - **COMPLETE**
- Casting in a fight: spell buttons and targeting - **COMPLETE**
- Casting outside a fight (healing, buffs), from the spells screen - **COMPLETE**
- Shield cast automatically as a reaction when it would turn a hit into a miss - **COMPLETE**

### Spell slots
- Slots by class and level (the SRD full-caster table) - **COMPLETE**
- Slots shown on the portraits and the spell screen - **COMPLETE**

### Spell scrolls
- Scroll items, with icons in both art styles - **COMPLETE**
- Reading a scroll: a caster with the spell on their class list, no slot used - **COMPLETE**
- Scrolls for sale and in loot (Wenna sells Cure Wounds; the bandits' strongbox and the
  ruin's chest hold one each) - **COMPLETE**

### Resting (R, or the sidebar's Rest button)
- Short rest: spend hit dice, recover short-rest features - **COMPLETE**
- Long rest: hit points, slots and features back; indoors only - **COMPLETE**
- A room at Tobin's inn is a long rest - **COMPLETE**

### Class features
- Fighter: Second Wind (level 1), Action Surge (level 2) - **COMPLETE**
- Rogue: Expertise with thieves' tools (level 1), Cunning Action Dash and Disengage
  (level 2) - **COMPLETE**
- Wizard: Arcane Recovery (level 1) - **COMPLETE**
- Cleric, Life domain: Disciple of Life (level 1); Channel Divinity Turn Undead and
  Preserve Life (level 2) - **COMPLETE**
- Features, slots and spells gained on level-up, from a class table - **COMPLETE**

### Spell and ability bar (from your first message: "interact with their inventory or spells or abilities")
- A spells and abilities screen, opened from the sidebar (or B) - **COMPLETE**
- Ability buttons in the combat bar - **COMPLETE**

### The rest of combat
- Thrown weapons (daggers) - **COMPLETE**
- Fleeing a fight (getting out of the enemies' sight or reach ends it) - **COMPLETE**
- Saving and loading in the middle of a fight (on a party member's turn) - **COMPLETE**

---

## Requests along the way

- Click to move like Baldur's Gate - **COMPLETE**
- Buildings as big outside as inside - **COMPLETE**
- The hex grid hidden except as a movement option; seamless terrain - **COMPLETE**
- Less cartoony, more realistic art (the Blender pipeline) - **COMPLETE**
- More art polish (prop variants, set dressing, animated water, characters walking in
  8 directions, a colour grade) - **COMPLETE**
- Better 2D portraits (CC0 paintings from the Met) - **COMPLETE**
- One commit per phase - **COMPLETE**
- A guide to how the game is built ([GODOT_GUIDE.md](GODOT_GUIDE.md)) - **COMPLETE**
- A study checklist ([START_HERE.md](START_HERE.md)) - **COMPLETE**
- A painted art style for the item icons, rolled out to all 34 (and the 3 scrolls since) - **COMPLETE**
- A config switch between the classic and painted styles, plus an in-game button - **COMPLETE**
- Documentation of how the painted style was made ([PAINTED_STYLE.md](PAINTED_STYLE.md)) - **COMPLETE**
- The reference art in the repository - **COMPLETE**
- Entering buildings only from the hexes in front of the door - **COMPLETE**
- A status check of the four-phase plan (this file) - **COMPLETE**
- The painted style tried on a character sprite (Garrick) - **COMPLETE** (an experiment);
  rolling it out to characters - **NOT STARTED** (see below)
- Attack animations as samples to build on (option A: 2D effects and body motion) - **COMPLETE**
  ([COMBAT_FX.md](COMBAT_FX.md)):
  - Melee attacks swing the equipped weapon (slash, smash, thrust, punch; a wolf's bite) - **COMPLETE**
  - Ranged attacks shoot something (arrows; thrown daggers spin) - **COMPLETE**
  - Magic Missile darts, and bolts for Fire Bolt, Guiding Bolt and Scorching Ray - **COMPLETE**
  - Wind-up, lunge, flinch and sidestep, grounded at the characters' hands (anchors
    exported from the 3D models) - **COMPLETE**
  - Strike frames on the character sprites (option A plus frames) - **NOT STARTED**: to
    decide after seeing option A

## Added without being asked

All **COMPLETE**. These were added because the planned features needed them or felt
incomplete without them:

- Smooth walking that still ends on hex centres; group formations - **COMPLETE**
- Buildings and trees turning see-through when someone is behind them - **COMPLETE**
- Real-time pause - **COMPLETE**
- Hover info panel (F3), controls help (F1), toasts - **COMPLETE**
- Locks, keys and lock-picking with thieves' tools - **COMPLETE**
- Giving an item by dropping it on a portrait - **COMPLETE**
- Items lying on the map (the reeve's key) - **COMPLETE**
- Carry weight and its effect on speed - **COMPLETE**
- Whole buildings shown once any part is seen through the fog - **COMPLETE**
- Party members' own dialogue lines; quest stages that advance by themselves; quest XP - **COMPLETE**
- What you sell staying on the vendor's shelf - **COMPLETE**
- Combat log, floating damage numbers, health bars over enemies, hit chances on hover - **COMPLETE**
- Debug keys (Ctrl+K, Ctrl+Shift+K) - **COMPLETE**
- Python map generators - **COMPLETE**
- A headless test suite that fails on any engine error; screenshot scripts - **COMPLETE**
- A document for each system (MAPS, ITEMS, CHARACTER_SHEETS, DIALOGUE, NPCS_AND_QUESTS,
  COMBAT, SPELLS, ASSETS, AUDIO) - **COMPLETE**
- Phase 4, part 2 extras: a rest dialog (R) showing everyone's hit points, hit dice and
  slots; hit dice per character; Second Wind and Preserve Life usable outside a fight;
  scrolls readable from the inventory as well as the combat bar; a spell-casting sound;
  every class feature described on the spells screen - **COMPLETE**

## Changed from the original proposal

- Party size: the proposal said up to 6; you chose 4, with the limit in the config - **COMPLETE**
- Art: CC0 packs such as Kenney were blocked from this environment, so the art is rendered
  with Blender instead - **COMPLETE**
- XP and levelling, fog of war, audio and save slots: out of scope in the proposal; you
  brought them in - see their flags above
- Spell scrolls: moved from Phase 2 to Phase 4, part 2 - see there
- Maps: JSON with text rows written by Python generators, drawn by our own terrain shader
  instead of a Godot `TileMap` - **COMPLETE**

---

## Not started: ideas and gaps

None of these were promised; they are the known limits, listed so nothing is forgotten.

- Character creation - **NOT STARTED** (out of scope)
- Cutscenes - **NOT STARTED** (out of scope)
- Utility cantrips Light and Mage Hand having an effect in the game - **NOT STARTED**
- Choosing which spells to learn at a level-up (spells are granted from a fixed list) - **NOT STARTED**
- Enemy spellcasters - **NOT STARTED**
- Hiding and stealth (Cunning Action's Hide) - **NOT STARTED**
- A game clock (resting doesn't move time on) - **NOT STARTED**
- Effects for the spells without an attack roll (Burning Hands, Sacred Flame, Sleep,
  Bless, healing) and for Shield and the class features - **NOT STARTED**
- Weapons drawn as separate sprites, so swings show the equipped weapon in the hand - **NOT STARTED**
- Choosing Bless's and Aid's targets by hand (they take the nearest allies) - **NOT STARTED**
- Concentration spells other than Bless, and more spells beyond 2nd level - **NOT STARTED**
- Other classes' features and spell lists (only fighter, rogue, wizard and Life cleric
  have class tables) - **NOT STARTED**
- Items whose use does more than heal or cast a scroll's spell (healing, scrolls and
  lock-picking today) - **NOT STARTED**
- Passive bonuses on worn items other than armour class - **NOT STARTED**
- Splitting a stack by a chosen amount - **NOT STARTED**
- Unidentified magic items; trapped containers - **NOT STARTED**
- The painted art style for characters and the world (needs larger sprites or a closer
  camera; see [PAINTED_STYLE.md](PAINTED_STYLE.md), section 10) - **NOT STARTED**
