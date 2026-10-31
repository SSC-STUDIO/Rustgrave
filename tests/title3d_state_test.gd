extends TestCase
## 3D title state (`TitleState`): the scene-free assertions of the retired 2D
## `tests/title_world_test.gd` (save -> variant mapping, lantern count, every ending,
## true_break, skin fallback, disk peek) plus the new 3D contracts:
## grade(state) ranges/monotonic warming and light_plan(state) budgets/roles.
##
## Everything here is headless and render-free: no node is built, no window opens,
## no renderer is touched.

const SAVE_PATH := "user://title3d_state_test.cfg"
const SAVE_BAK := SAVE_PATH + ".bak"

## The legacy 2D GRADES keys carried over for consumers of the old look.
const LEGACY_KEYS: Array[String] = ["ambient", "furnace", "furnace_color", "forge", "shaft",
		"shaft_color", "embers", "ash", "steam", "gears", "lantern", "flicker"]
## The 3D grade keys every variant must provide.
const GRADE_KEYS: Array[String] = ["variant", "grade_id", "exposure", "white", "sun_color",
		"sun_energy", "furnace_color", "furnace_energy", "pit_energy", "fog_density",
		"fog_albedo", "fog_emission", "glow_intensity", "grade_tint", "lantern_lit",
		"lantern_flicker", "brazier_flicker", "gear_speed", "ember_rate", "steam_rate",
		"souls_rate", "souls_goal", "souls_escape", "ghost_count", "brazier_left",
		"brazier_right", "chain_mode", "knight_pose", "planted_sword"]
## The prop_plan keys (stable: the 3D prop nodes consume them directly).
const PROP_KEYS: Array[String] = ["chain_mode", "ghosts", "souls_rate", "souls_escape",
		"braziers", "knight_turns"]
## The light_plan keys (pure fixture data; placement belongs to the lighting rig).
const LIGHT_KEYS: Array[String] = ["id", "kind", "shadow", "energy", "color", "flicker",
		"range", "fixture"]
const GRADE_IDS: Array = [&"cold", &"act1", &"act2", &"act3", &"act4", &"give", &"keep",
		&"snuff", &"true_break"]

var _saved := {}


func setup() -> void:
	TitleState.forced_state = {}
	_saved = {
		"save_path": SaveData.save_path,
		"data": SaveData.data.duplicate(true),
		"flags": SaveData.flags.duplicate(),
		"ending": SaveData.ending,
		"skin_id": SaveData.skin_id,
		"ember_rank": SaveData.ember_rank,
		"attribute_points": SaveData.attribute_points,
	}


func teardown() -> void:
	TitleState.forced_state = {}
	SaveData.save_path = String(_saved.get("save_path", "user://rustgrave_save.cfg"))
	SaveData.data = (_saved.get("data", {}) as Dictionary).duplicate(true)
	SaveData.flags = _saved.get("flags", PackedStringArray())
	SaveData.ending = String(_saved.get("ending", ""))
	SaveData.skin_id = String(_saved.get("skin_id", ""))
	SaveData.ember_rank = int(_saved.get("ember_rank", 1))
	SaveData.attribute_points = int(_saved.get("attribute_points", 0))
	_remove(SAVE_PATH)
	_remove(SAVE_BAK)
	_remove(SAVE_PATH + ".tmp")


# ------------------------------------------------------------------ fixtures --

## A `peek` the way TitleState.peek_save() reports it.
func _peek(level_id: String = "", flags: Array = [], ending: String = "", has_save: bool = true,
		skin: String = "", origin: String = "") -> Dictionary:
	return _peek_scene(String(GameContext.LEVELS[level_id]) if level_id != "" else "", flags,
			ending, has_save, skin, origin)


func _peek_scene(scene: String, flags: Array = [], ending: String = "", has_save: bool = true,
		skin: String = "", origin: String = "") -> Dictionary:
	return {
		"has_save": has_save,
		"scene": scene,
		"flags": PackedStringArray(flags),
		"ending": ending,
		"skin": skin,
		"origin": origin,
		"rank": 3,
		"points": 1,
	}


func _done_flags(count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(String(StoryFlow.DONE_FLAGS[GameContext.LEVEL_ORDER[i]]))
	return out


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Clears the in-memory save and points SaveData at the test save path.
func _reset_save_data() -> void:
	SaveData.data = {}
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""
	SaveData.skin_id = ""
	SaveData.ember_rank = 1
	SaveData.attribute_points = 0
	SaveData.save_path = SAVE_PATH
	_remove(SAVE_PATH)
	_remove(SAVE_BAK)
	_remove(SAVE_PATH + ".tmp")


func _write_cfg(path: String, scene: String, flags: Array, ending: String = "",
		skin: String = "", rank: int = 1, points: int = 0, origin: String = "") -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("meta", "scene", scene)
	cfg.set_value("meta", "ending", ending)
	cfg.set_value("player", "origin", origin)
	cfg.set_value("story", "flags", flags)
	cfg.set_value("profile", "ember_rank", rank)
	cfg.set_value("profile", "attribute_points", points)
	cfg.set_value("profile", "skin_id", skin)
	return cfg.save(path)


func _write_corrupt(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	ok(file != null, "能写损坏存档 %s" % path)
	if file != null:
		file.store_string("this is not a godot ConfigFile\n")
		file.close()


func _cold() -> Dictionary:
	return TitleState.build_state(_peek("", [], "", false))


func _journey(level_id: String, cleared: int) -> Dictionary:
	return TitleState.build_state(_peek(level_id, _done_flags(cleared)))


func _ending(ending: String, level_id: String = "stage07") -> Dictionary:
	return TitleState.build_state(_peek(level_id, _done_flags(14), ending))


## One state per act: enough cleared chapters to reach it and a chapter index in it.
func _act_state(act: int) -> Dictionary:
	var cases := {1: ["stage02", 2], 2: ["stage03", 4], 3: ["stage05", 8], 4: ["stage08_true", 13]}
	var entry: Array = cases[act]
	return _journey(String(entry[0]), int(entry[1]))


func _all_states() -> Array:
	var out: Array = []
	out.append(["cold", _cold()])
	for act in [1, 2, 3, 4]:
		out.append(["act%d" % act, _act_state(act)])
	for ending in ["give", "keep", "snuff", "true_break"]:
		out.append([ending, _ending(ending)])
	return out


# --------------------------------------------------------------- the mapping --

func test_acts_split_the_fourteen_chapters_as_1_3_4_7_8_11_12_14() -> void:
	var expected := [1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4]
	eq(GameContext.LEVEL_ORDER.size(), 14, "战役 14 章")
	eq(TitleState.CHAPTERS, 14, "CHAPTERS = 14")
	eq(TitleState.ACT_STARTS, [0, 3, 7, 11], "四幕起点")
	for i in 14:
		eq(TitleState.act_of_index(i), int(expected[i]), "第 %d 章在第 %d 幕" % [i + 1, int(expected[i])])


func test_constants_keep_the_2d_names_and_the_3d_budgets() -> void:
	eq(TitleState.LANTERN_COUNT, 14, "十四盏吊灯")
	eq(TitleState.LIGHT_POOL_FIXTURES, [1, 4, 7, 10, 13], "旧光池挂点保持")
	eq(TitleState.LANTERN_LIGHT_FIXTURES.size(), 6, "3D 六盏吊灯灯")
	for fixture in TitleState.LIGHT_POOL_FIXTURES:
		ok(TitleState.LANTERN_LIGHT_FIXTURES.has(int(fixture)),
				"旧光池挂点 %d 仍在 3D 吊灯里" % int(fixture))
	eq(TitleState.LIGHT_FIXTURES, 12, "12 盏 fixture（1 dir + 1 spot + 1 炉口 + 1 桥下 + 6 吊灯 + 2 火盆）")
	ok(TitleState.LIGHT_FIXTURES <= TitleState.MAX_LIGHTS, "灯数在预算内")
	eq(TitleState.MAX_LIGHTS, 14, "Forward+ 的灯预算")
	ok(TitleState.MAX_SHADOWS <= 6, "投影预算 <= 6")
	eq(TitleState.SOUL_POOL_SIZE, 16, "魂光池 16")
	eq(TitleState.BRAZIER_FIRST_AT, 1, "第一章点亮第一座火盆")
	eq(TitleState.BRAZIER_SECOND_AT, 7, "第七章点亮第二座火盆")
	eq(TitleState.VARIANTS.size(), 6, "六个变体")
	ok(TitleState.VARIANTS.has(TitleState.VARIANT_TRUE_BREAK), "VARIANTS 收录 true_break")
	for gid in GRADE_IDS:
		ok(TitleState.GRADES.has(gid), "GRADES 有 %s" % gid)
		ok(TitleState.GRADES_3D.has(gid), "GRADES_3D 有 %s" % gid)
	eq(TitleState.MODE_RUN, 0, "链条模式与旧脚本同值")
	eq(TitleState.MODE_EMPTY, 1)
	eq(TitleState.MODE_STILL, 2)
	eq(TitleState.rest_facing_for(TitleState.VARIANT_KEEP), 1, "守火骑士朝着炉火")
	eq(TitleState.rest_facing_for(TitleState.VARIANT_COLD), -1, "其余骑士背朝炉火")


func test_lit_lanterns_follow_cleared_chapters() -> void:
	var table := {0: 0, 1: 1, 2: 2, 3: 3, 5: 5, 6: 6, 8: 8, 9: 9, 11: 11, 12: 12, 14: 14}
	for cleared in table:
		eq(TitleState.lit_lantern_count(int(cleared)), int(table[cleared]),
				"通关 %d 章点亮几盏" % int(cleared))
	var previous := 0
	for cleared in 15:
		var n := TitleState.lit_lantern_count(cleared)
		ok(n >= previous and n <= TitleState.LANTERN_COUNT,
				"通关 %d 章：%d 盏，不倒退不超额" % [cleared, n])
		previous = n
	eq(TitleState.lit_lantern_count(-3), 0, "负数夹到 0")
	eq(TitleState.lit_lantern_count(99), TitleState.LANTERN_COUNT, "超出夹到 14")
	# state 与 grade 都按 N/14 精确映射（不是近似比例）
	for cleared in 15:
		var s := _journey("stage01", cleared)
		eq(s["cleared"], cleared, "通关 %d 章：state.cleared" % cleared)
		eq(s["lit"], cleared, "通关 %d 章：state.lit" % cleared)
		eq(int(TitleState.grade(s)["lantern_lit"]), cleared, "通关 %d 章：grade.lantern_lit" % cleared)


func test_state_for_no_save_is_a_cold_forge() -> void:
	var s := TitleState.build_state(_peek("", [], "", false))
	eq(s["variant"], TitleState.VARIANT_COLD, "无存档 = 冷炉")
	eq(s["lit"], 0, "冷炉一盏灯都不亮")
	eq(s["cleared"], 0)
	eq(s["act"], 0, "冷炉没有幕次")
	eq(s["chapter_index"], -1)
	eq(s["has_save"], false)
	eq(TitleState.grade_id(s), &"cold")
	var g := TitleState.grade(s)
	eq(g["grade_id"], &"cold", "冷炉调色")
	eq(g["knight_pose"], TitleState.POSE_STAND, "冷炉：骑士站在桥心")
	eq(g["planted_sword"], false)
	eq(int(g["lantern_lit"]), 0)


func test_state_for_a_journey_grades_by_act_and_counts_lanterns() -> void:
	# 刚开局（存档在第一章、什么都没通）
	var fresh := TitleState.build_state(_peek("stage01"))
	eq(fresh["variant"], TitleState.VARIANT_JOURNEY)
	eq(fresh["act"], 1)
	eq(fresh["lit"], 0, "没通关任何一章，灯还没亮")
	eq(TitleState.grade_id(fresh), &"act1")
	# 每一幕取一个章：存档章节决定幕，通关旗标决定灯
	var cases := [["stage02", 2, 2, &"act1"], ["branch02", 3, 3, &"act2"], ["stage04", 6, 6, &"act2"],
			["stage05", 8, 8, &"act3"], ["stage06", 10, 10, &"act3"], ["branch05", 11, 11, &"act4"],
			["stage08_true", 13, 13, &"act4"]]
	for c in cases:
		var s := TitleState.build_state(_peek(String(c[0]), _done_flags(int(c[1]))))
		eq(s["cleared"], int(c[1]), "%s: 通关章数" % String(c[0]))
		eq(s["lit"], int(c[2]), "%s: 亮灯数" % String(c[0]))
		eq(TitleState.grade_id(s), c[3], "%s: 调色" % String(c[0]))
	# 通关旗标缺失时，存档章节之前的章也算通关（读档回到第五节点，前四节点必然过了）
	var inferred := TitleState.build_state(_peek("stage03"))
	eq(inferred["cleared"], 4, "第五节点之前的四节点视为通关")
	var done: Array = inferred["done"]
	eq(done.size(), 14, "每章一个通关标记")
	ok(done[3] and not done[4], "第四个亮、第五个（当前章）不亮")
	# 未知场景：幕次回退到通关数
	var unknown := TitleState.build_state(_peek_scene("res://scenes/levels/NotAChapter.tscn",
			_done_flags(8)))
	eq(unknown["chapter_id"], "", "未知场景没有章节 id")
	eq(unknown["cleared"], 8)
	eq(TitleState.grade_id(unknown), &"act3", "未知场景：按通关数落到第三幕")
	# 旧版章节 id 仍经 LEGACY_TO_STAGE 映射到现行节点
	var legacy := TitleState.build_state(_peek_scene(
			String(GameContext.LEGACY_LEVELS["level07b"]), _done_flags(2)))
	eq(legacy["chapter_id"], "stage05", "level07b -> stage05")
	eq(legacy["chapter_index"], 8, "level07b 在第十四节点序里的下标")


func test_state_for_each_ending() -> void:
	for ending in ["give", "keep", "snuff", "true_break"]:
		var s := TitleState.build_state(_peek("stage08_true", _done_flags(14), ending))
		eq(s["variant"], StringName(ending), "%s 变体" % ending)
		eq(s["act"], 4, "结局都在第四幕的终点")
		eq(s["cleared"], 14, "全部通关")
		eq(TitleState.grade_id(s), StringName(ending), "%s 有自己的调色" % ending)
	eq(TitleState.build_state(_peek("stage07", [], "give"))["lit"], 14, "送剑：灯全亮")
	eq(TitleState.build_state(_peek("stage07", [], "keep"))["lit"], 14, "守火：灯全亮")
	eq(TitleState.build_state(_peek("stage07", [], "snuff"))["lit"], 0, "熄灭：灯全暗")
	eq(TitleState.build_state(_peek("stage08_true", [], "true_break"))["lit"], 14, "真结局：灯全亮")
	# 没见过的结局 id（旧测试里写过 "purified"）按已完成处理，不崩
	eq(TitleState.build_state(_peek("stage07", [], "purified"))["variant"], TitleState.VARIANT_GIVE)


## 真结局「破约」：变体 / 灯全亮 / 独立调色 / prop_plan 里的空链、升魂、零亡魂和半亮火盆。
func test_true_break_has_its_own_state_grade_and_prop_plan() -> void:
	var s := TitleState.build_state(_peek("stage08_true", _done_flags(14), "true_break"))
	eq(s["variant"], TitleState.VARIANT_TRUE_BREAK, "结局 id 直接成为变体")
	eq(s["ending"], "true_break", "状态里记着结局")
	eq(s["cleared"], 14, "真结局：全章通关")
	eq(s["lit"], 14, "真结局：十四盏灯全亮")
	eq(s["act"], 4, "真结局在第四幕的终点")
	ok(TitleState.VARIANTS.has(TitleState.VARIANT_TRUE_BREAK), "VARIANTS 收录 true_break")
	eq(TitleState.grade_id(s), TitleState.VARIANT_TRUE_BREAK, "grade_id 指向自己的调色")
	ok(TitleState.GRADES.has(TitleState.VARIANT_TRUE_BREAK), "GRADES 里有 true_break")
	var legacy: Dictionary = TitleState.GRADES[TitleState.VARIANT_TRUE_BREAK]
	for key in LEGACY_KEYS:
		ok(legacy.has(key), "true_break 旧调色有 %s" % String(key))
	eq(legacy["furnace_color"], Color(0.45, 0.82, 0.96), "真结局的炉火是冷蓝色")
	ok(float(legacy["forge"]) < float(TitleState.GRADES[&"keep"]["forge"]), "真结局比守炉冷")
	var g := TitleState.grade(s)
	eq(g["grade_id"], TitleState.VARIANT_TRUE_BREAK, "grade 指向真结局")
	eq(g["furnace_color"], Color(0.45, 0.82, 0.96), "3D 调色也是冷蓝炉火")
	ok(float(g["furnace_energy"]) < float(TitleState.grade(_ending("keep"))["furnace_energy"]),
			"真结局炉火比守炉冷")
	eq(int(g["lantern_lit"]), 14, "真结局十四盏灯全亮")
	var plan := TitleState.prop_plan(s)
	eq(plan["chain_mode"], TitleState.MODE_EMPTY, "真结局：送剑链停空")
	eq(plan["ghosts"], 0, "真结局：亡魂都被放走了")
	eq(plan["souls_escape"], true, "真结局：真名升出屋顶")
	almost(float(plan["souls_rate"]), 1.0, 0.0001, "真结局：魂光满额")
	eq(plan["braziers"], [0.6, 0.6], "真结局：火盆半亮")
	eq(plan["knight_turns"], false, "真结局：没有骑士转身")


func test_state_picks_the_saved_skin_or_the_origin_default() -> void:
	eq(TitleState.build_state(_peek("stage01", [], "", true, "skin_gothic_hero"))["skin"],
			&"skin_gothic_hero")
	eq(TitleState.build_state(_peek("stage01", [], "", true, "not_a_skin"))["skin"],
			SkinCatalog.DEFAULT_SKIN, "未知外观退回默认")
	eq(TitleState.build_state(_peek("stage01", [], "", true, "", "rust_automaton"))["skin"],
			&"skin_cemetery_hero", "没选外观时跟随起源的默认外观")
	eq(TitleState.build_state(_peek("", [], "", false))["skin"], SkinCatalog.DEFAULT_SKIN,
			"无存档默认骑士")


# ------------------------------------------------------------ save peeking ----

## 真的存档文件 -> state_from_save()（标题启动时还没 load_game，必须自己读盘）。
func test_state_from_save_peeks_the_file_on_disk() -> void:
	_reset_save_data()
	eq(TitleState.state_from_save()["variant"], TitleState.VARIANT_COLD, "没有存档文件 -> 冷炉")

	eq(_write_cfg(SAVE_PATH, String(GameContext.LEVELS["stage04"]), _done_flags(6),
			"", "skin_ash_runner", 5, 2, "scrap_scavenger"), OK, "写测试存档")
	var s := TitleState.state_from_save()
	eq(s["variant"], TitleState.VARIANT_JOURNEY, "读盘：旅程中")
	eq(s["chapter_id"], "stage04", "读盘：存档章节")
	eq(s["cleared"], 6, "读盘：旗标里的通关数")
	eq(s["skin"], &"skin_ash_runner", "读盘：外观")
	eq(s["rank"], 5, "读盘：阶位")
	eq(s["points"], 2, "读盘：属性点")

	eq(_write_cfg(SAVE_PATH, String(GameContext.LEVELS["stage04"]), _done_flags(6),
			"keep"), OK)
	eq(TitleState.state_from_save()["variant"], TitleState.VARIANT_KEEP, "读盘：守火结局")

	# 强制状态（工具 / 测试用）压过存档
	TitleState.forced_state = TitleState.build_state(_peek("", [], "", false))
	eq(TitleState.state_from_save()["variant"], TitleState.VARIANT_COLD, "forced_state 优先")


## 内存状态优先于磁盘；profile 字段只在内存里加载过游戏时才采信。
func test_peek_prefers_memory_and_merges_the_disk_flags() -> void:
	_reset_save_data()
	eq(_write_cfg(SAVE_PATH, String(GameContext.LEVELS["stage04"]), _done_flags(6),
			"give", "skin_ash_runner", 5, 2, "scrap_scavenger"), OK, "写测试存档")
	SaveData.data = {
		"meta": {"scene": String(GameContext.LEVELS["stage03"])},
		"player": {"origin": "rust_automaton"},
	}
	SaveData.flags = PackedStringArray(["custom_flag"])
	SaveData.ending = "keep"
	SaveData.skin_id = "skin_gothic_hero"
	SaveData.ember_rank = 9
	SaveData.attribute_points = 7
	var peek := TitleState.peek_save()
	eq(peek["has_save"], true)
	eq(peek["scene"], String(GameContext.LEVELS["stage03"]), "内存里的场景优先")
	eq(peek["origin"], "rust_automaton", "内存里的起源优先")
	eq(peek["ending"], "keep", "内存里的结局优先于磁盘")
	eq(peek["skin"], &"skin_gothic_hero", "内存里的外观")
	eq(peek["rank"], 9, "内存里的阶位")
	eq(peek["points"], 7, "内存里的属性点")
	ok(peek["flags"] is PackedStringArray, "flags 是 PackedStringArray")
	ok(peek["flags"].has("custom_flag"), "内存旗标在")
	ok(peek["flags"].has(String(StoryFlow.DONE_FLAGS[GameContext.LEVEL_ORDER[0]])),
			"磁盘旗标合并进来")
	var s := TitleState.state_from_save()
	eq(s["variant"], TitleState.VARIANT_KEEP, "内存结局 -> 守火")
	eq(s["chapter_id"], "stage03", "状态用的是内存场景")


## .bak 回退：主档损坏/缺失时读备份；主档和备份都读不出来 -> 当作没有存档（冷炉），
## 并且 peek 是只读的，不会把备份「修复」写回主档。
func test_peek_falls_back_to_the_backup_and_a_damaged_save_is_cold() -> void:
	_reset_save_data()
	eq(_write_cfg(SAVE_PATH, String(GameContext.LEVELS["stage05"]), _done_flags(8),
			"give"), OK)
	eq(_write_cfg(SAVE_BAK, String(GameContext.LEVELS["stage05"]), _done_flags(8)), OK,
			"写备份（旅程：8 章旗标、无结局）")

	_remove(SAVE_PATH)
	var only_bak := TitleState.peek_save()
	eq(only_bak["has_save"], true, "只有 .bak 也算有存档")
	eq(only_bak["ending"], "", "旅程备份没有结局")
	eq(only_bak["scene"], String(GameContext.LEVELS["stage05"]), "场景从 .bak 读出")
	var only_bak_state := TitleState.state_from_save()
	eq(only_bak_state["variant"], TitleState.VARIANT_JOURNEY, "从 .bak 得到旅程变体")
	eq(only_bak_state["cleared"], 8, "通关数从 .bak 读出")

	_write_corrupt(SAVE_PATH)
	var corrupted := TitleState.peek_save()
	eq(corrupted["has_save"], true, "主档坏了但还有可用备份")
	eq(corrupted["scene"], String(GameContext.LEVELS["stage05"]), "主档坏了：场景从 .bak 读出")
	eq(TitleState.state_from_save()["cleared"], 8, "主档坏了：通关数从 .bak 读出")
	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	ok(raw.begins_with("this is not"), "peek 只读：没有修复/覆盖主档")

	# 备份里带结局：结局也从 .bak 读出
	eq(_write_cfg(SAVE_BAK, String(GameContext.LEVELS["stage05"]), _done_flags(8), "keep"), OK)
	var ending_bak := TitleState.peek_save()
	eq(ending_bak["ending"], "keep", "主档坏了：结局从 .bak 读出")
	eq(TitleState.state_from_save()["variant"], TitleState.VARIANT_KEEP, "从 .bak 得到守火变体")

	_write_corrupt(SAVE_BAK)
	var damaged := TitleState.peek_save()
	eq(damaged["has_save"], false, "主档和备份都读不出来 = 没有存档")
	eq(TitleState.state_from_save()["variant"], TitleState.VARIANT_COLD, "损坏存档 -> 冷炉")
	eq(TitleState.state_from_save()["lit"], 0, "损坏存档：没有灯亮")


# --------------------------------------------------------------- grade --------

func _assert_plan(state: Dictionary, chain: int, ghosts: int, souls_rate: float, escape: bool,
		braziers: Array, turns: bool, label: String) -> void:
	var plan := TitleState.prop_plan(state)
	for key in PROP_KEYS:
		ok(plan.has(key), "%s: prop_plan 有 %s" % [label, String(key)])
	eq(plan["chain_mode"], chain, "%s: 链模式" % label)
	eq(plan["ghosts"], ghosts, "%s: 亡魂数" % label)
	almost(float(plan["souls_rate"]), souls_rate, 0.0001, "%s: 魂光比例" % label)
	eq(plan["souls_escape"], escape, "%s: 魂光走向" % label)
	var levels: Array = plan["braziers"]
	eq(levels.size(), 2, "%s: 两座火盆" % label)
	almost(float(levels[0]), float(braziers[0]), 0.0001, "%s: 第一座火盆" % label)
	almost(float(levels[1]), float(braziers[1]), 0.0001, "%s: 第二座火盆" % label)
	eq(plan["knight_turns"], turns, "%s: 骑士转身" % label)


func test_prop_plan_covers_every_variant() -> void:
	# cold：链还在（极慢），一个亡魂，魂光 15%（2/16），火盆冷，骑士会转身
	_assert_plan(_cold(), TitleState.MODE_RUN, 1, 0.15, false, [0.0, 0.0], true, "cold")
	# journey：亡魂 clamp(幕,1,3)、魂光 20%+3.5%/章（≤70%）、火盆按通关章数与幕次
	_assert_plan(_act_state(1), TitleState.MODE_RUN, 1, 0.20 + 0.035 * 2.0, false,
			[0.6, 0.0], true, "act1")
	_assert_plan(_act_state(4), TitleState.MODE_RUN, 3, 0.20 + 0.035 * 13.0, false,
			[1.0, 1.0], true, "act4")
	# give：链停空（剑一把不剩），没有亡魂，魂光满额升出屋顶，火盆稳稳亮着，骑士不在
	_assert_plan(_ending("give"), TitleState.MODE_EMPTY, 0, 1.0, true, [0.9, 0.9], false, "give")
	# keep：链还在，三个亡魂，魂光 30%，火盆最亮，骑士一直朝着炉火
	_assert_plan(_ending("keep"), TitleState.MODE_RUN, 3, 0.30, false, [1.3, 1.3], false, "keep")
	# snuff：链停住、全暗、没有魂光与亡魂
	_assert_plan(_ending("snuff"), TitleState.MODE_STILL, 0, 0.0, false, [0.0, 0.0], false, "snuff")
	# true_break：与还火同构，火盆半亮
	_assert_plan(_ending("true_break"), TitleState.MODE_EMPTY, 0, 1.0, true, [0.6, 0.6], false,
			"true_break")
	# journey 的中间档：通关 7 章第二座火盆点亮，魂光封顶 70%
	var mid := TitleState.prop_plan(_journey("stage03", 7))
	eq(mid["ghosts"], 2, "第二幕两个亡魂")
	almost(float(mid["souls_rate"]), 0.20 + 0.035 * 7.0, 0.0001, "通关 7 章魂光")
	ok(float(mid["braziers"][0]) > 0.0 and float(mid["braziers"][1]) > 0.0, "通关 7 章两座火盆都亮")
	almost(float(mid["braziers"][0]), lerpf(0.6, 1.0, 1.0 / 3.0), 0.0001, "第二幕火盆亮度")
	var maxed := TitleState.prop_plan(_journey("stage08_true", 14))
	almost(float(maxed["souls_rate"]), 0.20 + 0.035 * 14.0, 0.0001, "满章魂光 69%")
	ok(float(maxed["souls_rate"]) <= 0.70, "不超 70%")


func test_grade_has_every_field_in_range_for_every_variant() -> void:
	for entry in _all_states():
		var label := String(entry[0])
		var s: Dictionary = entry[1]
		var g := TitleState.grade(s)
		for key in LEGACY_KEYS:
			ok(g.has(key), "%s: grade 保留旧键 %s" % [label, String(key)])
		for key in GRADE_KEYS:
			ok(g.has(key), "%s: grade 有 %s" % [label, String(key)])
		eq(g["variant"], s["variant"], "%s: variant 一致" % label)
		eq(g["grade_id"], TitleState.grade_id(s), "%s: grade_id 一致" % label)
		ok(float(g["exposure"]) >= 0.3 and float(g["exposure"]) <= 1.4,
				"%s: exposure 合理 (%.2f)" % [label, float(g["exposure"])])
		ok(float(g["white"]) >= 0.85 and float(g["white"]) <= 1.35, "%s: white 合理" % label)
		ok(float(g["sun_energy"]) >= 0.0 and float(g["sun_energy"]) <= 1.2,
				"%s: sun_energy 合理" % label)
		ok(float(g["furnace_energy"]) >= 0.0 and float(g["furnace_energy"]) <= 2.0,
				"%s: furnace_energy 合理" % label)
		ok(float(g["pit_energy"]) >= 0.0 and float(g["pit_energy"]) <= 1.8,
				"%s: pit_energy 合理" % label)
		ok(float(g["fog_density"]) > 0.0 and float(g["fog_density"]) <= 0.06,
				"%s: fog_density 合理" % label)
		ok(float(g["glow_intensity"]) >= 0.0 and float(g["glow_intensity"]) <= 1.2,
				"%s: glow_intensity 合理" % label)
		ok(g["sun_color"] is Color and g["furnace_color"] is Color, "%s: 光是 Color" % label)
		ok(g["fog_albedo"] is Color and g["fog_emission"] is Color, "%s: 雾是 Color" % label)
		ok(g["grade_tint"] is Color, "%s: 调色 tint 是 Color" % label)
		var lit := int(g["lantern_lit"])
		ok(lit >= 0 and lit <= TitleState.LANTERN_COUNT, "%s: 灯数 0..14" % label)
		eq(lit, int(s["lit"]), "%s: grade 灯数 = state.lit" % label)
		ok(float(g["gear_speed"]) >= 0.0 and float(g["gear_speed"]) <= 1.4,
				"%s: gear_speed 合理" % label)
		ok(float(g["ember_rate"]) >= 0.0 and float(g["ember_rate"]) <= 1.6,
				"%s: ember_rate 合理" % label)
		ok(float(g["steam_rate"]) >= 0.0 and float(g["steam_rate"]) <= 1.2,
				"%s: steam_rate 合理" % label)
		ok(float(g["souls_rate"]) >= 0.0 and float(g["souls_rate"]) <= 1.0,
				"%s: souls_rate 0..1" % label)
		var souls_goal := int(g["souls_goal"])
		ok(souls_goal >= 0 and souls_goal <= TitleState.SOUL_POOL_SIZE,
				"%s: souls_goal 0..16" % label)
		eq(souls_goal, clampi(int(round(float(g["souls_rate"]) * float(TitleState.SOUL_POOL_SIZE))),
				0, TitleState.SOUL_POOL_SIZE), "%s: souls_goal 与比例一致" % label)
		ok(int(g["ghost_count"]) >= 0 and int(g["ghost_count"]) <= 3, "%s: ghost_count 0..3" % label)
		ok(float(g["brazier_left"]) >= 0.0 and float(g["brazier_left"]) <= 1.4,
				"%s: 左火盆亮度合理" % label)
		ok(float(g["brazier_right"]) >= 0.0 and float(g["brazier_right"]) <= 1.4,
				"%s: 右火盆亮度合理" % label)
		ok(int(g["chain_mode"]) in [0, 1, 2], "%s: chain_mode 三态" % label)
		ok([TitleState.POSE_STAND, TitleState.POSE_PLANTED, TitleState.POSE_SEATED,
				TitleState.POSE_ABSENT].has(g["knight_pose"]), "%s: knight_pose 四态" % label)
		match StringName(s["variant"]):
			TitleState.VARIANT_GIVE:
				eq(g["knight_pose"], TitleState.POSE_PLANTED, "%s: 送剑 = 插剑" % label)
				eq(g["planted_sword"], true, "%s: 送剑插在桥上" % label)
				eq(int(g["lantern_lit"]), 14, "%s: 送剑灯全亮" % label)
			TitleState.VARIANT_KEEP:
				eq(g["knight_pose"], TitleState.POSE_SEATED, "%s: 守火 = 坐姿" % label)
				eq(g["planted_sword"], false, "%s: 守火不插剑" % label)
				eq(int(g["lantern_lit"]), 14)
			TitleState.VARIANT_SNUFF:
				eq(g["knight_pose"], TitleState.POSE_ABSENT, "%s: 熄灭 = 无人" % label)
				eq(g["planted_sword"], false)
				eq(int(g["lantern_lit"]), 0, "%s: 熄灭灯全暗" % label)
			_:
				eq(g["knight_pose"], TitleState.POSE_STAND, "%s: 站姿" % label)
				eq(g["planted_sword"], false)


## cold -> act1..4 严格渐暖；give 在暖档之间稳定；keep 最盛；snuff 全暗只剩残红；真结局冷蓝。
func test_grade_warms_from_cold_to_act4_and_the_endings() -> void:
	var cold := TitleState.grade(_cold())
	var acts: Array = []
	for act in [1, 2, 3, 4]:
		acts.append(TitleState.grade(_act_state(act)))
	for field in ["exposure", "sun_energy", "furnace_energy", "pit_energy"]:
		var previous := float(cold[field])
		for i in acts.size():
			var current := float(acts[i][field])
			ok(current > previous, "%s: 第 %d 幕比上一档暖（%.3f > %.3f）"
					% [field, i + 1, current, previous])
			previous = current
	# give：全暖、稳定（不闪），落在第三、四幕之间
	var give := TitleState.grade(_ending("give"))
	ok(float(give["furnace_energy"]) > float(acts[2]["furnace_energy"])
			and float(give["furnace_energy"]) < float(acts[3]["furnace_energy"]),
			"give 炉火在第三、四幕之间")
	ok(float(give["exposure"]) > float(acts[2]["exposure"])
			and float(give["exposure"]) < float(acts[3]["exposure"]), "give 曝光在第三、四幕之间")
	ok(float(give["lantern_flicker"]) < 0.3, "give 的灯焰稳定")
	eq(int(give["lantern_lit"]), 14, "give 灯全亮")
	# keep：最盛的炉火 / 熔河 / 辉光
	var keep := TitleState.grade(_ending("keep"))
	for field in ["furnace_energy", "pit_energy", "glow_intensity"]:
		ok(float(keep[field]) > float(give[field]), "keep 的 %s 比 give 更盛" % field)
	ok(float(keep["furnace_energy"]) > float(acts[3]["furnace_energy"]), "keep 比第四幕更盛")
	eq(int(keep["lantern_lit"]), 14)
	# snuff：全暗 + 残红
	var snuff := TitleState.grade(_ending("snuff"))
	ok(float(snuff["exposure"]) < float(cold["exposure"]), "熄灭比冷炉更暗")
	for field in ["sun_energy", "furnace_energy", "pit_energy", "glow_intensity"]:
		ok(float(snuff[field]) < float(cold[field]), "熄灭的 %s 低于冷炉" % field)
	var snuff_color: Color = snuff["furnace_color"]
	ok(snuff_color.r > snuff_color.g * 2.0, "熄灭只剩残红 %s" % str(snuff_color))
	ok(float(snuff["furnace_energy"]) > 0.0, "残红仍有一点能量")
	eq(int(snuff["lantern_lit"]), 0)
	# true_break：冷蓝晨光，比冷炉暖、比第一幕冷
	var tb := TitleState.grade(_ending("true_break"))
	var tb_color: Color = tb["furnace_color"]
	ok(tb_color.b > tb_color.r, "真结局炉火是冷蓝 %s" % str(tb_color))
	eq(tb_color, Color(0.45, 0.82, 0.96))
	ok(float(tb["furnace_energy"]) > float(cold["furnace_energy"])
			and float(tb["furnace_energy"]) < float(acts[0]["furnace_energy"]),
			"真结局比冷炉暖、比第一幕冷")
	eq(int(tb["lantern_lit"]), 14)


func test_unknown_variants_fall_back_safely() -> void:
	eq(TitleState.grade({"variant": &"nonsense"})["variant"], TitleState.VARIANT_GIVE,
			"未知变体 -> give 调色")
	eq(TitleState.grade({"variant": &"nonsense"})["grade_id"], TitleState.VARIANT_GIVE)
	eq(TitleState.prop_plan({"variant": &"nonsense"})["chain_mode"], TitleState.MODE_EMPTY,
			"未知变体 -> 还火的空链")
	eq(TitleState.grade({"variant": &"journey", "act": 99})["grade_id"], &"act4",
			"幕次越界夹到第四幕")
	eq(TitleState.grade({"variant": &"journey", "act": -3})["grade_id"], &"act1",
			"幕次过小夹到第一幕")
	var s := TitleState.build_state(_peek("stage07", [], "purified"))
	eq(s["variant"], TitleState.VARIANT_GIVE, "未知结局回退 give")
	eq(s["lit"], 14)
	eq(TitleState.grade(s)["knight_pose"], TitleState.POSE_PLANTED, "未知结局桥上是插剑")


# ------------------------------------------------------------ light plan ------

func _light_by_id(lights: Array, id: StringName) -> Dictionary:
	for light in lights:
		if light["id"] == id:
			return light
	return {}


func _lit_lantern_fixtures(lights: Array) -> Array:
	var out: Array = []
	for light in lights:
		if int(light["fixture"]) >= 0 and float(light["energy"]) > 0.0:
			out.append(int(light["fixture"]))
	return out


func _total_energy(lights: Array) -> float:
	var total := 0.0
	for light in lights:
		total += float(light["energy"])
	return total


func test_light_plan_covers_the_budget_and_every_fixture_role() -> void:
	for entry in _all_states():
		var label := String(entry[0])
		var lights := TitleState.light_plan(entry[1])
		eq(lights.size(), TitleState.LIGHT_FIXTURES, "%s: 12 盏 fixture" % label)
		ok(lights.size() <= TitleState.MAX_LIGHTS, "%s: 灯数不超预算" % label)
		var shadows := 0
		var directional := 0
		var spot := 0
		var lanterns: Array = []
		var ids := {}
		for light in lights:
			for key in LIGHT_KEYS:
				ok(light.has(key), "%s: 灯有 %s" % [label, String(key)])
			var id: StringName = light["id"]
			ok(not ids.has(id), "%s: id %s 唯一" % [label, String(id)])
			ids[id] = true
			var kind: StringName = light["kind"]
			ok(kind == &"directional" or kind == &"spot" or kind == &"omni",
					"%s: kind 合法（%s）" % [label, String(kind)])
			if kind == &"directional":
				directional += 1
			if kind == &"spot":
				spot += 1
			if bool(light["shadow"]):
				shadows += 1
			ok(light["color"] is Color, "%s: 灯色是 Color" % label)
			ok(float(light["energy"]) >= 0.0, "%s: 能量非负" % label)
			ok(float(light["flicker"]) >= 0.0, "%s: 闪烁非负" % label)
			if light["kind"] == &"directional":
				eq(float(light["range"]), 0.0, "%s: 平行光没有 range" % label)
			else:
				ok(float(light["range"]) > 0.0, "%s: 位置灯有 range" % label)
			if int(light["fixture"]) >= 0:
				lanterns.append(int(light["fixture"]))
		eq(directional, 1, "%s: 一盏天光" % label)
		eq(spot, 1, "%s: 一盏光柱" % label)
		ok(shadows <= TitleState.MAX_SHADOWS, "%s: 投影 %d <= 6" % [label, shadows])
		eq(shadows, 4, "%s: 投影 = 天光 + 炉口 + 两盏吊灯" % label)
		eq(lanterns.size(), 6, "%s: 六盏吊灯灯" % label)
		for i in TitleState.LANTERN_LIGHT_FIXTURES.size():
			eq(lanterns[i], TitleState.LANTERN_LIGHT_FIXTURES[i],
					"%s: 第 %d 盏吊灯挂在 fixture %d" % [label, i, int(lanterns[i])])
		for required in [&"sun", &"shaft", &"furnace", &"pit", &"brazier_left", &"brazier_right"]:
			ok(ids.has(required), "%s: 有 %s" % [label, String(required)])
		# 太阳 / 光柱 / 炉口 / 桥下 / 两座火盆 + 六盏吊灯都真的被描述到
		ok(float(_light_by_id(lights, &"sun")["energy"]) > 0.0, "%s: 天光有能量" % label)


func test_light_plan_follows_lantern_progress_and_braziers() -> void:
	for entry in _all_states():
		var lights := TitleState.light_plan(entry[1])
		for light in lights:
			ok(not light.has("position") and not light.has("pos"),
					"%s: light_plan 不写 3D 坐标" % String(entry[0]))
	# 冷炉 / 熄灭：一盏吊灯都不亮
	eq(_lit_lantern_fixtures(TitleState.light_plan(_cold())), [], "冷炉：吊灯全暗")
	eq(_lit_lantern_fixtures(TitleState.light_plan(_ending("snuff"))), [], "熄灭：吊灯全暗")
	eq(_lit_lantern_fixtures(TitleState.light_plan(_journey("stage01", 0))), [],
			"通关 0 章：吊灯全暗")
	# 旅程：fixture < 通关章数 的吊灯才亮（N/14 精确映射）
	eq(_lit_lantern_fixtures(TitleState.light_plan(_journey("stage01", 4))), [0, 1],
			"通关 4 章：fixture 0/1 亮")
	eq(_lit_lantern_fixtures(TitleState.light_plan(_journey("stage01", 7))), [0, 1, 4],
			"通关 7 章")
	eq(_lit_lantern_fixtures(TitleState.light_plan(_journey("stage01", 13))), [0, 1, 4, 7, 10],
			"通关 13 章")
	eq(_lit_lantern_fixtures(TitleState.light_plan(_journey("stage01", 14))),
			TitleState.LANTERN_LIGHT_FIXTURES.duplicate(), "通关 14 章：六盏全亮")
	# 结局：灯全亮（熄灭除外）
	for ending in ["give", "keep", "true_break"]:
		eq(_lit_lantern_fixtures(TitleState.light_plan(_ending(ending))),
				TitleState.LANTERN_LIGHT_FIXTURES.duplicate(), "%s：灯全亮" % ending)
	# 火盆灯跟着 prop_plan.braziers 走
	eq(float(_light_by_id(TitleState.light_plan(_cold()), &"brazier_left")["energy"]), 0.0,
			"冷炉：火盆灯灭")
	ok(float(_light_by_id(TitleState.light_plan(_ending("give")), &"brazier_left")["energy"]) > 0.0,
			"送剑：火盆亮")
	var keep_brazier := float(_light_by_id(TitleState.light_plan(_ending("keep")),
			&"brazier_left")["energy"])
	var give_brazier := float(_light_by_id(TitleState.light_plan(_ending("give")),
			&"brazier_left")["energy"])
	ok(keep_brazier > give_brazier, "守炉的火盆比送剑更亮")
	# 总光能：旅程逐幕递增，keep 最盛，snuff 最低
	var totals: Array = []
	for act in [1, 2, 3, 4]:
		totals.append(_total_energy(TitleState.light_plan(_act_state(act))))
	for i in 3:
		ok(float(totals[i + 1]) > float(totals[i]), "总光能：第 %d 幕 > 第 %d 幕" % [i + 2, i + 1])
	ok(_total_energy(TitleState.light_plan(_ending("keep")))
			> _total_energy(TitleState.light_plan(_ending("give"))), "keep 总光能最盛")
	ok(_total_energy(TitleState.light_plan(_ending("snuff")))
			< _total_energy(TitleState.light_plan(_cold())), "snuff 总光能最低")


# ---------------------------------------------------------------- purity ------

func test_plans_and_grade_are_pure_and_side_effect_free() -> void:
	var s := _act_state(3)
	var snapshot := s.duplicate(true)
	var g1 := TitleState.grade(s)
	var g2 := TitleState.grade(s)
	eq(g1, g2, "grade 连续两次结果相同")
	eq(TitleState.prop_plan(s), TitleState.prop_plan(s), "prop_plan 连续两次结果相同")
	eq(TitleState.light_plan(s), TitleState.light_plan(s), "light_plan 连续两次结果相同")
	eq(s, snapshot, "纯函数不改 state")
	# 返回的是深拷贝：改结果不会污染下一次调用
	g1["exposure"] = 999.0
	g1["souls_goal"] = -1
	g1["grade_tint"] = Color(1, 0, 0)
	g1["furnace_color"] = Color(0, 1, 0)
	eq(TitleState.grade(s), g2, "grade 返回深拷贝")
	var lights := TitleState.light_plan(s)
	lights.clear()
	eq(TitleState.light_plan(s), TitleState.light_plan(s), "light_plan 返回新数组")
	eq(TitleState.light_plan(s).size(), TitleState.LIGHT_FIXTURES, "清空返回值不影响下一次")
	var plan := TitleState.prop_plan(s)
	(plan["braziers"] as Array)[0] = 42.0
	plan["ghosts"] = 99
	var fresh_plan := TitleState.prop_plan(s)
	ok(float(fresh_plan["braziers"][0]) != 42.0, "prop_plan 的 braziers 是深拷贝")
	eq(fresh_plan["ghosts"], 3, "prop_plan 的 ghosts 是深拷贝")
	# 同一份 peek 连续 build 两次结果相同
	var peek := _peek("stage05", _done_flags(8))
	eq(TitleState.build_state(peek), TitleState.build_state(peek), "build_state 纯函数")
