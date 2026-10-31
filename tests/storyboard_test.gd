extends TestCase
## 分镜系统（v4 精简版）：仅保留紧凑序章（6 镜）、四大结局（give / keep / snuff / true_break）与滚动字幕（credits），
## 验证数据完备、时长预算、缺图静默回退实时舞台、逐句推进与整段跳过、暂停冻结、回放不写旗标，以及 Boss 名号卡读取。

const Boards := preload("res://scripts/data/storyboards.gd")
const Stage := preload("res://scripts/ui/storyboard_stage.gd")
const PlayerScript := preload("res://scripts/ui/storyboard_player.gd")

const ART_IDS: Array[String] = [
	"prologue_city", "prologue_names", "prologue_yir", "prologue_knight",
	"ending_give", "ending_keep", "ending_snuff", "ending_true_break",
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
	for kind in ["give", "keep", "snuff", "true_break"]:
		ids.append(Boards.ending_id(kind))
	return ids


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


func test_every_board_is_well_formed() -> void:
	eq(_all_ids().size(), 6, "prologue + credits + four endings (zero chapter interludes)")
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
				ok(not (shot["scroll"] as Array).is_empty(), "%s: credits scroll something" % id)
				ok(lines.is_empty(), "%s: scrolling shot has no spoken lines" % id)
			else:
				ok(not lines.is_empty(), "%s: every shot says something" % id)
			for line in lines:
				var text := String(line)
				ok(text.strip_edges() != "", "%s: no blank lines" % id)
				var cut := text.find("：")
				if cut > 0 and cut <= 6:
					var who := text.substr(0, cut)
					ok(ChapterText.SPEAKERS.has(who) or who in ["还火", "守炉", "炉约规定"],
							"%s: '%s' is a known speaker" % [id, who])


func test_boards_stay_inside_their_time_budgets_and_art_slots() -> void:
	eq(Boards.shots(Boards.PROLOGUE).size(), 6, "prologue is streamlined to 6 crisp shots")
	var prologue := Boards.seconds_of(Boards.PROLOGUE)
	ok(prologue >= 12.0 and prologue <= 32.0, "prologue stays tight (%.1fs)" % prologue)
	for kind in ["give", "keep", "snuff", "true_break"]:
		var seconds := Boards.seconds_of(Boards.ending_id(kind))
		ok(seconds >= 8.0 and seconds <= 40.0, "ending %s runs %.1fs" % [kind, seconds])
	almost(Boards.seconds_of(Boards.CREDITS), Boards.SHOT_FADE + Boards.CREDITS_SECONDS, 0.001)
	almost(Director.estimate_seconds([{"kind": "board", "id": Boards.PROLOGUE}]), prologue, 0.001)
	eq(Director.estimate_seconds([{"kind": "board", "id": "no_such_board"}]), 0.0)

	var used: Array = []
	for id in _all_ids():
		for raw in Boards.shots(id):
			var art := String((raw as Dictionary).get("art", ""))
			if art != "" and not used.has(art):
				used.append(art)
	var expected: Array = ART_IDS.duplicate()
	used.sort()
	expected.sort()
	eq(used, expected, "boards reference the 4 prologue + 4 ending illustration slots")


func test_missing_art_falls_back_to_the_live_stage_quietly() -> void:
	eq(Stage.resolve_art({}), "")
	eq(Stage.resolve_art({"art": "no_such_illustration"}), "")
	var stage := _new_stage()
	var shot := {"set": "forge", "actors": [["swords", 0.5, 1.0], ["knight", 0.3, 2.0]],
			"cam": "push", "fx": "embers", "lines": [], "art": "no_such_illustration"}
	stage.call("show_shot", shot, 4.0)
	var info: Dictionary = stage.call("info")
	eq(info["art_used"], false)
	ok(int(info["actors"]) >= 2)
	ok(int(info["motes"]) > 0)
	eq(Stage.ART_EXTS, ["png", "jpg"])
	eq(Stage.ART_DIR, Boards.ART_DIR)


func test_the_prologue_advances_line_by_line_and_skip_all_ends_it() -> void:
	var board = _new_board()
	var started: Array = []
	board.line_started.connect(func(index: int, _text: String) -> void: started.append(index))
	ok(board.play_board(Boards.PROLOGUE), "the prologue starts")
	ok(not board.skip_all_on_accept, "the prologue goes line by line")
	ok(await wait_until(func() -> bool: return board.phase == PlayerScript.Phase.TYPING, 120))
	eq(board.current_shot_index(), 0)
	board.press_accept()
	eq(board.phase, PlayerScript.Phase.HOLD)
	board.press_accept()
	ok(await wait_until(func() -> bool: return board.phase == PlayerScript.Phase.TYPING, 120))
	eq(board.current_shot_index(), 1)
	eq(started.size(), 2)
	board.skip_all()
	ok(await wait_until(func() -> bool: return not board.playing, 120))
	ok(SaveData.has_flag(Boards.seen_flag(Boards.PROLOGUE)))


func test_abort_replay_and_pause_contracts() -> void:
	var board = _new_board()
	var finished: Array = []
	board.board_finished.connect(func(id: String, completed: bool) -> void: finished.append([id, completed]))
	board.play_board(Boards.ending_id("give"))
	await get_tree().process_frame
	board.abort()
	board.abort()
	ok(not board.playing and not board.board_active() and not board.visible)
	eq(finished, [["ending_give", false]])
	ok(not SaveData.has_flag(Boards.seen_flag("ending_give")))
	ok(not board.play_board("no_such_board"))

	ok(board.play_board(Boards.ending_id("true_break"), {"replay": true}))
	ok(board.replay and board.layer > 22)
	get_tree().paused = true
	await flush(2)
	var before: float = board.age()
	for _i in 6:
		await get_tree().process_frame
	ok(board.age() > before, "replay keeps running while tree is paused")
	get_tree().paused = false
	board.skip_all()
	ok(await wait_until(func() -> bool: return not board.playing, 120))
	ok(not SaveData.has_flag(Boards.seen_flag("ending_true_break")))


func test_director_wiring_and_caption_speakers() -> void:
	Director.test_boards = true
	Director.play([
		{"kind": "lock"},
		{"kind": "board", "id": Boards.PROLOGUE, "skip_all": false},
		{"kind": "wait", "seconds": 30.0},
		{"kind": "unlock"},
	], true)
	ok(Director.playing and Director.board_active() and Director.board_blocks_pause())
	await _sleep(0.6)
	_accept()
	ok(Director.playing and Director.board_active())
	Director.board().call("skip_all")
	ok(await wait_until(func() -> bool: return not Director.board_active(), 120))
	ok(Director.playing and not Director.board_blocks_pause())
	_accept()
	ok(not Director.playing and not Director.is_input_locked())

	Director.play([{"kind": "lock"}, {"kind": "caption", "text": "真伊尔：握紧真名。", "hold": 5.0}])
	eq(Director.caption().speaker(), "真伊尔")
	Director.abort()


func test_the_boss_card_kicker_comes_from_the_chapter_text() -> void:
	var presentation := Director.get_node("CinematicPresentation")
	eq(presentation.call("_kicker_for_current_level"), "")
	var world := Node2D.new()
	world.add_to_group("game_world")
	add_child(world)
	_spawned.append(world)
	var knight := Node2D.new()
	knight.add_to_group("player")
	world.add_child(knight)
	world.scene_file_path = GameContext.WORLD_PATH
	eq(presentation.call("_kicker_for_current_level"), ChapterText.boss_intro_of("stage01"),
			"stage01 reads Executioner epithet")
	world.scene_file_path = String(GameContext.LEVELS["stage05"])
	eq(presentation.call("_kicker_for_current_level"), ChapterText.boss_intro_of("stage05"),
			"stage05 reads Bell Founder epithet")
	world.scene_file_path = String(GameContext.LEVELS["stage04"])
	eq(presentation.call("_kicker_for_current_level"), "", "wave-only stage has no boss kicker")
	world.scene_file_path = GameContext.LEGACY_WORLD_PATH
	eq(presentation.call("_kicker_for_current_level"), ChapterText.boss_intro_of("level01"),
			"legacy Level01_Static still reads legacy epithet")
