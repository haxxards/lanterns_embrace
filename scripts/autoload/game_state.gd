extends Node
## Mutable state of the current playthrough: the party, the purse, where the
## party is, and what has changed on each map (containers emptied, ground
## explored).
##
## Everything here serialises to a plain Dictionary (to_dict / load_dict);
## that dictionary is exactly what a save file contains (see SaveManager).

signal party_changed
signal gold_changed(gold: int)

const SAVE_VERSION := 1

var party: Array[CharacterSheet] = []
## The party shares one purse, as in the Baldur's Gate games.
var gold: int = 0
var current_map_path: String = ""
## Entry point on the current map to place the party at ("" = the map's spawn).
var current_entry: String = ""
## Exact hexes to restore on the next map load: {member id: Vector2i}. Used by
## loading a save; cleared once the map has used them.
var pending_positions: Dictionary = {}
var pending_camera: Variant = null
## Seconds of unpaused play.
var playtime: float = 0.0
## Story flags for later phases (quests, dialogue).
var flags: Dictionary = {}

## map id -> {container id -> ContainerState}
var _containers: Dictionary = {}
## map id -> PackedByteArray, one byte per hex: 1 = explored.
var _explored: Dictionary = {}


func _process(delta: float) -> void:
	if not get_tree().paused:
		playtime += delta


## Builds the starting party from GameConfig.starting_party_path.
func start_new_game() -> void:
	party.clear()
	gold = 0
	flags.clear()
	playtime = 0.0
	_containers.clear()
	_explored.clear()
	pending_positions.clear()
	pending_camera = null
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
		_join(sheet)
	current_map_path = GameConfig.starting_map_path
	current_entry = ""
	party_changed.emit()
	gold_changed.emit(gold)


func add_party_member(sheet: CharacterSheet) -> bool:
	if party.size() >= GameConfig.max_party_size or party.has(sheet):
		return false
	_join(sheet)
	party_changed.emit()
	gold_changed.emit(gold)
	return true


func remove_party_member(sheet: CharacterSheet) -> void:
	party.erase(sheet)
	party_changed.emit()


## A joining character's own gold goes into the party purse.
func _join(sheet: CharacterSheet) -> void:
	party.append(sheet)
	gold += sheet.gold
	sheet.gold = 0


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


## Spends gold if the purse holds enough. Returns false (and spends nothing) otherwise.
func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	add_gold(-amount)
	return true


func member(member_id: String) -> CharacterSheet:
	for s in party:
		if s.id == member_id:
			return s
	return null


# --- per-map state ------------------------------------------------------------

func get_container(map_id: String, container_id: String) -> ContainerState:
	return (_containers.get(map_id, {}) as Dictionary).get(container_id)


## All containers known on a map: {container id: ContainerState}.
func containers_for(map_id: String) -> Dictionary:
	return _containers.get(map_id, {})


func set_container(map_id: String, container_id: String, state: ContainerState) -> void:
	if not _containers.has(map_id):
		_containers[map_id] = {}
	_containers[map_id][container_id] = state


## The explored-hex mask for a map (created empty on first visit).
func explored_for(map_id: String, cell_count: int) -> PackedByteArray:
	var mask: PackedByteArray = _explored.get(map_id, PackedByteArray())
	if mask.size() != cell_count:
		mask.resize(cell_count)
		mask.fill(0)
	return mask


func set_explored(map_id: String, mask: PackedByteArray) -> void:
	_explored[map_id] = mask


# --- save data -----------------------------------------------------------------

## Everything needed to restore the game. `positions` ({id: Vector2i}) and
## `camera` come from the live world (see SaveManager).
func to_dict(positions: Dictionary = {}, camera: Variant = null) -> Dictionary:
	var members: Array = []
	for sheet in party:
		members.append(sheet.to_dict())
	var pos := {}
	for k in positions:
		var h: Vector2i = positions[k]
		pos[k] = [h.x, h.y]
	var maps := {}
	for map_id in _containers:
		var c := {}
		for cid in _containers[map_id]:
			var state: ContainerState = _containers[map_id][cid]
			if str(cid).begins_with("ground_") and state.inventory.is_empty():
				continue  # picked-up piles leave nothing behind
			c[cid] = state.to_dict()
		maps[map_id] = {"containers": c}
	for map_id in _explored:
		if not maps.has(map_id):
			maps[map_id] = {}
		maps[map_id]["explored"] = Marshalls.raw_to_base64(_explored[map_id])
	var d := {
		"version": SAVE_VERSION,
		"party": members,
		"gold": gold,
		"current_map": current_map_path,
		"positions": pos,
		"playtime": playtime,
		"flags": flags.duplicate(true),
		"maps": maps,
	}
	if camera is Vector2:
		d["camera"] = [camera.x, camera.y]
	return d


## Replaces the current playthrough with saved data. The caller reloads the map.
func load_dict(d: Dictionary) -> bool:
	if int(d.get("version", 0)) > SAVE_VERSION:
		push_error("Save is from a newer version of the game (%s)" % d.get("version"))
		return false
	var new_party: Array[CharacterSheet] = []
	for m in d.get("party", []):
		if m is Dictionary:
			var sheet := CharacterSheet.from_dict(m)
			for err in sheet.errors:
				push_warning("Saved character %s: %s" % [sheet.id, err])
			new_party.append(sheet)
	if new_party.is_empty():
		push_error("Save contains no party")
		return false
	party = new_party
	gold = int(d.get("gold", 0))
	current_map_path = str(d.get("current_map", GameConfig.starting_map_path))
	current_entry = ""
	playtime = float(d.get("playtime", 0.0))
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	pending_positions.clear()
	var pos: Dictionary = d.get("positions", {})
	for k in pos:
		pending_positions[str(k)] = JsonUtil.to_vec2i(pos[k])
	pending_camera = JsonUtil.to_vec2(d["camera"]) if d.has("camera") else null
	_containers.clear()
	_explored.clear()
	var maps: Dictionary = d.get("maps", {})
	for map_id in maps:
		var m: Dictionary = maps[map_id]
		for cid in m.get("containers", {}):
			set_container(map_id, cid, ContainerState.from_dict(m["containers"][cid]))
		if m.has("explored"):
			_explored[map_id] = Marshalls.base64_to_raw(str(m["explored"]))
	party_changed.emit()
	gold_changed.emit(gold)
	return true
