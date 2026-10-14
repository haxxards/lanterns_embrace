extends Node
## Entry point: starts a new game (if none is running) and loads its map.

@onready var world: World = $World
@onready var hud: Hud = $HUD


func _ready() -> void:
	if GameState.party.is_empty():
		GameState.start_new_game()
	hud.bind(world)
	if not world.load_map(GameState.current_map_path):
		hud.show_message("Map failed to load",
				"Could not load '%s'. Check the Output panel for details." % GameState.current_map_path)
