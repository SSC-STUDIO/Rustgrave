extends TestCase
## M3 放置检查：level09 出口东侧死角的 persist 秘道墙（rampart 裂石墙），
## 墙后藏着余烬窖，墙西陪一只锈罐。主线（出口）在墙西，不经过它。

const LEVEL_PATH := "res://scenes/levels/Level09_Ramparts.tscn"
const WALL_POS := Vector2(4104, 256)
const WALL_SIZE := Vector2(64, 64)
const CACHE_FEET := Vector2(4186, 320)
const URN_FEET := Vector2(4040, 320)


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
	ok(packed != null, "level09 场景加载")
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	return level


func test_secret_wall_seals_the_east_dead_end() -> void:
	var level := await _load_level()
	if level == null:
		return
	var slab := level.find_child("SecretWallEast", true, false) as BreakableTerrain
	ok(slab != null, "SecretWallEast 已放置")
	if slab != null:
		eq(slab.size, WALL_SIZE, "秘道墙 64x64（2x2 块）")
		eq(slab.chunk_count(), 4)
		eq(slab.skin, "rampart", "城墙皮：和城垒石板同族")
		ok(slab.persist_break, "秘道墙 persist_break=true：打碎写进战役档")
		almost(slab.global_position.x, WALL_POS.x, 0.01, "墙在出口东侧死角")
		almost(slab.global_position.y + slab.size.y, 320.0, 0.01,
				"墙底脚坐在 FloorE 台面（320）")
		ok(slab.get_parent().name == "Props", "秘道墙进 Props 组")
		var exit := level.find_child("Exit", true, false) as Node2D
		ok(exit != null, "出口存在")
		if exit != null:
			ok(exit.global_position.x < slab.global_position.x,
					"出口在秘道墙西侧：主路线不经过秘道墙")
	level.free()
	await flush(1)


func test_cache_waits_behind_the_wall_and_urn_marks_the_spot() -> void:
	var level := await _load_level()
	if level == null:
		return
	var slab := level.find_child("SecretWallEast", true, false) as BreakableTerrain
	ok(slab != null, "SecretWallEast 已放置")
	if slab == null:
		level.free()
		await flush(1)
		return
	var cache := level.find_child("SecretEmberCache", true, false) as DestructibleProp
	ok(cache != null, "SecretEmberCache 已放置")
	if cache != null:
		eq(cache.prop_id, &"ember_cache")
		almost(cache.global_position.x, CACHE_FEET.x, 0.01)
		almost(cache.global_position.y, 320.0, 0.01, "余烬窖脚点在 FloorE 台面（320）")
		ok(cache.get_parent().name == "Props", "余烬窖进 Props 组")
		ok(cache.global_position.x > slab.global_position.x + slab.size.x,
				"余烬窖在秘道墙东侧：打碎墙才够得着")
	var urn := level.find_child("SecretRustUrn", true, false) as DestructibleProp
	ok(urn != null, "SecretRustUrn 已放置")
	if urn != null:
		eq(urn.prop_id, &"rust_urn")
		almost(urn.global_position.x, URN_FEET.x, 0.01)
		almost(urn.global_position.y, 320.0, 0.01, "锈罐脚点在 FloorE 台面（320）")
		ok(urn.get_parent().name == "Props", "锈罐进 Props 组")
		ok(urn.global_position.x < slab.global_position.x,
				"锈罐在墙西（到达侧），只是点缀不挡路")
	level.free()
	await flush(1)


func test_main_route_does_not_depend_on_the_secret_wall() -> void:
	var level := await _load_level()
	if level == null:
		return
	# 秘道墙只封出口东侧的死角奖励；巢与出口的可达性由 LevelSanity 独立检查
	# （可破坏物不计入台面，主路线结构性不依赖打碎它们）。
	var reports := LevelSanity.check(level, Rect2())
	for problem in reports:
		ok(false, "level09 体检失败：%s" % problem)
	ok(reports.is_empty(), "level09 LevelSanity clean（%d 问题）" % reports.size())
	level.free()
	await flush(1)
