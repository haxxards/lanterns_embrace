class_name Effects
extends RefCounted
## Applies the "do" effects of dialogue nodes and options. Each effect is a
## small Dictionary:
##
##   {"set_flag": "x"}  {"clear_flag": "x"}
##   {"give_item": "id", "qty": 1}        to the speaker (or anyone with room)
##   {"take_item": "id", "qty": 1}        from whoever carries it
##   {"give_gold": 20}  {"take_gold": 10}
##   {"quest": "id", "stage": "started"}  advance a quest (see GameState.set_quest_stage)
##   {"xp": 50}                           every living member gains it
##   {"heal_party": true}                 everyone not dead is healed to full (the unconscious wake)
##   {"long_rest": true}                  a night's sleep: hit points, spell slots, features (Rest.long_rest)
##   {"revive": true}                     the dead (and the unconscious) rise with 1 hit point
##   {"identify": "all", "cost_each": 25} name the party's unidentified items, paying for each
##                                        (as many as the purse allows)
##   {"toast": "text"}
##
## Returns a list of short messages describing what happened (for toasts).


static func apply(effects: Variant, speaker: CharacterSheet) -> PackedStringArray:
	var out := PackedStringArray()
	if effects is Dictionary:
		effects = [effects]
	if not effects is Array:
		return out
	for e in effects:
		if e is Dictionary:
			var msg := _apply_one(e, speaker)
			if not msg.is_empty():
				out.append(msg)
	return out


static func _apply_one(e: Dictionary, speaker: CharacterSheet) -> String:
	if e.has("set_flag"):
		GameState.flags[str(e["set_flag"])] = true
	if e.has("clear_flag"):
		GameState.flags.erase(str(e["clear_flag"]))
	if e.has("give_item"):
		var item_id := str(e["give_item"])
		var qty := int(e.get("qty", 1))
		var def: ItemDef = Data.items.get(item_id)
		var left := GameState.give_party_item(item_id, qty, speaker)
		var name := def.display_name if def else item_id
		if left > 0:
			return "No room to carry the %s." % name
		return "Received: %s%s." % [name, "" if qty == 1 else " ×%d" % qty]
	if e.has("take_item"):
		var item_id := str(e["take_item"])
		GameState.take_party_item(item_id, int(e.get("qty", 1)))
		var def: ItemDef = Data.items.get(item_id)
		return "Handed over: %s." % (def.display_name if def else item_id)
	if e.has("give_gold"):
		GameState.add_gold(int(e["give_gold"]))
		Audio.play_sfx("coins")
		return "Received %d gold." % int(e["give_gold"])
	if e.has("take_gold"):
		GameState.add_gold(-int(e["take_gold"]))
		Audio.play_sfx("coins")
		return "Paid %d gold." % int(e["take_gold"])
	if e.has("quest"):
		GameState.set_quest_stage(str(e["quest"]), str(e.get("stage", "started")))
	if e.has("xp"):
		GameState.award_xp(int(e["xp"]))
	if e.has("heal_party"):
		for s in GameState.party:
			if not s.dead:
				s.heal(s.hp_max)
		Audio.play_sfx("potion")
		return "The party is healed."
	if e.has("long_rest"):
		Rest.long_rest(GameState.party)
		Audio.play_sfx("potion")
		return "The party sleeps the night through and wakes rested."
	if e.has("revive"):
		var raised := PackedStringArray()
		for s in GameState.party:
			if s.dead:
				s.revive(1)
				raised.append(s.display_name)
			elif not s.is_alive():
				s.heal(1)
				raised.append(s.display_name)
		if not raised.is_empty():
			return "%s %s raised." % [", ".join(raised), "is" if raised.size() == 1 else "are"]
	if e.has("identify"):
		var cost := int(e.get("cost_each", 0))
		var named := PackedStringArray()
		for s in GameState.party:
			for st in InventoryOps.unidentified(s):
				if GameState.gold < cost:
					break
				GameState.add_gold(-cost)
				InventoryOps.identify(st, s)
				named.append(st.def.display_name)
		if named.is_empty():
			return "Nothing was named."
		if cost > 0:
			Audio.play_sfx("coins")
		return "Named for %d gold: %s." % [cost * named.size(), ", ".join(named)]
	if e.has("toast"):
		return str(e["toast"])
	return ""
