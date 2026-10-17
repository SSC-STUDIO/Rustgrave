extends TestCase
## Integration: the slash ACTIVE window deflects an incoming slag bolt home.
## Uses the real Player + Projectile scenes; drives the swing via start_swing()
## (input-free by design) and lets physics resolve the overlap.


func test_active_window_deflects_incoming_bolt_at_spitter() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -24))
	almost(player.global_position.y, 0.0, 6.0, "settled onto floor")

	const PROJ := preload("res://scenes/combat/Projectile.tscn")
	var shooter := Node2D.new()
	shooter.position = Vector2(480, -38)
	arena.add_child(shooter)

	var bolt: Projectile = PROJ.instantiate()
	bolt.setup(Vector2(340, -38), Vector2.LEFT, 40.0, &"enemy", shooter)
	arena.add_child(bolt)
	await flush(2)

	# Swing, ride out wind-up into the ACTIVE (parry) window...
	ok(player.melee.start_swing(), "swing armed")
	var active := await wait_until(func() -> bool:
		return player.melee.is_parry_window(), 60)
	ok(active, "reached the active parry window")

	# ...and hand the overlapping bolt to the production deflect path
	# (this is exactly what the hitbox sweep feeds it each idle frame).
	player.melee._on_hitbox_area_entered(bolt)
	ok(bolt.deflected, "bolt deflected through the melee hook")
	eq(bolt.team, &"player")
	ok(bolt.velocity.x > 0.0, "reflected back toward its source")

	var untouched := player.health.current == player.health.max_hp
	ok(untouched, "player took no damage")
	await wait_until(func() -> bool:
		return player.melee.phase_name() == "idle", 80)
	eq(player.melee.phase_name(), "idle", "swing finished cleanly")


func test_double_deflect_is_refused() -> void:
	const PROJ := preload("res://scenes/combat/Projectile.tscn")
	var arena := Node2D.new()
	add_child(arena)
	var shooter := Node2D.new()
	shooter.position = Vector2(100, 0)
	arena.add_child(shooter)

	var bolt: Projectile = PROJ.instantiate()
	bolt.setup(Vector2.ZERO, Vector2.RIGHT, 10.0, &"enemy", shooter)
	arena.add_child(bolt)
	await flush(2)
	ok(bolt.can_deflect())
	bolt.deflect(shooter)
	ok(not bolt.can_deflect(), "second deflect attempt is a no-op")


## 判定第一帧就已经压在剑刃里的弹丸，必须在那一帧被弹回：
## 不能等到 Area2D 的 overlapping_areas 下一次物理刷新。
func test_bolt_already_inside_the_blade_is_parried_on_the_active_entry_frame() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -24))
	var shooter := Node2D.new()
	shooter.position = Vector2(480, -38)
	arena.add_child(shooter)

	const PROJ := preload("res://scenes/combat/Projectile.tscn")
	var bolt: Projectile = PROJ.instantiate()
	bolt.setup(player.global_position + Vector2(18, -14), Vector2.LEFT, 0.0, &"enemy", shooter)
	arena.add_child(bolt)
	await flush(2)
	ok(bolt.can_deflect(), "the bolt is live before the swing")
	ok(player.melee.start_swing())
	for i in 60:
		if player.melee.phase_name() == "active":
			break
		player.melee.tick(1.0 / 60.0)
	eq(player.melee.phase_name(), "active")
	ok(bolt.deflected, "the active-entry sweep parries the overlapping bolt at once")
	eq(bolt.team, &"player")
	ok(player.melee.swing_connected(), "the parry counts as a connected swing for cancels")
