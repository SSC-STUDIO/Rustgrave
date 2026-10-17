extends TestCase
## Director: step order, skip, and a hard rule — never touch Engine.time_scale.


func setup() -> void:
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	Engine.time_scale = 1.0


func teardown() -> void:
	Director.abort()
	Director.resume()
	Engine.time_scale = 1.0


func test_empty_play_finishes_immediately() -> void:
	Director.play([])
	await flush(2)
	ok(not Director.playing, "empty script finishes")
	ok(not Director.is_input_locked())


func test_wait_then_unlock_releases_lock() -> void:
	Director.play([
		{"kind": "lock"},
		{"kind": "wait", "seconds": 0.05},
		{"kind": "unlock"},
	])
	ok(Director.playing)
	ok(Director.is_input_locked())
	var done := await wait_until(func() -> bool: return not Director.playing, 90)
	ok(done, "wait step elapsed")
	ok(not Director.is_input_locked())


func test_skip_advances_long_wait() -> void:
	Director.play([
		{"kind": "wait", "seconds": 8.0},
		{"kind": "unlock"},
	])
	await flush(2)
	Director.skip_step()
	var done := await wait_until(func() -> bool: return not Director.playing, 40)
	ok(done, "skip ended the long wait")


func test_play_does_not_touch_time_scale() -> void:
	Engine.time_scale = 1.0
	Director.play([
		{"kind": "wait", "seconds": 0.02},
		{"kind": "caption", "text": "test", "hold": 0.02},
		{"kind": "unlock"},
	])
	eq(Engine.time_scale, 1.0, "play start leaves time_scale")
	await wait_until(func() -> bool: return not Director.playing, 90)
	eq(Engine.time_scale, 1.0, "play finish leaves time_scale")


func test_play_queues_second_script() -> void:
	var kinds: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		kinds.append(String(step.get("kind", "")))
	Director.step_started.connect(on_step)
	Director.play([{"kind": "wait", "seconds": 8.0}])
	Director.play([{"kind": "lock"}, {"kind": "unlock"}])
	ok(Director.playing, "first script still playing")
	ok(kinds.has("wait"), "first script started")
	Director.skip_step()
	var done := await wait_until(func() -> bool: return not Director.playing, 60)
	ok(done, "both queued scripts finished")
	ok(kinds.has("lock"), "second script ran after the first")
	Director.step_started.disconnect(on_step)


func test_fade_to_queues_latest_target() -> void:
	Director.last_fade_target = ""
	Director.fade_to("res://scenes/ui/TitleScreen.tscn")
	Director.fade_to("res://scenes/levels/TestArena.tscn")
	var done := await wait_until(func() -> bool: return not Director.is_fading(), 120)
	ok(done, "fade finished")
	eq(Director.last_fade_target, "res://scenes/levels/TestArena.tscn", "second fade_to wins")


func test_play_runs_two_queued_scripts_in_order() -> void:
	var kinds: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		kinds.append(String(step.get("kind", "")))
	Director.step_started.connect(on_step)
	Director.play([{"kind": "wait", "seconds": 8.0}])
	Director.play([{"kind": "lock"}])
	Director.play([{"kind": "sfx", "id": "ui_select"}])
	Director.skip_step()
	var done := await wait_until(func() -> bool: return not Director.playing, 80)
	ok(done, "queued scripts finished")
	ok(kinds.has("wait") and kinds.has("lock") and kinds.has("sfx"), "all three scripts ran")
	var wait_i := kinds.find("wait")
	var lock_i := kinds.find("lock")
	var sfx_i := kinds.find("sfx")
	ok(wait_i >= 0 and lock_i > wait_i and sfx_i > lock_i, "queue order preserved")
	Director.step_started.disconnect(on_step)


func test_play_keeps_fourth_queued_script() -> void:
	var kinds: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		kinds.append(String(step.get("kind", "")))
	Director.step_started.connect(on_step)
	Director.play([{"kind": "lock"}, {"kind": "wait", "seconds": 8.0}])
	Director.play([{"kind": "lock"}])
	Director.play([{"kind": "sfx", "id": "ui_select"}])
	Director.play([{"kind": "unlock"}])
	Director.play([{"kind": "tag_fourth"}])
	ok(Director.is_input_locked(), "first script holds the lock across the queue")
	Director.skip_step()
	var done := await wait_until(func() -> bool: return not Director.playing, 80)
	ok(done, "four queued scripts plus the live one finished")
	ok(kinds.has("wait") and kinds.has("lock") and kinds.has("sfx"), "early scripts ran")
	ok(kinds.has("unlock") and kinds.has("tag_fourth"), "fourth queued script was not dropped")
	ok(not Director.is_input_locked(), "lock released after the whole queue")
	Director.step_started.disconnect(on_step)


func test_play_overflow_drops_oldest_queued() -> void:
	var kinds: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		kinds.append(String(step.get("kind", "")))
	Director.step_started.connect(on_step)
	Director.play([{"kind": "wait", "seconds": 8.0}])
	Director.play([{"kind": "old_0"}])
	for i in range(1, Director.PLAY_QUEUE_MAX):
		Director.play([{"kind": "keep_%d" % i}])
	Director.play([{"kind": "newest"}])
	Director.skip_step()
	var done := await wait_until(func() -> bool: return not Director.playing, 80)
	ok(done, "overflowed queue drained")
	ok(not kinds.has("old_0"), "oldest queued script was dropped")
	ok(kinds.has("newest"), "newest script still ran")
	ok(kinds.has("keep_%d" % (Director.PLAY_QUEUE_MAX - 1)), "later queued scripts kept")
	Director.step_started.disconnect(on_step)


func test_letterbox_opens_during_play_and_closes() -> void:
	Director.set_letterbox(false, true)
	almost(Director.letterbox_amount(), 0.0, 0.01)
	Director.play([{"kind": "wait", "seconds": 2.0}])
	Director._tick_letterbox(0.4)
	ok(Director.letterbox_amount() > 0.4, "play opens the bars")
	Director.abort()
	Director.set_letterbox(false, true)
	almost(Director.letterbox_amount(), 0.0, 0.01, "abort clears the bars")


func test_skip_to_end_unlocks_and_keeps_the_queued_script() -> void:
	var kinds: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		kinds.append(String(step.get("kind", "")))
	Director.step_started.connect(on_step)
	Director.play([
		{"kind": "lock"},
		{"kind": "wait", "seconds": 8.0},
		{"kind": "unlock"},
	], true)
	Director.play([{"kind": "sfx", "id": "ui_select"}])
	ok(Director.is_input_locked(), "skippable script still locks")
	Director.skip_step()
	var done := await wait_until(func() -> bool: return not Director.playing, 40)
	ok(done, "one skip ended the long script and the queued one")
	ok(not Director.is_input_locked(), "skip-to-end clears the lock")
	ok(kinds.has("lock") and kinds.has("sfx"), "queued script still ran")
	ok(not kinds.has("unlock"), "the rest of the skipped script did not play")
	Director.step_started.disconnect(on_step)


func test_fx_step_waits_then_finishes() -> void:
	Director.play([
		{"kind": "fx", "id": "shock_ring", "seconds": 0.05},
		{"kind": "fx", "id": "not_a_real_fx", "seconds": 0.05},
	])
	ok(Director.playing, "fx step holds the script")
	var done := await wait_until(func() -> bool: return not Director.playing, 90)
	ok(done, "known and unknown fx ids both advance")


## The whole piece freezes together while paused or suspended — including the letterbox,
## which used to keep crawling in the background while the player was in the menu.
func test_letterbox_freezes_with_the_rest_of_the_piece() -> void:
	Director.set_letterbox(false, true)
	almost(Director.letterbox_amount(), 0.0, 0.01, "bars start closed")
	# A wait long enough that the piece is still inside it for the whole test; play()
	# opens the bars and locks input in the same call, before any frame runs.
	Director.play([{"kind": "lock"}, {"kind": "wait", "seconds": 30.0}])
	ok(Director.is_input_locked(), "play locks input immediately")
	# _process is the only caller of _tick_letterbox, so the bars move only on frames.
	# A single small tick opens them part-way (LETTER_SPEED * delta per call).
	Director._tick_letterbox(0.05)
	var mid := Director.letterbox_amount()
	ok(mid > 0.05 and mid < 1.0, "the bars open part-way (%.2f)" % mid)

	# Paused: the bars must hold still. process_frame (not physics_frame) is what runs
	# while the tree is paused, and _process is skipped there.
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	var held := Director.letterbox_amount()
	almost(held, mid, 0.02, "paused: the bars hold where they are")
	ok(Director.playing, "a paused tree still owns the piece")
	ok(Director.is_input_locked(), "and still owns the input")

	get_tree().paused = false
	await get_tree().process_frame
	var after_pause := Director.letterbox_amount()
	ok(after_pause > held, "the bars keep opening after the pause (%.2f -> %.2f)" % [held, after_pause])
	ok(Director.playing, "the piece resumes when the pause lifts")

	# Suspended: same contract, without the tree's pause.
	Director.suspend()
	await get_tree().process_frame
	await get_tree().process_frame
	almost(Director.letterbox_amount(), after_pause, 0.02, "suspended: the bars hold too")
	Director.resume()
	await get_tree().process_frame
	ok(Director.letterbox_amount() > after_pause, "resume lets the bars move again")

	Director.abort()
	Director.set_letterbox(false, true)
	almost(Director.letterbox_amount(), 0.0, 0.01, "abort clears the bars")
	ok(not Director.is_input_locked(), "abort gives the input back")
	ok(not get_tree().paused, "the test leaves the tree running")


## A scene change or a death uses reset_view, which must be stronger than abort:
## input, camera, caption, letterbox, hint, tableau and time effects all restored in
## the same frame — no bars receding behind the death overlay, no stale lock in the
## next level.
func test_reset_view_restores_everything_in_one_frame() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -1))
	var cam := GameCamera.new()
	arena.add_child(cam)
	Director.set_letterbox(false, true)
	Director.play([
		{"kind": "lock"},
		{"kind": "tableau", "id": "boss", "title": "炉约刽子手", "subtitle": "守 芯 者"},
		{"kind": "cam_focus", "target": Vector2(180, 200), "zoom": 1.6, "duration": 0.05},
		{"kind": "caption", "text": "这一行不该留在屏幕上。", "hold": 8.0},
		{"kind": "unlock"},
	])
	await flush(10)
	ok(Director.is_input_locked(), "the piece locks the knight")
	ok(player.cutscene_locked, "the player is held")
	ok(cam._focused, "the camera is directed")
	ok(Director.letterbox_amount() > 0.0, "the bars are up")
	ok(Director.caption().is_busy(), "a caption is on screen")
	ok(Director.get_node("CinematicPresentation").active_shot == "boss", "a card is up")

	Director.reset_view()
	ok(not Director.playing, "no script survives reset_view")
	ok(not Director.is_input_locked(), "input is back")
	ok(not player.cutscene_locked, "the knight is released")
	ok(not cam._focused, "the camera is handed back")
	almost(cam.zoom.x, GameCamera.ZOOM, 0.001, "zoom is back at 1x")
	almost(Director.letterbox_amount(), 0.0, 0.001, "the bars close in the same frame")
	ok(not Director.caption().is_busy(), "the caption is cleared")
	ok(not Director.get_node("CinematicPresentation").front.visible, "the card is gone")
	ok(not Director.get_node("CinematicPresentation").hint_visible(), "no hint survives")
	eq(Director.pending_scripts(), 0, "nothing is left queued")
	cam.queue_free()
	arena.queue_free()


## reset_view also drops a script that never got a clear moment to start (fade, pause,
## choice menu), so a deferred opening cannot lock the next scene.
func test_reset_view_drops_a_deferred_script() -> void:
	get_tree().paused = true
	Director.play_when_clear([
		{"kind": "lock"},
		{"kind": "wait", "seconds": 30.0},
	])
	eq(Director.pending_scripts(), 1, "the script waits for a clear moment")
	ok(not Director.playing, "and has not started")
	Director.reset_view()
	eq(Director.pending_scripts(), 0, "reset_view dropped the deferred script")
	get_tree().paused = false
	await get_tree().process_frame
	ok(not Director.playing, "it does not start after the pause lifts")
	ok(not Director.is_input_locked(), "and never took the input")
