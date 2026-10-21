extends Node
## Global tunables loaded from res://data/config/game_config.json.
##
## Everything a designer is likely to tweak (party size, hex size, speeds,
## camera feel) lives in that JSON file so it can change without code edits.

const CONFIG_PATH := "res://data/config/game_config.json"
## The looks the art can come in (see docs/PAINTED_STYLE.md). "classic" is the
## original set; every other style is a subfolder of the same name.
const ART_STYLES: PackedStringArray = ["classic", "painted"]

var max_party_size: int = 4
var starting_party_path: String = "res://data/party/starting_party.json"
var starting_map_path: String = ""
var character_dirs: PackedStringArray = PackedStringArray(["res://data/characters"])

var hex_radius: float = 32.0
var feet_per_hex: int = 5
var explore_move_speed: float = 165.0
var show_grid_default: bool = false

## Terrain blending (see terrain_blend.gdshader).
var terrain_splat_px: float = 12.0
var terrain_splat_blur: int = 2
var terrain_warp: float = 0.45
var terrain_edge_noise: float = 0.5
var terrain_edge_sharpness: float = 4.0

## Colour grade over the game view (see scripts/ui/color_grade.gdshader).
var post_enabled: bool = true
var post_contrast: float = 1.06
var post_saturation: float = 1.06
var post_warmth: float = 0.025
var post_vignette: float = 0.32

## Backpack slots per character.
var backpack_slots: int = 16

## Fog of war (see scripts/world/fog_of_war.gd).
var fog_enabled: bool = true
var fog_sight_radius: int = 9
## How dark explored-but-not-currently-seen ground is (0 = BG-style, fully clear).
var fog_explored_dim: float = 0.35

## Save slots shown in the save/load menus (plus the quicksave).
var save_slots: int = 8

## Volumes in decibels per audio bus (see scripts/autoload/audio.gd).
var audio_volume_db: Dictionary = {"Master": 0.0, "Music": -8.0, "SFX": -2.0, "Ambience": -6.0}

## Developer hotkeys (Ctrl+K knocks out the leader, to test the temple).
var debug_keys: bool = true

## Which look each kind of art uses, by its folder under res://assets:
## {"items": "painted"} shows the inventory icons from assets/items/painted/.
## Kinds not listed use "classic". See styled_path().
var art_style: Dictionary = {}

var camera_pan_speed: float = 900.0
var camera_edge_pan: bool = true
var camera_edge_margin: float = 10.0
var camera_zoom_min: float = 0.5
var camera_zoom_max: float = 2.0
var camera_zoom_step: float = 0.1
var camera_zoom_default: float = 1.0


func _ready() -> void:
	load_config(CONFIG_PATH)


func load_config(path: String) -> void:
	var cfg: Variant = JsonUtil.load_json(path)
	if not cfg is Dictionary:
		push_error("GameConfig: could not load %s, using defaults" % path)
		return
	max_party_size = int(cfg.get("max_party_size", max_party_size))
	starting_party_path = str(cfg.get("starting_party", starting_party_path))
	starting_map_path = str(cfg.get("starting_map", starting_map_path))
	if cfg.has("character_dirs"):
		character_dirs = PackedStringArray(cfg["character_dirs"])
	hex_radius = float(cfg.get("hex_radius", hex_radius))
	feet_per_hex = int(cfg.get("feet_per_hex", feet_per_hex))
	explore_move_speed = float(cfg.get("explore_move_speed", explore_move_speed))
	show_grid_default = bool(cfg.get("show_grid_default", show_grid_default))

	var blend: Dictionary = cfg.get("terrain_blend", {})
	terrain_splat_px = maxf(2.0, float(blend.get("splat_px", terrain_splat_px)))
	terrain_splat_blur = maxi(0, int(blend.get("blur_passes", terrain_splat_blur)))
	terrain_warp = float(blend.get("warp", terrain_warp))
	terrain_edge_noise = float(blend.get("edge_noise", terrain_edge_noise))
	terrain_edge_sharpness = float(blend.get("edge_sharpness", terrain_edge_sharpness))

	var post: Dictionary = cfg.get("post", {})
	post_enabled = bool(post.get("enabled", post_enabled))
	post_contrast = float(post.get("contrast", post_contrast))
	post_saturation = float(post.get("saturation", post_saturation))
	post_warmth = float(post.get("warmth", post_warmth))
	post_vignette = float(post.get("vignette", post_vignette))

	backpack_slots = maxi(1, int(cfg.get("backpack_slots", backpack_slots)))

	var fog: Dictionary = cfg.get("fog_of_war", {})
	fog_enabled = bool(fog.get("enabled", fog_enabled))
	fog_sight_radius = maxi(1, int(fog.get("sight_radius", fog_sight_radius)))
	fog_explored_dim = clampf(float(fog.get("explored_dim", fog_explored_dim)), 0.0, 1.0)

	save_slots = maxi(1, int(cfg.get("save_slots", save_slots)))
	debug_keys = bool(cfg.get("debug_keys", debug_keys))
	var styles: Dictionary = cfg.get("art_style", {})
	for kind in styles:
		var style := str(styles[kind])
		if ART_STYLES.has(style):
			art_style[str(kind)] = style
		else:
			push_warning("GameConfig: unknown art style '%s' for %s (use one of %s)" % [style, kind, ART_STYLES])
	var audio: Dictionary = cfg.get("audio_volume_db", {})
	for bus in audio:
		audio_volume_db[str(bus)] = float(audio[bus])

	var cam: Dictionary = cfg.get("camera", {})
	camera_pan_speed = float(cam.get("pan_speed", camera_pan_speed))
	camera_edge_pan = bool(cam.get("edge_pan", camera_edge_pan))
	camera_edge_margin = float(cam.get("edge_margin", camera_edge_margin))
	camera_zoom_min = float(cam.get("zoom_min", camera_zoom_min))
	camera_zoom_max = float(cam.get("zoom_max", camera_zoom_max))
	camera_zoom_step = float(cam.get("zoom_step", camera_zoom_step))
	camera_zoom_default = float(cam.get("zoom_default", camera_zoom_default))


## The art style in use for one kind of art ("items"...).
func art_style_of(kind: String) -> String:
	return str(art_style.get(kind, "classic"))


## The file to load for an art `path` under its kind's current style. The kind
## is the first folder under res://assets, and a style's files sit in a
## subfolder named after it, under the same names:
##   res://assets/items/longsword.png  ->  res://assets/items/painted/longsword.png
## A file the style doesn't have falls back to the classic one, so new art can
## be added in one style first.
func styled_path(path: String) -> String:
	const PREFIX := "res://assets/"
	if not path.begins_with(PREFIX):
		return path
	var rest := path.trim_prefix(PREFIX)
	var slash := rest.find("/")
	if slash < 0:
		return path
	var kind := rest.substr(0, slash)
	var style := art_style_of(kind)
	if style == "classic":
		return path
	var styled := PREFIX + kind.path_join(style).path_join(rest.substr(slash + 1))
	return styled if ResourceLoader.exists(styled) else path
