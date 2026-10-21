extends Node
## Save slots on disk. Each slot is a JSON file (GameState.to_dict() plus a
## "meta" block for the menus) and an optional PNG thumbnail:
##   user://saves/slot_1.json, slot_1.png ... and quicksave.json
##
## Loading only replaces GameState and emits `game_loaded`; Main then reloads
## the world from it.

signal game_saved(slot: String)
signal game_loaded(slot: String)

const QUICKSAVE := "quicksave"
const THUMB_SIZE := Vector2i(192, 108)

## Folder for save files (tests point this somewhere else).
var save_dir: String = "user://saves"


## Slot ids for the menus: the quicksave first, then numbered slots.
func slot_ids() -> PackedStringArray:
	var ids := PackedStringArray([QUICKSAVE])
	for i in GameConfig.save_slots:
		ids.append("slot_%d" % (i + 1))
	return ids


func slot_path(slot: String) -> String:
	return save_dir.path_join(slot + ".json")


func thumbnail_path(slot: String) -> String:
	return save_dir.path_join(slot + ".png")


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Writes the game to `slot`. `world` supplies positions and the map name;
## `thumbnail` (optional) is a screenshot of the game view.
func save_game(slot: String, label: String, world: World, thumbnail: Image = null) -> bool:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var positions := {}
	for m in world.party.members:
		positions[m.sheet.id] = m.hex
	var data := GameState.to_dict(positions, world.camera.position)
	if world.combat.active:
		data["combat"] = world.combat.to_dict()
	var names: Array = []
	for s in GameState.party:
		names.append("%s (%d)" % [s.display_name, s.level])
	data["meta"] = {
		"label": label if not label.strip_edges().is_empty() else world.map.display_name,
		"map_name": world.map.display_name,
		"saved_at": int(Time.get_unix_time_from_system()),
		"playtime": int(GameState.playtime),
		"party": names,
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Could not write save %s: %s" % [slot_path(slot), error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if thumbnail != null and not thumbnail.is_empty():
		var img := thumbnail.duplicate() as Image
		img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
		img.save_png(thumbnail_path(slot))
	elif FileAccess.file_exists(thumbnail_path(slot)):
		DirAccess.remove_absolute(thumbnail_path(slot))
	Audio.play_sfx("save")
	game_saved.emit(slot)
	return true


## The slot's data, or {} if it is empty or unreadable.
func read_slot(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(slot_path(slot))) != OK or not json.data is Dictionary:
		push_warning("Save %s is unreadable" % slot_path(slot))
		return {}
	return json.data


## Menu info per slot: {"slot", "exists", "label", "map_name", "saved_at", "playtime", "party"}.
func describe_slot(slot: String) -> Dictionary:
	var d := read_slot(slot)
	var meta: Dictionary = d.get("meta", {})
	var info := meta.duplicate()
	info["slot"] = slot
	info["exists"] = not d.is_empty()
	return info


func load_thumbnail(slot: String) -> Texture2D:
	var path := thumbnail_path(slot)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img else null


func load_game(slot: String) -> bool:
	var d := read_slot(slot)
	if d.is_empty() or not GameState.load_dict(d):
		return false
	game_loaded.emit(slot)
	return true


func delete_slot(slot: String) -> void:
	for path in [slot_path(slot), thumbnail_path(slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


@warning_ignore("integer_division")
static func format_playtime(seconds: int) -> String:
	return "%d:%02d" % [seconds / 3600, (seconds / 60) % 60]
