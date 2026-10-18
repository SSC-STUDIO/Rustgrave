extends Node
## Director autoload: fade transitions + sequenced cutscenes.
## Never sets Engine.time_scale itself: freeze / slow-mo fx go through Juice, and the
## only write we make is putting our own still-running freeze back to 1.0 when a
## script is skipped or aborted. Pause hangs us via suspend() / tree.paused,
## not by us setting paused ourselves.
##
## Step kinds: lock unlock wait tableau caption cam_focus cam_release letterbox sfx fx anim.
## fx ids: ember_rise ash_fall heart_pulse shock_ring rust_flake dust_puff plant bell_ring
##   grave_answer core_ring boss_roar phase_flash shake flash freeze slowmo.

signal finished
## Every script end that is not an abort (natural end or skip), including the ones
## followed by a queued script. `finished` only fires when the queue runs dry.
signal script_finished
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
## 等一个干净时机再开的剧本（开场、章节到达）。见 play_when_clear。
var _deferred: Array = []
## cam_release 先把推近的镜头缓回 1x，等这一步的等待结束再真正交还。
var _release_pending: bool = false
## 本剧本发起的冻帧 / 慢动作的墙钟终点；跳过或中断时只复位还在跑的那一次。
var _time_fx_until_ms: int = 0
const LETTER_BAR := 32.0
const LETTER_SPEED := 3.4


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	add_child(preload("res://scripts/ui/cinematic_presentation.gd").new())
	add_child(preload("res://scripts/ui/story_stage.gd").new())


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
	# Captions and cinematic bars belong to the game picture, not the window: in a
	# window that is not an integer multiple of 640x360 (e.g. 960x540) they used to sit
	# in the black margin under the world image. The fade stays full-window.
	PresentationMetrics.bind_layer(_caption_layer)
	PresentationMetrics.bind_layer(_letter_layer)


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


## Rough running time of a script in seconds: waits, fx, camera moves, timed cards and
## captions (typing + hold). Freezes and skips are not counted. Tests hold each cinematic
## to its budget with it.
func estimate_seconds(script: Array) -> float:
	var total := 0.0
	for raw in script:
		var step := _as_step(raw)
		match _kind_of(step):
			"wait":
				total += _seconds_of(step)
			"fx":
				total += float(step.get("seconds", 0.6))
			"cam_focus":
				total += float(step.get("duration", 0.8))
			"cam_release":
				total += float(step.get("duration", 0.35))
			"letterbox":
				total += float(step.get("duration", 0.28))
			"tableau":
				total += float(step.get("seconds", 0.0))
			"caption":
				var text := String(step.get("text", ""))
				total += float(text.length()) / Caption.CHARS_PER_SEC 						+ float(step.get("hold", Caption.DEFAULT_HOLD))
	return total


## Scripts waiting behind the live one. Zero after abort(); tests read it.
func pending_scripts() -> int:
	return _script_queue.size() + _deferred.size()


func is_test_runner() -> bool:
	return _is_test_runner()


## One-line control hint over the world (the opening's move prompt). It hides on the
## first gameplay input, on timeout, on death, on abort and when a scene change starts.
func show_hint(text: String, seconds: float = 14.0) -> void:
	var presentation := get_node_or_null("CinematicPresentation")
	if presentation != null:
		presentation.show_hint(text, seconds)


func hide_hint() -> void:
	var presentation := get_node_or_null("CinematicPresentation")
	if presentation != null:
		presentation.hide_hint()


## fade_to(scene) or fade_to(scene, duration_seconds). Always fades to black.
## 正在淡变时不丢第二次请求：只保留最后一个目标，当前淡出结束后切过去。
func fade_to(scene: String, duration: float = FADE_DEFAULT) -> void:
	# 切场必须掐掉进行中的过场，否则 lock/字幕会跟着 Autoload 进下一幕。
	abort()
	# Back at the title the play session is over: New Game and Continue start from
	# the save alone, with no "already seen this session" memory (see StoryStage.once).
	if scene.get_file() == "TitleScreen.tscn":
		StoryStage.forget()
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
	# 回火试炼：不播章节卡 / 间幕 / 出口字幕等剧本；Boss 名号走 GameEvents +
	# CinematicPresentation，不经过这里，所以仍然保留（契约 §5）。
	if TrialRun.suppresses_cinematics():
		return
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


## Start `script` as soon as nothing blocks it: tree not paused, Director not suspended,
## no scene fade (in or out) and no choice menu open. The opening and the chapter
## arrivals are kicked off in the very frame a scene finishes loading — possibly in the
## middle of the fade, or with the pause menu open on top of it; a script started then
## would sit suspended and locked inside a level nobody can unpause. `on_start` runs
## right before the first step. abort() drops anything still waiting.
func play_when_clear(script: Array, skip_to_end: bool = false, on_start: Callable = Callable()) -> void:
	if TrialRun.suppresses_cinematics():
		return
	if _clear_to_start():
		if on_start.is_valid():
			on_start.call()
		play(script, skip_to_end)
		return
	_deferred.append({"script": script.duplicate(), "skip": skip_to_end, "on_start": on_start})


func _clear_to_start() -> bool:
	if not is_inside_tree():
		return false
	return not get_tree().paused and not _suspended and not _fading and not choice_hold


func _start_deferred() -> void:
	var item: Dictionary = _deferred.pop_front()
	var on_start: Callable = item.get("on_start", Callable())
	if on_start.is_valid():
		on_start.call()
	play(item["script"] as Array, bool(item["skip"]))


func is_aborting() -> bool:
	return _aborting


func skip_step() -> void:
	if not playing or _suspended or get_tree().paused:
		return
	if _skip_to_end:
		var cam := _camera()
		if cam != null:
			cam.release()
		_release_pending = false
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
	_release_pending = false
	_clear_time_effects()
	if _caption != null:
		_caption.clear()
	_queue.clear()
	_script_queue.clear()
	var dropped := not _deferred.is_empty()
	_deferred.clear()
	_index = -1
	_waiting = false
	_wait_kind = ""
	set_letterbox(false)
	var was := playing
	playing = false
	# Scripts that were still waiting for a clear moment end here too; listeners that
	# prepared the scene for them (the opening's prone knight) must get to undo it.
	if was or dropped:
		finished.emit()
	_aborting = false


## Hard reset for a scene change or a death: nothing may own the screen afterwards.
## abort() already releases the lock/camera/caption, but it lets the bars recede over
## a few frames; here they close instantly so the death overlay or the next chapter
## card starts from a clean composition. Idempotent, and safe with no script running.
func reset_view() -> void:
	abort()
	set_letterbox(false, true)
	hide_hint()
	if _caption != null:
		_caption.clear()
	var cam := _camera()
	if cam != null:
		cam.release()
	_clear_time_effects()
	_skip_to_end = false
	_release_pending = false


func _unhandled_input(event: InputEvent) -> void:
	if not playing or _suspended or get_tree().paused:
		return
	if event.is_action_pressed("ui_accept"):
		skip_step()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# 暂停 / 挂起时整条演出（含遮幅的收放）一起冻住：过场中间按下暂停，
	# 黑边不许在玩家背后继续爬。
	if _suspended or get_tree().paused:
		return
	_tick_letterbox(delta)
	if not _deferred.is_empty() and _clear_to_start():
		_start_deferred()
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


## One-off fx from code (the opening's grave answers, the forge pulse) with the same
## ids as the fx step, no script needed. Inert headless like the step.
func play_fx(id: String, target: Variant = null) -> void:
	_play_fx_step({"id": id, "target": target})


func _play_fx_step(step: Dictionary) -> void:
	var id := String(step.get("id", ""))
	# Freeze / slow-mo are only Juice's wall-clock timer, so they resolve (and reset)
	# deterministically headless too. Everything else is visual and stays inert there.
	if id == "freeze" or id == "slowmo":
		var ms := int(step.get("ms", 400 if id == "freeze" else 600))
		_time_fx_until_ms = maxi(_time_fx_until_ms, Time.get_ticks_msec() + ms)
		if id == "freeze":
			Juice.hit_stop(ms, float(step.get("scale", 0.05)))
		else:
			Juice.slow_mo(ms, float(step.get("scale", 0.25)))
		return
	if DisplayServer.get_name() == "headless":
		return
	var pos := _fx_anchor()
	var target = step.get("target")
	if typeof(target) == TYPE_OBJECT and is_instance_valid(target) and target is Node2D:
		pos = (target as Node2D).global_position
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
		"rust_flake":
			# 锈片从甲和剑上剥落，慢慢往下掉。
			for _i in 3:
				Fx.burst(&"rust", pos + Vector2(randf_range(-14.0, 14.0), randf_range(-52.0, -10.0)), PI * 0.5)
			Fx.burst(&"dust", pos + Vector2(randf_range(-10.0, 10.0), -34.0), PI * 0.5)
		"dust_puff":
			Fx.dust_puff(pos + Vector2(0.0, -2.0))
		"plant":
			# 剑尖杵进地里：两侧扬灰 + 一下很轻的震。
			Fx.dust_puff(pos + Vector2(-12.0, -2.0), PI)
			Fx.dust_puff(pos + Vector2(12.0, -2.0), 0.0)
			Juice.shake(float(step.get("shake", 1.8)), 200)
		"bell_ring":
			# 地下的一声钟：冲击环 + 震 + 顶上落灰；剑背上的火星跳一下，像剑里有人应声。
			Fx.burst(&"ring", pos + Vector2(0.0, -24.0))
			Fx.burst(&"spark", pos + Vector2(-8.0, -34.0), -PI * 0.5)
			Juice.shake(float(step.get("shake", 3.0)), 420)
			for _i in 2:
				Fx.burst(&"dust", pos + Vector2(randf_range(-70.0, 70.0), -96.0), PI * 0.5)
		"grave_answer":
			# 坟回应：一缕冷灰带着火星往上冒，坟头亮一下又暗下去。
			Fx.burst(&"dust", pos + Vector2(0.0, -4.0), -PI * 0.5)
			Fx.burst(&"dust", pos + Vector2(-5.0, -10.0), -PI * 0.5 - 0.35)
			Fx.burst(&"spark", pos + Vector2(randf_range(-6.0, 6.0), -14.0), -PI * 0.5)
			Fx.burst(&"spark", pos + Vector2(randf_range(-6.0, 6.0), -20.0), -PI * 0.5)
			CineFx.glow_pulse(self, pos + Vector2(0.0, -14.0), Color(0.78, 0.84, 1.0, 0.55), 0.9, 0.85)
		"core_ring":
			Fx.burst(&"ring", pos + Vector2(0.0, -24.0))
			Fx.burst(&"spark", pos + Vector2(0.0, -26.0), -PI * 0.5)
		"boss_roar":
			Fx.burst(&"ring", pos + Vector2(0.0, -30.0))
			Fx.hit_sparks(pos + Vector2(0.0, -40.0))
			Juice.shake(float(step.get("shake", 4.5)), 380)
			Juice.flash(Color(0.86, 0.2, 0.12, 0.3), 220)
		"phase_flash":
			Fx.burst(&"ring", pos + Vector2(0.0, -30.0))
			Juice.shake(float(step.get("shake", 5.0)), 360)
			Juice.flash(Color(0.9, 0.16, 0.1, 0.42), 240)
		"shake":
			Juice.shake(float(step.get("px", 3.0)), int(step.get("ms", 300)))
		"flash":
			var tint = step.get("color", Color(1.0, 1.0, 1.0, 0.5))
			Juice.flash(tint if tint is Color else Color(1.0, 1.0, 1.0, 0.5), int(step.get("ms", 160)))
		_:
			pass


## 目标被释放（场景已换）或没给时退回骑士，镜头不会对着悬空对象锁死。
func _focus_target(raw: Variant) -> Variant:
	if raw is Vector2:
		return raw
	if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is Node2D:
		return raw
	var tree := get_tree()
	var player: Node2D = null
	if tree != null:
		player = tree.get_first_node_in_group("player") as Node2D
	if player != null:
		return player
	var cam := _camera()
	return cam.global_position if cam != null else Vector2.ZERO


func _clear_time_effects() -> void:
	if Time.get_ticks_msec() < _time_fx_until_ms and Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	_time_fx_until_ms = 0


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
				cam.focus(_focus_target(step.get("target")), float(step.get("zoom", GameCamera.ZOOM)), dur)
			_begin_wait(dur, "cam")
		"cam_release":
			var cam := _camera()
			var dur := float(step.get("duration", 0.35))
			if cam != null:
				if absf(cam.zoom.x - GameCamera.ZOOM) > 0.03 and dur > 0.06:
					# release() snaps zoom back to 1x. Ease it home first, then hand over.
					cam.focus(_focus_target(null), GameCamera.ZOOM, dur / 3.0)
					_release_pending = true
				else:
					cam.release()
			_begin_wait(dur, "cam")
		"letterbox":
			set_letterbox(bool(step.get("on", true)), bool(step.get("instant", false)))
			_begin_wait(float(step.get("duration", 0.28)), "letterbox")
		"sfx":
			var sfx_id := StringName(step.get("id", "ui_select"))
			if step.has("db"):
				Sfx.play(sfx_id, float(step.get("jitter", 0.08)), float(step["db"]))
			else:
				Sfx.play(sfx_id)
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
	if _release_pending:
		_release_pending = false
		var cam := _camera()
		if cam != null:
			cam.release()
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
	_release_pending = false
	_clear_time_effects()
	script_finished.emit()
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
