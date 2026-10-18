extends TestCase
## Hard cinematics preserve the combat state they interrupt and release it cleanly.

var _flags_before: PackedStringArray


func setup() -> void:
	_flags_before = SaveData.flags.duplicate()
	Director.reset_view()
	Director.resume()
	Director.choice_hold = false
	get_tree().paused = false


func teardown() -> void:
	get_tree().paused = false
	Director.reset_view()
	Director.resume()
	Director.choice_hold = false
	SaveData.flags = _flags_before


func _lock() -> void:
	Director.play([
		{"kind": "lock"},
		{"kind": "wait", "seconds": 5.0},
		{"kind": "unlock"},
	], true)


func test_cinematic_rejects_contact_direct_damage_and_knockback_before_signals() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	var hurtbox := player.get_node("Hurtbox") as Hurtbox
	var contact := Hitbox.new()
	contact.team = &"enemy"
	contact.damage = 2
	contact.knockback = Vector2(120.0, -30.0)
	arena.add_child(contact)
	var hits: Array = []
	hurtbox.hurt.connect(func(amount: int, _source: Node) -> void: hits.append(amount))
	var hp_before := player.health.current
	player.velocity = Vector2(7.0, 0.0)
	_lock()
	ok(player.cutscene_locked and player.is_invincible())
	hurtbox.receive_hit(2, contact)
	hurtbox._on_area_entered(contact)
	ok(not player.health.take_damage(1, contact), "direct health damage also respects the lock")
	eq(player.health.current, hp_before)
	eq(player.velocity, Vector2(7.0, 0.0), "cinematic contact cannot add knockback")
	eq(hits.size(), 0, "blocked contact emits no hurt reaction")
	eq(contact.already_hit.size(), 0, "ignored contact does not spend the hitbox's hit")
	Director.abort()
	ok(not player.cutscene_locked and not player.is_invincible(), "abort restores ordinary vulnerability")
	hurtbox.receive_hit(2, contact)
	ok(player.health.current < hp_before, "normal combat damage works again")
	ok(player.velocity.x > 7.0, "normal combat knockback works again")
	eq(hits.size(), 1)


func _assert_combat_clock_handoff(exit_kind: String) -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	player.resonance.set_process(false)
	player.resonance.pulse()
	const ENEMY := preload("res://scenes/enemies/SkeletonEnemy.tscn")
	var enemy: EnemyBase = ENEMY.instantiate()
	enemy.position = Vector2(1000.0, -1.0)
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.open_riposte()
	enemy.set_process(false)
	var marker := CombatMarker.spawn(enemy, CombatMarker.Kind.ZONE, Vector2.ZERO,
			0.45, Color.WHITE)
	marker.set_process(false)
	const PROJECTILE := preload("res://scenes/combat/Projectile.tscn")
	var bolt: Projectile = PROJECTILE.instantiate()
	bolt.setup(Vector2(900.0, -300.0), Vector2.LEFT, 80.0, &"enemy", enemy)
	arena.add_child(bolt)
	bolt.set_physics_process(false)
	var bolt_position := bolt.global_position
	var bolt_life := bolt.lifetime
	var resonance_left := player.resonance.remaining()
	var riposte_left := enemy.riposte_left()
	_lock()
	bolt._physics_process(3.0)
	player.resonance._process(3.0)
	enemy.tick_riposte(3.0)
	marker._process(3.0)
	eq(bolt.global_position, bolt_position, "in-flight trajectory waits for the camera")
	almost(bolt.lifetime, bolt_life, 0.0001)
	almost(player.resonance.remaining(), resonance_left, 0.0001)
	almost(enemy.riposte_left(), riposte_left, 0.0001)
	almost(marker.age(), 0.0, 0.0001, "the visible telegraph keeps the same age as its AI")
	ok(not marker.is_queued_for_deletion(), "the warning survives a cinematic longer than its lifetime")
	match exit_kind:
		"natural":
			Director._process(5.1)
		"skip":
			Director.skip_step()
		"abort":
			Director.abort()
		"chapter":
			GameEvents.chapter_started.emit("level02")
		"death":
			GameEvents.player_died.emit()
	ok(not Director.is_input_locked() and not player.cutscene_locked, "%s returns control" % exit_kind)
	ok(not player.is_invincible(), "%s leaves no stale cinematic invulnerability" % exit_kind)
	bolt._physics_process(0.1)
	player.resonance._process(0.1)
	enemy.tick_riposte(0.1)
	marker._process(0.1)
	almost(bolt.global_position.x, bolt_position.x - 8.0, 0.001)
	almost(bolt.lifetime, bolt_life - 0.1, 0.001)
	almost(player.resonance.remaining(), resonance_left - 0.1, 0.001)
	almost(enemy.riposte_left(), riposte_left - 0.1, 0.001)
	almost(marker.age(), 0.1, 0.001)
	ok(player.health.take_damage(1, null), "%s restores ordinary damage" % exit_kind)


func test_natural_finish_returns_preserved_combat_windows() -> void:
	await _assert_combat_clock_handoff("natural")


func test_skip_returns_preserved_combat_windows() -> void:
	await _assert_combat_clock_handoff("skip")


func test_abort_returns_preserved_combat_windows() -> void:
	await _assert_combat_clock_handoff("abort")


func test_chapter_restore_returns_preserved_combat_windows() -> void:
	await _assert_combat_clock_handoff("chapter")


func test_death_cleanup_releases_the_cinematic_owners() -> void:
	await _assert_combat_clock_handoff("death")


func test_incoming_projectile_waits_during_pause_then_can_hit_after_skip() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	const PROJECTILE := preload("res://scenes/combat/Projectile.tscn")
	var bolt: Projectile = PROJECTILE.instantiate()
	bolt.setup(player.global_position + Vector2(-48.0, -14.0), Vector2.RIGHT,
			90.0, &"enemy", null)
	arena.add_child(bolt)
	var hp_before := player.health.current
	var bolt_position := bolt.global_position
	var bolt_life := bolt.lifetime
	_lock()
	await flush(12)
	eq(player.health.current, hp_before, "a locked knight is safe from a real in-flight bolt")
	eq(bolt.global_position, bolt_position)
	almost(bolt.lifetime, bolt_life, 0.0001)
	get_tree().paused = true
	for i in 4:
		await get_tree().process_frame
	eq(bolt.global_position, bolt_position, "pause does not release the held projectile")
	get_tree().paused = false
	Director.skip_step()
	ok(await wait_until(func() -> bool: return player.health.current < hp_before, 90),
			"the same bolt resumes normal motion and collision after the handoff")

