extends Node
## Acceptance driver: normal input only. Never moves actors, gives items,
## damages enemies, opens gates, or emits gameplay milestones.
const ERROR_COLLECTOR := preload("res://tests/error_collector.gd")
const TITLE := "res://scenes/ui/TitleScreen.tscn"
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rendered = DisplayServer.get_name() != "headless"
	if _rendered:
		get_tree().root.mode = Window.MODE_WINDOWED
		get_tree().root.borderless = true
		get_tree().root.size = Vector2i(1920, 1080)
		get_tree().root.position = Vector2i(-12000, -12000)
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


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _rendered and _last_frame_usec > 0 and GameContext.gameplay_input_enabled() and _player() != null:
		_frame_ms.append(float(now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now
	if _failed:
		return
	if Time.get_ticks_msec() - _started > (1800000 if _campaign else 240000):
		_fail("walkthrough exceeded its time budget")
	if not _errors.errors().is_empty():
		_fail("engine error: " + _errors.errors()[0])
	if _skip_captions and Director.playing and not get_tree().paused and Time.get_ticks_msec() - _last_skip > 180:
		_last_skip = Time.get_ticks_msec()
		_ui(&"ui_accept")


func _run() -> void:
	get_tree().change_scene_to_file(TITLE)
	await _frames(12)
	_ui(&"ui_accept") # title: new game
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
	if not await _walk_to(812.0, false): return
	if not _basic_abilities:
		await _tap(&"interact")
		if not await _wait_world(): return
		await _tap(&"socket_1")
		if not await _wait_world(): return
		if not _require(_player().inventory.has_ability(AbilityIds.HOOKSHOT_TETHER), "spitter tether drop equipped"): return
		_record("spitter_tether")
	if not await _walk_to(904.0, false): return
	if not await _walk_to(1050.0, false): return
	await _frames(20)
	var world := GameContext.world_root(_player())
	if not _require(world.get_node("Props/Door").is_open, "pressure plate opened door"): return
	_record("pressure_plate")
	if not await _collect_kiln(): return
	_record("kiln_socket")
	if not await _walk_to(1363.0, false): return
	await _tap(&"interact")
	await _frames(4)
	world = GameContext.world_root(_player())
	if not _require(not is_instance_valid(world.get_node_or_null("Props/RustyGate")), "rust gate melted through E"): return
	_record("rust_gate")
	if not await _walk_to(1430.0, false): return
	if not _basic_abilities:
		if not await _grapple_ember(): return
		_record("grapple_ember")
	if not await _walk_to(1640.0, false): return
	if not await _walk_to(1536.0, false): return
	await _tap(&"interact")
	if not _require(SaveData.last_lit_nest().ends_with("EmberNestEast"), "east checkpoint is reachable"): return
	_record("east_checkpoint")
	if not await _walk_to(1885.0, false): return
	if not await _fight_boss(): return
	_record("boss_slain")
	if not await _verify_progress_reload(): return
	if not await _walk_to(2052.0, false): return
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
	_ui(&"ui_cancel")
	await _frames(3)
	_ui(&"ui_up")
	await _frames(3)
	_ui(&"ui_accept")
	for i in 600:
		await _frames(1)
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == TITLE:
			await _frames(6)
			_ui(&"ui_down")
			await _frames(3)
			_ui(&"ui_accept")
			if not await _wait_world(): return false
			var player := _player()
			if not _require(GameContext.world_scene_path(player) == GameContext.LEVEL02_PATH, "continue reopens Level02"): return false
			if not _require(absf(player.position.x - 176.0) < 12.0, "continue restores the undercroft checkpoint"): return false
			_record("undercroft_continue_verified")
			return true
	_fail("pause menu did not return to title from Level02")
	return false


func _wait_world() -> bool:
	for i in 600:
		await _frames(1)
		var player := _player()
		if player != null and player.health.current > 0 and GameContext.gameplay_input_enabled():
			return true
	_fail("world did not become playable")
	return false


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
		var need_jump := jump or (target_x > 600.0 and player.global_position.x < 780.0)
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
			if not await _walk_to(1885.0, false): return false
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
		attack_cd = maxi(0, attack_cd - 1)
		var attack := absf(player.global_position.x - boss.global_position.x) < 38.0 \
				and player.controller.facing == -1 and attack_cd == 0
		_set_action(&"attack", attack)
		if attack: attack_cd = 24
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
		if i % 120 == 0:
			print("[SPITTER] player=%s hp=%d spitter=%s hp=%d" % [player.position, player.health.current, spitter.position, spitter.health.current])
		await _frames(1)
	_fail("spitter could not be defeated with normal melee")
	return false


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
		if not await _walk_to(1220.0, false): return false
		await _tap(&"interact")
		if not await _wait_world(): return false
	_fail("kiln core could not be collected and socketed")
	return false


func _verify_progress_reload() -> bool:
	_step = "boss_death_reload"
	var old_id := _player().get_instance_id()
	# Walk back into the hostile courtyard and allow ordinary enemy damage.
	# This never calls damage, respawn, load, or any story completion hook.
	for i in 2400:
		var player := _player()
		if player != null and player.get_instance_id() != old_id and player.health.current > 0 \
				and GameContext.gameplay_input_enabled():
			_release()
			if not _check_restored_progress(): return false
			_record("boss_death_reload_verified")
			break
		if player != null and player.health.current > 0 and GameContext.gameplay_input_enabled():
			_move(-1.0 if player.position.x > 1020.0 else 0.0)
		else:
			_release()
		await _frames(1)
		if i == 2399:
			_fail("enemy damage did not complete a checkpoint reload")
			return false
	_ui(&"ui_cancel")
	await _frames(3)
	_ui(&"ui_up") # Pause: wrap from Resume to Return to Title.
	await _frames(3)
	_ui(&"ui_accept")
	for i in 600:
		await _frames(1)
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == TITLE:
			await _frames(6)
			_ui(&"ui_down") # Title: Continue.
			await _frames(3)
			_ui(&"ui_accept")
			if not await _wait_world(): return false
			if not _check_restored_progress(): return false
			_record("continue_verified")
			return true
	_fail("pause menu did not return to title")
	return false


func _check_restored_progress() -> bool:
	var player := _player()
	var world := GameContext.world_root(player)
	return _require(absf(player.position.x - 1536.0) < 12.0, "reload preserves east nest checkpoint") \
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
		var dx := 1568.0 - player.position.x
		_move(signf(dx) if absf(dx) > 4.0 else 0.0)
		if i % 30 == 0:
			print("[HOOK] position=%s active=%s" % [player.position, player.hookshot.is_active()])
		if player.position.y < 125.0 and player.is_on_floor() and absf(dx) < 18.0:
			_release()
			await _tap(&"interact")
			await _frames(15)
			await _tap(&"socket_2")
			await _frames(8)
			return _require(player.inventory.has_ability(AbilityIds.EMBER_STEP), "ember core equipped from real ledge")
		await _frames(1)
	_fail("grapple did not reach the ember ledge")
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
