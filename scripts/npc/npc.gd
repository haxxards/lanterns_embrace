class_name Npc
extends Actor
## A townsperson on the map. Stands near their spot and strolls a little,
## blocks the hex they stand on (HexGrid.set_occupied), turns to face whoever
## talks to them, and is hidden while outside the party's sight.
##
## Clicking one sends the leader over (PartyController.interact_with), and on
## arrival interact() asks the HUD to start their dialogue.

const HOVER_COLOR := Color(1.0, 0.85, 0.4, 0.85)
const WALK_SPEED := 70.0

var def: NpcDef
var home: Vector2i
## Set by World so wandering keeps clear of the party.
var party: PartyController
var talking: bool = false

var _wait: float = 0.0


func setup(d: NpcDef, grid: HexGrid, start: Vector2i, party_controller: PartyController) -> void:
	def = d
	_grid = grid
	home = start
	party = party_controller
	name = "Npc_%s" % d.id
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_sprite(d.animation_path, d.sprite_path, null)
	place_at(start)
	_grid.set_occupied(start, true)
	_wait = randf_range(2.0, 6.0)


func move_speed() -> float:
	return WALK_SPEED


func _process(delta: float) -> void:
	super._process(delta)
	if is_moving() or talking or def.wander_radius <= 0:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = randf_range(4.0, 9.0)
		_wander()


## Strolls to a random free hex near home, away from the party.
func _wander() -> void:
	var options: Array[Vector2i] = []
	for h in Hex.spiral(home, def.wander_radius):
		if h != hex and _grid.is_walkable(h) and not _party_near(h):
			options.append(h)
	if options.is_empty() or _party_near(hex):
		return
	var target: Vector2i = options.pick_random()
	_grid.set_occupied(hex, false)  # our own hex must be enabled to path from it
	var p := _grid.find_path(hex, target)
	_grid.set_occupied(hex, true)
	if not p.is_empty() and p.size() <= def.wander_radius * 2 + 1:
		follow_path(p)


func _party_near(h: Vector2i) -> bool:
	if party == null:
		return false
	for m in party.members:
		if Hex.distance(m.hex, h) <= 1 or Hex.distance(m.destination, h) <= 1:
			return true
	return false


## Stops strolling (someone is coming to talk).
func hold() -> void:
	if is_moving():
		stop()
	talking = true


func end_talk() -> void:
	talking = false
	_wait = randf_range(4.0, 9.0)


# --- moving on the grid -----------------------------------------------------------

func _can_stand(h: Vector2i) -> bool:
	return _grid.is_ground_walkable(h) and (h == hex or not _grid.is_occupied(h))


func _on_hex_changed(old: Vector2i, new: Vector2i) -> void:
	_grid.set_occupied(old, false)
	_grid.set_occupied(new, true)


# --- interaction (the same calls a Prop answers) -----------------------------------

func display_name() -> String:
	return def.display_name


func is_transition() -> bool:
	return false


func approach_hexes(grid: HexGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n in Hex.neighbors(hex):
		if grid.is_walkable(n):
			out.append(n)
	return out


func is_adjacent_to(h: Vector2i) -> bool:
	return Hex.distance(hex, h) <= 1


## Starts talking with `member` (the HUD opens the dialogue window).
func interact(member: PartyMember) -> void:
	talking = true
	face_towards(member.position)
	member.face_towards(position)
	Events.dialogue_requested.emit(self, member)


func _draw() -> void:
	super._draw()
	if hovered:
		_draw_ring(HOVER_COLOR, 1.5)
