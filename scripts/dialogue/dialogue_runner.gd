class_name DialogueRunner
extends RefCounted
## Walks a Dialogue graph: which node is showing, which options are on offer
## (their "if" conditions pass), and what choosing one does. Pure logic, no UI,
## so it can be tested directly. The DialogueWindow shows a runner.

var dialogue: Dialogue
var npc: NpcDef
## The party member doing the talking.
var speaker: CharacterSheet
var node_id: String = ""
var finished: bool = false
## Set when an option asks for the vendor's shop; the UI opens it after closing.
var wants_shop: bool = false
## Messages from effects since the last choice ("Received 20 gold.").
var messages := PackedStringArray()


func start(d: Dialogue, who: NpcDef, talker: CharacterSheet) -> void:
	dialogue = d
	npc = who
	speaker = talker
	finished = false
	wants_shop = false
	messages = PackedStringArray()
	var first := ""
	if d.start is Array:
		for entry in d.start:
			if Conditions.check(entry.get("if"), speaker, d.id):
				first = str(entry.get("node", ""))
				break
	else:
		first = str(d.start)
	_enter(first)


func node() -> Dictionary:
	return dialogue.nodes.get(node_id, {})


## The current line, with {leader}, {npc} and {gold} filled in.
func text() -> String:
	return _fill(str(node().get("text", "...")))


func speaker_name() -> String:
	return str(node().get("speaker", npc.display_name if npc else ""))


## Options whose conditions pass: [{"index": i, "text": ...}]. A node without
## options offers "Continue" (to its "next") or "Farewell."
func options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var opts: Array = node().get("options", [])
	for i in opts.size():
		var opt: Dictionary = opts[i]
		if Conditions.check(opt.get("if"), speaker, dialogue.id):
			out.append({"index": i, "text": _fill(str(opt.get("text", "...")))})
	if out.is_empty():
		out.append({"index": -1, "text": "Continue." if node().has("next") else "Farewell."})
	return out


## Picks option `index` (from options()): applies its effects and moves on.
func choose(index: int) -> void:
	messages = PackedStringArray()
	if index < 0:
		if node().has("next"):
			_enter(str(node()["next"]))
		else:
			finished = true
		return
	var opts: Array = node().get("options", [])
	if index >= opts.size():
		return
	var opt: Dictionary = opts[index]
	if not Conditions.check(opt.get("if"), speaker, dialogue.id):
		return
	messages.append_array(Effects.apply(opt.get("do", []), speaker))
	if bool(opt.get("shop", false)):
		wants_shop = true
		finished = true
	elif bool(opt.get("end", false)) or not opt.has("goto"):
		finished = true
	else:
		_enter(str(opt["goto"]))


func _enter(id: String) -> void:
	if not dialogue.nodes.has(id):
		push_warning("Dialogue %s has no node '%s'" % [dialogue.id, id])
		finished = true
		return
	node_id = id
	GameState.flags["seen:%s:%s" % [dialogue.id, id]] = true
	messages.append_array(Effects.apply(node().get("do", []), speaker))


func _fill(s: String) -> String:
	return s.replace("{leader}", speaker.display_name if speaker else "traveller") \
			.replace("{npc}", npc.display_name if npc else "") \
			.replace("{gold}", str(GameState.gold))
