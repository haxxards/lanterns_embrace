class_name Prop
extends Node2D
## A placed map object (tree, house, sign, chest...). Its node position is
## the anchor hex centre, which is also the point used for y-sorting.
##
## Interactions (from props.json, or "interaction" on the map placement):
##   read       show the placement's "title" and "text"
##   container  open its contents (ContainerState kept in GameState)
##   enter      go into the building's "interior" map
##   exit       leave for the placement's "map" at its "entry"

var def: PropDef
var look: PropDef.Look
var look_index: int = 0
var anchor: Vector2i
var cells: Array[Vector2i] = []
## Per-instance data from the map file ("name", "title", "text"...).
var extra: Dictionary = {}
## Contents, for containers (set by World when the prop is spawned).
var container: ContainerState
var highlighted: bool = false:
	set(value):
		highlighted = value
		_update_modulate()
## See-through while a party member is behind it.
var faded: bool = false:
	set(value):
		if value != faded:
			faded = value
			_update_modulate()

var _sprite: Sprite2D


func setup(placement: MapData.Placement, grid: HexGrid) -> void:
	def = placement.def
	look_index = placement.look
	look = def.look(look_index)
	anchor = placement.anchor
	extra = placement.extra
	cells = placement.cells.duplicate()
	name = "%s_%d_%d" % [def.id, placement.cell.x, placement.cell.y]
	# Rect footprints (buildings) sit on their footprint's bottom edge, which is
	# also their y-sort point; other props sit on their anchor hex.
	position = PropDef.placement_point(def, cells, anchor, grid.radius)
	_sprite = Sprite2D.new()
	_sprite.texture = look.texture
	_sprite.centered = false
	_sprite.offset = -look.origin
	add_child(_sprite)


## Hex the entrance opens from (buildings), or null.
func door_hex(grid: HexGrid) -> Variant:
	return PropDef.door_hex(def, cells, anchor, grid.radius, look_index)


func _update_modulate() -> void:
	var c := Color(1.25, 1.2, 1.05) if highlighted else Color.WHITE
	c.a = 0.45 if faded else 1.0
	modulate = c


func display_name() -> String:
	return str(extra.get("name", extra.get("title", def.display_name)))


## The interaction kind: the placement can override the prop type's.
func interaction() -> String:
	return str(extra.get("interaction", def.interaction))


func is_interactable() -> bool:
	return not interaction().is_empty()


## Doors and exits move the party to another map.
func is_transition() -> bool:
	return interaction() == "enter" or interaction() == "exit"


## Stable id for saving state (the map's "id", else type + cell).
func state_id() -> String:
	return str(extra.get("id", name))


## Map and entry this door or exit leads to.
func target_map() -> String:
	return str(extra.get("interior", "")) if interaction() == "enter" else str(extra.get("map", ""))


func target_entry() -> String:
	return str(extra.get("entry", "door" if interaction() == "enter" else ""))


## World-space rectangle covered by the sprite.
func sprite_rect() -> Rect2:
	return Rect2(global_position + _sprite.offset, _sprite.texture.get_size())


## Walkable hexes where a character stands to interact: next to the door for
## buildings, otherwise around the footprint (or on it, if it can be walked on).
func approach_hexes(grid: HexGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var door: Variant = door_hex(grid) if interaction() == "enter" else null
	var around: Array[Vector2i] = []
	if door != null:
		around.append(door)
	else:
		around = cells.duplicate()
	for c in around:
		if not def.blocks_movement and grid.is_walkable(c) and not out.has(c):
			out.append(c)
		for n in Hex.neighbors(c):
			if not cells.has(n) and not out.has(n) and grid.is_walkable(n):
				out.append(n)
	return out


## Ground in front of the door (where a party arriving from inside appears).
func entry_hex(grid: HexGrid) -> Variant:
	var hexes := approach_hexes(grid)
	if hexes.is_empty():
		return null
	var best: Vector2i = hexes[0]
	for h in hexes:  # prefer the hex most in front (largest y) of the door
		if grid.hex_to_world(h).y > grid.hex_to_world(best).y + 0.1:
			best = h
	return best


func is_adjacent_to(h: Vector2i) -> bool:
	for c in cells:
		if Hex.distance(c, h) == 1 or (c == h and not def.blocks_movement):
			return true
	return false


## Runs this prop's interaction for `actor`. Extend the match for new kinds.
func interact(actor: PartyMember) -> void:
	match interaction():
		"read":
			Events.message_requested.emit(str(extra.get("title", display_name())),
					str(extra.get("text", "The writing is too faded to read.")))
		"container":
			_open_container(actor.sheet)
		"enter", "exit":
			if target_map().is_empty():
				Events.toast_requested.emit("The door is barred.")
				return
			Audio.play_sfx("door_open")
			Events.map_change_requested.emit(target_map(), target_entry())
		_:
			push_warning("Prop %s has unknown interaction '%s'" % [name, interaction()])


## Opens a container, dealing with its lock first: a key anywhere in the party
## opens it; otherwise someone with thieves' tools can try to pick it
## (d20 + Dex, + proficiency if trained, against the lock's DC).
func _open_container(opener: CharacterSheet) -> void:
	if container == null:
		return
	if container.locked:
		var key_def: ItemDef = Data.items.get(container.key_id)
		var has_key := false
		for s in GameState.party:
			has_key = has_key or (not container.key_id.is_empty() and s.has_item(container.key_id))
		if has_key:
			container.locked = false
			Audio.play_sfx("unlock")
			Events.toast_requested.emit("Unlocked with the %s." % (key_def.display_name if key_def else "key"))
		elif container.lock_dc > 0 and opener.inventory.has_tool("lockpick"):
			var trained := (opener.proficiencies.get("tools", []) as Array).has("thieves_tools")
			var roll := Rules.ability_check(opener, "dex", trained)
			if roll < container.lock_dc:
				Audio.play_sfx("locked")
				Events.toast_requested.emit("%s fails to pick the lock (%d vs DC %d)." % [opener.display_name, roll, container.lock_dc])
				return
			container.locked = false
			Audio.play_sfx("unlock")
			Events.toast_requested.emit("%s picks the lock (%d vs DC %d)." % [opener.display_name, roll, container.lock_dc])
		else:
			Audio.play_sfx("locked")
			var hint := " Someone with thieves' tools might open it." if container.lock_dc > 0 else ""
			Events.toast_requested.emit("The %s is locked.%s" % [display_name().to_lower(), hint])
			return
	Audio.play_sfx("chest_open")
	Events.container_opened.emit(container, display_name(), opener)
