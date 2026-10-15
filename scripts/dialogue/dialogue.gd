class_name Dialogue
extends RefCounted
## A conversation graph loaded from data/dialogue/*.json (see docs/DIALOGUE.md).
##
##   {"id": "tobin", "start": "greet",       // or a list of {"if": ..., "node": ...}
##    "nodes": {"greet": {"text": "...", "do": [...],
##                        "options": [{"text": "...", "if": {...}, "do": [...], "goto": "news"}]}}}

var id: String = ""
## A node id, or an Array of {"if": condition, "node": id} tried in order.
var start: Variant = ""
var nodes: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()


static func load_file(path: String) -> Dialogue:
	var dl := Dialogue.new()
	var d: Variant = JsonUtil.load_json(path)
	if not d is Dictionary:
		dl.errors.append("could not read %s" % path)
		return dl
	dl.id = str(d.get("id", path.get_file().get_basename()))
	dl.start = d.get("start", "")
	dl.nodes = d.get("nodes", {})
	dl.validate()
	return dl


## Checks that every goto and start points at a real node.
func validate() -> void:
	var targets: Array = []
	if start is Array:
		for s in start:
			targets.append(str(s.get("node", "")))
	else:
		targets.append(str(start))
	for node_id in nodes:
		var node: Dictionary = nodes[node_id]
		if node.has("next"):
			targets.append(str(node["next"]))
		for opt in node.get("options", []):
			if opt.has("goto"):
				targets.append(str(opt["goto"]))
	for t in targets:
		if not nodes.has(t):
			errors.append("%s: no node named '%s'" % [id, t])
