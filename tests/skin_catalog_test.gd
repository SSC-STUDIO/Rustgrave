extends TestCase
## 皮肤/刻印目录：素材可用、动作映射完整、起源默认皮肤、解锁 id 对齐阶位奖励。

const SkinCatalog := preload("res://scripts/data/skin_catalog.gd")
const RuneCatalog := preload("res://scripts/data/rune_catalog.gd")
const EmberRankScript := preload("res://scripts/data/ember_rank.gd")

const EXPECTED_SKINS := [&"skin_fantasy_knight", &"skin_ash_runner",
		&"skin_cemetery_hero", &"skin_gothic_hero"]


func test_every_skin_declares_a_real_folder_and_complete_actions() -> void:
	for id in SkinCatalog.ids():
		var folder := SkinCatalog.folder_of(id)
		ok(CharFrames.available(folder), "%s 的素材目录 %s 存在" % [id, folder])
		ok(SkinCatalog.name_of(id) != "", "%s 有名字" % id)
		var counts := SkinCatalog.action_frame_counts(id)
		for action in SkinCatalog.LOGICAL_ACTIONS:
			ok(int(counts.get(action, 0)) > 0,
					"%s 的 %s 至少解析到一帧" % [id, action])
	for id in EXPECTED_SKINS:
		ok(SkinCatalog.has(id), "目录包含 %s" % id)


func test_default_skin_covers_the_full_knight_action_set() -> void:
	var counts := SkinCatalog.action_frame_counts(SkinCatalog.DEFAULT_SKIN)
	eq(int(counts[&"attack_combo"]), 10, "默认骑士连击 10 帧")
	eq(int(counts[&"idle"]), 10)
	var frames := SkinCatalog.frames_for(SkinCatalog.DEFAULT_SKIN, &"run")
	ok(frames.size() == 10)
	for tex in frames:
		ok(tex != null)


func test_action_slices_reduce_frame_counts() -> void:
	var cemetery := SkinCatalog.action_frame_counts(&"skin_cemetery_hero")
	eq(int(cemetery[&"attack1"]), 3, "墓园行客 attack1 取 3 帧")
	ok(int(cemetery[&"attack_combo"]) > int(cemetery[&"attack1"]))
	var gothic := SkinCatalog.action_frame_counts(&"skin_gothic_hero")
	eq(int(gothic[&"attack1"]), 3)
	eq(int(gothic[&"attack_combo"]), 6)


func test_offsets_and_tints_are_per_skin() -> void:
	eq(SkinCatalog.offset_for(&"skin_fantasy_knight", &"idle"), Vector2(6, -40))
	eq(SkinCatalog.offset_for(&"skin_cemetery_hero", &"idle"), Vector2(12, -29))
	eq(SkinCatalog.offset_for(&"skin_cemetery_hero", &"attack1"), Vector2(7, -29),
			"攻击动作有单独偏移")
	ok(SkinCatalog.tint_of(&"skin_ash_runner") != Color.WHITE)
	eq(SkinCatalog.tint_of(&"skin_fantasy_knight"), Color.WHITE)


func test_origin_defaults_map_to_the_three_hero_skins() -> void:
	eq(SkinCatalog.default_for_origin(OriginCatalog.ORIGIN_EMBER_VANGUARD),
			&"skin_fantasy_knight")
	eq(SkinCatalog.default_for_origin(OriginCatalog.ORIGIN_SCRAP_SCAVENGER),
			&"skin_ash_runner")
	eq(SkinCatalog.default_for_origin(OriginCatalog.ORIGIN_RUST_AUTOMATON),
			&"skin_cemetery_hero")
	eq(SkinCatalog.default_for_origin(&"nobody"), SkinCatalog.DEFAULT_SKIN)


func test_skin_unlock_ids_match_rank_rewards() -> void:
	var rewards: Array = []
	for rank in EmberRankScript.REWARDS:
		for value in EmberRankScript.REWARDS[rank]:
			rewards.append(String(value))
	for id in [&"skin_ash_runner", &"skin_cemetery_hero", &"skin_gothic_hero"]:
		var unlock := String(SkinCatalog.def(id).get("unlock", ""))
		ok(rewards.has(unlock), "%s 的解锁 id %s 在阶位奖励表里" % [id, unlock])


func test_rune_catalog_complete_and_lines() -> void:
	ok(RuneCatalog.ids().size() >= 4)
	for id in RuneCatalog.ids():
		ok(RuneCatalog.name_of(id) != "")
		ok(RuneCatalog.desc_of(id) != "")
		ok(not RuneCatalog.modifier_of(id).is_empty(), "%s 有属性" % id)
	eq(RuneCatalog.modifier_of(&"rune_unbroken"), {"max_hp": 1, "defense": 1})
	eq(RuneCatalog.modifier_of(&"nope"), {})
	ok(RuneCatalog.line_of(&"rune_ember_grip").contains("余烬握柄"))
	eq(RuneCatalog.line_of(&"nope"), "无刻印")
