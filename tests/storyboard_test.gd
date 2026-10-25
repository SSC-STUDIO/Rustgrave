extends TestCase
## 分镜系统：数据完整（每段 / 每个镜头的布景、演员、运镜、粒子、台词都合法，时长在预算内）、
## 序章专名就地解释、7 张关键插图的位置、插图缺失时舞台静默退回实时拼、播放器的逐句 / 整段跳过、
## 输入宽限、暂停冻结、abort 幂等、回放不写「看过」旗标，以及它在 Director 里的接线
## （序章里的 Enter 不会连同后面的场内开场一起吞掉、暂停菜单在分镜里不开、字幕说话人）。
##
## 播放器用自己 new 的一份（不碰 Director 里常驻的那一个），要走 Director 的用例置位
## Director.test_boards（测试跑器里 board 步骤默认只是 0.3 秒的占位等待）。

const Boards := preload("res://scripts/data/storyboards.gd")
const Stage := preload("res://scripts/ui/storyboard_stage.gd")
const PlayerScript := preload("res://scripts/ui/storyboard_player.gd")
const DOC_PATH := "res://docs/cinematics.md"

## 序章里每个专名第一次出现的那一句必须就地带着白话解释（子串）。
const FIRST_MENTION := {
	"炉约": "炉约：",
	"守炉人": "叫守炉人",
	"炉心": "——炉心——",
	"火种": "小核——火种",
	"炉座": "——炉座——",
	"伊尔": "伊尔：我是最后一个守炉人",
	"余烬骑士": "人偶",
}
## 分镜里用到的 7 张关键插图（assets/story/<id>.png 或 .jpg）。
const ART_IDS: Array[String] = [
	"prologue_city", "prologue_names", "prologue_yir", "prologue_knight",
	"ending_give", "ending_keep", "ending_snuff",
]

var _spawned: Array[Node] = []


func setup() -> void:
	SaveData.flags.clear()
	Director.abort()
	Director.resume()
	Director.test_boards = false
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	Director.test_boards = false
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	SaveData.flags.clear()


func _accept() -> void:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Director._unhandled_input(event)


func _all_ids() -> Array[String]:
	var ids: Array[String] = [Boards.PROLOGUE, Boards.CREDITS]
	for edge in StoryFlow.boundaries():
		ids.append(Boards.interlude_id(String((edge as Dictionary)["from"])))
	for kind in ["give", "keep", "snuff"]:
		ids.append(Boards.ending_id(kind))
	return ids


## 自己的播放器（untyped：用 Variant 调脚本成员，和 Director 持有的那一个互不相干）。
func _new_board() -> Variant:
	var board: CanvasLayer = PlayerScript.new()
	add_child(board)
	_spawned.append(board)
	return board


func _new_stage() -> Control:
	var stage := Stage.new() as Control
	add_child(stage)
	_spawned.append(stage)
	return stage


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# --- 数据 -----------------------------------------------------------------------

func test_every_board_is_well_formed() -> void:
	eq(_all_ids().size(), 2 + 13 + 3, "prologue + credits + thirteen interludes + three endings")
	for id in _all_ids():
		var shots := Boards.shots(id)
		ok(Boards.has(id) and not shots.is_empty(), "%s has shots" % id)
		ok(Boards.title_of(id) != "" and Boards.title_of(id) != id, "%s has a story-page title" % id)
		for raw in shots:
			var shot: Dictionary = raw
			var set_id := String(shot.get("set", ""))
			ok(Stage.supports_set(set_id), "%s: the stage can build set '%s'" % [id, set_id])
			ok(Stage.CAMS.has(String(shot.get("cam", ""))), "%s: known camera move" % id)
			ok(Stage.FXS.has(String(shot.get("fx", ""))), "%s: known particle kind" % id)
			for actor in shot.get("actors", []):
				var spec: Array = actor
				ok(spec.size() == 3, "%s: an actor is [kind, x, scale]" % id)
				if spec.size() < 3:
					continue
				ok(Stage.ACTOR_KINDS.has(String(spec[0])), "%s: actor '%s' is implemented" % [id, spec[0]])
				ok(float(spec[1]) >= 0.0 and float(spec[1]) <= 1.0, "%s: actor x is 0..1" % id)
				ok(float(spec[2]) > 0.0 and float(spec[2]) <= 4.0, "%s: actor scale is sane" % id)
			var lines: Array = shot.get("lines", [])
			if shot.has("scroll"):
				ok(not (shot["scroll"] as Array).is_empty(), "%s: the credits scroll something" % id)
				ok(lines.is_empty(), "%s: a scrolling shot has no spoken lines" % id)
			else:
				ok(not lines.is_empty(), "%s: every shot says something" % id)
			for line in lines:
				var text := String(line)
				ok(text.strip_edges() != "", "%s: no blank lines" % id)
				var cut := text.find("：")
				if cut > 0 and cut <= 4:
					var who := text.substr(0, cut)
					ok(ChapterText.SPEAKERS.has(who) or who == "还火" or who == "守炉",
							"%s: '%s' is a known speaker" % [id, who])


func test_boards_stay_inside_their_time_budgets() -> void:
	var prologue := Boards.seconds_of(Boards.PROLOGUE)
	ok(prologue >= 25.0 and prologue <= 45.0, "the prologue is a real piece but not a film (%.1fs)" % prologue)
	for edge in StoryFlow.boundaries():
		var limit := 30.0 if String((edge as Dictionary).get("special", "")) == "pre_ending" else 18.0
		var seconds := Boards.seconds_of(Boards.interlude_id(String(edge["from"])))
		ok(seconds > 3.0 and seconds <= limit, "%s stays a bridge (%.1fs <= %.0f)" % [edge["from"], seconds, limit])
	for kind in ["give", "keep", "snuff"]:
		var seconds := Boards.seconds_of(Boards.ending_id(kind))
		ok(seconds >= 8.0 and seconds <= 40.0, "ending %s runs %.1fs" % [kind, seconds])
	almost(Boards.seconds_of(Boards.CREDITS), Boards.SHOT_FADE + Boards.CREDITS_SECONDS, 0.001,
			"credits last their scroll time")
	for id in _all_ids():
		for raw in Boards.shots(id):
			var shot: Dictionary = raw
			if shot.has("scroll"):
				continue
			ok(Boards.shot_seconds(shot) <= 12.0, "%s: no single shot drags (%.1fs)" % [id, Boards.shot_seconds(shot)])
	# Director 的估算就是分镜自己的时长（开场 / 章间预算测试靠它）。
	almost(Director.estimate_seconds([{"kind": "board", "id": Boards.PROLOGUE}]), prologue, 0.001,
			"the Director counts a board step as the board's own length")
	eq(Director.estimate_seconds([{"kind": "board", "id": "no_such_board"}]), 0.0, "an unknown board counts for nothing")


func test_prologue_explains_each_name_where_it_first_appears() -> void:
	var lines := Boards.lines_of(Boards.PROLOGUE)
	for term in FIRST_MENTION:
		var word := String(term)
		var first := -1
		for i in lines.size():
			if lines[i].contains(word):
				first = i
				break
		ok(first >= 0, "the prologue mentions '%s'" % word)
		if first >= 0:
			ok(lines[first].contains(String(FIRST_MENTION[term])),
					"'%s' is explained in the very line it first appears in: %s" % [word, lines[first]])
	# 序章不抢关内开场的活：开场七拍只许在序章之后。
	for line in ChapterText.opening_lines():
		ok(not lines.has(line), "the prologue does not repeat the in-level opening line: %s" % line)


func test_the_seven_illustration_slots_are_documented() -> void:
	var used: Array = []
	for id in _all_ids():
		for raw in Boards.shots(id):
			var art := String((raw as Dictionary).get("art", ""))
			if art != "" and not used.has(art):
				used.append(art)
	var expected: Array = ART_IDS.duplicate()
	used.sort()
	expected.sort()
	eq(used, expected, "the boards ask for exactly the seven key illustrations")
	var give_art := ""
	for raw in Boards.shots("ending_give"):
		var shot: Dictionary = raw
		if String(shot.get("art", "")) == "ending_give":
			give_art = " ".join(PackedStringArray(shot.get("lines", []) as Array))
	ok(give_art.contains("铁屑") or give_art.contains("散"),
			"ending_give is on the farewell where the knight scatters, not the opening shot")
	ok(String((Boards.shots("prologue")[1] as Dictionary).get("art", "")) == "prologue_names",
			"prologue_names is the covenant shot: named swords pushed into the furnace")
	var file := FileAccess.open(DOC_PATH, FileAccess.READ)
	ok(file != null, "docs/cinematics.md is readable")
	if file == null:
		return
	var docs := file.get_as_text()
	file.close()
	for art in ART_IDS:
		ok(docs.contains(art), "docs/cinematics.md lists the illustration %s" % art)
	ok(docs.contains("assets/story"), "the docs say where the files go")


# --- 舞台：插图与回退 ------------------------------------------------------------

func test_missing_art_falls_back_to_the_live_stage_quietly() -> void:
	eq(Stage.resolve_art({}), "", "a shot without art asks for none")
	eq(Stage.resolve_art({"art": ""}), "", "an empty art id asks for none")
	eq(Stage.resolve_art({"art": "no_such_illustration"}), "", "a missing file resolves to nothing")
	eq(Stage.art_file("no_such_illustration"), "")
	var stage := _new_stage()
	var shot := {"set": "forge", "actors": [["swords", 0.5, 1.0], ["knight", 0.3, 2.0]],
			"cam": "push", "fx": "embers", "lines": [], "art": "no_such_illustration"}
	stage.call("show_shot", shot, 4.0)
	var info: Dictionary = stage.call("info")
	eq(info["art_used"], false, "no file, so the live composition is used")
	eq(info["art_path"], "", "and no art path is claimed")
	ok(int(info["actors"]) >= 2, "the actors are drawn instead")
	ok(int(info["motes"]) > 0, "the particles still run")
	stage.call("tick", 0.2)
	stage.call("set_black", 0.5)
	almost(float(stage.call("black_amount")), 0.5, 0.001, "the cut-to-black amount is readable")
	# 不认识的布景名退成纯黑，不报错、不留空指针。
	stage.call("show_shot", {"set": "no_such_set", "actors": [], "cam": "still", "fx": "none",
			"lines": [], "art": ""}, 2.0)
	eq(int((stage.call("info") as Dictionary)["layers"]), 0, "an unknown set is plain dark")
	# 装好插图（任一扩展名）后改用插图：不画演员，粒子保留。
	if Stage.art_file("prologue_city") != "":
		stage.call("show_shot", {"set": "title_hall", "actors": [["knight", 0.5, 2.0]], "cam": "push",
				"fx": "embers", "lines": [], "art": "prologue_city"}, 4.0)
		var art_info: Dictionary = stage.call("info")
		eq(art_info["art_used"], true, "an installed illustration is used")
		eq(art_info["actors"], 0, "an illustration shot draws no actors")
		ok(int(art_info["motes"]) > 0, "but keeps the particles")


func test_stage_resolves_both_png_and_jpg() -> void:
	eq(Stage.ART_EXTS, ["png", "jpg"], "png first, then the jpg the image tool writes")
	eq(Stage.ART_DIR, Boards.ART_DIR, "the stage and the data agree on the folder")


# --- 播放器 ---------------------------------------------------------------------

func test_accept_skips_a_whole_interlude_and_marks_it_seen() -> void:
	var board = _new_board()
	var finished: Array = []
	board.board_finished.connect(func(id: String, completed: bool) -> void: finished.append([id, completed]))
	ok(board.play_board("interlude_level01"), "the interlude starts")
	ok(board.playing and board.board_active())
	ok(board.skip_all_on_accept, "an interlude is skipped whole by one accept")
	board.press_accept()
	ok(board.playing, "an accept in the first moments is swallowed by the input grace")
	await _sleep(0.5)
	board.press_accept()
	ok(await wait_until(func() -> bool: return not board.playing, 120), "one accept ends the whole interlude")
	eq(finished, [["interlude_level01", true]], "it finished once, completed")
	ok(SaveData.has_flag(Boards.seen_flag("interlude_level01")), "skipping counts as seen")
	ok(not board.visible or board.is_revealing(), "the layer is on its way out")


func test_the_prologue_advances_line_by_line_and_skip_all_ends_it() -> void:
	var board = _new_board()
	var started: Array = []
	board.line_started.connect(func(index: int, _text: String) -> void: started.append(index))
	ok(board.play_board(Boards.PROLOGUE), "the prologue starts")
	ok(not board.skip_all_on_accept, "the prologue goes line by line")
	ok(await wait_until(func() -> bool: return board.phase == PlayerScript.Phase.TYPING, 120),
			"the first line starts typing")
	eq(board.current_shot_index(), 0, "on the first shot")
	board.press_accept()
	eq(board.phase, PlayerScript.Phase.HOLD, "the first accept finishes the line")
	board.press_accept()
	eq(started, [0, 1], "the second accept moves on to the next line")
	board.skip_all()
	ok(await wait_until(func() -> bool: return not board.playing, 120), "skip-all closes the whole piece")
	ok(SaveData.has_flag(Boards.seen_flag(Boards.PROLOGUE)), "a skipped prologue still counts as seen")


func test_abort_is_idempotent_and_never_counts_as_seen() -> void:
	var board = _new_board()
	var finished: Array = []
	board.board_finished.connect(func(id: String, completed: bool) -> void: finished.append([id, completed]))
	board.play_board(Boards.ending_id("give"))
	await get_tree().process_frame
	board.abort()
	board.abort()
	ok(not board.playing and not board.board_active(), "abort stops it")
	ok(not board.visible, "abort hides the layer at once (no stuck dark screen)")
	eq(finished, [["ending_give", false]], "one finish, not completed")
	ok(not SaveData.has_flag(Boards.seen_flag("ending_give")), "an aborted board is not seen")
	board.abort()
	eq(finished.size(), 1, "aborting an idle player is a no-op")
	ok(board.play_board(Boards.CREDITS), "it can play again after an abort")
	board.abort()
	ok(not board.playing)


func test_play_board_refuses_an_unknown_id() -> void:
	var board = _new_board()
	ok(not board.play_board("no_such_board"), "an unknown id does not start")
	ok(not board.playing and not board.visible)


func test_replay_writes_no_flag_and_sits_above_the_pause_menu() -> void:
	var board = _new_board()
	ok(board.play_board(Boards.ending_id("keep"), {"replay": true}), "a replay starts")
	ok(board.replay)
	ok(board.layer > 22, "the replay is drawn above the pause menu layers (20-22)")
	board.skip_all()
	ok(await wait_until(func() -> bool: return not board.playing, 120), "skip-all ends the replay")
	ok(not SaveData.has_flag(Boards.seen_flag("ending_keep")), "a replay never writes the seen flag")
	ok(board.play_board(Boards.ending_id("keep")), "a normal play afterwards")
	eq(board.layer, PlayerScript.LAYER, "goes back to the story layer")
	board.abort()


func test_tree_pause_and_director_suspend_freeze_the_board() -> void:
	var board = _new_board()
	board.play_board(Boards.PROLOGUE)
	await flush(4)
	var before: float = board.age()
	ok(before > 0.0, "the board runs while the game runs")
	get_tree().paused = true
	for _i in 8:
		await get_tree().process_frame
	almost(board.age(), before, 0.001, "tree pause freezes the board clock")
	get_tree().paused = false
	Director.suspend()
	for _i in 8:
		await get_tree().process_frame
	almost(board.age(), before, 0.001, "a suspended Director freezes it too")
	Director.resume()
	for _i in 8:
		await get_tree().process_frame
	ok(board.age() > before, "resuming runs it again")
	board.abort()


func test_a_replay_keeps_running_while_the_tree_is_paused() -> void:
	# 故事页回放就是在暂停菜单里点开的：树是暂停的，它自己必须能播。
	var board = _new_board()
	board.play_board(Boards.PROLOGUE, {"replay": true})
	get_tree().paused = true
	await flush(2)
	var before: float = board.age()
	for _i in 8:
		await get_tree().process_frame
	ok(board.age() > before, "a replay is not frozen by the pause menu it was opened from")
	get_tree().paused = false
	board.abort()


# --- Director 接线 --------------------------------------------------------------

func test_an_accept_in_the_prologue_does_not_swallow_the_rest_of_a_skippable_script() -> void:
	Director.test_boards = true
	Director.play([
		{"kind": "lock"},
		{"kind": "board", "id": Boards.PROLOGUE, "skip_all": false},
		{"kind": "wait", "seconds": 30.0},
		{"kind": "unlock"},
	], true)
	ok(Director.playing and Director.board_active(), "the prologue owns the screen")
	ok(Director.skips_whole_script(), "the script itself is skippable (the in-level opening is)")
	ok(Director.board_blocks_pause(), "the pause menu stays shut while a board plays")
	await _sleep(0.6)
	_accept()
	ok(Director.playing and Director.board_active(), "an accept advances the prologue, not the whole script")
	Director.board().call("skip_all")
	ok(await wait_until(func() -> bool: return not Director.board_active(), 120), "the board ends")
	ok(Director.playing, "the steps after the prologue still run")
	ok(not Director.board_blocks_pause(), "the pause menu is available again")
	_accept()
	ok(not Director.playing, "now the script-level skip applies and ends what is left")
	ok(not Director.is_input_locked(), "and hands the controls back")


func test_a_replay_does_not_block_the_pause_menu() -> void:
	Director.board().call("play_board", Boards.PROLOGUE, {"replay": true})
	ok(Director.board_active(), "the replay is on screen")
	ok(not Director.board_blocks_pause(), "but it was opened from the pause menu, so it never blocks it")
	Director.board().call("abort")
	ok(not Director.board_active())


func test_the_test_runner_plays_a_board_step_as_a_short_placeholder() -> void:
	Director.play([{"kind": "lock"}, {"kind": "board", "id": Boards.PROLOGUE}, {"kind": "unlock"}])
	ok(Director.playing, "the script runs")
	ok(not Director.board_active(), "but the real board does not (tests would wait half a minute)")
	ok(await wait_until(func() -> bool: return not Director.playing, 90), "the placeholder wait is short")
	ok(not Director.is_input_locked())


func test_an_unknown_board_step_is_skipped_not_stuck() -> void:
	Director.test_boards = true
	Director.play([{"kind": "lock"}, {"kind": "board", "id": "no_such_board"}, {"kind": "unlock"}])
	ok(not Director.playing, "a missing board never leaves the Director waiting")
	ok(not Director.is_input_locked())


func test_abort_closes_a_board_the_director_started() -> void:
	Director.test_boards = true
	Director.play([{"kind": "board", "id": Boards.ending_id("snuff"), "skip_all": false},
			{"kind": "wait", "seconds": 5.0}])
	ok(Director.board_active())
	Director.abort()
	Director.abort()
	ok(not Director.board_active() and not Director.playing, "abort and reset are idempotent")
	ok(not (Director.board() as CanvasLayer).visible, "the board layer is gone")
	ok(not SaveData.has_flag(Boards.seen_flag("ending_snuff")), "an interrupted ending is not seen")


func test_caption_steps_carry_a_speaker_nameplate() -> void:
	Director.play([{"kind": "lock"}, {"kind": "caption", "text": "伊尔：醒醒。", "hold": 5.0}])
	eq(Director.caption().speaker(), "伊尔", "「说话人：」前缀自动拆成名牌")
	Director.abort()
	Director.play([{"kind": "caption", "text": "醒醒。", "who": "刽子手", "hold": 5.0}])
	eq(Director.caption().speaker(), "刽子手", "a `who` field names the speaker explicitly")
	Director.abort()
	Director.play([{"kind": "caption", "text": "钟声又响了。", "hold": 5.0}])
	eq(Director.caption().speaker(), "", "narration has no nameplate")
	Director.abort()


# --- Boss 名号卡上的白话一行 ------------------------------------------------------

func test_the_boss_card_kicker_comes_from_the_chapter_text() -> void:
	var presentation := Director.get_node("CinematicPresentation")
	eq(presentation.call("_kicker_for_current_level"), "", "outside a level there is no kicker")
	var world := Node2D.new()
	world.add_to_group("game_world")
	add_child(world)
	_spawned.append(world)
	var knight := Node2D.new()
	knight.add_to_group("player")
	world.add_child(knight)
	world.scene_file_path = GameContext.WORLD_PATH
	eq(presentation.call("_kicker_for_current_level"), ChapterText.boss_intro_of("level01"),
			"chapter one (the legacy bare path) reads its own epithet")
	world.scene_file_path = String(GameContext.LEVELS["level02b"])
	eq(presentation.call("_kicker_for_current_level"), ChapterText.boss_intro_of("level02b"),
			"a data chapter reads its own epithet")
	world.scene_file_path = String(GameContext.LEVELS["level03"])
	eq(presentation.call("_kicker_for_current_level"), "", "a chapter without a boss has none")
