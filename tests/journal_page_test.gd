extends TestCase
## 故事页（暂停菜单「故事」）与标题「回看余烬」总结页：
##   · 故事页：现在要做什么 / 前情 / 人物 / 名词 / 重看，空存档兜底句，←→ 换页，Esc 回暂停菜单；
##   · 重看只列看过的分镜；回放时覆盖层藏起来、播完（或被跳过 / 打断）恢复，且不写「看过」旗标；
##   · 总结页：行集合、结局名、已过章数按 DONE_FLAGS 数、重温序章 / 结局、锁着的试炼不能进。
## 回放用的是真的 Director.board()：测试里用 abort() / skip_all() 收场。

const JournalScript := preload("res://scripts/ui/journal_screen.gd")
const RecapScript := preload("res://scripts/ui/ember_recap.gd")
const Boards := preload("res://scripts/data/storyboards.gd")

var _saved_flags := PackedStringArray()
var _signal_log: Array = []


func setup() -> void:
	_saved_flags = SaveData.flags.duplicate()
	SaveData.flags = PackedStringArray()
	_signal_log = []
	Director.choice_hold = false
	Director.resume()


func teardown() -> void:
	# 回放测试可能留着一段正在播的分镜：收掉，别污染后面的用例。
	if Director.board() != null and Director.board_active():
		Director.board().call("abort")
	SaveData.flags = _saved_flags
	Director.choice_hold = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


func _make_journal():
	var journal = JournalScript.new()
	journal.layer = 21
	add_child(journal)
	await get_tree().process_frame
	return journal


func _press(node: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node.call("_unhandled_input", event)


func _seen_flags() -> PackedStringArray:
	return PackedStringArray([Boards.seen_flag(Boards.PROLOGUE),
			StoryFlow.interlude_flag("level01"), Boards.seen_flag("ending_give")])


# ------------------------------------------------------------ 故事页内容 ----

func test_an_empty_save_shows_the_fallback_recap_and_the_first_goal() -> void:
	var journal = await _make_journal()
	journal.open()
	eq(journal.recap_label().text, StoryFlow.RECAP_FALLBACK, "没通关任何一章：前情用兜底句")
	eq(journal.objective_label().text, ChapterText.objective_of("level01"),
			"没有存档进度：目标是第一章的目标")
	ok(journal.chapter_label().text.contains(ChapterText.name_of("level01")), "章节行写章名")
	ok(journal.replay_ids().is_empty(), "空存档没有可重看的分镜")
	ok(journal.replay_empty_visible(), "重看页给出空态说明")
	eq(journal.replay_menu().items().size(), 0, "空态下菜单一行也没有")
	journal.queue_free()
	await get_tree().process_frame


func test_the_goal_and_the_recap_follow_the_chapter_and_the_flags() -> void:
	SaveData.flags = PackedStringArray([StoryFlow.done_flag("level01"), StoryFlow.done_flag("level02"),
			StoryFlow.done_flag("level02b")])
	var journal = await _make_journal()
	journal.open("level04")
	eq(journal.objective_label().text, ChapterText.objective_of("level04"), "目标按当前章节")
	ok(journal.chapter_label().text.contains(ChapterText.name_of("level04")), "章节行跟着变")
	eq(journal.recap_label().text, StoryFlow.recap_text(), "前情就是 StoryFlow.recap_text()")
	ok(journal.recap_label().text.contains(ChapterText.recap_of("level02b")),
			"最新通关的一章在前情里")
	ok(journal.recap_label().text != StoryFlow.RECAP_FALLBACK, "通关过就不再用兜底句")
	journal.queue_free()
	await get_tree().process_frame


func test_without_a_known_scene_the_goal_comes_from_save_progress() -> void:
	SaveData.flags = PackedStringArray([StoryFlow.done_flag("level01")])
	var journal = await _make_journal()
	journal.open()
	eq(JournalScript.progress_chapter_id(), "level02", "第一章通关了：下一章是第二章")
	eq(journal.objective_label().text, ChapterText.objective_of("level02"))
	journal.queue_free()
	await get_tree().process_frame


func test_cast_and_term_pages_follow_progress_and_keep_the_canonical_sentence() -> void:
	var journal = await _make_journal()
	journal.open()
	var early := ChapterText.progress_index(journal.current_chapter_id(), SaveData.flags)
	eq(journal.cast_names_shown(), ChapterText.revealed_cast(early), "开局只列已出场的人物")
	ok(journal.cast_names_shown().has("余烬骑士") and journal.cast_names_shown().has("伊尔"),
			"没有任何进度也看得到主角和伊尔")
	for hidden in ["灰卫", "哈伦", "薇尔", "梦魇"]:
		ok(not journal.cast_names_shown().has(hidden), "开局不剧透 %s" % hidden)
	for who in journal.cast_names_shown():
		eq(journal.entry_text(JournalScript.TAB_CAST, who), ChapterText.cast_of(who), "%s 的那一句" % who)
	eq(journal.term_names_shown(), ChapterText.revealed_terms(early), "开局只列已出场的名词")
	ok(not journal.term_names_shown().has("锈核"), "锈核要到齿轮工坊才列入名词")
	for term in journal.term_names_shown():
		eq(journal.entry_text(JournalScript.TAB_TERMS, term), ChapterText.term_of(term), "%s 的白话" % term)

	journal.open("level10")
	var late := ChapterText.progress_index("level10", SaveData.flags)
	eq(journal.cast_names_shown(), ChapterText.revealed_cast(late), "走到炉心：人物按进度补全")
	ok(journal.cast_names_shown().has("梦魇"), "炉心章节看得到梦魇")
	ok(journal.term_names_shown().has("锈核"), "过了工坊看得到锈核")
	journal.queue_free()
	await get_tree().process_frame


func test_the_replay_page_lists_only_what_was_seen() -> void:
	SaveData.flags = _seen_flags()
	var journal = await _make_journal()
	journal.open()
	var expected := Boards.replay_list(SaveData.flags)
	eq(journal.replay_ids(), expected, "重看列表 = Boards.replay_list(存档旗标)")
	eq(journal.replay_ids(), [Boards.PROLOGUE, Boards.interlude_id("level01"), Boards.ending_id("give")],
			"看过序章、第一章间幕和还火结局")
	ok(not journal.replay_ids().has(Boards.interlude_id("level02")), "没看过的章间不列")
	ok(not journal.replay_ids().has(Boards.ending_id("keep")), "没看过的结局不列")
	ok(not journal.replay_empty_visible(), "有内容就不显示空态")
	eq(journal.replay_menu().items().size(), expected.size(), "菜单行数 = 列表条数")
	var first: MenuItem = journal.replay_menu().items()[0]
	ok(first._text.contains(Boards.title_of(Boards.PROLOGUE)), "行文字是分镜的名字：%s" % first._text)
	journal.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------- 导航与返回 ----

func test_arrow_keys_switch_pages_and_wrap_around() -> void:
	var journal = await _make_journal()
	journal.open()
	eq(journal.tab_count(), 4, "四页：现在 / 人物 / 名词 / 重看")
	eq(journal.current_tab(), JournalScript.TAB_NOW)
	_press(journal, &"ui_right")
	eq(journal.current_tab(), JournalScript.TAB_CAST, "→ 下一页")
	_press(journal, &"ui_right")
	_press(journal, &"ui_right")
	eq(journal.current_tab(), JournalScript.TAB_REPLAY, "再两下到重看页")
	_press(journal, &"ui_right")
	eq(journal.current_tab(), JournalScript.TAB_NOW, "最后一页再 → 回到第一页")
	_press(journal, &"ui_left")
	eq(journal.current_tab(), JournalScript.TAB_REPLAY, "第一页 ← 绕到最后一页")
	for i in journal.tab_count():
		eq(journal.page(i).visible, i == journal.current_tab(), "只有当前页可见（第 %d 页）" % i)
	ok(journal.hint_text().contains("Enter"), "重看页的提示带里有 Enter 重看")
	journal.show_tab(JournalScript.TAB_CAST)
	ok(not journal.hint_text().contains("Enter"), "文字页的提示带不提 Enter")
	journal.queue_free()
	await get_tree().process_frame


func test_the_replay_list_only_takes_keys_on_its_own_page() -> void:
	SaveData.flags = _seen_flags()
	var journal = await _make_journal()
	journal.open()
	ok(not journal.replay_menu().active, "不在重看页：列表不吃方向键 / 回车")
	journal.show_tab(JournalScript.TAB_REPLAY)
	ok(journal.replay_menu().active, "到了重看页才吃输入")
	journal.show_tab(JournalScript.TAB_CAST)
	ok(not journal.replay_menu().active, "离开重看页又收回去")
	journal.close()
	ok(not journal.replay_menu().active, "关着的页面不吃输入")
	journal.queue_free()
	await get_tree().process_frame


func test_escape_goes_back_to_the_pause_menu() -> void:
	var pause := PauseMenu.new()
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	await get_tree().process_frame
	var journal = pause.journal_screen()
	pause._on_chosen(PauseMenu.ID_STORY)
	await get_tree().process_frame
	ok(journal.visible, "故事页在暂停菜单上打开")
	ok(pause.is_open() and get_tree().paused, "暂停状态不变")
	ok(pause.sub_screen_open(), "暂停菜单知道有子页盖着")
	ok(not pause.menu().active, "盖着时左列不吃输入")
	_press(journal, &"ui_cancel")
	await get_tree().process_frame
	ok(not journal.visible, "Esc 关掉故事页")
	ok(pause.is_open() and get_tree().paused, "回到的是暂停菜单，不是游戏")
	ok(pause.menu().active, "左列重新吃输入")
	pause.close()
	await get_tree().process_frame
	ok(not pause.is_open() and not get_tree().paused, "再关暂停菜单才继续游戏")
	pause.queue_free()
	await get_tree().process_frame


func test_closing_the_pause_menu_takes_the_story_page_with_it() -> void:
	var pause := PauseMenu.new()
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	pause._on_chosen(PauseMenu.ID_STORY)
	await get_tree().process_frame
	ok(pause.journal_screen().visible, "故事页开着")
	pause.close()
	await get_tree().process_frame
	ok(not pause.journal_screen().visible, "关暂停菜单时故事页一起收起")
	ok(not pause.sub_screen_open(), "没有残留的子页")
	pause.queue_free()
	await get_tree().process_frame


# --------------------------------------------------------------- 回放 ----

func _wait_board_idle() -> bool:
	return await wait_until(func() -> bool: return not Director.board_active(), 300)


func test_replay_hides_the_overlays_and_brings_them_back() -> void:
	SaveData.flags = _seen_flags()
	var pause := PauseMenu.new()
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	await get_tree().process_frame
	var journal = pause.journal_screen()
	journal.replay_started.connect(func(id: String) -> void: _signal_log.append("start:" + id))
	journal.replay_finished.connect(func(id: String) -> void: _signal_log.append("end:" + id))
	pause._on_chosen(PauseMenu.ID_STORY)
	journal.show_tab(JournalScript.TAB_REPLAY)
	var pause_root := pause.get_node("ModalRoot") as Control
	ok(pause_root.visible and journal.root_control().visible, "回放前两层都可见")

	ok(journal.play_replay(Boards.PROLOGUE), "看过序章：回放能开始")
	ok(Director.board_active(), "分镜播放器在演")
	ok(journal.replaying(), "故事页知道在回放")
	ok(not journal.root_control().visible, "回放时故事页藏起来")
	ok(not pause_root.visible, "回放时暂停菜单的卡片也藏起来")
	ok(not journal.replay_menu().active, "回放时列表不吃输入")
	eq(_signal_log, ["start:prologue"], "发了 replay_started")
	# 再点一次别的：回放中不叠第二段
	ok(not journal.play_replay(Boards.ending_id("give")), "回放中不能再开第二段")

	Director.board().call("abort")
	await get_tree().process_frame
	ok(not Director.board_active(), "被打断后播放器收起")
	ok(not journal.replaying(), "故事页不再回放")
	ok(journal.root_control().visible, "故事页恢复可见")
	ok(pause_root.visible, "暂停菜单的卡片恢复可见")
	eq(journal.current_tab(), JournalScript.TAB_REPLAY, "回到「重 看」页")
	ok(journal.replay_menu().active, "列表重新吃输入")
	eq(journal.replay_menu().selected_id(), &"prologue", "光标停在刚重看的那一项")
	eq(_signal_log, ["start:prologue", "end:prologue"], "发了 replay_finished")
	ok(pause.is_open() and get_tree().paused, "整个过程暂停没有解除")

	pause.close()
	await get_tree().process_frame
	pause.queue_free()
	await get_tree().process_frame


func test_a_finished_replay_does_not_write_the_seen_flag() -> void:
	SaveData.flags = PackedStringArray([Boards.seen_flag(Boards.PROLOGUE), Boards.seen_flag("ending_give")])
	var before := SaveData.flags.duplicate()
	var journal = await _make_journal()
	journal.open()
	ok(journal.play_replay(Boards.ending_id("give")), "结局回放开始")
	await get_tree().create_timer(0.5).timeout
	Director.board().call("skip_all")
	var idle: bool = await _wait_board_idle()
	ok(idle, "跳过整段后播放器收起")
	ok(not journal.replaying(), "回放结束")
	ok(journal.root_control().visible, "故事页恢复")
	eq(SaveData.flags, before, "回放不写任何旗标")
	journal.queue_free()
	await get_tree().process_frame


func test_replay_is_refused_while_the_story_is_playing_a_board() -> void:
	SaveData.flags = _seen_flags()
	var journal = await _make_journal()
	journal.open()
	ok(bool(Director.board().call("play_board", Boards.PROLOGUE, {"replay": true})), "主线分镜先在播")
	ok(not journal.play_replay(Boards.PROLOGUE), "已有分镜在演：不回放，不打断它")
	ok(Director.board_active(), "原来那段还在演")
	ok(journal.root_control().visible, "故事页没有被藏起来")
	Director.board().call("abort")
	journal.queue_free()
	await get_tree().process_frame


func test_closing_the_page_during_a_replay_stops_it() -> void:
	SaveData.flags = _seen_flags()
	var journal = await _make_journal()
	journal.open()
	ok(journal.play_replay(Boards.PROLOGUE), "回放开始")
	journal.dismiss()
	ok(not Director.board_active(), "页面被收起：播放器一并收起")
	ok(not journal.replaying(), "不再回放")
	ok(not journal.visible, "页面已关")
	journal.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------- 总结页 ----

func _recap_info(ending: String, flags: Array, has_save: bool = true, trial: bool = true) -> Dictionary:
	return {"ending": ending, "flags": PackedStringArray(flags), "has_save": has_save,
			"trial_ready": trial}


func _make_recap():
	var recap = RecapScript.new()
	recap.layer = 4
	add_child(recap)
	await get_tree().process_frame
	return recap


func test_recap_rows_cover_continue_replays_modes_back_and_chapters() -> void:
	var recap = await _make_recap()
	var flags := [StoryFlow.done_flag("level01"), StoryFlow.done_flag("level02"),
			Boards.seen_flag(Boards.PROLOGUE), Boards.seen_flag("ending_give")]
	recap.open(_recap_info("give", flags))
	var ids: Array = recap.row_ids()
	eq(ids, [&"continue", &"replay_prologue", &"replay_ending_give", &"arena", &"trial", &"back",
			&"chapter_level01", &"chapter_level02"], "总结页的行：继续 / 重温序章 / 重温结局 / 模式 / 返回 / 再入各章")
	eq(recap.heading_text(), "结局 · 还火", "标题写结局名")
	eq(recap.count_text(), "已过 2 / 14 章", "第一、二章按 DONE_FLAGS 算进去（boss_dead / undercroft_done）")
	eq(recap.summary_text(), ChapterText.ending_summary_of("give"), "有结局时总结段是结局概述")
	var first: MenuItem = recap.menu().items()[0]
	ok(first._text.contains("继 续 旅 程"), "第一行是继续旅程")
	ok(recap.menu().selected_id() == &"continue", "光标默认停在继续旅程")
	recap.queue_free()
	await get_tree().process_frame


func test_recap_without_a_save_or_an_ending_is_still_sane() -> void:
	var recap = await _make_recap()
	recap.open(_recap_info("", [], false, false))
	eq(recap.heading_text(), "尚无结局")
	eq(recap.count_text(), "已过 0 / 14 章")
	eq(recap.summary_text(), StoryFlow.RECAP_FALLBACK, "没通关：兜底句")
	ok(not recap.row_ids().has(&"continue"), "没存档：没有继续旅程")
	ok(not recap.row_ids().has(&"replay_prologue"), "没看过序章：不列重温")
	var trial: MenuItem = null
	for item in recap.menu().items():
		if (item as MenuItem).id == &"trial":
			trial = item
	ok(trial != null and trial.disabled, "试炼没解锁：置灰")
	var requested := [0]
	recap.trial_requested.connect(func() -> void: requested[0] += 1)
	recap.choose(&"trial")
	eq(requested[0], 0, "锁着的试炼不能进")
	recap.queue_free()
	await get_tree().process_frame


func test_recap_rows_emit_the_requests_the_title_listens_to() -> void:
	var recap = await _make_recap()
	recap.open(_recap_info("keep", [StoryFlow.done_flag("level01"), StoryFlow.done_flag("level02")]))
	var calls: Array = []
	recap.continue_requested.connect(func() -> void: calls.append("continue"))
	recap.arena_requested.connect(func() -> void: calls.append("arena"))
	recap.trial_requested.connect(func() -> void: calls.append("trial"))
	recap.chapter_requested.connect(func(id: String) -> void: calls.append("chapter:" + id))
	recap.closed.connect(func() -> void: calls.append("closed"))
	recap.choose(&"continue")
	recap.choose(&"arena")
	recap.choose(&"trial")
	recap.choose(&"chapter_level02")
	recap.choose(&"back")
	await get_tree().process_frame
	eq(calls, ["continue", "arena", "trial", "chapter:level02", "closed"], "每一行发自己的信号")
	ok(not recap.visible, "返回关掉总结页")
	recap.queue_free()
	await get_tree().process_frame


func test_recap_offers_the_saved_ending_even_without_a_seen_flag() -> void:
	var recap = await _make_recap()
	# 旧存档：分镜系统之前通关的，没有 board_seen_* 旗标，但存档里记着结局。
	recap.open(_recap_info("snuff", [StoryFlow.done_flag("level01")]))
	ok(recap.row_ids().has(&"replay_ending_snuff"), "存档里的结局永远能重温")
	ok(not recap.row_ids().has(&"replay_ending_give"), "没得到过的结局不列")
	recap.queue_free()
	await get_tree().process_frame


func test_recap_replay_hides_the_page_and_brings_it_back() -> void:
	var recap = await _make_recap()
	recap.open(_recap_info("give", [Boards.seen_flag(Boards.PROLOGUE)]))
	recap.replay_started.connect(func(id: String) -> void: _signal_log.append("start:" + id))
	recap.replay_finished.connect(func(id: String) -> void: _signal_log.append("end:" + id))
	recap.choose(&"replay_prologue")
	ok(Director.board_active(), "序章回放开始")
	ok(recap.replaying(), "总结页知道在回放")
	ok(not recap.root_control().visible, "回放时总结页藏起来")
	ok(not recap.menu().active, "回放时列表不吃输入")
	Director.board().call("abort")
	await get_tree().process_frame
	ok(recap.root_control().visible, "播完恢复")
	ok(recap.menu().active, "列表重新吃输入")
	eq(recap.menu().selected_id(), &"replay_prologue", "光标停在刚重温的那一行")
	eq(_signal_log, ["start:prologue", "end:prologue"])
	recap.queue_free()
	await get_tree().process_frame


## 十四章都列出来时列表比卡片高；焦点移到最后一行会把那一行卷进视口。
func test_recap_scrolls_the_focused_chapter_into_view() -> void:
	var flags: Array = []
	for id in ChapterText.order():
		flags.append(StoryFlow.done_flag(id))
	var recap = await _make_recap()
	recap.open(_recap_info("give", flags))
	await get_tree().process_frame
	await get_tree().process_frame
	var ids: Array = recap.row_ids()
	var last := String(ids[ids.size() - 1])
	ok(last.begins_with("chapter_"), "最后一行是再入某章")
	var at := recap.menu().item_ids().find(StringName(last))
	recap.menu().select(at, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := recap.root_control().find_child("Scroll", true, false) as ScrollContainer
	ok(scroll != null and scroll.scroll_vertical > 0, "焦点在末章时列表滚了下去")
	var row := recap.menu().items()[at] as Control
	var view := scroll.get_global_rect()
	var box := row.get_global_rect()
	ok(box.position.y >= view.position.y - 2.0 and box.end.y <= view.end.y + 2.0,
			"末章整行落在视口里 (row %s view %s)" % [box, view])
	var hint := recap.root_control().find_child("MoreHint", true, false) as Label
	ok(hint != null, "溢出时有向下滚动的提示")
	recap.queue_free()
	await get_tree().process_frame


## 摘要得真正画出来（给过高度、没被滚走），视口里露出来的每一行都是整行。
func test_recap_summary_is_shown_and_visible_rows_are_whole() -> void:
	var all_flags: Array = []
	for chapter_id in ChapterText.order():
		all_flags.append(StoryFlow.done_flag(chapter_id))
	var recap = await _make_recap()
	recap.open(_recap_info("give", all_flags))
	await _recap_frames()
	_assert_recap_summary_visible(recap)
	_assert_recap_rows_whole(recap)
	var ids: Array = recap.row_ids()
	var last := String(ids[ids.size() - 1])
	var at := recap.menu().item_ids().find(StringName(last))
	recap.menu().select(at, false)
	await _recap_frames()
	_assert_recap_rows_whole(recap)
	recap.queue_free()
	await get_tree().process_frame

	var mid: Array = []
	var order := ChapterText.order()
	for i in mini(8, order.size()):
		mid.append(StoryFlow.done_flag(order[i]))
	recap = await _make_recap()
	recap.open(_recap_info("", mid))
	await _recap_frames()
	_assert_recap_summary_visible(recap)
	ok(recap.summary_text() != StoryFlow.RECAP_FALLBACK, "进行中显示前情，不是兜底句")
	ok(recap.heading_text() == "尚无结局", "进行中没有结局标题")
	_assert_recap_rows_whole(recap)
	recap.queue_free()
	await get_tree().process_frame

	recap = await _make_recap()
	recap.open(_recap_info("", [], false, false))
	await _recap_frames()
	eq(recap.summary_text(), StoryFlow.RECAP_FALLBACK, "没存档是兜底句")
	_assert_recap_summary_visible(recap)
	_assert_recap_rows_whole(recap)
	recap.queue_free()
	await get_tree().process_frame


func _recap_frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


## 前情住在右侧的档案板里（不随列表滚动）：摘要整段要落在档案卡之内。
func _assert_recap_summary_visible(recap) -> void:
	var summary := recap.root_control().find_child("Summary", true, false) as Label
	var card := recap.root_control().find_child("DossierCard", true, false) as Control
	ok(summary != null and card != null, "总结页有摘要和档案卡")
	if summary == null or card == null:
		return
	ok(summary.is_visible_in_tree(), "摘要在树上可见")
	ok(summary.size.y > 0.0, "摘要高度 %s" % summary.size.y)
	ok(summary.text != "", "摘要文字非空")
	ok(summary.get_line_count() >= 1, "摘要排出了文字行")
	var box := summary.get_global_rect()
	var view := card.get_global_rect()
	ok(box.position.y >= view.position.y - 1.0 and box.end.y <= view.end.y + 1.0,
			"摘要整段在档案卡内 box %s card %s" % [box, view])


func _assert_recap_rows_whole(recap) -> void:
	var scroll := recap.root_control().find_child("Scroll", true, false) as ScrollContainer
	ok(scroll != null, "总结页有滚动区")
	if scroll == null:
		return
	var view := scroll.get_global_rect()
	var hint := recap.root_control().find_child("MoreHint", true, false) as Label
	for child in recap.menu().get_children():
		var row := child as Control
		if row == null or not row.is_visible_in_tree() or row.size.y < 1.0:
			continue
		var box := row.get_global_rect()
		if box.intersection(view).size.y <= 1.0:
			continue
		var tag := row.name
		if row is Label:
			tag = (row as Label).text
		elif row is MenuItem:
			tag = (row as MenuItem)._text
		ok(box.position.y >= view.position.y - 1.0 and box.end.y <= view.end.y + 1.0,
				"可见行没被裁 %s box %s view %s" % [tag, box, view])
		if hint != null and hint.visible and hint.size.y > 1.0:
			ok(box.intersection(hint.get_global_rect()).size.y <= 1.0,
					"可见行不跟底部提示重叠 %s" % tag)


func test_recap_escape_closes_the_page() -> void:
	var recap = await _make_recap()
	recap.open(_recap_info("give", []))
	var closed := [0]
	recap.closed.connect(func() -> void: closed[0] += 1)
	_press(recap, &"ui_cancel")
	await get_tree().process_frame
	eq(closed[0], 1, "Esc 关页并发 closed")
	ok(not recap.visible)
	recap.queue_free()
	await get_tree().process_frame
