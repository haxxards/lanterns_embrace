class_name Creature
extends Actor
## A hostile creature on the map (wolf, bandit, skeleton...). Outside a fight
## it idles and strolls near its spot; when the party comes within its aggro
## range in sight, World starts a fight with its whole encounter group. It
## blocks the hex it stands on, hides in the fog like townsfolk, shows a
## health bar while fighting, and fades away when slain.

const HOVER_COLOR := Color(0.95, 0.3, 0.25, 0.9)
const ACTIVE_COLOR := Color(1.0, 0.82, 0.3, 0.95)
const BAR_WIDTH := 34.0

var def: CreatureDef
var sheet: CreatureSheet
## Unique per map (saved when slain, so it stays dead).
var spawn_id: String = ""
## Encounter group: all of a group join the fight together.
var group: String = ""
var home: Vector2i
var wander_radius: int = 1
var party: PartyController
var in_combat: bool = false:
	set(value):
		in_combat = value
		queue_redraw()
## Its turn in a fight.
var active: bool = false:
	set(value):
		active = value
		queue_redraw()

var _wait: float = 0.0


func setup(d: CreatureDef, grid: HexGrid, spawn: Dictionary, party_controller: PartyController) -> void:
	def = d
	sheet = CreatureSheet.create(d)
	_grid = grid
	home = spawn["hex"]
	spawn_id = str(spawn["id"])
	group = str(spawn.get("group", spawn_id))
	wander_radius = int(spawn.get("wander", 1))
	party = party_controller
	name = "Creature_%s" % spawn_id
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_sprite(d.animation_path, d.sprite_path, null)
	place_at(home)
	occupies = true
	_facing = randi_range(0, 7)
	_update_frame()
	sheet.changed.connect(queue_redraw)
	_wait = randf_range(2.0, 6.0)


func is_alive() -> bool:
	return sheet.hp_current > 0


func display_name() -> String:
	return def.display_name


func _process(delta: float) -> void:
	super._process(delta)
	if in_combat or is_moving() or wander_radius <= 0 or not is_alive():
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = randf_range(3.0, 8.0)
		_wander()


func _wander() -> void:
	var options: Array[Vector2i] = []
	for h in Hex.spiral(home, wander_radius):
		if h != hex and _grid.is_walkable(h):
			options.append(h)
	if options.is_empty():
		return
	var p := path_to(options.pick_random())
	if not p.is_empty() and p.size() <= wander_radius * 2 + 1:
		follow_path(p)


## Slain: frees its hex and fades out (World removes it from the map).
func die() -> void:
	in_combat = false
	active = false
	stop()
	occupies = false
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.6, 0.2, 0.15, 0.0), 0.9)
	tw.tween_callback(queue_free)


func _draw() -> void:
	super._draw()
	if active:
		_draw_ring(ACTIVE_COLOR, 2.0)
	elif hovered:
		_draw_ring(HOVER_COLOR, 1.5)
	if (in_combat or sheet.hp_current < sheet.hp_max) and is_alive():
		var top := _sprite.get_rect().position.y - 7.0
		var r := Rect2(-BAR_WIDTH / 2.0, top, BAR_WIDTH, 4.0)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
		var f := clampf(float(sheet.hp_current) / float(sheet.hp_max), 0.0, 1.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), Color(0.85, 0.22, 0.18))
