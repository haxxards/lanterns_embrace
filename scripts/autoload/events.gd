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
