class_name QuestDef
extends RefCounted
## One quest from data/quests/quests.json: a name and an ordered list of
## stages, each with a journal entry. Reaching a stage marked "done" completes
## the quest and awards its XP to every living party member. A stage with an
## "auto_if" condition is reached by itself once that condition holds (for
## example, when someone picks up the item the quest is about).

var id: String = ""
var display_name: String = ""
var xp: int = 0
## [{"id", "journal", "done", "auto_if"}] in order.
var stages: Array[Dictionary] = []


static func from_dict(quest_id: String, d: Dictionary) -> QuestDef:
	var q := QuestDef.new()
	q.id = quest_id
	q.display_name = str(d.get("name", quest_id.capitalize()))
	q.xp = int(d.get("xp", 0))
	for s in d.get("stages", []):
		if s is Dictionary and s.has("id"):
			q.stages.append(s)
	return q


func stage(stage_id: String) -> Dictionary:
	for s in stages:
		if str(s["id"]) == stage_id:
			return s
	return {}


func stage_index(stage_id: String) -> int:
	for i in stages.size():
		if str(stages[i]["id"]) == stage_id:
			return i
	return -1


func is_done_stage(stage_id: String) -> bool:
	return bool(stage(stage_id).get("done", false))
