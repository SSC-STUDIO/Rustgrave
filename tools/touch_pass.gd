extends Node
## SIMULATED TOUCH PASS — not a device test.
## Forces the on-screen pad (TouchInput.force_show = 1) in a desktop window, then injects
## InputEventScreenTouch (touch index >= 1, so Godot does not also emulate a mouse click)
## at the on-screen centre of the opening's skip button and of pad buttons, and checks
## what the game did. No real finger, no real touchscreen, desktop OS, desktop GPU.
##   tools/run_touch_pass.ps1 -Window 1280x720

const PRESENTATION := preload("res://scenes/ui/GamePresentation.tscn")

var _win := Vector2i(1280, 720)
var _tag := "1280x720"
var _out := "user://touch"
var _results: Dictionary = {"kind": "SIMULATED touch (InputEventScreenTouch injected on a desktop window)"}
var _failed: PackedStringArray = []
var _touch_index := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--window="):
			var parts := arg.trim_prefix("--window=").split("x", false)
			if parts.size() == 2:
				_win = Vector2i(int(parts[0]), int(parts[1]))
	_tag = "%dx%d" % [_win.x, _win.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.size = _win
	win.position = Vector2i(40, 40)
	TouchInput.force_show = 1
	SaveData.save_path = "user://touch_pass_save.cfg"
	SaveData.delete_save()
	add_child(PRESENTATION.instantiate())
	_run.call_deferred()


func _run() -> void:
	# 1) Opening: the skip prompt must speak touch, and a tap on it must skip the opening.
	var skip := await _wait_node("SkipCinematic", 8.0) as Button
	await _seconds(2.4)
	if skip != null and skip.visible:
		_results["opening_skip_label"] = skip.text
		_check(skip.text.begins_with("点此"), "opening skip prompt uses touch wording")
		_shot("t_00_opening_touch_skip")
		await _tap(_center(skip), 0.08)
		var skipped := await _until(func() -> bool: return not Director.playing, 4.0)
		_check(skipped, "tapping the skip prompt skips the opening")
	else:
		_check(false, "opening skip prompt became visible")
	# 2) Control: pad visible, buttons drive the knight.
	var ok_control := await _until(_has_control, 20.0)
	_check(ok_control, "control returns after the opening")
	await _seconds(0.6)
	var pad := get_tree().root.find_child("TouchControls", true, false) as CanvasLayer
	_check(pad != null and pad.visible, "touch pad is visible in play")
	_shot("t_01_pad_in_play")
	var player := _player()
	if pad == null or player == null:
		_finish()
		return
	var right := _button(pad, &"move_right")
	var left := _button(pad, &"move_left")
	var jump := _button(pad, &"jump")
	var attack := _button(pad, &"attack")
	var pause := _pause_button(pad)
	_check(right != null and left != null and jump != null and attack != null and pause != null, "pad buttons found")
	if right == null or left == null or jump == null or attack == null or pause == null:
		_finish()
		return
	var x0 := player.global_position.x
	await _hold(_center(right), 0.7, func() -> void:
		_results["right_action_pressed_mid_hold"] = Input.is_action_pressed(&"move_right")
		_shot("t_02_hold_right"))
	var dx := player.global_position.x - x0
	_results["hold_right_dx"] = dx
	_check(dx > 20.0, "holding → walks right")
	await _seconds(0.5)  # let the walk-right momentum settle first
	x0 = player.global_position.x
	await _hold(_center(left), 0.7, func() -> void: _results["left_action_pressed_mid_hold"] = Input.is_action_pressed(&"move_left"))
	_results["hold_left_dx"] = player.global_position.x - x0
	_check(player.global_position.x - x0 < -10.0, "holding ← walks left")
	await _seconds(0.3)
	var y0 := player.global_position.y
	await _tap(_center(jump), 0.06)
	var min_y := y0
	for i in 30:
		await get_tree().physics_frame
		min_y = minf(min_y, player.global_position.y)
		if i == 10:
			_shot("t_03_jump")
	_results["jump_rise_px"] = y0 - min_y
	_check(y0 - min_y > 8.0, "tapping 跳 jumps")
	await _seconds(0.6)
	await _tap(_center(attack), 0.06)
	var swung := false
	for i in 12:
		await get_tree().physics_frame
		if player.melee.is_busy():
			swung = true
			if i >= 3:
				_shot("t_04_attack")
				break
	_check(swung, "tapping 斩 swings")
	await _seconds(0.6)
	await _tap(_center(pause), 0.06)
	var menu := get_tree().root.find_child("PauseMenu", true, false)
	var opened := await _until(func() -> bool: return menu != null and bool(menu.call("is_open")), 2.0)
	_check(opened, "tapping the pause button opens the pause menu")
	await _seconds(0.4)
	_shot("t_05_pause_by_touch")
	_finish()


func _finish() -> void:
	_results["failed"] = _failed
	_results["window"] = _tag
	var f := FileAccess.open("%s/touch_%s.json" % [_out, _tag], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_results, "  "))
		f.close()
	print("[TOUCH %s] SIMULATED touch %s; %s" % ["PASS" if _failed.is_empty() else "FAIL", _tag, JSON.stringify(_results)])
	TouchInput.force_show = 0
	get_tree().quit(0 if _failed.is_empty() else 1)


func _check(cond: bool, what: String) -> void:
	print("[TOUCH CHECK] %s %s" % ["ok" if cond else "FAIL", what])
	if not cond:
		_failed.append(what)


func _has_control() -> bool:
	var p := _player()
	return p != null and not p.cutscene_locked and not Director.playing and not Director.is_input_locked()


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _button(pad: Node, action: StringName) -> Control:
	for n in pad.find_children("*", "Panel", true, false):
		if n.has_meta("action") and StringName(n.get_meta("action")) == action and not bool(n.get_meta("pause", false)):
			return n as Control
	return null


func _pause_button(pad: Node) -> Control:
	for n in pad.find_children("*", "Panel", true, false):
		if bool(n.get_meta("pause", false)):
			return n as Control
	return null


## Window-pixel centre of a control, through its canvas layer and the root stretch.
func _center(c: Control) -> Vector2:
	var xf := c.get_viewport().get_final_transform() * c.get_global_transform_with_canvas()
	return xf * (c.size * 0.5)


func _touch(pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = _touch_index
	ev.position = pos
	ev.pressed = down
	Input.parse_input_event(ev)


func _tap(pos: Vector2, hold_s: float) -> void:
	_touch(pos, true)
	await _seconds(hold_s)
	_touch(pos, false)
	_touch_index = 1 + (_touch_index % 4)
	await get_tree().process_frame


func _hold(pos: Vector2, hold_s: float, mid: Callable = Callable()) -> void:
	_touch(pos, true)
	await _seconds(hold_s * 0.5)
	if mid.is_valid():
		mid.call()
	await _seconds(hold_s * 0.5)
	_touch(pos, false)
	_touch_index = 1 + (_touch_index % 4)
	await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_out, _tag, name])


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _until(pred: Callable, timeout_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _wait_node(node_name: String, timeout_s: float) -> Node:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end:
		var n := get_tree().root.find_child(node_name, true, false)
		if n != null:
			return n
		await get_tree().process_frame
	return null
