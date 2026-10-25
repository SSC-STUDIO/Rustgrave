extends Node
## Acceptance driver: normal input only. Never moves actors, gives items,
## damages enemies, opens gates, or emits gameplay milestones.
const ERROR_COLLECTOR := preload("res://tests/error_collector.gd")
const TITLE := "res://scenes/ui/TitleScreen.tscn"
const HAZARD_POLICY := preload("res://tools/campaign_hazard_policy.gd")
var _errors
var _ending := "rekindle"
var _step := "startup"
var _started := 0
var _failed := false
var _last_skip := 0
var _deaths := 0
var _records: Array[Dictionary] = []
var _jump_hold := 0
var _jump_cd := 0
var _dash_cd := 0
var _rendered := false
var _frame_ms: Array[float] = []
var _last_frame_usec := 0
var _campaign := false
var _basic_abilities := false
var _skip_captions := true
var _hazard_wait_frames := 0
## --shots: save a PNG at every milestone plus opening / combat / boss beats into
## user://shots/. --window=WxH sizes the real window; --onscreen puts it on the desktop
## (decorated, at 40,40) instead of the off-screen borderless default.
var _shots := false
var _window := Vector2i(1920, 1080)
var _onscreen := false
var _shot_done: Dictionary = {}
var _beat_started := 0
var _beat_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rendered = DisplayServer.get_name() != "headless"
	for arg in OS.get_cmdline_user_args():
		if arg == "--shots": _shots = true
		elif arg == "--onscreen": _onscreen = true
		elif arg.begins_with("--window="):
			var wh := arg.trim_prefix("--window=").split("x")
			if wh.size() == 2: _window = Vector2i(int(wh[0]), int(wh[1]))
	if _rendered:
		get_tree().root.mode = Window.MODE_WINDOWED
		get_tree().root.borderless = not _onscreen
		get_tree().root.size = _window
		get_tree().root.position = Vector2i(40, 40) if _onscreen else Vector2i(-12000, -12000)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 60
	_errors = ERROR_COLLECTOR.new()
	OS.add_logger(_errors)
	_started = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ending="):
			_ending = arg.trim_prefix("--ending=")
		elif arg == "--campaign": _campaign = true
		elif arg == "--basic-abilities": _basic_abilities = true
		elif arg == "--fast": Engine.max_fps = 0
	SaveData.save_path = "user://input_walkthrough_%s.cfg" % _ending
	GameEvents.player_died.connect(func() -> void: _deaths += 1)
	# Keep the driver beside the real current scene while all normal scene
	# transitions (title, world, death, ending) execute unmodified.
	get_tree().current_scene = null
	call_deferred("_run")


func _recording() -> bool:
	for arg in OS.get_cmdline_args():
		if str(arg).begins_with("--write-movie"):
			return true
	return false


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _rendered and _last_frame_usec > 0 and GameContext.gameplay_input_enabled() and _player() != null:
		_frame_ms.append(float(now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now
	if _failed:
		return
	# 录像时每帧都要编码，墙钟会比平时长。给全程通关四小时，避免录到一半被掐掉。
	var budget := 240000
	if _campaign:
		budget = 14400000 if _recording() else 1800000
	if Time.get_ticks_msec() - _started > budget:
		_fail("walkthrough exceeded its time budget")
	if not _errors.errors().is_empty():
		_fail("engine error: " + _errors.errors()[0])
	var now_ms := Time.get_ticks_msec()
	if not Director.playing:
		_beat_started = 0
	elif _beat_started == 0:
		_beat_started = now_ms
		_beat_count += 1
	# --shots: let every story beat play for a moment and photograph it before skipping.
	var beat_age := now_ms - _beat_started if _beat_started > 0 else 0
	if _shots and _skip_captions and Director.playing and beat_age > 1300:
		_shot("beat_%02d" % _beat_count)
	var may_skip := not _shots or beat_age > 2600
	if _skip_captions and may_skip and Director.playing and not get_tree().paused and now_ms - _last_skip > 180:
		_last_skip = now_ms
		_ui(&"ui_accept")


func _run() -> void:
	get_tree().change_scene_to_file(TITLE)
	await _frames(12)
	if _shots:
		await _frames(90)
		_shot("00_title")
		_skip_captions = false
	_ui(&"ui_accept") # title: new game (opens the character select since the loadout screen landed)
	await _embark_default_origin()
	if _shots:
		await _watch_opening()
	if not await _wait_world():
		return
	_record("new_game")
	if not await _walk_to(150.0, false): return
	await _tap(&"interact")
	if not _require(not SaveData.lit_nests.is_empty(), "nest was lit through E"): return
	_record("checkpoint")
	if not await _walk_to(244.0, true): return
	if not _require(_player().position.y < 290.0, "tutorial terrace reached by jump"): return
	_record("tutorial_terrace")
	if not await _walk_to(352.0, true): return
	await _tap(&"interact")
	if not await _walk_to(566.0, true): return
	_record("toxin_pit_escape")
	if not await _walk_to(650.0, true): return
	if not await _walk_to(734.0, true): return
	if not await _walk_to(790.0, true): return
	if not await _fight_spitter(): return
	if not await _walk_to(812.0, true): return
	if not _basic_abilities:
		# Combat knockback can leave the knight past the drop; walk back to where it
		# actually lies and press E again (still normal input, at most three tries).
		for attempt in 3:
			await _tap(&"interact")
			if not await _wait_world(): return
			if _owns_core(&"tether_core"):
				break
			var drop := _tether_drop()
			if drop == null:
				break
			if not await _walk_to(drop.global_position.x, false): return
		await _tap(&"socket_1")
		if not await _wait_world(): return
		if not _require(_player().inventory.has_ability(AbilityIds.HOOKSHOT_TETHER), "spitter tether drop equipped"): return
		_record("spitter_tether")
	# --- ① 压板偏殿：上层路 → 楼座 → 塌陷锈梁 → 压板（在楼座上），落回地穴巷 ---
	# 死了会重载场景：每一步都重新取世界根，不留指向旧场景的引用。
	var plate := _world_root().get_node("Props/PressurePlate") as Node2D
	if not await _nv_navigate(LevelSanity.feet_of(plate)): return
	await _frames(20)
	if not _require(_world_root().get_node("Props/Door").is_open, "pressure plate opened door"): return
	_record("pressure_plate")
	# --- ② 锻核工坊：穿过伏击巷与压板门，废料堆里的窑核 → 嵌核台 ---
	if not await _collect_kiln(): return
	_record("kiln_socket")
	# 休息龛的巢（炉廊前的存档点）：点亮它，炉廊里死了回这里。
	if not await _light_nest("EmberNestForge"): return
	_record("forge_checkpoint")
	# 炉廊（三口错相炉口，机关感知）→ 锈门
	var gate := _world_root().get_node("Props/RustyGate") as Node2D
	var gate_feet := LevelSanity.feet_of(gate)
	if not await _nv_navigate(Vector2(gate_feet.x - 28.0, gate_feet.y)): return
	await _tap(&"interact")
	await _frames(4)
	if not _require(not is_instance_valid(_world_root().get_node_or_null("Props/RustyGate")), "rust gate melted through E"): return
	_record("rust_gate")
	if not _basic_abilities:
		# 余烬阁（可选，钩锁）：回到炉廊西头的发射点，跳起来甩钩。
		if not await _nv_navigate(Vector2(Level01EastWing.EMBER_HOOK_POS.x - 82.0, 320.0)): return
		if not await _grapple_ember(): return
		_record("grapple_ember")
	# --- ③ 中殿长阶 → BossGate 前的巢 ---
	var nest_feet := LevelSanity.feet_of(_world_root().get_node("Props/EmberNestEast"))
	if not await _nv_navigate(nest_feet): return
	# Let contact queries and any introductory lock settle before interacting.
	for attempt in 4:
		if SaveData.last_lit_nest().ends_with("EmberNestEast"): break
		if not await _wait_world(): return
		if not await _nv_navigate(nest_feet): return
		await _frames(8)
		print("[CHECKPOINT] attempt=%d player=%s focus=%s" % [attempt, _player().position, _player().sensor.get_focus()])
		await _tap(&"interact")
	if not _require(SaveData.last_lit_nest().ends_with("EmberNestEast"), "east checkpoint is reachable"): return
	_record("east_checkpoint")
	# --- ④ 炉厅竞技场：刽子手在石台上，炉龛喷火口只在战斗里转 ---
	# Hand control to the combat driver at the arena's near side. Navigation must
	# not demand a precise point behind a live shield-bearing boss first.
	if not await _nv_navigate(Vector2(Level01EastWing.ARENA_CENTER_X - 80.0, Level01EastWing.STAGE_Y)): return
	if not await _fight_boss(): return
	_record("boss_slain")
	if not await _verify_progress_reload(): return
	var heart_feet := LevelSanity.feet_of(_world_root().get_node("Props/ForgeHeart"))
	if not await _nv_navigate(Vector2(heart_feet.x, heart_feet.y - 4.0)): return
	await _tap(&"interact")
	await _frames(8)
	if not _require(Director.choice_hold, "real heart choice opened"): return
	if _ending == "snuff":
		_ui(&"ui_down")
		await _frames(2)
	_ui(&"ui_accept")
	if _ending == "rekindle":
		# 复燃不回标题：陵墓醒来，骑士落进第二关。走到第一个存档点、过第一段毒水。
		if not await _descend_into_undercroft(): return
		if not await _after_undercroft(): return
		print("[WALKTHROUGH PASS] %s; %d deaths; normal input only" % [_ending, _deaths])
		_write_result(true)
		get_tree().quit(0)
		return
	for i in 600:
		await _frames(1)
		# 结局分镜每帧面板需要按一次确认才推进（skip_all_on_accept=false）。
		# 不点就会永远停在第一格的 HOLD 上。
		if Director.playing and i % 30 == 0:
			_ui(&"ui_accept")
		var current := get_tree().current_scene
		if i % 120 == 0:
			print("[ENDING] i=%d playing=%s hold=%s fading=%s scene=%s" % [
				i, Director.playing, Director.choice_hold, Director.is_fading(),
				current.scene_file_path if current != null else "null"])
		if current != null and current.scene_file_path == TITLE:
			if not _require(SaveData.peek_ending() == _ending, "ending persists on title"): return
			_record("ending_" + _ending)
			print("[WALKTHROUGH PASS] %s; %d deaths; normal input only" % [_ending, _deaths])
			_write_result(true)
			get_tree().quit(0)
			return
	_fail("ending did not return to title")


## 「点燃余烬」之后是选人界面：焦点默认在「启程」，再按一次确认键就带默认出身出发
## （正常输入，和玩家一样）。没有选人界面的旧标题（回退版）直接跳过。
func _embark_default_origin() -> void:
	for i in 120:
		await _frames(1)
		var title := get_tree().current_scene
		if title == null or not title.has_method("character_select_screen"):
			return
		var select = title.character_select_screen()
		if select != null and select.is_open():
			await _frames(6)
			_ui(&"ui_accept")
			return


## Watch the opening without skipping it; grab frames at fixed beats. Ends when the
## Director hands control back, then later captions are skipped as before.
func _watch_opening() -> void:
	var beats := [0.6, 2.4, 4.6, 7.0, 9.4, 11.6, 13.2]
	var t0 := Time.get_ticks_msec()
	var next := 0
	for i in 1500:
		await _frames(1)
		var t := float(Time.get_ticks_msec() - t0) / 1000.0
		if next < beats.size() and t >= beats[next]:
			_shot("01_opening_%02d" % next)
			next += 1
		if t > 2.0 and not Director.playing and _player() != null and GameContext.gameplay_input_enabled():
			break
	await _frames(20)
	_shot("02_first_control")
	_skip_captions = true


func _shot(name_: String) -> void:
	if not _shots or not _rendered or _shot_done.has(name_):
		return
	_shot_done[name_] = true
	DirAccess.make_dir_recursive_absolute("user://shots")
	get_tree().root.get_texture().get_image().save_png("user://shots/%dx%d_%s.png" % [_window.x, _window.y, name_])
	_last_frame_usec = Time.get_ticks_usec()


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _after_undercroft() -> bool:
	return true


func _descend_into_undercroft() -> bool:
	_step = "descend_level02"
	var arrived := false
	for i in 900:
		await _frames(1)
		var player := _player()
		if player != null and player.health.current > 0 \
				and GameContext.world_scene_path(player) == GameContext.LEVEL02_PATH \
				and GameContext.gameplay_input_enabled():
			arrived = true
			break
	if not _require(arrived, "rekindle drops the knight into Level02"): return false
	_record("descend_level02")
	for i in 120:
		if _player().is_on_floor():
			break
		await _frames(1)
	if not _require(_player().is_on_floor() and absf(_player().position.y - 320.0) < 2.0, "knight lands on FloorA"): return false
	if not await _walk_to(176.0, false): return false
	await _tap(&"interact")
	if not _require(SaveData.last_lit_nest() == "level02:Props/EmberNestShaft", "undercroft checkpoint lit under its namespace"): return false
	_record("undercroft_checkpoint")
	if not await _walk_to(430.0, false): return false
	if not await _walk_to(760.0, true): return false
	if not _require(absf(_player().position.y - 320.0) < 2.0, "knight stands on FloorB after the toxin pit"): return false
	_record("undercroft_pit_crossed")
	# Save/continue round trip: pause → title → continue must come back here.
	if not await _pause_return_to_title(): 
		_fail("pause menu did not return to title from Level02")
		return false
	await _frames(6)
	await _title_continue()
	if not await _wait_world(): return false
	var player_after := _player()
	if not _require(GameContext.world_scene_path(player_after) == GameContext.LEVEL02_PATH, "continue reopens Level02"): return false
	if not _require(absf(player_after.position.x - 176.0) < 12.0, "continue restores the undercroft checkpoint"): return false
	_record("undercroft_continue_verified")
	return true


func _wait_world() -> bool:
	for i in 600:
		await _frames(1)
		var player := _player()
		if player != null and player.health.current > 0 and GameContext.gameplay_input_enabled():
			return true
	var cur := get_tree().current_scene
	var plr := _player()
	_fail("world did not become playable (scene=%s player=%s hp=%s playing=%s locked=%s input=%s)" % [
			cur.scene_file_path if cur != null else "null", plr != null,
			plr.health.current if plr != null else -1, Director.playing, Director.is_input_locked(),
			GameContext.gameplay_input_enabled()])
	return false


## 标题菜单：有存档时光标默认停在「继续」（scripts/ui/title_screen.gd:216-218），
## 所以不能再按一次 ↓ —— 那会把光标落到「设置」上，世界永远不加载。
## 只有没有存档（不可能走 Continue）时才需要 ↓。返回时确认键已按下。
func _title_continue() -> void:
	if not SaveData.has_save():
		_ui(&"ui_down")
		await _frames(3)
	_ui(&"ui_accept")


func _walk_to(target_x: float, jump: bool) -> bool:
	_step = "walk_to_%.0f" % target_x
	for i in 3600:
		var player := _player()
		if player == null or player.health.current <= 0 or not GameContext.gameplay_input_enabled():
			_release()
			await _frames(1)
			continue
		var dx := target_x - player.global_position.x
		if absf(dx) < 5.0 and player.is_on_floor():
			_release()
			await _frames(12)
			return true
		_move(signf(dx) if absf(dx) > 3.0 else 0.0)
		_jump_cd = maxi(0, _jump_cd - 1)
		_jump_hold = maxi(0, _jump_hold - 1)
		var need_jump := jump or (target_x > 600.0 and player.global_position.x < 780.0) \
				or (player.is_on_wall() and player.is_on_floor())
		if need_jump and player.is_on_floor() and _jump_cd == 0 and absf(dx) > 24.0:
			_jump_hold = 20
			_jump_cd = 32
		_set_action(&"jump", _jump_hold > 0)
		_dash_cd = maxi(0, _dash_cd - 1)
		var dash := false
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy is EnemyBase and enemy._mobile and absf(enemy.global_position.y - player.global_position.y) < 30.0 \
					and absf(enemy.global_position.x - player.global_position.x) < 40.0 and _dash_cd == 0:
				dash = true
				_dash_cd = 32
		if _dash_cd == 0 and player.is_on_floor() and player.position.x > 850.0:
			for effect in GameContext.world_effects(player).get_children():
				if effect is Projectile and effect.team == &"enemy":
					var future: Vector2 = effect.global_position + effect.velocity * 0.08
					if future.distance_to(player.global_position + Vector2(0, -14)) < 23.0:
						dash = true
						_dash_cd = 26
		_set_action(&"dash", dash)
		if i % 180 == 0:
			print("[WALK] %s position=%s hp=%d" % [_step, player.global_position, player.health.current])
		await _frames(1)
	_release()
	_fail("could not reach target; position=" + str(_player().global_position if _player() else Vector2.INF))
	return false


func _fight_boss() -> bool:
	_step = "boss_combat"
	var attack_cd := 0
	var fighter_id := _player().get_instance_id()
	for i in 3600:
		if SaveData.has_flag("boss_dead"):
			_release()
			await _frames(90)
			return true
		var player := _player()
		if player == null or player.health.current <= 0 or not GameContext.gameplay_input_enabled():
			_release()
			await _frames(1)
			continue
		if player.get_instance_id() != fighter_id:
			fighter_id = player.get_instance_id()
			# 死了回 BossGate 前的巢：长阶 + 石台 + 掩体墩都要走回去（不传送，不跳关）。
			if not await _nv_navigate(Vector2(Level01EastWing.ARENA_CENTER_X - 80.0, Level01EastWing.STAGE_Y)): return false
			continue
		var boss: ExecutionerBoss = null
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy is ExecutionerBoss:
				boss = enemy
				break
		if boss == null:
			_fail("boss missing without a defeat flag")
			return false
		var dx := boss.global_position.x + 26.0 - player.global_position.x
		if absf(dx) > 6.0:
			_move(signf(dx))
		else:
			_move(-1.0 if player.controller.facing != -1 else 0.0)
		_set_action(&"dash", player.global_position.x < boss.global_position.x and i % 30 == 0)
		# 石台边（16px）与掩体墩（32px）挡路时按住跳过去，和玩家一样。
		_jump_cd = maxi(0, _jump_cd - 1)
		_jump_hold = maxi(0, _jump_hold - 1)
		if player.is_on_wall() and player.is_on_floor() and _jump_cd == 0:
			_jump_hold = 20
			_jump_cd = 32
		_set_action(&"jump", _jump_hold > 0)
		attack_cd = maxi(0, attack_cd - 1)
		var attack := absf(player.global_position.x - boss.global_position.x) < 38.0 \
				and player.controller.facing == -1 and attack_cd == 0
		_set_action(&"attack", attack)
		if attack: attack_cd = 24
		if boss.is_announced() and not _shot_done.has("04_boss_intro"):
			_shot("04_boss_intro")
		if boss.health.current < boss.health.max_hp and boss.health.current > boss.health.max_hp / 2:
			_shot("05_boss_fight")
		if boss.is_enraged():
			_shot("06_boss_phase2")
		if i % 180 == 0:
			print("[FIGHT] player=%s hp=%d boss=%s hp=%d" % [player.global_position, player.health.current, boss.global_position, boss.health.current])
		await _frames(1)
	_release()
	_fail("boss fight timed out")
	return false


func _fight_spitter() -> bool:
	_step = "spitter_combat"
	for i in 600:
		var player := _player()
		if player == null or player.health.current <= 0:
			_fail("died before tether acquisition")
			return false
		var spitter := GameContext.world_root(player).get_node_or_null("Props/Spitter1") as SpitterEnemy
		if spitter == null:
			_release()
			await _frames(8)
			return true
		var dx := spitter.position.x - player.position.x
		var face := signf(dx)
		_move(face if absf(dx) > 28.0 or player.controller.facing != int(face) else 0.0)
		# The spitter is intentionally placed on the first combat platform. Reach
		# it with the same jump input a player uses, then keep melee pressure.
		_jump_cd = maxi(0, _jump_cd - 1)
		_jump_hold = maxi(0, _jump_hold - 1)
		if player.is_on_floor() and _jump_cd == 0 and absf(dx) < 90.0:
			_jump_hold = 16
			_jump_cd = 34
		_set_action(&"jump", _jump_hold > 0)
		_dash_cd = maxi(0, _dash_cd - 1)
		var evade := false
		if _dash_cd == 0:
			for effect in GameContext.world_effects(player).get_children():
				if effect is Projectile and effect.team == &"enemy":
					var future: Vector2 = effect.global_position + effect.velocity * 0.10
					if future.distance_to(player.global_position + Vector2(0, -14)) < 28.0:
						evade = true
						_dash_cd = 30
		_set_action(&"dash", evade)
		_set_action(&"attack", absf(dx) < 42.0 and absf(player.global_position.y - spitter.global_position.y) < 58.0 and i % 24 == 0)
		if i == 50 or i == 90:
			_shot("03_combat_spitter_%d" % i)
		if i % 120 == 0:
			print("[SPITTER] player=%s hp=%d spitter=%s hp=%d" % [player.position, player.health.current, spitter.position, spitter.health.current])
		await _frames(1)
	_fail("spitter could not be defeated with normal melee")
	return false


func _owns_core(core_id: StringName) -> bool:
	var player := _player()
	if player == null:
		return false
	for core in player.inventory.pouch + player.inventory.sockets:
		if core != null and (core as RustCore).id == core_id:
			return true
	return false


func _tether_drop() -> Node2D:
	for node in get_tree().get_nodes_in_group("persistent"):
		if node is CorePickup and String(node.name).begins_with("TetherDrop_") and not node.is_queued_for_deletion():
			return node as Node2D
	return null


func _collect_kiln() -> bool:
	for attempt in 5:
		if not await _wait_world(): return false
		var player := _player()
		if player.inventory.has_ability(AbilityIds.HEAT_FORGE): return true
		var in_pouch := false
		for core in player.inventory.pouch:
			if core.id == &"kiln_core": in_pouch = true
		if in_pouch:
			await _tap(&"socket_2")
			if not await _wait_world(): return false
			continue
		var scrap := _world_root().get_node_or_null("Props/ScrapPile") as Node2D
		if scrap == null:
			_fail("scrap pile is missing")
			return false
		if not await _nv_navigate(LevelSanity.feet_of(scrap)): return false
		await _tap(&"interact")
		if not await _wait_world(): return false
	_fail("kiln core could not be collected and socketed")
	return false


## 点亮一个余烬巢（正常输入：走到巢边按 E）。
func _light_nest(nest_name: String) -> bool:
	var nest := _world_root().get_node_or_null("Props/" + nest_name) as Node2D
	if nest == null:
		_fail("nest %s is missing" % nest_name)
		return false
	for attempt in 4:
		if SaveData.last_lit_nest().ends_with(nest_name):
			return true
		if not await _wait_world(): return false
		if not await _nv_navigate(LevelSanity.feet_of(nest)): return false
		await _frames(8)
		await _tap(&"interact")
	return _require(SaveData.last_lit_nest().ends_with(nest_name), "nest %s lit through E" % nest_name)


func _verify_progress_reload() -> bool:
	_step = "boss_death_reload"
	var old_id := _player().get_instance_id()
	# Walk back into the hostile courtyard and allow ordinary enemy damage.
	# This never calls damage, respawn, load, or any story completion hook.
	# 回炉廊，站进最近那口炉口里让「普通机关伤害」把骑士送回巢（不调用 damage / respawn）。
	var vent := _world_root().get_node_or_null("Props/FlameVent3") as Node2D
	var vent_x := vent.global_position.x if vent != null else 2464.0
	for i in 5400:
		var player := _player()
		if player != null and player.get_instance_id() != old_id and player.health.current > 0 \
				and GameContext.gameplay_input_enabled():
			_release()
			if not _check_restored_progress(): return false
			_record("boss_death_reload_verified")
			break
		if player != null and player.health.current > 0 and GameContext.gameplay_input_enabled():
			var gap := vent_x - player.position.x
			_move(signf(gap) if absf(gap) > 3.0 else 0.0)
			# 石台边 / 掩体墩 / 长阶挡路时按住跳（和 _walk_to 同一套保持计数：松键太早跳不过 32px）。
			_jump_cd = maxi(0, _jump_cd - 1)
			_jump_hold = maxi(0, _jump_hold - 1)
			if player.is_on_wall() and player.is_on_floor() and _jump_cd == 0:
				_jump_hold = 20
				_jump_cd = 32
			_set_action(&"jump", _jump_hold > 0)
		else:
			_release()
		await _frames(1)
		if i % 600 == 0:
			var plr := _player()
			print("[RELOAD] i=%d player=%s hp=%s vent_x=%.0f" % [i, plr.position if plr != null else Vector2.INF,
					plr.health.current if plr != null else -1, vent_x])
		if i == 5399:
			_fail("hazard damage did not complete a checkpoint reload")
			return false
	if not await _pause_return_to_title():
		_fail("pause menu did not return to title")
		return false
	await _frames(6)
	await _title_continue()
	if not await _wait_world(): return false
	# Continue restores the saved interaction position; death uses the
	# nest's respawn point. Momentum may put those a few pixels apart.
	if not _check_restored_progress((SaveData.data["player"]["pos"] as Vector2).x): return false
	_record("continue_verified")
	return true


## 暂停 → 返回标题。
## 死亡重载后还会有一小段场景淡变：PauseMenu 在淡变期间只记下请求（不立即暂停），
## 而紧接着再按一次 Esc 会把该请求收回。所以这里先等淡变结束（玩家等半秒再按），
## 再发送真实的 ui_cancel/ui_up/ui_accept；重试时同样等状态，不盲目连按。
func _pause_return_to_title() -> bool:
	for attempt in 4:
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == TITLE:
			return true
		for _i in 240:
			if not Director.is_fading() or get_tree().paused:
				break
			await _frames(1)
		_ui(&"ui_cancel")
		await _frames(8)
		var paused := get_tree().paused
		var pause := _find_pause()
		print("[PAUSE] attempt=%d paused=%s scene=%s fading=%s playing=%s locked=%s hold=%s open=%s"
				% [attempt, paused,
				get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "null",
				Director.is_fading(), Director.playing, Director.is_input_locked(),
				Director.choice_hold, pause != null and pause.is_open()])
		if not paused:
			await _frames(30)
			continue
		_ui(&"ui_up")
		await _frames(6)
		_ui(&"ui_accept")
		for i in 300:
			await _frames(1)
			if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == TITLE:
				return true
		if get_tree().paused:
			# 没退出：把菜单关掉，下一轮重新来。
			_ui(&"ui_cancel")
			await _frames(8)
	return false


func _find_pause() -> PauseMenu:
	var host := GameContext.ui_host(_player())
	if host == null:
		return null
	for node in host.find_children("*", "", true, false):
		if node is PauseMenu:
			return node
	return null


func _check_restored_progress(expected_x: float = Level01EastWing.EMBER_NEST_EAST_POS.x) -> bool:
	var player := _player()
	var world := GameContext.world_root(player)
	return _require(absf(player.position.x - expected_x) < 12.0, "reload preserves east nest checkpoint") \
		and _require(_basic_abilities or player.inventory.has_ability(AbilityIds.HOOKSHOT_TETHER), "tether survives reload") \
		and _require(_basic_abilities or player.inventory.has_ability(AbilityIds.EMBER_STEP), "ember step survives reload") \
		and _require(_basic_abilities or SaveData.is_consumed("Pickups/EmberCore"), "ember pickup record survives") \
		and _require(SaveData.is_consumed("Props/RustyGate"), "melted gate record survives") \
		and _require(world.get_node_or_null("Props/RustyGate") == null, "melted gate stays absent") \
		and _require(world.get_node("Props/Door").is_open, "pressure plate door stays open") \
		and _require(SaveData.has_flag("boss_dead"), "boss stays defeated") \
		and _require(world.get_node("Props/ForgeHeart").unlocked, "forge stays unlocked")


func _grapple_ember() -> bool:
	_step = "grapple_ember"
	_move(1.0)
	await _frames(1)
	_move(0.0)
	_set_action(&"jump", true)
	await _frames(12)
	_set_action(&"jump", false)
	await _tap(&"hookshot")
	for i in 300:
		var player := _player()
		var dx := Level01EastWing.EMBER_CORE_POS.x - player.position.x
		_move(signf(dx) if absf(dx) > 4.0 else 0.0)
		if i % 30 == 0:
			print("[HOOK] position=%s active=%s" % [player.position, player.hookshot.is_active()])
		if player.position.y < Level01EastWing.EMBER_LEDGE_POS.y + 13.0 and player.is_on_floor() and absf(dx) < 18.0:
			_release()
			await _tap(&"interact")
			await _frames(15)
			# The first-core pickup stages a short beat; socket once control is back.
			if not await _wait_world(): return false
			await _tap(&"socket_2")
			await _frames(8)
			return _require(player.inventory.has_ability(AbilityIds.EMBER_STEP), "ember core equipped from real ledge")
		await _frames(1)
	_fail("grapple did not reach the ember ledge")
	return false


# --- 几何导航（第一章东半：多层楼座 / 塌陷梁 / 炉口） --------------------------------------
## 读 LevelSanity 的台面表选落脚点、只发正常输入（不挪人、不开门、不改状态）。
## 机关感知：走进炉口判定区之前先看 CyclicHazard.safe_window()，等它喷完再过；
## 塌陷梁只当一块「踩上就走」的踏台，不停留（落下去就重新规划）。
## 算法与 campaign_walkthrough 的 _navigate 同源（那边服务第 2–10 章），这里用 _nv_ 前缀
## 自成一套，campaign 子类里的同名方法不会覆盖它。
var _nv_tick := 0
## 这次导航的终点：从一块台子落到一整条长地面上时，选朝着终点那一侧的台缘走下去。
var _nv_goal := Vector2.INF
## 本关的周期机关（每次导航开头重取一次：死了会重载场景，旧引用作废）。
var _nv_vents: Array[Node2D] = []


func _world_root() -> Node:
	return GameContext.world_root(_player())


## Closed pressure gates are real walls even though LevelSanity's static
## terrain table intentionally omits interactables. Read their live state.
func _nv_solids() -> Array[Rect2]:
	var world := _world_root()
	var solids := LevelSanity.solid_rects(world)
	for node in world.find_children("*", "", true, false):
		if node is ArenaDoor and not node.is_open:
			solids.append(Rect2(node.global_position, Vector2(16.0, 64.0)))
		elif node is BreakableTerrain or node is DestructibleProp:
			# Optional rubble is still a physical wall until its real chunks break.
			# Read only the body's direct shapes, excluding the damage Hurtbox.
			for child in node.get_children():
				if child is CollisionShape2D and not child.disabled and child.shape is RectangleShape2D:
					var size_: Vector2 = child.shape.size
					solids.append(Rect2(child.global_position - size_ * 0.5, size_))
	return solids


func _nv_tops() -> Array[LevelSanity.TopSeg]:
	var tops := LevelSanity.top_segments(_world_root())
	# Decorative caches are real bodies too. Read their live collision tops so
	# a jump landing on an intact cache can replan from that actual support.
	for node in _world_root().find_children("*", "", true, false):
		if not node is DestructibleProp and not node is BreakableTerrain: continue
		for child in node.get_children():
			if child is CollisionShape2D and not child.disabled and child.shape is RectangleShape2D:
				var size_: Vector2 = child.shape.size
				var corner: Vector2 = child.global_position - size_ * 0.5
				if size_.x >= 16.0:
					tops.append(LevelSanity.TopSeg.new(corner.x, corner.x + size_.x, corner.y, String(node.name), "prop"))
	return tops


func _nv_clear_approach(feet: Vector2, direction: float) -> Vector2:
	var solids := _nv_solids()
	var tops := _nv_tops()
	for offset in range(0, 81, 8):
		var candidate := feet + Vector2(direction * offset, 0)
		var body := Rect2(candidate - Vector2(7, 26), Vector2(14, 26))
		var clear := LevelSanity.standing_on(tops, candidate, 3.0, 3.0) != null
		for solid in solids:
			if solid.grow(-0.5).intersects(body):
				clear = false
				break
		if clear: return candidate
	return feet


func _nv_segments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var world := _world_root()
	var solids := _nv_solids()
	for top in _nv_tops():
		var name_ := top.owner_name.get_slice("@", 0)
		var lift := world.get_node_or_null("Platforms/" + name_) as MovingPlatform
		if lift != null:
			out.append({"r": Rect2(top.x0, top.y, top.x1 - top.x0, 16), "lift": lift, "end": top.owner_name.ends_with("@end")})
			continue
		var spans: Array[Vector2] = [Vector2(top.x0, top.x1)]
		for r in solids:
			if r.position.y >= top.y - 3 or r.end.y < top.y - 26: continue
			var pieces: Array[Vector2] = []
			for span in spans:
				if r.position.x >= span.y or r.end.x <= span.x: pieces.append(span)
				else:
					if r.position.x - span.x >= 16: pieces.append(Vector2(span.x, r.position.x))
					if span.y - r.end.x >= 16: pieces.append(Vector2(r.end.x, span.y))
			spans = pieces
		for span in spans:
			if span.y - span.x >= (16 if top.kind == "prop" else 24):
				out.append({"r": Rect2(span.x, top.y, span.y - span.x, 16), "lift": null, "name": top.owner_name})
	for segment in out:
		segment.wet = false
		for prop in world.get_node("Props").get_children():
			if prop is ToxinPool:
				var pool: Rect2 = prop.surface_rect()
				var r: Rect2 = segment.r
				if r.position.y > pool.position.y and r.position.x < pool.end.x and r.end.x > pool.position.x: segment.wet = true
	return out


func _nv_closest(segments: Array[Dictionary], feet: Vector2) -> int:
	var best := -1
	var score := INF
	for i in segments.size():
		var r: Rect2 = segments[i].r
		var value := absf(feet.y - r.position.y) * 4 + absf(feet.x - clampf(feet.x, r.position.x, r.end.x))
		if value < score:
			score = value
			best = i
	return best


func _nv_link(a: Dictionary, b: Dictionary, solids: Array[Rect2] = []) -> bool:
	if a.lift != null and a.lift == b.lift: return true
	var ar: Rect2 = a.r
	var br: Rect2 = b.r
	var at := LevelSanity.TopSeg.new(ar.position.x, ar.end.x, ar.position.y, "a")
	var bt := LevelSanity.TopSeg.new(br.position.x, br.end.x, br.position.y, "b")
	if not LevelSanity._can_hop(at, bt): return false
	var gap := maxf(0.0, maxf(br.position.x - ar.end.x, ar.position.x - br.end.x))
	if b.lift == null and gap <= 0.0 and br.position.y > ar.position.y + 8.0:
		if not _nv_drop_side_clear(ar, br, true) and not _nv_drop_side_clear(ar, br, false):
			return false
	var x0 := minf(ar.end.x, br.end.x)
	var x1 := maxf(ar.position.x, br.position.x)
	if x1 > x0:
		for r in (_nv_solids() if solids.is_empty() else solids):
			# A lower stair in the gap catches a descending body before the
			# distant floor. Visit that landing instead of claiming a direct drop.
			if br.position.y > ar.position.y + 8.0 and r.position.y > ar.position.y + 0.5 \
					and r.position.y < br.position.y - 0.5 and r.position.x < x1 and r.end.x > x0 \
					and (r.position.x >= ar.end.x - 0.5 or r.end.x <= ar.position.x + 0.5):
				return false
			# Walk over an actual connecting floor before climbing its stair.
			# Skipping that floor invents a gap and an unnecessary airborne dash,
			# which can overshoot a narrow landing after a conveyor run-up.
			if br.position.y < ar.position.y - 8.0 and absf(r.position.y - ar.position.y) < 1.0 \
					and r.position.x <= x0 + 0.5 and r.end.x >= x1 - 0.5:
				return false
			if r.position.x < x1 and r.end.x > x0 and r.position.y < ar.position.y - 3 and r.end.y > minf(ar.position.y, br.position.y) - 24:
				return false
	return true


func _nv_route_cost(a: Dictionary, b: Dictionary) -> float:
	var ar: Rect2 = a.r
	var br: Rect2 = b.r
	var gap := maxf(0.0, maxf(br.position.x - ar.end.x, ar.position.x - br.end.x))
	# Equal hop counts must not prefer a narrow uphill dash over the broad
	# recoverable floor underneath it. Keep physical effort in the route cost.
	return 10.0 + (200.0 if b.wet else 0.0) + gap / 16.0 \
			+ maxf(0.0, ar.position.y - br.position.y) / 16.0 \
			+ 24.0 / maxf(24.0, br.size.x)


func _nv_path(segments: Array[Dictionary], feet: Vector2) -> Array[Dictionary]:
	# No physics advances during graph search; use one live obstacle snapshot.
	var solids := _nv_solids()
	var start := _nv_closest(segments, _player().position)
	var goal := _nv_closest(segments, feet)
	var parents := {start: -1}
	var costs := {start: 0.0}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		queue.sort_custom(func(a: int, b: int) -> bool: return costs[a] < costs[b])
		var at: int = queue.pop_front()
		if at == goal: break
		for i in segments.size():
			var cost: float = costs[at] + _nv_route_cost(segments[at], segments[i])
			if (not costs.has(i) or cost < costs[i]) and _nv_link(segments[at], segments[i], solids):
				parents[i] = at
				costs[i] = cost
				if not i in queue: queue.append(i)
	if not parents.has(goal): return []
	var route: Array[Dictionary] = []
	while goal >= 0:
		route.push_front(segments[goal])
		goal = parents[goal]
	return route


func _nv_plate_open_at(feet: Vector2) -> bool:
	for plate in _world_root().get_node("Props").get_children():
		if not plate is PressurePlate or LevelSanity.feet_of(plate).distance_to(feet) > 4: continue
		for connection in plate.activated.get_connections():
			var door = connection.callable.get_object()
			if door is ArenaDoor and door.is_open: return true
	return false


## 走到 feet（脚点）。目标在一扇还关着的压板门后面时，先去踩那块压板（正常输入）。
func _nv_navigate(feet: Vector2, restore_plates: bool = true) -> bool:
	_step = "route_to_" + str(feet)
	_nv_goal = feet
	for attempt in 30:
		_release()
		for i in 180:
			await _frames(1)
			if _player() != null and _player().health.current > 0 and _player().is_on_floor() and GameContext.gameplay_input_enabled(): break
		if _player() == null or _player().health.current <= 0: continue
		_nv_vents = LevelSanity.hazards(_world_root())
		if _nv_plate_open_at(feet): return true
		if restore_plates:
			var missing_plate := Vector2.INF
			for plate in _world_root().get_node("Props").get_children():
				if not plate is PressurePlate or LevelSanity.feet_of(plate).distance_to(feet) < 4: continue
				var plate_feet := LevelSanity.feet_of(plate)
				for connection in plate.activated.get_connections():
					var door = connection.callable.get_object()
					if door is ArenaDoor and not door.is_open and door.position.x > _player().position.x - 400.0 and door.position.x < feet.x:
						missing_plate = plate_feet
			if missing_plate != Vector2.INF:
				if not await _nv_navigate(missing_plate, false): return false
		_step = "route_to_" + str(feet)
		var route := _nv_path(_nv_segments(), feet)
		if route.is_empty():
			var segs := _nv_segments()
			var here := _nv_closest(segs, _player().position)
			_fail("no navigation route to %s from %s (segment %s)" % [feet, _player().position,
					segs[here].r if here >= 0 else "none"])
			return false
		var traversed := true
		for i in range(1, route.size()):
			if not await _nv_cross(route[i - 1], route[i]):
				traversed = false
				break
		if traversed and await _nv_flat(feet.x, feet.y):
			return true
		if _player() != null and _player().health.current > 0 and _nv_plate_open_at(feet): return true
		print("[NAV RETRY] target=%s at=%s attempt=%d" % [feet, _player().position if _player() else Vector2.INF, attempt])
	_fail("navigation exhausted retries to " + str(feet))
	return false


## 炉口挡路吗：前方 ~40px 内有一口同高度的周期炉口，且现在进去（含穿过判定区的时间）不安全。
## 已经站在判定区里就不拦（要让人走出去）。
func _nv_hazard_blocks(p: Player, target_x: float) -> bool:
	if not p.is_on_floor(): return false
	return HAZARD_POLICY.should_wait(_nv_vents, p.global_position, target_x,
			p.controller.max_speed)


func _nv_grounded_near(x: float, y: float) -> bool:
	var p := _player()
	if p == null or not p.is_on_floor() or absf(p.position.x - x) >= 4.0 \
			or absf(p.get_real_velocity().x) >= 12.0: return false
	# A live slope is connected ground, even though the static graph records
	# the adjacent platform's level top. Read its actual contact normal.
	var tolerance := 36.0 if absf(p.get_floor_normal().x) > 0.1 else 9.0
	return absf(p.position.y - y) < tolerance


func _nv_flat(x: float, y: float, fight: bool = true) -> bool:
	if not fight: _release()
	for i in 900:
		var p := _player()
		if p == null or p.health.current <= 0: return false
		if _nv_grounded_near(x, y):
			_release()
			return true
		if absf(p.position.y - y) > 40: return false
		if _nv_hazard_blocks(p, x):
			_release()
			_hazard_wait_frames += 1
			await _frames(1)
			continue
		_nv_steer(x)
		var spitter_close := false
		var landing_guard := false
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy is SpitterEnemy and not enemy._dead and absf(enemy.position.y - p.position.y) < 14 and absf(enemy.position.x - p.position.x) < 64: spitter_close = true
			if enemy is EnemyBase and not enemy._dead and not enemy is GhostEnemy \
					and absf(enemy.position.y - p.position.y) < 24 and absf(enemy.position.x - p.position.x) < 52:
				landing_guard = true
		if not fight and landing_guard:
			# A run-up is part of traversal, but contact enemies can knock the
			# knight back into the pit. Clear that real threat before positioning.
			_nv_combat(false, true)
		elif fight or spitter_close or absf(x - p.position.x) > 96:
			_nv_combat(absf(x - p.position.x) > 96)
		else:
			_set_action(&"attack", false)
			_set_action(&"dash", false)
		for gate in _world_root().get_node("Props").get_children():
			if gate is RustyGate and LevelSanity.feet_of(gate).distance_to(p.position) < 42:
				_set_action(&"interact", i % 30 == 0)
		_set_action(&"jump", p.is_on_wall() and i % 36 < 24)
		await _frames(1)
	_release()
	return false


func _nv_steer(x: float) -> void:
	var p := _player()
	var dx := x - p.position.x
	# CharacterBody.velocity excludes the conveyor's inherited floor motion.
	# Brake against measured world movement so a belt can be counter-steered.
	var speed := p.get_real_velocity().x if p.is_on_floor() else p.velocity.x
	var brake := speed * speed / (2.0 * (400.0 if p.is_on_floor() else 270.0) * 1.55)
	if absf(dx) < 2 and absf(speed) < 10:
		_move(0)
	elif signf(dx) == signf(speed) and absf(dx) < brake + 2:
		_move(0 if p.is_on_floor() and p.controller._land_grip > 0 else -signf(speed))
	else:
		_move(signf(dx))


func _nv_combat(allow_dash: bool = true, hold_ground: bool = false) -> void:
	_nv_tick += 1
	var p := _player()
	var melt := false
	for gate in _world_root().get_node("Props").get_children():
		if gate is RustyGate and LevelSanity.feet_of(gate).distance_to(p.position) < 42: melt = true
	_set_action(&"interact", melt and _nv_tick % 30 == 0)
	var threat: EnemyBase
	var distance := 64.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e is EnemyBase or e._dead or absf(e.position.y - p.position.y) > 40: continue
		var dx: float = absf(e.position.x - p.position.x)
		if dx < distance:
			distance = dx
			threat = e
	var attack := false
	var dash := false
	if _nv_guard_combat(threat, _nv_tick): return
	if threat != null:
		var side := signf(threat.position.x - p.position.x)
		if threat.has_method("is_airborne") and threat.is_airborne():
			if hold_ground:
				_move(side if p.controller.facing != side else 0.0)
			attack = distance < 48 and p.controller.facing == side and _nv_tick % 20 == 0
			dash = allow_dash and distance < 38 and _nv_tick % 6 == 0
		elif allow_dash and not threat is SpitterEnemy:
			var behind := threat.position.x + 28 - p.position.x
			_move(signf(behind) if absf(behind) > 6 else (-1.0 if p.controller.facing != -1 else 0.0))
			attack = distance < 38 and p.controller.facing == -1 and _nv_tick % 24 == 0
			dash = p.position.x < threat.position.x and distance < 42 and _nv_tick % 6 == 0
		else:
			var hold_distance := 30
			_move(side if distance > hold_distance or p.controller.facing != side else 0.0)
			attack = distance < 48 and p.controller.facing == side and _nv_tick % 20 == 0
	_set_action(&"attack", attack)
	_set_action(&"dash", dash)


## Flank a blocking guard only where its rear has a fixed same-height landing.
## Run-up positioning must not keep trading frontal swings into an intact shield.
func _nv_guard_combat(threat: EnemyBase, tick: int) -> bool:
	if not threat is GearShieldEnemy: return false
	var p := _player()
	var facing := float((threat as GearShieldEnemy)._shield_facing)
	var rear := threat.position.x - facing * 32.0
	var support := LevelSanity.standing_on(LevelSanity.top_segments(_world_root()),
			Vector2(rear, threat.position.y))
	if support == null or support.kind != "" or absf(p.position.y - threat.position.y) > 8: return false
	var behind := (p.position.x - threat.position.x) * facing < -16.0
	if not behind:
		_move(signf(rear - p.position.x))
		_set_action(&"attack", false)
		_set_action(&"dash", absf(p.position.x - threat.position.x) < 60 and p.controller._dash_cd <= 0)
	else:
		_move(facing if p.controller.facing != facing else 0.0)
		_set_action(&"attack", tick % 20 == 0)
		_set_action(&"dash", false)
	return true


## 台面这一端的外侧（身体高度）是不是实心：是墙不是边。
func _nv_edge_blocked(r: Rect2, right: bool) -> bool:
	# Test the full knight body. A balcony can clip the head while leaving the
	# old single waist-height probe clear, so walking off that edge never works.
	var probe := Rect2(Vector2(r.end.x + 0.5 if right else r.position.x - 14.5,
			r.position.y - 26.0), Vector2(14.0, 26.0))
	# Adjacent pieces of one continuous floor have no walk-off at their join.
	# Keep walking through the next segment until a real edge or stair exists.
	var foot_probe := Vector2(r.end.x + 0.5 if right else r.position.x - 0.5,
			r.position.y + 0.5)
	for s in _nv_solids():
		if s.grow(-0.5).intersects(probe): return true
		if absf(s.position.y - r.position.y) < 1.0 and s.has_point(foot_probe): return true
	return false


func _nv_drop_side_clear(from: Rect2, to: Rect2, right: bool) -> bool:
	var landing := from.end.x + 12.0 if right else from.position.x - 12.0
	# A landing may support part of the body at its outer lip; unlike an
	# intermediate obstacle, its edge does not need the entire descent sweep.
	if landing < to.position.x + 3.0 or landing > to.end.x - 3.0 or _nv_edge_blocked(from, right):
		return false
	# A stair under the departure ledge catches the knight before the claimed
	# lower floor. Route through that real landing instead of retrying forever.
	# Steering/braking can drift four pixels around the landing center. A
	# nominal 16px shaft beside a floor is too tight for that 14px body sweep.
	var descent := Rect2(landing - 11.0, from.position.y, 22.0, to.position.y - from.position.y)
	for solid in _nv_solids():
		if solid.position.y > from.position.y + 0.5 and solid.position.y < to.position.y - 0.5 \
				and solid.grow(-0.5).intersects(descent): return false
	return true


func _nv_cross(a: Dictionary, b: Dictionary) -> bool:
	if _player() == null or _player().health.current <= 0: return false
	var ar: Rect2 = a.r
	var br: Rect2 = b.r
	print("[CROSS] %s -> %s at=%s hp=%d" % [ar, br, _player().position, _player().health.current])
	if a.lift != null and a.lift == b.lift:
		_release()
		for i in 1200:
			if _player() == null or _player().health.current <= 0 or not is_instance_valid(b.lift): return false
			_nv_steer(b.lift.position.x + b.lift.width * 0.5)
			if b.lift.position.distance_to(br.position) < 8 \
					and absf(_player().position.y - br.position.y) < 10 and _player().is_on_floor(): return true
			await _frames(1)
		return false
	var right := br.get_center().x >= ar.get_center().x
	var gap := maxf(0, maxf(br.position.x - ar.end.x, ar.position.x - br.end.x))
	# A deep lower landing needs a drop through the opening. Jumping first
	# catches the neighboring upper gallery and repeats the same route forever.
	var deep_drop := gap > 0.0 and br.position.y - ar.position.y >= 64.0 \
			and a.lift == null and b.lift == null
	# 缺口大的上跳（升 ≥16、横跨 ≥24）贴着台缘起跳：真实单跳够距只有 ~40px。
	var margin := 3.0 if (gap >= 20.0 and br.position.y < ar.position.y - 8.0) else 8.0
	# At a contiguous 32px riser, jumping against the lip catches the body on
	# its vertical face. Start earlier so the feet clear it before moving across.
	if gap < 4.0 and ar.position.y - br.position.y > 24.0: margin = 24.0
	var launch := clampf(br.position.x - margin if right else br.end.x + margin, ar.position.x + margin, ar.end.x - margin)
	var vertical_riser := false
	if a.lift == null and gap < 4.0 and ar.position.y - br.position.y > 24.0:
		var rise := Rect2(launch - 7.0, br.position.y - 26.0, 14.0, ar.position.y - br.position.y)
		for solid in _nv_solids():
			if solid.grow(-0.5).intersects(rise): vertical_riser = true
		if vertical_riser:
			# Stand just outside the step after leaving the low ceiling. Jump
			# straight up, then use the normal air dash once the feet clear it.
			launch = ar.end.x - 8.0 if right else ar.position.x + 8.0
	# 落到一条与自己横向重叠的更低长地面（楼座 → 巷、浮石 → 地面）：不能「走到落点」——落点
	# 还在自己头顶的台面上。走到朝向终点那一侧的台缘，再往外走下去。
	var drop_landing := NAN
	if gap <= 0.0 and br.position.y > ar.position.y + 8.0 and b.lift == null:
		right = _nv_goal.x >= ar.get_center().x if _nv_goal.is_finite() else right
		if not _nv_drop_side_clear(ar, br, right): right = not right
		if not _nv_drop_side_clear(ar, br, right): return false
		launch = ar.end.x - 8.0 if right else ar.position.x + 8.0
		# Leave room for the steering deadband inside the destination's 3px
		# success margin, even when only its outer lip supports the landing.
		drop_landing = clampf(ar.end.x + 12.0 if right else ar.position.x - 12.0,
				br.position.x + 6.0, br.end.x - 6.0)
	if a.lift != null:
		for i in 1200:
			if _player() == null or _player().health.current <= 0 or not is_instance_valid(a.lift): return false
			_nv_steer(launch)
			if absf(_player().position.x - launch) < 4 and absf(_player().velocity.x) < 12 and absf(_player().position.y - ar.position.y) < 10: break
			await _frames(1)
	# 空中加速度只有 270px/s²：站着起跳 0.4s 只飘 ~22px。任何有缺口的跳都要助跑（和玩家一样）。
	if (gap > 0 or ar.position.y - br.position.y > 24.0) and a.lift == null and not vertical_riser:
		var run_start := ar.end.x - 36 if right else ar.position.x + 36
		run_start = clampf(run_start, ar.position.x + 4.0, ar.end.x - 4.0)
		if not await _nv_flat(run_start, ar.position.y, false): return false
		_release()
		while _player() != null and (_player().controller._dash_cd > 0 or _player().controller._commit_lock): await _frames(1)
		_move(1 if right else -1)
		for i in 90:
			if _player() == null or _player().health.current <= 0: return false
			if (right and _player().position.x >= launch) or (not right and _player().position.x <= launch): break
			await _frames(1)
	elif a.lift == null:
		if not await _nv_flat(launch, ar.position.y, false): return false
		_release()
		while _player() != null and (_player().controller._dash_cd > 0 or _player().controller._commit_lock): await _frames(1)
	if vertical_riser:
		# The flat-walk steering deadband is wider than the last pixel of
		# ceiling clearance. Settle against the actual riser face by input.
		_move(1.0 if right else -1.0)
		for i in 90:
			if _player() == null or _player().health.current <= 0: return false
			if (right and _player().position.x >= ar.end.x - 7.2) \
					or (not right and _player().position.x <= ar.position.x + 7.2): break
			await _frames(1)
		_release()
	if b.lift != null:
		_release()
		for i in 1200:
			if not is_instance_valid(b.lift) or _player() == null or _player().health.current <= 0: return false
			if b.lift.position.distance_to(br.position) < 10: break
			_move(0)
			_nv_combat(false, true)
			if absf(_player().position.x - launch) > 5: _nv_steer(launch)
			await _frames(1)
	_release()
	await _frames(2)
	if gap > 24:
		while _player() != null and _player().controller._dash_cd > 0:
			await _frames(1)
	var drop_dashed := false
	var riser_dashed := false
	for i in 180:
		var p := _player()
		if p == null or p.health.current <= 0: return false
		var r: Rect2 = br
		if b.lift != null:
			if not is_instance_valid(b.lift): return false
			r.position = b.lift.position
		var landing := r.position.x + minf(18, r.size.x * 0.5) if right else r.end.x - minf(18, r.size.x * 0.5)
		if not is_nan(drop_landing): landing = drop_landing
		var departure_y: float = a.lift.position.y if a.lift != null and is_instance_valid(a.lift) else ar.position.y
		if vertical_riser and not riser_dashed:
			_move(0.0)
		elif not is_nan(drop_landing) and p.is_on_floor() and absf(p.position.y - departure_y) < 8.0:
			# Leave the whole 14px body past the ledge before braking. Steering to
			# a point only 8px beyond it can stop 2px short and remain supported.
			_move(1.0 if right else -1.0)
		else:
			_nv_steer(landing)
		_set_action(&"jump", i < 24 and not deep_drop and is_nan(drop_landing) and not (gap < 4 and br.position.y > ar.position.y))
		var dash_frame := 11 if ar.position.y - br.position.y > 24 else (16 if ar.position.y == br.position.y else 8)
		var needs_dash := gap > (56 if br.position.y > ar.position.y else 40) \
				or (ar.position.y - br.position.y > 24.0 and gap > 24.0) \
				or (deep_drop and gap > 24.0) \
				or (a.lift != null and gap > 32.0)
		var dash_now := i == dash_frame
		if deep_drop:
			# Cross under the neighboring 16px gallery only after the whole
			# 26px knight clears its underside; an early dash hits its side.
			dash_now = not drop_dashed and p.position.y >= ar.position.y + 44.0
			if dash_now and needs_dash: drop_dashed = true
		if vertical_riser:
			needs_dash = true
			dash_now = not riser_dashed and p.position.y <= br.position.y - 2.0
			if dash_now:
				_move(1.0 if right else -1.0)
				riser_dashed = true
		_set_action(&"dash", dash_now and needs_dash)
		if i > 4 and p.is_on_floor() and absf(p.position.y - r.position.y) < 8 and p.position.x >= r.position.x + 3 and p.position.x <= r.end.x - 3 and absf(p.velocity.x) < 20:
			_release()
			return true
		if i > 35 and p.is_on_floor() and absf(p.position.y - r.position.y) > 9:
			_release()
			return false
		await _frames(1)
	_release()
	print("[CROSS TIMEOUT] feet=%s velocity=%s floor=%s destination=%s drop_target=%s" % [
			_player().position if _player() else Vector2.INF,
			_player().velocity if _player() else Vector2.INF,
			_player().is_on_floor() if _player() else false, br, drop_landing])
	return false


func _frames(count: int) -> void:
	var elapsed := 0.0
	while elapsed < count:
		await get_tree().physics_frame
		elapsed += Engine.time_scale


func _tap(action: StringName) -> void:
	_set_action(action, true)
	await _frames(2)
	_set_action(action, false)
	await _frames(2)


func _set_action(action: StringName, down: bool) -> void:
	if down == Input.is_action_pressed(action): return
	if down: Input.action_press(action)
	else: Input.action_release(action)


func _move(direction: float) -> void:
	_set_action(&"move_left", direction < 0.0)
	_set_action(&"move_right", direction > 0.0)


func _release() -> void:
	for action in [&"move_left", &"move_right", &"jump", &"dash", &"attack", &"interact", &"socket_1", &"socket_2", &"hookshot"]:
		_set_action(action, false)
	_jump_hold = 0
	_jump_cd = 0


func _ui(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _record(name_: String) -> void:
	var player := _player()
	var record := {"milestone": name_, "elapsed_ms": Time.get_ticks_msec() - _started,
		"position": str(player.global_position) if player else "title", "deaths": _deaths}
	_records.append(record)
	print("[MILESTONE] ", JSON.stringify(record))
	_shot("m_%02d_%s" % [_records.size(), name_])
	if _rendered and name_ in ["new_game", "grapple_ember", "boss_slain", "ending_rekindle", "ending_snuff"]:
		get_tree().root.get_texture().get_image().save_png("user://%s_%s.png" % [_ending, name_])
		_last_frame_usec = Time.get_ticks_usec() # PNG encoding is excluded from gameplay frame timings.


func _require(condition: bool, message: String) -> bool:
	if not condition: _fail(message)
	return condition


func _fail(message: String) -> void:
	if _failed: return
	_failed = true
	_release()
	printerr("[WALKTHROUGH FAIL] %s: %s" % [_step, message])
	_write_result(false)
	get_tree().quit(1)


func _write_result(passed: bool) -> void:
	var result := {"passed": passed, "ending": _ending, "input_only": true,
		"milestones": _records, "engine_errors": Array(_errors.errors()), "deaths": _deaths}
	result["campaign"] = _campaign
	result["basic_abilities"] = _basic_abilities
	result["resumed"] = "--resume" in OS.get_cmdline_user_args()
	result["fixed_fps_accelerated"] = "--fast" in OS.get_cmdline_user_args()
	result["rendered"] = _rendered
	result["hazard_wait_frames"] = _hazard_wait_frames
	result["assists"] = {
		"incoming_damage": Settings.assist(&"assist_incoming"),
		"parry_window": Settings.assist(&"assist_parry"),
		"toxin_exposure": Settings.assist(&"assist_toxin"),
	}
	result["renderer"] = RenderingServer.get_current_rendering_method()
	if not _frame_ms.is_empty():
		_frame_ms.sort()
		var total := 0.0
		for sample in _frame_ms: total += sample
		result["frame_timing"] = {"samples": _frame_ms.size(), "mean_ms": total / _frame_ms.size(),
			"p95_ms": _frame_ms[int((_frame_ms.size() - 1) * 0.95)], "max_ms": _frame_ms.back(),
			"scope": "1080p offscreen window; PNG encoding excluded; " + ("accelerated fixed 60 Hz simulation" if "--fast" in OS.get_cmdline_user_args() else "60 FPS cap")}
	var output := FileAccess.open("user://walkthrough_%s.json" % _ending, FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(result, "\t"))


func _exit_tree() -> void:
	if _errors != null: OS.remove_logger(_errors)
