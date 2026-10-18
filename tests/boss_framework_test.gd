extends TestCase
## Boss 框架（M3 task-8）验收：攻击表可读性、调度不重复、阶段阈值、竞技场 clamp、
## 暂停冻结、机关注册、存档点校验、ChapterLayout.boss 装配、夹具 smoke。
##
## 框架脚本用 preload 常量引用（不依赖编辑器全局类缓存，headless CI 也不会因缓存
## 更新时序而挂）。

const BOSS_KIT := preload("res://scripts/enemies/boss_kit.gd")
const BOSS_DIRECTOR := preload("res://scripts/enemies/boss_director.gd")
const BOSS_ARENA := preload("res://scripts/world/boss_arena.gd")
const CHAPTER_LAYOUT := preload("res://scripts/levels/chapter_layout.gd")
const EXECUTIONER := preload("res://scenes/enemies/ExecutionerBoss.tscn")
const NIGHTMARE := preload("res://scenes/enemies/NightmareBoss.tscn")
const EMBER_NEST := preload("res://scenes/interactables/EmberNest.tscn")

const FLOOR_FEET_Y := 0.0


# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------
func _make_kit(config: Dictionary) -> BossKit:
	return BOSS_KIT.new(config) as BossKit


## 三层阶段用的合成 Kit：一阶段两招、二阶段一招 + 狂暴限定、三阶段一招。
func _synthetic_kit() -> BossKit:
	return _make_kit({
		"id": &"test_boss",
		"title": "合成首领",
		"subtitle": "验收用",
		"max_phases": 3,
		"phase_thresholds": [1.0, 0.66, 0.33],
		"min_interval": 0.5,
		"enrage_after": 30.0,
		"attacks": [
			{"id": &"jab", "phase": 1, "weight": 1.0, "cooldown": 1.0,
				"windup": 0.4, "active": 0.1, "recovery": 0.3,
				"hitbox": {"offset": Vector2(24.0, -12.0), "size": Vector2(32.0, 24.0)}},
			{"id": &"sweep", "phase": 1, "weight": 1.0, "cooldown": 1.4,
				"windup": 0.5, "active": 0.12, "recovery": 0.4},
			{"id": &"beam", "phase": 2, "weight": 2.0, "cooldown": 1.2,
				"windup": 0.6, "active": 0.1, "recovery": 0.4},
			{"id": &"frenzy", "phase": 2, "weight": 3.0, "cooldown": 0.8,
				"windup": 0.45, "active": 0.1, "recovery": 0.2, "enrage_only": true},
			{"id": &"finale", "phase": 3, "weight": 1.0, "cooldown": 1.0,
				"windup": 0.55, "active": 0.1, "recovery": 0.4},
		],
		"arena_events": [
			{"id": &"surge", "at_phase": 1, "once": true},
			{"id": &"heat", "at_phase": 2, "once": true},
			{"id": &"more_heat", "at_phase": 2, "once": true},
			{"id": &"dim", "at_phase": 0, "once": true},
		],
	})


## 纯节点 Boss 宿主：导演层只调度 / 观测，不需要真敌人。
func _make_director_host(kit: BossKit, auto_drive: bool = true) -> Array:
	var boss := Node2D.new()
	boss.name = "SyntheticBoss"
	boss.position = Vector2(320, FLOOR_FEET_Y)
	add_child(boss)
	var director := BOSS_DIRECTOR.attach(boss, kit, auto_drive)
	director.set_physics_process(false)  # 测试手动 tick，避免物理帧偷跑
	return [boss, director]


func _spawn_executioner(arena: Node2D, at: Vector2 = Vector2(320, -20)) -> ExecutionerBoss:
	var boss := EXECUTIONER.instantiate() as ExecutionerBoss
	boss.position = at
	arena.add_child(boss)
	await flush(2)
	return boss


func _spawn_nightmare(arena: Node2D, at: Vector2 = Vector2(320, 0)) -> Node2D:
	var boss := NIGHTMARE.instantiate() as Node2D
	boss.position = at
	arena.add_child(boss)
	await flush(2)
	return boss


func _script_const(node: Node, const_name: String) -> Variant:
	var script := node.get_script() as Script
	if script == null:
		return null
	return script.get_script_constant_map().get(const_name, null)


func _pool_entry(kit: BossKit, id: String) -> Dictionary:
	for entry in kit.attack_pool():
		if String(entry.id) == id:
			return entry
	return {}


class FakeGate extends Node:
	var locked := false

	func lock() -> void:
		locked = true

	func unlock() -> void:
		locked = false


# ---------------------------------------------------------------------------
# 1. 框架脚本 / 默认实现
# ---------------------------------------------------------------------------
func test_framework_scripts_load_with_class_names() -> void:
	ok(BossKit != null, "BossKit 全局类可用")
	ok(BossDirector != null, "BossDirector 全局类可用")
	var director_probe = BOSS_DIRECTOR.new()
	ok(director_probe is BossDirector, "导演层节点可以 new")
	director_probe.free()
	var arena_probe = BOSS_ARENA.new()
	eq(arena_probe.name, "", "竞技场节点可以 new")
	arena_probe.free()
	var layout_probe = CHAPTER_LAYOUT.new()
	ok(layout_probe.has_method("boss"), "ChapterLayout 暴露 boss() 装配口")
	layout_probe.free()


func test_default_kit_is_safe_and_valid() -> void:
	var kit := _make_kit({})
	eq(kit.boss_title(), "首领", "默认 Kit 有名号（不会空标题）")
	eq(kit.max_phases(), 2, "默认二阶段")
	eq(kit.attack_table().size(), 0, "默认空攻击表")
	eq(kit.arena_events().size(), 0, "默认无场地事件")
	eq(kit.validate().size(), 0, "默认 Kit 自检通过（空表也安全）")
	eq(kit.phase_for_hp(100, 100), 1, "满血一阶段")
	eq(kit.phase_for_hp(50, 100), 2, "半血二阶段")
	eq(kit.phase_for_hp(0, 100), 2,
			"0 HP 只按阈值算阶段（死亡由 BossDirector.notify_death 单独处理）")
	eq(kit.windup_for({"id": &"x"}, 1), BossKit.BOSS_TELEGRAPH_MIN,
			"缺省前摇 = 可读性硬下限 0.35")
	eq(BossKit.BOSS_TELEGRAPH_MIN, 0.35, "契约 §4.1：Boss 预警 >= 0.35s")


func test_attack_table_rejects_unreadable_or_illegal_moves() -> void:
	var bad := BossKit.validate_attack_table([
		{"id": &"quick", "windup": 0.2},
		{"id": &"neg", "windup": 0.5, "cooldown": -1.0},
		{"id": &"zero_weight", "windup": 0.5, "weight": 0.0},
		{"id": &"phase_out", "windup": 0.5, "phase": 9},
		{"id": &"dup", "windup": 0.5},
		{"id": &"dup", "windup": 0.5},
	])
	ok(bad.size() >= 5, "校验能抓出前摇不足 / 负冷却 / 权重 0 / 阶段越界 / 重复 id（%d 条）" % bad.size())
	var good := BossKit.validate_attack_table([
		{"id": &"a", "windup": 0.35},
		{"id": &"b", "windup": 0.35, "windup_by_phase": [0.35, 0.4]},
	], 0.35, 2)
	eq(good.size(), 0, "前摇 0.35s（含分阶段覆盖）恰好合法")


# ---------------------------------------------------------------------------
# 2. 现有两场 Boss 的 Kit（结构迁移：可读性 / 判定不出场地 / 阶段阈值）
# ---------------------------------------------------------------------------
func test_migrated_boss_kits_describe_existing_moves() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)

	var executioner := await _spawn_executioner(arena)
	var exec_kit := executioner.boss_kit()
	eq(exec_kit.validate().size(), 0, "刽子手 Kit 自检通过")
	eq(exec_kit.max_phases(), 2, "刽子手二阶段")
	eq(exec_kit.phase_for_hp(7, 13), 1, "7/13 仍是一阶段")
	eq(exec_kit.phase_for_hp(6, 13), 2, "<= 半血进入二阶段（和 _on_hp_changed 一致）")
	eq(exec_kit.boss_title(), ExecutionerBoss.BOSS_TITLE, "Kit 名号和现有台词同源")
	var exec_pool := exec_kit.attack_pool()
	var exec_ids: Array = []
	for entry in exec_pool:
		exec_ids.append(String(entry.id))
		for phase in range(1, exec_kit.max_phases() + 1):
			ok(exec_kit.windup_for(entry, phase) >= BossKit.BOSS_TELEGRAPH_MIN,
					"刽子手 %s 前摇 >= 0.35s（阶段 %d）" % [entry.id, phase])
		ok(BossKit.hitbox_reach(entry) <= 200.0,
				"刽子手 %s 的判定触达不超过本场竞技场半宽" % entry.id)
	ok(exec_ids.has("slash") and exec_ids.has("bolt"), "斩 + 射都在攻击表里")
	var slash: Dictionary = _pool_entry(exec_kit, "slash")
	almost(float(slash.windup), ExecutionerBoss.SLASH_WINDUP, 0.0001,
			"斩前摇 = 现有 SLASH_WINDUP（0.52s）")
	var slash_box := BossKit.hitbox_rect(slash)
	eq(slash_box.size, ExecutionerBoss.SLASH_ZONE_SIZE, "判定盒 = 现有落点框尺寸")
	almost(slash_box.position.x,
			ExecutionerBoss.SLASH_ZONE_OFFSET.x - ExecutionerBoss.SLASH_ZONE_SIZE.x * 0.5,
			0.01, "落点框和现有偏移同源")
	almost(slash_box.end.y, -4.0, 0.01, "斧落点仍贴地（底边 -4）")

	var nightmare := await _spawn_nightmare(arena, Vector2(520, 0))
	var nm_kit := nightmare.call("boss_kit") as BossKit
	eq(nm_kit.validate().size(), 0, "梦魇 Kit 自检通过")
	eq(nm_kit.max_phases(), 3, "梦魇三期重做：三阶段")
	var nm_phases := nm_kit.phase_thresholds()
	eq(nm_phases.size(), 3, "梦魇三阶段阈值")
	if nm_phases.size() == 3:
		almost(float(nm_phases[0]), 1.0, 0.0001, "阶段阈值从 1.0 开始")
		almost(float(nm_phases[1]), 2.0 / 3.0, 0.0001, "2/3 生命进二阶段")
		almost(float(nm_phases[2]), 1.0 / 3.0, 0.0001, "1/3 生命进三阶段")
		eq(nm_kit.phase_for_hp(16, 16), 1, "满血一阶段")
		eq(nm_kit.phase_for_hp(10, 16), 2, "10/16 二阶段")
		eq(nm_kit.phase_for_hp(5, 16), 3, "5/16 三阶段")
	var nm_title: Variant = _script_const(nightmare, "BOSS_TITLE")
	if nm_title is String:
		eq(nm_kit.boss_title(), String(nm_title), "梦魇 Kit 名号和现有台词同源")
	var charge: Dictionary = _pool_entry(nm_kit, "charge")
	ok(not charge.is_empty(), "冲锋在攻击表里")
	if not charge.is_empty():
		almost(nm_kit.windup_for(charge, 1), 0.7, 0.0001, "一阶段蓄势 0.7s")
		almost(nm_kit.windup_for(charge, 2), CombatRules.NIGHTMARE_P2_WINDUP, 0.0001,
				"二阶段蓄势 0.58s（windup_by_phase）")
		ok(nm_kit.windup_for(charge, 2) >= BossKit.BOSS_TELEGRAPH_MIN,
				"收紧后的蓄势仍 >= 0.35s")
		ok(nm_kit.windup_for(charge, 3) >= BossKit.BOSS_TELEGRAPH_MIN,
				"三阶段蓄势仍 >= 0.35s")
	# 三期新增招式进表：余烬雨 / 地裂 / 热浪，且三阶段池子能选到它们。
	var nm_ids: Array = []
	for entry in nm_kit.attack_pool():
		nm_ids.append(String(entry.id))
	for id in ["ember_rain", "quake", "heat_wave"]:
		ok(nm_ids.has(id), "梦魇三期招式 %s 在攻击表里" % id)
	arena.queue_free()
	await flush(2)


func test_migrated_bosses_report_attacks_and_phases_to_the_director() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var executioner := await _spawn_executioner(arena)
	var director := executioner.boss_director()
	ok(director != null, "刽子手挂了导演层（协助模式）")
	if director != null:
		eq(director.phase, 1)
		eq(director.attack_count, 0)
		executioner._set_blocking(false)
		executioner._begin_slash()
		eq(director.attack_count, 1, "斩起手同步给导演层")
		eq(String(director.last_attack_id), "slash")
	executioner.health.take_damage(7, null)
	ok(executioner.is_enraged())
	if director != null:
		eq(director.phase, 2, "半血相变同步给导演层")
		var deaths := [0]
		director.died.connect(func() -> void: deaths[0] += 1)
		director.notify_death()
		director.notify_death()
		eq(deaths[0], 1, "死亡通知只发一次（幂等）")
		ok(not director.running, "死亡后停表")
	arena.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 3. 调度：串行 / 冷却 / 最短间隔 / 禁止连续重复 / 阶段过滤 / 狂暴
# ---------------------------------------------------------------------------
func test_director_serializes_attacks_without_repeats() -> void:
	var kit := _synthetic_kit()
	var built := _make_director_host(kit, true)
	var boss: Node2D = built[0]
	var director: BossDirector = built[1]
	var starts: Array = []
	var director_ref := director
	var on_selected := func(entry: Dictionary) -> void:
		starts.append({
			"clock": director_ref.clock,
			"id": String(entry.id),
		})
	director.attack_selected.connect(on_selected)
	var enrage_hits := [0]
	director.enrage_started.connect(func() -> void: enrage_hits[0] += 1)
	director.start()
	director.set_physics_process(false)
	for i in 240:
		director.tick(0.1)
	ok(starts.size() >= 4, "跑出一串攻击（%d）" % starts.size())
	# 串行出招 = 同一时刻最多一条预警；每次出手时上一招已收。
	var overlapping := 0
	for i in range(1, starts.size()):
		var gap := float((starts[i] as Dictionary).clock) - float((starts[i - 1] as Dictionary).clock)
		if gap <= 0.0001:
			overlapping += 1
	eq(overlapping, 0, "同一时刻最多一条预警：出招严格串行（相邻起手不同刻）")
	var consecutive := 0
	var per_id_last: Dictionary = {}
	var cooldown_violations := 0
	var min_gap_violations := 0
	for i in range(starts.size()):
		var row: Dictionary = starts[i]
		if i > 0:
			var previous: Dictionary = starts[i - 1]
			if String(previous.id) == String(row.id):
				consecutive += 1
			if float(row.clock) - float(previous.clock) + 0.0001 < kit.min_interval():
				min_gap_violations += 1
		var id := String(row.id)
		if per_id_last.has(id):
			var entry := _pool_entry(kit, id)
			if float(row.clock) - float(per_id_last[id]) + 0.0001 < kit.cooldown_for(entry, 1):
				cooldown_violations += 1
		per_id_last[id] = float(row.clock)
	eq(consecutive, 0, "禁止连续重复：相邻两次出手不是同一招")
	eq(cooldown_violations, 0, "同一招两次起手间隔 >= 冷却")
	eq(min_gap_violations, 0, "任意两招起手间隔 >= 最短间隔")
	var phase_locked := 0
	for row in starts:
		if String(row.id) in ["beam", "frenzy", "finale"]:
			phase_locked += 1
	eq(phase_locked, 0, "一阶段不会出二 / 三阶段的招")
	# 进二阶段：二阶段招式进池；三阶段招式仍锁着。
	var phase_change_at := starts.size()
	director.set_hp(60, 100)
	eq(director.phase, 2, "60% 生命进入二阶段（阈值 0.66）")
	for i in 80:
		director.tick(0.1)
	var phase_two_seen := false
	var phase_three_bad := 0
	for i in range(phase_change_at, starts.size()):
		var id := String((starts[i] as Dictionary).id)
		if id == "beam":
			phase_two_seen = true
		if id == "finale":
			phase_three_bad += 1
	ok(phase_two_seen, "二阶段招式会被调度到")
	eq(phase_three_bad, 0, "二阶段不会出三阶段的招")
	# 狂暴计时：30s 到点后 enrage_only 招式才解锁。
	for i in 60:
		director.tick(0.1)
	eq(enrage_hits[0], 1, "狂暴计时恰好触发一次")
	ok(director.enraged, "狂暴状态可读")
	# 关掉自动出招，把占用 / 冷却 / 最短间隔都走完，再问调度器：frenzy 现在可选。
	director.auto_drive = false
	director.notify_attack_finished()
	director.last_attack_id = &""
	for i in 20:
		director.tick(0.1)
	ok(director.can_use(&"frenzy"), "狂暴后 enrage_only 招式解锁")
	director.set_hp(30, 100)
	eq(director.phase, 3, "30% 生命进入三阶段（阈值 0.33）")
	ok(director.schedule_snapshot().has("attacks"), "调度快照可供夹具 report.json 使用")
	director.attack_selected.disconnect(on_selected)
	boss.queue_free()
	await flush(2)


func test_director_phase_thresholds_and_arena_events_fire_once() -> void:
	var kit := _synthetic_kit()
	var built := _make_director_host(kit, false)
	var boss: Node2D = built[0]
	var director: BossDirector = built[1]
	var phases: Array = []
	var events: Array = []
	var deaths := [0]
	director.phase_entered.connect(func(phase: int) -> void: phases.append(phase))
	director.arena_event.connect(func(id: StringName, _data: Dictionary) -> void: events.append(String(id)))
	director.died.connect(func() -> void: deaths[0] += 1)
	director.start()
	eq(events, ["surge"], "开战场地事件只发一次（once）")
	director.set_hp(60, 100)
	eq(phases, [2], "跨过 66% 进二阶段")
	eq(events, ["surge", "heat", "more_heat"], "同一阶段的多条场地事件都按 at_phase 发出")
	director.set_hp(55, 100)
	eq(phases, [2], "同阶段内掉血不重复触发阶段事件")
	director.set_hp(30, 100)
	eq(phases, [2, 3], "跨过 33% 进三阶段")
	director.notify_death()
	eq(deaths[0], 1, "死亡发一次")
	eq(events[events.size() - 1], "dim", "死亡场地事件（at_phase 0）")
	director.notify_death()
	eq(deaths[0], 1, "死亡通知幂等")
	ok(not director.running, "死亡后停表")
	boss.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 4. 暂停冻结 / 恢复
# ---------------------------------------------------------------------------
func test_director_freezes_while_paused_and_resumes() -> void:
	var kit := _synthetic_kit()
	var built := _make_director_host(kit, true)
	var boss: Node2D = built[0]
	var director: BossDirector = built[1]
	director.start()
	director.set_physics_process(false)
	for i in 20:
		director.tick(0.1)
	var clock_before := director.clock
	var count_before := director.attack_count
	ok(clock_before > 1.5, "战斗时钟在走（%.2f）" % clock_before)
	director.freeze()
	ok(director.is_frozen())
	for i in 50:
		director.tick(0.1)
	eq(director.clock, clock_before, "冻结时时钟完全不走")
	eq(director.attack_count, count_before, "冻结时不会出招")
	director.resume()
	ok(not director.is_frozen())
	director.tick(0.5)
	ok(director.clock > clock_before, "恢复后时钟继续走")
	# 树暂停也冻结：PAUSABLE 节点在暂停的树里不跑物理帧，手动 tick 同样拒绝推进。
	var clock_paused := director.clock
	get_tree().paused = true
	for i in 20:
		director.tick(0.1)
	eq(director.clock, clock_paused, "树暂停时手动 tick 也不推进")
	get_tree().paused = false
	director.tick(0.2)
	ok(director.clock > clock_paused, "取消暂停后恢复推进")
	boss.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 5. 竞技场：clamp / 锁门 / 相机 / 机关 / 存档点 / 战后解锁
# ---------------------------------------------------------------------------
func _make_arena_host(left: float = 200.0, right: float = 600.0) -> Array:
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	var arena := BOSS_ARENA.new() as BossArena
	arena.name = "TestArena"
	arena.arena_left = left
	arena.arena_right = right
	arena.arena_top = -320.0
	arena.arena_bottom = 400.0
	arena.floor_y = 0.0
	arena.start_immediately = false
	arena.start_on_intro = false
	host.add_child(arena)
	return [host, arena]


func test_arena_clamps_boss_and_player_then_unlocks_after_the_kill() -> void:
	var built := _make_arena_host(200.0, 600.0)
	var host: Node2D = built[0]
	var arena: BossArena = built[1]
	var gate := FakeGate.new()
	arena.register_gate(gate)
	var boss := await _spawn_executioner(arena, Vector2(320, -20))
	arena.bind_boss(boss)
	var player := Node2D.new()
	player.name = "FakeKnight"
	player.add_to_group("player")
	arena.add_child(player)
	player.global_position = Vector2(900, 0)
	arena.activate()
	ok(arena.is_active(), "开战激活竞技场")
	ok(gate.locked, "开战锁门")
	ok(arena.gate_locked)
	boss.global_position = Vector2(100, -20)
	await flush(3)
	ok(boss.global_position.x >= 200.0, "Boss 被夹在场地左边界内（%.1f）" % boss.global_position.x)
	ok(player.global_position.x <= 600.0, "骑士被夹在场地右边界内（%.1f）" % player.global_position.x)
	player.global_position = Vector2(-50, 0)
	await flush(3)
	ok(player.global_position.x >= 200.0, "骑士被夹在场地左边界内（%.1f）" % player.global_position.x)
	# 击杀：slain -> clear_arena（门开、边界放开）。
	boss.health.take_damage(99, null)
	await flush(3)
	ok(arena.is_cleared(), "Boss 倒地后清场")
	ok(not gate.locked, "清场解锁门")
	ok(not arena.is_active(), "清场后不再 clamp")
	player.global_position = Vector2(900, 0)
	await flush(2)
	ok(player.global_position.x > 600.0, "战斗结束后骑士可以走出竞技场")
	host.queue_free()
	await flush(2)


func test_arena_syncs_camera_limits_and_restores_them() -> void:
	var built := _make_arena_host(200.0, 600.0)
	var host: Node2D = built[0]
	var arena: BossArena = built[1]
	var camera := GameCamera.new()
	host.add_child(camera)
	await flush(1)
	eq(camera.limit_left, 0)
	eq(camera.limit_right, 1600)
	arena.activate()
	eq(camera.limit_left, 200, "开战把相机左 limit 同步到竞技场")
	eq(camera.limit_right, 600, "开战把相机右 limit 同步到竞技场")
	ok(arena.has_saved_camera_limits)
	arena.clear_arena()
	eq(camera.limit_left, 0, "清场还原相机左 limit")
	eq(camera.limit_right, 1600, "清场还原相机右 limit")
	ok(not arena.has_saved_camera_limits)
	host.queue_free()
	await flush(2)


func test_arena_hazard_interface_keeps_hitboxes_inside_the_floorplan() -> void:
	var built := _make_arena_host(200.0, 600.0)
	var host: Node2D = built[0]
	var arena: BossArena = built[1]
	arena.activate()
	var fire = arena.make_hazard(BossArena.HazardKind.FIRE_PILLAR, Vector2(900, -40),
			{"telegraph": 0.4, "size": Vector2(32, 64)})
	ok(fire != null, "火柱机关可以生成")
	var fire_offset: Vector2 = fire.get("hitbox_offset")
	var fire_size: Vector2 = fire.get("hitbox_size")
	var rect := Rect2(fire.global_position + fire_offset - fire_size * 0.5, fire_size)
	ok(rect.position.x >= 200.0 - 0.01 and rect.end.x <= 600.0 + 0.01,
			"机关被 clamp 进场内：判定框 %s 不出 [200,600]" % [rect])
	var marker_count := 0
	for child in fire.get_children():
		if child is CombatMarker:
			marker_count += 1
			ok((child as CombatMarker).lifetime >= BossKit.BOSS_TELEGRAPH_MIN,
					"机关预警 >= 0.35s（%.2f）" % (child as CombatMarker).lifetime)
	eq(marker_count, 1, "机关只画一条预警")
	# 注册表 / 触发接口：Callable 与内置机关都行。
	var custom_hits := [0]
	arena.register_hazard(&"custom", func(_data: Dictionary) -> void: custom_hits[0] += 1)
	ok(arena.trigger_hazard(&"custom"), "自定义机关可以触发")
	eq(custom_hits[0], 1)
	ok(not arena.trigger_hazard(&"missing"), "未注册的机关返回 false")
	arena.register_hazard(&"fire", fire)
	ok(arena.trigger_hazard(&"fire"), "内置火柱可以触发")
	# 等预警走完：判定盒出现、并且仍在场地内。SceneTreeTimer 是真实时间，
	# headless 下物理帧可能远快于墙钟，所以按 50ms 轮询而不是数物理帧。
	var armed := false
	for i in 30:
		await get_tree().create_timer(0.05).timeout
		for child in fire.get_children():
			if child is Hitbox:
				armed = true
				var box := child as Hitbox
				ok(box.monitoring, "预警结束后判定打开")
				var box_rect := Rect2(box.global_position - fire_size * 0.5, fire_size)
				ok(box_rect.position.x >= 200.0 - 0.01 and box_rect.end.x <= 600.0 + 0.01,
						"火柱 hitbox 不出场地")
		if armed:
			break
	ok(armed, "火柱在预警后真的出判定")
	# 落石 / 水流占位接口同样可造。
	var rock = arena.make_hazard(BossArena.HazardKind.ROCKFALL, Vector2(300, -60))
	ok(rock != null, "落石机关可以生成")
	var water = arena.make_hazard(BossArena.HazardKind.WATER_FLOW, Vector2(400, -40))
	ok(water != null, "水流机关可以生成")
	host.queue_free()
	await flush(2)


func test_arena_checkpoint_report_finds_the_nest_before_the_gate() -> void:
	var built := _make_arena_host(200.0, 600.0)
	var host: Node2D = built[0]
	var arena: BossArena = built[1]
	var nest := EMBER_NEST.instantiate() as Node2D
	nest.name = "EmberNestNear"
	nest.position = Vector2(160, -14)
	host.add_child(nest)
	await flush(2)
	eq(arena.nearest_nest(), nest, "找得到竞技场外最近的余烬巢")
	var report := arena.checkpoint_report()
	ok(report.ok, "存档点在 80px 内：%s" % [report])
	ok(float(report.distance) <= 80.0, "距离 %.1f <= 80" % float(report.distance))
	ok(arena.validate_checkpoint(), "校验通过")
	nest.position = Vector2(-400, -14)
	await flush(1)
	ok(not arena.checkpoint_report().ok, "巢被挪远后校验失败（不会静默放行）")
	host.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 6. ChapterLayout.boss() 统一装配 + 新 Boss 占位登记
# ---------------------------------------------------------------------------
func test_chapter_layout_boss_builds_arena_and_registers_placeholders() -> void:
	var layout = CHAPTER_LAYOUT.new()
	add_child(layout)
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	for folder in ["Platforms", "Hooks", "Pickups", "Props", "Enemies"]:
		var node := Node2D.new()
		node.name = folder
		host.add_child(node)
	var boss := layout.boss(host, "TestExecutioner", "executioner", Vector2(320, -20), 120.0, 520.0)
	ok(boss != null, "ChapterLayout.boss 生成 Boss")
	if boss != null:
		eq(boss.arena_left, 120.0, "Boss 自己也拿到竞技场左边界")
		eq(boss.arena_right, 520.0)
	var arena := layout.boss_arena(host, "TestExecutioner")
	ok(arena != null, "竞技场挂在 host/Arenas/<name>Arena")
	if arena != null:
		eq(arena.arena_left, 120.0)
		eq(arena.arena_right, 520.0)
		eq(arena.boss, boss, "竞技场绑定 Boss")
	if boss != null:
		eq(String(boss.get_meta("boss_arena_name", "")), "TestExecutionerArena",
				"Boss 上登记了竞技场名（供剧情 / 测试反查）")
	# 新 Boss 场景名先登记占位：阶段 agent 可以提前写布局，场景缺失也不报错。
	for kind in ["capstan_warden", "silent_choir", "hollow_bell", "bell_founder", "emberwind_herald"]:
		ok(ChapterLayout.ENEMY_SCENES.has(kind), "%s 已登记占位" % kind)
		var path := String(ChapterLayout.ENEMY_SCENES[kind])
		ok(path.begins_with("res://scenes/enemies/") and path.ends_with(".tscn"))
	# 新 Boss 场景现已交付，缺场景守卫用一个真正不存在的 kind 验证。
	eq(layout.enemy(host, "Placeholder", "definitely_missing_boss", Vector2.ZERO), null,
			"缺场景的 Boss kind 会安全跳过（不炸布局）")
	eq(layout.boss(host, "PlaceholderBoss", "definitely_missing_boss", Vector2.ZERO, 0.0, 100.0), null,
			"缺场景时 boss() 也安全返回 null")
	host.queue_free()
	layout.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 7. 夹具 smoke
# ---------------------------------------------------------------------------
func test_boss_fixture_plan_covers_intro_phases_and_death() -> void:
	ok(ResourceLoader.exists("res://tools/boss_fixture.gd"), "通用夹具脚本存在")
	ok(ResourceLoader.exists("res://scenes/tools/BossFixture.tscn"), "通用夹具场景存在")
	var fixture_script := load("res://tools/boss_fixture.gd") as GDScript
	ok(fixture_script != null, "夹具脚本可加载")
	if fixture_script == null:
		return
	var plan_two: Array = fixture_script.call("stage_plan", 2)
	var plan_three: Array = fixture_script.call("stage_plan", 3)
	eq(String((plan_two[0] as Dictionary).get("id", "")), "intro", "二阶段夹具从入场开始")
	eq(String((plan_two[plan_two.size() - 1] as Dictionary).get("id", "")), "death", "二阶段夹具以死亡收尾")
	eq(plan_two.size(), 4, "二阶段 = 入场 + 一阶段 + 二阶段 + 死亡")
	eq(plan_three.size(), 5, "三阶段 = 入场 + 3 阶段 + 死亡")
	for row in plan_three:
		ok(String((row as Dictionary).get("id", "")) != "", "每个拍摄点都有 id")
		ok(String((row as Dictionary).get("screen", "")) != "", "每个拍摄点都有文件名")
	var report: Dictionary = fixture_script.call("empty_report", "level01", "TestBoss")
	ok(report.has("stages") and report.has("captures"), "report.json 骨架含 stages/captures")
	eq(String(report.get("level_id", "")), "level01")
	var scene := load("res://scenes/tools/BossFixture.tscn") as PackedScene
	ok(scene != null, "夹具场景可加载")
	if scene != null:
		var instance := scene.instantiate()
		ok(instance.get_script() == fixture_script, "夹具场景挂的是通用夹具脚本")
		instance.free()
