class_name JsonUtil
extends RefCounted
## Small helpers for reading JSON data files with useful error messages.


## Returns the parsed value, or null on failure (the error is pushed).
static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("JSON file not found: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Lists *.json files in a directory (non-recursive). Missing dirs yield [].
static func list_json_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.get_extension().to_lower() == "json":
			out.append(dir_path.path_join(file_name))
	out.sort()
	return out


## Parses "#rrggbb" / "#rrggbbaa" strings, falling back to `fallback`.
static func parse_color(value: Variant, fallback: Color = Color.MAGENTA) -> Color:
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	return fallback


## Reads a [x, y] JSON array into a Vector2i.
static func to_vec2i(value: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


## Reads a [x, y] JSON array into a Vector2.
static func to_vec2(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
