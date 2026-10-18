extends TestCase
## M2 放置检查：level03 真的种下了可破坏道具/地形，且都在支路、不压主路线。

const LEVEL_PATH := "res://scenes/levels/Level03_RustTown.tscn"


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()


func _load_level() -> Node:
	var packed := load(LEVEL_PATH) as PackedScene
	ok(packed != null, "level03 场景加载")
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	return level


func test_level03_has_destructible_props_on_the_street() -> void:
	var level := await _load_level()
	if level == null:
		return
	for spec in [["ScrapHeapStreet", &"scrap_heap"], ["RustUrnStreet", &"rust_urn"]]:
		var prop := level.find_child(String(spec[0]), true, false) as DestructibleProp
		ok(prop != null, "%s 已放置" % spec[0])
		if prop == null:
			continue
		eq(prop.prop_id, StringName(spec[1]))
		almost(prop.global_position.y, 320.0, 0.01, "%s 脚点在街面（320）" % spec[0])
		ok(prop.get_parent().name == "Props", "%s 进 Props 组" % spec[0])
	level.free()
	await flush(1)


func test_breakable_slab_gates_the_dead_roof_reward() -> void:
	var level := await _load_level()
	if level == null:
		return
	var slab := level.find_child("RubbleRoofB", true, false) as BreakableTerrain
	ok(slab != null, "RubbleRoofB 已放置")
	if slab != null:
		eq(slab.size, Vector2(64, 64), "裂石板 64x64（2x2 块）")
		eq(slab.chunk_count(), 4)
		almost(slab.global_position.y + slab.size.y, 256.0, 0.01,
				"裂石板底脚坐在 DeadRoofA 台面（256）")
		var reward := level.find_child("RewardDeadQuarter", true, false) as Node2D
		ok(reward != null, "屋脊奖励位存在")
		if reward != null:
			ok(reward.global_position.x > slab.global_position.x + slab.size.x,
					"奖励在裂石板东侧：打碎石板才能过去")
		ok(not slab.persist_break, "会话内破坏：重载恢复，不写战役档")
	level.free()
	await flush(1)


func test_main_route_does_not_depend_on_the_slab() -> void:
	var level := await _load_level()
	if level == null:
		return
	# 裂石板只挡死城屋脊的支路奖励；巢与出口的可达性由 LevelSanity 独立检查。
	var reports := LevelSanity.check(level, Rect2())
	for problem in reports:
		ok(false, "level03 体检失败：%s" % problem)
	ok(reports.is_empty(), "level03 LevelSanity clean（%d 问题）" % reports.size())
	level.free()
	await flush(1)
