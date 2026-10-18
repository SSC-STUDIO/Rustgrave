extends TestCase
## 炉风先驱（EmberwindHerald）验收：Kit / 飞行悬停与 airborne 豁免 / 俯冲 / 风推 /
## 羽刃弹幕 / 上升气流 / 钩锁拉下处决 / 二阶段 / 死亡旗标。

const BOSS := preload("res://scenes/enemies/EmberwindHerald.tscn")
const FLAG := "herald_dead"


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


func _find_child_named(root: Node, prefix: String) -> Node:
	for child in root.get_children():
		if String(child.name).begins_with(prefix):
			return child
	return null


func _host(arena: Node) -> Node:
	var effects := arena.get_node_or_null("WorldEffects")
	return effects if effects != null else arena


func _projectiles(host: Node, boss: Node) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child in host.get_children():
		if child is Projectile and (child as Projectile).source == boss:
			out.append(child as Projectile)
	return out


func test_kit_and_airborne_hover() -> void:
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
		eq(kit.max_phases(), 2, "炉风先驱两阶段")
		var ids: Array = []
		for entry in kit.attack_pool():
			ids.append(String(entry.id))
		for id in ["dive", "wind_push", "feather_blades", "updraft"]:
			ok(ids.has(id), "攻击表包含 %s" % id)
	# 飞行豁免：level_sanity 据此跳过「脚下没有平台」。
	ok(boss.call("is_airborne"), "is_airborne() = true（飞行 Boss）")
	ok(boss.global_position.y < 0.0, "悬停在地面之上（y=%.1f）" % boss.global_position.y)
	almost(boss.global_position.y, float(boss.call("hover_y")), 1.0, "停在自己的悬停高度")
	var director := boss.call("boss_director") as BossDirector
	ok(director != null and director.auto_drive, "驾驶模式导演层")
	var heard: Array = []
	var on_appear := func(name_: String, _cur: int, _max: int) -> void: heard.append(name_)
	GameEvents.boss_appeared.connect(on_appear)
	boss.call("announce")
	boss.call("announce")
	eq(heard.size(), 1, "announce 恰好一次")
	GameEvents.boss_appeared.disconnect(on_appear)
	arena.queue_free()
	await flush(2)


func test_dive_moves_fast_and_arms_hitbox() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	var boss := _spawn(arena, player.global_position + Vector2(220, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	var start_x: float = boss.global_position.x
	boss.call("_begin_attack", &"dive")
	boss.call("_tick_state", 0.59)
	eq(int(boss.call("dive_count")), 1, "俯冲计数")
	ok(boss.hitbox.monitoring, "俯冲判定打开")
	boss.call("_tick_state", 0.2)
	var moved: float = absf(boss.global_position.x - start_x)
	ok(moved > 100.0, "俯冲真的穿过竞技场（%.0f px）" % moved)
	ok(boss.global_position.y > -80.0, "俯冲把身体压到低空")
	boss.call("_tick_state", 0.3)
	ok(not boss.hitbox.monitoring, "俯冲判定收掉")
	boss.call("_tick_state", 0.9)
	eq(boss.call("state"), 0, "俯冲结束回到悬停")
	arena.queue_free()
	await flush(2)


func test_wind_push_and_updraft_zones() -> void:
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
	# 风推：生成持续推力区，站进去会被吹。
	boss.call("_begin_attack", &"wind_push")
	boss.call("_tick_state", 0.56)
	eq(int(boss.call("push_count")), 1, "风推计数")
	var zone := _find_child_named(boss, "WindZone") as Area2D
	ok(zone != null, "风推生成推力区")
	if zone != null:
		ok(float(zone.get("flow")) != 0.0, "推力区有方向")
		player.global_position = zone.global_position
		await flush(6)
		ok(absf(player.velocity.x) > 5.0, "站进风推区被推着走（vx=%.1f）" % player.velocity.x)
	# 上升气流：三阶段才有，这里直接验证二阶段的区域与 lift。
	boss.health.take_damage(10, player)
	boss.call("_tick_state", 1.3)
	player.velocity = Vector2.ZERO
	boss.call("_begin_attack", &"updraft")
	boss.call("_tick_state", 0.61)
	eq(int(boss.call("updraft_count")), 1, "上升气流计数")
	var draft := _find_child_named(boss, "UpdraftZone") as Area2D
	ok(draft != null, "生成上升气流区")
	if draft != null:
		ok(float(draft.get("lift")) > 0.0, "托管力 > 0")
		player.global_position = draft.global_position
		await flush(6)
		var bodies: Array = draft.get("_bodies") as Array
		ok(bodies.has(player), "玩家被上升气流区识别")
	arena.queue_free()
	await flush(2)


func test_feather_blades_volley_scales_in_phase_two() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	var boss := _spawn(arena, player.global_position + Vector2(220, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	boss.call("_begin_attack", &"feather_blades")
	boss.call("_tick_state", 0.56)
	eq(int(boss.call("blade_volleys")), 1, "羽刃齐射计数")
	var p1 := _projectiles(_host(arena), boss).size()
	ok(p1 >= 5, "一阶段 5 片羽刃")
	boss.call("_tick_state", 0.3)
	boss.call("_tick_state", 0.8)
	# 二阶段：6 片。
	await get_tree().create_timer(0.55).timeout                         # 让受击 iframe 先过去
	boss.health.take_damage(10, player)
	boss.call("_tick_state", 1.3)
	boss.call("_begin_attack", &"feather_blades")
	boss.call("_tick_state", 0.56)
	var p2 := _projectiles(_host(arena), boss).size()
	ok(p2 - p1 >= 6, "二阶段羽刃加密（本次 %d 片）" % (p2 - p1))
	arena.queue_free()
	await flush(2)


func test_hook_chain_pulls_the_herald_down() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	var boss := _spawn(arena, player.global_position + Vector2(140, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	ok(boss.call("is_yankable"), "飞行 Boss 可被钩锁拽下")
	var ok_yank: Variant = boss.call("yank_to", player.global_position + Vector2(80, 0), 0.2)
	ok(bool(ok_yank), "钩锁拉下生效")
	ok(boss.call("is_down"), "被拉下后进入倒地状态")
	ok(boss.is_marked(), "倒地开破绽（处决窗口）")
	eq(int(boss.call("yank_count")), 1, "拉下计数")
	ok(absf(boss.global_position.y) < 40.0, "被拉到地面高度（y=%.1f）" % boss.global_position.y)
	ok(boss.global_position.y > boss.call("hover_y"), "离开了悬停高度")
	boss.call("_tick_state", 2.7)
	ok(not boss.call("is_down"), "倒地窗口结束")
	arena.queue_free()
	await flush(2)


func test_death_flag() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn(arena, player.global_position + Vector2(220, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	var slain := [0]
	var defeated := [0]
	boss.slain.connect(func() -> void: slain[0] += 1)
	var on_defeated := func() -> void: defeated[0] += 1
	GameEvents.boss_defeated.connect(on_defeated)
	ok(not SaveData.has_flag(FLAG), "开战前没有死亡旗标")
	boss.health.take_damage(99, player)
	eq(slain[0], 1, "slain 一次")
	eq(defeated[0], 1, "boss_defeated 一次")
	ok(SaveData.has_flag(FLAG), "落 herald_dead 旗标")
	await flush(3)
	ok(not is_instance_valid(boss), "死亡演出后释放")
	GameEvents.boss_defeated.disconnect(on_defeated)
	arena.queue_free()
	await flush(2)
