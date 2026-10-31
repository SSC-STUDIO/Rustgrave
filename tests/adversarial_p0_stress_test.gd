extends TestCase
## Empirical Adversarial Stress Test Suite for Phase 0
## Covers Health.quiet, take_damage edge conditions, and Player arena depth / jump z-axis isolation.

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const UnitScript := preload("res://scripts/arena/arena_unit.gd")

var _hit_events: Array = []


func setup() -> void:
	if get_tree().paused:
		get_tree().paused = false
	ArenaRun.auto_begin = false
	ArenaRun.abandon()
	_hit_events.clear()
	if not GameEvents.hit.is_connected(_on_game_hit):
		GameEvents.hit.connect(_on_game_hit)


func teardown() -> void:
	if GameEvents.hit.is_connected(_on_game_hit):
		GameEvents.hit.disconnect(_on_game_hit)
	_hit_events.clear()
	ArenaRun.auto_begin = false
	ArenaRun.abandon()


func _on_game_hit(attacker: Node, target: Node, amount: int) -> void:
	_hit_events.append({
		"attacker": attacker,
		"target": target,
		"amount": amount,
	})


# -----------------------------------------------------------------------------
# 1. Health.take_damage Edge Conditions & GameEvents.hit Verification
# -----------------------------------------------------------------------------

func test_quiet_null_attacker_no_player_no_hit_signal() -> void:
	var dummy_host := Node2D.new()
	dummy_host.name = "DummyHost"
	add_child(dummy_host)
	var hp := Health.new()
	hp.name = "Health"
	hp.quiet = true
	dummy_host.add_child(hp)
	await flush(1)

	_hit_events.clear()
	var took := hp.take_damage(2, null)
	ok(took, "Damage should be taken with null attacker")
	eq(hp.current, hp.max_hp - 2, "HP should decrease by 2")
	eq(_hit_events.size(), 0, "GameEvents.hit must NOT be emitted when quiet=true and attacker=null on non-player")
	dummy_host.queue_free()


func test_quiet_player_attacker_emits_hit_signal() -> void:
	var dummy_host := Node2D.new()
	dummy_host.name = "VictimAI"
	add_child(dummy_host)
	var hp := Health.new()
	hp.name = "Health"
	hp.quiet = true
	dummy_host.add_child(hp)

	# Direct player attacker
	var player_node := Node2D.new()
	player_node.name = "FakePlayer"
	player_node.add_to_group("player")
	add_child(player_node)
	await flush(1)

	_hit_events.clear()
	var took := hp.take_damage(1, player_node)
	ok(took, "Damage should succeed")
	eq(_hit_events.size(), 1, "GameEvents.hit MUST be emitted when attacker is in group 'player'")
	if _hit_events.size() > 0:
		eq(_hit_events[0]["attacker"], player_node)
		eq(_hit_events[0]["target"], dummy_host)
		eq(_hit_events[0]["amount"], 1)

	# Sub-node attacker (e.g. projectile or hitbox child of player)
	var child_hitbox := Node2D.new()
	child_hitbox.name = "HitboxChild"
	player_node.add_child(child_hitbox)
	await flush(1)

	# Burn iframe
	hp._hit_iframe = 0.0
	_hit_events.clear()
	var took_child := hp.take_damage(1, child_hitbox)
	ok(took_child, "Damage should succeed from child hitbox")
	eq(_hit_events.size(), 1, "GameEvents.hit MUST be emitted when attacker's parent is in group 'player'")

	player_node.queue_free()
	dummy_host.queue_free()


func test_quiet_player_victim_emits_hit_signal() -> void:
	var player_host := Node2D.new()
	player_host.name = "PlayerHost"
	player_host.add_to_group("player")
	add_child(player_host)
	var hp := Health.new()
	hp.name = "Health"
	hp.quiet = true
	player_host.add_child(hp)

	var enemy_attacker := Node2D.new()
	enemy_attacker.name = "EnemyAttacker"
	add_child(enemy_attacker)
	await flush(1)

	# Enemy attacker hits player victim with quiet=true
	_hit_events.clear()
	var took := hp.take_damage(1, enemy_attacker)
	ok(took, "Player victim should take damage")
	eq(_hit_events.size(), 1, "GameEvents.hit MUST be emitted when victim host is in group 'player'")
	if _hit_events.size() > 0:
		eq(_hit_events[0]["attacker"], enemy_attacker)
		eq(_hit_events[0]["target"], player_host)

	# Null attacker hitting player victim with quiet=true (e.g. environmental hazard)
	hp._hit_iframe = 0.0
	_hit_events.clear()
	var took_null := hp.take_damage(1, null)
	ok(took_null, "Player victim should take damage from null attacker")
	eq(_hit_events.size(), 1, "GameEvents.hit MUST be emitted when victim is player even if attacker is null")

	player_host.queue_free()
	enemy_attacker.queue_free()


func test_quiet_ai_vs_ai_strictly_suppressed() -> void:
	var vic := Node2D.new()
	vic.name = "MinionVic"
	add_child(vic)
	var hp := Health.new()
	hp.name = "Health"
	hp.quiet = true
	vic.add_child(hp)

	var atk := Node2D.new()
	atk.name = "MinionAtk"
	add_child(atk)
	await flush(1)

	_hit_events.clear()
	var took := hp.take_damage(1, atk)
	ok(took, "Damage taken")
	eq(_hit_events.size(), 0, "AI vs AI must NOT emit GameEvents.hit when quiet=true")

	# Flip quiet to false
	hp._hit_iframe = 0.0
	hp.quiet = false
	_hit_events.clear()
	var took2 := hp.take_damage(1, atk)
	ok(took2, "Damage taken")
	eq(_hit_events.size(), 1, "AI vs AI MUST emit GameEvents.hit when quiet=false")

	vic.queue_free()
	atk.queue_free()


func test_force_quiet_overrides() -> void:
	var vic := Node2D.new()
	add_child(vic)
	var hp := Health.new()
	hp.quiet = false
	vic.add_child(hp)
	var atk := Node2D.new()
	add_child(atk)
	await flush(1)

	# quiet=false, but force_quiet=true
	_hit_events.clear()
	hp.take_damage(1, atk, true)
	eq(_hit_events.size(), 0, "force_quiet=true should suppress hit signal even when quiet=false")

	# quiet=true, but force_quiet=false
	hp._hit_iframe = 0.0
	hp.quiet = true
	_hit_events.clear()
	hp.take_damage(1, atk, false)
	eq(_hit_events.size(), 1, "force_quiet=false should emit hit signal even when quiet=true")

	# force_quiet with player involved: player involvement always overrides quiet
	var player_atk := Node2D.new()
	player_atk.add_to_group("player")
	add_child(player_atk)
	await flush(1)

	hp._hit_iframe = 0.0
	_hit_events.clear()
	hp.take_damage(1, player_atk, true)
	eq(_hit_events.size(), 1, "Player attacker still emits hit even if force_quiet=true")

	vic.queue_free()
	atk.queue_free()
	player_atk.queue_free()


func test_rapid_fire_damage_and_iframes() -> void:
	var hp := Health.new()
	hp.max_hp = 100
	add_child(hp)
	await flush(1)

	var land_count := 0
	# Attempt 100 rapid calls to take_damage in the same frame
	for i in 100:
		if hp.take_damage(1):
			land_count += 1
	eq(land_count, 1, "Rapid fire in same frame should only land exactly 1 hit due to iframes")
	eq(hp.current, hp.max_hp - 1, "Only 1 damage should be subtracted")

	# Burn iframes via manual process
	hp._process(hp.hit_iframe_time + 0.05)
	ok(not hp.is_invincible(), "Iframes should have expired")
	ok(hp.take_damage(2), "Next hit should land after iframe expiration")
	eq(hp.current, hp.max_hp - 3)

	# Test grant_iframes
	hp._hit_iframe = 0.0
	hp.grant_iframes(2.0)
	ok(hp.is_invincible(), "grant_iframes should make pool invincible")
	ok(not hp.take_damage(5), "Damage during granted iframes must be rejected")
	# grant_iframes with shorter time should NOT reduce running iframe
	hp.grant_iframes(0.1)
	ok(hp._hit_iframe > 1.5, "grant_iframes must never shorten existing window")

	# Test death latch under rapid fire
	hp._hit_iframe = 0.0
	var died_signals := [0]
	var on_died := func():
		died_signals[0] += 1
	hp.died.connect(on_died)
	var took_deadly := hp.take_damage(hp.max_hp + 50)
	eq(hp.current, 0, "HP should clamp to 0 on death")
	eq(died_signals[0], 1, "died signal should fire once")
	for i in 50:
		ok(not hp.take_damage(1), "Further damage after death must return false")
	eq(died_signals[0], 1, "died signal must NEVER fire multiple times")

	hp.queue_free()


func test_attacker_queue_freed_during_damage_processing() -> void:
	var host := Node2D.new()
	add_child(host)
	var hp := Health.new()
	host.add_child(hp)
	var atk := Node2D.new()
	add_child(atk)
	await flush(1)

	var callback := func(_c, _m):
		if is_instance_valid(atk):
			atk.queue_free()
	hp.changed.connect(callback)
	var ok_hit := hp.take_damage(1, atk)
	ok(ok_hit, "take_damage should handle attacker queue_free during changed callback")
	hp.changed.disconnect(callback)
	host.queue_free()


func test_host_queue_freed_during_damage_processing() -> void:
	var host := Node2D.new()
	add_child(host)
	var hp := Health.new()
	host.add_child(hp)
	await flush(1)

	var callback := func(_c, _m):
		if is_instance_valid(host):
			host.queue_free()
	hp.changed.connect(callback)
	var ok_hit := hp.take_damage(1, null)
	ok(ok_hit, "take_damage should handle host queue_free during changed callback")
	hp.changed.disconnect(callback)


func test_orphan_health_node() -> void:
	var orphan_hp := Health.new()
	var ok_hit := orphan_hp.take_damage(1, null)
	ok(ok_hit, "take_damage on orphan Health node should succeed without crashing")
	orphan_hp.free()


# -----------------------------------------------------------------------------
# 2. Player.arena_depth() and Boundary Clamping & Jump Z Isolation
# -----------------------------------------------------------------------------

func test_arena_depth_boundary_clamping() -> void:
	var rig := Node2D.new()
	rig.name = "DepthRig"
	add_child(rig)
	build_floor(rig, 320.0)
	var player: Player = await spawn_player(rig, Vector2(320, 290))
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()
	player.add_to_group("arena_plane")
	await flush(2)

	# 1. Clamping at DEPTH_BACK (252.0)
	player.global_position = Vector2(400, -1000.0)
	await flush(2)
	almost(player.arena_depth(), ArenaCatalog.DEPTH_BACK, 0.01, "arena_depth clamped to DEPTH_BACK from far negative")
	eq(player.arena_depth(), player.global_position.y, "arena_depth() must match global_position.y")

	# 2. Clamping at DEPTH_FRONT (328.0)
	player.global_position = Vector2(400, 2000.0)
	await flush(2)
	almost(player.arena_depth(), ArenaCatalog.DEPTH_FRONT, 0.01, "arena_depth clamped to DEPTH_FRONT from far positive")
	eq(player.arena_depth(), player.global_position.y, "arena_depth() must match global_position.y")

	# 3. Driving continuously backward beyond boundary (needs ~62 frames at 74px/s to cross 76px band; flush 85 frames)
	player.arena_set_drive(0.0, -1.0, false)
	await flush(85)
	almost(player.arena_depth(), ArenaCatalog.DEPTH_BACK, 0.01, "Continuous backward drive stays clamped at DEPTH_BACK")

	# 4. Driving continuously forward beyond boundary (needs ~62 frames; flush 85 frames)
	player.arena_set_drive(0.0, 1.0, false)
	await flush(85)
	almost(player.arena_depth(), ArenaCatalog.DEPTH_FRONT, 0.01, "Continuous forward drive stays clamped at DEPTH_FRONT")
	player.arena_clear_drive()

	# 5. arena_respawn boundary enforcement
	player.arena_respawn(Vector2(500, 50.0))
	almost(player.arena_depth(), ArenaCatalog.DEPTH_BACK, 0.01, "arena_respawn beyond DEPTH_BACK clamps to DEPTH_BACK")
	player.arena_respawn(Vector2(500, 800.0))
	almost(player.arena_depth(), ArenaCatalog.DEPTH_FRONT, 0.01, "arena_respawn beyond DEPTH_FRONT clamps to DEPTH_FRONT")

	player.remove_from_group("arena_plane")
	player.queue_free()
	rig.queue_free()


func test_jump_z_ground_depth_isolation() -> void:
	var rig := Node2D.new()
	rig.name = "JumpRig"
	add_child(rig)
	build_floor(rig, 320.0)
	var player: Player = await spawn_player(rig, Vector2(320, 290))
	ArenaRun.auto_begin = true
	ArenaRun.activate_for_test()
	player.add_to_group("arena_plane")
	await flush(2)

	var ground_depth := player.arena_depth()
	var initial_global_pos := player.global_position

	# Force various heights and verify depth and ground position remain completely unchanged
	var heights := [0.0, 5.0, 15.0, 25.0, ArenaCatalog.JUMP_Z_MAX]
	for h in heights:
		player.arena_force_z(h)
		eq(player.arena_z(), h, "arena_z should match forced height before physics step")
		if player.visual != null:
			almost(player.visual.position.y, -h, 0.001, "Visual position.y must be lifted by -z")
		var hurt := player.get_node_or_null("Hurtbox") as Node2D
		if hurt != null:
			almost(hurt.position.y, -h, 0.001, "Hurtbox position.y must be lifted by -z")
		if player.melee != null:
			almost(player.melee.position.y, -h, 0.001, "MeleeCombat position.y must be lifted by -z")

		await flush(1)
		almost(player.arena_depth(), ground_depth, 0.0001, "arena_depth must NOT change when z changes (h=%f)" % h)
		eq(player.global_position.y, ground_depth, "global_position.y must remain ground level")
		if player.visual != null:
			almost(player.visual.position.y, -player.arena_z(), 0.001, "Visual position.y tracks -arena_z after step")

	# Over-max height clamping
	player.arena_force_z(9999.0)
	eq(player.arena_z(), ArenaCatalog.JUMP_Z_MAX, "arena_force_z must clamp to JUMP_Z_MAX")

	# Negative height clamping
	player.arena_force_z(-50.0)
	eq(player.arena_z(), 0.0, "arena_force_z must clamp negative values to 0.0")

	# Dynamic jump integration test
	player.arena_force_z(0.0)
	await flush(2)
	player.arena_request_jump()
	var saw_air := false
	var peak_z := 0.0

	for frame in 60:
		await flush(1)
		var cur_z := player.arena_z()
		if cur_z > 0.0:
			saw_air = true
		if cur_z > peak_z:
			peak_z = cur_z
		almost(player.arena_depth(), ground_depth, 0.001, "arena_depth must remain invariant across jump arc (frame %d)" % frame)

	ok(saw_air, "Player should have taken to the air")
	ok(peak_z > 10.0, "Player should have reached significant jump height")
	ok(peak_z <= ArenaCatalog.JUMP_Z_MAX, "Peak z must not exceed JUMP_Z_MAX")
	eq(player.arena_z(), 0.0, "Player should have landed back on the ground after 60 frames")

	player.remove_from_group("arena_plane")
	player.queue_free()
	rig.queue_free()


func test_campaign_mode_physics_isolation() -> void:
	var rig := Node2D.new()
	rig.name = "CampaignRig"
	add_child(rig)
	build_floor(rig, 320.0)
	var player: Player = await spawn_player(rig, Vector2(320, -50))
	ArenaRun.abandon()
	await flush(2)

	# Verify not in arena plane
	ok(not player.is_in_group("arena_plane"), "Not in arena_plane group")
	ok(not player._arena_plane_active(), "_arena_plane_active must be false")
	eq(player.motion_mode, CharacterBody2D.MOTION_MODE_GROUNDED, "Motion mode must be GROUNDED")

	# In campaign mode, arena_request_jump does nothing
	player.arena_request_jump()
	await flush(2)
	eq(player.arena_z(), 0.0, "arena_request_jump must have no effect in campaign mode")

	# Standard gravity applies
	player.global_position = Vector2(320, -100)
	player.velocity = Vector2.ZERO
	await flush(3)
	ok(player.velocity.y > 0.0, "Gravity pulls downward in campaign mode")

	player.queue_free()
	rig.queue_free()
