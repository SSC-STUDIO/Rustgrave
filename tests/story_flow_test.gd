extends TestCase
## 章间间幕：13 条边界齐备、开演一次、跳过算看过、暂停冻结、死亡/切场硬复位、
## 不写未完成章节旗标、结局前后特殊序列、暂停菜单前情提要。

const DOC_PATH := "res://docs/story.md"
const ALLOWED_STAGING: Array[String] = [
	"door", "water", "canal", "town", "crypt", "workshop", "rain", "bell",
	"foundry", "slag", "rampart", "wind", "heart",
]
const ALLOWED_STEP_KINDS: Array[String] = [
	"lock", "unlock", "wait", "tableau", "caption", "cam_focus", "cam_release",
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


func test_arrival_steps_are_lock_captions_unlock() -> void:
	for edge in StoryFlow.boundaries():
		var to := String(edge["to"])
		var steps := StoryFlow.arrival_steps(to)
		ok(not steps.is_empty(), "%s has arrival steps" % to)
		eq(String((steps[0] as Dictionary).get("kind", "")), "lock", "%s starts locked" % to)
		eq(String((steps[steps.size() - 1] as Dictionary).get("kind", "")), "unlock",
				"%s ends unlocked" % to)
		var captions: Array[String] = []
		for raw in steps:
			var step: Dictionary = raw
			ok(ALLOWED_STEP_KINDS.has(String(step.get("kind", ""))),
					"%s only uses Director kinds" % to)
			if String(step.get("kind", "")) == "caption":
				captions.append(String(step.get("text", "")))
		var expected: Array[String] = []
		for line in edge.get("epilogue", []):
			expected.append(String(line))
		for line in edge.get("teaser", []):
			expected.append(String(line))
		if String(edge.get("special", "")) == "pre_ending":
			for line in StoryFlow.SPECIALS["pre_ending"]["lines"]:
				expected.append(String(line))
		expected.append("目标 · " + ChapterText.objective_of(to))
		eq(captions, expected, "%s interlude reads epilogue → teaser → objective" % to)
		var seconds := Director.estimate_seconds(steps)
		# 终章前要把两个选择的代价说清，所以那条间幕允许更长。
		var limit := 30.0 if String(edge.get("special", "")) == "pre_ending" else 18.0
		ok(seconds <= limit, "%s interlude stays a bridge (%.1fs <= %.0f)" % [to, seconds, limit])


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
	ok(_transition.staging() == "door", "the staging belongs to the boundary")
	ok(Director.playing, "the interlude runs through the Director")
	ok(Director.skips_whole_script(), "one accept skips the whole interlude")
	ok(SaveData.has_flag("interlude_level01_seen"), "the flag is written when the interlude starts")
	_accept()
	ok(not Director.playing, "skip ends the interlude in one press")
	ok(not Director.is_input_locked(), "skip releases the input lock")
	await flush(2)
	eq(_transition.staging(), "", "skip hides the staging art")
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


func test_pause_freezes_the_staging_clock() -> void:
	await _arrive("level02")
	ok(_transition.is_playing())
	await flush(4)
	var before := _transition.staging_age()
	ok(before > 0.0, "the staging animates while the game runs")
	get_tree().paused = true
	for _i in 8:
		await get_tree().process_frame
	almost(_transition.staging_age(), before, 0.001, "tree pause freezes the staging clock")
	get_tree().paused = false
	for _i in 8:
		await get_tree().process_frame
	ok(_transition.staging_age() > before, "unpausing resumes the staging clock")
	Director.abort()
	_transition.reset_view()
	await flush(1)


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
	var steps := StoryFlow.arrival_steps("level10")
	var texts: Array[String] = []
	for raw in steps:
		if String((raw as Dictionary).get("kind", "")) == "caption":
			texts.append(String((raw as Dictionary).get("text", "")))
	for line in StoryFlow.SPECIALS["pre_ending"]["lines"]:
		ok(texts.has(String(line)), "the pre-ending special line plays: %s" % line)
	ok(texts[texts.size() - 1].contains("目标"), "the interlude closes on the objective")
	# 盲测 P0：做选择前必须把两个选择的代价说清（结局词面要能区分）。
	var specials := " ".join(StoryFlow.SPECIALS["pre_ending"]["lines"])
	ok(specials.contains("送剑") and specials.contains("守火"),
			"both choices are named before the final door")
	ok(specials.contains("散成铁") and specials.contains("城终于睡下"), "the give cost is stated")
	ok(specials.contains("一年一年") and specials.contains("城还醒着"), "the keep cost is stated")
	ok(specials.contains("都要付账"), "the interlude says both choices cost something")

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
	ok(StoryFlow.post_ending_line("give").contains("听不真"),
			"give's closing keeps the fire's answer ambiguous")
	ok(StoryFlow.post_ending_line("keep").contains("城还醒着"),
			"keep closes with the city still awake")


## M1R3 canon：间幕不出现设计术语/旧称呼；伊尔动作有「封核之前」；代价预埋；钥匙落地。
func test_interludes_keep_the_core_canon() -> void:
	var all := ""
	for edge in StoryFlow.boundaries():
		all += " " + " ".join(edge.get("epilogue", []))
		all += " " + " ".join(edge.get("teaser", []))
	for word in ["骑士", "陵墓", "塞进剑", "你这把剑", "你这一把", "收索", "欠伊尔一次回答",
			"不是灯芯", "第一幕", "第二幕", "幕", "债", "借他们的手艺往前"]:
		ok(not all.contains(word), "interludes do not use the retired wording '%s'" % word)
	# 渣渊间幕必须说：伊尔（封核之前）把残芯嵌进你背上的剑、点亮你。
	var slag_edge := StoryFlow.for_edge("level08")
	ok(not slag_edge.is_empty(), "the slag boundary exists")
	var slag := " ".join(slag_edge["epilogue"])
	ok(slag.contains("封核之前") and slag.contains("残芯嵌进你背上的剑"),
			"the slag interlude marks Yir's action as pre-sealing")
	# 第二幕开场：债只作剧情句（你欠她一次问火），不带幕/债的设计词。
	var debt_edge := StoryFlow.for_edge("level03")
	ok(" ".join(debt_edge["epilogue"]).contains("你欠她一次问火"),
			"the bridge points the debt the right way: you owe her one question")
	ok(" ".join(debt_edge["epilogue"]).contains("往下走，才有机会还"),
			"the bridge tells you where to go to pay it back, in plain plot terms")
	# 地窖→工坊：伊尔的动作是她留下的字/封核前画的一笔，不是现在时。
	var crypt_edge := StoryFlow.for_edge("level04b")
	var crypt_text := " ".join(crypt_edge["epilogue"]) + " " + " ".join(crypt_edge["teaser"])
	ok(crypt_text.contains("封核之前") and crypt_text.contains("画的一笔"),
			"the workshop bridge uses the page she left, not a present-tense Yir")
	# 工坊→墓园：借手艺在通关时兑现，不是空口欠债。
	var rain_edge := StoryFlow.for_edge("level05")
	ok(" ".join(rain_edge["epilogue"]).contains("机关") and " ".join(rain_edge["epilogue"]).contains("手艺"),
			"the borrowed craft pays off at the next mechanism")
	# 墓园→钟楼：第一次预埋「还火的人自己也要进炉」的代价。
	ok(" ".join(StoryFlow.for_edge("level06")["epilogue"]).contains("自己也要进炉"),
			"the bell bridge seeds the cost of returning the fire")
	var under := " ".join(StoryFlow.for_edge("level02")["teaser"]) \
			+ " " + " ".join(StoryFlow.for_edge("level01")["teaser"])
	ok(under.contains("要下去，得先上去"), "the undercroft interlude explains the climb-first route")
	# 钟舌熔核的发现留到 ch9，间幕不在 ch6→07 提前剧透。
	var bell_teaser := " ".join(StoryFlow.for_edge("level06")["teaser"])
	ok(not bell_teaser.contains("熔"), "the bell-tower teaser does not spoil the melted tongue")
	# 终章前的 teaser 让钥匙落地（门认核不认人）。
	ok(" ".join(StoryFlow.for_edge("level09b")["teaser"]).contains("门认核不认人"),
			"the final bridge turns the key into a door rule")


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
	# 渲染夹具与暂停菜单共用同一份预览入口；直接构造步骤也算一次真实播放。
	ok(_transition.preview("level01"), "preview plays the first boundary")
	ok(_transition.is_playing(), "preview reports playing")
	Director.abort()
	_transition.reset_view()
	ok(not _transition.preview("level10", "level09"), "preview rejects a mismatched target")
