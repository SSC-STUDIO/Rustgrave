extends TestCase
## 无声唱诗班（level04b Boss）验收：攻击表可读性、3 壳 + 1 指挥结构、驾驶出招、
## 静默区「听不见」、二阶段合声光束可弹反破防、阶段/清场/死亡旗标。

const SCENE := preload("res://scenes/enemies/SilentChoir.tscn")
const KIT_SCRIPT := preload("res://scripts/enemies/boss_kit.gd")
const ARENA := preload("res://scripts/world/boss_arena.gd")
const FLAG := &"choir_dead"


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


func _spawn(arena: Node2D, player: Player = null) -> SilentChoirBoss:
	var boss := SCENE.instantiate() as SilentChoirBoss
	boss.position = Vector2(320, 0)
	arena.add_child(boss)
	await flush(2)
	boss.set_physics_process(false)
	if boss.boss_director() != null:
		boss.boss_director().set_physics_process(false)
	return boss


func _request(boss: SilentChoirBoss, id: StringName) -> void:
	boss.set_physics_process(true)
	boss._on_attack_requested(id)
	boss.set_physics_process(false)


func _arena_host() -> Array:
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	var boss := SCENE.instantiate() as Node2D
	boss.position = Vector2(320, 0)
	host.add_child(boss)
	await flush(2)
	var arena = ARENA.attach(host, "SilentChoirArena", boss, 120.0, 520.0, 0.0, false)
	boss.set_meta("boss_arena_name", "SilentChoirArena")
	boss.call("_bind_arena")
	return [host, boss, arena]


# ---------------------------------------------------------------------------
# 攻击表 / 结构 / 可读性
# ---------------------------------------------------------------------------
func test_kit_is_valid_and_covers_the_choir_kit() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	var kit := boss.boss_kit()
	eq(kit.validate(), [] as Array[String], "kit self-check passes")
	eq(kit.max_phases(), 2, "two phases")
	var ids: Array = []
	for entry in kit.attack_pool():
		ids.append(String(entry.id))
		for phase in range(1, kit.max_phases() + 1):
			ok(kit.windup_for(entry, phase) >= KIT_SCRIPT.BOSS_TELEGRAPH_MIN,
					"%s windup >= 0.35s in phase %d" % [entry.id, phase])
		ok(BossKit.hitbox_reach(entry) <= 300.0, "%s stays inside the arena" % entry.id)
	for required in ["sound_cone", "candle_rain", "silence_zone", "harmony_beam"]:
		ok(ids.has(required), "attack table has %s" % required)
	arena.queue_free()
	await flush(2)


func test_three_shells_and_one_double_scale_conductor() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	eq(boss.shells().size(), 3, "three choir shells")
	ok(boss.is_airborne(), "the choir floats (LevelSanity treats it as airborne)")
	var anim := boss.get_node_or_null("Visual/BodySprite") as FrameAnimSprite
	ok(anim != null, "the conductor wears the ghost frame animation")
	if anim != null:
		eq(anim.scale, Vector2(2, 2), "conductor is drawn at an integer 2x scale")
		ok(anim.position.y < 0.0, "conductor floats above the floor line")
	var hurt := boss.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	var rect := hurt.shape as RectangleShape2D
	eq(rect.size, SilentChoirBoss.HURT_SIZE)
	almost(boss.hurtbox.position.y + rect.size.y * 0.5, 0.0, 0.01,
			"the conductor's hurtbox reaches the floor so the sword can hit it")
	for shell in boss.shells():
		var sprite := (shell as Node).get_child(0) as Sprite2D
		ok(sprite != null and sprite.texture != null, "each shell has a ghost sprite")
		ok(sprite != null and sprite.modulate.r >= 1.0, "shells carry the warm candle hue")
	arena.queue_free()
	await flush(2)


func test_drive_request_has_one_warning_and_cleans_up() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	var kit := boss.boss_kit()
	for entry in kit.attack_pool():
		var before := CombatMarker.live
		var heard: Array = []
		var on_tel := func(kind: StringName, duration: float) -> void: heard.append([kind, duration])
		boss.telegraph_started.connect(on_tel)
		_request(boss, StringName(entry.id))
		ok(boss.drive_phase() != 0, "%s started" % entry.id)
		eq(heard.size(), 1, "%s announces exactly one telegraph" % entry.id)
		if heard.size() == 1:
			ok(float(heard[0][1]) >= KIT_SCRIPT.BOSS_TELEGRAPH_MIN,
					"%s telegraph lasts >= 0.35s" % entry.id)
		ok(CombatMarker.live <= before + 1, "%s spawns at most one warning" % entry.id)
		var guard := 0
		while boss.drive_phase() != 0 and guard < 200:
			boss._tick_state(0.05)
			guard += 1
		ok(boss.drive_phase() == 0, "%s finishes cleanly" % entry.id)
		boss.telegraph_started.disconnect(on_tel)
	arena.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 静默区 / 合声光束
# ---------------------------------------------------------------------------
func test_silence_zone_hides_the_knight_from_sound_targeting() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -24))
	var boss := await _spawn(arena, player)
	boss._last_heard = Vector2(200.0, -24.0)
	ok(not boss.is_player_silenced(), "outside a silence zone the knight is heard")
	boss._execute_silence()
	var center: Vector2 = boss._silence_rect.get_center()
	player.global_position = Vector2(center.x, -24.0)
	ok(boss.is_player_silenced(), "inside the silence zone the knight is unheard")
	almost(boss._aim_point().x, 200.0, 0.01, "sound attacks aim at the last heard position")
	player.global_position = Vector2(520.0, -24.0)
	ok(not boss.is_player_silenced(), "leaving the zone restores hearing")
	arena.queue_free()
	await flush(2)


func test_phase_two_harmony_beam_is_deflectable_and_breaks_the_choir() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -24))
	player.set_physics_process(false)
	var boss := await _spawn(arena, player)
	boss.health.take_damage(8, null)  # phase 2
	boss._tick_state(1.3)  # transition
	boss.health.invincible = false
	boss.health._hit_iframe = 0.0  # 相变那一击的受击无敌不该吃掉弹反测试
	eq(boss.phase(), 2)
	_request(boss, &"harmony_beam")
	var guard := 0
	while boss.drive_phase() == 1 and guard < 60:  # windup -> active
		boss._tick_state(0.05)
		guard += 1
	var bolt: Projectile = null
	for child in arena.find_children("*", "Projectile", true, false):
		bolt = child as Projectile
		if bolt != null:
			break
	ok(bolt != null, "the harmony beam is a real Projectile")
	if bolt != null:
		eq(bolt.team, &"enemy", "the beam starts hostile")
		ok(bolt.can_deflect(), "the beam can be parried")
		bolt.deflect(player)
		eq(bolt.team, &"player", "a parried beam changes team")
		# 打回指挥身上：Hurtbox 的破绽分支会给 Boss 开 Riposte。
		var hurt := boss.get_node("Hurtbox") as Node2D
		bolt.global_position = hurt.global_position
		for i in 6:
			await get_tree().physics_frame
		ok(boss.is_marked(), "a deflected beam opens the choir's riposte window")
		ok(boss.health.current < boss.health.max_hp, "the returned beam damages the choir")
	arena.queue_free()
	await flush(2)


# ---------------------------------------------------------------------------
# 阶段 / 场地机关 / 清场
# ---------------------------------------------------------------------------
func test_half_hp_enters_phase_two_and_shifts_the_hue() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn(arena)
	var phases: Array = []
	boss.boss_director().phase_entered.connect(func(next: int) -> void: phases.append(next))
	boss.health.take_damage(8, null)
	eq(phases, [2] as Array, "phase two entered exactly once")
	eq(boss.phase(), 2)
	ok(boss.health.invincible, "phase transition is invulnerable")
	ok(boss.boss_director().is_frozen(), "director freezes during the transition")
	boss._tick_state(1.3)
	ok(not boss.health.invincible)
	ok(not boss.boss_director().is_frozen())
	arena.queue_free()
	await flush(2)


func test_arena_hazards_register_and_trigger() -> void:
	var built := await _arena_host()
	var host: Node2D = built[0]
	var arena: BossArena = built[2]
	var ids := arena.registered_hazard_ids()
	for required in [&"choir_rise", &"silence_veil", &"choir_fade"]:
		ok(ids.has(required), "hazard %s is registered" % required)
		ok(arena.trigger_hazard(required), "hazard %s triggers" % required)
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
	ok(SaveData.has_flag(FLAG), "death flag choir_dead is written")
	ok(arena.is_cleared(), "clearing the choir unlocks the arena")
	ok(not is_instance_valid(boss), "boss body is released")
	host.queue_free()
	await flush(2)


func test_death_flag_survives_a_save_round_trip() -> void:
	SaveData.delete_save()
	var built := await _arena_host()
	var host: Node2D = built[0]
	var boss: Node2D = built[1]
	var player := await spawn_player(host)
	ok(SaveData.save_game(GameContext.LEVELS["level04b"], player), "chapter save exists")
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
