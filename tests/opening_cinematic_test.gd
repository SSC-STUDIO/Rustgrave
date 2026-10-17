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
	eq(Opening.LINES.size(), 5, "five beats: situation, identity split into two captions, anomaly, objective")
	ok(Opening.LINES[0].contains("剑"), "the situation beat names the sword")
	ok(Opening.LINES[1].contains("选中"), "the identity beat (1/2) denies the chosen-one reading")
	ok(Opening.LINES[2].contains("锈透"), "the identity beat (2/2) closes on the knight's own rot")
	ok(Opening.LINES[3].contains("钟"), "the anomaly is the bell under the graves")
	ok(Opening.LINES[4].contains("炉"), "the objective names the furnace")
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
	# 身份拍的两个 tag 把镜头和坟群的回应绑在同一条字幕上；目标拍带 line_forge，
	# 截图夹具按 tag 认它，不按第几句认。
	eq(tags, ["rouse", "stand", "pullback", "grave_row", "toll", "line_forge", "card", "handoff"])
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


## The hand-off is a moment, not a leftover: the prompt only appears once the script is
## over (natural end or skip), and it carries the move keys the player just got back.
func test_handoff_prompt_arrives_only_after_the_script_is_over() -> void:
	var presentation := Director.get_node("CinematicPresentation")
	ok(Opening.try_start())
	ok(Director.playing, "the script is running")
	ok(not presentation.hint_visible(), "no prompt while the piece still owns the screen")
	# A skip ends it and hands over in the same frame.
	_accept()
	ok(not Director.playing)
	ok(presentation.hint_visible(), "the hand-off prompt is up the moment control returns")
	ok(presentation.hint_label.text == Opening.move_prompt(),
			"the prompt reads from the player's own key bindings")


## If another Director script is already queued behind the opening (a forced beat that
## fired during it), the move prompt must not flash under that script. It waits for the
## queue to go dry, then hands over.
func test_handoff_prompt_waits_for_a_queued_script() -> void:
	var presentation := Director.get_node("CinematicPresentation")
	ok(Opening.try_start())
	Director.play([
		{"kind": "lock"},
		{"kind": "wait", "seconds": 8.0},
		{"kind": "unlock"},
	])
	_accept()
	ok(SaveData.has_flag(Opening.FLAG), "skipping the opening still counts it as seen")
	ok(Director.playing, "the queued beat owns the screen next")
	ok(not presentation.hint_visible(), "no hand-off prompt under a queued beat")
	_accept()
	ok(not Director.playing, "the queued beat is over")
	ok(presentation.hint_visible(), "the prompt arrives once the queue is dry")
	ok(presentation.hint_label.text == Opening.move_prompt(),
			"the delayed prompt is still the move prompt")


## A death mid-piece aborts instead of finishing: no prompt, no seen flag, no music
## hand-back that would leave the graveyard playing over the death stinger.
func test_death_mid_piece_aborts_without_a_handoff() -> void:
	ok(Opening.try_start())
	ok(Director.playing)
	ok(Director.is_input_locked())
	Director.abort()
	ok(not Director.playing, "abort ends the piece")
	ok(not Director.is_input_locked(), "input is back")
	ok(not SaveData.has_flag(Opening.FLAG), "an interrupted opening is not a seen opening")
	ok(not SaveData.has_flag("wake"), "and does not mark the wake")
	ok(not Director.get_node("CinematicPresentation").hint_visible(),
			"no hand-off prompt for a piece that never finished")
	ok(Opening.try_start(), "it can still play once the knight is alive again")
	Director.abort()


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


## The hand-off prompt carries the keys and nothing else: the corridor pan already
## showed the way east, so the line does not have to spell it out. The direction is
## told by the camera and the objective light, not by text.
func test_handoff_prompt_states_the_keys_and_leaves_the_direction_to_the_camera() -> void:
	var prompt := Opening.move_prompt()
	ok(prompt.contains("移动"), "the prompt names the move keys")
	ok(prompt.contains("跳跃"), "the prompt names jump")
	ok(not prompt.contains("东"), "the prompt does not spell out east; the pan already showed it")
	ok(not prompt.contains("往"), "no compass words in the hand-off line")
	# Touch devices get the same contract without keyboard labels.
	var wants_overlay := TouchInput.wants_overlay()
	if wants_overlay:
		ok(prompt.contains("触控板"), "touch prompt names the pads")
	else:
		ok(not prompt.contains("触控板"), "keyboard prompt stays on key labels")


## Every caption line must be short enough that the picture carries the beat and the
## text only pins it. Long subtitle blocks are a sign the shot stopped telling the story.
func test_lines_are_short_enough_for_the_picture_to_lead() -> void:
	for line in Opening.LINES:
		ok(String(line).length() <= 16, "line is a pin, not a paragraph: %s" % line)
	# The objective beat names the furnace and the ones below in the same breath.
	ok(Opening.LINES[4].contains("炉") and Opening.LINES[4].contains("他们"),
			"the objective names both the furnace and who has to be taken down")
	# The identity beat says what the knight is, not what he must do.
	ok(Opening.LINES[2].contains("偶"), "the identity echo calls the knight what he is")
	# The anomaly is one sentence; the graves' answers are the picture.
	ok(Opening.LINES[3].contains("钟") and Opening.LINES[3].contains("数"),
			"the anomaly beat says the bell is counting")


## The objective shot ends on the forge remnant at the corridor's end: the camera must
## arrive closer than the wide establishing pull-back, and the heart's second pulse is
## spaced so it reads as an answer from below the door, not one lamp flickering.
func test_objective_shot_pushes_in_and_pulses_twice() -> void:
	ok(Opening.ZOOM_ARRIVE < Opening.ZOOM_WIDE,
			"the arrival shot is tighter than the identity pull-back")
	ok(Opening.PAN_END_X > 1800.0, "the corridor pan ends deep in the east wing")
	ok(Opening.HEART.x >= 2000.0, "the forge remnant sits at the east end of the map")
	ok(Opening.HEART_SECOND_BEAT > 0.2 and Opening.HEART_SECOND_BEAT < 1.2,
			"the heart's second beat is a delayed answer, not a double flicker")


## The world mystery and the immediate goal are the same place: while the bell is still
## counting graves, the corridor's end answers with a low, far pulse before the camera
## gets there. The echo must land inside the travel and stay in frame at the arrival.
func test_corridor_echo_answers_before_the_camera_arrives() -> void:
	ok(Opening.ECHO_AT > 0.2 and Opening.ECHO_AT < 0.9,
			"the far answer is a mid-pan beat, not the arrival itself")
	var at := Opening.PAN_SECONDS * Opening.ECHO_AT
	ok(at > 1.0 and at < Opening.PAN_SECONDS,
			"the echo lands inside the pan (%.2fs of %.2fs)" % [at, Opening.PAN_SECONDS])
	ok(absf(Opening.HEART.x - Opening.PAN_END_X) < 320.0,
			"the corridor's end and the forge remnant stay in the same arrival frame")
	# Calling the echo with no dolly (unit fixture / aborted scene) is inert, not an error.
	Opening.reset()
	Opening._heart_echo()


## The mystery beat is carried by the graves answering in order, so the pan must expose
## a timing function that spreads them out and keeps them inside the travel.
func test_grave_answers_stay_inside_the_pan_and_never_bunch_up() -> void:
	var xs := Opening.grave_xs(null)
	var times := Opening.pan_times(xs, Opening.PULLBACK_X, Opening.PAN_END_X, Opening.PAN_SECONDS)
	eq(times.size(), xs.size(), "every fallback grave gets an answer inside the pan")
	for i in range(1, times.size()):
		ok(times[i] > times[i - 1], "answer %d lands strictly after the one before" % i)
		ok(times[i] <= Opening.PAN_SECONDS + 0.001, "answer %d is inside the pan" % i)


## The identity shot ends with the nearest graves answering under the knight: he reads
## as one of the row, which is what the second line says without saying it.
func test_identity_shot_ends_with_the_grave_row_answering() -> void:
	ok(Opening.PULLBACK_X < 400.0, "the pull-back settles close to the western graves")
	ok(Opening.GRAVE_XS.size() >= 5, "there is a row of graves to answer")
	for x in Opening.GRAVE_XS:
		ok(x > 0.0, "every grave stands in the world")
