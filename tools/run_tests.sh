#!/usr/bin/env sh
# Runs the headless test suite.
#   tools/run_tests.sh [path/to/godot]      (or set GODOT=/path/to/godot)
set -e
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."
# Make sure textures are imported and the class cache exists (first run / CI).
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . res://tests/test_runner.tscn
