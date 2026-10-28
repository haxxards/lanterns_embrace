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
## The dialog asking about a trap the party found (the last one; for tests).
var trap_dialog: ChoiceDialog = null
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
var _image: Image  # the texture's pixels, read on first use (is_opaque_at)


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


## Hexes the opaque part of the sprite is drawn over. A tall building's roof
## covers ground north of its footprint; the fog shows those hexes together
## with the building (see FogOfWar.setup) so the roof isn't blacked out.
func covered_hexes(grid: HexGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if look.texture == null:
		return out
	var img := look.texture.get_image()
	if img == null:
		return out
	if img.is_compressed():
		img.decompress()
	var rect := Rect2(position - look.origin, look.texture.get_size())
	var a := Hex.axial_to_offset(grid.world_to_hex(rect.position))
	var b := Hex.axial_to_offset(grid.world_to_hex(rect.end))
	for r in range(a.y - 1, b.y + 2):
		for c in range(a.x - 1, b.x + 2):
			var h := Hex.offset_to_axial(Vector2i(c, r))
			var p := grid.hex_to_world(h)
			if not grid.in_bounds(h) or not rect.has_point(p):
				continue
			var px := Vector2i(p - rect.position).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE)
			if img.get_pixelv(px).a > 0.5:
				out.append(h)
	return out


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


## True if the sprite actually draws something at `world_pos` (not just
## somewhere inside its rectangle).
func is_opaque_at(world_pos: Vector2) -> bool:
	var rect := sprite_rect()
	if not rect.has_point(world_pos):
		return false
	if _image == null:
		_image = _sprite.texture.get_image()
		if _image == null:
			return true
		if _image.is_compressed():
			_image.decompress()
	var px := Vector2i(world_pos - rect.position).clamp(Vector2i.ZERO, _image.get_size() - Vector2i.ONE)
	return _image.get_pixelv(px).a > 0.5


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


## Opens a container, dealing with a trap first (Traps: the party's best
## passive Perception may notice it, and then a dialog asks what to do;
## unnoticed, it goes off on the opener), then its lock: a key anywhere in
## the party opens it; otherwise someone with thieves' tools can try to pick
## it (d20 + Dex, + proficiency if trained, against the lock's DC).
func _open_container(opener: CharacterSheet) -> void:
	if container == null:
		return
	if Traps.is_live(container.trap):
		var spotter := Traps.notice(container.trap, GameState.party)
		if Traps.is_found(container.trap):
			_ask_about_trap(opener, spotter)
			return
		var hurt := Traps.spring(container.trap, opener)
		Audio.play_sfx("hit")
		Events.toast_requested.emit("A %s! %s" % [container.trap.get("name", "trap"), hurt])
		if not opener.is_alive():
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
			var roll := Rules.ability_check(opener, "dex", trained, null, trained and opener.has_feature("expertise"))
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



## A found trap: disarm it (the party's best at it tries), open it anyway (it
## goes off on `opener`), or leave the container alone. `spotter` is who just
## noticed it (null if it was found before).
func _ask_about_trap(opener: CharacterSheet, spotter: CharacterSheet) -> void:
	var trap := container.trap
	var name := str(trap.get("name", "trap"))
	var text := ("%s notices a %s on the %s." % [spotter.display_name, name, display_name().to_lower()]) \
			if spotter != null else "The %s on the %s is still there." % [name, display_name().to_lower()]
	var answers := PackedStringArray()
	var who := Traps.best_disarmer(trap, GameState.party)
	if who != null:
		answers.append("Disarm it: %s, %s %s vs DC %d" % [who.display_name, Traps.disarm_means(trap),
				Rules.format_modifier(Traps.disarm_bonus(trap, who)),
				int((trap.get("disarm", {}) as Dictionary).get("dc", 10))])
	else:
		text += " Disarming it needs %s, and no one has them." % Traps.disarm_means(trap)
	answers.append("Open it anyway (%s sets it off)" % opener.display_name)
	answers.append("Leave it alone")
	trap_dialog = ChoiceDialog.ask(self, "A trap!", text, answers)
	trap_dialog.chosen.connect(_on_trap_answer.bind(opener, who))


## The answer to the trap dialog: 0 disarm (`who` tries), 1 open it anyway,
## 2 leave it. Without anyone to disarm it, the answers start at "open".
func _on_trap_answer(index: int, opener: CharacterSheet, who: CharacterSheet) -> void:
	var trap := container.trap
	var choice := index if who != null else index + 1
	if choice == 0:
		var r := Traps.try_disarm(trap, who)
		Audio.play_sfx("unlock" if r["ok"] else ("hit" if r["sprung"] else "locked"))
		Events.toast_requested.emit(str(r["text"]))
		if r["ok"] or (r["sprung"] and opener.is_alive()):
			_open_container(opener)
	elif choice == 1:
		var hurt := Traps.spring(trap, opener)
		Audio.play_sfx("hit")
		Events.toast_requested.emit("%s opens it anyway. %s" % [opener.display_name, hurt])
		if opener.is_alive():
			_open_container(opener)
