extends TestCase
## 新游戏开场：只播一次，不写结局，跳过会解锁，无头不报错。

const Opening := preload("res://scripts/levels/opening_cinematic.gd")


var _save_path := ""


func setup() -> void:
	_save_path = SaveData.save_path
	SaveData.save_path = "user://rustgrave_opening_test.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.ending = ""
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	Opening.reset()
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	Director.abort()
	Opening.reset()
	SaveData.delete_save()
	SaveData.save_path = _save_path
	SaveData.flags.clear()
	SaveData.ending = ""
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


func test_new_game_plays_lines_then_marks_seen_without_ending() -> void:
	var texts: Array[String] = []
	var fx_ids: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		if String(step.get("kind", "")) == "caption":
			texts.append(String(step.get("text", "")))
		elif String(step.get("kind", "")) == "fx":
			fx_ids.append(String(step.get("id", "")))
	Director.step_started.connect(on_step)
	var fx_children := Fx.get_child_count()
	ok(Opening.try_start(), "fresh new game starts the opening")
	ok(Director.playing)
	ok(Director.is_input_locked(), "opening locks input")
	eq(SaveData.ending, "")
	ok(not Opening.try_start(), "a second call while it plays does not replay")
	var done := await wait_until(func() -> bool: return not Director.playing, 1100)
	Director.step_started.disconnect(on_step)
	ok(done, "opening finished")
	ok(not Director.is_input_locked(), "finish clears the lock")
	eq(texts, Opening.LINES)
	eq(fx_ids, ["ash_fall"])
	ok(SaveData.has_flag(Opening.FLAG))
	eq(SaveData.flags.count(Opening.FLAG), 1)
	eq(SaveData.ending, "", "opening does not write an ending")
	ok(not SaveData.has_flag("game_complete"))
	ok(not Opening.try_start(), "finished opening does not replay")
	ok(not Director.playing)
	eq(Fx.burst_live_count(), 0, "headless ash_fall spawns nothing")
	eq(Fx.get_child_count(), fx_children, "headless fx step adds no nodes")


func test_skip_jumps_to_end_and_blocks_replay() -> void:
	ok(Opening.try_start())
	ok(Director.is_input_locked())
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Director._unhandled_input(event)
	ok(not Director.playing, "one ui_accept ends the opening")
	ok(not Director.is_input_locked(), "skip clears the lock")
	ok(not get_tree().paused)
	ok(SaveData.has_flag(Opening.FLAG), "skip counts as seen")
	eq(SaveData.ending, "")
	ok(not SaveData.has_flag("game_complete"))
	ok(not Opening.try_start(), "skipped opening does not replay")
	ok(not Director.playing)


func test_continue_checkpoint_and_wake_do_not_replay() -> void:
	var file := FileAccess.open(SaveData.save_path, FileAccess.WRITE)
	ok(file != null, "throwaway save opens")
	if file != null:
		file.store_line("opening-test")
		file.close()
	ok(SaveData.has_save())
	ok(not Opening.should_play(), "continue / existing save skips the opening")
	ok(not Opening.try_start())
	SaveData.delete_save()

	SaveData.entering_from_checkpoint = true
	ok(not Opening.try_start(), "death reload does not replay")
	SaveData.entering_from_checkpoint = false

	SaveData.pending_spawn = Vector2(12, 34)
	ok(not Opening.try_start(), "pending respawn does not replay")
	SaveData.pending_spawn = Vector2.INF

	SaveData.mark_flag("wake")
	ok(not Opening.try_start(), "already-awake chapter 1 does not replay")
	SaveData.flags.clear()

	SaveData.ending = "snuff"
	ok(not Opening.try_start(), "an ending already set does not replay")
	eq(SaveData.ending, "snuff", "the check does not clear or rewrite ending")
	SaveData.ending = ""
	ok(not Director.playing)


func test_wake_follows_opening_and_keeps_its_line() -> void:
	var texts: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		if String(step.get("kind", "")) == "caption":
			texts.append(String(step.get("text", "")))
	Director.step_started.connect(on_step)
	var beats := Level01StoryBeats.new()
	add_child(beats)
	beats.bind(self, null, null)
	beats.try_wake()
	ok(SaveData.has_flag("wake"), "wake is marked so a reload will not redo chapter 1")
	ok(Director.playing, "opening is playing ahead of the wake")
	var caption_started := await wait_until(func() -> bool: return not texts.is_empty(), 180)
	ok(caption_started, "opening caption started")
	Director.skip_step()
	for _i in 8:
		if texts.has("你不是被选中的。刮锈的偶，自己先锈透了。"):
			break
		if not Director.playing:
			break
		Director.skip_step()
		await flush(1)
	Director.step_started.disconnect(on_step)
	ok(texts.has(Opening.LINES[0]), "opening line plays before the wake")
	ok(texts.has("你不是被选中的。刮锈的偶，自己先锈透了。"), "existing wake line still plays")
	ok(SaveData.has_flag(Opening.FLAG))
	eq(SaveData.ending, "")
	ok(not SaveData.has_flag("game_complete"))
	Director.abort()
	ok(not Director.is_input_locked())
	beats.try_wake()
	ok(not Director.playing, "second wake does not replay the opening")
	beats.queue_free()
