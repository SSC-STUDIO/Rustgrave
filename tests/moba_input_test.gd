extends TestCase
## Input routing of the actual 3D preview, including its native return button.

const Spike := preload("res://scripts/moba/spike/render_spike.gd")
const Camera := preload("res://scripts/moba/view/pixel_camera.gd")
const Run := preload("res://scripts/moba/moba_run.gd")

var _left_events: Array[InputEvent] = []
var _old_shake := 1.0
var _old_hold := false
var _old_jump := 0
var _old_device := &"keyboard"


func setup() -> void:
	_old_shake = Settings.shake_scale
	_old_hold = WorldClock.menu_hold
	_old_jump = Settings.key_for(&"jump")
	_old_device = KeyLabels.device()
	_left_events = InputMap.action_get_events("move_left")
	Run.abandon()
	Director._fading = false
	Director._queued_fade_path = ""
	Director.last_fade_target = ""
	_release_actions()


func teardown() -> void:
	_release_actions()
	InputMap.action_erase_events("move_left")
	for event in _left_events:
		InputMap.action_add_event("move_left", event)
	Settings.set_shake_scale(_old_shake, false)
	Settings.rebind_action(&"jump", _old_jump, false)
	KeyLabels.set_device(_old_device)
	Run.abandon()
	WorldClock.menu_hold = _old_hold
	Director._fading = false
	Director._queued_fade_path = ""


func _release_actions() -> void:
	for action in ["move_left", "move_right", "ui_up", "ui_down", "attack", "jump"]:
		Input.action_release(action)


func _spike() -> Node:
	var spike := Spike.new()
	add_child(spike)
	await flush(2)
	spike.set_process(false)
	return spike


func _key(spike: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	spike._unhandled_input(event)


func _pad_button(action: StringName) -> InputEventJoypadButton:
	for binding in InputMap.action_get_events(action):
		if binding is InputEventJoypadButton:
			var event := binding.duplicate() as InputEventJoypadButton
			event.device = 5
			event.pressed = true
			return event
	return null


func test_normal_overlay_keeps_render_controls_behind_f3() -> void:
	var spike := await _spike()
	ok(Run.active(), "a standalone preview attaches its protected session")
	eq(spike._mode_label.text, "余烬竞技场 · 3D试演")
	ok(spike._player_hint.visible and spike._return_button.visible)
	ok(not spike._info.visible and not spike._help.visible,
			"the normal screen does not expose render statistics")
	var button: Button = spike._return_button
	var viewport_bounds := get_viewport().get_visible_rect()
	var button_bounds := button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size)
	ok(viewport_bounds.encloses(button_bounds), "the actual themed return button fits the canvas")
	var right_edge := button_bounds.end.x
	# A theme or text-scale change may enlarge the native minimum after ready.
	button.custom_minimum_size = button.size + Vector2(96.0, 0.0)
	await flush(2)
	button_bounds = button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size)
	ok(viewport_bounds.encloses(button_bounds), "a later minimum-size increase cannot clip the frame")
	almost(button_bounds.end.x, right_edge, 0.01, "resizing preserves the original right inset")
	KeyLabels.set_device(KeyLabels.DEVICE_KEYBOARD)
	Settings.rebind_action(&"jump", KEY_V, false)
	spike._refresh_player_hint()
	ok(spike._player_hint.text.contains(" / V"), "the alternate swing prompt follows the rebound jump action")
	ok(not spike._player_hint.text.contains("空格"), "the old Space hint is removed after rebinding")
	_key(spike, KEY_M)
	_key(spike, KEY_3)
	eq(spike._stress.size(), 0, "the normal map key cannot spawn forty units")
	ok(spike._snap, "normal number keys do not change the rendering pipeline")
	_key(spike, KEY_F3)
	ok(spike._info.visible and spike._help.visible)
	_key(spike, KEY_M)
	eq(spike._stress.size(), 40, "debug mode retains the original stress tool")
	_key(spike, KEY_M)
	_key(spike, KEY_F3)
	ok(not spike._info.visible and not spike._help.visible)
	spike.queue_free()
	await flush(2)
	ok(not Run.active(), "freeing the preview detaches its session")


func test_rebound_horizontal_keys_and_vertical_actions_move_the_hero() -> void:
	var spike := await _spike()
	InputMap.action_erase_events("move_left")
	var binding := InputEventKey.new()
	binding.physical_keycode = KEY_Z
	InputMap.action_add_event("move_left", binding)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Z
	key.keycode = KEY_Z
	key.pressed = true
	ok(key.is_action_pressed("move_left"), "the new physical key matches the rebound action")
	# SceneTree test hosts do not update OS keyboard state from a synthetic key.
	# Verify the binding above, then drive the action consumed by locomotion.
	Input.action_press("move_left")
	var before: Vector3 = spike.hero.global_position
	spike._move_hero(0.1)
	ok(spike.hero.global_position.x < before.x, "rebound input moves left without hardcoded A")
	Input.action_release("move_left")
	Input.action_press("ui_down")
	before = spike.hero.global_position
	spike._move_hero(0.1)
	ok(spike.hero.global_position.z > before.z, "vertical UI actions also drive the world axis")
	Input.action_release("ui_down")
	spike.queue_free()
	await flush(2)


func test_gamepad_actions_work_for_a_nonzero_device() -> void:
	var spike := await _spike()
	var event := _pad_button(&"move_right")
	spike._input(event)
	almost(spike._pad_strength(&"move_right"), 1.0, 0.001,
			"D-pad mapping accepts a controller beyond device zero")
	var before: Vector3 = spike.hero.global_position
	spike._move_hero(0.1)
	ok(spike.hero.global_position.x > before.x)
	var release := event.duplicate() as InputEventJoypadButton
	release.pressed = false
	spike._input(release)
	almost(spike._pad_strength(&"move_right"), 0.0)
	var axis := InputEventJoypadMotion.new()
	axis.device = 5
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 0.1
	spike._input(axis)
	almost(spike._pad_strength(&"move_right"), 0.0, 0.001, "stick drift stays inside the mapped deadzone")
	axis.axis_value = 0.6
	spike._input(axis)
	ok(spike._pad_strength(&"move_right") > 0.0 and spike._pad_strength(&"move_right") < 1.0,
			"analog strength preserves the active InputMap deadzone")
	spike._on_pad_connection_changed(5, false)
	almost(spike._pad_strength(&"move_right"), 0.0, 0.001, "disconnect clears held motion")
	spike._input(event)
	spike._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	almost(spike._pad_strength(&"move_right"), 0.0, 0.001, "focus loss clears held motion")
	spike._unhandled_input(_pad_button(&"attack"))
	ok(spike.hero.is_attacking(), "the bound gamepad attack reaches the knight")
	spike.queue_free()
	await flush(2)


func test_arrival_fade_blocks_input_until_the_scene_is_ready() -> void:
	var spike := await _spike()
	var before: Vector3 = spike.hero.global_position
	Director._fading = true
	Input.action_press("move_right")
	spike._move_hero(0.5)
	_key(spike, KEY_F3)
	var attack := InputEventAction.new()
	attack.action = &"attack"
	attack.pressed = true
	spike._unhandled_input(attack)
	spike._demo = true
	spike._process(0.5)
	eq(spike.hero.global_position, before, "held movement waits for arrival to finish")
	ok(not spike.hero.is_attacking(), "arrival also blocks attack and the demo controller")
	ok(not spike._debug)
	Director._fading = false
	spike._demo = false
	spike._move_hero(0.1)
	ok(spike.hero.global_position.x > before.x, "input resumes after the fade")
	Input.action_release("move_right")
	spike.queue_free()
	await flush(2)


func test_escape_and_gamepad_cancel_return_without_quitting_or_double_fading() -> void:
	for kind in ["keyboard", "gamepad"]:
		var spike := await _spike()
		spike._touch_index = 4
		spike._touch_goal = Vector3.ONE
		if kind == "keyboard":
			_key(spike, KEY_ESCAPE)
		else:
			spike._unhandled_input(_pad_button(&"ui_cancel"))
		ok(spike._leaving, "%s starts the title return" % kind)
		eq(spike._touch_index, -1)
		eq(spike._touch_goal, Vector3.ZERO)
		ok(spike._return_button.disabled)
		spike._return_to_title()
		eq(Director._queued_fade_path, "", "a duplicate return cannot queue a second transition")
		ok(await wait_until(func() -> bool: return not Director.is_fading(), 90))
		eq(Director.last_fade_target, Run.TITLE_SCENE, "cancel requests the title instead of process quit")
		ok(Run.active(), "save protection lasts until the 3D owner leaves")
		spike.queue_free()
		await flush(2)
		ok(not Run.active())


func test_native_return_button_consumes_mouse_input_and_freezes_leaving_controls() -> void:
	var spike := await _spike()
	var button: Button = spike._return_button
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await flush(1)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		get_viewport().push_input(click, true)
		await flush(1)
	ok(spike._leaving, "a real native button press/release requests the return")
	ok(not spike.hero.is_attacking(), "the GUI click is consumed before the attack action")
	var before: Vector3 = spike.hero.global_position
	Input.action_press("move_right")
	spike._move_hero(1.0)
	eq(spike.hero.global_position, before, "input cannot move a leaving hero")
	Input.action_release("move_right")
	_key(spike, KEY_F3)
	_key(spike, KEY_M)
	var attack := InputEventAction.new()
	attack.action = &"attack"
	attack.pressed = true
	spike._unhandled_input(attack)
	ok(not spike._debug and spike._stress.is_empty(), "leaving cannot activate debug controls")
	ok(not spike.hero.is_attacking(), "leaving cannot start another swing")
	var touch := InputEventScreenTouch.new()
	touch.index = 8
	touch.pressed = true
	touch.double_tap = true
	spike._on_touch(touch)
	eq(spike._touch_index, -1, "a late touch cannot reclaim the movement target")
	spike._on_impact(before)
	almost(spike.camera._shake, 0.0, 0.001, "a late impact cannot create new shake")
	ok(await wait_until(func() -> bool: return not Director.is_fading(), 90))
	eq(Director.last_fade_target, Run.TITLE_SCENE)
	spike.queue_free()
	await flush(2)


func test_shake_comfort_applies_immediately_to_an_existing_impact() -> void:
	var camera := Camera.new()
	camera.add_shake(0.4)
	Settings.set_shake_scale(1.0, false)
	camera._rng.seed = 8
	var full: Vector3 = camera._shake_offset(Basis.IDENTITY)
	ok(full.length() > 0.0)
	Settings.set_shake_scale(0.0, false)
	eq(camera._shake_offset(Basis.IDENTITY), Vector3.ZERO,
			"turning shake off immediately suppresses an already active impact")
	Settings.set_shake_scale(0.5, false)
	camera._rng.seed = 8
	ok(camera._shake_offset(Basis.IDENTITY).is_equal_approx(full * 0.5),
			"comfort scales the current amplitude rather than only future impacts")
	camera.free()
