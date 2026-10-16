# NPCs, quests, vendors and the temple

## Townsfolk: `data/npcs/npcs.json`

```json
"tobin": {
	"name": "Tobin Hale", "title": "Innkeeper",
	"portrait": "res://assets/portraits/npc_elder.png",
	"animation": "res://assets/characters/innkeeper_anim.json",
	"dialogue": "res://data/dialogue/tobin.json",
	"wander": 1,
	"vendor": {"markup": 1.0, "buy_rate": 0.4, "stock": [
		{"item": "rations", "qty": 10}, {"item": "lantern", "qty": 3}]}
}
```

| Key | Meaning |
|---|---|
| `name`, `title` | Shown in the dialogue window and on hover |
| `portrait` | Any image; the dialogue window shows it |
| `animation` | An 8-direction walk sheet from `tools/art/blender/render_characters.py` (or `"sprite"` for a still image) |
| `dialogue` | Their conversation, see [DIALOGUE.md](DIALOGUE.md) |
| `wander` | How far (in hexes) they stroll from their spot. 0 stands still. |
| `vendor` | Makes them a trader: `markup` is what the party pays × the item's value, `buy_rate` what they pay for the party's goods, `stock` what's on the shelf |

**Placing them:** a map lists its townsfolk by id and hex:

```json
"npcs": [{"id": "aldous", "at": [62, 29]}]
```

The village map gets this from `tools/maps/generate_millbrook.py`. The interiors get it
from the `npcs=[...]` lists in `tools/maps/generate_interiors.py`. There, `at="bar"`
stands someone behind the bar add-on, and a hex that furniture took is nudged to the
nearest free one. The generator also refuses a spot that would cut the room in two, since
NPCs block movement.

**How an NPC works** (`scripts/npc/npc.gd`, class `Npc`): it shares the `Actor` base class
with `PartyMember`, which provides the sprite, the 8-direction animation and smooth walking
along a hex path. On top of that it:

- marks its hex as occupied in the `HexGrid`, so the party paths around it
  (`HexGrid.set_occupied` disables the A* point);
- strolls to a random free hex within `wander` of home every few seconds, keeping clear of
  the party;
- answers the same calls a door or chest does (`approach_hexes`, `is_adjacent_to`,
  `interact`), so `PartyController.interact_with` walks the leader over without knowing
  it's a person;
- stops when clicked, turns to face whoever talks to it, and emits
  `Events.dialogue_requested`, which opens the HUD's dialogue window;
- is hidden while outside the party's sight (fog of war).

## Quests: `data/quests/quests.json`

```json
"the_reeves_key": {
	"name": "The Reeve's Key", "xp": 150,
	"stages": [
		{"id": "started", "journal": "Aldous Grey, the reeve, lost an iron key ..."},
		{"id": "found", "auto_if": {"item": "reeve_key"}, "journal": "We found the reeve's key ..."},
		{"id": "done", "done": true, "journal": "We gave the key back to the reeve ..."}
	]
}
```

- A quest is **not started** until something sets a stage, usually a dialogue effect
  `{"quest": "the_reeves_key", "stage": "started"}`.
- Each stage reached adds its `journal` entry to the journal (J).
- A stage with `"auto_if"` is reached by itself once its condition holds. Fights use
  `{"defeated": "<group>"}`: true once every creature of that encounter group is dead. The check runs
  whenever a character sheet changes (an item picked up or handed over, hit points), and
  right after a quest moves to a new stage. It only
  applies to quests already under way: finding the key first doesn't start the quest.
  Aldous's dialogue notices the key either way.
- A stage with `"done": true` completes the quest and gives its `xp` to **every living
  member** (quest XP isn't split). Levels follow the 5e thresholds. Each level adds hit
  points (half the hit die + 1 + Con modifier) and shows a toast.
- Quest stages, the journal and story flags are saved with the game.

`GameState` is the API: `quest_state(id)` returns `"not_started"`, `"active"` or
`"done"`. The others are `quest_stage(id)`, `set_quest_stage(id, stage)`, `award_xp(n)`,
`give_party_item`, `take_party_item` and `party_item_count`.

### The quests in Millbrook

| Quest | Giver | What to do |
|---|---|---|
| The Reeve's Key | Aldous, by the well | The key lies on the cobbles south-east of the well. Bring it back for 40 gold. Or keep it: it opens his strongbox. |
| A Draught for the Miller's Wife | Wenna, the herbalist | Take her fever draught to Hob at the mill for 20 gold. |
| Light for the Dawn | Father Anselm, the temple | Buy a lantern from Tobin and bring it to the altar for a potion of greater healing. |
| Wolves in the Woods | Aldous | Kill the wolf pack in the north-west woods (across the bridge), then tell him: 25 gold. |
| The Old Temple Road | Bram, the smith | Clear the bandits camped on the road east of Millbrook (the waymarker at the end of the east road): 50 gold. |
| Rest for the Restless Dead | Father Anselm | Destroy the skeletons at the ruined temple at the end of that road: a potion of greater healing. |
| The Lantern That Never Goes Out | Pip, the bard | A rumour only, the hook for later. (A carved stone at the ruin adds a clue.) |

## Vendors

A vendor's `"shop": true` dialogue option opens the inventory screen with their stock in
place of a container. Prices come from `InventoryOps.buy_price` / `sell_price`:

- **Buying:** drag from their stock to buy the whole stack (as many as the purse
  allows), or right-click to buy one. Price = value × `markup`, at least 1 gp.
- **Selling:** drag an item onto their stock, or right-click it in the backpack.
  Price = value × `buy_rate`, rounded down. Worthless items, coins and **quest items**
  (`"quest": true` in items.json) can't be sold.

Stock is kept in `GameState` (under the pseudo-map `_vendors`), so what you sell stays on
the shelf and is saved.

## The temple, falling and game over

- A party member at 0 hit points is **down** (unconscious): they lie on the ground, greyed,
  can't be selected or given orders, and the party doesn't wait for them at a door (they
  are carried along to the next map). In a fight they make death saving throws (see
  [COMBAT.md](COMBAT.md)); their portrait says "Dying" with the saves so far, or
  "Unconscious" once stable. **Any healing wakes them**: a potion (from someone next to
  them, in a fight), Tobin's room, or the temple.
- Three failed death saves, or one blow that leaves as much damage again as their
  maximum, and they are **dead** (darker, portrait "Dead"). Healing does nothing for the
  dead.
- **Father Anselm** at the Temple of the Dawn heals everyone who isn't dead for 10 gold,
  and raises the dead for 100 gold (with 1 hit point). **Tobin** rents a room that heals
  everyone who isn't dead for 5. These are ordinary dialogue options.
- When **nobody** is left standing, `Events.party_defeated` fires and the HUD shows the
  game-over screen (load a save, or quit).
- With `debug_keys` on in `data/config/game_config.json`, **Ctrl+K** knocks out the
  first selected member and **Ctrl+Shift+K** kills them, to try healing and raising.
