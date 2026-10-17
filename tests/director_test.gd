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
