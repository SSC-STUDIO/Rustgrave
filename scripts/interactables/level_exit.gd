class_name LevelExit
extends Interactable
## 关卡出口：一扇门。E 进门 → 过场字幕 → 存档写下一关 + 落点 → 淡入下一关。
## `target_scene` 为空时是阶段结局：字幕后回标题（存档仍留在本关门前）。

const DOOR_TEX := "res://assets/env/moss_door.png"
const DOOR_SIZE := Vector2(48, 64)
const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"
const Storyboards := preload("res://scripts/data/storyboards.gd")
## 炉心门前的选择：标题 + 两句各自的代价（选之前就说清，不靠猜）。
const CHOICE_TITLE := "炉 心 门 前"
const CHOICE_GIVE_HINT := "还火：名字走，你也散成铁。"
const CHOICE_KEEP_HINT := "守炉：你留下，名字也留下。"

@export var target_scene: String = ""
@export var spawn: Vector2 = Vector2.ZERO
@export var door_label: String = "门"
@export var captions: PackedStringArray = []
## 走过这扇门时点亮的剧情旗标（为空则不写）。
@export var flag_id: String = ""
## 需要先点亮的旗标（例如 Boss 死亡）；没点亮时门锁着，只给提示。
@export var requires_flag: String = ""
@export var locked_prompt: String = "门还锁着"
## 炉心之门：打开还火 / 守炉两个选择，而不是直接播 captions。
## 选完播结局分镜 + 滚动字幕；give_captions / keep_captions 是没有分镜时的字幕兜底。
@export var ending_choice: bool = false
@export var give_captions: PackedStringArray = []
@export var keep_captions: PackedStringArray = []

var _used := false
var _choosing := false
var _layer: CanvasLayer
var _ending_actor: Player


func _ready() -> void:
	super._ready()
	prompt = "E 推开%s" % door_label
	ensure_sprite(DOOR_TEX, DOOR_SIZE, Vector2(-DOOR_SIZE.x * 0.5, -DOOR_SIZE.y), Palette.IRON)


func is_locked() -> bool:
	return requires_flag != "" and not SaveData.has_flag(requires_flag)


func can_interact(_actor: Node) -> bool:
	return not _used


func get_prompt(_actor: Node) -> String:
	return locked_prompt if is_locked() else prompt


func interact(actor: Node) -> void:
	if _used or _choosing or not actor is Player:
		return
	# 回火试炼：推开门 = 到达终点（限时 / 禁核结算），不执行战役换场、不写战役档。
	if TrialRun.active():
		TrialRun.reach_goal()
		return
	if is_locked():
		Sfx.play(&"ui_denied", 0.04, -4.0)
		GameEvents.announcement.emit(locked_prompt)
		return
	if ending_choice:
		_open_ending_choice(actor as Player)
		return
	_used = true
	Sfx.play(&"gate")
	_play_and_leave(captions, actor as Player, "")


## 菜单和测试都走这里。默认项是还火（give）。
func confirm_ending(id: StringName) -> void:
	if _used or not ending_choice:
		return
	_used = true
	_close_ending_choice()
	var kind := "keep" if id == &"keep" else "give"
	SaveData.ending = kind
	# 契约 §5：任一结局都解锁回火试炼（战役写；试炼中 mark_flag 会被守卫 no-op）。
	SaveData.mark_flag("trial_unlocked")
	GameEvents.ending_chosen.emit(StringName(kind))
	var lines := keep_captions if kind == "keep" else give_captions
	Sfx.play(&"gate")
	_play_and_leave(lines, _ending_actor, "ash_fall" if kind == "give" else "ember_rise", kind)


func _open_ending_choice(actor: Player) -> void:
	_choosing = true
	_ending_actor = actor
	Director.choice_hold = true
	Director.suspend()
	_layer = CanvasLayer.new()
	_layer.layer = 25
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	GameContext.ui_host(self).add_child(_layer)
	var root := Control.new()
	root.name = "ChoiceRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(root)
	root.add_child(UiKit.scrim(0.72, 0.72, 0.72))
	var frame := UiKit.panel(&"OrnatePanel")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(frame)
	var column := VBoxContainer.new()
	frame.add_child(column)
	column.add_child(UiKit.label(CHOICE_TITLE, &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())
	column.add_child(UiKit.label(CHOICE_GIVE_HINT, &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.label(CHOICE_KEEP_HINT, &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var menu := MenuList.new()
	menu.add_theme_constant_override("separation", 12)
	column.add_child(menu)
	# 还火是默认项（燕尾板），守炉是留在原地的第三层（四只角标）。
	menu.compact(menu.add_item(&"give", "还 火", false, MenuItem.Kind.SECONDARY))
	menu.compact(menu.add_item(&"keep", "守 炉", false, MenuItem.Kind.GHOST))
	menu.chosen.connect(confirm_ending)
	get_tree().paused = true


func _close_ending_choice() -> void:
	Director.choice_hold = false
	Director.resume()
	_choosing = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	if _layer != null:
		_layer.queue_free()
		_layer = null


## 播完过场后离开。`ending_kind` 非空 = 结局：播结局分镜 + 滚动字幕（字幕兜底只在
## 分镜库里没有这个结局时才用）；为空 = 普通出口字幕。
func _play_and_leave(lines: PackedStringArray, player: Player, fx_id: String,
		ending_kind: String = "") -> void:
	var steps := ending_play_steps(lines, fx_id, ending_kind)
	Director.play(steps)
	await Director.finished
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if flag_id != "":
		SaveData.mark_flag(flag_id)
	if target_scene != "":
		travel(target_scene, spawn, player)
	else:
		if player != null and is_instance_valid(player):
			SaveData.save_game(GameContext.world_scene_path(self), player)
		Director.fade_to(TITLE_PATH)


## 出口 / 结局的 Director 步骤（纯构造，测试直接读）。结局走分镜 + 滚动字幕；没有对应分镜
## 或不是结局时退回字幕。
static func ending_play_steps(lines: PackedStringArray, fx_id: String,
		ending_kind: String = "") -> Array:
	var steps: Array = [{"kind": "lock"}]
	if fx_id != "":
		steps.append({"kind": "fx", "id": "heart_pulse", "seconds": 0.55})
		steps.append({"kind": "fx", "id": fx_id, "seconds": 1.0})
	if ending_kind != "" and Storyboards.has("ending_%s" % ending_kind):
		steps.append_array(StoryFlow.ending_steps(ending_kind))
	else:
		for line in lines:
			steps.append({"kind": "caption", "text": String(line), "hold": 2.2})
	steps.append({"kind": "wait", "seconds": 0.2})
	steps.append({"kind": "unlock"})
	return steps


## Shared by every exit (and the forge heart): save into the next level with
## the arrival point, then fade there. The knight arrives fresh (no death
## queue, no checkpoint heal) at `spawn_point`.
static func travel(scene_path: String, spawn_point: Vector2, player: Player) -> void:
	SaveData.pending_spawn = spawn_point
	SaveData.entering_from_checkpoint = false
	if player != null:
		# 章节切换等于一次休整：否则残血进关、还没点亮第一个巢就死，会反复带着残血
		# 读回这份存档。
		player.health.heal_full()
		player.toxin.purify(1.0)
		GameEvents.player_health_changed.emit(player.health.current, player.health.max_hp)
		SaveData.save_game(scene_path, player, spawn_point)
	Director.fade_to(scene_path)
