class_name Conditions
extends RefCounted
## Evaluates the "if" conditions used by dialogue options, dialogue starts and
## quest stages. A condition is a Dictionary; every key in it must hold:
##
##   {"flag": "x"}  {"not_flag": "x"}              story flags in GameState.flags
##   {"quest": "id", "is": "active"}               "not_started", "active", "done" or a stage id
##   {"quest": "id", "is_not": "done"}
##   {"item": "id"}  {"not_item": "id"}            anyone in the party carries it
##   {"gold": 10}                                   the purse holds at least this much
##   {"member": "odran"}                            this character is in the party, alive
##   {"speaker": "wren"}                            this character is doing the talking
##   {"hurt": true}  {"fallen": true}               someone is wounded / someone has fallen
##   {"visited": "node"}                            this dialogue node was seen before
##   {"all": [...]}  {"any": [...]}  {"not": {...}}
##
## An empty or missing condition is true.


static func check(cond: Variant, speaker: CharacterSheet = null, dialogue_id: String = "") -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c in cond:
			if not check(c, speaker, dialogue_id):
				return false
		return true
	if not cond is Dictionary:
		push_warning("Condition should be a dictionary: %s" % str(cond))
		return false
	var d: Dictionary = cond
	for key in d:
		if not _check_key(str(key), d[key], d, speaker, dialogue_id):
			return false
	return true


static func _check_key(key: String, value: Variant, d: Dictionary, speaker: CharacterSheet,
		dialogue_id: String) -> bool:
	match key:
		"flag":
			return bool(GameState.flags.get(str(value), false))
		"not_flag":
			return not bool(GameState.flags.get(str(value), false))
		"quest":
			var state := GameState.quest_state(str(value))
			if d.has("is"):
				return _quest_is(str(value), state, str(d["is"]))
			if d.has("is_not"):
				return not _quest_is(str(value), state, str(d["is_not"]))
			return state != "not_started"
		"is", "is_not", "qty":
			return true  # read together with "quest" / "item"
		"item":
			return GameState.party_item_count(str(value)) >= int(d.get("qty", 1))
		"not_item":
			return GameState.party_item_count(str(value)) == 0
		"gold":
			return GameState.gold >= int(value)
		"member":
			var m := GameState.member(str(value))
			return m != null and m.is_alive()
		"speaker":
			return speaker != null and speaker.id == str(value)
		"hurt":
			return GameState.anyone_hurt() == bool(value)
		"fallen":
			return GameState.anyone_fallen() == bool(value)
		"visited":
			return bool(GameState.flags.get("seen:%s:%s" % [dialogue_id, value], false))
		"all":
			return check(value, speaker, dialogue_id)
		"any":
			for c in value:
				if check(c, speaker, dialogue_id):
					return true
			return false
		"not":
			return not check(value, speaker, dialogue_id)
	push_warning("Unknown condition '%s'" % key)
	return false


static func _quest_is(quest_id: String, state: String, wanted: String) -> bool:
	if wanted in ["not_started", "active", "done"]:
		return state == wanted
	return GameState.quest_stage(quest_id) == wanted
