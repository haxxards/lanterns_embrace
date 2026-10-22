class_name World
extends Node2D
## One loaded map: terrain, props, party tokens, camera, and map mouse input.
##
## Mouse controls (BG-style):
##   left click ground    move the selection (group fans out around the target)
##   left click member    select it (Shift: add/remove)
##   left drag            box-select members (Shift: add)
##   left click sign      leader walks over and reads it
##   left click chest     leader walks over and opens it
##   left click door zone the party gathers at the door and goes in. A door
##                        zone is the ground hexes right in front of a
##                        building's door (door_zones); clicks anywhere else
##                        on a building just walk the party there, so it can
##                        walk all round a building without going in.
##   left click someone   leader walks over and talks to them
##   left click a foe     start a fight
##   right click          clear selection
##
## During a fight (CombatManager), clicks go to the combatant whose turn it
## is: ground moves them within their movement, an enemy attacks it, and
## Space ends the turn.

const DRAG_THRESHOLD := 8.0
const NO_HEX := Vector2i(-99999, -99999)
## Container ids of dropped-item piles: "ground_<q>_<r>".
const PILE_PREFIX := "ground_"

var map: MapData
var grid: HexGrid
var props: Array[Prop] = []
var props_by_hex: Dictionary = {}  # Vector2i -> Prop
## Ground hexes in front of building doors -> the building (see _build_door_zones).
var door_zones: Dictionary = {}    # Vector2i -> Prop
var _pile_props: Dictionary = {}   # Vector2i -> Prop (items dropped on the ground)

var terrain: TerrainRenderer
## Pre-rendered picture of the whole map (interiors), used instead of terrain.
var backdrop: Sprite2D
var ground_props: Node2D
var grid_lines: GridLines
var cursor: CursorOverlay
var entities: Node2D
## Combat effects (CombatFx): swings, projectiles, bursts.
var fx: Node2D
var selection_box: SelectionBox
var camera: GameCamera
var party: PartyController
var fog: FogOfWar
## Townsfolk on this map.
var npcs: Array[Npc] = []
## Hostile creatures on this map (the slain are removed).
var creatures: Array[Creature] = []
var combat: CombatManager

var _hover_hex: Vector2i = NO_HEX
var _hover_prop: Prop = null
var _hover_member: PartyMember = null
var _hover_npc: Npc = null
var _hover_creature: Creature = null
var _mouse_screen := Vector2(-1.0, -1.0)
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO
var _left_down: bool = false
var _dragging: bool = false


func _ready() -> void:
	# The world keeps taking input while paused; party tokens opt back into pausing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	terrain = TerrainRenderer.new()
	terrain.name = "Terrain"
	terrain.z_index = -10
	add_child(terrain)
	backdrop = Sprite2D.new()
	backdrop.name = "Backdrop"
	backdrop.centered = false
	backdrop.z_index = -10
	backdrop.visible = false
	add_child(backdrop)
	ground_props = Node2D.new()
	ground_props.name = "GroundProps"
	ground_props.z_index = -9
	add_child(ground_props)
	grid_lines = GridLines.new()
	grid_lines.name = "GridLines"
	grid_lines.z_index = -8
	grid_lines.visible = GameConfig.show_grid_default
	add_child(grid_lines)
	cursor = CursorOverlay.new()
	cursor.name = "Cursor"
	cursor.z_index = -7
	add_child(cursor)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	fx = Node2D.new()
	fx.name = "Fx"
	fx.z_index = 30  # above everyone, under the fog
	add_child(fx)
	fog = FogOfWar.new()
	fog.name = "Fog"
	fog.z_index = 40
	add_child(fog)
	selection_box = SelectionBox.new()
	selection_box.name = "SelectionBox"
	selection_box.z_index = 50
	add_child(selection_box)
	camera = GameCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	party = PartyController.new()
	party.name = "Party"
	party.entities = entities
	add_child(party)
	combat = CombatManager.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self)
	combat.state_changed.connect(_on_combat_changed)
	Events.selection_changed.connect(func(_s: Array) -> void: _refresh_hover(true))


## Loads a map file and places the current GameState party on it: at `entry`
## (see entry_hex), or on GameState.pending_positions after loading a save.
func load_map(path: String, entry: String = "") -> bool:
	_clear()
	map = Data.load_map(path)
	if map.width == 0 or map.height == 0:
		push_error("World: map %s is empty or unreadable" % path)
		return false
	grid = HexGrid.new()
	grid.setup(map.width, map.height, GameConfig.hex_radius)
	for r in map.height:
		for c in map.width:
			grid.set_terrain(Hex.offset_to_axial(Vector2i(c, r)), map.terrain[r * map.width + c])
	for placement in map.placements:
		if placement.def.id == "item_pile":
			_seed_item_pile(placement)
		else:
			_spawn_prop(placement)
	_spawn_saved_piles()
	grid.rebuild_pathfinding()
	_build_door_zones()

	var view_bounds := grid.world_bounds()
	if map.backdrop_path.is_empty():
		terrain.visible = true
		backdrop.visible = false
		terrain.build(grid)
	else:
		terrain.visible = false
		backdrop.visible = true
		backdrop.texture = Data.load_texture(map.backdrop_path)
		backdrop.offset = -map.backdrop_origin
		view_bounds = view_bounds.merge(Rect2(backdrop.offset, backdrop.texture.get_size()))
	grid_lines.build(grid)
	cursor.grid = grid
	cursor.party = party
	party.grid = grid
	RenderingServer.set_default_clear_color(map.background_color)

	_spawn_npcs()
	_spawn_creatures()
	var spawn := entry_hex(entry)
	party.spawn_party(GameState.party, spawn, GameState.pending_positions)
	GameState.pending_positions.clear()
	for m in party.members:
		m.hex_entered.connect(func(_m: PartyMember, _h: Vector2i) -> void: fog.mark_dirty())
	var wholes: Array = []
	if map.fog:
		for p in props:
			if p.def.blocks_sight and p.cells.size() > 1:
				wholes.append({"cells": p.cells, "covered": p.covered_hexes(grid)})
	fog.setup(grid, map.id, map.fog, party.members, wholes)
	camera.set_bounds(view_bounds)
	var focus: Vector2 = GameState.pending_camera if GameState.pending_camera is Vector2 \
			else grid.hex_to_world(spawn)
	GameState.pending_camera = null
	camera.center_on(focus, true)
	GameState.current_map_path = path
	GameState.current_entry = entry
	Audio.play_music(map.music)
	Audio.play_ambience(map.ambience)
	Events.map_loaded.emit(map.id)
	if not GameState.pending_combat.is_empty():
		var fight := GameState.pending_combat
		GameState.pending_combat = {}
		combat.restore(fight)  # a game saved mid-fight: the fight goes on
	return true


## Where the party arrives: a named entry from the map file, else the ground
## in front of the door of the prop with that "id", else the map's spawn.
func entry_hex(entry: String) -> Vector2i:
	if entry.is_empty():
		return map.party_spawn
	if map.entries.has(entry):
		return map.entries[entry]
	for p in props:
		if p.state_id() == entry:
			var h: Variant = p.entry_hex(grid)
			if h != null:
				return h
	push_warning("Map %s has no entry '%s'; using the party spawn" % [map.id, entry])
	return map.party_spawn


## Hex of every party member, by character id (for saving).
func party_positions() -> Dictionary:
	var out := {}
	for m in party.members:
		out[m.sheet.id] = m.hex
	return out


func _clear() -> void:
	combat.abort()
	for f in fx.get_children():
		f.queue_free()
	for cr in creatures:
		cr.queue_free()
	creatures.clear()
	_hover_creature = null
	for p in props:
		p.queue_free()
	props.clear()
	props_by_hex.clear()
	door_zones.clear()
	_pile_props.clear()
	for n in npcs:
		n.queue_free()
	npcs.clear()
	_hover_npc = null
	_hover_prop = null
	_hover_member = null
	_hover_hex = NO_HEX


## Each building's door zone: the walkable hexes touching its door, outside its
## footprint (Prop.approach_hexes). Clicking one of them is the only way in.
func _build_door_zones() -> void:
	door_zones.clear()
	for p in props:
		if p.interaction() == "enter":
			for h in p.approach_hexes(grid):
				door_zones[h] = p


## The building whose door zone `h` is in (once the building has been seen), or null.
func door_at(h: Vector2i) -> Prop:
	var p: Prop = door_zones.get(h)
	return p if p != null and _seen(p) else null


## The hexes of one building's door zone.
func door_zone_of(building: Prop) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in door_zones:
		if door_zones[h] == building:
			out.append(h)
	return out


func _spawn_prop(placement: MapData.Placement) -> Prop:
	var prop := Prop.new()
	prop.setup(placement, grid)
	for cell in prop.cells:
		if not grid.in_bounds(cell):
			push_warning("Prop %s footprint leaves the map at %s" % [prop.name, cell])
			continue
		if props_by_hex.has(cell) and props_by_hex[cell].def.blocks_movement and placement.def.blocks_movement:
			push_warning("Prop %s overlaps %s" % [prop.name, props_by_hex[cell].name])
		grid.add_prop_cell(cell, placement.def)
		props_by_hex[cell] = prop
	if prop.interaction() == "container":
		# Contents live in GameState so they persist; the map only seeds them.
		var state := GameState.get_container(map.id, prop.state_id())
		if state == null:
			state = ContainerState.from_placement(placement.extra)
			GameState.set_container(map.id, prop.state_id(), state)
		prop.container = state
	if placement.def.layer == PropDef.LAYER_GROUND:
		ground_props.add_child(prop)
	else:
		entities.add_child(prop)
	props.append(prop)
	return prop


# --- townsfolk ---------------------------------------------------------------------

## Places the map's NPCs (before the party, so the party avoids their hexes).
func _spawn_npcs() -> void:
	for spawn in map.npc_spawns:
		var def: NpcDef = Data.npcs.get(spawn["id"])
		if def == null:
			push_warning("Map %s places unknown NPC '%s'" % [map.id, spawn["id"]])
			continue
		var h: Vector2i = spawn["hex"]
		if not grid.is_walkable(h):
			push_warning("NPC %s stands on blocked ground at %s" % [def.id, h])
			continue
		var npc := Npc.new()
		npc.setup(def, grid, h, party)
		entities.add_child(npc)
		npcs.append(npc)


## The visible NPC under a world position (front-most first).
func npc_at(world_pos: Vector2) -> Npc:
	var best: Npc = null
	for n in npcs:
		if n.visible and n.pick_rect().has_point(world_pos) and (best == null or n.position.y > best.position.y):
			best = n
	return best


func npc(npc_id: String) -> Npc:
	for n in npcs:
		if n.def.id == npc_id:
			return n
	return null


# --- hostile creatures -----------------------------------------------------------------

## Places the map's creatures, except those slain earlier.
func _spawn_creatures() -> void:
	for spawn in map.creature_spawns:
		if GameState.is_defeated(map.id, spawn["id"]):
			continue
		var def: CreatureDef = Data.creatures.get(spawn["type"])
		if def == null:
			push_warning("Map %s places unknown creature '%s'" % [map.id, spawn["type"]])
			continue
		if not grid.is_walkable(spawn["hex"]):
			push_warning("Creature %s stands on blocked ground at %s" % [spawn["id"], spawn["hex"]])
			continue
		var cr := Creature.new()
		cr.setup(def, grid, spawn, party)
		entities.add_child(cr)
		creatures.append(cr)


## "  ·  asleep, prone" for someone in the fight with conditions, else "".
func _conditions_text(actor: Node) -> String:
	var c := combat.combatant_of(actor) if combat.active else null
	if c == null or c.conditions().is_empty():
		return ""
	return "  ·  " + ", ".join(c.conditions())


## The visible, living creature under a world position (front-most first).
func creature_at(world_pos: Vector2) -> Creature:
	var best: Creature = null
	for cr in creatures:
		if cr.visible and cr.is_alive() and cr.pick_rect().has_point(world_pos) \
				and (best == null or cr.position.y > best.position.y):
			best = cr
	return best


## Clear if no hex strictly between a and b blocks sight.
func line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var line := Hex.line(a, b)
	for k in range(1, line.size() - 1):
		if grid.blocks_sight(line[k]):
			return false
	return true


## Living creatures not yet fighting that can see a conscious party member
## within their aggro range.
func hostiles_noticing(fight: CombatManager = null) -> Array[Creature]:
	var out: Array[Creature] = []
	for cr in creatures:
		if not cr.is_alive() or cr.in_combat or (fight != null and fight.combatant_of(cr) != null):
			continue
		for m in party.members:
			if m.is_alive() and Hex.distance(m.hex, cr.hex) <= cr.def.aggro and line_of_sight(m.hex, cr.hex):
				out.append(cr)
				break
	return out


## Starts a fight with `trigger`'s whole encounter group, plus anything else
## that has noticed the party.
func start_combat(trigger: Creature) -> void:
	if combat.active:
		return
	var foes: Array = []
	for cr in creatures:
		if cr.is_alive() and (cr == trigger or (cr.group == trigger.group and not trigger.group.is_empty())):
			foes.append(cr)
	for cr in hostiles_noticing():
		if not foes.has(cr):
			foes.append(cr)
	combat.start(foes)


## Called by the fight when a creature dies: loot on the ground, remembered
## as slain, and its group marked beaten once none of it is left.
func on_creature_slain(cr: Creature) -> void:
	creatures.erase(cr)
	if _hover_creature == cr:
		_hover_creature = null
	GameState.mark_defeated(map.id, cr.spawn_id)
	_drop_loot(cr)
	var group_left := false
	for other in creatures:
		if other.group == cr.group and other.is_alive():
			group_left = true
	if not group_left and not cr.group.is_empty():
		GameState.mark_group_defeated(cr.group)
	cr.die()


func _drop_loot(cr: Creature) -> void:
	var drops: Array[ItemStack] = []
	for e in cr.def.loot:
		if combat.rng.randf() > float(e.get("chance", 1.0)):
			continue
		var qty_v: Variant = e.get("qty", 1)
		var qty := Rules.roll_expr(str(qty_v), combat.rng) if qty_v is String else int(qty_v)
		if qty > 0 and Data.items.has(str(e["item"])):
			drops.append(ItemStack.create(str(e["item"]), qty))
	if drops.is_empty():
		return
	var pile := ground_pile(cr.hex, true)
	for st in drops:
		pile.inventory.add(st)


# --- items on the ground ----------------------------------------------------------

## The pile of items dropped on hex `h`, or null. With `create`, an empty pile
## is made (it only shows on the map once something is in it). Piles are
## ordinary containers kept in GameState, so they persist and are saved.
func ground_pile(h: Vector2i, create: bool = false) -> ContainerState:
	var id := _pile_id(h)
	var state := GameState.get_container(map.id, id)
	if state == null and create:
		state = ContainerState.new()
		state.inventory = Inventory.new(ContainerState.MIN_SLOTS)
		GameState.set_container(map.id, id, state)
	if state != null and not state.inventory.changed.is_connected(_on_pile_changed):
		state.inventory.changed.connect(_on_pile_changed.bind(h, state))
	return state


func _pile_id(h: Vector2i) -> String:
	return "%s%d_%d" % [PILE_PREFIX, h.x, h.y]


## Shows or removes the pile's sprite as items are dropped or picked up.
func _on_pile_changed(h: Vector2i, state: ContainerState) -> void:
	if map == null or GameState.get_container(map.id, _pile_id(h)) != state:
		return  # a pile from a map that is no longer loaded
	var prop: Prop = _pile_props.get(h)
	if state.inventory.is_empty():
		if prop != null:
			_pile_props.erase(h)
			props.erase(prop)
			if props_by_hex.get(h) == prop:
				props_by_hex.erase(h)
				for other in props:  # something else may stand on that hex too
					if other.cells.has(h):
						props_by_hex[h] = other
			if _hover_prop == prop:
				_hover_prop = null
			prop.queue_free()
	elif prop == null:
		var pl := MapData.Placement.new()
		pl.def = Data.props["item_pile"]
		pl.cell = Hex.axial_to_offset(h)
		pl.anchor = h
		pl.cells = [h]
		pl.extra = {"id": _pile_id(h), "name": "Items on the ground"}
		_pile_props[h] = _spawn_prop(pl)


## Items the map file leaves lying about ("item_pile" props) join the ground
## pile on that hex the first time the map loads, so they behave exactly like
## dropped items afterwards (and are not put back once picked up).
func _seed_item_pile(placement: MapData.Placement) -> void:
	var flag := "seeded:%s:%s" % [map.id, str(placement.extra.get("id", placement.cell))]
	if GameState.flags.has(flag):
		return
	GameState.flags[flag] = true
	var state := ground_pile(placement.anchor, true)
	for e in placement.extra.get("items", []):
		state.inventory.add(ItemStack.create(str(e["item"]), int(e.get("qty", 1))))


## Piles dropped on this map earlier (or loaded from a save).
func _spawn_saved_piles() -> void:
	var saved := GameState.containers_for(map.id)
	for id in saved:
		if str(id).begins_with(PILE_PREFIX):
			var parts := str(id).trim_prefix(PILE_PREFIX).split("_")
			var h := Vector2i(int(parts[0]), int(parts[1]))
			var state := ground_pile(h)
			if state != null and not state.inventory.is_empty():
				_on_pile_changed(h, state)


# --- input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if grid == null:
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif combat.active and event.is_action_pressed("toggle_pause"):
		combat.end_turn()  # Space ends the turn in a fight
	elif combat.active and (event.is_action_pressed("select_all") or _is_select_key(event)):
		pass  # the turn order decides who acts
	elif event.is_action_pressed("toggle_pause"):
		set_paused(not get_tree().paused)
	elif event.is_action_pressed("toggle_grid"):
		grid_lines.visible = not grid_lines.visible
	elif event.is_action_pressed("select_all"):
		party.select_all()
	elif event.is_action_pressed("cam_center_selection"):
		focus_selection()
	else:
		for i in 9:
			if event.is_action_pressed("select_member_%d" % (i + 1)):
				party.select_index(i, Input.is_key_pressed(KEY_SHIFT))
				break


func _is_select_key(event: InputEvent) -> bool:
	for i in 9:
		if event.is_action_pressed("select_member_%d" % (i + 1)):
			return true
	return false


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	_mouse_screen = mb.position
	var world_pos := screen_to_world(mb.position)
	if combat.active:
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_combat_click(world_pos)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			combat.cancel_targeting()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_left_down = true
			_dragging = false
			_press_screen = mb.position
			_press_world = world_pos
		elif _left_down:
			_left_down = false
			if _dragging:
				_dragging = false
				selection_box.active = false
				party.select_in_rect(Rect2(_press_world, world_pos - _press_world).abs(), mb.shift_pressed)
			else:
				_on_click(world_pos, mb.shift_pressed)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		party.clear_selection()


func _on_mouse_motion(mm: InputEventMouseMotion) -> void:
	_mouse_screen = mm.position
	if _left_down and not _dragging and mm.position.distance_to(_press_screen) > DRAG_THRESHOLD:
		_dragging = true
		selection_box.active = true
	if _dragging:
		selection_box.set_rect(Rect2(_press_world, screen_to_world(mm.position) - _press_world))
	_refresh_hover()


func _on_click(world_pos: Vector2, shift: bool) -> void:
	var foe := creature_at(world_pos)
	if foe and party.leader():
		start_combat(foe)
		return
	var member := party.member_at(world_pos)
	if member:
		if shift:
			party.toggle(member)
		else:
			party.select_only(member)
		return
	var person := npc_at(world_pos)
	if person and party.leader():
		person.hold()
		if not party.interact_with(person):
			person.end_talk()
		return
	var door := door_at(grid.world_to_hex(world_pos))
	if door and party.leader():
		party.interact_with(door)
		return
	var prop := _interactable_at(world_pos)
	if prop and party.leader():
		party.interact_with(prop)
		return
	party.move_selected_to(grid.world_to_hex(world_pos))
	_refresh_hover(true)


## A click during a fight: an enemy is attacked, ground is walked to. While a
## spell waits for a target, the click chooses it instead.
func _on_combat_click(world_pos: Vector2) -> void:
	if not combat.is_player_turn():
		return
	if not combat.targeting.is_empty():
		combat.confirm_target(grid.world_to_hex(world_pos), _combatant_at(world_pos))
		_refresh_hover(true)
		return
	var foe := creature_at(world_pos)
	if foe:
		combat.player_attack(combat.combatant_of(foe))
	elif party.member_at(world_pos) == null:
		combat.player_move(grid.world_to_hex(world_pos))
	_refresh_hover(true)


## The fighter (creature or party member) under the cursor, or null.
func _combatant_at(world_pos: Vector2) -> Combatant:
	var foe := creature_at(world_pos)
	if foe:
		return combat.combatant_of(foe)
	var member := party.member_at(world_pos)
	if member:
		return combat.combatant_of(member)
	return combat.combatant_at_hex(grid.world_to_hex(world_pos))


## Viewport (screen) position -> world position, through the camera.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	Events.pause_changed.emit(paused)


func focus_selection() -> void:
	var list: Array = party.selected if not party.selected.is_empty() else party.members
	if list.is_empty():
		return
	var sum := Vector2.ZERO
	for m in list:
		sum += m.global_position
	camera.center_on(sum / list.size())


## Interactable prop under the cursor: sprite rectangle first, then footprint.
## Props still under black fog can't be picked, and buildings aren't picked
## at all: they are entered from their door zones (door_at).
func _interactable_at(world_pos: Vector2) -> Prop:
	var best: Prop = null
	for p in props:
		if _clickable(p) and p.sprite_rect().has_point(world_pos):
			if best == null or p.position.y > best.position.y:  # front-most wins
				best = p
	if best:
		return best
	var under: Prop = props_by_hex.get(grid.world_to_hex(world_pos))
	return under if under and _clickable(under) else null


func _clickable(p: Prop) -> bool:
	return p.is_interactable() and p.interaction() != "enter" and _seen(p)


## The building drawn under the cursor (its visible pixels, not its whole
## picture rectangle), front-most first, or null.
func _building_at(world_pos: Vector2) -> Prop:
	var best: Prop = null
	for p in props:
		if p.interaction() == "enter" and _seen(p) and p.is_opaque_at(world_pos):
			if best == null or p.position.y > best.position.y:
				best = p
	return best


func _seen(p: Prop) -> bool:
	for c in p.cells:
		if fog.is_explored(c):
			return true
	return false


# --- hover feedback ----------------------------------------------------------------

## Shows where the party member whose turn it is can still walk.
func _on_combat_changed() -> void:
	cursor.reachable = combat.reachable_for(combat.current) if combat.is_player_turn() else {}
	if not combat.active:
		cursor.preview_path.clear()
	_refresh_hover(true)


## Hover during a fight: the path for the combatant whose turn it is, or what
## attacking the enemy under the cursor would do.
func _combat_hover(h: Vector2i, foe: Creature, info: Dictionary) -> void:
	cursor.preview_path.clear()
	cursor.hover_hex = null
	cursor.area = []
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if not combat.is_player_turn():
		cursor.reachable = {}
		combat.set_hint("")
		return
	var me := combat.current
	if not combat.targeting.is_empty():
		# Choosing a spell's target: show what it would cover and do.
		var p := combat.preview_target(h, _combatant_at(screen_to_world(_mouse_screen)))
		cursor.area = p["hexes"]
		cursor.area_ok = p["ok"]
		info["action"] = str(p["text"])
		combat.set_hint("%s   (right-click or Esc: cancel)" % p["text"])
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if p["ok"] else Input.CURSOR_FORBIDDEN)
		return
	if foe:
		var text := combat.describe_attack(me, combat.combatant_of(foe))
		info["action"] = text
		combat.set_hint(text)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		return
	if not grid.in_bounds(h) or h == me.hex():
		combat.set_hint("")
		return
	cursor.hover_hex = h
	if cursor.reachable.has(h):
		cursor.hover_color = CursorOverlay.HOVER_OK
		cursor.preview_path = me.actor.path_to(h)
		var ft := roundi(float(cursor.reachable[h]) * GameConfig.feet_per_hex)
		combat.set_hint("Move %d ft  (%d ft left)" % [ft, roundi(me.movement_left)])
	else:
		cursor.hover_color = CursorOverlay.HOVER_BLOCKED
		combat.set_hint("Too far: %d ft of movement left" % roundi(me.movement_left) if grid.is_walkable(h)
				else "Can't stand there")

func _process(_delta: float) -> void:
	if grid == null:
		return
	# Keep the path preview honest while the party walks.
	if party.leader() and party.leader().is_moving():
		_refresh_hover(true)
	_update_occlusion()
	for n in npcs:  # townsfolk and creatures only show where the party can see
		n.visible = fog.is_in_sight(n.hex)
	for cr in creatures:
		cr.visible = fog.is_in_sight(cr.hex)
	if not combat.active and not get_tree().paused:
		var noticed := hostiles_noticing()
		if not noticed.is_empty():
			start_combat(noticed[0])


## Fades tall props (trees, buildings) that hide a party member behind them.
func _update_occlusion() -> void:
	for p in props:
		if not p.def.fade_when_occluding:
			continue
		var hide_someone := false
		var rect := p.sprite_rect()
		for m in party.members:
			if p.position.y > m.position.y and rect.intersects(m.pick_rect().grow(-6.0)):
				hide_someone = true
				break
		p.faded = hide_someone


func _refresh_hover(force: bool = false) -> void:
	if grid == null or _mouse_screen.x < 0.0:
		return
	var world_pos := screen_to_world(_mouse_screen)
	var h := grid.world_to_hex(world_pos)
	var member := party.member_at(world_pos)
	var foe := creature_at(world_pos) if member == null else null
	var person := npc_at(world_pos) if member == null and foe == null else null
	var free := member == null and foe == null and person == null and not combat.active
	var door := door_at(h) if free else null
	var prop := door if door else (_interactable_at(world_pos) if person == null and foe == null and not combat.active else null)
	if not force and h == _hover_hex and member == _hover_member and prop == _hover_prop and person == _hover_npc \
			and foe == _hover_creature:
		return
	if _hover_creature and is_instance_valid(_hover_creature):
		_hover_creature.hovered = false
	_hover_creature = foe
	if foe:
		foe.hovered = true
	if _hover_member and is_instance_valid(_hover_member):
		_hover_member.hovered = false
	if _hover_npc and is_instance_valid(_hover_npc):
		_hover_npc.hovered = false
	_hover_npc = person
	if person:
		person.hovered = true
	if _hover_prop and is_instance_valid(_hover_prop):
		_hover_prop.highlighted = false
	_hover_hex = h
	_hover_member = member
	_hover_prop = prop
	if member:
		member.hovered = true
	if prop:
		prop.highlighted = true

	var info := {
		"hex": h,
		"cell": Hex.axial_to_offset(h),
		"in_bounds": grid.in_bounds(h),
	}
	cursor.preview_path.clear()
	cursor.door_zone = []
	if not combat.active:
		cursor.reachable = {}
	cursor.hover_hex = null
	if grid.in_bounds(h):
		cursor.hover_hex = h
	var t := grid.get_terrain(h)
	if t:
		info["terrain"] = t.display_name
		info["walkable"] = grid.is_walkable(h)
		info["move_cost"] = grid.move_cost(h)
	var any_prop: Prop = props_by_hex.get(h)
	if any_prop and not _seen(any_prop):
		any_prop = null
	if prop:
		info["prop"] = prop.display_name()
	elif any_prop:
		info["prop"] = any_prop.display_name()
	if member:
		info["member"] = "%s  ·  %s%s" % [member.sheet.display_name, CreatureTypes.describe(member.sheet),
				_conditions_text(member)]
	if foe:
		info["member"] = "%s  (%d/%d HP)  ·  %s%s" % [foe.def.display_name, foe.sheet.hp_current, foe.sheet.hp_max,
				CreatureTypes.describe(foe.sheet), _conditions_text(foe)]
	if combat.active:
		_combat_hover(h, foe, info)
		Events.hover_info_changed.emit(info)
		return
	if person:
		info["member"] = "%s, %s" % [person.def.display_name, person.def.title] if not person.def.title.is_empty() \
				else person.def.display_name

	var cursor_shape := Input.CURSOR_ARROW
	if foe:
		cursor.hover_hex = null
		cursor_shape = Input.CURSOR_POINTING_HAND
		info["action"] = "Click to attack"
	elif member:
		cursor.hover_hex = null
	elif person:
		cursor.hover_hex = null
		cursor_shape = Input.CURSOR_POINTING_HAND
	elif door:
		# In front of a door: the whole zone lights up and a click goes in.
		cursor.hover_color = CursorOverlay.HOVER_INTERACT
		cursor.door_zone = door_zone_of(door)
		cursor.door_zone_hot = true
		cursor_shape = Input.CURSOR_POINTING_HAND
		info["action"] = "Click to go in"
	elif prop:
		cursor.hover_color = CursorOverlay.HOVER_INTERACT
		cursor_shape = Input.CURSOR_POINTING_HAND
	elif party.leader():
		var leader := party.leader()
		var walkable := grid.is_walkable(h)
		cursor.hover_color = CursorOverlay.HOVER_OK if walkable else CursorOverlay.HOVER_BLOCKED
		if walkable and h != leader.hex:
			var path := grid.find_path(leader.hex, h)
			if path.is_empty():
				cursor.hover_color = CursorOverlay.HOVER_BLOCKED
			else:
				cursor.preview_path = path
				info["path_hexes"] = path.size()
				info["path_cost"] = grid.path_cost(path)
				info["path_feet"] = int(grid.path_cost(path) * GameConfig.feet_per_hex)
		elif not walkable:
			cursor_shape = Input.CURSOR_FORBIDDEN
	else:
		# Nothing selected: no movement option, so no hex highlight.
		cursor.hover_hex = null
	if free and door == null and prop == null:
		# On a building's walls or roof: a click only walks there, so show
		# where its door zone is.
		var building := _building_at(world_pos)
		if building:
			cursor.door_zone = door_zone_of(building)
			cursor.door_zone_hot = false
			info["prop"] = building.display_name()
			info["action"] = "Click in front of the door to go in"
	Input.set_default_cursor_shape(cursor_shape)
	Events.hover_info_changed.emit(info)
