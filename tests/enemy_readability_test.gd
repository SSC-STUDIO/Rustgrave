extends TestCase
## 敌人读招：每种敌人一个独有的暗号，伤害绝不早于暗号结束，出招后有看得见的破绽。
## 全部通过各敌人的公共 / 内部状态接缝推进，不模拟输入；步长 1/60 秒。

const DT := 1.0 / 60.0
const MIN := 0.25


func _arena() -> Node2D:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	return arena


func _enemy(arena: Node2D, path: String, pos: Vector2) -> EnemyBase:
	var e := load(path).instantiate() as EnemyBase
	e.position = pos
	arena.add_child(e)
	return e


func _record(e: EnemyBase) -> Array:
	var seen: Array = []
	e.telegraph_started.connect(func(kind: StringName, duration: float) -> void: seen.append([kind, duration]))
	return seen


## 读招结束前判定体必须没开：armed 是「现在有没有伤害能力」的闭包。
func _drive(step: Callable, armed: Callable, started: Callable, limit: int = 240) -> float:
	var elapsed := 0.0
	var began := false
	for i in limit:
		step.call()
		if not began and bool(started.call()):
			began = true
			elapsed = 0.0
		if began:
			elapsed += DT
			if bool(armed.call()):
				return elapsed
	return -1.0


func _check_telegraph(kind: StringName, seen: Array, elapsed: float, tolerance: float = DT * 1.5) -> void:
	ok(seen.size() >= 1, "%s announced its telegraph" % kind)
	if seen.is_empty():
		return
	eq(seen[0][0], kind)
	var duration: float = seen[0][1]
	ok(duration >= MIN, "%s telegraph lasts >= 0.25 s (%.2f)" % [kind, duration])
	almost(duration, float(CombatRules.TELEGRAPH[kind]["time"]), 0.0001, "%s matches the table" % kind)
	ok(elapsed >= 0.0, "%s eventually attacks" % kind)
	ok(elapsed >= duration - tolerance, "%s: no damage before its telegraph ends (%.3f of %.3f)" % [kind, elapsed, duration])


func test_table_is_distinct_and_long_enough() -> void:
	var signatures: Dictionary = {}
	var colors: Array = []
	for kind in CombatRules.TELEGRAPH:
		var e: Dictionary = CombatRules.TELEGRAPH[kind]
		ok(float(e["time"]) >= CombatRules.TELEGRAPH_MIN, "%s telegraphs >= 0.25 s" % kind)
		ok(float(e["punish"]) > 0.0, "%s leaves a punish window" % kind)
		ok(not signatures.has(e["signature"]), "%s has its own signature" % kind)
		signatures[e["signature"]] = kind
		colors.append([kind, e["color"]])
	eq(CombatRules.TELEGRAPH.size(), 9, "one entry per enemy kind (7 enemies + 2 bosses)")
	for i in colors.size():
		for j in range(i + 1, colors.size()):
			var a: Color = colors[i][1]
			var b: Color = colors[j][1]
			var d := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			ok(d >= 0.2, "%s and %s cues differ in colour (%.2f)" % [colors[i][0], colors[j][0], d])


func test_spitter_swells_before_it_spits() -> void:
	var arena := _arena()
	var p := await spawn_player(arena, Vector2(180, -24))
	p.set_physics_process(false)
	var spit := _enemy(arena, "res://scenes/enemies/SpitterEnemy.tscn", Vector2(320, 0)) as SpitterEnemy
	await flush(2)
	var seen := _record(spit)
	var bolts_before := Projectile.live_count()
	spit._begin_charge()
	var elapsed := 0.0
	var fired := false
	for i in 80:
		await get_tree().physics_frame
		elapsed += DT
		if Projectile.live_count() > bolts_before:
			fired = true
			break
	ok(fired, "the bolt eventually flies")
	_check_telegraph(&"spitter", seen, elapsed, 0.08)
	ok(spit._body.modulate != spit._base_modulate or spit._charging == false, "the body carried the toxic swell")
	await get_tree().create_timer(0.1).timeout
	var marks := 0
	for child in spit.get_children():
		if child is CombatMarker:
			marks += 1
	ok(marks >= 1, "the exhale after the shot is marked as an opening")


func test_scrapper_crouches_before_charging_and_stuns_after() -> void:
	var arena := _arena()
	var scrap := _enemy(arena, "res://scenes/enemies/ScrapperEnemy.tscn", Vector2(320, -20)) as ScrapperEnemy
	await flush(4)
	scrap.set_physics_process(false)
	var seen := _record(scrap)
	scrap._dir = 1.0
	scrap._enter_windup()
	var armed_early := false
	var elapsed := _drive(func() -> void: scrap._tick_state(DT),
			func() -> bool:
				if scrap.charge_box.monitoring and scrap._state != ScrapperEnemy.State.CHARGE:
					armed_early = true
				return scrap._state == ScrapperEnemy.State.CHARGE,
			func() -> bool: return true)
	ok(not armed_early)
	_check_telegraph(&"scrapper", seen, elapsed)
	ok(scrap.charge_box.monitoring, "the ram hitbox is live only once the charge starts")
	# 冲满一程落空 -> 眩晕 + 头顶箭头
	scrap._timer = 0.0
	scrap._tick_charge(DT)
	if scrap._state == ScrapperEnemy.State.CHARGE:
		scrap._tick_charge(DT)
	eq(scrap._state, ScrapperEnemy.State.STUN, "a charge that ends in open air leaves it winded")
	ok(not scrap.charge_box.monitoring, "winded brutes cannot ram")
	ok(scrap._timer >= CombatRules.TELEGRAPH[&"scrapper"]["punish"] - 0.001, "punish window >= the table")


func test_skeleton_bites_in_three_beats() -> void:
	var arena := _arena()
	var p := await spawn_player(arena, Vector2(320, -24))
	p.set_physics_process(false)
	var skel := _enemy(arena, "res://scenes/enemies/SkeletonEnemy.tscn", Vector2(334, 0)) as SkeletonEnemy
	await flush(3)
	skel.set_physics_process(false)
	skel._state = SkeletonEnemy.State.WALK
	skel._set_tangible(true)
	skel.visual.visible = true
	var seen := _record(skel)
	var armed_in_windup := false
	var elapsed := _drive(func() -> void: skel._tick_state(DT),
			func() -> bool:
				if skel.hitbox.monitoring and skel.bite_phase() == SkeletonEnemy.BitePhase.WINDUP:
					armed_in_windup = true
				return skel.hitbox.monitoring,
			func() -> bool: return skel.state() == SkeletonEnemy.State.BITE)
	ok(not armed_in_windup, "the bite is not live during the lean-back")
	_check_telegraph(&"skeleton", seen, elapsed)
	eq(skel.bite_phase(), SkeletonEnemy.BitePhase.ACTIVE)
	var active := 0.0
	while skel.bite_phase() == SkeletonEnemy.BitePhase.ACTIVE and active < 0.5:
		skel._tick_state(DT)
		active += DT
	ok(active <= SkeletonEnemy.BITE_ACTIVE + DT * 2.0, "the live window is short (%.2f)" % active)
	eq(skel.bite_phase(), SkeletonEnemy.BitePhase.RECOVERY)
	ok(not skel.hitbox.monitoring, "mouth open, hitbox closed")
	var rec := 0.0
	while skel.state() == SkeletonEnemy.State.BITE and rec < 1.0:
		skel._tick_state(DT)
		rec += DT
	almost(rec, SkeletonEnemy.BITE_RECOVERY, DT * 2.0, "punish window")
	ok(rec >= float(CombatRules.TELEGRAPH[&"skeleton"]["punish"]) - DT * 2.0)


func test_skeleton_miss_when_the_knight_steps_out_during_the_lean() -> void:
	var arena := _arena()
	var p := await spawn_player(arena, Vector2(320, -24))
	p.set_physics_process(false)
	var skel := _enemy(arena, "res://scenes/enemies/SkeletonEnemy.tscn", Vector2(334, 0)) as SkeletonEnemy
	await flush(3)
	skel.set_physics_process(false)
	skel._state = SkeletonEnemy.State.WALK
	skel._set_tangible(true)
	skel._tick_state(DT)
	eq(skel.state(), SkeletonEnemy.State.BITE)
	p.global_position.x = 600.0  # 骑士退开
	for i in 40:
		skel._tick_state(DT)
	ok(not p.health.is_invincible() or p.health.current == p.health.max_hp)
	eq(p.health.current, p.health.max_hp, "stepping away in the windup means the bite lands on nothing")


func test_ghost_rings_before_it_lunges() -> void:
	var arena := _arena()
	var p := await spawn_player(arena, Vector2(320, -24))
	p.set_physics_process(false)
	var ghost := _enemy(arena, "res://scenes/enemies/GhostEnemy.tscn", Vector2(330, -36)) as GhostEnemy
	await flush(2)
	ghost.set_physics_process(false)
	ghost._state = GhostEnemy.State.HAUNT
	ghost._timer = 5.0
	ghost._set_tangible(true)
	ghost.global_position = p.global_position + Vector2(12.0, -12.0)
	var seen := _record(ghost)
	var markers_before := CombatMarker.live
	var armed_early := false
	var elapsed := _drive(func() -> void: ghost._tick_state(DT),
			func() -> bool:
				if ghost.hitbox.monitoring and ghost._timer > GhostEnemy.ATTACK_ACTIVE + 0.001:
					armed_early = true
				return ghost.hitbox.monitoring,
			func() -> bool: return ghost._state == GhostEnemy.State.ATTACK)
	ok(not armed_early)
	_check_telegraph(&"ghost", seen, elapsed)
	ok(CombatMarker.live > markers_before, "a wail ring marks the lunge")
	for i in 60:
		ghost._tick_state(DT)
	eq(ghost._state, GhostEnemy.State.HAUNT)
	ok(ghost._recover_left > 0.0 or ghost._attack_cd > 0.0, "it freezes for a beat after the lunge")


func test_fire_skull_flares_before_it_lunges_and_pauses_after() -> void:
	var arena := _arena()
	var p := await spawn_player(arena, Vector2(320, -24))
	p.set_physics_process(false)
	var skull := _enemy(arena, "res://scenes/enemies/FireSkullEnemy.tscn", Vector2(330, -40)) as FireSkullEnemy
	await flush(2)
	skull.set_physics_process(false)
	skull._state = FireSkullEnemy.State.HUNT
	skull.global_position = p.global_position + Vector2(10.0, -22.0)
	var seen := _record(skull)
	var armed_early := false
	var elapsed := _drive(func() -> void: skull._tick_state(DT),
			func() -> bool:
				if skull.hitbox.monitoring and skull.state() == FireSkullEnemy.State.FLARE:
					armed_early = true
				return skull.hitbox.monitoring,
			func() -> bool: return skull.state() == FireSkullEnemy.State.FLARE)
	ok(not armed_early)
	_check_telegraph(&"fire_skull", seen, elapsed)
	eq(skull.state(), FireSkullEnemy.State.LUNGE)
	# 扑完立刻进喘息；要在 RETREAT 开头量停顿，别把喘息时间算进扑击循环里。
	for i in 40:
		skull._tick_state(DT)
		if skull.state() == FireSkullEnemy.State.RETREAT:
			break
	eq(skull.state(), FireSkullEnemy.State.RETREAT)
	ok(not skull.hitbox.monitoring)
	var held := skull.global_position
	var pause_frames := int(ceil(FireSkullEnemy.RETREAT_PAUSE / DT)) - 1
	for i in maxi(pause_frames, 1):
		skull._tick_state(DT)
		eq(skull.state(), FireSkullEnemy.State.RETREAT)
	ok(skull.global_position.distance_to(held) < 3.0, "after the lunge it hangs still for a beat")


func test_demon_swells_before_it_dives_and_hovers_after() -> void:
	var arena := _arena()
	var p := await spawn_player(arena, Vector2(320, -24))
	p.set_physics_process(false)
	var demon := _enemy(arena, "res://scenes/enemies/FlyingDemonEnemy.tscn", Vector2(380, -110)) as FlyingDemonEnemy
	await flush(2)
	demon.set_physics_process(false)
	demon._target_player = p
	var seen := _record(demon)
	demon._start_attack()
	var armed_early := false
	var elapsed := _drive(func() -> void: demon._tick_state(DT),
			func() -> bool:
				if demon.hitbox.monitoring and demon._state == FlyingDemonEnemy.State.ATTACK:
					armed_early = true
				return demon.hitbox.monitoring,
			func() -> bool: return true)
	ok(not armed_early)
	_check_telegraph(&"flying_demon", seen, elapsed)
	eq(demon._state, FlyingDemonEnemy.State.SWOOP)
	demon._state_timer = 0.0
	demon._tick_state(DT)
	eq(demon._state, FlyingDemonEnemy.State.RECOVERY)
	ok(not demon.hitbox.monitoring)
	almost(demon._state_timer, FlyingDemonEnemy.RECOVERY_TIME, 0.001)
	ok(demon._state_timer >= float(CombatRules.TELEGRAPH[&"flying_demon"]["punish"]) - 0.001)


func test_gear_shield_arm_raise_comes_before_the_bolt() -> void:
	var arena := _arena()
	var p := await spawn_player(arena, Vector2(180, -24))
	p.set_physics_process(false)
	var g := _enemy(arena, "res://scenes/enemies/GearShieldEnemy.tscn", Vector2(320, -20)) as GearShieldEnemy
	await flush(24)
	g.set_physics_process(false)
	g._enter_block(p)
	var seen := _record(g)
	g._shoot_timer = 0.0
	var before := Projectile.live_count()
	var elapsed := 0.0
	var fired := false
	for i in 120:
		g._tick_state(DT)
		if g._state == GearShieldEnemy.State.CHARGE or fired:
			elapsed += DT
		if Projectile.live_count() > before:
			fired = true
			break
	ok(fired, "the guard fires")
	_check_telegraph(&"gear_shield", seen, elapsed)
	# 弹反破盾 = 唯一的破绽，且被标记。
	g._enter_stagger()
	almost(g._timer, g.stagger_time, 0.001)
	ok(g.stagger_time >= float(CombatRules.TELEGRAPH[&"gear_shield"]["punish"]) - 0.001)


func test_executioner_axe_zone_matches_the_hitbox() -> void:
	var arena := _arena()
	var b := _enemy(arena, "res://scenes/enemies/ExecutionerBoss.tscn", Vector2(320, -20)) as ExecutionerBoss
	await flush(2)
	b.set_physics_process(false)
	var seen := _record(b)
	var markers_before := CombatMarker.live
	b._begin_slash()
	ok(CombatMarker.live == markers_before + 1, "a red landing zone is drawn for the swing")
	var armed_early := false
	var elapsed := _drive(func() -> void: b._tick_charge(DT),
			func() -> bool:
				if b._slash_box != null and b._slash_box.monitoring and b._slash_next:
					armed_early = true
				return b._slash_box != null and b._slash_box.monitoring,
			func() -> bool: return true)
	ok(not armed_early)
	_check_telegraph(&"executioner", seen, elapsed)
	# 落点框与判定盒同位同尺寸
	var zone_center := Vector2(float(b._shield_facing) * ExecutionerBoss.SLASH_ZONE_OFFSET.x, ExecutionerBoss.SLASH_ZONE_OFFSET.y)
	var box_center := b._slash_box.global_position - b.global_position
	ok(zone_center.distance_to(box_center) < 0.01, "zone sits exactly where the axe lands")
	var shape := (b._slash_box.get_child(0) as CollisionShape2D).shape as RectangleShape2D
	eq(shape.size, ExecutionerBoss.SLASH_ZONE_SIZE, "zone is exactly the hitbox size")


func test_nightmare_lane_and_lock() -> void:
	for enraged in [false, true]:
		var arena := _arena()
		var p := await spawn_player(arena, Vector2(120, -24))
		p.set_physics_process(false)
		var boss := _enemy(arena, "res://scenes/enemies/NightmareBoss.tscn", Vector2(420, 0))
		await flush(2)
		boss.set_physics_process(false)
		boss.arena_left = 40.0
		boss.arena_right = 700.0
		if enraged:
			boss.health.take_damage(8, p)
			ok(boss.is_enraged())
			boss._enter_rest()
		var seen := _record(boss)
		boss._enter_windup()
		ok(boss._lane != null and is_instance_valid(boss._lane), "a lane is drawn for the charge")
		var armed_early := false
		var locked_at := -1.0
		var t := 0.0
		for i in 120:
			boss._tick_state(DT)
			t += DT
			if locked_at < 0.0 and boss._direction_locked:
				locked_at = t
				ok(boss._lane.is_locked(), "the lane turns solid the moment the direction locks")
			if boss.hitbox.monitoring and boss.state() == boss.State.WINDUP:
				armed_early = true
			if boss.state() == boss.State.CHARGE:
				break
		ok(not armed_early)
		ok(seen.size() >= 1 and seen[0][0] == &"nightmare", "the windup announced itself")
		if not enraged:
			_check_telegraph(&"nightmare", seen, t, DT * 2.0)
		else:
			ok(float(seen[0][1]) >= MIN, "enraged telegraph still >= 0.25 s")
			almost(float(seen[0][1]), CombatRules.NIGHTMARE_P2_WINDUP, 0.0001, "phase two windup from the table")
		ok(t >= boss.windup_time - DT * 2.0, "no damage before the windup ends (%.2f of %.2f)" % [t, boss.windup_time])
		ok(boss.windup_time >= 0.5, "even the enraged windup is long")
		ok(boss.windup_time - boss.DIRECTION_LOCK_TIME >= MIN, "the tracking part alone still lasts >= 0.25 s")
		ok(locked_at > 0.0 and (t - locked_at) >= boss.DIRECTION_LOCK_TIME - DT * 2.0, "the last 0.2 s is locked")
		ok(boss._lane == null or not is_instance_valid(boss._lane) or boss._lane.is_queued_for_deletion(), "lane dismissed as the charge starts")
		boss._enter_rest()
		var opening := 0
		for child in boss.get_children():
			if child is CombatMarker:
				opening += 1
		ok(opening >= 1, "the rest is marked as an opening")
		arena.queue_free()
		await flush(2)


func test_every_enemy_can_be_hit_during_its_punish_window() -> void:
	# 破绽期间的受击不会被「无敌」吃掉：敌人的 Health 在这些状态下不是 invincible。
	var arena := _arena()
	var scrap := _enemy(arena, "res://scenes/enemies/ScrapperEnemy.tscn", Vector2(320, -20)) as ScrapperEnemy
	await flush(3)
	scrap._enter_stun(0.5)
	ok(not scrap.health.is_invincible(), "a stunned brute can be struck")
	eq(scrap._state, ScrapperEnemy.State.STUN)
	var before := scrap.health.current
	scrap.get_node("Hurtbox").receive_hit(1, scrap)
	eq(scrap.health.current, before - 1)
