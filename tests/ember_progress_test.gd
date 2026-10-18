extends TestCase
## 余烬阶位：纯函数边界 + EmberProgress 落档/升阶/解锁/封顶。

const Rank := preload("res://scripts/data/ember_rank.gd")
const Progress := preload("res://scripts/autoload/ember_progress.gd")
const PATH := "user://test_ember_progress.cfg"


func setup() -> void:
	SaveData.save_path = PATH
	SaveData.delete_save()
	SaveData.ember_rank = 1
	SaveData.ember_xp = 0
	SaveData.attribute_points = 0
	SaveData.skill_1 = ""
	SaveData.skill_2 = ""
	SaveData.skin_id = ""
	SaveData.skin_rune = ""
	SaveData.extras.clear()
	Progress.clear_cache()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.ember_rank = 1
	SaveData.ember_xp = 0
	SaveData.attribute_points = 0
	Progress.clear_cache()


func test_rank_thresholds_are_monotonic_and_clamped() -> void:
	eq(Rank.rank_for_xp(0), 1)
	eq(Rank.rank_for_xp(119), 1)
	eq(Rank.rank_for_xp(120), 2, "第二阶门槛 120")
	eq(Rank.rank_for_xp(299), 2)
	eq(Rank.rank_for_xp(300), 3)
	eq(Rank.rank_for_xp(4760), 10, "第十阶门槛 4760")
	eq(Rank.rank_for_xp(999999), 10, "XP 溢出也停在 10 阶")
	eq(Rank.xp_for_rank(1), 0)
	eq(Rank.xp_for_rank(4), 560)
	eq(Rank.xp_for_rank(99), Rank.xp_for_rank(10), "越界阶位被夹到满阶")
	eq(Rank.rank_span(10), 0, "满阶没有下一段")


func test_progress_and_remaining_xp() -> void:
	eq(Rank.xp_into_rank(150), 30, "第二阶内已积累 30")
	eq(Rank.xp_to_next(150), 150, "离第三阶还差 150")
	almost(Rank.progress(150), 30.0 / 180.0, 0.0001)
	eq(Rank.progress(4760), 1.0, "满阶进度 1")
	eq(Rank.xp_to_next(4760), 0)
	eq(Rank.points_for_rank(1), 0)
	eq(Rank.points_for_rank(4), 3)
	eq(Rank.name_for_rank(1), "拾灰者")
	eq(Rank.name_for_rank(10), "余烬之王")
	ok(Rank.summary(172).contains("2 阶"), "摘要包含阶位")


func test_rewards_table_is_ordered_and_within_range() -> void:
	var seen := {}
	for rank in range(1, Rank.MAX_RANK + 1):
		for id in Rank.rewards_for_rank(rank):
			ok(not seen.has(id), "%s 只解锁一次" % id)
			seen[id] = rank
	ok(seen.size() >= 6, "至少 6 个阶位解锁点")
	eq(Rank.rewards_for_rank(1).size(), 0, "1 阶不额外解锁")
	ok(not Rank.is_max_rank(9))
	ok(Rank.is_max_rank(10))


func test_award_xp_levels_up_and_grants_a_point_and_unlocks() -> void:
	var result := Progress.award_xp(150, &"test")
	eq(int(result["rank_before"]), 1)
	eq(int(result["rank_after"]), 2)
	eq(int(result["xp_after"]), 150)
	ok(bool(result["leveled"]))
	eq(SaveData.ember_rank, 2)
	eq(SaveData.ember_xp, 150)
	eq(SaveData.attribute_points, 1, "升一阶给 1 点属性点")
	var unlocked: Array = SaveData.get_extra(Progress.UNLOCKS_KEY, [])
	ok(unlocked.has("skin_ash_runner"), "2 阶解锁首个 id")
	eq(Progress.last_award(), result)


func test_multiple_rank_jump_awards_every_point_and_unlock() -> void:
	var result := Progress.award_xp(600, &"test")
	eq(int(result["rank_after"]), 4, "600 XP 直接到 4 阶")
	eq(SaveData.attribute_points, 3, "跨 3 阶给 3 点")
	var unlocked: Array = SaveData.get_extra(Progress.UNLOCKS_KEY, [])
	ok(unlocked.has("skin_ash_runner"))
	ok(unlocked.has("skill_ember_burst"))
	ok(unlocked.has("rune_ember_grip"))


func test_max_rank_stops_leveling_but_keeps_xp() -> void:
	Progress.award_xp(6000, &"test")
	eq(SaveData.ember_rank, 10)
	eq(SaveData.attribute_points, 9)
	var before_points := SaveData.attribute_points
	var result := Progress.award_xp(1000, &"test")
	eq(int(result["rank_after"]), 10)
	ok(not bool(result["leveled"]))
	eq(SaveData.attribute_points, before_points, "满阶不再给点")
	eq(SaveData.ember_xp, 7000)


func test_boss_defeated_signal_awards_boss_xp() -> void:
	GameEvents.boss_defeated.emit()
	eq(SaveData.ember_xp, Rank.BOSS_XP, "Boss 击杀自动给 XP")
	eq(String(Progress.last_award().get("source", "")), "boss")
	Progress.clear_cache()
	Progress.award_boss()
	eq(SaveData.ember_xp, Rank.BOSS_XP * 2)


func test_zero_award_is_ignored() -> void:
	var before := SaveData.ember_xp
	eq(Progress.award_xp(0), {})
	eq(Progress.award_xp(-5), {})
	eq(SaveData.ember_xp, before)
