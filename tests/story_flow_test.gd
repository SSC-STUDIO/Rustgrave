extends TestCase
## 章间分镜：13 条边界齐备、每条边界有一段分镜、开演一次、跳过算看过、暂停冻结、
## 死亡/切场硬复位、不写未完成章节旗标、结局前后特殊序列、暂停菜单前情提要。

const Boards := preload("res://scripts/data/storyboards.gd")
const DOC_PATH := "res://docs/story.md"
const ALLOWED_STAGING: Array[String] = [
	"door", "water", "canal", "town", "crypt", "workshop", "rain", "bell",
	"foundry", "slag", "rampart", "wind", "heart",
]
const ALLOWED_STEP_KINDS: Array[String] = [
	"lock", "unlock", "wait", "tableau", "caption", "board", "cam_focus", "cam_release",
	"letterbox", "sfx", "fx",
]

var _save_path := ""
var _transition: ChapterTransition
var _docs := ""


func setup() -> void:
	_save_path = SaveData.save_path
	SaveData.save_path = "user://rustgrave_story_flow_test.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.ending = ""
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	StoryStage.forget()
	if get_tree().paused:
		get_tree().paused = false
	_transition = ChapterTransition.new()
	_transition.test_enabled = true
	add_child(_transition)
	var file := FileAccess.open(DOC_PATH, FileAccess.READ)
	if file != null:
		_docs = file.get_as_text()
		file.close()


func teardown() -> void:
	Director.test_boards = false
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	if is_instance_valid(_transition):
		_transition.queue_free()
		_transition = null
	SaveData.delete_save()
	SaveData.save_path = _save_path
	SaveData.flags.clear()
	SaveData.ending = ""
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false


func _accept() -> void:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Director._unhandled_input(event)


## 直接驱动执行器（不走 GameEvents.chapter_started，免得 autoload 的 StoryStage
## 在用例中途做场景复位）。deferred 的 _start_arrival 在下一帧跑。
func _arrive(level_id: String) -> void:
	_transition._on_chapter_started(level_id)
	await get_tree().process_frame
	await get_tree().process_frame


# --- 数据 -----------------------------------------------------------------------

func test_boundaries_cover_all_thirteen_transitions_in_order() -> void:
	var order := ChapterText.order()
	eq(StoryFlow.boundary_count(), 13, "fourteen chapters meet at thirteen boundaries")
	var boundaries := StoryFlow.boundaries()
	for i in boundaries.size():
		var edge: Dictionary = boundaries[i]
		eq(String(edge["from"]), order[i], "boundary %d starts at %s" % [i, order[i]])
		eq(String(edge["to"]), order[i + 1], "boundary %d arrives at %s" % [i, order[i + 1]])
		ok(ALLOWED_STAGING.has(StoryFlow.staging_of(edge)),
				"boundary %d uses a known staging" % i)
		var epilogue: Array = edge.get("epilogue", [])
		ok(epilogue.size() >= 2 and epilogue.size() <= 3,
				"boundary %d has a 2-3 sentence epilogue" % i)
		for line in epilogue:
			ok(String(line).length() >= 4 and String(line).length() <= 40,
					"epilogue line is a readable sentence: %s" % line)
		var teaser: Array = edge.get("teaser", [])
		eq(teaser.size(), 1, "boundary %d has exactly one teaser" % i)
		ok(String(teaser[0]).length() >= 4 and String(teaser[0]).length() <= 40,
				"teaser is one readable sentence: %s" % teaser[0])
	advance_ok()
	var last: Dictionary = boundaries[boundaries.size() - 1]
	eq(String(last.get("special", "")), "pre_ending", "the final boundary is the pre-ending special")
	eq(StoryFlow.staging_of(last), "heart", "the pre-ending interlude is staged on the heart")


func advance_ok() -> void:
	var flags := {}
	for edge in StoryFlow.boundaries():
		var flag := StoryFlow.interlude_flag(String(edge["from"]))
		ok(not flags.has(flag), "interlude flag %s is unique" % flag)
		flags[flag] = true
		eq(flag, "interlude_%s_seen" % String(edge["from"]),
				"interlude flag follows the contract name")


func test_arrival_steps_are_lock_board_unlock() -> void:
	for edge in StoryFlow.boundaries():
		var to := String(edge["to"])
		var from := String(edge["from"])
		var steps := StoryFlow.arrival_steps(to)
		eq(steps.size(), 3, "%s arrival is lock / board / unlock" % to)
		eq(String((steps[0] as Dictionary).get("kind", "")), "lock", "%s starts locked" % to)
		eq(String((steps[1] as Dictionary).get("kind", "")), "board", "%s plays one storyboard" % to)
		eq(String((steps[1] as Dictionary).get("id", "")), Boards.interlude_id(from),
				"%s plays the storyboard of the boundary it crosses" % to)
		eq(String((steps[2] as Dictionary).get("kind", "")), "unlock", "%s ends unlocked" % to)
		for raw in steps:
			ok(ALLOWED_STEP_KINDS.has(String((raw as Dictionary).get("kind", ""))),
					"%s only uses Director kinds" % to)
		# 目标一句不在章间里重复：由章节自己的醒来流程给（只念一遍）。
		for raw in steps:
			ok(not String((raw as Dictionary).get("text", "")).begins_with("目标"),
					"%s interlude does not repeat the objective" % to)
		ok(Boards.has(Boards.interlude_id(from)), "%s has a storyboard" % from)
		var seconds := Director.estimate_seconds(steps)
		eq(seconds, Boards.seconds_of(Boards.interlude_id(from)),
				"%s estimate is the storyboard's own length" % to)
		# 终章前要把两个选择的代价说清，所以那条间幕允许更长。
		var limit := 30.0 if String(edge.get("special", "")) == "pre_ending" else 18.0
		ok(seconds <= limit, "%s interlude stays a bridge (%.1fs <= %.0f)" % [to, seconds, limit])


## 分镜里念的台词 = StoryFlow.lines_of 的顺序（epilogue → teaser →（终章前）代价），
## 每个镜头有布景，章间每段 2–3 个镜头。
func test_each_interlude_storyboard_reads_its_boundary_lines() -> void:
	for edge in StoryFlow.boundaries():
		var from := String(edge["from"])
		var id := Boards.interlude_id(from)
		var shots := Boards.shots(id)
		var pre_ending := String(edge.get("special", "")) == "pre_ending"
		eq(shots.size(), 3 if pre_ending else 2, "%s has %s shots" % [id, 3 if pre_ending else 2])
		for shot in shots:
			ok(String((shot as Dictionary).get("set", "")) != "", "%s: every shot has a set" % id)
		eq(Boards.lines_of(id), StoryFlow.lines_of(edge), "%s reads epilogue → teaser (→ cost)" % id)
		ok(Boards.title_of(id).begins_with("章间"), "%s has a replay title" % id)


func test_docs_interludes_match_flow_data() -> void:
	ok(_docs != "", "docs/story.md is readable")
	var rows: Array = []
	for raw in _docs.split("\n"):
		var line := String(raw).strip_edges()
		if not line.begins_with("|") or not line.contains("→"):
			continue
		var cells := line.split("|")
		if cells.size() < 5:
			continue
		# 只认「01→02」这种边界行；章节拍表的去向列也有 →，不能算进来。
		var edge_label := String(cells[1]).strip_edges()
		if not edge_label.begins_with("0") or edge_label.length() > 8:
			continue
		rows.append(cells)
	eq(rows.size(), 13, "docs pins all thirteen interludes")
	var boundaries := StoryFlow.boundaries()
	for i in rows.size():
		var cells: PackedStringArray = rows[i]
		var epilogue := String(cells[2]).strip_edges().split("｜")
		var teaser := String(cells[3]).strip_edges()
		var edge: Dictionary = boundaries[i]
		var expected_epilogue: Array = edge["epilogue"]
		eq(epilogue.size(), expected_epilogue.size(), "docs epilogue count matches boundary %d" % i)
		for j in mini(epilogue.size(), expected_epilogue.size()):
			eq(String(epilogue[j]).strip_edges(), String(expected_epilogue[j]),
					"docs epilogue %d/%d is in sync" % [i, j])
		eq(teaser, String((edge["teaser"] as Array)[0]),
				"docs teaser %d is in sync" % i)


# --- 执行器 ---------------------------------------------------------------------

func test_interlude_plays_once_and_skip_counts_as_seen() -> void:
	await _arrive("level02")
	ok(_transition.is_playing(), "arrival starts the level01→level02 interlude")
	eq(_transition.board_id(), "interlude_level01", "the storyboard belongs to the boundary")
	eq(_transition.staging(), "", "a boundary with a storyboard needs no geometric fallback")
	ok(Director.playing, "the interlude runs through the Director")
	ok(Director.skips_whole_script(), "one accept skips the whole interlude")
	ok(SaveData.has_flag("interlude_level01_seen"), "the flag is written when the interlude starts")
	_accept()
	ok(not Director.playing, "skip ends the interlude in one press")
	ok(not Director.is_input_locked(), "skip releases the input lock")
	await flush(2)
	eq(_transition.board_id(), "", "skip clears the storyboard id")
	# 再进同一关：旗标在，不重播。
	await _arrive("level02")
	ok(not _transition.is_playing(), "an interlude never plays twice")
	ok(not Director.playing)
	eq(SaveData.flags.count("interlude_level01_seen"), 1, "the interlude flag is written once")


## 到达顺序：间幕先播，章节卡与醒来句排在 Director 队列后面接上（ChapterLevel._wake
## 用 play_when_clear，间幕占着屏幕时它们只会入队）。跳过间幕不会吞掉章节卡。
func test_chapter_card_and_wake_queue_behind_the_interlude() -> void:
	await _arrive("level02")
	ok(_transition.is_playing(), "the interlude owns the screen first")
	Director.play_when_clear([
		{"kind": "lock"},
		ChapterLevel.chapter_card(ChapterText.title_of("level02")),
		{"kind": "caption", "text": ChapterText.wake_of("level02"), "hold": 0.2},
		{"kind": "unlock"},
	], true)
	ok(Director.pending_scripts() >= 1, "the chapter card waits in the Director queue")
	_accept()
	await flush(2)
	ok(Director.playing, "skipping the interlude hands over to the chapter card")
	_accept()
	await flush(2)
	ok(not Director.playing, "the card and wake line finish cleanly")
	ok(not Director.is_input_locked(), "input is back after the arrival sequence")
	ok(SaveData.has_flag("interlude_level01_seen"), "skipping still marks the interlude seen")


## 真播放：分镜播放器收到 board 步骤、画出来，一次确认键整段跳过（过了输入宽限之后），
## 看过的旗标由开演那一刻写下。
func test_a_live_board_plays_through_the_director_and_skips() -> void:
	Director.test_boards = true
	await _arrive("level02")
	ok(Director.playing and _transition.is_playing(), "the interlude is running")
	ok(Director.board_active(), "the storyboard player owns the screen")
	eq(String(Director.board().get("current_id")), "interlude_level01", "it is the boundary's storyboard")
	ok(Director.board().visible, "the board layer is visible")
	await get_tree().create_timer(0.6, true, false, true).timeout
	_accept()
	ok(await wait_until(func() -> bool: return not Director.playing),
			"one accept skips the whole interlude")
	ok(not Director.board_active(), "the board player is done")
	ok(not Director.is_input_locked(), "input is back")
	ok(SaveData.has_flag(Boards.seen_flag("interlude_level01")), "the replay list will offer it")
	ok(SaveData.has_flag("interlude_level01_seen"), "the interlude flag is written")


## 没有对应分镜的边界退回字幕版：仍然是 lock → 台词 → unlock，不卡死。
func test_a_boundary_without_a_storyboard_falls_back_to_captions() -> void:
	var steps := _transition.fallback_steps(StoryFlow.for_edge("level01"))
	eq(String((steps[0] as Dictionary).get("kind", "")), "lock", "fallback starts locked")
	eq(String((steps[steps.size() - 1] as Dictionary).get("kind", "")), "unlock", "fallback ends unlocked")
	var texts: Array[String] = []
	for raw in steps:
		if String((raw as Dictionary).get("kind", "")) == "caption":
			texts.append(String((raw as Dictionary).get("text", "")))
	eq(texts, StoryFlow.lines_of(StoryFlow.for_edge("level01")), "the fallback reads the same lines")


func test_interlude_writes_no_chapter_flags() -> void:
	await _arrive("level02")
	_accept()
	await flush(2)
	for id in ChapterText.order():
		for flag in [StoryFlow.done_flag(id), "%s_wake" % id, "%s_done" % id]:
			if flag == "":
				continue
			ok(not SaveData.has_flag(flag),
					"the interlude does not complete %s (%s)" % [id, flag])
	ok(not SaveData.has_flag("wake"), "the interlude does not fake the opening's wake flag")
	eq(SaveData.ending, "", "the interlude never writes an ending")


func test_pause_freezes_the_storyboard_clock() -> void:
	Director.test_boards = true
	await _arrive("level02")
	ok(_transition.is_playing() and Director.board_active())
	await flush(4)
	var board := Director.board()
	var before := float(board.call("age"))
	ok(before > 0.0, "the storyboard runs while the game runs")
	get_tree().paused = true
	for _i in 8:
		await get_tree().process_frame
	almost(float(board.call("age")), before, 0.001, "tree pause freezes the storyboard clock")
	get_tree().paused = false
	for _i in 8:
		await get_tree().process_frame
	ok(float(board.call("age")) > before, "unpausing resumes the storyboard clock")
	Director.abort()
	_transition.reset_view()
	await flush(1)
	ok(not Director.board_active(), "abort stops the storyboard")


## 兜底几何布景也在暂停时冻住（没有分镜的边界才会用到它）。
func test_fallback_staging_art_freezes_on_pause() -> void:
	_transition._show_staging("door")
	await flush(4)
	var before := _transition.staging_age()
	ok(before > 0.0, "the fallback staging animates while the game runs")
	get_tree().paused = true
	for _i in 8:
		await get_tree().process_frame
	almost(_transition.staging_age(), before, 0.001, "tree pause freezes the staging clock")
	get_tree().paused = false
	_transition.reset_view()
	eq(_transition.staging(), "", "reset hides the fallback staging")


func test_death_reload_does_not_replay_but_scene_change_resets() -> void:
	await _arrive("level02")
	ok(_transition.is_playing())
	# 死亡：Director 硬复位 + 执行器复位（StoryStage 在 player_died 上两个都调）。
	Director.reset_view()
	_transition._on_player_died()
	ok(not _transition.is_playing(), "death stops the interlude")
	eq(_transition.staging(), "", "death hides the staging art")
	ok(not Director.is_input_locked(), "death releases the input lock")
	# 读档回到同一关：旗标已点（开演时点的），不重播。
	await _arrive("level02")
	ok(not _transition.is_playing(), "a death reload never replays the interlude")
	# 切场硬复位幂等。
	_transition.reset_view()
	_transition.reset_view()
	eq(_transition.staging(), "")
	ok(not _transition.is_playing())


## 真实的死亡读档会把旗标回卷到上一次存档（章间旗标开演才点、还没存进去）。本会话记忆
## （StoryStage.once）补上这个缺口；回标题 / 新游戏清掉记忆后，新一局照常播。
func test_death_reload_with_rewound_flags_still_does_not_replay() -> void:
	SaveData.mark_flag("wake")
	await _arrive("level02")
	ok(_transition.is_playing(), "the first arrival plays the interlude")
	Director.reset_view()
	_transition._on_player_died()
	SaveData.flags.clear()
	SaveData.mark_flag("wake")
	ok(not SaveData.has_flag("interlude_level01_seen"), "fixture: the save was rewound past the flag")
	await _arrive("level02")
	ok(not _transition.is_playing(), "the session memory stops a death reload from replaying it")
	StoryStage.forget()
	await _arrive("level02")
	ok(_transition.is_playing(), "a new game / the title clears that memory")


func test_abort_before_the_script_starts_is_not_seen() -> void:
	# 暂停时到达：Director.play_when_clear 会挂起，从未真正开演。
	get_tree().paused = true
	_transition._on_chapter_started("level03")
	await get_tree().process_frame
	await get_tree().process_frame
	ok(not SaveData.has_flag("interlude_level02b_seen"),
			"a held interlude does not mark itself seen before it plays")
	Director.reset_view()
	_transition._on_player_died()
	get_tree().paused = false
	await flush(2)
	ok(not SaveData.has_flag("interlude_level02b_seen"),
			"an aborted interlude stays unseen so the bridge still plays later")
	ok(not Director.playing)


func test_pre_ending_and_post_ending_sequences() -> void:
	var edge := StoryFlow.for_edge("level09b")
	ok(not edge.is_empty(), "the level09b boundary exists")
	eq(StoryFlow.staging_of(edge), "heart", "the pre-ending interlude is staged on the heart")
	eq(ChapterText.order()[ChapterText.order().size() - 1], String(edge["to"]),
			"the pre-ending interlude arrives at the final chapter")
	# 终章前的分镜读出三句：到了 / 还火的代价 / 守炉的代价。
	var board_lines := Boards.lines_of(Boards.interlude_id("level09b"))
	for line in StoryFlow.SPECIALS["pre_ending"]["lines"]:
		ok(board_lines.has(String(line)), "the pre-ending special line plays: %s" % line)
	eq(board_lines[board_lines.size() - 1], String(StoryFlow.SPECIALS["pre_ending"]["lines"][2]),
			"the interlude closes on the cost of keeping")
	var specials := " ".join(StoryFlow.SPECIALS["pre_ending"]["lines"])
	ok(specials.contains("还火：") and specials.contains("守炉："),
			"both choices are named before the final door")
	ok(specials.contains("名字都能走") and specials.contains("散成铁"),
			"the give cost is stated (names leave, you scatter)")
	ok(specials.contains("新的守炉人") and specials.contains("城一直半醒"),
			"the keep cost is stated (you become the next keeper, the city half-awake)")

	for kind in ["give", "keep", "snuff"]:
		var ending := StoryFlow.post_ending_steps(kind)
		ok(not ending.is_empty(), "%s ending plays a sequence" % kind)
		eq(String((ending[0] as Dictionary).get("kind", "")), "lock", "%s starts locked" % kind)
		eq(String((ending[ending.size() - 1] as Dictionary).get("kind", "")), "unlock",
				"%s ends unlocked" % kind)
		var captions: Array[String] = []
		for raw in ending:
			if String((raw as Dictionary).get("kind", "")) == "caption":
				captions.append(String((raw as Dictionary).get("text", "")))
		var expected := ChapterText.ending_lines_of(kind)
		for i in expected.size():
			eq(captions[i], String(expected[i]), "%s ending line %d matches the registry" % [kind, i])
		eq(captions[captions.size() - 1], StoryFlow.post_ending_line(kind),
				"%s ends on its closing line" % kind)
		ok(StoryFlow.post_ending_line(kind) != "", "%s has a closing framing line" % kind)
	ok(StoryFlow.post_ending_line("give") != StoryFlow.post_ending_line("keep"),
			"the two endings close differently")
	ok(StoryFlow.post_ending_line("give").contains("都走了"),
			"give closes on the names finally leaving")
	ok(StoryFlow.post_ending_line("keep").contains("城一直半醒"),
			"keep closes with the city half-awake")
	ok(StoryFlow.post_ending_line("snuff").contains("再没有人替名字问一句"),
			"snuff closes on nobody asking for the names")


## 结局演出 = 结局分镜 + 滚动字幕；分镜读的就是注册表里的结局字幕 + 一句收束，顺序不变。
func test_ending_boards_read_the_registry_and_end_in_credits() -> void:
	for kind in ["give", "keep", "snuff"]:
		var steps := StoryFlow.ending_steps(kind)
		eq(steps.size(), 2, "%s ending plays two boards" % kind)
		eq(String((steps[0] as Dictionary).get("id", "")), Boards.ending_id(kind), "%s: its own board first" % kind)
		eq(String((steps[1] as Dictionary).get("id", "")), Boards.CREDITS, "%s: credits last" % kind)
		for raw in steps:
			eq(String((raw as Dictionary).get("kind", "")), "board", "%s uses board steps" % kind)
			ok(Boards.has(String((raw as Dictionary).get("id", ""))), "%s: the board exists" % kind)
			eq(bool((raw as Dictionary).get("skip_all", true)), false, "%s: endings advance line by line" % kind)
		var expected: Array[String] = []
		for line in ChapterText.ending_lines_of(kind):
			expected.append(String(line))
		expected.append(StoryFlow.post_ending_line(kind))
		eq(Boards.lines_of(Boards.ending_id(kind)), expected,
				"%s board reads the ending lines then the closing line" % kind)
		var shots := Boards.shots(Boards.ending_id(kind))
		var art_shots := 0
		var art_text := ""
		for raw_shot in shots:
			var shot: Dictionary = raw_shot
			if String(shot.get("art", "")) == "ending_%s" % kind:
				art_shots += 1
				art_text = " ".join(PackedStringArray(shot.get("lines", []) as Array))
		eq(art_shots, 1, "%s has exactly one illustrated shot" % kind)
		if kind == "give":
			ok(art_text.contains("铁屑") or art_text.contains("散"),
					"give's picture sits on the shot where you scatter into iron")
		elif kind == "keep":
			ok(art_text.contains("守下去"),
					"keep's picture sits on the vigil, not the moment the door opens")
		else:
			ok(art_text.contains("一点红"),
					"snuff's picture sits on the dark city and the last red in the furnace door")
		eq(Boards.title_of(Boards.ending_id(kind)), "结局 · %s" % Boards.ending_name(kind), "%s has a replay title" % kind)
	var credits := Boards.shots(Boards.CREDITS)
	eq(credits.size(), 1, "credits are one scrolling shot")
	ok((credits[0] as Dictionary).has("scroll") and not ((credits[0] as Dictionary)["scroll"] as Array).is_empty(),
			"the credits scroll something")
	for line in Boards.CREDITS_LINES:
		ok(not line.contains("幕"), "credits do not use the design term")


## M1R4 canon：间幕不出现设计术语/旧称呼；术语统一；路线与门序有交代。
func test_interludes_keep_the_core_canon() -> void:
	var all := ""
	for edge in StoryFlow.boundaries():
		all += " " + " ".join(edge.get("epilogue", []))
		all += " " + " ".join(edge.get("teaser", []))
	for word in ["陵墓", "塞进剑", "你这把剑", "你这一把", "收索", "欠伊尔一次回答",
			"不是灯芯", "第一幕", "第二幕", "幕", "债", "借他们的手艺往前",
			"插座", "封核", "封进核", "炉门", "提前离场结局", "净化偶", "残芯"]:
		ok(not all.contains(word), "interludes do not use the retired wording '%s'" % word)
	# 第一章：续火 → 收回剑里 → 石板松开。
	var first := " ".join(StoryFlow.for_edge("level01")["epilogue"])
	ok(first.contains("火种在炉座上亮了") and first.contains("收回剑里"),
			"the first bridge says the fire seed was relit and taken back")
	ok(" ".join(StoryFlow.for_edge("level01")["teaser"]).contains("下面有钟声"),
			"the first bridge points down to the bell")
	# 渣渊间幕必须说：伊尔（封进火种之前）从渣里把你捡起来。
	var slag_edge := StoryFlow.for_edge("level08")
	ok(not slag_edge.is_empty(), "the slag boundary exists")
	var slag := " ".join(slag_edge["epilogue"])
	ok(slag.contains("封进火种之前") and slag.contains("捡起了你"),
			"the slag interlude marks Yir's action as pre-sealing")
	# 去炉心没有直路：渠里的渣封死下城，只剩圣殿的暗门。
	ok(" ".join(StoryFlow.for_edge("level02b")["epilogue"]).contains("圣殿的暗门"),
			"the canal bridge says the only road is the cathedral's hidden door")
	# 地窖→工坊：末页是一页纸，伊尔的话是她早就想做的事。
	var crypt_edge := StoryFlow.for_edge("level04b")
	var crypt_text := " ".join(crypt_edge["epilogue"]) + " " + " ".join(crypt_edge["teaser"])
	ok(crypt_text.contains("把火还给炉") and crypt_text.contains("把火种交给你"),
			"the workshop bridge links the last page to why she handed you the fire seed")
	ok(crypt_text.contains("手艺"), "the workshop bridge says what the workshop gives the sword")
	# 工坊→墓园：借手艺在通关时兑现，不是空口。
	var rain_text := " ".join(StoryFlow.for_edge("level05")["epilogue"])
	ok(rain_text.contains("锈核") and rain_text.contains("手艺"),
			"the borrowed craft pays off right away")
	# 墓园→钟楼：第一次预埋「还火的人自己也要进炉」的代价。
	ok(" ".join(StoryFlow.for_edge("level06")["epilogue"]).contains("自己也要进炉"),
			"the bell bridge seeds the cost of returning the fire")
	# 钟舌熔成火种的发现留到 ch9，间幕不在 ch8→09 提前剧透。
	var bell_teaser := " ".join(StoryFlow.for_edge("level06")["teaser"])
	ok(not bell_teaser.contains("熔"), "the bell-tower teaser does not spoil the melted tongue")
	ok(" ".join(StoryFlow.for_edge("level07")["epilogue"]).contains("钟舌被熔成了火种"),
			"the bell tower bridge answers where the tongue went")
	# 终章前：门名统一，梦魇守门，火种在你背上。
	var last_teaser := " ".join(StoryFlow.for_edge("level09b")["teaser"])
	ok(last_teaser.contains("炉心门") and last_teaser.contains("梦魇"),
			"the final bridge names the door and who guards it")
	ok(" ".join(StoryFlow.for_edge("level09")["teaser"]).contains("炉心门"),
			"the cliff bridge uses the same door name")
	# 带说话人的句子只用 SPEAKERS 里的名字（名牌认得出）。
	for raw in StoryFlow.boundaries():
		for line in StoryFlow.lines_of(raw):
			var cut := String(line).find("：")
			if cut > 0 and cut <= 4:
				var who := String(line).substr(0, cut)
				if who in ["还火", "守炉"]:
					continue
				ok(ChapterText.SPEAKERS.has(who), "spoken prefix '%s' is a known speaker" % who)


func test_recap_uses_cleared_chapters() -> void:
	eq(StoryFlow.recap_text(), StoryFlow.RECAP_FALLBACK, "a fresh save gets the fallback recap")
	SaveData.mark_flag("boss_dead")
	eq(StoryFlow.recap_text(), ChapterText.recap_of("level01"),
			"one cleared chapter shows its own recap")
	SaveData.mark_flag("undercroft_done")
	var both := StoryFlow.recap_text()
	ok(both.contains(ChapterText.recap_of("level01")), "recent recaps include chapter one")
	ok(both.contains(ChapterText.recap_of("level02")), "recent recaps include chapter two")
	SaveData.mark_flag("level02b_done")
	var recent := StoryFlow.recap_text()
	ok(recent.contains(ChapterText.recap_of("level02b")), "the newest recap is shown")
	ok(not recent.contains(ChapterText.recap_of("level01")),
			"only the last one or two recaps are shown")
	ok(recent.length() <= 120, "the recap line stays a line")
	eq(StoryFlow.cleared_chapters(), ["level01", "level02", "level02b"],
			"cleared chapters follow campaign order and the save flags")


func test_staging_art_handles_every_staging() -> void:
	for edge in StoryFlow.boundaries():
		var staging := StoryFlow.staging_of(edge)
		ok(ALLOWED_STAGING.has(staging), "staging %s is implemented" % staging)
		# 兜底几何布景每一种都能画出来（没有分镜的边界才用它）。
		_transition._show_staging(staging)
		eq(_transition.staging(), staging, "the fallback art shows %s" % staging)
	_transition.reset_view()
	# 渲染夹具与暂停菜单共用同一份预览入口；直接构造步骤也算一次真实播放。
	ok(_transition.preview("level01"), "preview plays the first boundary")
	ok(_transition.is_playing(), "preview reports playing")
	eq(_transition.board_id(), "interlude_level01", "preview plays the boundary's storyboard")
	Director.abort()
	_transition.reset_view()
	ok(not _transition.preview("level10", "level09"), "preview rejects a mismatched target")
