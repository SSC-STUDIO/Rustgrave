class_name StageRoomMemory
extends RefCounted
## 单次会话内的房间状态记忆与跨节点切屏信箱。
##
## 作用：
##   1. 记录当前会话已清光的 `BattleWaveArena`（同次探索折返不重复刷小怪，回标题或开新档清空）；
##   2. 记录跨节点切屏的目标房间 `pending_room` 与出生口 `pending_spawn_tag`；
##   3. 记录玩家当前所在房间与入口标签，实现《ICEY》式当房满血零跑尸重试。

static var _cleared_rooms: Dictionary = {}
static var current_stage: String = ""
static var current_room: String = ""
static var current_spawn_tag: String = "west"

static var pending_stage: String = ""
static var pending_room: String = ""
static var pending_spawn_tag: String = ""


static func key_of(stage_id: String, room_id: String) -> String:
	return "%s:%s" % [stage_id, room_id]


static func is_cleared(stage_id: String, room_id: String) -> bool:
	if stage_id == "" or room_id == "":
		return false
	return bool(_cleared_rooms.get(key_of(stage_id, room_id), false))


static func mark_cleared(stage_id: String, room_id: String) -> void:
	if stage_id == "" or room_id == "":
		return
	_cleared_rooms[key_of(stage_id, room_id)] = true


static func set_checkpoint(stage_id: String, room_id: String, spawn_tag: String = "west") -> void:
	current_stage = stage_id
	current_room = room_id
	current_spawn_tag = spawn_tag if spawn_tag != "" else "west"


static func set_pending(stage_id: String, room_id: String, spawn_tag: String = "west") -> void:
	pending_stage = stage_id
	pending_room = room_id
	pending_spawn_tag = spawn_tag if spawn_tag != "" else "west"


static func has_pending_for(stage_id: String) -> bool:
	if pending_room == "":
		return false
	return pending_stage == "" or pending_stage == stage_id


static func consume_pending_for(stage_id: String) -> Dictionary:
	if not has_pending_for(stage_id):
		return {}
	var out := {
		"room_id": pending_room,
		"spawn_tag": pending_spawn_tag if pending_spawn_tag != "" else "west",
	}
	pending_stage = ""
	pending_room = ""
	pending_spawn_tag = ""
	return out


static func clear_stage(stage_id: String) -> void:
	if stage_id == "":
		return
	var prefix := "%s:" % stage_id
	for k in _cleared_rooms.keys():
		if String(k).begins_with(prefix):
			_cleared_rooms.erase(k)


static func clear_all() -> void:
	_cleared_rooms.clear()
	current_stage = ""
	current_room = ""
	current_spawn_tag = "west"
	pending_stage = ""
	pending_room = ""
	pending_spawn_tag = ""
