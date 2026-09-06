class_name LevelExit
extends Interactable
## 关卡出口：一扇门。E 进门 → 过场字幕 → 存档写下一关 + 落点 → 淡入下一关。
## `target_scene` 为空时是阶段结局：字幕后回标题（存档仍留在本关门前）。

const DOOR_TEX := "res://assets/env/moss_door.png"
const DOOR_SIZE := Vector2(48, 64)
const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"

@export var target_scene: String = ""
@export var spawn: Vector2 = Vector2.ZERO
@export var door_label: String = "门"
@export var captions: PackedStringArray = []
## 走过这扇门时点亮的剧情旗标（为空则不写）。
@export var flag_id: String = ""
## 需要先点亮的旗标（例如 Boss 死亡）；没点亮时门锁着，只给提示。
@export var requires_flag: String = ""
@export var locked_prompt: String = "门还锁着"

var _used := false


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
	if _used or not actor is Player:
		return
	if is_locked():
		Sfx.play(&"ui_denied", 0.04, -4.0)
		GameEvents.announcement.emit(locked_prompt)
		return
	_used = true
	Sfx.play(&"gate")
	var steps: Array = [{"kind": "lock"}]
	for line in captions:
		steps.append({"kind": "caption", "text": String(line), "hold": 2.2})
	steps.append({"kind": "wait", "seconds": 0.2})
	steps.append({"kind": "unlock"})
	Director.play(steps)
	await Director.finished
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if flag_id != "":
		SaveData.mark_flag(flag_id)
	var player := actor as Player
	if target_scene != "":
		travel(target_scene, spawn, player)
	else:
		SaveData.save_game(GameContext.world_scene_path(self), player)
		Director.fade_to(TITLE_PATH)


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
