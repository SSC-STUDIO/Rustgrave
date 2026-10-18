extends TestCase
## 主动技能目录 + 输入动作接线：数据完整、键位可改、冷却为正。

const SkillCatalog := preload("res://scripts/data/skill_catalog.gd")
const EmberRankScript := preload("res://scripts/data/ember_rank.gd")


func test_catalog_entries_are_complete() -> void:
	ok(SkillCatalog.ids().size() >= 4, "至少 4 个技能")
	for id in SkillCatalog.ids():
		var def: Dictionary = SkillCatalog.def(id)
		ok(String(def.get("name", "")) != "", "%s 有名字" % id)
		ok(String(def.get("desc", "")) != "", "%s 有说明" % id)
		ok(float(def.get("cooldown", 0.0)) > 0.0, "%s 冷却为正" % id)
		ok(StringName(def.get("effect", &"")) != &"", "%s 有 effect" % id)
		var rank := int(def.get("unlock_rank", 0))
		ok(rank >= 1, "%s 的解锁阶位合法" % id)
	eq(SkillCatalog.name_of(&"ember_burst"), "余烬冲击")
	eq(SkillCatalog.effect_of(&"toxin_purge"), &"purge")
	eq(SkillCatalog.cooldown_of(&"nope"), 0.0, "未知技能冷却 0")
	ok(not SkillCatalog.has(&"nope"))


func test_default_slots_are_usable() -> void:
	ok(SkillCatalog.has(SkillCatalog.DEFAULT_SLOT_1), "默认槽 1 是有效技能")
	eq(SkillCatalog.DEFAULT_SLOT_2, &"", "默认槽 2 为空")
	eq(SkillCatalog.SLOT_COUNT, 2)


func test_input_actions_exist_and_are_rebindable() -> void:
	for slot in SkillCatalog.SLOT_COUNT:
		var action := SkillCatalog.input_action(slot)
		ok(InputMap.has_action(action), "%s 已在 InputMap" % action)
		ok(Settings.REBINDABLE.has(action), "%s 可在设置里改键" % action)
		ok(KeyLabels.action_name(action) != String(action),
				"%s 有中文动作名" % action)


func test_rank_unlock_table_points_at_real_skills() -> void:
	for id in [&"ember_burst", &"hollow_guard", &"rust_lance"]:
		var def: Dictionary = SkillCatalog.def(id)
		var rank := int(def.get("unlock_rank", 0))
		ok(rank >= 1 and rank <= EmberRankScript.MAX_RANK, "%s 阶位在 1..10" % id)
		var rewards: Array = EmberRankScript.REWARDS.get(rank, [])
		var expected := StringName("skill_%s" % String(id))
		ok(rewards.has(expected), "%s 对应 EmberRank 解锁表" % id)
