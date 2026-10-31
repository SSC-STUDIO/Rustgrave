class_name RoomGate
extends Interactable
## 《ICEY》式房间切屏门 / 跨节点传送门。
##
## 支持两种通行方式：
##   · Mode.TOUCH_EDGE  触碰边界即切房（0.16s 极速黑场擦除，零按键负担，内置 0.35s 出生防回弹保护）；
##   · Mode.INTERACT    站在拱门前按 E 推门（用于主线跨区大门、隐藏裂隙入口或终章大门）。
## 同时实现 lock() / unlock() / set_locked()，可被 BattleWaveArena 与 BossArena 直接封锁。

signal gate_triggered(target_room: String, target_spawn: String, target_stage: String)

enum Mode { TOUCH_EDGE, INTERACT }

const ARCH_SIZE := Vector2(32.0, 64.0)
const ARCH_OFFSET := Vector2(-16.0, -64.0)

@export var mode: Mode = Mode.TOUCH_EDGE
@export var target_room: String = ""
@export var target_spawn: String = "west"
@export var target_stage: String = ""
@export var gate_label: String = ""
@export var unlock_node_id: String = ""
@export var done_node_id: String = ""
@export var requires_flag: String = ""
@export var locked_prompt: String = "铁栅封死"
@export var touch_size: Vector2 = Vector2(28.0, 64.0)

var locked: bool = false
var _spawn_grace: float = 0.35
var _triggered: bool = false


func _ready() -> void:
	super._ready()
	z_index = 1
	if mode == Mode.INTERACT:
		ensure_sprite("res://assets/env/door_arch.png", ARCH_SIZE, ARCH_OFFSET, Color("#3B2F3C"))
		prompt = "E 进入 · %s" % gate_label if gate_label != "" else "E 前进"
	else:
		# 触碰式边界口：居中挂感应框，使 global_position 悬在走廊净空中心，脚点返回 INF 免检接地。
		reach_pad = Vector2.ZERO
		_ensure_collision(touch_size, -touch_size * 0.5)
		body_entered.connect(_on_touch_body_entered)
	queue_redraw()


func feet_point() -> Vector2:
	if mode == Mode.TOUCH_EDGE:
		return Vector2.INF
	return global_position


func walkable_goal_point() -> Vector2:
	if mode == Mode.INTERACT:
		return global_position
	var nm := String(name)
	if nm.begins_with("GateEast_") or nm.begins_with("GateWest_"):
		return global_position + Vector2(0.0, touch_size.y * 0.5)
	return Vector2.INF


func lock() -> void:
	set_locked(true)


func unlock() -> void:
	set_locked(false)


func set_locked(on: bool) -> void:
	locked = on
	queue_redraw()


func is_gate_open() -> bool:
	if locked:
		return false
	if requires_flag != "" and not SaveData.has_flag(requires_flag):
		return false
	return true


func can_interact(_actor: Node) -> bool:
	return mode == Mode.INTERACT and not _triggered


func get_prompt(_actor: Node) -> String:
	if not is_gate_open():
		return locked_prompt
	if gate_label != "":
		return "E 前往 · %s" % gate_label
	return "E 前进"


func interact(actor: Node) -> void:
	if mode != Mode.INTERACT or _triggered:
		return
	if not is_gate_open():
		Sfx.play(&"ui_denied")
		GameEvents.announcement.emit(locked_prompt)
		return
	_activate_transition(actor)


func _process(delta: float) -> void:
	if _spawn_grace > 0.0:
		_spawn_grace = maxf(0.0, _spawn_grace - delta)
		if _spawn_grace <= 0.0 and mode == Mode.TOUCH_EDGE and not _triggered and is_gate_open():
			for body in get_overlapping_bodies():
				if body is Player:
					_activate_transition(body)
					break


func _on_touch_body_entered(body: Node) -> void:
	if mode != Mode.TOUCH_EDGE or _triggered or _spawn_grace > 0.0:
		return
	if not (body is Player):
		return
	if not is_gate_open():
		return
	_activate_transition(body)


func _activate_transition(actor: Node) -> void:
	if _triggered:
		return
	var world := GameContext.world_root(self)
	if TrialRun.handles_level_exit() and target_stage != "":
		var cur_stage := String(world.get("stage_id")) if world != null else ""
		if target_stage != cur_stage:
			_triggered = true
			TrialRun.reach_goal()
			return
	_triggered = true
	if done_node_id != "":
		SaveData.mark_node_cleared(done_node_id)
	if unlock_node_id != "":
		SaveData.unlock_node(unlock_node_id)
	if done_node_id != "" or unlock_node_id != "":
		SaveData.persist_story(actor)
		SaveData.save_equipment(actor)

	gate_triggered.emit(target_room, target_spawn, target_stage)
	if world != null and world.has_method("request_room_transition"):
		world.call("request_room_transition", target_room, target_spawn, target_stage)
	elif target_stage != "" and GameContext.LEVELS.has(target_stage):
		Director.fade_to(String(GameContext.LEVELS[target_stage]), 0.28)


func _draw() -> void:
	if not is_gate_open():
		if mode == Mode.INTERACT:
			for x in [-8.0, 0.0, 8.0]:
				draw_line(Vector2(x, -ARCH_SIZE.y), Vector2(x, 0.0), Color(0.92, 0.26, 0.22, 0.85), 2.0)
		else:
			var half_h := touch_size.y * 0.5
			for x in [-6.0, 0.0, 6.0]:
				draw_line(Vector2(x, -half_h), Vector2(x, half_h), Color(0.92, 0.26, 0.22, 0.85), 2.0)
		return
	if mode == Mode.TOUCH_EDGE:
		draw_rect(Rect2(-3.0, -touch_size.y * 0.5, 6.0, touch_size.y), Color(1.0, 0.76, 0.35, 0.14))
