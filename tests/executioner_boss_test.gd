extends TestCase
## ExecutionerBoss: half-HP enrage, starting HP.


func _spawn(arena: Node2D) -> ExecutionerBoss:
	const SCENE := preload("res://scenes/enemies/ExecutionerBoss.tscn")
	var b := SCENE.instantiate() as ExecutionerBoss
	b.position = Vector2(320, -20)
	arena.add_child(b)
	await flush(2)
	return b


func test_starts_with_boss_hp_and_not_enraged() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var b := await _spawn(arena)
	eq(b.health.max_hp, 13)
	eq(b.health.current, 13)
	ok(not b.is_enraged())


func test_slash_windup_pulses_ember() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var b := await _spawn(arena)
	b._begin_slash()
	ok(b._slash_next)
	eq(b._state, b.State.CHARGE)
	ok(b._flicker_tween != null and b._flicker_tween.is_valid(), "axe windup has a readable ember pulse")


func test_death_cancels_pending_slash() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var b := await _spawn(arena)
	b._set_blocking(false)
	b._begin_slash()
	b.health.take_damage(99, b)
	ok(b._dead)
	b._tick_charge(1.0)
	var extra := 0
	for child in arena.get_children():
		if child is Hitbox:
			extra += 1
	eq(extra, 0, "dead executioner does not finish the axe")


func test_enrages_at_half_hp() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var b := await _spawn(arena)
	b._set_blocking(false)
	b.health.take_damage(7, b)
	ok(b.is_enraged(), "half HP trips phase two")
	eq(b.health.current, 6)


func test_axe_active_then_full_unshielded_recovery_in_both_phases() -> void:
	for enraged in [false, true]:
		var arena := Node2D.new()
		add_child(arena)
		build_floor(arena)
		var b := await _spawn(arena)
		b.set_physics_process(false)
		b._enraged = enraged
		b._begin_slash()
		b._tick_charge(0.51)
		ok(b._slash_next, "full windup before damage")
		b._tick_charge(0.02)
		eq(b._slash_phase, b.SlashPhase.ACTIVE)
		ok(b._slash_box.monitoring)
		b._tick_state(0.15)
		eq(b._slash_phase, b.SlashPhase.ACTIVE)
		b._tick_state(0.02)
		eq(b._slash_phase, b.SlashPhase.RECOVERY)
		ok(not b._blocking)
		ok(b._slash_box == null)
		var before := arena.get_child_count()
		b._fire()
		eq(arena.get_child_count(), before, "recovery does not fire")
		var attacker := Node2D.new()
		arena.add_child(attacker)
		attacker.global_position = b.global_position + Vector2(b._shield_facing * 30, -10)
		b.hurtbox.receive_hit(1, attacker)
		eq(b.health.current, 12, "front attack lands during recovery")
		b._tick_state(0.64)
		eq(b._slash_phase, b.SlashPhase.RECOVERY)
		b._tick_state(0.02)
		eq(b._slash_phase, b.SlashPhase.NONE)
		ok(b._blocking, "shield returns after all 650ms")
		arena.queue_free()
		await flush(2)


func test_death_disarms_an_already_active_axe() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var b := await _spawn(arena)
	b.set_physics_process(false)
	b._begin_slash()
	b._tick_charge(0.53)
	var box := b._slash_box
	ok(box.monitoring)
	b._set_blocking(false)
	b.health.take_damage(99, null)
	ok(not box.monitoring, "death immediately closes detached axe hitbox")
	eq(b._slash_phase, b.SlashPhase.NONE)
	b._tick_state(1.0)
	ok(b._dead)
