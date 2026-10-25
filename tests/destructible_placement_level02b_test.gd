extends TestCase
## M3 放置检查：level02b 的爆破罐连锁演示位与绞盘架支路道具。
## 脚点必须精确贴所在台面顶面，全部进 Props 组，主线不靠打碎通过（LevelSanity 兜底）。

const LEVEL_PATH := "res://scenes/levels/Level02b_SlagConduit.tscn"


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
	ok(packed != null, "level02b 场景加载")
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	return level


func test_blast_urn_chain_pair_on_the_pump_catwalk() -> void:
	var level := await _load_level()
	if level == null:
		return
	var first := level.find_child("BlastUrnCatwalkA", true, false) as DestructibleProp
	var second := level.find_child("BlastUrnCatwalkB", true, false) as DestructibleProp
	for spec in [[first, "BlastUrnCatwalkA"], [second, "BlastUrnCatwalkB"]]:
		var prop := spec[0] as DestructibleProp
		ok(prop != null, "%s 已放置" % spec[1])
		if prop == null:
			continue
		eq(prop.prop_id, &"blast_urn")
		almost(prop.global_position.y, 136.0, 0.01,
				"%s 脚点在检修走道台面（136）" % spec[1])
		ok(prop.get_parent().name == "Props", "%s 进 Props 组" % spec[1])
	if first != null and second != null:
		var gap := first.global_position.distance_to(second.global_position)
		ok(gap <= 40.0, "两只爆破罐相距 %.0fpx ≤ 40（引爆半径 44，可连锁）" % gap)
	level.free()
	await flush(1)


func test_capstan_gallery_branch_props() -> void:
	var level := await _load_level()
	if level == null:
		return
	for spec in [["RustUrnCapstan", &"rust_urn"], ["EmberCacheCapstan", &"ember_cache"]]:
		var prop := level.find_child(String(spec[0]), true, false) as DestructibleProp
		ok(prop != null, "%s 已放置" % spec[0])
		if prop == null:
			continue
		eq(prop.prop_id, StringName(spec[1]))
		almost(prop.global_position.y, 120.0, 0.01,
				"%s 脚点在绞盘架台面（120）" % spec[0])
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
		ok(false, "level02b 体检失败：%s" % problem)
	ok(reports.is_empty(), "level02b LevelSanity clean（%d 问题）" % reports.size())
	level.free()
	await flush(1)
