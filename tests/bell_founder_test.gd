extends TestCase
## 铸钟人（BellFounder）验收：Kit / 锤击可弹反破防 / 铸模召唤 / 浇铸区（熔金池）/
## 二阶段扩大 / 死亡旗标。

const BOSS := preload("res://scenes/enemies/BellFounder.tscn")
const FLAG := "founder_dead"


func setup() -> void:
	_clear_flag()


func teardown() -> void:
	_clear_flag()


func _clear_flag() -> void:
	var i := SaveData.flags.find(FLAG)
	if i >= 0:
		SaveData.flags.remove_at(i)


func _spawn(arena: Node2D, pos: Vector2) -> Node2D:
	var boss := BOSS.instantiate() as Node2D
	boss.position = pos
	arena.add_child(boss)
	return boss


func _children_named(root: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		if String(child.name).begins_with(prefix):
			out.append(child)
	return out


func _host(arena: Node) -> Node:
	# 每次重新定位 WorldEffects：Boss 第一次出招时才创建它（缓存会拿到旧的 arena）。
	var effects := arena.find_child("WorldEffects", true, false)
	return effects if effects != null else arena


func _projectiles(host: Node, boss: Node) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child in host.get_children():
		if child is Projectile and (child as Projectile).source == boss:
			out.append(child as Projectile)
	return out


func test_kit_announce_and_phase_two() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn(arena, player.global_position + Vector2(620, 0))
	await flush(2)
	var kit := boss.call("boss_kit") as BossKit
	ok(kit != null, "Boss 挂了 BossKit")
	if kit != null:
		eq(kit.validate().size(), 0, "Kit 自检通过")
		eq(kit.max_phases(), 2, "铸钟人两阶段")
		eq(kit.boss_title(), boss.get_script().get_script_constant_map()["BOSS_TITLE"], "名号同源")
		var ids: Array = []
		for entry in kit.attack_pool():
			ids.append(String(entry.id))
		for id in ["hammer_slam", "mold_cast", "molten_pool", "bell_shard"]:
			ok(ids.has(id), "攻击表包含 %s" % id)
	var director := boss.call("boss_director") as BossDirector
	ok(director != null and director.auto_drive, "驾驶模式导演层")
	var heard: Array = []
	var on_appear := func(name_: String, _cur: int, _max: int) -> void: heard.append(name_)
	GameEvents.boss_appeared.connect(on_appear)
	boss.call("announce")
	boss.call("announce")
	eq(heard.size(), 1, "announce 恰好一次")
	GameEvents.boss_appeared.disconnect(on_appear)
	# 半血 -> 二阶段（熔池扩大在下面单独验证）。
	boss.set_physics_process(false)
	boss.health.take_damage(10, player)
	eq(int(boss.call("phase")), 2, "半血进入二阶段")
	ok(boss.call("is_enraged"), "二阶段炉温不再下降")
	ok(boss.health.invincible, "相变无敌演出")
	boss.call("_tick_state", 1.3)
	ok(not boss.health.invincible, "演出结束解除无敌")
	arena.queue_free()
	await flush(2)


func test_hammer_parry_breaks_guard() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn(arena, player.global_position + Vector2(120, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	boss.call("_begin_attack", &"hammer_slam")
	boss.call("_tick_state", 0.63)        # 前摇结束 -> 锤击 + 锤势
	var waves := _projectiles(_host(arena), boss)
	ok(waves.size() >= 1, "锤击甩出一道可弹反锤势")
	if waves.size() >= 1:
		ok(waves[0].can_deflect(), "锤势可被弹反")
		GameEvents.parried.emit(waves[0], player)
		ok(boss.call("is_broken"), "锤势被弹回 -> 破防")
		eq(int(boss.call("break_count")), 1, "破防计数")
		ok(boss.is_marked(), "破防开破绽（下一刀翻倍）")
		eq(boss.call("state"), 2, "破防进入硬直状态")
	boss.call("_tick_state", 2.3)
	ok(not boss.call("is_broken"), "破防窗口结束")
	arena.queue_free()
	await flush(2)


func test_mold_cast_and_bell_shards() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	var boss := _spawn(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	# 一阶段：铸模召唤 2 只钟壳（走可弹反弹丸管线）。
	boss.call("_begin_attack", &"mold_cast")
	boss.call("_tick_state", 0.59)
	eq(int(boss.call("husks_spawned")), 2, "一阶段召唤 2 只钟壳")
	boss.call("_tick_state", 0.3)
	boss.call("_tick_state", 0.7)
	# 钟片投射：三片扇形。
	boss.call("_begin_attack", &"bell_shard")
	boss.call("_tick_state", 0.53)
	eq(int(boss.call("shard_volleys")), 1, "钟片齐射")
	var shards := _projectiles(_host(arena), boss).size()
	ok(shards >= 3, "三片钟片（+ 之前的钟壳）")
	boss.call("_tick_state", 0.3)
	boss.call("_tick_state", 0.7)
	# 二阶段：召唤数量增加。
	await get_tree().create_timer(0.55).timeout                         # 让受击 iframe 先过去
	boss.health.take_damage(10, player)
	boss.call("_tick_state", 1.3)
	boss.call("_begin_attack", &"mold_cast")
	boss.call("_tick_state", 0.59)
	eq(int(boss.call("husks_spawned")), 5, "二阶段钟壳 +3（累计 5）")
	arena.queue_free()
	await flush(2)


func test_molten_pool_grows_in_phase_two_and_damages() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	var boss := _spawn(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	var base_radius := float(boss.call("pool_radius"))
	# 二阶段：两片更大的熔池。
	boss.health.take_damage(10, player)
	boss.call("_tick_state", 1.3)
	ok(float(boss.call("pool_radius")) > base_radius, "二阶段熔池半径更大")
	boss.call("_begin_attack", &"molten_pool")
	boss.call("_tick_state", 0.71)
	eq(int(boss.call("pool_count")), 2, "二阶段泼出两片熔池（安全台被挤窄）")
	var pools: Array[Node] = []
	for child in boss.get_children():
		if "MoltenPool" in String(child.name):
			pools.append(child)
	eq(pools.size(), 2, "熔池节点挂在 Boss 下")
	# 站进熔池：掉血（0.9s tick 后还会继续掉）。
	if pools.size() >= 1:
		var pool := pools[0] as Node2D
		player.global_position = pool.global_position + Vector2(0, 6)
		var hp_before := player.health.current
		await flush(8)
		ok(player.health.current < hp_before, "站进熔金池会掉血")
	player.health.invincible = false
	boss.call("_tick_state", 0.3)
	arena.queue_free()
	await flush(2)


func test_death_flag_and_cleanup() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	# 先放一片熔池，验证死亡清场。
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	boss.health.take_damage(10, player)
	boss.call("_tick_state", 1.3)
	boss.call("_begin_attack", &"molten_pool")
	boss.call("_tick_state", 0.71)
	ok(int(boss.call("pool_count")) >= 1, "死亡前有熔池")
	await get_tree().create_timer(0.55).timeout                         # 让受击 iframe 先过去
	var slain := [0]
	var defeated := [0]
	boss.slain.connect(func() -> void: slain[0] += 1)
	var on_defeated := func() -> void: defeated[0] += 1
	GameEvents.boss_defeated.connect(on_defeated)
	ok(not SaveData.has_flag(FLAG), "开战前没有死亡旗标")
	boss.health.take_damage(99, player)
	eq(slain[0], 1, "slain 一次")
	eq(defeated[0], 1, "boss_defeated 一次")
	ok(SaveData.has_flag(FLAG), "落 founder_dead 旗标")
	await flush(3)
	ok(not is_instance_valid(boss), "死亡演出后释放")
	GameEvents.boss_defeated.disconnect(on_defeated)
	arena.queue_free()
	await flush(2)
