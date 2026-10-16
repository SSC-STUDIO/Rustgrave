extends "res://tests/test_case.gd"
## Fixed arena fixtures; after spawning, only normal input drives all actors.
## No damage, movement, state-machine or parry APIs are called by this driver.

const ACTION_KEYS := {&"move_left": KEY_A, &"move_right": KEY_D,
	&"attack": KEY_J, &"dash": KEY_SHIFT, &"jump": KEY_SPACE}
const CAPTIONS := {&"move_left": "←", &"move_right": "→", &"attack": "斩",
	&"dash": "冲", &"jump": "跳"}
var _held: Dictionary = {}
var _touch := false
var _pad: CanvasLayer
var _arena: Node2D
var _knight: Player
var _records: Array[Dictionary] = []
var _errors
var _label: Label


func _ready() -> void:
	_touch = "--touch" in OS.get_cmdline_user_args()
	_errors = preload("res://tests/error_collector.gd").new()
	OS.add_logger(_errors)
	SaveData.save_path = "user://combat-input-fixture.cfg"
	Director.abort()
	get_tree().root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var backdrop := ColorRect.new()
	backdrop.color = Color("171b20")
	backdrop.size = Vector2(1280, 720)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_label = Label.new()
	_label.position = Vector2(70, 90)
	_label.add_theme_font_size_override("font_size", 26)
	add_child(_label)
	if _touch:
		if not ResourceLoader.exists("res://scripts/ui/touch_controls.gd"):
			ok(false, "touch controls are not present in this checkout")
			await _finish()
			return
		OS.set_environment("RUSTGRAVE_FORCE_TOUCH", "1")
		_pad = load("res://scripts/ui/touch_controls.gd").new()
		add_child(_pad)
	await flush(4)
	await _shield()
	await _executioner()
	await _nightmare()
	await _finish()


func _fixture(player_x: float, enemy_scene: PackedScene, enemy_x: float) -> Node2D:
	_release()
	if is_instance_valid(_arena):
		_arena.queue_free()
		await flush(3)
	_arena = Node2D.new()
	_arena.position.y = 400.0
	add_child(_arena)
	build_floor(_arena, 600.0)
	var ground := ColorRect.new()
	ground.position = Vector2(0, 0)
	ground.size = Vector2(1280, 50)
	ground.color = Color("39322c")
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(ground)
	_knight = await spawn_player(_arena, Vector2(player_x, -24))
	var enemy := enemy_scene.instantiate() as Node2D
	enemy.position = Vector2(enemy_x, 0)
	if enemy_scene.resource_path.ends_with("NightmareBoss.tscn"):
		enemy.set("arena_left", 250.0)
		enemy.set("arena_right", 520.0)
	_arena.add_child(enemy)
	return enemy


func _set_action(action: StringName, down: bool) -> void:
	if _held.get(action, false) == down:
		return
	_held[action] = down
	if _touch:
		for label in _pad.find_children("*", "Label", true, false):
			if label.text != CAPTIONS[action]:
				continue
			var button := label.get_parent() as Control
			var event := InputEventScreenTouch.new()
			event.index = ACTION_KEYS.keys().find(action)
			event.position = button.get_global_transform_with_canvas() * (button.size * 0.5)
			event.pressed = down
			get_viewport().push_input(event, true)
			return
		ok(false, "touch button found: " + String(action))
	else:
		var event := InputEventKey.new()
		event.physical_keycode = ACTION_KEYS[action]
		event.keycode = ACTION_KEYS[action]
		event.pressed = down
		Input.parse_input_event(event)


func _move(axis: float) -> void:
	_set_action(&"move_left", axis < 0)
	_set_action(&"move_right", axis > 0)


func _release() -> void:
	for action in ACTION_KEYS:
		_set_action(action, false)


func _shield() -> void:
	_label.text = "SHIELD: slash reflects a bolt, then punish the opening"
	var guard := await _fixture(400, preload("res://scenes/enemies/GearShieldEnemy.tscn"), 500) as GearShieldEnemy
	var opened := false
	var damaged := false
	for frame in 900:
		if not is_instance_valid(guard) or _knight.health.current <= 0:
			break
		_set_action(&"attack", false)
		if not opened:
			for area in find_children("*", "Area2D", true, false):
				if area is Projectile and area.team == &"enemy":
					var dx: float = area.global_position.x - _knight.global_position.x
					if dx > 54 and dx < 66 and not _knight.melee.is_busy():
						_set_action(&"attack", true)
			if guard._state == guard.State.STAGGER:
				opened = true
				await _capture("shield_reflection")
		else:
			var dx := guard.global_position.x - _knight.global_position.x
			_move(1.0 if dx > 34 else 0.0)
			_set_action(&"attack", dx < 42 and frame % 15 == 0)
			if guard.health.current < guard.health.max_hp and guard._state == guard.State.STAGGER:
				damaged = true
				await _capture("shield_punished")
				break
		if frame % 180 == 0:
			print("[SHIELD] player=", _knight.global_position, " guard=", guard.global_position, " state=", guard._state, " sword=", _knight.melee.phase_name())
		await flush(1)
	ok(opened, "normal attack input reflects a real shield bolt")
	ok(damaged, "normal movement and attack exploit the shield opening")
	_release()


func _executioner() -> void:
	_label.text = "EXECUTIONER: wait for axe recovery, then land a frontal strike"
	var boss := await _fixture(400, preload("res://scenes/enemies/ExecutionerBoss.tscn"), 480) as ExecutionerBoss
	var recovered := false
	var punished := false
	for frame in 900:
		if not is_instance_valid(boss) or _knight.health.current <= 0:
			break
		var dx := boss.global_position.x - _knight.global_position.x
		var recovery := boss._slash_phase == boss.SlashPhase.RECOVERY
		if recovery and not recovered:
			recovered = true
			await _capture("axe_recovery")
		_move(1.0 if dx > (34 if recovery else 66) else 0.0)
		_set_action(&"attack", recovery and dx < 42 and frame % 3 == 0)
		if boss.health.current < boss.health.max_hp and recovery:
			punished = true
			await _capture("axe_punished")
			break
		if frame % 180 == 0:
			print("[AXE] player=", _knight.global_position, " boss=", boss.global_position, " state=", boss._state, " phase=", boss._slash_phase)
		await flush(1)
	ok(recovered, "normal approach triggers axe and recovery")
	ok(punished, "normal attack lands through the lowered frontal shield")
	_release()


func _nightmare() -> void:
	_label.text = "NIGHTMARE: cross after direction lock; punish the rest"
	var boss = await _fixture(400, preload("res://scenes/enemies/NightmareBoss.tscn"), 430)
	var locked_face := 0.0
	var charge_verified := false
	var punished := false
	var first_dash := false
	for frame in 1200:
		if not is_instance_valid(boss) or _knight.health.current <= 0:
			break
		_set_action(&"dash", false)
		_set_action(&"attack", false)
		if boss.state() == boss.State.WINDUP and not first_dash:
			_move(1.0)
			_set_action(&"dash", true)
			first_dash = true
		elif boss.state() == boss.State.WINDUP and boss._direction_locked and locked_face == 0:
			locked_face = boss._facing
			_move(-1.0)
			_set_action(&"dash", true)
			await _capture("nightmare_locked")
		elif boss.state() == boss.State.WINDUP:
			_move(0.0)
		elif boss.state() == boss.State.CHARGE:
			if locked_face != 0.0 and not charge_verified:
				eq(boss._dir, locked_face, "charge retains the telegraphed direction")
				charge_verified = true
				await _capture("nightmare_charge")
			_move(0.0)
		elif boss.state() == boss.State.REST:
			var dx: float = boss.global_position.x - _knight.global_position.x
			_move(signf(dx) if absf(dx) > 34 else (signf(dx) if _knight.controller.facing != signf(dx) else 0.0))
			_set_action(&"attack", absf(dx) < 42 and frame % 3 == 0)
			if boss.health.current < boss.health.max_hp:
				punished = true
				await _capture("nightmare_punished")
				break
		if frame % 180 == 0:
			print("[HORSE] player=", _knight.global_position, " boss=", boss.global_position, " state=", boss.state(), " hp=", boss.health.current)
		await flush(1)
	ok(charge_verified, "input-driven crossing exercises the locked charge")
	ok(punished, "normal movement and attack punish its rest")
	_release()


func _capture(name_: String) -> void:
	var path := ""
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		path = "user://combat_" + name_ + ".png"
		get_tree().root.get_texture().get_image().save_png(path)
	_records.append({"state": name_, "image": path, "hp": _knight.health.current})
	print("[COMBAT] ", name_)


func _finish() -> void:
	_release()
	if is_instance_valid(_arena):
		_arena.queue_free()
	if is_instance_valid(_pad):
		_pad.queue_free()
	await flush(3)
	var engine_errors: PackedStringArray = _errors.errors()
	var passed := failure_count() == 0 and engine_errors.is_empty()
	var report := {"passed": passed, "input_only_after_fixture_spawn": true,
		"touch_events": _touch, "rendered": DisplayServer.get_name() != "headless",
		"failures": failures(), "engine_errors": engine_errors, "records": _records}
	var file := FileAccess.open("user://combat_input.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	OS.remove_logger(_errors)
	_errors = null
	print("[COMBAT RESULT] ", JSON.stringify(report))
	get_tree().quit(0 if passed else 1)
