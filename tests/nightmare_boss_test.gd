extends TestCase
## 梦魇：远处不亮血条 → 靠近只 announce 一次 → 冲锋位移并计数 → 半血嘶鸣召火骷髅 →
## 死亡发 slain 并落 nightmare_dead 旗标。
## 脚本没有 class_name（等导入后类缓存才会更新），所以这里全用动态调用。

const BOSS := preload("res://scenes/enemies/NightmareBoss.tscn")
const FLAG := "nightmare_dead"


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


func _skulls(arena: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child in arena.get_children():
		if child is Node2D and String(child.name).begins_with("Nightmare_Skull_") \
				and not child.is_queued_for_deletion():
			out.append(child as Node2D)
	return out


func test_far_boss_stays_quiet_and_announces_once_when_the_knight_closes_in() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss = _spawn(arena, player.global_position + Vector2(600, 0))
	var heard: Array = []
	var on_appear := func(name_: String, cur: int, max_: int) -> void: heard.append([name_, cur, max_])
	GameEvents.boss_appeared.connect(on_appear)
	await flush(4)
	ok(not boss.is_announced(), "600px away it has not shown itself")
	eq(heard.size(), 0, "no boss bar yet")
	eq(boss.state(), boss.State.IDLE)
	eq(boss.health.max_hp, 16)
	eq(boss.charge_count(), 0)
	boss.global_position = player.global_position + Vector2(200, 0)
	await flush(2)
	ok(boss.is_announced(), "within 340px it announces")
	eq(heard.size(), 1, "boss_appeared fires exactly once")
	boss.announce()
	eq(heard.size(), 1, "announce() is idempotent")
	if heard.size() == 1:
		eq(heard[0][0], "锈 墓 梦 魇 · 无 主 之 马")
		eq(heard[0][1], 16)
		eq(heard[0][2], 16)
	ok(boss.state() != boss.State.IDLE, "it starts its charge cycle")
	GameEvents.boss_appeared.disconnect(on_appear)


func test_charge_carries_the_boss_past_the_knight_and_counts() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss = _spawn(arena, player.global_position + Vector2(220, 0))
	await flush(2)
	var start_x: float = boss.global_position.x
	eq(boss.charge_count(), 0, "no charge before the windup ends")
	var hp_reports: Array = []
	var on_hp := func(cur: int, _max: int) -> void: hp_reports.append(cur)
	GameEvents.boss_hp_changed.connect(on_hp)
	var charged: bool = await wait_until(
			func() -> bool: return boss.charge_count() >= 1 and boss.state() == boss.State.REST, 360)
	ok(charged, "windup, then a full gallop that ends in a breather")
	eq(boss.charge_count(), 1)
	var moved: float = absf(boss.global_position.x - start_x)
	ok(moved > 150.0, "the gallop carried it far (%.0f px)" % moved)
	ok(boss.global_position.x < player.global_position.x, "it overran the knight and stopped on the far side")
	ok(not boss.hitbox.monitoring, "ram damage is off while it breathes")
	boss.health.take_damage(1, player)
	eq(hp_reports, [15], "every lost point is reported to the boss bar")
	GameEvents.boss_hp_changed.disconnect(on_hp)


func test_enraged_boss_neighs_up_fire_skulls_capped_at_four() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss = _spawn(arena, player.global_position + Vector2(700, 0))
	await flush(2)
	ok(not boss.is_enraged())
	boss.health.take_damage(8, player)
	ok(boss.is_enraged(), "half HP lights the mane")
	eq(boss.health.current, 8)
	ok(boss.is_announced(), "a first strike from afar still raises the bar")
	ok(ResourceLoader.exists("res://scenes/enemies/FireSkullEnemy.tscn"))
	boss._begin_neigh()
	eq(boss.state(), boss.State.NEIGH)
	var skulls := _skulls(arena)
	eq(skulls.size(), 2, "a neigh drops two fire skulls")
	for s in skulls:
		ok(s.global_position.y < boss.global_position.y - 30.0, "skulls appear above the horse")
		ok(absf(s.global_position.x - boss.global_position.x) < 40.0, "skulls appear around the mane")
	boss._begin_neigh()
	eq(_skulls(arena).size(), 4, "a second neigh fills the cap")
	boss._begin_neigh()
	eq(_skulls(arena).size(), 4, "never more than four at once")


func test_killing_blow_emits_slain_and_marks_the_story_flag() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss = _spawn(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	var slain_count := [0]
	boss.slain.connect(func() -> void: slain_count[0] += 1)
	var defeated := [0]
	var on_defeated := func() -> void: defeated[0] += 1
	GameEvents.boss_defeated.connect(on_defeated)
	ok(not SaveData.has_flag(FLAG), "flag is clear before the fight")
	boss.health.take_damage(99, player)
	eq(slain_count[0], 1, "slain fired once")
	eq(defeated[0], 1, "boss_defeated fired once")
	ok(SaveData.has_flag(FLAG), "story flag recorded")
	ok(boss._dead)
	eq(boss.collision_layer, 0)
	ok(not boss.hitbox.monitoring, "a dead horse cannot ram")
	await flush(2)
	ok(not is_instance_valid(boss), "the horse is freed after its death burst")
	GameEvents.boss_defeated.disconnect(on_defeated)


func test_arena_edges_stop_charges_and_bound_summons() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss = _spawn(arena, Vector2(320, 0))
	boss.set_physics_process(false)
	boss.arena_left = 280.0
	boss.arena_right = 400.0
	boss._facing = -1.0
	boss._begin_charge()
	boss._tick_charge(null, 0.1)
	eq(boss.state(), boss.State.REST, "brakes before its body crosses the west edge")
	eq(boss.velocity.x, 0.0)
	boss._begin_neigh()
	for skull in _skulls(arena):
		eq(skull.get("arena_left"), 280.0)
		eq(skull.get("arena_right"), 400.0)
		skull.global_position.x = 500.0
		skull.call("_update_facing")
		ok(skull.global_position.x <= 388.0, "summon cannot pursue beyond the arena")
	boss.health.take_damage(99)
	await flush(2)
	eq(_skulls(arena).size(), 0, "killing the boss dismisses its summons")


func test_final_windup_locks_the_same_direction_as_the_charge() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	var boss = _spawn(arena, Vector2(600, 0))
	boss.set_physics_process(false)
	boss._facing = -1.0
	boss._enter_windup()
	boss._tick_state(0.3)
	player.global_position.x = 800.0
	boss._tick_state(0.1)
	eq(boss._facing, 1.0, "tracks early movement")
	boss._tick_state(0.11)
	ok(boss._direction_locked, "locks with 190ms left")
	player.global_position.x = 400.0
	boss._tick_state(0.1)
	eq(boss._facing, 1.0, "late crossing cannot reverse telegraph")
	boss._tick_state(0.1)
	eq(boss.state(), boss.State.CHARGE)
	eq(boss._dir, 1.0)
	boss._enter_rest()
	boss._pick_next_move(player)
	ok(not boss._direction_locked, "next attack reacquires the player")
	eq(boss._facing, -1.0)


# ---------------------------------------------------------------------------
# 三期重做（M3b）：三阶段阈值 / 余烬雨 / 地裂 + 热浪 / 竞技场收窄 / 演出数据
# ---------------------------------------------------------------------------
func _spawn_for_phases(arena: Node2D, pos: Vector2 = Vector2(320, 0)) -> Node2D:
	var boss := _spawn(arena, pos)
	boss.set_physics_process(false)
	boss.arena_left = 100.0
	boss.arena_right = 900.0
	return boss


func test_kit_has_three_phases_and_new_moves() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := _spawn_for_phases(arena, Vector2(400, 0))
	await flush(2)
	var kit: BossKit = boss.call("boss_kit")
	ok(kit != null, "梦魇 Kit 可读")
	if kit != null:
		eq(kit.validate().size(), 0, "Kit 自检通过")
		eq(kit.max_phases(), 3, "三期重做：三阶段")
		var ids: Array = []
		for entry in kit.attack_pool():
			ids.append(String(entry.id))
		for id in ["charge", "neigh", "ember_rain", "quake", "heat_wave"]:
			ok(ids.has(id), "攻击表包含 %s" % id)
		ok(kit.intro_steps().size() > 0, "入场演出步骤数据在 Kit 里")
		ok(kit.death_steps().size() > 0, "死亡演出步骤数据在 Kit 里")
		eq(kit.phase_for_hp(16, 16), 1, "满血一阶段")
		eq(kit.phase_for_hp(10, 16), 2, "10/16 二阶段（<= 2/3）")
		eq(kit.phase_for_hp(5, 16), 3, "5/16 三阶段（<= 1/3）")
	# 入场演出不锁输入（可跳过）：announce 只发事件与音效。
	boss.announce()
	ok(boss.is_announced(), "名号卡亮起")
	ok(not Director.is_input_locked(), "入场演出不锁输入（可随时跳过）")
	arena.queue_free()
	await flush(2)


func test_phase_two_ember_rain_and_heat() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn_for_phases(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	eq(int(boss.call("phase")), 1, "开局一阶段")
	eq(int(boss.call("heat_level")), 0, "开局热度 0")
	await get_tree().create_timer(0.55).timeout
	boss.health.take_damage(6, player)          # 16 -> 10 = 62.5%
	eq(int(boss.call("phase")), 2, "过 2/3 生命进入二阶段")
	ok(boss.is_enraged(), "二阶段狂暴")
	eq(int(boss.call("heat_level")), 1, "二阶段热度 1")
	ok(boss.health.invincible, "相变无敌演出")
	boss._tick_state(1.3)
	ok(not boss.health.invincible, "演出结束解除无敌")
	# 余烬雨：鬃毛火星落在骑士附近，先预警后判定。
	var spawned: int = boss.call("_spawn_ember_rain")
	eq(spawned, 1, "落下第一柱余烬")
	eq(int(boss.call("ember_rain_count")), 1, "余烬雨计数")
	var column := boss.get_node_or_null("EmberRain1") as Node2D
	ok(column != null, "余烬柱节点存在")
	if column != null:
		ok(float(column.get("warn")) >= 0.35, "余烬柱预警 >= 0.35s")
	await get_tree().create_timer(0.8).timeout
	ok(column == null or not is_instance_valid(column) or bool(column.get("_armed")),
			"预警结束后落下判定")
	boss._tick_state(0.1)
	arena.queue_free()
	await flush(2)


func test_phase_three_shrinks_arena_and_rotates_quake_heat_wave() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn_for_phases(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	await get_tree().create_timer(0.55).timeout
	boss.health.take_damage(6, player)          # 二阶段
	boss._tick_state(1.3)
	await get_tree().create_timer(0.55).timeout
	boss.health.take_damage(5, player)          # 10 -> 5 = 31% -> 三阶段
	eq(int(boss.call("phase")), 3, "过 1/3 生命进入三阶段")
	eq(int(boss.call("heat_level")), 2, "三阶段热度再上一档")
	boss._tick_state(1.3)
	# 竞技场边界向内收（两侧各 96px）。
	var bounds: Vector2 = boss.call("arena_bounds_now")
	almost(bounds.x, 196.0, 0.01, "三阶段左边界内收 96px")
	almost(bounds.y, 804.0, 0.01, "三阶段右边界内收 96px")
	# 三阶段轮转：先地裂、再热浪（先清掉嘶鸣计数，否则第一手仍是嘶鸣）。
	boss._since_neigh = 0
	boss._enter_rest()
	boss._pick_next_move(player)
	eq(boss.state(), boss.State.QUAKE, "三阶段轮转先出地裂")
	boss._tick_state(0.63)
	eq(int(boss.call("quake_count")), 1, "地裂计数")
	var quakes := 0
	for child in arena.get_children():
		if child is Hitbox:
			quakes += 1
	ok(quakes >= 3, "地裂沿地面生成三段判定（%d）" % quakes)
	boss._tick_state(0.35)
	boss._tick_state(0.6)                       # 回到 REST，再轮转
	boss._since_neigh = 0
	boss._enter_rest()
	boss._pick_next_move(player)
	eq(boss.state(), boss.State.HEAT_WAVE, "三阶段轮转第二手是热浪")
	boss._tick_state(0.56)
	eq(int(boss.call("heat_wave_count")), 1, "热浪计数")
	var effects := arena.find_child("WorldEffects", true, false)
	var wave_host: Node = effects if effects != null else arena
	var waves := 0
	for child in wave_host.get_children():
		if child is Projectile and (child as Projectile).source == boss:
			waves += 1
	ok(waves >= 2, "热浪左右各一道（可弹反，%d）" % waves)
	arena.queue_free()
	await flush(2)


func test_phase_three_cleanup_keeps_death_semantics() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var boss := _spawn_for_phases(arena, player.global_position + Vector2(200, 0))
	await flush(2)
	boss._spawn_ember_rain()
	ok(boss.get_node_or_null("EmberRain1") != null, "先放一柱余烬")
	boss.health.take_damage(99, player)
	ok(boss._dead, "死亡标记（原语义）")
	eq(boss.collision_layer, 0, "死亡后不挡路")
	await flush(3)
	ok(not is_instance_valid(boss), "死亡演出后释放（原语义）")
	ok(SaveData.has_flag(FLAG), "nightmare_dead 旗标保持不变")
	arena.queue_free()
	await flush(2)
