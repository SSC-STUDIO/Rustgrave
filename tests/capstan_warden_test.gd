extends TestCase
## 绞盘守渠人（level02b Boss）验收：攻击表可读性、驾驶出招、阶段/无敌、
## 泄压阀破防、场地机关、边界、清场与死亡旗标。

const SCENE := preload("res://scenes/enemies/CapstanWarden.tscn")
const KIT_SCRIPT := preload("res://scripts/enemies/boss_kit.gd")
const ARENA := preload("res://scripts/world/boss_arena.gd")
const FLAG := &"capstan_dead"


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director.resume()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director.resume()


func _spawn(arena: Node2D) -> CapstanWardenBoss:
	var boss := SCENE.instantiate() as CapstanWardenBoss
	boss.position = Vector2(320, 0)
	arena.add_child(boss)
	await flush(2)
	boss.set_physics_process(false)
	if boss.boss_director() != null:
		boss.boss_director().set_physics_process(false)
	return boss


func _request(boss: CapstanWardenBoss, id: StringName) -> void:
	# 驾驶层本来在物理帧里发 attack_requested；测试直接走同一条接缝。
	boss.set_physics_process(true)
	boss._on_attack_requested(id)
	boss.set_physics_process(false)


func _entry(kit: BossKit, id: String) -> Dictionary:
	for entry in kit.attack_pool():
		if String(entry.id) == id:
			return entry
	return {}


func _arena_host() -> Array:
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	var boss := SCENE.instantiate() as Node2D
	boss.position = Vector2(320, 0)
	host.add_child(boss)
	await flush(2)
	var arena = ARENA.attach(host, "CapstanWardenArena", boss, 120.0, 520.0, 0.0, false)
	boss.set_meta("boss_arena_name", "CapstanWardenArena")
	boss.call("_bind_arena")
	return [host, boss, arena]


# ---------------------------------------------------------------------------
# 攻击表 / 可读性
# ---------------------------------------------------------------------------
func test_kit_is_valid_readable_and_inside_the_arena() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	var kit := boss.boss_kit()
	ok(kit != null, "boss exposes a BossKit")
	eq(kit.validate(), [] as Array[String], "kit self-check passes")
	eq(kit.max_phases(), 2, "two phases")
	eq(kit.phase_thresholds(), [1.0, 0.5] as Array[float])
	var ids: Array = []
	for entry in kit.attack_pool():
		ids.append(String(entry.id))
		for phase in range(1, kit.max_phases() + 1):
			ok(kit.windup_for(entry, phase) >= KIT_SCRIPT.BOSS_TELEGRAPH_MIN,
					"%s windup >= 0.35s in phase %d" % [entry.id, phase])
		ok(BossKit.hitbox_reach(entry) <= 300.0,
				"%s hitbox reach stays inside the 600px arena" % entry.id)
	for required in ["chain_sweep", "steam_column", "sluice_flood", "summon_hounds"]:
		ok(ids.has(required), "attack table has %s" % required)
	arena.queue_free()
	await flush(2)


func test_drive_request_runs_windup_into_active_recovery() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	var heard: Array = []
	var on_tel := func(kind: StringName, duration: float) -> void: heard.append([kind, duration])
	boss.telegraph_started.connect(on_tel)
	var markers_before := CombatMarker.live
	_request(boss, &"chain_sweep")
	eq(boss.drive_phase(), 1, "attack starts in the windup phase")
	eq(heard.size(), 1, "exactly one telegraph is announced")
	ok(float(heard[0][1]) >= KIT_SCRIPT.BOSS_TELEGRAPH_MIN, "telegraph lasts >= 0.35s")
	eq(CombatMarker.live, markers_before + 1, "exactly one warning marker for the attack")
	boss._tick_state(0.4)
	eq(boss.drive_phase(), 1, "still winding up before the windup ends")
	boss._tick_state(0.2)
	eq(boss.drive_phase(), 2, "windup ends -> active")
	await flush(1)
	eq(CombatMarker.live, markers_before, "warning marker is dismissed when the attack lands")
	boss._tick_state(0.3)
	eq(boss.drive_phase(), 3, "active ends -> recovery")
	boss._tick_state(0.6)
	eq(boss.drive_phase(), 0, "recovery ends -> idle again")
	boss.telegraph_started.disconnect(on_tel)
	arena.queue_free()
	await flush(2)


func test_every_attack_has_one_warning_and_a_break_window_afterwards() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	var kit := boss.boss_kit()
	for entry in kit.attack_pool():
		var before := CombatMarker.live
		_request(boss, StringName(entry.id))
		ok(boss.drive_phase() != 0, "%s started" % entry.id)
		ok(CombatMarker.live <= before + 1, "%s spawns at most one warning" % entry.id)
		var guard := 0
		while boss.drive_phase() != 0 and guard < 200:
			boss._tick_state(0.05)
			guard += 1
		ok(boss.drive_phase() == 0, "%s finishes cleanly" % entry.id)
		await flush(1)  # queue_free 的预警标记在帧末离树，live 计数下一帧才回落
		ok(CombatMarker.live <= before, "%s leaves no warning behind" % entry.id)
	arena.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 阶段 / 破防
# ---------------------------------------------------------------------------
func test_half_hp_enters_phase_two_with_invulnerable_transition() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	var phases: Array = []
	var on_phase := func(next: int) -> void: phases.append(next)
	boss.boss_director().phase_entered.connect(on_phase)
	boss.health.take_damage(8, null)
	eq(phases, [2] as Array, "phase two is entered exactly once")
	eq(boss.phase(), 2, "boss tracks the phase")
	ok(boss.health.invincible, "phase transition is invulnerable")
	ok(boss.boss_director().is_frozen(), "director freezes during the transition")
	var hp := boss.health.current
	ok(not boss.health.take_damage(1, null), "no damage during the transition")
	eq(boss.health.current, hp)
	boss._tick_state(1.3)
	ok(not boss.health.invincible, "invulnerability ends after 1.2s")
	ok(not boss.boss_director().is_frozen(), "director resumes")
	boss.boss_director().phase_entered.disconnect(on_phase)
	arena.queue_free()
	await flush(2)


func test_relief_valve_is_the_break_window() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	ok(not boss.is_broken(), "boss starts unbroken")
	boss._open_valve()
	var valve: Node = boss.get_node_or_null("ReliefValve")
	ok(valve != null, "vent window opens a relief valve")
	if valve != null:
		var area := valve as Area2D
		eq(area.collision_layer, 32, "valve is hittable by the sword layer")
		eq(area.collision_mask, 8, "valve listens to player hitboxes")
		var hit := Hitbox.new()
		hit.team = &"player"
		arena.add_child(hit)
		hit.arm()  # 先入树再 arm：Hitbox._ready() 会把 monitoring 归 false
		valve.call("_on_area_entered", hit)
		ok(boss.is_broken(), "striking the valve breaks the warden")
		ok(boss.is_marked(), "break opens a riposte window (double damage)")
		hit.queue_free()
	boss._tick_state(1.7)
	ok(not boss.is_broken(), "break recovers after the window")
	ok(not boss.boss_director().is_frozen(), "director is released after the break")
	await flush(1)
	# 没开阀时不能破防：阀只在泄压窗口存在。
	ok(boss.get_node_or_null("ReliefValve") == null, "no valve outside the vent window")
	arena.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 场地机关 / 边界 / 清场
# ---------------------------------------------------------------------------
func test_arena_hazards_register_and_trigger() -> void:
	var built := await _arena_host()
	var host: Node2D = built[0]
	var boss: Node2D = built[1]
	var arena: BossArena = built[2]
	ok(arena != null, "arena attaches")
	var ids := arena.registered_hazard_ids()
	for required in [&"steam_burst", &"pressure_vent", &"vent_finale"]:
		ok(ids.has(required), "hazard %s is registered" % required)
		ok(arena.trigger_hazard(required), "hazard %s triggers" % required)
	host.queue_free()
	await flush(2)


func test_bounds_and_clamp_keep_the_fight_in_the_arena() -> void:
	var built := await _arena_host()
	var host: Node2D = built[0]
	var boss: Node2D = built[1]
	var arena: BossArena = built[2]
	# ChapterLayout.boss() 会用 overrides 写这两项；夹具 / 测试也要能读到兜底外的真值。
	boss.set("arena_left", 120.0)
	boss.set("arena_right", 520.0)
	eq(boss.call("boss_arena_bounds"), Vector2(120.0, 520.0),
			"boss reports the arena bounds to fixtures")
	arena.activate()
	boss.global_position.x = 900.0
	arena.clamp_actor(boss, 20.0)
	ok(is_equal_approx(boss.global_position.x, 500.0), "boss is clamped inside the arena")
	host.queue_free()
	await flush(2)


func test_death_emits_slain_sets_flag_and_clears_arena() -> void:
	var built := await _arena_host()
	var host: Node2D = built[0]
	var boss: Node2D = built[1]
	var arena: BossArena = built[2]
	arena.activate()
	var slain: Array = []
	boss.connect("slain", func() -> void: slain.append(true))
	var died: Array = []
	boss.boss_director().died.connect(func() -> void: died.append(true))
	boss.call("announce")
	eq(boss.call("is_announced"), true)
	eq(boss.boss_director().running, true, "driving fight starts on announce")
	(boss.get_node("Health") as Health).take_damage(99, null)
	await flush(2)
	eq(slain.size(), 1, "slain fires once for the arena")
	eq(died.size(), 1, "the framework director is notified once")
	ok(SaveData.has_flag(FLAG), "death flag capstan_dead is written")
	ok(arena.is_cleared(), "clearing the boss unlocks the arena")
	ok(not is_instance_valid(boss), "boss body is released")
	host.queue_free()
	await flush(2)


func test_death_flag_survives_a_save_round_trip() -> void:
	SaveData.delete_save()
	var built := await _arena_host()
	var host: Node2D = built[0]
	var boss: Node2D = built[1]
	var player := await spawn_player(host)
	ok(SaveData.save_game(GameContext.LEVELS["level02b"], player), "chapter save exists")
	boss.call("announce")
	(boss.get_node("Health") as Health).take_damage(99, null)
	await flush(2)
	ok(SaveData.has_flag(FLAG), "flag set on death")
	SaveData.persist_story()
	SaveData.flags.clear()
	ok(SaveData.load_game(), "save round-trip loads")
	ok(SaveData.has_flag(FLAG), "death flag persists across a reload")
	host.queue_free()
	await flush(2)
