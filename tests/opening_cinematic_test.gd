extends TestCase
## 新游戏开场：约 13 秒的分镜、只播一次、不写结局、跳过会解锁并还原、无头不报错。

const Opening := preload("res://scripts/levels/opening_cinematic.gd")
## 开场只许用这些 Director 步骤（新东西只加在 fx id 上）。
const ALLOWED_KINDS: Array[String] = [
	"lock", "unlock", "wait", "tableau", "caption", "cam_focus", "cam_release",
	"letterbox", "sfx", "fx",
]

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
	Director.hide_hint()
	Director.choice_hold = false
	Opening.reset()
	StoryStage.forget()
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	Director.abort()
	Director.hide_hint()
	Opening.reset()
	SaveData.delete_save()
	SaveData.save_path = _save_path
	SaveData.flags.clear()
	SaveData.ending = ""
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false


func _accept() -> void:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Director._unhandled_input(event)


func test_beat_sheet_fits_the_budget_and_uses_only_known_step_kinds() -> void:
	var steps := Opening.steps()
	var seconds := Director.estimate_seconds(steps)
	ok(seconds <= Opening.MAX_SECONDS, "opening runs %.1fs, budget %.1fs" % [seconds, Opening.MAX_SECONDS])
	ok(seconds >= 10.0, "opening is a real piece, not a blink (%.1fs)" % seconds)
	var captions: Array[String] = []
	for raw in steps:
		var step: Dictionary = raw
		ok(ALLOWED_KINDS.has(String(step.get("kind", ""))), "step kind %s is an existing Director kind" % step.get("kind", ""))
		if step.get("kind", "") == "caption":
			captions.append(String(step["text"]))
	eq(captions, Opening.LINES, "situation, identity, anomaly, objective — in that order")
	eq(Opening.LINES.size(), 4)
	ok(Opening.LINES[2].contains("钟"), "the anomaly is the bell under the graves")
	ok(Opening.LINES[3].contains("炉"), "the objective names the furnace")
	var card: Dictionary = {}
	for raw in steps:
		if (raw as Dictionary).get("id", "") == "chapter":
			card = raw
	eq(card.get("title", ""), "腐液回廊")
	eq(card.get("subtitle", ""), "锈墓・壹")
	almost(float(card.get("seconds", 0.0)), Opening.CARD_SECONDS, 0.001)


func test_pan_times_follow_the_dolly_and_graves_behind_the_start_answer_first() -> void:
	var xs: Array[float] = [210.0, 360.0, 548.0, 1020.0, 1580.0, 2400.0]
	var times := Opening.pan_times(xs, 262.0, 1990.0, 3.4)
	eq(times.size(), 5, "a grave past the end of the pan never answers")
	almost(times[0], 0.0, 0.001, "the grave behind the camera answers at once")
	for i in range(1, times.size()):
		ok(times[i] >= times[i - 1] + 0.17, "answers are spread out, not one frame")
		ok(times[i] <= 3.4 + 0.001, "every answer lands inside the pan")
	ok(times[times.size() - 1] > times[2], "later graves answer later")
	eq(Opening.pan_times(xs, 500.0, 500.0, 3.0).size(), 0, "no travel, no answers")
	# The fallback list is a sorted run along the corridor.
	var fallback := Opening.grave_xs(null)
	eq(fallback.size(), Opening.GRAVE_XS.size())
	for i in range(1, fallback.size()):
		ok(fallback[i] > fallback[i - 1], "graves are ordered west to east")


func test_new_game_plays_the_beat_sheet_then_marks_seen_without_ending() -> void:
	var texts: Array[String] = []
	var fx_ids: Array[String] = []
	var tableau_ids: Array[String] = []
	var tags: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		var kind := String(step.get("kind", ""))
		if kind == "caption":
			texts.append(String(step.get("text", "")))
		elif kind == "fx":
			fx_ids.append(String(step.get("id", "")))
		elif kind == "tableau":
			tableau_ids.append(String(step.get("id", "")))
		if step.has("tag"):
			tags.append(String(step["tag"]))
	Director.step_started.connect(on_step)
	var fx_children := Fx.get_child_count()
	ok(Opening.try_start(), "fresh new game starts the opening")
	ok(Director.playing)
	ok(Director.is_input_locked(), "opening locks input")
	ok(Director.skips_whole_script(), "one accept skips the whole piece")
	ok(not SaveData.has_flag("wake"), "wake waits until the whole piece ends")
	eq(SaveData.ending, "")
	ok(not Opening.try_start(), "a second call while it plays does not replay")
	var done := await wait_until(func() -> bool: return not Director.playing, 1500)
	Director.step_started.disconnect(on_step)
	ok(done, "opening finished")
	ok(not Director.playing, "finish does not start a second wake script")
	ok(not Director.is_input_locked(), "finish clears the lock")
	eq(texts, Opening.LINES)
	eq(fx_ids, ["rust_flake", "rust_flake", "plant", "bell_ring"])
	eq(tableau_ids, ["chapter", "world"])
	eq(tags, ["rouse", "stand", "pullback", "toll", "card", "handoff"])
	ok(SaveData.has_flag(Opening.FLAG))
	ok(SaveData.has_flag("wake"), "wake is marked with the opening")
	eq(SaveData.flags.count(Opening.FLAG), 1)
	eq(SaveData.ending, "", "opening does not write an ending")
	ok(not SaveData.has_flag("game_complete"))
	ok(not Opening.try_start(), "finished opening does not replay")
	ok(not Director.playing)
	eq(Fx.burst_live_count(), 0, "headless fx steps spawn nothing")
	eq(Fx.get_child_count(), fx_children, "headless fx step adds no nodes")
	var presentation := Director.get_node("CinematicPresentation")
	ok(presentation.hint_visible(), "control returns with a move prompt")
	eq(presentation.hint_label.text, Opening.move_prompt())
	ok(presentation.hint_label.text.contains("移动"))


func test_skip_jumps_to_end_and_blocks_replay() -> void:
	ok(Opening.try_start())
	ok(Director.is_input_locked())
	_accept()
	ok(not Director.playing, "one ui_accept ends the opening")
	ok(not Director.is_input_locked(), "skip clears the lock")
	ok(not get_tree().paused)
	ok(SaveData.has_flag(Opening.FLAG), "skip counts as seen")
	ok(SaveData.has_flag("wake"), "skip also marks wake so chapter 1 does not replay it")
	eq(SaveData.ending, "")
	ok(not SaveData.has_flag("game_complete"))
	ok(not Opening.try_start(), "skipped opening does not replay")
	ok(not Director.playing)
	ok(Director.get_node("CinematicPresentation").hint_visible(), "a skipped opening still hands over with the prompt")


func test_abort_marks_neither_flag() -> void:
	ok(Opening.try_start())
	ok(Director.playing)
	Director.abort()
	ok(not Director.playing)
	ok(not Director.is_input_locked())
	ok(not SaveData.has_flag(Opening.FLAG), "abort does not count as seen")
	ok(not SaveData.has_flag("wake"), "abort does not mark wake")
	eq(SaveData.ending, "")
	ok(not Director.get_node("CinematicPresentation").hint_visible(), "an aborted opening shows no prompt")
	ok(Opening.try_start(), "an aborted opening can play again")
	Director.abort()


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


func test_wake_is_the_opening_and_skip_does_not_start_another() -> void:
	var emitted: Array[String] = []
	var on_started := func(level_id: String) -> void:
		emitted.append(level_id)
	GameEvents.chapter_started.connect(on_started)
	var beats := Level01StoryBeats.new()
	add_child(beats)
	beats.bind(self, null, null)
	beats.try_wake()
	ok(not SaveData.has_flag("wake"), "wake is not marked while the opening is still playing")
	ok(Director.playing, "opening is the only wake script")
	ok(Director.skips_whole_script(), "one accept skips the whole opening")
	_accept()
	ok(not Director.playing, "skip does not leave a second wake script")
	ok(not Director.is_input_locked())
	ok(SaveData.has_flag(Opening.FLAG))
	ok(SaveData.has_flag("wake"))
	eq(SaveData.ending, "")
	ok(not SaveData.has_flag("game_complete"))
	beats.try_wake()
	ok(not Director.playing, "second wake does not replay the opening")
	GameEvents.chapter_started.disconnect(on_started)
	eq(emitted, ["level01", "level01"], "chapter_started fires once per level load, replay or not")
	beats.queue_free()


## The knight lies down before the first frame and every way out puts him back:
## natural stand-up, skip, abort. The camera and the dolly go with it.
func test_rise_pose_and_dolly_are_restored_by_every_exit() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -1))
	var cam := GameCamera.new()
	arena.add_child(cam)
	var nest := Node2D.new()
	nest.position = Vector2(150, 0)
	arena.add_child(nest)
	var real := player.visual.get_node_or_null("KnightSprite") as FrameAnimSprite
	ok(real != null and real.visible)

	# Exit 1: abort during the first beat.
	ok(Opening.try_start(player, nest))
	ok(not real.visible, "the standing sprite is hidden while the knight is down")
	var rise := player.visual.get_node_or_null("OpeningRise") as FrameAnimSprite
	ok(rise != null and rise.visible, "the prone knight is drawn from the first frame")
	ok(player.cutscene_locked)
	ok(cam._focused, "camera is pushed in on the knight")
	Director.abort()
	ok(real.visible, "abort puts the standing knight back")
	ok(player.visual.get_node_or_null("OpeningRise") == null or player.visual.get_node("OpeningRise").is_queued_for_deletion())
	ok(not player.cutscene_locked)
	ok(not cam._focused)
	almost(cam.zoom.x, GameCamera.ZOOM, 0.001, "zoom is back to 1x")
	Opening.reset()

	# Exit 2: run past the stand-up and the pull-back, then skip.
	SaveData.flags.clear()
	ok(Opening.try_start(player, nest))
	await wait_until(func() -> bool: return real.visible, 200)
	ok(real.visible, "the knight stands up on his own and the real sprite returns")
	await wait_until(func() -> bool: return arena.get_node_or_null("OpeningDolly") != null, 400)
	ok(arena.get_node_or_null("OpeningDolly") != null, "the pull-back runs on a dolly")
	ok(Director.playing and cam._focused)
	_accept()
	ok(not Director.playing)
	await flush(2)
	ok(arena.get_node_or_null("OpeningDolly") == null, "skip removes the dolly")
	ok(real.visible)
	ok(not cam._focused, "skip hands the camera back")
	ok(not player.cutscene_locked)
	ok(SaveData.has_flag(Opening.FLAG))
	cam.queue_free()
	arena.queue_free()


## A scene that is still fading in, a pause menu on top of it, an open ending choice:
## the opening must not start (suspended and locked) inside any of them.
func test_opening_waits_for_a_clear_moment() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -1))
	var real := player.visual.get_node_or_null("KnightSprite") as FrameAnimSprite
	get_tree().paused = true
	ok(Opening.try_start(player, null), "the opening is accepted while paused")
	ok(not Director.playing, "but it does not start under the pause menu")
	eq(Director.pending_scripts(), 1)
	ok(not real.visible, "the knight is already lying down so nothing pops when it starts")
	ok(player.cutscene_locked, "and held")
	get_tree().paused = false
	var started := await wait_until(func() -> bool: return Director.playing, 20)
	ok(started, "it starts as soon as the pause lifts")
	Director.abort()
	ok(real.visible and not player.cutscene_locked, "abort restores the pre-pose")
	Opening.reset()

	# Dropped while still waiting: abort() must undo the pre-pose too.
	SaveData.flags.clear()
	Director.choice_hold = true
	ok(Opening.try_start(player, null))
	ok(not Director.playing, "an open choice menu holds it back as well")
	ok(not real.visible)
	Director.abort()
	Director.choice_hold = false
	eq(Director.pending_scripts(), 0, "abort drops a script that never started")
	ok(real.visible, "and puts the knight back")
	ok(not player.cutscene_locked)
	ok(not SaveData.has_flag(Opening.FLAG), "a dropped opening is not a seen opening")
	arena.queue_free()


func test_move_prompt_hides_on_the_first_input_and_never_on_a_menu_press() -> void:
	var presentation := Director.get_node("CinematicPresentation")
	Director.show_hint(Opening.move_prompt(), 30.0)
	ok(presentation.hint_visible())
	await flush(3)
	ok(presentation.hint_visible(), "no input yet, the prompt stays")
	# A press while paused belongs to the menu, not to the knight.
	get_tree().paused = true
	Input.action_press("move_right")
	await get_tree().process_frame
	Input.action_release("move_right")
	get_tree().paused = false
	await flush(3)
	ok(presentation.hint_visible(), "a menu press does not count as the first move")
	Input.action_press("move_right")
	await flush(3)
	Input.action_release("move_right")
	ok(not presentation.hint_visible(), "the first real move hides the prompt")

	# Timeout and abort also clear it.
	Director.show_hint("x", 0.2)
	await wait_until(func() -> bool: return not presentation.hint_visible(), 60)
	ok(not presentation.hint_visible(), "it times out on its own")
	Director.show_hint("x", 30.0)
	Director.abort()
	ok(not presentation.hint_visible(), "abort clears it")
	# A key already held when the prompt appears (the skip press) is not a move.
	Input.action_press("jump")
	Director.show_hint("x", 30.0)
	await flush(3)
	ok(presentation.hint_visible(), "a held key from before the prompt does not dismiss it")
	Input.action_release("jump")
	Director.hide_hint()
