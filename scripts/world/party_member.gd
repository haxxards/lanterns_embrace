class_name PartyMember
extends Actor
## A party member's token on the map. Walking and animation come from Actor;
## this adds the character sheet, selection, the pending interaction (a prop
## to use on arrival), speed penalties, and how the fallen look.

const SELECT_COLOR := Color(0.35, 0.95, 0.45)
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.55)

var sheet: CharacterSheet
## Prop or NPC to interact with on arrival, if any.
var pending_interaction: Node2D = null
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()


func setup(character: CharacterSheet, grid: HexGrid, start: Vector2i) -> void:
	sheet = character
	_grid = grid
	name = "Member_%s" % character.id
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_sprite(character.animation_path, character.sprite_path, character.sprite_origin)
	place_at(start)
	sheet.changed.connect(_refresh_alive)
	_refresh_alive()


func _exit_tree() -> void:
	if sheet != null and sheet.changed.is_connected(_refresh_alive):
		sheet.changed.disconnect(_refresh_alive)


func is_alive() -> bool:
	return sheet.is_alive()


## The fallen lie grey and still until raised at a temple.
func _refresh_alive() -> void:
	modulate = Color(1, 1, 1) if is_alive() else Color(0.45, 0.42, 0.42, 0.75)
	if not is_alive():
		stop()
		pending_interaction = null
	queue_redraw()


func move_speed() -> float:
	return GameConfig.explore_move_speed * speed_factor()


## Exploration speed relative to normal: heavy armour without the Strength
## for it, or carrying too much, slows a member down.
func speed_factor() -> float:
	return clampf(float(sheet.effective_speed_ft()) / maxf(1.0, float(sheet.speed_ft)), 0.25, 1.0)


func _draw() -> void:
	super._draw()
	if selected:
		_draw_ring(SELECT_COLOR, 2.0)
	elif hovered:
		_draw_ring(HOVER_COLOR, 1.5)
