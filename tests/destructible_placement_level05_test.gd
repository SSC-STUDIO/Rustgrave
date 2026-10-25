extends TestCase
## M3 放置检查：level05（齿轮工坊）的支路可破坏道具。
## 检修龛一只锈罐；吊装检修台奖励位两侧碎铁堆 + 余烬窖。全部贴台面顶面、进 Props 组。

const LEVEL_PATH := "res://scenes/levels/Level05_Workshop.tscn"


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
	ok(packed != null, "level05 场景加载")
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	return level


func test_nook_branch_rust_urn() -> void:
	var level := await _load_level()
	if level == null:
		return
	var prop := level.find_child("RustUrnNook", true, false) as DestructibleProp
	ok(prop != null, "RustUrnNook 已放置")
	if prop != null:
		eq(prop.prop_id, &"rust_urn")
		almost(prop.global_position.y, 152.0, 0.01, "脚点在检修龛台面（152）")
		ok(prop.get_parent().name == "Props", "RustUrnNook 进 Props 组")
	level.free()
	await flush(1)


func test_hoist_deck_reward_flankers() -> void:
	var level := await _load_level()
	if level == null:
		return
	for spec in [["ScrapHeapHoist", &"scrap_heap"], ["EmberCacheHoist", &"ember_cache"]]:
		var prop := level.find_child(String(spec[0]), true, false) as DestructibleProp
		ok(prop != null, "%s 已放置" % spec[0])
		if prop == null:
			continue
		eq(prop.prop_id, StringName(spec[1]))
		almost(prop.global_position.y, 240.0, 0.01,
				"%s 脚点在吊装检修台台面（240）" % spec[0])
		ok(prop.get_parent().name == "Props", "%s 进 Props 组" % spec[0])
	level.free()
	await flush(1)


func test_z_level_sanity_clean() -> void:
	var level := await _load_level()
	if level == null:
		return
	# 可破坏物不计入台面，主线可达性不许因这批道具变坏。
	var reports := LevelSanity.check(level, Rect2())
	for problem in reports:
		ok(false, "level05 体检失败：%s" % problem)
	ok(reports.is_empty(), "level05 LevelSanity clean（%d 问题）" % reports.size())
	level.free()
	await flush(1)
