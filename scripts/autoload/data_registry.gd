extends Node
## Loads and indexes static game data: terrain, props and character sheets.
##
## Content is plain JSON under res://data so it can be authored outside Godot.
## Textures referenced by data are loaded through load_texture(), which also
## accepts files outside the project (user://...) and never returns null.

const TERRAIN_PATH := "res://data/terrain/terrain.json"
const PROPS_PATH := "res://data/props/props.json"

var terrain: Dictionary = {}            # id -> TerrainDef
var terrain_by_symbol: Dictionary = {}  # symbol -> TerrainDef
var props: Dictionary = {}              # id -> PropDef
var characters: Dictionary = {}         # id -> CharacterSheet (template, never mutated)

var _texture_cache: Dictionary = {}
var _missing_texture: Texture2D


func _ready() -> void:
	reload()


func reload() -> void:
	_texture_cache.clear()
	_load_terrain()
	_load_props()
	_load_characters()


func _load_terrain() -> void:
	terrain.clear()
	terrain_by_symbol.clear()
	var d: Variant = JsonUtil.load_json(TERRAIN_PATH)
	if not d is Dictionary:
		return
	for entry in d.get("terrain", []):
		var t := TerrainDef.from_dict(entry)
		if t.id.is_empty() or t.symbol.length() != 1:
			push_error("terrain.json: each terrain needs an id and a one-character symbol: %s" % entry)
			continue
		t.texture = load_texture(t.texture_path)
		terrain[t.id] = t
		terrain_by_symbol[t.symbol] = t


func _load_props() -> void:
	props.clear()
	var d: Variant = JsonUtil.load_json(PROPS_PATH)
	if not d is Dictionary:
		return
	var defs: Dictionary = d.get("props", {})
	for prop_id in defs:
		var p := PropDef.from_dict(prop_id, defs[prop_id])
		p.texture = load_texture(p.texture_path)
		p.resolve_fade(GameConfig.hex_radius * 2.2)
		props[prop_id] = p


## Loads every sheet from GameConfig.character_dirs. Later directories win,
## so dropping a JSON into user://characters overrides a bundled sheet.
func _load_characters() -> void:
	characters.clear()
	for dir_path in GameConfig.character_dirs:
		for path in JsonUtil.list_json_files(dir_path):
			var sheet := CharacterSheet.load_file(path)
			for err in sheet.errors:
				push_warning("Character sheet %s: %s" % [path, err])
			if sheet.id.is_empty():
				continue
			characters[sheet.id] = sheet


## Fresh copy of a character template, safe to mutate during play.
func new_character(character_id: String) -> CharacterSheet:
	var template: CharacterSheet = characters.get(character_id)
	if template == null:
		return null
	return CharacterSheet.from_dict(template.to_dict(), template.source_path)


func load_map(path: String) -> MapData:
	var m := MapData.load_file(path, terrain_by_symbol, props)
	for err in m.errors:
		push_warning("Map %s: %s" % [path, err])
	return m


## Loads a texture from res:// (imported) or any readable PNG/JPG path.
## Missing files yield a magenta checker so broken references are obvious.
func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return missing_texture()
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("Texture not found: %s" % path)
		tex = missing_texture()
	_texture_cache[path] = tex
	return tex


func missing_texture() -> Texture2D:
	if _missing_texture == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var on := ((x >> 3) + (y >> 3)) % 2 == 0
				img.set_pixel(x, y, Color.MAGENTA if on else Color.BLACK)
		_missing_texture = ImageTexture.create_from_image(img)
	return _missing_texture
