extends Node
## Director autoload: fade transitions + sequenced cutscenes.
## Never touches Engine.time_scale. Pause hangs us via suspend() / tree.paused,
## not by us setting paused ourselves.

signal finished
signal step_started(index: int, step: Dictionary)
signal step_finished(index: int, step: Dictionary)

const FADE_DEFAULT := 0.45
## 进行中的剧本之外还能再排这么多条。满了丢掉最旧的并打日志，避免故事监听静默丢过场。
const PLAY_QUEUE_MAX := 8

var playing: bool = false
## 结局选择层打开时为 true：暂停菜单忽略 Esc，关掉后也不解 tree.paused。
var choice_hold: bool = false
## 最近一次 fade_to 实际采用的目标（含排队覆盖）。测试可读。
var last_fade_target: String = ""

var _locked: bool = false
var _suspended: bool = false
var _queue: Array = []
var _script_queue: Array = []
var _index: int = -1
var _waiting: bool = false
var _wait_kind: String = ""
var _step_timer: float = 0.0
var _fading: bool = false
var _queued_fade_path: String = ""
var _queued_fade_duration: float = FADE_DEFAULT
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _caption_layer: CanvasLayer
var _caption: Caption
var _fade_tween: Tween
var _letter_layer: CanvasLayer
var _letter_top: ColorRect
var _letter_bot: ColorRect
var _letter_amount: float = 0.0
var _letter_target: float = 0.0
## play(..., true) 时，一次 ui_accept 结束当前这条剧本并解锁，队列里的下一条照常接上。
var _skip_to_end: bool = false
var _script_skip_queue: Array = []
var _aborting: bool = false
const LETTER_BAR := 32.0
const LETTER_SPEED := 3.4


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	add_child(preload("res://scripts/ui/cinematic_presentation.gd").new())


func _build_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "DirectorFade"
	_fade_layer.layer = 100
	_fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)

	_caption_layer = CanvasLayer.new()
	_caption_layer.name = "DirectorCaption"
	_caption_layer.layer = 12
	add_child(_caption_layer)
	_caption = Caption.new()
	_caption.name = "Caption"
	_caption_layer.add_child(_caption)
	_letter_layer = CanvasLayer.new()
	_letter_layer.name = "DirectorLetterbox"
	_letter_layer.layer = 11
	_letter_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_letter_layer)
	_letter_top = _make_bar(true)
	_letter_bot = _make_bar(false)
	_letter_layer.add_child(_letter_top)
	_letter_layer.add_child(_letter_bot)
	WorldClock.isolate_ui_layer(_fade_layer)
	WorldClock.isolate_ui_layer(_caption_layer)
	WorldClock.isolate_ui_layer(_letter_layer)


func _make_bar(top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 1)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	if top:
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
	else:
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
	return bar


func set_letterbox(on: bool, instant: bool = false) -> void:
	_letter_target = 1.0 if on else 0.0
	if instant:
		_letter_amount = _letter_target
		_apply_letterbox()


func letterbox_amount() -> float:
	return _letter_amount


func _tick_letterbox(delta: float) -> void:
	_letter_amount = move_toward(_letter_amount, _letter_target, delta * LETTER_SPEED)
	_apply_letterbox()


func _apply_letterbox() -> void:
	if _letter_top == null or _letter_bot == null:
		return
	var h := LETTER_BAR * _letter_amount
	_letter_top.offset_bottom = h
	_letter_bot.offset_top = -h
	_letter_top.visible = h > 0.2
	_letter_bot.visible = h > 0.2


func caption() -> Caption:
	return _caption


func is_input_locked() -> bool:
	return _locked


func is_suspended() -> bool:
	return _suspended


func skips_whole_script() -> bool:
	return _skip_to_end


func suspend() -> void:
	_suspended = true


func resume() -> void:
	_suspended = false


func is_fading() -> bool:
	return _fading


## fade_to(scene) or fade_to(scene, duration_seconds). Always fades to black.
## 正在淡变时不丢第二次请求：只保留最后一个目标，当前淡出结束后切过去。
func fade_to(scene: String, duration: float = FADE_DEFAULT) -> void:
	# 切场必须掐掉进行中的过场，否则 lock/字幕会跟着 Autoload 进下一幕。
	abort()
	if _fading:
		_queued_fade_path = scene
		_queued_fade_duration = duration
		return
	_fading = true
	_fade.color = Color(0, 0, 0, _fade.color.a)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if DisplayServer.get_name() == "headless":
		# 留一帧给紧随其后的第二次 fade_to 排队，避免测试里同步跑完。
		await get_tree().process_frame
		_on_fade_out_done(scene, duration)
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = _fade_layer.create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade, "color:a", 1.0, maxf(0.05, duration))
	_fade_tween.tween_callback(_on_fade_out_done.bind(scene, duration))


func fade_in(duration: float = FADE_DEFAULT) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if _fade.color.a < 0.01:
		_fade.color.a = 1.0
	if DisplayServer.get_name() == "headless":
		_fade.color.a = 0.0
		_on_fade_in_done()
		return
	_fade_tween = _fade_layer.create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade, "color:a", 0.0, maxf(0.05, duration))
	_fade_tween.tween_callback(_on_fade_in_done)


## skip_to_end：这一条剧本接受一次 ui_accept 就跳到结尾并解锁。默认仍是逐拍跳过。
func play(script: Array, skip_to_end: bool = false) -> void:
	if playing:
		if _script_queue.size() >= PLAY_QUEUE_MAX:
			var dropped: Array = _script_queue.pop_front()
			if not _script_skip_queue.is_empty():
				_script_skip_queue.pop_front()
			push_warning("Director: play queue full (%d), dropped oldest script (%d steps)" \
					% [PLAY_QUEUE_MAX, dropped.size()])
		_script_queue.append(script.duplicate())
		_script_skip_queue.append(skip_to_end)
		return
	_skip_to_end = skip_to_end
	_queue = script.duplicate()
	_index = -1
	playing = true
	_waiting = false
	_wait_kind = ""
	set_letterbox(true)
	_advance()


func is_aborting() -> bool:
	return _aborting


func skip_step() -> void:
	if not playing or _suspended or get_tree().paused:
		return
	if _skip_to_end:
		var cam := _camera()
		if cam != null:
			cam.release()
		if _caption != null:
			_caption.clear()
		_waiting = false
		_wait_kind = ""
		_queue.clear()
		_finish_play()
		return
	if _wait_kind == "caption" and _caption != null and _caption.is_busy():
		_caption.skip()
		if _caption.is_busy():
			_caption.skip()
		return
	if _waiting:
		_step_timer = 0.0
		_complete_wait()


func abort() -> void:
	_aborting = true
	var presentation := get_node_or_null("CinematicPresentation")
	if presentation != null:
		presentation.dismiss(true)
	_skip_to_end = false
	_script_skip_queue.clear()
	_set_lock(false)
	var cam := _camera()
	if cam != null:
		cam.release()
	if _caption != null:
		_caption.clear()
	_queue.clear()
	_script_queue.clear()
	_index = -1
	_waiting = false
	_wait_kind = ""
	set_letterbox(false)
	var was := playing
	playing = false
	if was:
		finished.emit()
	_aborting = false


func _unhandled_input(event: InputEvent) -> void:
	if not playing or _suspended or get_tree().paused:
		return
	if event.is_action_pressed("ui_accept"):
		skip_step()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tick_letterbox(delta)
	if _suspended or get_tree().paused:
		return
	if not playing or not _waiting:
		return
	if _wait_kind == "caption":
		if _caption == null or not _caption.is_busy():
			_complete_wait()
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_complete_wait()


func _advance() -> void:
	_index += 1
	if _index >= _queue.size():
		_finish_play()
		return
	var step := _as_step(_queue[_index])
	step_started.emit(_index, step)
	_run_step(step)


func _as_step(raw) -> Dictionary:
	if raw is Dictionary:
		return raw
	return {"kind": String(raw)}


func _kind_of(step: Dictionary) -> String:
	return String(step.get("kind", step.get("op", "")))


func _seconds_of(step: Dictionary, fallback: float = 0.3) -> float:
	return float(step.get("seconds", step.get("sec", fallback)))


func _play_fx_step(step: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var id := String(step.get("id", ""))
	var pos := _fx_anchor()
	var target = step.get("target")
	if target is Node2D and is_instance_valid(target):
		pos = target.global_position
	elif target is Vector2:
		pos = target
	match id:
		"ember_rise":
			for _i in 4:
				Fx.burst(&"spark", pos + Vector2(randf_range(-36.0, 36.0), randf_range(0.0, 16.0)), -PI * 0.5)
		"ash_fall":
			for _i in 4:
				Fx.burst(&"dust", pos + Vector2(randf_range(-40.0, 40.0), -24.0), PI * 0.5)
				Fx.burst(&"rust", pos + Vector2(randf_range(-20.0, 20.0), -12.0), PI * 0.5)
		"heart_pulse":
			Fx.burst(&"ring", pos + Vector2(0.0, -16.0))
			Juice.flash(Color(1.0, 0.46, 0.22, 0.34), 160)
		"shock_ring":
			Fx.burst(&"ring", pos)
		_:
			pass


func _fx_anchor() -> Vector2:
	var tree := get_tree()
	if tree == null:
		return Vector2.ZERO
	var player := tree.get_first_node_in_group("player") as Node2D
	if player != null:
		return player.global_position
	var cam := _camera()
	if cam != null:
		return cam.global_position
	return Vector2.ZERO


func _run_step(step: Dictionary) -> void:
	var kind := _kind_of(step)
	match kind:
		"lock":
			_set_lock(true)
			_finish_step(step)
			_advance()
		"unlock":
			_set_lock(false)
			_finish_step(step)
			_advance()
		"wait":
			_begin_wait(_seconds_of(step), "wait")
		"tableau":
			# Presentation listens to step_started. Timed cards retain the same
			# lock, pause and skip semantics as the rest of the Director sequence.
			if step.has("seconds"):
				_begin_wait(_seconds_of(step), "tableau")
			else:
				_finish_step(step)
				_advance()
		"caption":
			if _caption != null:
				_caption.enqueue(String(step.get("text", "")),
						float(step.get("hold", Caption.DEFAULT_HOLD)))
			_begin_wait(0.0, "caption")
		"cam_focus":
			var cam := _camera()
			var dur := float(step.get("duration", 0.8))
			if cam != null:
				cam.focus(step.get("target"), float(step.get("zoom", GameCamera.ZOOM)), dur)
			_begin_wait(dur, "cam")
		"cam_release":
			var cam := _camera()
			var dur := float(step.get("duration", 0.35))
			if cam != null:
				cam.release()
			_begin_wait(dur, "cam")
		"letterbox":
			set_letterbox(bool(step.get("on", true)), bool(step.get("instant", false)))
			_begin_wait(float(step.get("duration", 0.28)), "letterbox")
		"sfx":
			Sfx.play(StringName(step.get("id", "ui_select")))
			_finish_step(step)
			_advance()
		"fx":
			_play_fx_step(step)
			_begin_wait(float(step.get("seconds", 0.6)), "fx")
		"anim":
			_play_anim(step)
			_begin_wait(_seconds_of(step, 0.2), "anim")
		_:
			_finish_step(step)
			_advance()


func _begin_wait(sec: float, kind: String) -> void:
	_waiting = true
	_wait_kind = kind
	_step_timer = maxf(0.0, sec)


func _complete_wait() -> void:
	if not playing:
		return
	_waiting = false
	_wait_kind = ""
	if _index >= 0 and _index < _queue.size():
		_finish_step(_as_step(_queue[_index]))
	_advance()


func _finish_step(step: Dictionary) -> void:
	step_finished.emit(_index, step)


func _finish_play() -> void:
	var presentation := get_node_or_null("CinematicPresentation")
	if presentation != null:
		presentation.dismiss()
	playing = false
	_waiting = false
	_wait_kind = ""
	_skip_to_end = false
	# 队列里还有下一条：保持 lock，避免两段过场之间漏一帧输入/灌毒/AI。
	if not _script_queue.is_empty():
		var next: Array = _script_queue.pop_front()
		var skip := false
		if not _script_skip_queue.is_empty():
			skip = bool(_script_skip_queue.pop_front())
		play(next, skip)
		return
	_set_lock(false)
	set_letterbox(false)
	finished.emit()


func _on_fade_out_done(scene: String, duration: float) -> void:
	var target := scene
	var dur := duration
	if _queued_fade_path != "":
		target = _queued_fade_path
		dur = _queued_fade_duration
		_queued_fade_path = ""
	last_fade_target = target
	if target != "" and not _is_test_runner():
		# Level01 must load inside GamePresentation (640×360 world).
		# Fading straight into the authored map uses the window as the
		# viewport and unrolls the whole graveyard beside a 1280px sky plate.
		get_tree().change_scene_to_file(GameContext.route_scene(target))
	fade_in(dur)


func _on_fade_in_done() -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fading = false
	if _queued_fade_path != "":
		var next := _queued_fade_path
		var next_dur := _queued_fade_duration
		_queued_fade_path = ""
		fade_to(next, next_dur)


func _is_test_runner() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	return String(scene.scene_file_path).ends_with("run_tests.tscn")


func _set_lock(locked: bool) -> void:
	_locked = locked
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null:
		player.cutscene_locked = locked


func _camera() -> GameCamera:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("game_camera") as GameCamera


func _play_anim(step: Dictionary) -> void:
	var node = step.get("node")
	var anim := String(step.get("name", ""))
	if node == null or anim == "" or not is_instance_valid(node):
		return
	if node is FrameAnimSprite:
		(node as FrameAnimSprite).play(anim, true)
	elif node.has_method("play"):
		node.play(anim)
