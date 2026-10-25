extends TestCase
## Ground areas use the level's world floor even when their owning flyer moves.
const BOSS := preload("res://scenes/enemies/EmberwindHerald.tscn")


func setup() -> void:
	Input.action_release("jump")
	Director.abort()
	Director._set_lock(false)


func teardown() -> void:
	Input.action_release("jump")
	Director.abort()
	Director._set_lock(false)


func _rig() -> Node2D:
	var arena := Node2D.new()
	arena.position = Vector2(700, 100)
	add_child(arena)
	var floor_ := build_floor(arena)
	floor_.position.y += 320.0
	return arena


func _boss(arena: Node2D) -> Node2D:
	var boss := BOSS.instantiate() as Node2D
	boss.position = Vector2(520, 320)
	arena.add_child(boss)
	boss.set_physics_process(false)
	(boss.call("boss_director") as BossDirector).set_physics_process(false)
	return boss


func _child(boss: Node, prefix: String) -> Node2D:
	for node in boss.get_children():
		if String(node.name).begins_with(prefix): return node as Node2D
	return null


func _marker(boss: Node, kind: CombatMarker.Kind) -> CombatMarker:
	for node in boss.get_children():
		if node is CombatMarker and node.kind == kind: return node
	return null


func test_updraft_matches_ground_warning_at_nonzero_world_floor_and_stays_put() -> void:
	var arena := _rig()
	var player := await spawn_player(arena, Vector2(320, 296))
	var boss := _boss(arena)
	var floor_y := player.global_position.y
	boss.call("_begin_attack", &"updraft")
	var warning := _marker(boss, CombatMarker.Kind.ZONE)
	ok(warning != null)
	if warning == null: return
	almost(warning.global_position.x, player.global_position.x)
	almost(warning.global_position.y, floor_y - 75.0, 0.2)
	boss.call("_tick_state", 0.61)
	var zone := _child(boss, "UpdraftZone")
	ok(zone != null)
	if zone == null: return
	eq(zone.global_position, warning.global_position, "real updraft covers exactly its world warning")
	almost(zone.global_position.y + 75.0, floor_y, 0.2, "updraft reaches the standing knight instead of hiding below the floor")
	var fixed := zone.global_position
	boss.global_position += Vector2(60, -80)
	eq(zone.global_position, fixed, "Boss hovering does not carry the ground zone")
	eq(warning.global_position, fixed, "Boss hovering does not carry the warning")
	await flush(3)
	ok((zone.get("_bodies") as Array).has(player), "the actual collision area sees the real grounded player")
	boss.call("_cleanup_transient")
	await flush(2)
	ok(not is_instance_valid(zone), "Boss still owns zone cleanup")
	arena.queue_free()
	await flush(2)


func test_wind_and_dive_warnings_use_the_same_world_lane_as_the_real_areas() -> void:
	var arena := _rig()
	var player := await spawn_player(arena, Vector2(320, 296))
	var boss := _boss(arena)
	var floor_y := player.global_position.y
	boss.call("_begin_attack", &"wind_push")
	var warning := _marker(boss, CombatMarker.Kind.ZONE)
	ok(warning != null)
	if warning == null: return
	almost(warning.global_position.y, floor_y - 100.0, 0.2)
	boss.call("_tick_state", 0.56)
	var zone := _child(boss, "WindZone")
	ok(zone != null)
	if zone == null: return
	eq(zone.global_position, warning.global_position)
	var fixed := zone.global_position
	boss.global_position += Vector2(80, -30)
	eq(zone.global_position, fixed)
	eq(warning.global_position, fixed)
	player.set_physics_process(false)
	await flush(12)
	ok((zone.get("_bodies") as Array).has(player), "the ground wind overlaps the knight without teleporting into it")
	ok(player.velocity.x < -5.0, "actual Area2D membership applies the existing wind force")
	boss.call("_interrupt_attack")
	boss.call("_begin_attack", &"dive")
	var lane := _marker(boss, CombatMarker.Kind.LANE)
	ok(lane != null)
	if lane != null:
		almost(lane.global_position.y, floor_y - 34.0 + 8.0, 0.2, "lane marks the dive's low hitbox centre")
	arena.queue_free()
	await flush(2)


func _jump_rise(with_updraft: bool) -> float:
	var arena := _rig()
	var player := await spawn_player(arena, Vector2(320, 296))
	var boss := _boss(arena)
	if with_updraft:
		boss.call("_begin_attack", &"updraft")
		boss.call("_tick_state", 0.61)
		await flush(3)
	var floor_y := player.global_position.y
	var highest := floor_y
	Input.action_press("jump")
	for i in 42:
		await flush(1)
		highest = minf(highest, player.global_position.y)
	Input.action_release("jump")
	arena.queue_free()
	await flush(2)
	return floor_y - highest


func test_real_normal_jump_rises_higher_inside_the_updraft() -> void:
	var baseline := await _jump_rise(false)
	var lifted := await _jump_rise(true)
	print("[HERALD UPDRAFT] ordinary_jump=%.2f lifted_jump=%.2f" % [baseline, lifted])
	ok(baseline > 25.0, "ordinary jump was executed by the real controller")
	ok(lifted > baseline + 12.0, "unchanged real updraft adds lift to normal jump: %.2f -> %.2f" % [baseline, lifted])
