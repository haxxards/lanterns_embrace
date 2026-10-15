class_name ColorGrade
extends CanvasLayer
## Full-view colour grade drawn above the world and below the HUD.
## Tuned by the "post" section of game_config.json.

const SHADER := preload("res://scripts/ui/color_grade.gdshader")

var _rect: ColorRect


func setup(right_ui_width: float) -> void:
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.offset_right = -right_ui_width
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("contrast", GameConfig.post_contrast)
	mat.set_shader_parameter("saturation", GameConfig.post_saturation)
	mat.set_shader_parameter("warmth", GameConfig.post_warmth)
	mat.set_shader_parameter("vignette", GameConfig.post_vignette)
	_rect.material = mat
	add_child(_rect)
	visible = GameConfig.post_enabled
