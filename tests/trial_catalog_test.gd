extends TestCase
## 回火试炼数据源：赛道 / 解锁门 / 已通关章节与 Boss 目标 / 固定装载 / 评级。

const Catalog := preload("res://scripts/data/trial_catalog.gd")
const SAVE_TEST_PATH := "user://trial_catalog_test_save.cfg"

var _orig_flags: PackedStringArray
var _orig_ending := ""
var _orig_save_path := ""


func setup() -> void:
	_orig_flags = SaveData.flags.duplicate()
	_orig_ending = SaveData.ending
	_orig_save_path = SaveData.save_path
	SaveData.save_path = SAVE_TEST_PATH
	_delete_save()
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""


func teardown() -> void:
	SaveData.flags = _orig_flags
	SaveData.ending = _orig_ending
	SaveData.save_path = _orig_save_path
	_delete_save()


func _delete_save() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = SAVE_TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _flags(ids: Array) -> void:
	for id in ids:
		SaveData.mark_flag(String(id))


# --- 赛道 ---------------------------------------------------------------------

func test_three_tracks_with_stable_ids_and_names() -> void:
	eq(Catalog.TRACKS.size(), 3, "三条赛道")
	var ids := {}
	for track in Catalog.TRACKS:
		ok(Catalog.is_valid_track(track), "赛道 %d 合法" % track)
		var id := Catalog.track_id(track)
		ok(not ids.has(id), "赛道 id 唯一：%s" % id)
		ids[id] = true
		ok(Catalog.track_name(track) != "", "赛道 %d 有名字" % track)
		ok(Catalog.track_tagline(track) != "", "赛道 %d 有副题" % track)
		ok(Catalog.track_rules(track).size() >= 2, "赛道 %d 有规则说明" % track)
	eq(Catalog.track_id(Catalog.Track.BOSS_RUSH), &"boss_rush")
	eq(Catalog.track_id(Catalog.Track.TIME_ATTACK), &"time_attack")
	eq(Catalog.track_id(Catalog.Track.BARE_STEEL), &"bare_steel")
	eq(Catalog.is_valid_track(99), false, "未知赛道被拒绝")


# --- 解锁门 -------------------------------------------------------------------

func test_unlock_gate_needs_level07_or_an_ending() -> void:
	eq(Catalog.unlocked(), false, "新档不开放试炼")
	ok("玖章" in Catalog.unlock_requirement(), "提示用钟楼的章号（玖），不写旧的第七章")
	SaveData.mark_flag("level07_done")
	eq(Catalog.unlocked(), true, "通关第七章解锁")
	SaveData.flags = PackedStringArray()
	SaveData.ending = "give"
	eq(Catalog.unlocked(), true, "任一结局解锁")
	SaveData.ending = ""
	SaveData.flags = PackedStringArray()
	SaveData.mark_flag("trial_unlocked")
	eq(Catalog.unlocked(), true, "战役写入的 trial_unlocked 也解锁")
	SaveData.flags = PackedStringArray()
	SaveData.mark_flag("level06_done")
	eq(Catalog.unlocked(), false, "只打通第六章还不够")


# --- 章节 / Boss 目标 ---------------------------------------------------------

func test_cleared_chapters_follow_campaign_order() -> void:
	eq(Catalog.cleared_chapters().size(), 0, "没通关任何章节时列表为空")
	eq(Catalog.targets_for(Catalog.Track.TIME_ATTACK).size(), 0,
			"限时赛道没有可选章节")
	_flags(["boss_dead", "level03_done", "level07_done"])
	var cleared := Catalog.cleared_chapters()
	var ids := PackedStringArray()
	for entry in cleared:
		ids.append(String(entry["id"]))
	eq(ids, PackedStringArray(["level01", "level03", "level07"]),
			"按 GameContext.LEVEL_ORDER 排序（而不是旗标写入顺序）")
	var targets := Catalog.targets_for(Catalog.Track.TIME_ATTACK)
	eq(targets.size(), 3, "限时赛道按已通关章节列目标")
	eq(String(targets[0]["id"]), "level01")
	ok(String(targets[0]["title"]) != "", "目标带章节标题")


func test_chapter_clear_flags_reuse_story_flow() -> void:
	eq(Catalog.chapter_flag("level01"), "boss_dead")
	eq(Catalog.chapter_flag("level02"), "undercroft_done")
	eq(Catalog.chapter_flag("level07"), "level07_done")
	eq(Catalog.chapter_flag("level10"), "game_complete")
	for level_id in GameContext.LEVEL_ORDER:
		eq(Catalog.chapter_flag(level_id), StoryFlow.done_flag(level_id),
				"%s 的完成旗标与 StoryFlow.DONE_FLAGS 同源" % level_id)


func test_boss_rush_lists_only_delivered_and_cleared_bosses() -> void:
	eq(Catalog.available_bosses().size(), 0, "没有通关 Boss 时连战为空")
	eq(Catalog.targets_for(Catalog.Track.BOSS_RUSH).size(), 0,
			"没有可打 Boss 时没有目标")
	_flags(["boss_dead", "nightmare_dead"])
	var bosses := Catalog.available_bosses()
	eq(bosses.size(), 2, "已通关的两位 Boss 可连战；未交付场景的占位 Boss 自动跳过")
	var kinds := PackedStringArray()
	for row in bosses:
		kinds.append(String(row["kind"]))
		ok(String(row["scene"]).begins_with("res://scenes/enemies/"), "Boss 场景路径合法")
		ok(ResourceLoader.exists(String(row["scene"])), "Boss 场景已交付：%s" % row["scene"])
	eq(kinds, PackedStringArray(["executioner", "nightmare_boss"]), "顺序与 BOSS_TABLE 一致")
	var targets := Catalog.targets_for(Catalog.Track.BOSS_RUSH)
	eq(targets.size(), 1, "连战只有一格「全部 Boss」")
	eq(String(targets[0]["id"]), Catalog.ALL_BOSSES_ID)
	ok("2 场" in String(targets[0]["subtitle"]), "副题报场次")
	var stages := Catalog.stages_for(Catalog.Track.BOSS_RUSH,
			Catalog.ALL_BOSSES_ID)
	eq(stages.size(), 2, "两场连战")
	eq(String(stages[0]["level_id"]), "level01")
	eq(String(stages[0]["scene"]), GameContext.LEVELS["level01"])
	eq(String(stages[1]["level_id"]), "level10")
	eq((stages[0]["spawn"] as Vector2), Vector2(Level01EastWing.ARENA_CENTER_X - 204.0, Level01EastWing.STAGE_Y - 20.0), "Boss 竞技场落点来自当前布局")


func test_chapter_track_has_a_single_stage_at_the_level_start() -> void:
	_flags(["level03_done"])
	var stages := Catalog.stages_for(Catalog.Track.BARE_STEEL, "level03")
	eq(stages.size(), 1, "限时 / 禁核：一章一场")
	eq(String(stages[0]["level_id"]), "level03")
	eq(String(stages[0]["scene"]), GameContext.LEVELS["level03"])
	eq((stages[0]["spawn"] as Vector2), Vector2.INF, "章节赛从关卡默认出生点开始")
	eq(Catalog.stages_for(Catalog.Track.BARE_STEEL, "level09b").size(), 0,
			"未通关章节不能开赛")


# --- 固定装载 / 评级 ------------------------------------------------------------

func test_fixed_loadouts_per_track() -> void:
	var bare := Catalog.loadout_for(Catalog.Track.BARE_STEEL)
	eq((bare["sockets"] as Array).size(), 0, "禁核锈行不镶锈核")
	eq((bare["pouch"] as Array).size(), 0, "禁核锈行不带备用核")
	eq(int(bare["hp"]), Catalog.BASE_MAX_HP, "禁核锈行满生命开跑")
	var timed := Catalog.loadout_for(Catalog.Track.TIME_ATTACK)
	eq((timed["sockets"] as Array).size(), 2, "限时疾行固定镶满两个插座")
	eq(String((timed["sockets"] as Array)[0]), "kiln_core", "限时带热锻核")
	eq(String((timed["sockets"] as Array)[1]), "tether_core", "限时带钩锁核")
	eq((timed["pouch"] as Array).size(), 1, "限时口袋里放第三枚核")
	eq(String((timed["pouch"] as Array)[0]), "ember_core")
	var rush := Catalog.loadout_for(Catalog.Track.BOSS_RUSH)
	eq(int(rush["hp"]), 5, "Boss 连战满生命开跑")
	ok("无锈核" in Catalog.loadout_summary(Catalog.Track.BARE_STEEL),
			"摘要写明禁核")
	ok("生命 5" in Catalog.loadout_summary(Catalog.Track.TIME_ATTACK),
			"摘要写明生命")
	ok("每场回复 1 HP" in Catalog.loadout_summary(Catalog.Track.BOSS_RUSH),
			"摘要写明连战回复规则")


func test_rank_thresholds_and_death_penalty() -> void:
	var track := Catalog.Track.TIME_ATTACK
	var par := Catalog.par_ms(track, 1)
	eq(par, Catalog.PAR_CHAPTER_MS)
	eq(Catalog.rank_for(track, par, 0, 1), &"S", "基准时间内 S")
	eq(Catalog.rank_for(track, int(par * 1.2), 0, 1), &"A", "1.2 倍内 A")
	eq(Catalog.rank_for(track, int(par * 3.0), 0, 1), &"B", "更慢也是 B")
	# 死亡按赛道折算罚时：限时 20s / 禁核 30s / 连战 45s。
	var penalty := Catalog.death_penalty_ms(track)
	eq(penalty, 20000)
	eq(Catalog.score_ms(track, par - penalty, 1), par, "一次死亡 = 罚时 20s")
	eq(Catalog.rank_for(track, par - penalty, 1, 1), &"S",
			"罚时后仍在基准内 → S")
	eq(Catalog.rank_for(track, par, 1, 1), &"A", "基准时间 + 一次死亡 → A")
	eq(Catalog.death_penalty_ms(Catalog.Track.BARE_STEEL), 30000)
	# Boss 连战基准按场次翻倍。
	eq(Catalog.par_ms(Catalog.Track.BOSS_RUSH, 2),
			Catalog.PAR_BOSS_MS * 2)
	eq(Catalog.rank_for(Catalog.Track.BOSS_RUSH,
			Catalog.PAR_BOSS_MS * 2, 0, 2), &"S")
	eq(Catalog.death_penalty_ms(Catalog.Track.BOSS_RUSH), 45000)
	ok(Catalog.RANKS.has(&"S") and Catalog.RANKS.has(&"A") \
			and Catalog.RANKS.has(&"B"), "只有 S/A/B 三档")
