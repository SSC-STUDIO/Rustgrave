extends Node
## 通用 Boss 验收夹具（M3 task-8）。不是全流程通关：把一章真实关卡载进画面壳，
## 绑定其中一个 Boss，按「入场 -> 每个阶段 -> 死亡」逐拍渲染并写 report.json。
##
##   & $godot --path <proj> --windowed --position -12000,-12000 \
##       --resolution 1280x720 --rendering-method gl_compatibility \
##       res://scenes/tools/BossFixture.tscn -- --level=level01
##   & $godot --path <proj> --windowed ... -- --level=level10 --boss=Nightmare
##   & $godot --path <proj> --headless ... -- --level=level10 --smoke
##
## 输出：user://boss_fixture/<level>_<boss>/boss_*.png + report.json
##   （report.json 里写的是绝对路径；--out= 可覆盖输出目录，支持 user:// / 绝对路径）。
## 使用自己的临时存档（user://rustgrave_boss_fixture.cfg），不碰玩家档；
## 关卡里的旗标 / 战斗时序全部走真实游戏路径，只有「把骑士摆到门口 / 直接扣血」
## 这类取景动作是夹具行为（和 1D 演出夹具同一约定）。

const OUT_DEFAULT := "user://boss_fixture"
const SAVE_PATH := "user://rustgrave_boss_fixture.cfg"
const ERRORS := preload("res://tests/error_collector.gd")
const BOSS_ARENA := preload("res://scripts/world/boss_arena.gd")
const DEADLINE_MS := 180000

## 每个已知关卡的取景提示：Boss 节点名、竞技场左右界、进场触发点（世界 x）。
## 新 Boss 的关卡 agent 在这里补一行即可；缺省则按 Boss 自身 arena_left/right 推断。
const LEVEL_HINTS := {
	"level01": {
		"boss": "ExecutionerBoss",
		"arena": Vector2(3104.0, 3744.0),
		"intro_trigger": 3112.0,
	},
	"level10": {
		"boss": "Nightmare",
		"arena": Vector2(1100.0, 2300.0),
		"intro_trigger": 1150.0,
	},
}

var level_id: String = "level01"
var boss_name: String = ""
var out_dir: String = OUT_DEFAULT
var headless: bool = false
var smoke: bool = false
var report: Dictionary = {}
var shots: Array[String] = []
var deadline: int = 0

var errors
var _world: Node2D
var _boss: Node2D
var _player: Player
var _camera: GameCamera
var _arena: BossArena
var _director: BossDirector


# ---------------------------------------------------------------------------
# 静态工具（headless smoke / 测试读）
# ---------------------------------------------------------------------------
## 拍摄计划：入场 -> 一阶段读招 -> 二阶段 -> … -> 死亡。
## 每项：{id, label, screen, action, phase}。stage_plan(2) 长度 4，stage_plan(3) 长度 5。
static func stage_plan(max_phases: int) -> Array:
	var plan: Array = []
	plan.append({"id": "intro", "label": "入场", "screen": "00-intro",
		"action": "intro", "phase": 0})
	var phases := clampi(max_phases, 1, 3)
	for phase in range(1, phases + 1):
		plan.append({
			"id": "phase%d" % phase,
			"label": "第 %d 阶段读招" % phase,
			"screen": "%02d-phase%d" % [phase, phase],
			"action": "phase",
			"phase": phase,
		})
	plan.append({"id": "death", "label": "死亡", "screen": "%02d-death" % (phases + 1),
		"action": "death", "phase": phases + 1})
	return plan


## report.json 的骨架（夹具与测试共用同一字段口径）。
static func empty_report(p_level: String, p_boss: String) -> Dictionary:
	return {
		"purpose": "generic boss fixture (not a full playthrough)",
		"level_id": p_level,
		"boss_node": p_boss,
		"headless": false,
		"renderer": "",
		"boss": {},
		"arena": {},
		"checkpoint": {},
		"stages": [],
		"captures": [],
		"engine_errors": [],
	}


## 某个关卡的竞技场左右界（先读关卡 hints，再读 Boss 自身 arena_left/right）。
static func arena_bounds_for(p_level: String, boss: Node2D) -> Vector2:
	if boss != null and boss.has_method("boss_arena_bounds"):
		var bounds: Vector2 = boss.call("boss_arena_bounds")
		if is_finite(bounds.x) and is_finite(bounds.y) and bounds.y > bounds.x:
			return bounds
	var hint: Dictionary = LEVEL_HINTS.get(p_level, {})
	if hint.has("arena"):
		return hint["arena"] as Vector2
	if boss is Node2D:
		var x := (boss as Node2D).global_position.x
		return Vector2(x - 240.0, x + 240.0)
	return Vector2(0.0, 640.0)


# ---------------------------------------------------------------------------
# 启动
# ---------------------------------------------------------------------------
func _ready() -> void:
	_parse_args()
	headless = DisplayServer.get_name() == "headless"
	if headless and not smoke:
		# headless 无法读 viewport 图像；要跑逻辑烟雾就显式加 --smoke。
		print("BossFixture: headless without --smoke, nothing to render; quitting.")
		get_tree().quit(2)
		return
	errors = ERRORS.new()
	OS.add_logger(errors)
	deadline = Time.get_ticks_msec() + DEADLINE_MS
	report = empty_report(level_id, boss_name)
	report["headless"] = headless
	out_dir = OUT_DEFAULT + "/" + level_id + "_" + (boss_name if boss_name != "" else "auto")
	report["out_dir"] = ProjectSettings.globalize_path(out_dir)
	if not headless:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		var win := get_tree().root
		win.mode = Window.MODE_WINDOWED
		win.position = Vector2i(-12000, -12000)
		win.size = Vector2i(1280, 720)
		Engine.max_fps = 60
	# 独立临时存档：不碰玩家档，也不被玩家档的旗标影响。
	SaveData.save_path = SAVE_PATH
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	SaveData.consumed.clear()
	SaveData.lit_nests.clear()
	# 驱动节点留在根下：真实切场不会把它一起释放（1D 演出夹具同一约定）。
	get_tree().current_scene = null
	call_deferred("_run")


func _process(_delta: float) -> void:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		report["timeout"] = true
		_finish()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_id = arg.trim_prefix("--level=")
		elif arg.begins_with("--boss="):
			boss_name = arg.trim_prefix("--boss=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--smoke":
			smoke = true


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
func _run() -> void:
	var world_path: String = GameContext.LEVELS.get(level_id, "")
	if world_path == "" or not ResourceLoader.exists(world_path):
		report["error"] = "unknown level id: %s" % level_id
		_finish()
		return
	# 跳过开场；只看这一场 Boss。
	SaveData.mark_flag("wake")
	SaveData.mark_flag("opening_seen")
	GameContext.pending_world_path = world_path
	get_tree().change_scene_to_file(GameContext.PRESENTATION_PATH)
	if not await _wait_world(300):
		report["error"] = "%s never loaded" % level_id
		_finish()
		return
	_world = _find_world()
	_player = get_tree().get_first_node_in_group("player") as Player
	_camera = get_tree().get_first_node_in_group("game_camera") as GameCamera
	_boss = _find_boss()
	if _world == null or _player == null or _boss == null:
		report["error"] = "fixture could not bind world/player/boss"
		report["bound"] = {"world": _world != null, "player": _player != null, "boss": _boss != null}
		_finish()
		return
	_bind_boss()
	await _settle()
	var plan := stage_plan(_max_phases())
	report["stages_plan"] = plan.map(func(row: Dictionary) -> String: return String(row.id))
	for row in plan:
		match String(row.action):
			"intro":
				await _stage_intro(row)
			"phase":
				await _stage_phase(row)
			"death":
				await _stage_death(row)
	report["engine_errors"] = errors.errors()
	report["renderer"] = RenderingServer.get_current_rendering_method()
	_finish()


func _finish() -> void:
	report["captures"] = shots
	if not headless:
		var dir_abs := ProjectSettings.globalize_path(out_dir)
		DirAccess.make_dir_recursive_absolute(dir_abs)
		var file := FileAccess.open(dir_abs + "/report.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
	# 无论渲染与否都打印一份，CI / 终端可读。
	print("BOSS FIXTURE: ", JSON.stringify(report))
	if errors != null:
		OS.remove_logger(errors)
	SaveData.delete_save()
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# 绑定
# ---------------------------------------------------------------------------
func _bind_boss() -> void:
	var bounds := arena_bounds_for(level_id, _boss)
	report["boss_node"] = String(_boss.name)
	_arena = BOSS_ARENA.attach(_world, String(_boss.name) + "FixtureArena", _boss,
			bounds.x, bounds.y, _boss.global_position.y, true)
	if _arena != null:
		_arena.arena_top = minf(-320.0, _boss.global_position.y - 420.0)
		_arena.arena_bottom = _boss.global_position.y + 160.0
		# 开战由真实的 boss_intro_started 驱动（attach 已按名号匹配打开）。
		_arena.clamp_player = true
		_arena.clamp_boss = true
	if _boss.has_method("boss_director"):
		_director = _boss.call("boss_director") as BossDirector
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy != _boss:
			enemy.set_physics_process(false)
			enemy.set_process(false)
	_player.health.invincible = true
	_player.set_physics_process(false)
	_player.cutscene_locked = false
	_report_boss("bound")


func _find_world() -> Node2D:
	var worlds := get_tree().get_nodes_in_group("game_world")
	return worlds[0] as Node2D if worlds.size() == 1 else null


func _find_boss() -> Node2D:
	var wanted := boss_name
	if wanted == "":
		var hint: Dictionary = LEVEL_HINTS.get(level_id, {})
		wanted = String(hint.get("boss", ""))
	if wanted != "":
		var found := _world.find_child(wanted, true, false) as Node2D
		if found != null:
			return found
	# 兜底：世界里第一个带 boss_kit() 的敌人（Boss 脚本都用它接框架）。
	for node in _world.find_children("*", "", true, false):
		if node is Node2D and node.has_method("boss_kit"):
			return node as Node2D
	return null


func _max_phases() -> int:
	if _boss.has_method("boss_kit"):
		var kit := _boss.call("boss_kit") as BossKit
		if kit != null:
			return kit.max_phases()
	return 2


# ---------------------------------------------------------------------------
# 阶段
# ---------------------------------------------------------------------------
func _stage_intro(row: Dictionary) -> void:
	# 先把开章卡 / 遗留剧本清干净：输入被 Director 锁着时 Boss 的 AI 不跑，
	# 会让「走到门口触发」变成超时。
	await _clear_director()
	# 把骑士摆到门口 / 触发点：能走真实的 boss_intro_started 就走。
	var trigger_x := _boss.global_position.x - 120.0
	var hint: Dictionary = LEVEL_HINTS.get(level_id, {})
	if level_id == "level01" and hint.has("intro_trigger"):
		trigger_x = float(hint["intro_trigger"])
	await _place_player(Vector2(trigger_x, _boss.global_position.y - 20.0), true)
	var announced := await _wait_until(func() -> bool: return _boss_announced(), 240)
	var path := "trigger"
	if not announced and _boss.has_method("announce"):
		_boss.call("announce")
		path = "direct"
		await _wait(0.3)
	announced = _boss_announced()
	report["intro"] = {
		"announced": announced,
		"path": path,
		"director_playing": Director.playing,
		"input_locked": Director.is_input_locked(),
		"arena_active": _arena != null and _arena.is_active(),
	}
	# 开场镜头跑一小段（保留名号卡 / 进场冲击），随后跳过并交还镜头与输入。
	await _wait(0.9)
	await _capture(String(row.screen))
	if Director.playing:
		Director.skip_step()
		await _wait(0.25)
	if _arena != null and not _arena.is_active():
		_arena.activate()
	_report_boss("intro")
	report["stages"].append(_stage_record(row, "intro"))


func _stage_phase(row: Dictionary) -> void:
	var phase := int(row.phase)
	if phase > 1:
		await _damage_to_phase(phase)
		await _wait(0.45)
	elif _boss_has_telegraph():
		# 一阶段：抓一次真实读招（预警标记 + 地面框 / 路径线）。
		await _capture_telegraph()
	await _capture(String(row.screen))
	_report_boss(String(row.id))
	report["stages"].append(_stage_record(row, "phase"))


func _stage_death(row: Dictionary) -> void:
	_report_boss("before_death")
	var health := _boss.get_node_or_null("Health") as Health
	if health != null:
		health.invincible = false
		health.take_damage(999, _player)
	# 死亡演出（慢动作 / 震屏 / 尸体）刚开始的那一拍。
	await _wait(0.35)
	await _capture(String(row.screen))
	# 死亡演出 / 章节承接可能压着 Director 剧本：给一拍再跳过，取景不被黑边吃掉。
	if Director.playing:
		await _wait(0.4)
		Director.skip_step()
	Engine.time_scale = 1.0
	await _wait_director_idle(6.0)
	await _wait(0.3)
	await _capture(String(row.screen) + "-cleared")
	_report_arena()
	var death: Dictionary = {
		"boss_gone": _boss == null or not is_instance_valid(_boss),
		"arena_cleared": _arena != null and _arena.is_cleared(),
		"director_playing": Director.playing,
		"input_locked": Director.is_input_locked(),
	}
	report["death"] = death
	report["checkpoint"] = _arena.checkpoint_report() if _arena != null else {}
	report["stages"].append(_stage_record(row, "death"))


## 扣血到某一阶段的阈值（夹具摆位行为，伤害与相变仍走真实 Health/信号）。
func _damage_to_phase(phase: int) -> void:
	var health := _boss.get_node_or_null("Health") as Health
	if health == null or not _boss.has_method("boss_kit"):
		return
	var kit := _boss.call("boss_kit") as BossKit
	if kit == null:
		return
	health.invincible = false
	_boss.set_physics_process(true)
	_boss.set_process(true)
	var thresholds := kit.phase_thresholds()
	var index := mini(phase - 1, thresholds.size() - 1)
	var target := int(floor(float(health.max_hp) * float(thresholds[index])))
	var amount := health.current - target
	if amount > 0:
		health.take_damage(amount, _player)
	await _wait(0.1)
	# 相变演出是短慢动作：先等它播完再停 AI，取景才是相变后的画面。
	await _wait(0.35)
	Engine.time_scale = 1.0
	_boss.set_physics_process(false)
	_boss.set_process(false)


## 抓一次读招：等 Boss 自己起手（telegraph_started），落到预警中段。
func _capture_telegraph() -> void:
	await _clear_director()
	_place_player_instant(Vector2(_boss.global_position.x - 120.0, _boss.global_position.y - 20.0))
	_boss.set_physics_process(true)
	_boss.set_process(true)
	var seen := [false]
	var on_telegraph := func(_kind: StringName, _duration: float) -> void:
		seen[0] = true
	if _boss.has_signal("telegraph_started") and not _boss.is_connected("telegraph_started", on_telegraph):
		_boss.connect("telegraph_started", on_telegraph)
	var waited := 0
	while not seen[0] and waited < 300:
		await get_tree().physics_frame
		waited += 1
	if seen[0]:
		await _wait(0.2)
	_boss.set_physics_process(false)
	_boss.set_process(false)
	if _boss.has_signal("telegraph_started") and _boss.is_connected("telegraph_started", on_telegraph):
		_boss.disconnect("telegraph_started", on_telegraph)
	report["telegraph"] = {
		"seen": seen[0],
		"markers": CombatMarker.live,
	}


func _boss_has_telegraph() -> bool:
	return _boss.has_signal("telegraph_started")


# ---------------------------------------------------------------------------
# 摆位 / 取景
# ---------------------------------------------------------------------------
func _place_player(at: Vector2, enable_physics: bool) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	_player.health.invincible = true
	_player.set_physics_process(enable_physics)


func _place_player_instant(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	_player.health.invincible = true


func _settle() -> void:
	# 等章节卡 / 教学提示自己退，别盖住竞技场构图。
	await _wait(1.2)
	await _clear_director()
	# 先站远一点：Boss 不能在我们摆机位时先冲锋 / 开打。
	_place_player_instant(_boss.global_position + Vector2(-420.0, -20.0))


## 清掉正在播放 / 排队的章节剧本，直到输入交还（硬复位由切场 / 死亡负责）。
func _clear_director() -> void:
	var guard := 0
	while (Director.playing or Director.is_input_locked()) and guard < 8:
		if Director.playing:
			Director.skip_step()
		else:
			Director.abort()
		await get_tree().process_frame
		guard += 1
	Director.abort()
	await get_tree().process_frame


func _report_boss(_tag: String) -> void:
	if _boss == null or not is_instance_valid(_boss):
		_report_arena()
		return
	var health := _boss.get_node_or_null("Health") as Health
	var entry: Dictionary = report["boss"]
	entry["node"] = String(_boss.name)
	entry["position"] = _boss.global_position
	entry["hp"] = health.current if health != null else -1
	entry["max_hp"] = health.max_hp if health != null else -1
	if _boss.has_method("boss_kit"):
		var kit := _boss.call("boss_kit") as BossKit
		if kit != null:
			entry["title"] = kit.boss_title()
			entry["subtitle"] = kit.boss_subtitle()
			entry["max_phases"] = kit.max_phases()
			entry["attack_ids"] = kit.attack_pool().map(func(e: Dictionary) -> String: return String(e.id))
			entry["kit_problems"] = kit.validate()
	if _director != null and is_instance_valid(_director):
		entry["director"] = _director.schedule_snapshot()
	_report_arena()


func _report_arena() -> void:
	if _arena == null or not is_instance_valid(_arena):
		return
	var arena_entry: Dictionary = report["arena"]
	arena_entry["node"] = String(_arena.name)
	arena_entry["bounds"] = _arena.bounds
	arena_entry["active"] = _arena.is_active()
	arena_entry["cleared"] = _arena.is_cleared()
	arena_entry["gate_locked"] = _arena.gate_locked
	arena_entry["camera"] = _arena.has_saved_camera_limits


func _stage_record(row: Dictionary, kind: String) -> Dictionary:
	var health: Health = null
	if is_instance_valid(_boss):
		health = _boss.get_node_or_null("Health") as Health
	var record: Dictionary = {
		"id": String(row.id),
		"label": String(row.label),
		"kind": kind,
		"screen": String(row.screen),
		"hp": health.current if health != null else 0,
		"phase": _director.phase if _director != null and is_instance_valid(_director) else 1,
	}
	if _director != null and is_instance_valid(_director):
		record["enraged"] = _director.enraged
	return record


func _boss_announced() -> bool:
	if _boss == null or not is_instance_valid(_boss):
		return false
	if _boss.has_method("is_announced"):
		return bool(_boss.call("is_announced"))
	return false


func _capture(shot: String) -> void:
	if headless:
		shots.append("")
		return
	await RenderingServer.frame_post_draw
	var dir_abs := ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var path := dir_abs + "/boss_%s.png" % shot
	var save_error := get_viewport().get_texture().get_image().save_png(path)
	if save_error != OK:
		push_error("could not save " + path)
	shots.append(path)


func _wait(seconds: float) -> void:
	if get_tree() == null:
		return
	await get_tree().create_timer(maxf(seconds, 0.0)).timeout


func _wait_until(predicate: Callable, max_frames: int = 300) -> bool:
	for i in max_frames:
		if bool(predicate.call()):
			return true
		await get_tree().physics_frame
	return bool(predicate.call())


func _wait_director_idle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and (Director.playing or Director.is_fading()):
		await get_tree().process_frame


func _wait_world(frames: int) -> bool:
	for i in frames:
		await get_tree().process_frame
		var worlds := get_tree().get_nodes_in_group("game_world")
		if worlds.size() == 1 and get_tree().get_first_node_in_group("player") != null:
			return true
	return false
