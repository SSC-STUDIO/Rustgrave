extends TestCase
## M3 放置检查：Arena_Duel 观礼矮墙顶的两只装饰性可破坏物。
## 竞技场不走 ChapterLayout / LevelSanity（没有关卡台面语义），最后的测试换成
## 断言 persist=false、不进 arena_unit/arena_plane 组、脚点在纵深带之外。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const ARENA_PATH := "res://scenes/levels/Arena_Duel.tscn"
const WALL_TOP := 226.0


func setup() -> void:
	if get_tree().paused:
		get_tree().paused = false
	ArenaRun.auto_begin = false
	ArenaRun.abandon()


func teardown() -> void:
	ArenaRun.auto_begin = false
	ArenaRun.abandon()


func _load_arena() -> Node:
	var packed := load(ARENA_PATH) as PackedScene
	ok(packed != null, "Arena_Duel 场景加载")
	if packed == null:
		return null
	var world := packed.instantiate()
	add_child(world)
	await flush(2)
	ArenaRun.abandon()
	return world


func test_arena_has_spectator_destructibles_on_the_parapet() -> void:
	var world := await _load_arena()
	if world == null:
		return
	for spec in [["SpectatorUrnWest", &"rust_urn", 620.0], ["SpectatorHeapEast", &"scrap_heap", 3220.0]]:
		var prop := world.find_child(String(spec[0]), true, false) as DestructibleProp
		ok(prop != null, "%s 已放置" % spec[0])
		if prop == null:
			continue
		eq(prop.prop_id, StringName(spec[1]))
		almost(prop.global_position.x, float(spec[2]), 0.01, "%s 在观礼墙顶（左右镜像）" % spec[0])
		almost(prop.global_position.y, WALL_TOP, 0.01, "%s 脚点坐在矮墙顶（226）" % spec[0])
		ok(prop.get_parent() == world, "%s 直接挂在场馆根（y_sort 按脚点排序）" % spec[0])
		ok(prop.is_in_group(&"destructible_body"), "%s 仍是可破坏体" % spec[0])
	world.queue_free()
	await flush(2)


func test_props_are_side_show_only_not_fight_rules() -> void:
	var world := await _load_arena()
	if world == null:
		return
	for prop_name in ["SpectatorUrnWest", "SpectatorHeapEast"]:
		var prop := world.find_child(prop_name, true, false) as DestructibleProp
		ok(prop != null, "%s 已放置" % prop_name)
		if prop == null:
			continue
		ok(not prop.persist, "%s persist=false：场馆是临时对局，不写战役档" % prop_name)
		ok(not prop.is_in_group("arena_unit"), "%s 不进 arena_unit 组" % prop_name)
		ok(not prop.is_in_group("arena_plane"), "%s 不进 arena_plane 组" % prop_name)
		ok(not prop.is_in_group("arena_bolt"), "%s 不进 arena_bolt 组" % prop_name)
		eq(prop.collision_layer, 0, "%s 无碰撞层：纯摆设，不挡路" % prop_name)
		ok(not ArenaCatalog.in_depth(prop.global_position.y),
				"%s 在纵深带（%.0f..%.0f）之外" % [prop_name, ArenaCatalog.DEPTH_BACK, ArenaCatalog.DEPTH_FRONT])
		var gap := ArenaCatalog.DEPTH_BACK - prop.global_position.y
		ok(gap > ArenaCatalog.TOL_MELEE,
				"%s 距带后缘 %.0fpx > 近战容差 %.0f：对局里近战够不到" % [prop_name, gap, ArenaCatalog.TOL_MELEE])
	world.queue_free()
	await flush(2)
