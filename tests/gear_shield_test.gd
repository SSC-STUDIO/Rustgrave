extends TestCase
## GearShieldEnemy: frontal defense blocks damage, flanking lands it, and a
## deflected bolt staggers the shield open. Drives the state machine directly
## through public seams for determinism.


func _spawn(arena: Node2D, x: float) -> GearShieldEnemy:
	const SCENE := preload("res://scenes/enemies/GearShieldEnemy.tscn")
	var g := SCENE.instantiate() as GearShieldEnemy
	g.position = Vector2(x, -20)
	arena.add_child(g)
	await flush(24)
	return g


## Force the guard into its guarding posture facing `side` (1 = right).
func _enter_guard(g: GearShieldEnemy, side: int) -> void:
	g._state = g.State.BLOCK
	g._shield_facing = side
	g._blocking = false
	g._set_blocking(true)
	g._update_visual()


func test_torso_matches_the_drawn_armour() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var g := await _spawn(arena, 320.0)
	var body := g.get_node("CollisionShape2D") as CollisionShape2D
	var rect := body.shape as RectangleShape2D
	eq(rect.size, GearShieldEnemy.BODY_SIZE, "physics body is the torso, not the 16x26 placeholder")
	almost(body.position.y + rect.size.y * 0.5, 0.0, 0.01, "torso feet stay on y=0")
	var hurt := g.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	var hurt_rect := hurt.shape as RectangleShape2D
	eq(hurt_rect.size, GearShieldEnemy.HURT_SIZE, "hurtbox covers the hood-to-feet silhouette")
	almost(g.hurtbox.position.y + hurt_rect.size.y * 0.5, 0.0, 0.01, "hurtbox feet stay on y=0")
	var clear := g.body_clearance()
	almost(clear.x, 21.0, 0.01, "the cloak pushes before the player stands inside it")
	almost(clear.y, GearShieldEnemy.BODY_SIZE.y, 0.01, "a jump has to clear the torso")


func test_patrol_idle_takes_full_damage() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var g := await _spawn(arena, 320.0)
	g._set_blocking(false)
	var hp := g.health.current
	g.hurtbox.receive_hit(1, g)
	eq(g.health.current, hp - 1, "unguarded hit lands")


func test_frontal_melee_is_absorbed_by_shield() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var g := await _spawn(arena, 320.0)
	_enter_guard(g, 1)  # guarding toward the +x side
	var hp := g.health.current
	# Simulate a player hitbox striking from the guarded side.
	var fake := Node2D.new()
	fake.position = g.global_position + Vector2(30, 0)
	arena.add_child(fake)
	g.hurtbox.receive_hit(2, fake)
	eq(g.health.current, hp, "frontal hit is blocked, no damage")
	ok(g._state == g.State.BLOCK or g._state == g.State.CHARGE, "stays guarding after a blocked melee")


func test_flanking_hit_goes_around_the_shield() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var g := await _spawn(arena, 320.0)
	_enter_guard(g, 1)  # guarding the +x side
	var hp := g.health.current
	var fake := Node2D.new()
	fake.position = g.global_position + Vector2(-30, 0)  # other side = flank
	arena.add_child(fake)
	g.hurtbox.receive_hit(1, fake)
	eq(g.health.current, hp - 1, "flank attack damages")


func test_deflected_bolt_staggers_shield_open() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var g := await _spawn(arena, 320.0)
	_enter_guard(g, -1)  # guarding the -x (left) side
	const PROJ := preload("res://scenes/combat/Projectile.tscn")
	var bolt := PROJ.instantiate() as Projectile
	# A deflected bolt flying back at the guard from the guarded (left) side.
	bolt.setup(g.global_position + Vector2(-40, -20), Vector2.RIGHT, 200.0, &"player", g)
	arena.add_child(bolt)
	await flush(1)
	g.hurtbox.receive_hit(1, bolt)
	eq(g.health.current, g.health.max_hp, "deflected bolt does not chip HP")
	ok(g._state == g.State.STAGGER, "shield staggered open")
	ok(not g._blocking, "no longer blocking during stagger")


func test_hit_flash_keeps_block_tint() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var g := await _spawn(arena, 320.0)
	_enter_guard(g, 1)
	g._flash_white()
	ok(g._indicator.modulate != Color.WHITE, "block telegraph survives the hit flash")
	eq(g._flash_restore_color(), Color.WHITE, "parent Visual flash still restores to white")


func test_stagger_recovers_to_guarding() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var g := await _spawn(arena, 320.0)
	_enter_guard(g, 1)
	g._enter_stagger()
	ok(g._state == g.State.STAGGER)
	for i in ceili((g.stagger_time + 0.05) * 60.0):
		g._tick_stagger(1.0 / 60.0)
	ok(g._state == g.State.BLOCK, "recovers to guarding")
	ok(g._blocking, "shield raised again")


func test_bolt_spawns_in_the_enemy_world() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var g := await _spawn(arena, 320.0)
	g._fire()
	var effects := arena.get_node_or_null("WorldEffects")
	ok(effects != null, "bolt host is the world, not current_scene")
	var found := false
	if effects != null:
		for child in effects.get_children():
			if child is Projectile:
				found = true
				ok(child.get_world_2d() == g.get_world_2d(), "bolt shares the enemy World2D")
	ok(found, "bolt was parented under WorldEffects")


func test_real_slash_reflects_front_bolts_and_opens_both_shield_facings() -> void:
	for side in [-1, 1]:
		var arena := Node2D.new()
		add_child(arena)
		build_floor(arena)
		var g := await _spawn(arena, 320.0)
		g.set_physics_process(false)
		_enter_guard(g, side)
		var player := await spawn_player(arena, Vector2(320 + side * 110, -24))
		player.set_physics_process(false)
		player.melee.set_physics_process(false)
		player.controller.facing = -side
		player.melee.scale.x = -side
		player.melee.start_swing()
		for i in 12:
			player.melee.tick(1.0 / 60.0)
		ok(player.melee.is_parry_window())
		var bolt := preload("res://scenes/combat/Projectile.tscn").instantiate() as Projectile
		arena.add_child(bolt)
		bolt.setup(player.global_position + Vector2(-side * 28, -18),
				Vector2(side, 0), 80.0, &"enemy", g)
		var opened := await wait_until(func() -> bool: return g._state == g.State.STAGGER, 120)
		ok(opened, "real sword/bolt/guard collision opens facing %d" % side)
		eq(g.health.current, g.health.max_hp, "front reflection staggers without HP damage")
		ok(not g._blocking)
		arena.queue_free()
		await flush(2)


func test_real_back_bolts_damage_both_shield_facings() -> void:
	for side in [-1, 1]:
		var arena := Node2D.new()
		add_child(arena)
		build_floor(arena)
		var g := await _spawn(arena, 320.0)
		g.set_physics_process(false)
		_enter_guard(g, side)
		var bolt := preload("res://scenes/combat/Projectile.tscn").instantiate() as Projectile
		arena.add_child(bolt)
		bolt.setup(g.global_position + Vector2(-side * 70, -18),
				Vector2(side, 0), 140.0, &"player", null)
		var hit := await wait_until(func() -> bool: return g.health.current < g.health.max_hp, 90)
		ok(hit, "rear bolt lands behind facing %d" % side)
		eq(g.health.current, g.health.max_hp - 1)
		eq(g._state, g.State.BLOCK, "rear hit does not count as shield stagger")
		arena.queue_free()
		await flush(2)
