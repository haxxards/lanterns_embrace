extends Node
## Global tunables loaded from res://data/config/game_config.json.
##
## Everything a designer is likely to tweak (party size, hex size, speeds,
## camera feel) lives in that JSON file so it can change without code edits.

const CONFIG_PATH := "res://data/config/game_config.json"

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

	var cam: Dictionary = cfg.get("camera", {})
	camera_pan_speed = float(cam.get("pan_speed", camera_pan_speed))
	camera_edge_pan = bool(cam.get("edge_pan", camera_edge_pan))
	camera_edge_margin = float(cam.get("edge_margin", camera_edge_margin))
	camera_zoom_min = float(cam.get("zoom_min", camera_zoom_min))
	camera_zoom_max = float(cam.get("zoom_max", camera_zoom_max))
	camera_zoom_step = float(cam.get("zoom_step", camera_zoom_step))
	camera_zoom_default = float(cam.get("zoom_default", camera_zoom_default))
