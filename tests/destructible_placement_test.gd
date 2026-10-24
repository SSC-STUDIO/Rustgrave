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


func test_breakable_slab_opens_the_west_approach_to_the_dead_roof_reward() -> void:
	var level := await _load_level()
	if level == null:
		return
	var slab := level.find_child("RubbleRoofB", true, false) as BreakableTerrain
	ok(slab != null, "RubbleRoofB 已放置")
	if slab != null:
		ok(slab.size.y > LevelSanity.JUMP_RISE_MAX, "裂石板构成屋檐西口的障碍")
		var feet := slab.global_position + Vector2(slab.size.x * 0.5, slab.size.y)
		ok(LevelSanity.standing_on(LevelSanity.top_segments(level), feet) != null,
				"裂石板底脚坐在固定屋檐台面上")
		var reward := level.find_child("RewardDeadQuarter", true, false) as Node2D
		ok(reward != null, "屋脊奖励位存在")
		if reward != null:
			ok(reward.global_position.x > slab.global_position.x + slab.size.x,
					"奖励位在裂石板后方的屋脊，西口可以破坏开路")
		ok(not slab.persist_break, "会话内破坏：重载恢复，不写战役档")
		for index in slab.chunk_count():
			slab.damage_chunk(index, slab.chunk_hp)
		await flush(2)
		ok(slab.is_destroyed(), "支路的裂板可以清空")
		if reward != null:
			ok(LevelSanity.standing_on(LevelSanity.top_segments(level), LevelSanity.feet_of(reward)) != null,
					"清掉裂板后奖励仍站在固定屋脊上")
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
