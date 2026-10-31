extends TestCase
## StoryFlow（v4「焚名轮回」实时叙事版）回归契约：
##   1. 进出大区彻底取消 13 段黑屏幕间播片（BOUNDARIES 为空、arrival_steps 恒为空）；
##   2. ChapterTransition 收到 chapter_started 时绝不锁输入、绝不拉起黑屏遮罩，兜底几何布景在暂停/复位下仍安全；
##   3. 四大结局（give / keep / snuff / true_break）分镜与字幕收束完整对齐；
##   4. 14 节点完成旗标与真名残片动态前情提要（recap_text）准确反映进度。

const Boards := preload("res://scripts/data/storyboards.gd")

var _save_path := ""
var _transition: ChapterTransition


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


func test_zero_black_screen_interludes_across_all_stage_transitions() -> void:
	eq(StoryFlow.boundary_count(), 0, "v4 has zero black-screen chapter interludes")
	eq(StoryFlow.boundaries(), [], "BOUNDARIES is empty")
	for id in ChapterText.order():
		eq(StoryFlow.arrival_steps(id), [], "%s has zero blocking arrival steps" % id)
		eq(StoryFlow.for_edge(id), {}, "%s has no blocking boundary edge" % id)
		_transition._on_chapter_started(id)
		await get_tree().process_frame
		ok(not _transition.is_playing(), "%s arrival never locks screen in ChapterTransition" % id)
		ok(not Director.is_input_locked(), "%s arrival keeps player controls unlocked" % id)


func test_fallback_staging_art_freezes_on_pause_and_resets_cleanly() -> void:
	for staging in ["door", "water", "canal", "crypt", "workshop", "rain", "bell", "heart"]:
		_transition._show_staging(staging)
		eq(_transition.staging(), staging)
	_transition._show_staging("door")
	await flush(4)
	var before := _transition.staging_age()
	ok(before > 0.0, "fallback staging animates while unpaused")
	get_tree().paused = true
	for _i in 8:
		await get_tree().process_frame
	almost(_transition.staging_age(), before, 0.001, "tree pause freezes staging clock")
	get_tree().paused = false
	_transition.reset_view()
	eq(_transition.staging(), "", "reset hides fallback staging")


func test_four_endings_sequences_and_boards_align_with_registry() -> void:
	for kind in ["give", "keep", "snuff", "true_break"]:
		var post := StoryFlow.post_ending_steps(kind)
		ok(not post.is_empty(), "%s ending has post_ending_steps" % kind)
		eq(String((post[0] as Dictionary).get("kind", "")), "lock")
		eq(String((post[post.size() - 1] as Dictionary).get("kind", "")), "unlock")
		ok(StoryFlow.post_ending_line(kind) != "", "%s has closing framing line" % kind)

		var steps := StoryFlow.ending_steps(kind)
		eq(steps.size(), 2, "%s ending plays ending board + credits" % kind)
		eq(String((steps[0] as Dictionary).get("id", "")), Boards.ending_id(kind))
		eq(String((steps[1] as Dictionary).get("id", "")), Boards.CREDITS)
		for raw in steps:
			eq(String((raw as Dictionary).get("kind", "")), "board")
			ok(Boards.has(String((raw as Dictionary).get("id", ""))), "%s board exists" % kind)
			eq(bool((raw as Dictionary).get("skip_all", true)), false)

		var expected: Array[String] = []
		for line in ChapterText.ending_lines_of(kind):
			expected.append(String(line))
		expected.append(StoryFlow.post_ending_line(kind))
		eq(Boards.lines_of(Boards.ending_id(kind)), expected,
				"%s board reads ending lines + closing line" % kind)
		eq(Boards.title_of(Boards.ending_id(kind)), "结局 · %s" % Boards.ending_name(kind))


func test_recap_tracks_stage_nodes_legacy_flags_and_truth_fragments() -> void:
	eq(StoryFlow.recap_text(), StoryFlow.RECAP_FALLBACK, "fresh save uses fallback recap")
	SaveData.mark_flag("stage01_done")
	eq(StoryFlow.recap_text(), ChapterText.recap_of("stage01"))
	SaveData.mark_flag("truth_1")
	SaveData.mark_flag("branch01_done")
	var with_frag := StoryFlow.recap_text()
	ok(with_frag.contains(ChapterText.recap_of("branch01")), "includes branch01 recap")
	ok(with_frag.contains("真名残片 1 / 5"), "appends truth fragment progress")
	SaveData.mark_flag("stage02_done")
	SaveData.mark_flag("stage03_done")
	var recent := StoryFlow.recap_text()
	ok(recent.contains(ChapterText.recap_of("stage03")), "shows newest cleared stage")
	ok(not recent.contains(ChapterText.recap_of("stage01")), "keeps recap compact (last 2 nodes)")
	eq(StoryFlow.cleared_chapters(), ["stage01", "branch01", "stage02", "stage03"])
