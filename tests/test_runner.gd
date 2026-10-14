extends Node
## Headless test runner:
##   godot --headless --path . res://tests/test_runner.tscn
## Runs every test_*.gd under tests/unit and tests/integration, prints a
## summary and exits with code 1 if anything failed.

const SUITE_DIRS := ["res://tests/unit", "res://tests/integration"]


func _ready() -> void:
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
				await suite.before_each()
				await suite.call(method_name)
				await suite.after_each()
				if suite.failures.is_empty():
					passed += 1
					print("  PASS  %s" % method_name)
				else:
					failed += 1
					print("  FAIL  %s" % method_name)
					for f in suite.failures:
						print("        - %s" % f)
	print("\n%d passed, %d failed" % [passed, failed])
	get_tree().paused = false
	get_tree().quit(1 if failed > 0 else 0)
