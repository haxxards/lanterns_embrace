extends Node
## Mutable state of the current playthrough: the party, the purse, where the
## party is, and what has changed on each map (containers emptied, ground
## explored).
##
## Everything here serialises to a plain Dictionary (to_dict / load_dict);
## that dictionary is exactly what a save file contains (see SaveManager).

signal party_changed
signal gold_changed(gold: int)

const SAVE_VERSION := 1

var party: Array[CharacterSheet] = []
## The party shares one purse, as in the Baldur's Gate games.
var gold: int = 0
var current_map_path: String = ""
## Entry point on the current map to place the party at ("" = the map's spawn).
var current_entry: String = ""
## Exact hexes to restore on the next map load: {member id: Vector2i}. Used by
## loading a save; cleared once the map has used them.
var pending_positions: Dictionary = {}
var pending_camera: Variant = null
## Seconds of unpaused play.
var playtime: float = 0.0
## Story flags set by dialogue (and "seen:<dialogue>:<node>" markers).
var flags: Dictionary = {}
## Quest id -> current stage id.
var quests: Dictionary = {}
## Quest id -> stage ids reached so far, in order (the journal).
var quest_log: Dictionary = {}

## The fight in progress (a CombatManager), or null. A save made during a
## fight stores it (CombatManager.to_dict, under "combat").
var combat: Node = null
## A saved fight to pick up on the next map load (see World.load_map).
var pending_combat: Dictionary = {}

## map id -> {container id -> ContainerState}
var _containers: Dictionary = {}
## map id -> {creature spawn id -> true}: creatures slain there (they stay dead).
var _defeated: Dictionary = {}
## map id -> PackedByteArray, one byte per hex: 1 = explored.
var _explored: Dictionary = {}


func _process(delta: float) -> void:
	if not get_tree().paused:
		playtime += delta


## Builds the starting party from GameConfig.starting_party_path.
func start_new_game() -> void:
	party.clear()
	gold = 0
	flags.clear()
	quests.clear()
	quest_log.clear()
	playtime = 0.0
	_containers.clear()
	_explored.clear()
	_defeated.clear()
	pending_combat = {}
	combat = null
	pending_positions.clear()
	pending_camera = null
	var d: Variant = JsonUtil.load_json(GameConfig.starting_party_path)
	var ids: Array = d.get("members", []) if d is Dictionary else []
	for character_id in ids:
		if party.size() >= GameConfig.max_party_size:
			push_warning("Starting party lists more than max_party_size (%d); extra members ignored"
					% GameConfig.max_party_size)
			break
		var sheet := Data.new_character(str(character_id))
		if sheet == null:
			push_error("Starting party member '%s' has no character sheet" % character_id)
			continue
		_join(sheet)
	current_map_path = GameConfig.starting_map_path
	current_entry = ""
	party_changed.emit()
	gold_changed.emit(gold)


func add_party_member(sheet: CharacterSheet) -> bool:
	if party.size() >= GameConfig.max_party_size or party.has(sheet):
		return false
	_join(sheet)
	party_changed.emit()
	gold_changed.emit(gold)
	return true


func remove_party_member(sheet: CharacterSheet) -> void:
	party.erase(sheet)
	party_changed.emit()


## A joining character's own gold goes into the party purse.
func _join(sheet: CharacterSheet) -> void:
	party.append(sheet)
	gold += sheet.gold
	sheet.gold = 0
	_watch(sheet)


## Re-checks quests when items change hands, and notices a fallen party.
func _watch(sheet: CharacterSheet) -> void:
	if not sheet.changed.is_connected(_on_sheet_changed):
		sheet.changed.connect(_on_sheet_changed)


func _on_sheet_changed() -> void:
	check_quests()
	if not party.is_empty() and not anyone_alive():
		Events.party_defeated.emit()


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


## Spends gold if the purse holds enough. Returns false (and spends nothing) otherwise.
func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	add_gold(-amount)
	return true


# --- the party as a whole -----------------------------------------------------------

func anyone_alive() -> bool:
	for s in party:
		if s.is_alive():
			return true
	return false


func anyone_fallen() -> bool:
	for s in party:
		if not s.is_alive():
			return true
	return false


## Someone not dead is below full hit points (the unconscious count).
func anyone_hurt() -> bool:
	for s in party:
		if not s.dead and s.hp_current < s.hp_max:
			return true
	return false


func anyone_dead() -> bool:
	for s in party:
		if s.dead:
			return true
	return false


func in_combat() -> bool:
	return combat != null and is_instance_valid(combat) and combat.active


## How many of an item the whole party carries (backpacks and equipment).
func party_item_count(item_id: String) -> int:
	var n := 0
	for s in party:
		for st in s.all_items():
			if st.id == item_id:
				n += st.qty
	return n


## Gives items to `first` if there is room, else to whoever has room.
## Returns the quantity nobody could carry.
func give_party_item(item_id: String, qty: int, first: CharacterSheet = null) -> int:
	var left := qty
	var order: Array[CharacterSheet] = []
	if first != null:
		order.append(first)
	for s in party:
		if s != first:
			order.append(s)
	for s in order:
		if left <= 0:
			break
		left = s.inventory.add(ItemStack.create(item_id, left))
	return left


## Removes items from whoever carries them (backpacks first, then worn).
func take_party_item(item_id: String, qty: int) -> int:
	var taken := 0
	for s in party:
		if taken < qty:
			taken += s.inventory.remove_item(item_id, qty - taken)
	for s in party:
		for slot in ItemDef.EQUIP_SLOTS:
			var st := s.equipped(slot)
			if taken < qty and st != null and st.id == item_id:
				taken += st.qty
				s.unequip(slot)
	return taken


## Every member who isn't dead gains `amount` XP (quest rewards are not split).
func award_xp(amount: int) -> void:
	for s in party:
		if not s.dead:
			var levels := s.add_xp(amount)
			if levels > 0:
				Events.toast_requested.emit(s.level_up_message())


# --- quests -------------------------------------------------------------------------

## "not_started", "active" or "done".
func quest_state(quest_id: String) -> String:
	if not quests.has(quest_id):
		return "not_started"
	var q: QuestDef = Data.quests.get(quest_id)
	return "done" if q != null and q.is_done_stage(str(quests[quest_id])) else "active"


func quest_stage(quest_id: String) -> String:
	return str(quests.get(quest_id, ""))


## Moves a quest to `stage` (and logs the journal entry). Reaching a "done"
## stage completes it and awards its XP.
func set_quest_stage(quest_id: String, stage: String) -> void:
	var q: QuestDef = Data.quests.get(quest_id)
	if q == null or q.stage_index(stage) < 0:
		push_warning("Unknown quest stage %s/%s" % [quest_id, stage])
		return
	if quest_stage(quest_id) == stage or quest_state(quest_id) == "done":
		return
	quests[quest_id] = stage
	if not quest_log.has(quest_id):
		quest_log[quest_id] = []
	quest_log[quest_id].append(stage)
	Events.quest_updated.emit(quest_id, stage)
	if q.is_done_stage(stage):
		Events.toast_requested.emit("Quest complete: %s  (+%d XP)" % [q.display_name, q.xp])
		award_xp(q.xp)
	else:
		Events.toast_requested.emit("Journal updated: %s" % q.display_name)
		check_quests()  # e.g. the item a new quest asks for is already in a pack


## Advances active quests whose next stages have an "auto_if" that now holds.
func check_quests() -> void:
	for quest_id in quests.keys():
		if quest_state(quest_id) != "active":
			continue
		var q: QuestDef = Data.quests.get(quest_id)
		var current := q.stage_index(quest_stage(quest_id))
		for i in range(current + 1, q.stages.size()):
			var st: Dictionary = q.stages[i]
			if st.has("auto_if") and Conditions.check(st["auto_if"]):
				set_quest_stage(quest_id, str(st["id"]))
				break


func member(member_id: String) -> CharacterSheet:
	for s in party:
		if s.id == member_id:
			return s
	return null


# --- per-map state ------------------------------------------------------------

func get_container(map_id: String, container_id: String) -> ContainerState:
	return (_containers.get(map_id, {}) as Dictionary).get(container_id)


## All containers known on a map: {container id: ContainerState}.
func containers_for(map_id: String) -> Dictionary:
	return _containers.get(map_id, {})


func set_container(map_id: String, container_id: String, state: ContainerState) -> void:
	if not _containers.has(map_id):
		_containers[map_id] = {}
	_containers[map_id][container_id] = state


## A vendor's stock: a container kept under the pseudo-map "_vendors", made
## from the NPC's starting stock the first time the shop opens.
func vendor_stock(npc: NpcDef) -> ContainerState:
	var state := get_container("_vendors", npc.id)
	if state == null:
		var stock: Array = npc.vendor.get("stock", [])
		state = ContainerState.new()
		state.inventory = Inventory.from_array(stock, stock.size() + 16)
		set_container("_vendors", npc.id, state)
	return state


## The explored-hex mask for a map (created empty on first visit).
func explored_for(map_id: String, cell_count: int) -> PackedByteArray:
	var mask: PackedByteArray = _explored.get(map_id, PackedByteArray())
	if mask.size() != cell_count:
		mask.resize(cell_count)
		mask.fill(0)
	return mask


func set_explored(map_id: String, mask: PackedByteArray) -> void:
	_explored[map_id] = mask


func is_defeated(map_id: String, spawn_id: String) -> bool:
	return (_defeated.get(map_id, {}) as Dictionary).has(spawn_id)


func mark_defeated(map_id: String, spawn_id: String) -> void:
	if not _defeated.has(map_id):
		_defeated[map_id] = {}
	_defeated[map_id][spawn_id] = true


## Records that a whole encounter group has been beaten (the "defeated"
## condition reads it) and lets quests notice.
func mark_group_defeated(group: String) -> void:
	flags["defeated:%s" % group] = true
	check_quests()


# --- save data -----------------------------------------------------------------

## Everything needed to restore the game. `positions` ({id: Vector2i}) and
## `camera` come from the live world (see SaveManager).
func to_dict(positions: Dictionary = {}, camera: Variant = null) -> Dictionary:
	var members: Array = []
	for sheet in party:
		members.append(sheet.to_dict())
	var pos := {}
	for k in positions:
		var h: Vector2i = positions[k]
		pos[k] = [h.x, h.y]
	var maps := {}
	for map_id in _containers:
		var c := {}
		for cid in _containers[map_id]:
			var state: ContainerState = _containers[map_id][cid]
			if str(cid).begins_with("ground_") and state.inventory.is_empty():
				continue  # picked-up piles leave nothing behind
			c[cid] = state.to_dict()
		maps[map_id] = {"containers": c}
	for map_id in _explored:
		if not maps.has(map_id):
			maps[map_id] = {}
		maps[map_id]["explored"] = Marshalls.raw_to_base64(_explored[map_id])
	for map_id in _defeated:
		if not maps.has(map_id):
			maps[map_id] = {}
		maps[map_id]["defeated"] = (_defeated[map_id] as Dictionary).keys()
	var d := {
		"version": SAVE_VERSION,
		"party": members,
		"gold": gold,
		"current_map": current_map_path,
		"positions": pos,
		"playtime": playtime,
		"flags": flags.duplicate(true),
		"quests": quests.duplicate(),
		"quest_log": quest_log.duplicate(true),
		"maps": maps,
	}
	if camera is Vector2:
		d["camera"] = [camera.x, camera.y]
	return d


## Replaces the current playthrough with saved data. The caller reloads the map.
func load_dict(d: Dictionary) -> bool:
	if int(d.get("version", 0)) > SAVE_VERSION:
		push_error("Save is from a newer version of the game (%s)" % d.get("version"))
		return false
	var new_party: Array[CharacterSheet] = []
	for m in d.get("party", []):
		if m is Dictionary:
			var sheet := CharacterSheet.from_dict(m)
			for err in sheet.errors:
				push_warning("Saved character %s: %s" % [sheet.id, err])
			new_party.append(sheet)
	if new_party.is_empty():
		push_error("Save contains no party")
		return false
	party = new_party
	gold = int(d.get("gold", 0))
	current_map_path = str(d.get("current_map", GameConfig.starting_map_path))
	current_entry = ""
	playtime = float(d.get("playtime", 0.0))
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	quests = (d.get("quests", {}) as Dictionary).duplicate()
	quest_log = (d.get("quest_log", {}) as Dictionary).duplicate(true)
	for sheet in party:
		_watch(sheet)
	pending_positions.clear()
	var pos: Dictionary = d.get("positions", {})
	for k in pos:
		pending_positions[str(k)] = JsonUtil.to_vec2i(pos[k])
	pending_camera = JsonUtil.to_vec2(d["camera"]) if d.has("camera") else null
	pending_combat = (d.get("combat", {}) as Dictionary).duplicate(true) if d.get("combat") is Dictionary else {}
	_containers.clear()
	_explored.clear()
	_defeated.clear()
	var maps: Dictionary = d.get("maps", {})
	for map_id in maps:
		var m: Dictionary = maps[map_id]
		for cid in m.get("containers", {}):
			set_container(map_id, cid, ContainerState.from_dict(m["containers"][cid]))
		if m.has("explored"):
			_explored[map_id] = Marshalls.base64_to_raw(str(m["explored"]))
		for spawn_id in m.get("defeated", []):
			mark_defeated(map_id, str(spawn_id))
	party_changed.emit()
	gold_changed.emit(gold)
	return true
