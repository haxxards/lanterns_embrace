extends TestCase
## The art style switch: "art_style" in game_config.json, GameConfig.styled_path
## and Data.set_art_style (see docs/PAINTED_STYLE.md).

var _saved: Dictionary


func before_each() -> void:
	_saved = GameConfig.art_style.duplicate()


func after_each() -> void:
	Data.set_art_style("items", str(_saved.get("items", "classic")))
	GameConfig.art_style = _saved


func test_config_names_a_known_style_for_items() -> void:
	var cfg: Dictionary = JsonUtil.load_json(GameConfig.CONFIG_PATH)
	var style := str(cfg.get("art_style", {}).get("items", ""))
	check(GameConfig.ART_STYLES.has(style), "game_config.json art_style.items is one of %s (got '%s')"
			% [GameConfig.ART_STYLES, style])


func test_styled_path_follows_the_style() -> void:
	var classic := "res://assets/items/longsword.png"
	GameConfig.art_style["items"] = "classic"
	check_eq(GameConfig.styled_path(classic), classic, "classic keeps the path")
	GameConfig.art_style["items"] = "painted"
	check_eq(GameConfig.styled_path(classic), "res://assets/items/painted/longsword.png", "painted subfolder")
	# Other kinds of art keep their own style, and paths outside assets/ are left alone.
	check_eq(GameConfig.styled_path("res://assets/characters/fighter.png"), "res://assets/characters/fighter.png",
			"characters unaffected")
	check_eq(GameConfig.styled_path("user://portraits/me.png"), "user://portraits/me.png", "outside assets")
	check_eq(GameConfig.styled_path("res://assets/items/no_such_item.png"), "res://assets/items/no_such_item.png",
			"a file missing from the style falls back to classic")


func test_every_item_has_icons_in_both_styles() -> void:
	GameConfig.art_style["items"] = "painted"
	for id in Data.items:
		var it: ItemDef = Data.items[id]
		check(ResourceLoader.exists(it.icon_path), "%s classic icon %s" % [id, it.icon_path])
		var painted := GameConfig.styled_path(it.icon_path)
		check(painted != it.icon_path, "%s has a painted icon (assets/items/painted/%s)" % [id, it.icon_path.get_file()])


func test_switching_swaps_the_loaded_icons() -> void:
	var heard: Array = []
	var listener := func(kind: String, style: String) -> void: heard.append([kind, style])
	Events.art_style_changed.connect(listener)
	check(Data.set_art_style("items", "painted"), "painted accepted")
	check_eq(Data.items["longsword"].icon.resource_path, "res://assets/items/painted/longsword.png", "painted icon")
	check(Data.set_art_style("items", "classic"), "classic accepted")
	check_eq(Data.items["longsword"].icon.resource_path, "res://assets/items/longsword.png", "classic icon")
	check_eq(heard, [["items", "painted"], ["items", "classic"]], "art_style_changed told the UI both times")
	Events.art_style_changed.disconnect(listener)


func test_unknown_style_is_refused() -> void:
	Data.set_art_style("items", "classic")
	check(not Data.set_art_style("items", "watercolour"), "unknown style refused")
	check_eq(GameConfig.art_style_of("items"), "classic", "style unchanged")
