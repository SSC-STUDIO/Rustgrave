class_name ChapterLevel
extends Node2D
## 章节关卡的通用场景脚本（level03 起）。场景里只有根节点 + 五个空组；
## `layout_path` 指向该关的 ChapterLayout 子类，_ready 读档、铺关、生成骑士/相机/HUD、
## 放开场字幕。关卡内容一律写在 layout 里，这个脚本不改。

const PLAYER := preload("res://scenes/player/Player.tscn")
const CAMERA := preload("res://scenes/camera/GameCamera.tscn")
const HUD := preload("res://scenes/ui/HUD.tscn")

@export_file("*.gd") var layout_path: String = ""

var layout: ChapterLayout
var _player: Player


func _enter_tree() -> void:
	add_to_group("game_world")


func _ready() -> void:
	DisplayFit.apply()
	var restored := false
	if SaveData.has_save():
		restored = SaveData.load_game()
	layout = _make_layout()
	if layout == null:
		push_error("ChapterLevel: no layout at %s" % layout_path)
		return
	layout.name = "Layout"
	add_child(layout)
	# 上一关的局部天气区域不能漏进这一关；本章配方在建关卡之前装好，
	# finish() 再铺出本关自己的区域。
	WorldClock.clear_weather_regions()
	WorldClock.set_weather_profile(layout.weather_recipe())
	WorldClock.set_zone(WorldClock.Zone.INDOORS if layout.indoors() else WorldClock.Zone.OUTDOORS)
	layout.build(self)
	if not layout.indoors() and not SaveData.has_flag("%s_wake" % layout.level_id()):
		apply_ambient(layout.ambient())
	_spawn_actors(restored)
	# Once per level load, after the knight, camera and HUD exist — Continue and
	# respawn-reloads included. Music and the stage reset their per-place state here.
	GameEvents.chapter_started.emit(layout.level_id())
	call_deferred("_wake")


func _make_layout() -> ChapterLayout:
	if layout_path == "" or not ResourceLoader.exists(layout_path):
		return null
	var script := load(layout_path) as GDScript
	if script == null:
		return null
	return script.new() as ChapterLayout


func _spawn_actors(restored: bool) -> void:
	_player = PLAYER.instantiate()
	_player.position = layout.default_spawn()
	add_child(_player)
	var from_checkpoint := SaveData.entering_from_checkpoint
	if SaveData.has_pending_spawn():
		_player.position = SaveData.consume_pending_spawn()
	elif restored and SaveData.data.has("player") and (SaveData.data["player"] as Dictionary).has("pos"):
		_player.position = SaveData.data["player"]["pos"]
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
	cam.limit_right = layout.east_limit()
	cam.limit_top = layout.camera_top()
	cam.global_position = _player.global_position + Vector2(0, -18)
	var hud: CanvasLayer = HUD.instantiate()
	GameContext.ui_host(self).add_child(hud)


func _wake() -> void:
	var returning := SaveData.entering_from_checkpoint
	SaveData.entering_from_checkpoint = false
	var flag := "%s_wake" % layout.level_id()
	# A reload after death is a return, not an arrival. And a card the player already
	# sat through this session stays seen even though the load rewinds the save flags.
	if returning:
		StoryStage.once(flag)
		return
	if not StoryStage.once(flag):
		return
	var steps: Array = [
		{"kind": "lock"},
		chapter_card(layout.title()),
	]
	if layout.wake_line() != "":
		steps.append({"kind": "caption", "text": layout.wake_line(), "hold": 2.0})
	# 每章进关都要回答「我现在要干什么」：醒来句之后补一句目标（文本在 ChapterText，
	# 一句 ≤16 字）。Boss 战/HUD 的实时目标仍由 ObjectiveTracker 另算，不改它。
	var objective := ChapterText.objective_of(layout.level_id())
	if objective != "":
		steps.append({"kind": "caption", "text": "目标 · %s" % objective, "hold": 1.8})
	steps.append({"kind": "unlock"})
	# One press skips the card and the line together. Waits out a scene fade or an open
	# pause menu instead of starting suspended inside a level nobody can unpause.
	Director.play_when_clear(steps, true, func() -> void: Music.stinger(&"chapter"))


## First arrival only (later respawns keep the saved clock). Weather is held so the
## chapter's signature sky does not flip within seconds of the title card.
static func apply_ambient(ambient: Dictionary) -> void:
	if ambient.is_empty():
		return
	if ambient.has("time"):
		WorldClock.set_time(float(ambient["time"]))
	if ambient.has("weather"):
		WorldClock.set_weather(WorldClock.weather_from_id(String(ambient["weather"])), true)
	WorldClock.set_weather_hold(float(ambient.get("hold", 240.0)))


## Chapter metadata remains the source of truth; cards do not invent story flags.
static func chapter_card(chapter_title: String, seconds: float = 2.6) -> Dictionary:
	var parts := chapter_title.split("—", false, 1)
	return {
		"kind": "tableau", "id": "chapter", "seconds": seconds,
		"title": String(parts[1]).strip_edges() if parts.size() > 1 else chapter_title,
		"subtitle": String(parts[0]).strip_edges() if parts.size() > 1 else "锈 墓",
	}
