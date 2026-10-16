class_name FloatingText
extends Node2D
## A number or word that rises from someone and fades ("-7", "Miss"),
## for combat feedback.

const RISE := 34.0
const DURATION := 1.1


static func spawn(parent: Node, at: Vector2, text: String, color: Color, size: int = 18) -> FloatingText:
	var f := FloatingText.new()
	f.position = at
	f.z_index = 60
	f.process_mode = Node.PROCESS_MODE_ALWAYS
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(120, 0)
	label.position = Vector2(-60, -12)
	f.add_child(label)
	parent.add_child(f)
	var tw := f.create_tween()
	tw.set_parallel(true)
	tw.tween_property(f, "position:y", at.y - RISE, DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(f, "modulate:a", 0.0, DURATION * 0.4).set_delay(DURATION * 0.6)
	tw.chain().tween_callback(f.queue_free)
	return f
