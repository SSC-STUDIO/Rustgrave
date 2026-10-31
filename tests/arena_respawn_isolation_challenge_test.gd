extends TestCase
## Empirical Challenger adversarial stress test suite for Player.arena_respawn
## and campaign physics isolation.

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

var _respawn_signal_count: int = 0


func setup() -> void:
	if get_tree().paused:
		get_tree().paused = false
	ArenaRun.auto_begin = false
	ArenaRun.abandon()
	_respawn_signal_count = 0


func teardown() -> void:
	ArenaRun.auto_begin = false
	ArenaRun.abandon()
	_respawn_signal_count = 0


func _on_respawn_event() -> void:
	_respawn_signal_count += 1


func _setup_rig() -> Dictionary:
	var rig := Node2D.new()
	rig.name = "ChallengeRig"
	add_child(rig)
	build_floor(rig, 320.0)
	var player := await spawn_player(rig, Vector2(320, -24))
	return {"rig": rig, "player": player}


## 1. Verify arena_respawn cleanly resets all states, health, iframes, and emits signal
func test_arena_respawn_full_state_reset() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	GameEvents.player_respawned.connect(_on_respawn_event)

	# Mess up all internal states into dirty/in-flight values
	player.velocity = Vector2(345.0, -190.0)
	player.set("_arena_z", 22.5)
	player.set("_arena_vz", 85.0)
	player.set("_arena_jump_queued", true)
	player.health.current = 1
	player.health.invincible = true
	player.controller._dash_timer = 0.2
	player.controller.facing = -1
	player.collision_layer = 0
	player.collision_mask = 0
	player.visible = false
	var hurt: Hurtbox = player.get_node_or_null("Hurtbox") as Hurtbox
	if hurt != null:
		hurt.monitorable = false
	player.set_physics_process(false)
	player.set_process(false)
	player.melee.start_swing()

	# Apply lift so visual/melee/hurtbox are displaced
	player.call("_arena_apply_lift")
	ok(player.visual.position.y < -20.0, "Visual displaced before respawn")

	var target_pos := Vector2(500.0, 220.0)
	player.arena_respawn(target_pos)

	# Assertions on post-respawn state
	eq(_respawn_signal_count, 1, "GameEvents.player_respawned emitted exactly once")
	almost(player.global_position.x, target_pos.x, 0.01, "Position X set to target")
	almost(player.global_position.y, target_pos.y, 0.01, "Position Y set to target (not in arena_plane)")
	eq(player.velocity, Vector2.ZERO, "Velocity cleanly zeroed")
	almost(player.arena_z(), 0.0, 0.001, "_arena_z reset to zero")
	almost(float(player.get("_arena_vz")), 0.0, 0.001, "_arena_vz reset to zero")
	eq(bool(player.get("_arena_jump_queued")), false, "Jump queue reset")
	eq(player.health.current, player.health.max_hp, "Restored to full HP")
	eq(player.health.invincible, false, "Manual health.invincible flag reset")
	ok(player.health.is_invincible(), "health.is_invincible() is true due to hit iframe")
	almost(player.controller._iframe, 1.2, 0.01, "controller iframe initialized to 1.2s")
	almost(player.controller._dash_timer, 0.0, 0.001, "controller dash timer reset")
	eq(player.collision_layer, 2, "collision_layer restored to 2")
	eq(player.collision_mask, 1, "collision_mask restored to 1")
	ok(player.visible, "Player visibility restored")
	ok(player.is_physics_processing(), "Physics processing re-enabled")
	ok(player.is_processing(), "Process re-enabled")
	if hurt != null:
		ok(hurt.monitorable, "Hurtbox monitorable restored")
	eq(player.melee.phase_name(), "idle", "Melee attack cancelled back to idle")

	# Check lift reset on visual nodes
	almost(player.visual.position.y, 0.0, 0.01, "Visual position Y reset to 0")
	almost(player.melee.position.y, 0.0, 0.01, "Melee position Y reset to 0")
	if hurt != null:
		almost(hurt.position.y, 0.0, 0.01, "Hurtbox position Y reset to 0")

	GameEvents.player_respawned.disconnect(_on_respawn_event)
	rig.queue_free()
	await flush(2)


## 2. Verify depth clamping when in arena_plane group vs free coordinate when outside
func test_arena_respawn_depth_clamping() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	# A: In group arena_plane -> Y must clamp to ArenaCatalog band
	player.add_to_group("arena_plane")

	# Overshoot forward
	player.arena_respawn(Vector2(400.0, ArenaCatalog.DEPTH_FRONT + 999.0))
	almost(player.global_position.y, ArenaCatalog.DEPTH_FRONT, 0.05, "Clamped to front band edge")

	# Overshoot backward
	player.arena_respawn(Vector2(400.0, ArenaCatalog.DEPTH_BACK - 999.0))
	almost(player.global_position.y, ArenaCatalog.DEPTH_BACK, 0.05, "Clamped to back band edge")

	# Normal valid depth
	var mid_y := (ArenaCatalog.DEPTH_FRONT + ArenaCatalog.DEPTH_BACK) * 0.5
	player.arena_respawn(Vector2(400.0, mid_y))
	almost(player.global_position.y, mid_y, 0.05, "Valid depth preserved within band")

	# B: NOT in group arena_plane -> Y is not clamped
	player.remove_from_group("arena_plane")
	var free_y := -450.0
	player.arena_respawn(Vector2(400.0, free_y))
	almost(player.global_position.y, free_y, 0.05, "Outside arena_plane: Y not clamped")

	rig.queue_free()
	await flush(2)


## 3. Verify 1.2s iframe protection window and graceful expiration
func test_arena_respawn_iframe_protection_and_expiry() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	player.arena_respawn(Vector2(320.0, 0.0))
	var hp := player.health
	eq(hp.current, hp.max_hp, "Full health after respawn")

	# Damage attempted immediately during iframes must be rejected
	var damaged_immediate := hp.take_damage(2)
	ok(not damaged_immediate, "take_damage rejected during iframe window")
	eq(hp.current, hp.max_hp, "HP unaffected during iframe window")

	# Step time through 1.3 seconds (78 frames at 60Hz)
	var dt := 1.0 / 60.0
	for i in 78:
		hp._process(dt)
		if player.is_physics_processing():
			player.controller._iframe = maxf(0.0, player.controller._iframe - dt)

	ok(not hp.is_invincible(), "Invincibility expired after 1.3 seconds")
	almost(player.controller._iframe, 0.0, 0.001, "Controller iframe expired")

	# Damage attempted now must succeed
	var damaged_later := hp.take_damage(2)
	ok(damaged_later, "take_damage succeeds after iframes expire")
	eq(hp.current, hp.max_hp - 2, "HP correctly decremented after iframe expiry")

	rig.queue_free()
	await flush(2)


## 4. Verify clearing of campaign DeathOverlay veil and resilience when missing
func test_arena_respawn_clears_death_overlay() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	# Inject a simulated DeathOverlay into root
	var overlay := ColorRect.new()
	overlay.name = "DeathOverlay"
	overlay.visible = true
	overlay.modulate = Color(1, 1, 1, 1)
	get_tree().root.add_child(overlay)

	# Call respawn
	player.arena_respawn(Vector2(320.0, 0.0))

	# Verify overlay was hidden and faded out
	eq(overlay.visible, false, "DeathOverlay made invisible")
	almost(overlay.modulate.a, 0.0, 0.001, "DeathOverlay modulate.a set to 0.0")

	overlay.queue_free()
	await flush(1)

	# Verify calling arena_respawn when DeathOverlay does NOT exist is completely safe
	player.arena_respawn(Vector2(320.0, 0.0))
	ok(true, "arena_respawn survived cleanly without DeathOverlay node")

	rig.queue_free()
	await flush(2)


## 5. Verify calling arena_respawn when not inside tree is safely guarded
func test_arena_respawn_not_in_tree_safety() -> void:
	const PLAYER := preload("res://scenes/player/Player.tscn")
	var orphan: Player = PLAYER.instantiate()
	ok(not orphan.is_inside_tree(), "Player not added to tree")

	# Should return early cleanly without crashing or throwing errors
	orphan.arena_respawn(Vector2(100.0, 100.0))
	ok(true, "Orphan arena_respawn returned safely")

	orphan.free()


## 6. Stress harness: 100 consecutive rapid respawns without state corruption or node leak
func test_arena_respawn_stress_and_leak_resistance() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	player.add_to_group("arena_plane")
	var start_nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	for i in 100:
		var x := 100.0 + float(i % 20) * 10.0
		var y := ArenaCatalog.DEPTH_BACK + float(i % 15) * 4.0
		player.velocity = Vector2(float(i * 10), -float(i * 5))
		player.set("_arena_z", float(i % 30))
		player.health.current = 1 if (i % 2 == 0) else 0

		player.arena_respawn(Vector2(x, y))

		eq(player.velocity, Vector2.ZERO, "Iter %d: velocity zeroed" % i)
		almost(player.arena_z(), 0.0, 0.001, "Iter %d: arena_z zeroed" % i)
		eq(player.health.current, player.health.max_hp, "Iter %d: full health" % i)

	var end_nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	# Node count difference should be minimal (no leaking timer/nodes on each call)
	ok(absf(end_nodes - start_nodes) < 5.0, "Node count stable after 100 respawns (diff: %d)" % int(end_nodes - start_nodes))

	rig.queue_free()
	await flush(2)


## 7. Campaign Physics Isolation: verify normal grounded gravity and movement when not in arena
func test_campaign_physics_isolation_normal_gravity_and_movement() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	ok(not ArenaRun.active(), "ArenaRun inactive")
	ok(not player.is_in_group("arena_plane"), "Not in arena_plane")

	# Drop airborne player
	player.global_position = Vector2(320.0, -80.0)
	player.velocity = Vector2.ZERO

	# Let gravity act for 20 frames
	await flush(20)

	ok(player.velocity.y > 0.0 or player.is_on_floor(), "Downward campaign acceleration")
	
	# Wait for landing on the floor (y == 0.0)
	await flush(30)
	ok(player.is_on_floor(), "Player landed on campaign floor")
	almost(player.global_position.y, 0.0, 2.5, "Resting on fixture floor surface")
	eq(player.motion_mode, CharacterBody2D.MOTION_MODE_GROUNDED, "Motion mode is GROUNDED")
	eq(player.collision_mask, 1, "Collision mask is 1")
	almost(player.arena_z(), 0.0, 0.001, "arena_z is 0 in campaign")

	rig.queue_free()
	await flush(2)


## 8. Campaign Physics Isolation: arena request jump and arena drive are completely ignored
func test_campaign_physics_ignores_arena_jump_and_drive() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	await flush(10)
	ok(player.is_on_floor(), "Player settled on floor")
	var initial_y := player.global_position.y

	# Drive and jump calls
	player.arena_request_jump()
	player.arena_set_drive(1.0, 1.0, true)

	await flush(10)

	# Verify neither depth nor z changed
	almost(player.arena_z(), 0.0, 0.001, "arena_request_jump ignored in campaign")
	almost(player.visual.position.y, 0.0, 0.001, "visual.position.y unaffected")
	almost(player.global_position.y, initial_y, 1.0, "arena_set_drive ignored in campaign")

	rig.queue_free()
	await flush(2)


## 9. Mode switch and cutscene exit: clean restoration of motion_mode, mask, and lift offsets
func test_clean_plane_exit_on_mode_switch_or_cutscene() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	player.add_to_group("arena_plane")
	ArenaRun.activate_for_test()
	ok(ArenaRun.active(), "ArenaRun active")

	# Put into airborne arena state
	player.arena_force_z(30.0)
	player.call("_arena_enter_plane")
	almost(player.arena_z(), 30.0, 0.001, "arena_z forced to 30")
	almost(player.visual.position.y, -30.0, 0.001, "visual offset applied")
	eq(player.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING, "Floating in arena plane")
	eq(player.collision_mask, 0, "Collision mask 0 in arena plane")

	# Now abandon arena (mode switch back to campaign)
	ArenaRun.abandon()
	ok(not ArenaRun.active(), "ArenaRun abandoned")

	# Flush 1 physics frame to let _physics_process run _arena_exit_plane()
	await flush(2)

	eq(player.motion_mode, CharacterBody2D.MOTION_MODE_GROUNDED, "Motion mode restored to GROUNDED")
	eq(player.collision_mask, 1, "Collision mask restored to 1")
	almost(player.floor_snap_length, 4.0, 0.001, "Floor snap restored to 4.0")
	almost(player.arena_z(), 0.0, 0.001, "arena_z restored to 0")
	almost(player.visual.position.y, 0.0, 0.001, "visual position Y restored to 0")
	almost(player.melee.position.y, 0.0, 0.001, "melee position Y restored to 0")

	# Next test: cutscene lock while in arena
	ArenaRun.activate_for_test()
	player.arena_force_z(25.0)
	player.call("_arena_enter_plane")
	almost(player.visual.position.y, -25.0, 0.001)

	player.cutscene_locked = true
	await flush(2)

	eq(player.motion_mode, CharacterBody2D.MOTION_MODE_GROUNDED, "Cutscene forces GROUNDED")
	eq(player.collision_mask, 1, "Cutscene forces mask 1")
	almost(player.arena_z(), 0.0, 0.001, "Cutscene forces arena_z 0")
	almost(player.visual.position.y, 0.0, 0.001, "Cutscene forces visual lift 0")

	rig.queue_free()
	await flush(2)


## 10. Verify arena death leaves no lingering campaign timers and arena_respawn cleanly revives
func test_arena_death_and_respawn_lifecycle() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	player.add_to_group("arena_plane")
	ArenaRun.activate_for_test()
	ok(ArenaRun.active(), "ArenaRun active")

	# Start an attack and jump
	player.melee.start_swing()
	player.arena_force_z(15.0)

	# Take fatal damage in arena
	var died_state := [false]
	var died_cb := func(): died_state[0] = true
	GameEvents.player_died.connect(died_cb)

	player.health.take_damage(999)
	await flush(1)

	ok(died_state[0], "GameEvents.player_died emitted on arena death")
	eq(player.health.current, 0, "Player HP at 0")
	eq(player.collision_layer, 0, "Collision layer cleared on arena death")
	ok(not player.is_physics_processing(), "Physics processing stopped on death")
	eq(player.melee.phase_name(), "idle", "Melee attack cancelled on arena death")
	var hurt: Hurtbox = player.get_node_or_null("Hurtbox") as Hurtbox
	if hurt != null:
		eq(hurt.monitorable, false, "Hurtbox monitorable cleared on death")

	# Critical: verify _respawn_wait timer was NOT instantiated (which would leak campaign reload)
	eq(player.get("_respawn_wait"), null, "No campaign _respawn_wait timer created")

	# Now respawn the player
	player.arena_respawn(Vector2(250.0, ArenaCatalog.GROUND_Y))

	eq(player.health.current, player.health.max_hp, "HP restored to full")
	eq(player.collision_layer, 2, "Collision layer restored to 2")
	ok(player.is_physics_processing(), "Physics processing restarted")
	if hurt != null:
		eq(hurt.monitorable, true, "Hurtbox monitorable restored")

	# Await over 1.2 seconds of frames (80 frames) to ensure no pending timer fires
	await flush(80)
	eq(player.get("_respawn_wait"), null, "Still no campaign respawn timer after wait")
	ok(is_instance_valid(player), "Player remains valid in scene")

	GameEvents.player_died.disconnect(died_cb)
	rig.queue_free()
	await flush(2)


## 11. Repeated fatal kill-and-respawn cycles under arena conditions
func test_repeated_kill_and_respawn_cycle() -> void:
	var fixture := await _setup_rig()
	var rig: Node2D = fixture["rig"]
	var player: Player = fixture["player"]

	player.add_to_group("arena_plane")
	ArenaRun.activate_for_test()

	for cycle in 15:
		# Kill player
		player.health.invincible = false
		player.health.set("_hit_iframe", 0.0)
		player.health.set("_dead", false)
		player.health.take_damage(50)
		eq(player.health.current, 0, "Cycle %d: player killed" % cycle)
		ok(not player.is_physics_processing(), "Cycle %d: physics stopped" % cycle)

		# Respawn player
		player.arena_respawn(Vector2(320.0, ArenaCatalog.GROUND_Y))
		eq(player.health.current, player.health.max_hp, "Cycle %d: revived with full HP" % cycle)
		ok(player.is_physics_processing(), "Cycle %d: physics restored" % cycle)
		await flush(2)

	rig.queue_free()
	await flush(2)

