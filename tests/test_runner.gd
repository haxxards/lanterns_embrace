extends Node
## Headless test runner:
##   godot --headless --path . res://tests/test_runner.tscn
## Runs every test_*.gd under tests/unit and tests/integration, prints a
## summary and exits with code 1 if anything failed. Engine and script errors
## raised while a test runs (e.g. a bad property access) fail that test.

const SUITE_DIRS := ["res://tests/unit", "res://tests/integration"]


## Collects errors reported by the engine while tests run.
class ErrorCatcher:
	extends Logger

	var errors: PackedStringArray = PackedStringArray()
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return out


func _ready() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var passed := 0
	var failed := 0
	for dir_path in SUITE_DIRS:
		for file_name in DirAccess.get_files_at(dir_path):
			if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
				continue
			var script: GDScript = load(dir_path.path_join(file_name))
			var suite: TestCase = script.new()
			suite.runner = self
			print("\n== %s" % file_name)
			for method in suite.get_method_list():
				var method_name: String = method["name"]
				if not method_name.begins_with("test_"):
					continue
				suite.failures.clear()
				catcher.take()
				await suite.before_each()
				await suite.call(method_name)
				await suite.after_each()
				for err in catcher.take():
					suite.failures.append("engine error: " + err)
				if suite.failures.is_empty():
					passed += 1
					print("  PASS  %s" % method_name)
				else:
					failed += 1
					print("  FAIL  %s" % method_name)
					for f in suite.failures:
						print("        - %s" % f)
	OS.remove_logger(catcher)
	print("\n%d passed, %d failed" % [passed, failed])
	get_tree().paused = false
	get_tree().quit(1 if failed > 0 else 0)
