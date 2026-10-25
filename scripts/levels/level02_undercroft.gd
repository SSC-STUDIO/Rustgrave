class_name Level02Undercroft
extends Node2D
## 锈墓・贰「沉钟地窟」场景脚本。续火之后陵墓醒来，炉心下方的石板松开，
## 骑士落进淹着苔水的地窟。整关室内：没有天气与昼夜，只有冷青的壁龛灯与幽魂的眼。
## 铺设全部在 Level02Layout；这里只管读档、生成骑士/相机/HUD 和开场字幕。

const PLAYER := preload("res://scenes/player/Player.tscn")
const CAMERA := preload("res://scenes/camera/GameCamera.tscn")
const HUD := preload("res://scenes/ui/HUD.tscn")

const LEVEL_ID := "level02"
const ENTRY_SPAWN := Level02Layout.ENTRY_SPAWN
const DEFAULT_SPAWN := Level02Layout.DEFAULT_SPAWN
const EAST_LIMIT := Level02Layout.EAST_LIMIT
const CAMERA_TOP := Level02Layout.CAMERA_TOP

var _player: Player
var _layout: Level02Layout


func _enter_tree() -> void:
	add_to_group("game_world")


func _ready() -> void:
	DisplayFit.apply()
	var restored := false
	if SaveData.has_save():
		restored = SaveData.load_game()
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	_layout = Level02Layout.new()
	_layout.name = "Layout"
	add_child(_layout)
	_layout.build(self)
	_spawn_actors(restored)
	# 和其他章节一样发 chapter_started：01→02 的章间分镜（ChapterTransition）、Music 的章节
	# 曲、HUD 的目标条、StoryStage 的硬复位都挂在它上面。以前这一关不发，章间永远不播。
	GameEvents.chapter_started.emit(LEVEL_ID)
	call_deferred("_wake")


func _spawn_actors(restored: bool) -> void:
	_player = PLAYER.instantiate()
	_player.position = DEFAULT_SPAWN
	add_child(_player)
	var from_checkpoint := SaveData.entering_from_checkpoint
	if SaveData.has_pending_spawn():
		_player.position = SaveData.consume_pending_spawn()
	elif restored and SaveData.data.has("player") and (SaveData.data["player"] as Dictionary).has("pos"):
		_player.position = SaveData.data["player"]["pos"]
	_player.position = SpawnSafety.safe_position(self, _player.position, DEFAULT_SPAWN)
	if restored:
		SaveData.apply_player(_player)
		SaveData.apply_world(self)
		SaveData.apply_consumed(self)
	SaveData.apply_lit_nests(self)
	if from_checkpoint:
		_player.health.heal_full()
		_player.toxin.purify(1.0)
		GameEvents.player_health_changed.emit(_player.health.current, _player.health.max_hp)
	var cam: GameCamera = CAMERA.instantiate()
	add_child(cam)
	cam.limit_right = EAST_LIMIT
	cam.limit_top = CAMERA_TOP
	cam.global_position = _player.global_position + Vector2(0, -18)
	var hud: CanvasLayer = HUD.instantiate()
	GameContext.ui_host(self).add_child(hud)


## 章节到达：章间分镜（ChapterTransition 先入队）→ 章节卡 → 醒来句 → 目标，和 ChapterLevel._wake
## 同一套顺序与语义：死亡读档是「回来」不是「到达」；本会话看过的卡不再来（StoryStage.once）。
func _wake() -> void:
	var returning := SaveData.entering_from_checkpoint
	SaveData.entering_from_checkpoint = false
	if returning:
		StoryStage.once("l2_wake")
		return
	if not StoryStage.once("l2_wake"):
		return
	var steps: Array = [
		{"kind": "lock"},
		ChapterLevel.chapter_card(ChapterText.title_of(LEVEL_ID)),
		{"kind": "caption", "text": ChapterText.wake_of(LEVEL_ID), "hold": 2.0},
	]
	var objective := ChapterText.objective_of(LEVEL_ID)
	if objective != "":
		steps.append({"kind": "caption", "text": "目标 · %s" % objective, "hold": 1.8})
	steps.append({"kind": "unlock"})
	# 一次确认跳过卡和字幕；等淡变 / 暂停菜单收掉再开，不在没人能解锁的关里挂起。
	Director.play_when_clear(steps, true, func() -> void: Music.stinger(&"chapter"))
