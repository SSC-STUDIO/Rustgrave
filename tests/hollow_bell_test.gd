extends TestCase
## 空钟（HollowBell）验收：Kit 数据 / 四招（摆锤、钟索拉拽、落钟、钟鸣波）/ 钟锤弱点 /
## 二阶段相变 / 死亡旗标。
## 脚本没有 class_name（与现有 Boss 一致），全部走 preload 场景 + 动态调用。

const BOSS := preload("res://scenes/enemies/HollowBell.tscn")
const FLAG := "hollow_bell_dead"


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


func _host(arena: Node) -> Node:
	# Boss 的临时判定/弹丸/Projectile 都挂在 WorldEffects 下（GameContext.world_effects）。
	var effects := arena.get_node_or_null("WorldEffects")
	return effects if effects != null else arena


func _boxes(host: Node) -> Array[Hitbox]:
	var out: Array[Hitbox] = []
	for child in host.get_children():
		if child is Hitbox:
			out.append(child as Hitbox)
	return out


func test_kit_and_announce() -> void:
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
		eq(kit.max_phases(), 2, "空钟两阶段")
		eq(kit.boss_title(), boss.get_script().get_script_constant_map()["BOSS_TITLE"],
				"Kit 名号与脚本同源")
		var ids: Array = []
		for entry in kit.attack_pool():
			ids.append(String(entry.id))
		for id in ["pendulum", "chain_pull", "bell_drop", "toll_wave"]:
			ok(ids.has(id), "攻击表包含 %s" % id)
		ok(kit.attack_pool().size() == 4, "四招都在表里")
		for entry in kit.attack_pool():
			ok(kit.windup_for(entry, 1) >= BossKit.BOSS_TELEGRAPH_MIN,
					"%s 前摇 >= 0.35s" % entry.id)
			ok(BossKit.hitbox_reach(entry) <= 460.0, "%s 判定不超出场地半宽" % entry.id)
	var director := boss.call("boss_director") as BossDirector
	ok(director != null, "驾驶模式导演层存在")
	if director != null:
		ok(director.auto_drive, "新 Boss 用驾驶模式")
		eq(director.running, false, "未开战前不调度")
	var heard: Array = []
	var on_appear := func(name_: String, _cur: int, _max: int) -> void: heard.append(name_)
	GameEvents.boss_appeared.connect(on_appear)
	ok(not boss.call("is_announced"), "远处还没亮名号")
	boss.call("announce")
	boss.call("announce")
	eq(heard.size(), 1, "announce 恰好一次")
	if director != null:
		ok(director.running, "announce 后导演层开战")
	GameEvents.boss_appeared.disconnect(on_appear)
	arena.queue_free()
	await flush(2)


func test_pendulum_telegraph_and_hitbox() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	var telegraphs := [0]
	var on_tel := func(_kind: StringName, _dur: float) -> void: telegraphs[0] += 1
	boss.connect("telegraph_started", on_tel)
	boss.call("_begin_attack", &"pendulum")
	eq(boss.call("state"), 1, "摆锤进入出招状态")
	eq(boss.call("attack_name"), &"pendulum")
	eq(telegraphs[0], 1, "起手先发读招")
	boss.call("_tick_state", 0.61)      # 走完前摇
	var fling: Variant = boss.get("_fling")
	ok(fling != null and is_instance_valid(fling), "前摇结束扫出摆锤判定")
	if fling is Hitbox:
		ok((fling as Hitbox).monitoring, "摆锤判定已打开")
		var shape := ((fling as Hitbox).get_child(0) as CollisionShape2D).shape as RectangleShape2D
		eq(shape.size, boss.get_script().get_script_constant_map()["PENDULUM_BOX"],
				"摆锤判定盒 = 常量")
		ok((fling as Hitbox).damage >= 1, "摆锤有伤害")
	boss.call("_tick_state", 0.4)       # 判定段
	ok(not is_instance_valid(boss.get("_fling")), "收锤后判定收回")
	boss.call("_tick_state", 0.75)      # 后摇
	eq(boss.call("state"), 0, "收锤回到待机")
	boss.disconnect("telegraph_started", on_tel)
	arena.queue_free()
	await flush(2)


func test_chain_pull_drags_and_jump_escapes() -> void:
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
	player.global_position = boss.global_position + Vector2(-180, -24)
	player.velocity = Vector2.ZERO
	boss.call("_begin_attack", &"chain_pull")
	boss.call("_tick_state", 0.56)       # 前摇结束，开始拉
	ok(bool(boss.get("_pulling")), "钟索拉拽开始")
	boss.call("_tick_state", 0.2)
	ok(player.velocity.x > 0.0, "骑士被拉向钟心（向右的速度 %.1f）" % player.velocity.x)
	# 跳起甩开：拉拽立即结束。
	player.velocity.y = -220.0
	boss.call("_tick_state", 0.02)
	ok(not bool(boss.get("_pulling")), "跳跃反制成功，拉拽中断")
	# 钩锁反制同样成立。
	player.velocity.y = 0.0
	player.velocity.x = 0.0
	boss.call("_begin_attack", &"chain_pull")
	boss.call("_tick_state", 0.56)
	var hook := player.get_node_or_null("HookshotTether")
	if hook != null:
		hook.set("_anchor", boss)      # 伪造钩锁激活（is_active 读 _anchor）
		boss.call("_tick_state", 0.05)
		ok(not bool(boss.get("_pulling")), "钩锁反制成功，拉拽中断")
		hook.set("_anchor", null)
	arena.queue_free()
	await flush(2)


func test_bell_drop_and_toll_wave_are_parryable() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn(arena, player.global_position + Vector2(180, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	var host := _host(arena)
	# 落钟：落点先出区域预警，判定落在骑士脚下、尺寸与常量一致。
	boss.call("_begin_attack", &"bell_drop")
	boss.call("_tick_state", 0.71)
	var boxes := _boxes(_host(arena))
	ok(boxes.size() >= 1, "落钟生成了地面判定")
	if boxes.size() >= 1:
		eq((boxes[0].get_child(0) as CollisionShape2D).shape.size,
				boss.get_script().get_script_constant_map()["DROP_ZONE"], "落钟判定盒 = 常量")
	boss.call("_tick_state", 0.3)
	boss.call("_tick_state", 0.7)
	# 钟鸣波：左右各一道可弹反弹丸（走 Projectile 管线）。
	var p0 := Projectile.live_count()
	boss.call("_begin_attack", &"toll_wave")
	boss.call("_tick_state", 0.51)
	var waves: Array[Projectile] = []
	for child in _host(arena).get_children():
		if child is Projectile and (child as Projectile).source == boss:
			waves.append(child as Projectile)
	ok(Projectile.live_count() >= p0 + 2, "钟鸣波生成弹丸")
	ok(waves.size() >= 2, "左右各一道钟鸣波")
	for wave in waves:
		ok(wave.can_deflect(), "钟鸣波可被弹反")
	# 弹回：空钟破防（硬直 + 破绽）。
	if waves.size() >= 1:
		GameEvents.parried.emit(waves[0], player)
		eq(boss.call("state"), 2, "被弹反的钟鸣让空钟破防")
		ok(boss.is_marked(), "破防后露出破绽（下一刀翻倍）")
		eq(int(boss.call("parried_waves")), 1, "弹反计数")
	boss.call("_tick_state", 1.7)
	eq(boss.call("state"), 0, "破防结束回到待机")
	arena.queue_free()
	await flush(2)


func test_weakpoint_phase_two_and_death_flag() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	boss.set_physics_process(false)
	boss.call("announce")
	var director := boss.call("boss_director") as BossDirector
	if director != null:
		director.set_physics_process(false)
	# 钟锤弱点：打断当前招 + 破绽。
	boss.call("_begin_attack", &"pendulum")
	boss.call("_on_weak_hurt", 1, player)
	eq(boss.call("state"), 2, "打中钟锤让空钟破防")
	eq(int(boss.call("weak_marks")), 1, "弱点命中计数")
	ok(boss.is_marked(), "弱点命中开破绽")
	boss.call("_tick_state", 1.7)
	eq(boss.call("state"), 0, "破防结束")
	# 半血相变：2 阶段、1.2s 无敌演出。
	await get_tree().create_timer(0.55).timeout                     # 让受击 iframe 先过去
	boss.health.take_damage(9, player)
	eq(int(boss.call("phase")), 2, "半血进入二阶段")
	ok(boss.call("is_enraged"), "二阶段狂暴")
	ok(boss.health.invincible, "相变无敌演出")
	boss.call("_tick_state", 0.7)
	ok(boss.health.invincible, "1.2s 内仍无敌")
	boss.call("_tick_state", 0.6)
	ok(not boss.health.invincible, "演出结束解除无敌")
	# 死亡：slain + boss_defeated + hollow_bell_dead 旗标。
	await get_tree().create_timer(0.55).timeout
	var slain := [0]
	var defeated := [0]
	boss.slain.connect(func() -> void: slain[0] += 1)
	var on_defeated := func() -> void: defeated[0] += 1
	GameEvents.boss_defeated.connect(on_defeated)
	ok(not SaveData.has_flag(FLAG), "开战前没有死亡旗标")
	boss.health.take_damage(99, player)
	eq(slain[0], 1, "slain 一次")
	eq(defeated[0], 1, "boss_defeated 一次")
	ok(SaveData.has_flag(FLAG), "落 hollow_bell_dead 旗标")
	ok(boss._dead, "死亡标记")
	await flush(3)
	ok(not is_instance_valid(boss), "死亡演出后释放")
	GameEvents.boss_defeated.disconnect(on_defeated)
	arena.queue_free()
	await flush(2)
