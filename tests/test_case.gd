class_name TestCase
extends RefCounted
## Base class for tests. Methods named test_* are run by tests/test_runner.gd;
## they may `await` (integration tests use `runner` to reach the scene tree).

var runner: Node
var failures: PackedStringArray = PackedStringArray()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


## Optional per-test hooks.
func before_each() -> void:
	pass


func after_each() -> void:
	pass
