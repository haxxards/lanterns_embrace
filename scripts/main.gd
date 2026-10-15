extends Node
## Entry point: starts a new game (if none is running) and loads its map.
## Also performs map changes (doors) and reloads the world after a save is
## loaded, so World itself never has to free itself mid-signal.

@onready var world: World = $World
@onready var hud: Hud = $HUD


func _ready() -> void:
	if GameState.party.is_empty():
		GameState.start_new_game()
	hud.bind(world)
	Events.map_change_requested.connect(_on_map_change_requested)
	SaveManager.game_loaded.connect(_on_game_loaded)
	_load(GameState.current_map_path, GameState.current_entry)


func _load(path: String, entry: String) -> void:
	if not world.load_map(path, entry):
		hud.show_message("Map failed to load",
				"Could not load '%s'. Check the Output panel for details." % path)


func _on_map_change_requested(path: String, entry: String) -> void:
	# Deferred: the request comes from inside a party member's signal, and the
	# map change frees that member.
	_load.call_deferred(path, entry)


func _on_game_loaded(_slot: String) -> void:
	_load.call_deferred(GameState.current_map_path, "")
