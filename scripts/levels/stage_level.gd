class_name StageLevel
extends Node2D
## 《ICEY》式多房间拓扑节点控制器。
##
## 每个主线/支线节点是一个 `StageLevel` 场景，通过 `stage_script_path` 挂载 `StageRoomBuilder` 子类，
## 在单场景内按需热切换紧凑房间（640~1280px），并提供：
##   1. 0.16s 极速黑场房间擦除（测试环境下零帧直切）；
##   2. 当房满血重生（`room_checkpoint_spawn` + `StageRoomMemory` 零跑尸体验）；
##   3. 按 `stage_id_room_id:` 独立命名空间的 `consumed` / `lit_nests` / `world` 存档同步；
##   4. 无黑屏章节幕间卡——进房直接触发实时旁白条与游戏操作。

signal room_changed(room_id: String, spawn_tag: String)

const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/GameCamera.tscn")
const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
const TrialCatalog := preload("res://scripts/data/trial_catalog.gd")

@export_file("*.gd") var stage_script_path: String = ""

var layout: StageRoomBuilder
var stage_id: String = ""
var current_room_id: String = ""
var current_spawn_tag: String = "west"
var instant_room_transitions: bool = false

var _player: Player
var _camera: GameCamera
var _hud: CanvasLayer
var _wipe_layer: CanvasLayer
var _wipe_rect: ColorRect
var _transitioning: bool = false


func _enter_tree() -> void:
	add_to_group("game_world")


func save_namespace() -> String:
	if stage_id == "":
		return ""
	if current_room_id == "":
		return stage_id
	return "%s_%s" % [stage_id, current_room_id]


func _ready() -> void:
	DisplayFit.apply()
	var restored := false
	if SaveData.has_save():
		restored = SaveData.load_game()

	layout = _instantiate_layout()
	if layout == null:
		push_error("StageLevel: failed to load stage script '%s'" % stage_script_path)
		return
	layout.name = "Layout"
	add_child(layout)
	stage_id = layout.level_id()
	SaveData.unlock_node(stage_id)

	var init_pair := _resolve_initial_room(restored)
	current_room_id = String(init_pair["room_id"])
	current_spawn_tag = String(init_pair["spawn_tag"])

	_build_room_contents(current_room_id)
	if not layout.indoors() and not SaveData.has_flag("%s_wake" % stage_id):
		ChapterLevel.apply_ambient(layout.ambient())

	_spawn_actors(restored, current_room_id, current_spawn_tag)
	StageRoomMemory.set_checkpoint(stage_id, current_room_id, current_spawn_tag)
	SaveData.set_stage_room(stage_id, current_room_id, current_spawn_tag)

	GameEvents.chapter_started.emit(stage_id)
	GameEvents.room_entered.emit(stage_id, current_room_id)
	layout.on_room_entered(self, current_room_id)
	call_deferred("_wake")


func _instantiate_layout() -> StageRoomBuilder:
	if stage_script_path == "" or not ResourceLoader.exists(stage_script_path):
		return null
	var scr := load(stage_script_path) as GDScript
	if scr == null:
		return null
	return scr.new() as StageRoomBuilder


func _resolve_initial_room(restored: bool) -> Dictionary:
	var rooms := layout.room_ids()
	var fallback := layout.default_room()

	if TrialRun.active():
		var st := TrialRun.stage()
		var tr_room := String(st.get("room", ""))
		if tr_room != "" and rooms.has(tr_room):
			return {"room_id": tr_room, "spawn_tag": String(st.get("spawn_tag", "west"))}
		if TrialRun.track() == TrialCatalog.Track.BOSS_RUSH and layout.boss_room() != "":
			return {"room_id": layout.boss_room(), "spawn_tag": "west"}

	if StageRoomMemory.has_pending_for(stage_id):
		var pend := StageRoomMemory.consume_pending_for(stage_id)
		var pr := String(pend.get("room_id", fallback))
		if rooms.has(pr):
			return {"room_id": pr, "spawn_tag": String(pend.get("spawn_tag", "west"))}

	if SaveData.entering_from_checkpoint and StageRoomMemory.current_stage == stage_id \
			and rooms.has(StageRoomMemory.current_room):
		return {
			"room_id": StageRoomMemory.current_room,
			"spawn_tag": StageRoomMemory.current_spawn_tag,
		}

	if restored and String(SaveData.get_extra("saved_stage", "")) == stage_id:
		var sr := String(SaveData.get_extra("saved_room", ""))
		if sr != "" and rooms.has(sr):
			return {
				"room_id": sr,
				"spawn_tag": String(SaveData.get_extra("saved_spawn_tag", "west")),
			}

	return {"room_id": fallback, "spawn_tag": "west"}


func _build_room_contents(room_id: String) -> void:
	current_room_id = room_id
	WorldClock.clear_weather_regions()
	WorldClock.set_weather_profile(layout.weather_recipe())
	layout.plate_door_pairs.clear()
	remove_meta(&"chapter_overhaul")
	remove_meta(&"terrain_structure_queued")
	remove_meta(&"terrain_structure_built")
	layout.build_room(self, room_id)
	WorldClock.set_zone(WorldClock.Zone.INDOORS if layout.indoors() else WorldClock.Zone.OUTDOORS)
	layout.finish(self)


func _clear_room_children() -> void:
	for child in get_children():
		if child == layout or child == _player or child == _camera or child == _hud or child == _wipe_layer:
			continue
		if String(child.name) == "WorldEffects":
			continue
		remove_child(child)
		child.queue_free()


func _spawn_actors(restored: bool, room_id: String, spawn_tag: String) -> void:
	var default_pt := layout.spawn_for_room(room_id, spawn_tag)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = default_pt
	add_child(_player)

	var from_checkpoint := SaveData.entering_from_checkpoint
	var saved_stage := String(SaveData.get_extra("saved_stage", ""))
	var same_room_save := (saved_stage == stage_id and String(SaveData.get_extra("saved_room", "")) == room_id) \
			or (saved_stage == "" and SaveData.saved_scene() == scene_file_path and room_id == layout.default_room())
	if SaveData.has_pending_spawn():
		_player.position = SaveData.consume_pending_spawn()
	elif restored and same_room_save \
			and SaveData.data.has("player") and (SaveData.data["player"] as Dictionary).has("pos"):
		_player.position = SaveData.data["player"]["pos"]

	_player.position = SpawnSafety.safe_position(self, _player.position, default_pt)
	if restored:
		SaveData.apply_player(_player)
		SaveData.apply_world(self)
		SaveData.apply_consumed(self)
	SaveData.apply_lit_nests(self)
	if from_checkpoint:
		_player.health.heal_full()
		_player.toxin.purify(1.0)
		GameEvents.player_health_changed.emit(_player.health.current, _player.health.max_hp)

	_camera = CAMERA_SCENE.instantiate() as GameCamera
	add_child(_camera)
	_sync_camera_to_room()

	_hud = HUD_SCENE.instantiate() as CanvasLayer
	GameContext.ui_host(self).add_child(_hud)
	_build_wipe_overlay()


func _build_wipe_overlay() -> void:
	_wipe_layer = CanvasLayer.new()
	_wipe_layer.name = "RoomWipe"
	_wipe_layer.layer = 19
	GameContext.ui_host(self).add_child(_wipe_layer)
	_wipe_rect = ColorRect.new()
	_wipe_rect.color = Color(0.03, 0.02, 0.03, 0.0)
	_wipe_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe_layer.add_child(_wipe_rect)


func _exit_tree() -> void:
	if _wipe_layer != null and is_instance_valid(_wipe_layer) and _wipe_layer.get_parent() != self:
		_wipe_layer.queue_free()


func _sync_camera_to_room() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera.limit_left = 0
	_camera.limit_right = layout.east_limit()
	_camera.limit_top = layout.camera_top()
	_camera.limit_bottom = 400
	if _player != null and is_instance_valid(_player):
		_camera.global_position = _player.global_position + Vector2(0.0, -18.0)
		if "_follow_inited" in _camera:
			_camera.set("_follow_inited", false)


func _wake() -> void:
	var returning := SaveData.entering_from_checkpoint
	SaveData.entering_from_checkpoint = false
	if TrialRun.active() or returning:
		return
	# 新游戏首次进入 stage01 起始房：运行序章分镜 + 骑士拔剑起身
	if stage_id == "stage01" and current_room_id == layout.default_room() and OpeningCinematic.should_play():
		var first_nest := _find_first_nest()
		OpeningCinematic.try_start(_player, first_nest)
		return
	var wake_flag := "%s_wake" % stage_id
	if not SaveData.has_flag(wake_flag):
		SaveData.mark_flag(wake_flag)
		var ttl := ChapterText.title_of(stage_id)
		if ttl != "":
			GameEvents.announcement.emit(ttl)


func _find_first_nest() -> Node2D:
	var props := get_node_or_null("Props")
	if props == null:
		return null
	for child in props.get_children():
		if child is EmberNest:
			return child as Node2D
	return null


## 当房重生点：供 Player._on_died 在无点亮余烬巢时零跑尸满血重返当前房间入口。
func room_checkpoint_spawn() -> Vector2:
	if layout == null:
		return SaveData.NEW_GAME_SPAWN
	return layout.spawn_for_room(current_room_id, current_spawn_tag)


## RoomGate 调用的统一过渡入口。
func request_room_transition(target_room: String, target_spawn: String = "west",
		target_stage: String = "") -> void:
	if _transitioning:
		return
	if target_stage != "" and target_stage != stage_id:
		_transitioning = true
		SaveData.unlock_node(target_stage)
		var next_room := target_room
		StageRoomMemory.set_pending(target_stage, next_room, target_spawn)
		SaveData.set_stage_room(target_stage, next_room, target_spawn)
		var next_path := String(GameContext.LEVELS.get(target_stage, GameContext.WORLD_PATH))
		if _player != null and is_instance_valid(_player) and not TrialRun.active():
			_player.health.heal_full()
			_player.toxin.purify(1.0)
			GameEvents.player_health_changed.emit(_player.health.current, _player.health.max_hp)
			SaveData.save_game(next_path, _player)
		Director.fade_to(next_path, 0.24)
		return

	if target_room == "" or not layout.room_ids().has(target_room):
		return
	_transitioning = true
	call_deferred("_run_room_swap", target_room, target_spawn)


func _run_room_swap(target_room: String, target_spawn: String) -> void:
	if not is_inside_tree():
		_transitioning = false
		return
	var fast_test := instant_room_transitions or Director.is_test_runner()
	if not fast_test and _wipe_rect != null and is_instance_valid(_wipe_rect):
		GameContext.suppress_gameplay_input()
		var t_in := create_tween()
		t_in.tween_property(_wipe_rect, "color:a", 1.0, 0.08)
		await t_in.finished
		if not is_inside_tree():
			_transitioning = false
			return
		load_room_immediate(target_room, target_spawn)
		var t_out := create_tween()
		t_out.tween_property(_wipe_rect, "color:a", 0.0, 0.08)
		await t_out.finished
	else:
		load_room_immediate(target_room, target_spawn)
	_transitioning = false


## 立即切换至本节点指定房间（供 `_run_room_swap` 与拓扑自检测试直接调用）。
func load_room_immediate(room_id: String, spawn_tag: String = "west") -> void:
	if layout == null or not layout.room_ids().has(room_id):
		return
	_clear_room_children()
	current_spawn_tag = spawn_tag if spawn_tag != "" else "west"
	_build_room_contents(room_id)

	var spawn_pt := layout.spawn_for_room(room_id, current_spawn_tag)
	if _player != null and is_instance_valid(_player):
		_player.velocity = Vector2.ZERO
		_player.position = SpawnSafety.safe_position(self, spawn_pt, spawn_pt)

	SaveData.apply_world(self)
	SaveData.apply_consumed(self)
	SaveData.apply_lit_nests(self)
	_sync_camera_to_room()

	StageRoomMemory.set_checkpoint(stage_id, room_id, current_spawn_tag)
	SaveData.set_stage_room(stage_id, room_id, current_spawn_tag)
	if _player != null and is_instance_valid(_player) and not TrialRun.active() and SaveData.has_save():
		SaveData.persist_progress(_player)

	GameEvents.room_entered.emit(stage_id, room_id)
	layout.on_room_entered(self, room_id)
	room_changed.emit(room_id, current_spawn_tag)
