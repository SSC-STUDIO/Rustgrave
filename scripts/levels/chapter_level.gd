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
	WorldClock.set_zone(WorldClock.Zone.INDOORS if layout.indoors() else WorldClock.Zone.OUTDOORS)
	layout.build(self)
	_spawn_actors(restored)
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
	SaveData.entering_from_checkpoint = false
	var flag := "%s_wake" % layout.level_id()
	if SaveData.has_flag(flag):
		return
	SaveData.mark_flag(flag)
	var steps: Array = [
		{"kind": "lock"},
		{"kind": "caption", "text": layout.title(), "hold": 1.8},
	]
	if layout.wake_line() != "":
		steps.append({"kind": "caption", "text": layout.wake_line(), "hold": 2.0})
	steps.append({"kind": "unlock"})
	Director.play(steps)
