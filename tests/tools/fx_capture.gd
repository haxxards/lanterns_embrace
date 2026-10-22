extends Node
## Records the combat effects frame by frame (sword swing, mace smash, dagger
## throw, arrow, Fire Bolt, Magic Missile, wolf bite) into tests/output/fx/,
## for looking at a new effect closely and for the docs' GIFs
## (tools/capture/fx_gifs.py). Needs a display (or xvfb-run):
##   godot --path . res://tests/tools/fx_capture.tscn
## Not a test: the runner only reads tests/unit and tests/integration.

var main: Node
var world: World
var hud: Hud
var combat: CombatManager


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output/fx"))
	GameState.start_new_game()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	world = main.get_node("World")
	hud = main.get_node("HUD")
	combat = world.combat
	_run()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _place_party(cell: Vector2i) -> void:
	var taken := {}
	var spots := world.grid.walkable_near(Hex.offset_to_axial(cell), 3)
	var k := 0
	for m in world.party.members:
		while taken.has(spots[k]):
			k += 1
		m.place_at(spots[k])
		taken[spots[k]] = true
	world.fog.refresh()


func _until_player_turn() -> void:
	for i in 900:
		if combat.is_player_turn() or not combat.active:
			return
		await get_tree().process_frame


func _member(id: String) -> Combatant:
	for c in combat.combatants:
		if c.is_party() and c.sheet.id == id:
			return c
	return null


func _foe(type: String) -> Combatant:
	for c in combat.combatants:
		if not c.is_party() and not c.is_out() and (c.sheet as CreatureSheet).def.id == type:
			return c
	return null


func _free_at(from: Vector2i, dist: int) -> Vector2i:
	for h in Hex.ring(from, dist):
		if world.grid.is_walkable(h) and not world.grid.is_occupied(h) and world.line_of_sight(from, h):
			return h
	return from


## Records `frames` frames (every `step`th) around a and b while `action` plays.
func _record(name: String, a: Combatant, b: Combatant, action: Callable, frames: int = 60, step: int = 1,
		heal: bool = true) -> void:
	var kept := {}
	for c in [a, b]:
		kept[c] = [c.sheet.hp_max, c.sheet.hp_current]
		if heal:  # so blows don't kill anyone mid-recording
			c.sheet.hp_max = maxi(c.sheet.hp_max, 200)
			c.sheet.hp_current = c.sheet.hp_max
	var far := a.actor.global_position.distance_to(b.actor.global_position) > 150.0
	world.camera.zoom = Vector2(1.1, 1.1) if far else Vector2(1.6, 1.6)
	world.camera.center_on((a.actor.global_position + b.actor.global_position) / 2.0 + Vector2(0, -24), true)
	await _wait(0.3)
	# The software renderer here draws a few frames a second: slow the game
	# down so the recording catches every beat (about 1/60 s apart).
	Engine.time_scale = 0.15
	action.call()
	var n := 0
	for i in frames * step:
		await RenderingServer.frame_post_draw
		if i % step != 0:
			continue
		var img := get_viewport().get_texture().get_image()
		var xf := get_viewport().get_canvas_transform()
		var pa := xf * a.actor.global_position
		var pb := xf * b.actor.global_position
		var box := Rect2(pa, Vector2.ZERO).expand(pb).grow_individual(110, 150, 110, 50)
		var size := Vector2(maxf(520.0, box.size.x), maxf(300.0, box.size.y))
		var rect := Rect2i(Rect2(box.get_center() - size / 2.0, size))
		rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(rect).save_png("res://tests/output/fx/%s_%03d.png" % [name, n])
		n += 1
	Engine.time_scale = 1.0
	for c in kept:  # put hit points back as they were
		if heal and not c.sheet.dead:
			c.sheet.hp_max = kept[c][0]
			c.sheet.hp_current = clampi(kept[c][1], 1, kept[c][0])
			c.sheet.changed.emit()
	await _wait(1.5)


func _run() -> void:
	for i in 10:
		await get_tree().process_frame
	hud._help_panel.visible = false
	hud._info_panel.visible = false
	world.camera.zoom = Vector2(1.6, 1.6)
	world.load_map("res://data/maps/old_temple_road.json", "west")
	_place_party(Vector2i(16, 25))
	await _wait(1.0)
	await _until_player_turn()
	combat.rng.seed = 3  # mostly hits
	var garrick := _member("garrick")
	var elowen := _member("elowen")
	var odran := _member("odran")
	var wren := _member("wren")
	var bandit := _foe("bandit")
	var archer := _foe("bandit_archer")
	for c in combat.combatants:
		if not c.is_party():
			c.sheet.armor_class = 1
	# Garrick's longsword.
	bandit.actor.place_at(_free_at(garrick.hex(), 1))
	await _record("sword", garrick, bandit, func() -> void:
		combat.attack_with(garrick, bandit, garrick.attacks()[0], false, false))
	# Odran's mace.
	bandit.actor.place_at(_free_at(odran.hex(), 1))
	await _record("mace", odran, bandit, func() -> void:
		combat.attack_with(odran, bandit, odran.attacks()[0], false, false))
	# Wren throws her dagger.
	bandit.actor.place_at(_free_at(wren.hex(), 3))
	var thrown: Attack = null
	for a in wren.attacks():
		if a.thrown_from != "":
			thrown = a
	await _record("thrown", wren, bandit, func() -> void:
		combat.attack_with(wren, bandit, thrown, false, false))
	# A bandit archer shoots Garrick.
	archer.actor.place_at(_free_at(garrick.hex(), 5))
	await _record("arrow", archer, garrick, func() -> void:
		combat.attack_with(archer, garrick, archer.ranged_attack(), false, false))
	# Elowen's Fire Bolt and Magic Missile.
	bandit.actor.place_at(_free_at(elowen.hex(), 5))
	var fire: SpellDef = Data.spells["fire_bolt"]
	await _record("fire_bolt", elowen, bandit, func() -> void:
		combat.attack_with(elowen, bandit, CombatSpells.spell_attack(elowen, fire, 0), false, false))
	await _record("magic_missile", elowen, bandit, func() -> void:
		CombatSpells.cast(combat, elowen, Data.spells["magic_missile"], 1, bandit.hex(), bandit), 90)
	# A wolf bites Wren.
	var spawn := {"id": "fx_wolf", "type": "wolf", "hex": _free_at(wren.hex(), 1), "group": "fx", "wander": 0}
	var cr := Creature.new()
	cr.setup(Data.creatures["wolf"], world.grid, spawn, world.party)
	world.entities.add_child(cr)
	world.creatures.append(cr)
	var wolf := combat._add_creature(cr)
	await _record("bite", wolf, wren, func() -> void:
		combat.attack_with(wolf, wren, wolf.attacks()[0], false, false))
	# Sleep on two bandits standing together, then Hold Person on a third.
	combat.abort()  # a fresh fight, at the bandit camp
	world.load_map("res://data/maps/old_temple_road.json", "west")
	_place_party(Vector2i(16, 25))
	await _wait(1.0)
	await _until_player_turn()
	elowen = _member("elowen")
	var bandits: Array[Combatant] = []
	for c in combat.combatants:
		if not c.is_party() and (c.sheet as CreatureSheet).def.id == "bandit":
			bandits.append(c)
	if bandits.size() >= 2 and elowen != null:
		var spot := _free_at(elowen.hex(), 5)
		bandits[0].actor.place_at(spot)
		bandits[1].actor.place_at(_free_at(spot, 1))
		for b in bandits:
			b.sheet.hp_current = 3
		var sleep: SpellDef = Data.spells["sleep"]
		await _record("sleep", elowen, bandits[0], func() -> void:
			CombatSpells.cast(combat, elowen, sleep, 1, bandits[0].hex(), null), 100, 1, false)
		var target: Combatant = bandits[2] if bandits.size() > 2 else _foe("bandit_archer")
		if target != null:
			target.actor.place_at(_free_at(elowen.hex(), 4))
			target.sheet.abilities["wis"] = -30  # for the picture: it fails the save
			await _record("hold_person", elowen, target, func() -> void:
				CombatSpells.cast(combat, elowen, Data.spells["hold_person"], 2, target.hex(), target), 90, 1, false)
			# A still of the whole screen: the sleepers, the held bandit, the badges.
			world.camera.zoom = Vector2(1.25, 1.25)
			world.camera.center_on((elowen.actor.global_position + bandits[0].actor.global_position
					+ target.actor.global_position) / 3.0, true)
			hud._info_panel.visible = true
			world._mouse_screen = get_viewport().get_canvas_transform() * target.actor.global_position
			world._refresh_hover(true)
			await _wait(0.8)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/output/fx/conditions.png")
	get_tree().quit()
