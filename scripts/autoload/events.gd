extends Node
## Global signal hub. Systems emit here instead of holding references to the
## UI (and vice versa), which keeps world code and HUD code decoupled.

## Party selection changed. `selected` is an Array of PartyMember nodes.
signal selection_changed(selected: Array)
## A map finished loading and the world is ready.
signal map_loaded(map_id: String)
## Show a modal text box (signs, notes...).
signal message_requested(title: String, text: String)
## Short transient notice ("Can't reach that.").
signal toast_requested(text: String)
## Details about whatever is under the mouse (hex, terrain, prop, path).
signal hover_info_changed(info: Dictionary)
## Ask the camera to look at a world position.
signal camera_focus_requested(world_position: Vector2)
## The player gave the party a new order (move or interact).
signal party_order_issued
## Real-time pause toggled.
signal pause_changed(paused: bool)
## A container was opened by `opener` (shows it on the inventory screen).
signal container_opened(container: ContainerState, title: String, opener: CharacterSheet)
## Leave this map for another (door, exit). Main performs the change.
signal map_change_requested(map_path: String, entry: String)
## A party member started talking to an NPC (the HUD opens the dialogue).
signal dialogue_requested(npc: Npc, speaker: PartyMember)
## A dialogue closed (the NPC can wander again).
signal dialogue_ended(npc: Npc)
## Open a vendor's shop for `buyer` (from a dialogue option).
signal shop_requested(npc: Npc, buyer: CharacterSheet)
## A quest advanced to `stage`.
signal quest_updated(quest_id: String, stage: String)
## Every party member has fallen.
signal party_defeated
## The art style of one kind of art changed (Data.set_art_style), so anything
## drawing that art should redraw.
signal art_style_changed(kind: String, style: String)
