extends Node
## 1D Boss 演出验收夹具（不是全流程通关）：在真实的一章场景里跑刽子手的
## 进场 / 读招 / 二阶段 / 倒地 / 残芯交接 / 章节切场，按节拍抓实机渲染图并写报告。
##
##   & $godot --path <proj> --windowed --resolution 1280x720 \
##       --rendering-method gl_compatibility res://scenes/tools/BossPresentationAcceptance.tscn
##
## 输出到 screenshots/peek/lead-1d/；使用自己的一次性存档，不碰玩家存档。
## 夹具只负责位移玩家 / 直接扣血这类「摆位」，事件、Director 剧本、灯光、HUD、
## 存档与章节切场全部走真实游戏路径。驱动节点留在根下，跟着真实场景切换一起走。

const OUT := "res://screenshots/peek/lead-1d"
const ERRORS := preload("res://tests/error_collector.gd")
## 进场镜头时间轴（秒）：门砸下 0.18 → 交出竞技场 0.45 → 吼 0.3 → 推近 0.4。
const INTRO_CARD_AT := 1.0

var errors
var shots: Array[String] = []
var report: Dictionary = {}
var deadline := 0
var _boss: ExecutionerBoss
var _wing: Level01EastWing
var _player: Player
var _camera: GameCamera


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	errors = ERRORS.new()
	OS.add_logger(errors)
	deadline = Time.get_ticks_msec() + 180000
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	SaveData.save_path = OUT + "/boss-presentation-save.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	# 驱动节点不入 current_scene：后续的真实切场（复燃 → Level02）不会把它一起释放。
	get_tree().current_scene = null
	call_deferred("_run")


func _process(_delta: float) -> void:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		report["timeout"] = true
		_finish()


func _run() -> void:
	# 跳过开场：这一轮只看刽子手。旗标走真实存档字段，不伪造演出。
	SaveData.mark_flag("wake")
	SaveData.mark_flag("opening_seen")
	GameContext.pending_world_path = GameContext.LEVELS["level01"]
	get_tree().change_scene_to_file(GameContext.PRESENTATION_PATH)
	if not await _wait_world(240):
		report["error"] = "level01 never loaded"
		_finish()
		return
	Director.abort()
	Director.set_letterbox(false, true)
	Director.hide_hint()
	_player = get_tree().get_first_node_in_group("player") as Player
	_camera = get_tree().get_first_node_in_group("game_camera") as GameCamera
	_wing = _find_wing()
	_boss = _wing.boss if _wing != null else null
	report["bound"] = {
		"player": _player != null,
		"boss": _boss != null,
		"wing": _wing != null,
		"boss_position": _boss.global_position if _boss != null else Vector2.INF,
	}
	if _player == null or _camera == null or _wing == null or _boss == null:
		push_error("boss presentation fixture could not bind the arena")
		_finish()
		return
	# 干净开局：等 HUD 教学提示自己退，别盖住竞技场构图。
	await get_tree().create_timer(2.6).timeout
	for child in get_tree().get_nodes_in_group("enemies"):
		child.set_physics_process(false)
		child.set_process(false)
	_player.set_physics_process(false)
	_player.health.invincible = true
	_player.cutscene_locked = false

	# 1) 通常游玩视角：还没跨门，Boss 未宣布、血条未出现，竞技场灯已亮。
	_place_player(Vector2(1660, 300))
	_snap_camera_to_player()
	await get_tree().create_timer(0.8).timeout
	await _capture("01-arena-approach")
	report["approach"] = {
		"announced": _boss.is_announced(),
		"hearths": _wing.arena_hearth_count(),
		"hearth_energy": _wing.arena_light_energy(),
		"presence_alpha": _boss.presence_alpha(),
		"boss_position": _boss.global_position,
		"player_hp": _player.health.current,
	}

	# 2) 跨门：真实 Area2D 触发 —— 东翼宣布、炉火涌起、名号卡与进场剧本。
	_place_player(Vector2(1688, 300))
	_player.set_physics_process(true)
	var entered := false
	for _i in 50:
		await get_tree().physics_frame
		if _boss.is_announced():
			entered = true
			break
	_player.set_physics_process(false)
	_player.health.invincible = true
	report["gate_entry_announced"] = entered
	await get_tree().create_timer(INTRO_CARD_AT).timeout
	await _capture("02-gate-intro")
	_pause_ai()
	report["intro"] = {
		"playing": Director.playing,
		"locked": Director.is_input_locked(),
		"nameplate": _active_shot(),
		"hearth_energy": _wing.arena_light_energy(),
		"surge": _wing._arena_surge,
	}
	# 整段进场可跳过；跳过必须交还镜头与输入。
	Director.skip_step()
	await get_tree().create_timer(0.25).timeout
	report["intro_skip"] = {
		"playing": Director.playing,
		"locked": Director.is_input_locked(),
		"camera_focused": _camera._focused,
		"knight_locked": _player.cutscene_locked,
	}
	# 3) 进场后的竞技场构图（正常游玩视角，1x 与 640×360 原生各一张）。
	_place_player(Vector2(1740, 300))
	_snap_camera_to_player()
	await get_tree().create_timer(0.8).timeout
	await _capture("03-arena-composed")
	await _capture_native("03b-arena-native-640x360")

	# 4) 读招：把骑士放进斧程，让 Boss 自己起手，抓前摇红框与余烬脉冲。
	_place_player(Vector2(1772, 300))
	await _capture_telegraph("04-axe-telegraph")

	# 5) 二阶段：半血相变（炽红竞技场 + 名号卡相数 + 吼叫）。
	_pause_ai()
	_boss.set_physics_process(true)
	_boss.set_process(true)
	_boss.health.invincible = false
	_boss.health.take_damage(7, _player)
	await get_tree().create_timer(0.45).timeout
	await _capture("05-phase-two")
	_pause_ai()
	report["phase_two"] = {
		"enraged": _boss.is_enraged(),
		"arena_hot": _wing.arena_lights_hot(),
		"presence_hot": _boss.presence_hot(),
		"hearth_energy": _wing.arena_light_energy(),
		"nameplate": _active_shot(),
	}
	if Director.playing:
		Director.skip_step()
	await get_tree().create_timer(0.4).timeout

	# 6) 倒地：死亡演出 + 舞台暗场。
	_boss.set_physics_process(true)
	_boss.set_process(true)
	_boss.health.invincible = false
	_boss.health.take_damage(99, _player)
	await get_tree().create_timer(0.85).timeout
	await _capture("06-boss-death")
	await _wait_director_idle(7.0)
	var heart := _heart()
	report["death"] = {
		"boss_gone": not is_instance_valid(_boss),
		"arena_dimmed": _wing.arena_lights_dimmed(),
		"hearth_energy": _wing.arena_light_energy(),
		"locked": Director.is_input_locked(),
		"camera_focused": _camera._focused if is_instance_valid(_camera) else false,
		"heart_unlocked": heart.unlocked if heart != null else false,
		"boss_dead_flag": SaveData.has_flag("boss_dead"),
	}

	# 7) 残芯成为可交互目标：站过去让 E 提示自己出来。
	_place_player(Vector2(2050, 300))
	_snap_camera_to_player()
	# E 提示由骑士自己的物理帧刷新：这一段把骑士的物理打开（位置已摆好，不会再跑）。
	_player.set_physics_process(true)
	await get_tree().create_timer(0.9).timeout
	# 夹具把骑士直接摆到残芯旁：E 提示要等传感器在物理帧里认出目标，
	# 站位擦边时补一次进入事件（摆位是夹具行为，交互判定仍是真实逻辑）。
	var focus := _player.sensor.get_focus()
	if focus == null and heart != null:
		_player.sensor._on_area_entered(heart)
		await get_tree().create_timer(0.2).timeout
	await _capture("07-heart-unlocked")
	report["heart"] = {
		"unlocked": heart.unlocked if heart != null else false,
		"can_interact": heart.can_interact(_player) if heart != null else false,
		"focus": _player.sensor.get_focus() == heart,
		"prompt": _interaction_prompt(),
		"arena_dimmed": _wing.arena_lights_dimmed(),
	}
	# 8) 章节交接：走真实的「复燃」路径（ForgeHeart → LevelExit.travel → Level02）。
	if heart != null and heart.unlocked:
		heart._on_chosen(ForgeHeart.ID_REKINDLE)
		var switched := false
		for _i in 480:
			await get_tree().process_frame
			var worlds := get_tree().get_nodes_in_group("game_world")
			if not Director.is_fading() and worlds.size() == 1 \
					and worlds[0].name == "Level02_Undercroft":
				switched = true
				break
		await get_tree().create_timer(0.9).timeout
		await _capture("08-level02-arrival")
		var worlds := get_tree().get_nodes_in_group("game_world")
		report["chapter_handoff"] = {
			"switched": switched,
			"pending_world": GameContext.pending_world_path,
			"scene": get_tree().current_scene.name if get_tree().current_scene != null else "",
			"world": worlds[0].name if worlds.size() == 1 else "",
			"locked": Director.is_input_locked(),
		}
	else:
		report["chapter_handoff"] = {"switched": false, "reason": "heart was not unlocked"}
	report["engine_errors"] = errors.errors()
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["purpose"] = "Executioner presentation fixture (not a full playthrough)"
	_finish()


# --- helpers ------------------------------------------------------------------

func _wait_world(frames: int) -> bool:
	for _i in frames:
		await get_tree().process_frame
		var worlds := get_tree().get_nodes_in_group("game_world")
		if worlds.size() == 1 and get_tree().get_first_node_in_group("player") != null:
			return true
	return false


func _find_wing() -> Level01EastWing:
	for node in get_tree().get_nodes_in_group("game_world"):
		for child in node.find_children("*", "", true, false):
			if child is Level01EastWing:
				return child as Level01EastWing
	return null


func _heart() -> ForgeHeart:
	for node in get_tree().get_nodes_in_group("game_world"):
		var heart := node.get_node_or_null("Props/ForgeHeart") as ForgeHeart
		if heart != null:
			return heart
	return null


func _active_shot() -> String:
	var presentation := Director.get_node_or_null("CinematicPresentation")
	return String(presentation.active_shot) if presentation != null else ""


func _interaction_prompt() -> String:
	var worlds := get_tree().get_nodes_in_group("game_world")
	if worlds.is_empty():
		return ""
	var ui := GameContext.ui_host(worlds[0])
	if ui == null:
		return ""
	var hud := ui.get_node_or_null("HUD")
	if hud == null:
		return ""
	var prompt := hud.find_child("Prompt", true, false) as Label
	if prompt == null:
		prompt = hud.find_child("PromptLabel", true, false) as Label
	return prompt.text if prompt != null else ""


func _place_player(at: Vector2) -> void:
	if not is_instance_valid(_player):
		return
	_player.set_physics_process(false)
	_player.health.invincible = true
	_player.global_position = at
	_player.velocity = Vector2.ZERO


## 让真实跟随相机立刻贴到夹具摆好的骑士身上（之后照常由相机自己跟）。
func _snap_camera_to_player() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_player):
		return
	_camera.set_physics_process(true)
	_camera.global_position = _player.global_position + Vector2(0, -18)
	if "_follow_inited" in _camera:
		_camera.set("_follow_inited", false)


func _pause_ai() -> void:
	for child in get_tree().get_nodes_in_group("enemies"):
		child.set_physics_process(false)
		child.set_process(false)


func _wait_director_idle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and (Director.playing or Director.is_fading()):
		await get_tree().process_frame


## 抓读招：等 Boss 自己开始挥斧，落到红框最亮的后段。
func _capture_telegraph(shot: String) -> void:
	_boss.set_physics_process(true)
	_boss.set_process(true)
	# GDScript 的 lambda 按值捕获局部变量：用数组当可变盒子。
	var seen: Array = []
	var on_telegraph := func(kind: StringName, _duration: float) -> void:
		if kind == &"executioner":
			seen.append(kind)
	_boss.telegraph_started.connect(on_telegraph)
	for _i in 420:
		await get_tree().physics_frame
		if not seen.is_empty():
			break
	await get_tree().create_timer(0.2).timeout
	var zone_markers := 0
	for child in _boss.get_children():
		if child is CombatMarker and (child as CombatMarker).kind == CombatMarker.Kind.ZONE:
			zone_markers += 1
	report["telegraph"] = {
		"announced": not seen.is_empty(),
		"zone_markers": zone_markers,
		"slash_phase": int(_boss._slash_phase),
		"slash_timer": _boss._slash_timer,
		"player_hp": _player.health.current,
	}
	await _capture(shot)
	_boss.telegraph_started.disconnect(on_telegraph)
	_pause_ai()


func _capture(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + "/boss_%s.png" % shot
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("could not save " + path)
	shots.append(path)


## 640×360 原生窗口的一帧：检验 Boss 在最小可读分辨率下的剪影。
func _capture_native(shot: String) -> void:
	var win := get_tree().root
	win.size = Vector2i(640, 360)
	for _i in 8:
		await get_tree().process_frame
	await _capture(shot)
	win.size = Vector2i(1280, 720)
	for _i in 8:
		await get_tree().process_frame


func _finish() -> void:
	report["captures"] = shots
	var file := FileAccess.open(OUT + "/boss_presentation_report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	OS.remove_logger(errors)
	print("BOSS PRESENTATION: ", JSON.stringify(report))
	SaveData.delete_save()
	get_tree().quit(0)
