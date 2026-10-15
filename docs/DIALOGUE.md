# Dialogue

Conversations are JSON files in `data/dialogue/`, one per speaker, named by an NPC's
`"dialogue"` path in `data/npcs/npcs.json`. They are read by an in-house system (no
addons):

- `scripts/dialogue/dialogue.gd` (**Dialogue**) loads a file and checks that every link
  points at a real node.
- `scripts/dialogue/dialogue_runner.gd` (**DialogueRunner**) walks a conversation. It
  tracks which node is showing, which options are on offer, and what choosing one does.
  It is pure logic with no UI, so the tests drive it directly.
- `scripts/dialogue/conditions.gd` and `effects.gd` (**Conditions**, **Effects**)
  evaluate the `"if"` and `"do"` blocks.
- `scripts/ui/dialogue_window.gd` (**DialogueWindow**) shows a runner: the portrait, the
  name and title, the line, and numbered options. Number keys 1–9 pick an option, and Esc
  leaves.

The game pauses while a conversation is open, as it does for every other window.

## A file

```json
{
	"id": "tobin",
	"start": [
		{"if": {"not_flag": "met_tobin"}, "node": "first"},
		{"node": "greet"}
	],
	"nodes": {
		"first": {
			"text": "Welcome to the Lantern & Thistle! ...",
			"do": [{"set_flag": "met_tobin"}],
			"options": [
				{"text": "What have you got for sale?", "shop": true},
				{"text": "We need a room for the night.", "if": {"hurt": true}, "goto": "room"},
				{"text": "Any news in Millbrook?", "goto": "news"},
				{"text": "Farewell.", "end": true}
			]
		},
		"room": {
			"text": "Five gold for a bed ...",
			"options": [
				{"text": "Here's five gold.", "if": {"gold": 5},
				 "do": [{"take_gold": 5}, {"heal_party": true}], "goto": "rested"},
				{"text": "Maybe later.", "goto": "greet"}
			]
		},
		"rested": {"text": "There, colour back in your cheeks.", "next": "greet"}
	}
}
```

### Starting

`"start"` is either a node id, or a list of `{"if": condition, "node": id}` entries. The
first entry whose condition holds wins, so put the most specific entries first and finish
with one that has no `"if"`. This is how an NPC greets you differently the second time, or
notices that you are carrying the thing they asked for:

```json
"start": [
	{"if": {"quest": "the_reeves_key", "is_not": "done", "item": "reeve_key"}, "node": "return"},
	{"if": {"quest": "the_reeves_key", "is": "not_started"}, "node": "intro"},
	{"if": {"quest": "the_reeves_key", "is": "active"}, "node": "searching"},
	{"node": "after"}
]
```

### Nodes

| Key | Meaning |
|---|---|
| `text` | The line. `{leader}` becomes the speaking character's name, `{npc}` the NPC's, `{gold}` the purse. BBCode works (`[i]...[/i]`). |
| `speaker` | Optional name shown instead of the NPC's (for a narrator line, say). |
| `do` | Effects applied when the node is shown. |
| `options` | The choices. Only those whose `if` holds are offered. |
| `next` | With no options, the node offers "Continue." and goes here. |

A node with neither `options` nor `next` offers "Farewell." and ends the conversation.

### Options

| Key | Meaning |
|---|---|
| `text` | What the party says. |
| `if` | Condition for the option to be offered. |
| `do` | Effects applied when it is chosen. |
| `goto` | The next node. |
| `end` | `true` ends the conversation. An option with no `goto` ends it too. |
| `shop` | `true` closes the conversation and opens the NPC's shop (vendors only). |

Every node you show is remembered as a flag, `seen:<dialogue id>:<node id>`. The
`visited` condition reads it.

## Conditions (`"if"`)

A condition is a dictionary, and every key in it must hold. A list of conditions means all
of them.

| Condition | Holds when |
|---|---|
| `{"flag": "x"}` / `{"not_flag": "x"}` | A story flag is set / not set |
| `{"quest": "id"}` | The quest has been started (or finished) |
| `{"quest": "id", "is": "active"}` | `not_started`, `active`, `done`, or a stage id |
| `{"quest": "id", "is_not": "done"}` | The opposite |
| `{"item": "id"}`, `{"item": "id", "qty": 3}` | Someone in the party carries it (backpack or worn) |
| `{"not_item": "id"}` | Nobody carries it |
| `{"gold": 10}` | The purse holds at least this much |
| `{"member": "odran"}` | That character is in the party and standing |
| `{"speaker": "wren"}` | That character is the one doing the talking |
| `{"hurt": true}` | A living member is below full hit points |
| `{"fallen": true}` | A member is down at 0 hit points |
| `{"visited": "node"}` | That node of this dialogue was shown before |
| `{"all": [...]}`, `{"any": [...]}`, `{"not": {...}}` | Combinations |

The same conditions are used by dialogue starts and options, and by quest stages that
advance by themselves (`"auto_if"`, see [NPCS_AND_QUESTS.md](NPCS_AND_QUESTS.md)).

## Effects (`"do"`)

A list of small dictionaries, applied in order. Each one returns a short message that
the HUD shows as a toast ("Received 20 gold.").

| Effect | Does |
|---|---|
| `{"set_flag": "x"}` / `{"clear_flag": "x"}` | Story flags (saved with the game) |
| `{"give_item": "id", "qty": 1}` | Into the speaker's pack, or whoever has room |
| `{"take_item": "id", "qty": 1}` | From whoever carries it (backpacks, then worn items) |
| `{"give_gold": 20}` / `{"take_gold": 10}` | The shared purse |
| `{"quest": "id", "stage": "started"}` | Moves a quest on (logs the journal entry, awards XP on a done stage) |
| `{"xp": 50}` | Every living member gains it |
| `{"heal_party": true}` | The living are healed to full |
| `{"revive": true}` | The fallen get up with 1 hit point |
| `{"toast": "text"}` | Just a message |

Paid services are an option gated on gold, with a `take_gold` effect. The temple does it
this way:

```json
{"text": "Raise our fallen. (100 gold)", "if": {"fallen": true, "gold": 100},
 "do": [{"take_gold": 100}, {"revive": true}], "goto": "raised"},
{"text": "Raise our fallen.", "if": {"fallen": true, "not": {"gold": 100}}, "goto": "poor"}
```

## Adding a conversation

1. Write `data/dialogue/<npc>.json`.
2. Point the NPC's `"dialogue"` at it in `data/npcs/npcs.json`.
3. Run the tests. `test_every_npc_and_dialogue_is_sound` checks every link, every item and
   quest named in a condition or effect, and that only vendors offer a shop.

Adding a new condition or effect means adding a branch to `Conditions._check_key` or
`Effects._apply_one`. Both are short `match`/`if` lists.
