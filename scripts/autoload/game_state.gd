extends Node
## Mutable state of the current playthrough: the party and where it is.
##
## Everything here is meant to be serialisable so save/load can be added
## without restructuring (see to_dict()).

signal party_changed

var party: Array[CharacterSheet] = []
var current_map_path: String = ""


## Builds the starting party from GameConfig.starting_party_path.
func start_new_game() -> void:
	party.clear()
	var d: Variant = JsonUtil.load_json(GameConfig.starting_party_path)
	var ids: Array = d.get("members", []) if d is Dictionary else []
	for character_id in ids:
		if party.size() >= GameConfig.max_party_size:
			push_warning("Starting party lists more than max_party_size (%d); extra members ignored"
					% GameConfig.max_party_size)
			break
		var sheet := Data.new_character(str(character_id))
		if sheet == null:
			push_error("Starting party member '%s' has no character sheet" % character_id)
			continue
		party.append(sheet)
	current_map_path = GameConfig.starting_map_path
	party_changed.emit()


func add_party_member(sheet: CharacterSheet) -> bool:
	if party.size() >= GameConfig.max_party_size or party.has(sheet):
		return false
	party.append(sheet)
	party_changed.emit()
	return true


func remove_party_member(sheet: CharacterSheet) -> void:
	party.erase(sheet)
	party_changed.emit()


func to_dict() -> Dictionary:
	var members: Array = []
	for sheet in party:
		members.append(sheet.to_dict())
	return {"party": members, "current_map": current_map_path}
