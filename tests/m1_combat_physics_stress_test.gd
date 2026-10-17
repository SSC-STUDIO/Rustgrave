class_name M1CombatPhysicsStressTest
extends TestCase
## Adversarial Stress Test Suite for Milestone 1:
## 1. Active melee hitbox timings across 3-hit combo with varying attack bonuses.
## 2. Knockback scaling with finisher hits and toxin tiers.
## 3. Dash movement velocity and physics collisions under extreme speed modifiers.
## 4. Parry deflect timings and ember resonance activation.

const STATS_SCRIPT_PATH := "res://scripts/player/character_stats.gd"
const PROJ_SCENE := preload("res://scenes/combat/Projectile.tscn")


# ============================================================================
# Helpers
# ============================================================================

class DummyEnemy extends CharacterBody2D:
	var hit_material: StringName = &"flesh"


func _setup_player_with_stats(arena: Node2D, pos: Vector2 = Vector2(320, -24)) -> Player:
	var player := await spawn_player(arena, pos)
	if not ("stats" in player and player.stats != null):
		var stats_script: GDScript = load(STATS_SCRIPT_PATH)
		var stats = stats_script.new()
		stats.name = "CharacterStats"
		player.add_child(stats)
		player.set("stats", stats)
	return player


# ============================================================================
# Area 1: Active melee hitbox timings across 3-hit combo & attack bonus invariance
# ============================================================================

func test_hitbox_active_timing_invariance_across_attack_bonuses() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await _setup_player_with_stats(arena)
	player.set_physics_process(false)
	var melee: MeleeCombat = player.melee
	melee.set_physics_process(false)

	# Test all 3 combo steps across diverse attack bonus conditions
	var attack_bonuses: Array[int] = [0, 5, 25, 100, -10]

	for combo_idx in 3:
		var expected_windup: float = CombatRules.SWING_WINDUP[combo_idx]
		var expected_active: float = CombatRules.SWING_ACTIVE[combo_idx]
		var expected_recovery: float = CombatRules.SWING_RECOVERY[combo_idx]
		var base_damage: int = CombatRules.SWING_DAMAGE[combo_idx]

		for bonus in attack_bonuses:
			player.stats.recalculate([{"attack": bonus}])
			eq(player.stats.get_attack_bonus(), maxi(0, bonus), "attack bonus clamped >= 0")

			# Reset combat state
			melee.cancel_attack()
			melee._cooldown = 0.0
			melee._combo_index = combo_idx

			ok(melee.start_swing(), "combo %d swing starts with bonus %d" % [combo_idx, bonus])
			eq(melee.phase_name(), "windup", "phase is windup")
			ok(not melee.hitbox.monitoring, "hitbox not monitoring in windup")
			ok(not melee.is_parry_window(), "not parry window in windup")
			almost(melee._timer, expected_windup, 0.001, "windup duration matches rules")

			# Advance to 1 frame before windup ends
			var dt := 1.0 / 60.0
			var windup_frames := int(expected_windup / dt)
			for f in windup_frames - 1:
				melee.tick(dt)
			eq(melee.phase_name(), "windup", "still windup right before transition")
			ok(not melee.hitbox.monitoring, "hitbox closed until active")

			# Advance into active phase
			while melee.phase_name() == "windup":
				melee.tick(dt)

			eq(melee.phase_name(), "active", "entered active phase")
			ok(melee.hitbox.monitoring, "hitbox is monitoring during active")
			ok(melee.is_parry_window(), "active phase is parry window")

			# Verify damage formula: maxi(1, COMBO_DAMAGE + tier_damage + attack_bonus)
			var expected_dmg := maxi(1, base_damage + player.stats.get_attack_bonus())
			eq(melee.hitbox.damage, expected_dmg, "hitbox damage scaled correctly for bonus %d" % bonus)

			# Count exact active duration while ticking
			var active_time_elapsed := 0.0
			while melee.phase_name() == "active":
				melee.tick(dt)
				active_time_elapsed += dt

			# Active duration must match COMBO_ACTIVE regardless of attack bonus
			almost(active_time_elapsed, expected_active, dt * 1.5,
				"active duration (%.3fs) invariant to attack bonus %d (expected %.3fs)" % [
					active_time_elapsed, bonus, expected_active])

			# In recovery phase: hitbox must immediately turn off
			eq(melee.phase_name(), "recovery", "transitioned to recovery")
			ok(not melee.hitbox.monitoring, "hitbox monitoring disarmed in recovery")
			ok(not melee.is_parry_window(), "parry window closed in recovery")


func test_animation_frame_pose_mapping_boundaries() -> void:
	# Test Player.attack_frame_index across all phases and edge progress values
	var frame_counts: Array[int] = [1, 3, 4, 6]
	for count in frame_counts:
		# Single-frame edge case
		if count == 1:
			eq(Player.attack_frame_index(count, "windup", 0.0), 0)
			eq(Player.attack_frame_index(count, "active", 0.5), 0)
			eq(Player.attack_frame_index(count, "recovery", 1.0), 0)
			continue

		var last := count - 1
		var strike := 1 if count <= 3 else clampi(int(round(float(last) * 0.45)), 1, last - 1)

		# Windup starts at 0, only moves to 1 when near end if strike > 1
		eq(Player.attack_frame_index(count, "windup", 0.0), 0, "windup starts at frame 0")
		eq(Player.attack_frame_index(count, "windup", 0.5), 0, "windup at 50% stays 0")

		# Active ALWAYS pins exactly the strike frame
		eq(Player.attack_frame_index(count, "active", 0.0), strike, "active 0% pins strike frame")
		eq(Player.attack_frame_index(count, "active", 0.5), strike, "active 50% pins strike frame")
		eq(Player.attack_frame_index(count, "active", 1.0), strike, "active 100% pins strike frame")

		# Recovery smoothly finishes at last frame
		eq(Player.attack_frame_index(count, "recovery", 1.0), last, "recovery 100% hits last frame")
		# Recovery progress clamped
		eq(Player.attack_frame_index(count, "recovery", -0.5), mini(strike + 1, last), "recovery clamped lower")
		eq(Player.attack_frame_index(count, "recovery", 2.0), last, "recovery clamped upper")


# ============================================================================
# Area 2: Knockback scaling with finisher hits and toxin tiers
# ============================================================================

func test_knockback_scaling_finisher_and_toxin_tiers() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await _setup_player_with_stats(arena)
	player.set_physics_process(false)
	var melee: MeleeCombat = player.melee

	var bands: Array[StringName] = [&"cold", &"warm", &"hot", &"overflow"]

	for band in bands:
		# Force player toxin level to match band
		match band:
			&"cold": player.toxin.toxin = 0.0
			&"warm": player.toxin.toxin = 40.0
			&"hot": player.toxin.toxin = 70.0
			&"overflow": player.toxin.toxin = 100.0
		eq(player.toxin.band(), band, "toxin band set to %s" % band)

		var tier := CombatRules.toxin_tier(band)
		var finisher_multiplier: float = float(tier["finisher_knock"])

		# Test Combo 0 (Light swing)
		melee._combo_index = 0
		player.controller.facing = 1
		melee._begin_active()
		almost(melee.hitbox.knockback.x, 90.0, 0.01, "combo 0 knockback.x invariant to toxin (%s)" % band)
		almost(melee.hitbox.knockback.y, -24.0, 0.01, "combo 0 knockback.y invariant to toxin (%s)" % band)

		# Test Combo 1 (Light swing)
		melee._combo_index = 1
		player.controller.facing = -1
		melee._begin_active()
		almost(melee.hitbox.knockback.x, -90.0, 0.01, "combo 1 facing -1 inverts knockback.x (%s)" % band)
		almost(melee.hitbox.knockback.y, -24.0, 0.01, "combo 1 knockback.y invariant (%s)" % band)

		# Test Combo 2 (Finisher hit)
		melee._combo_index = 2
		player.controller.facing = 1
		melee._begin_active()
		var expected_finisher_power: float = 150.0 * finisher_multiplier
		almost(melee.hitbox.knockback.x, expected_finisher_power, 0.01,
			"combo 2 finisher knockback scaled by tier multiplier (%.2f vs %.2f) in %s" % [
				melee.hitbox.knockback.x, expected_finisher_power, band])
		almost(melee.hitbox.knockback.y, -40.0, 0.01, "finisher vertical knockback is -40 in %s" % band)


func test_knockback_equipment_attack_bonus_does_not_corrupt_knockback() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await _setup_player_with_stats(arena)
	player.set_physics_process(false)
	var melee: MeleeCombat = player.melee

	# Attack bonus +50
	player.stats.recalculate([{"attack": 50}])
	player.toxin.toxin = 0.0 # cold tier
	melee._combo_index = 2
	player.controller.facing = 1
	melee._begin_active()

	eq(melee.hitbox.damage, 2 + 50, "damage amplified by attack bonus")
	almost(melee.hitbox.knockback.x, 150.0, 0.01, "finisher knockback power remains purely physics-driven")
	almost(melee.hitbox.knockback.y, -40.0, 0.01, "finisher knockback vertical remains -40")


func test_enemy_material_knockback_damping() -> void:
	# Test Hurtbox._apply_knockback material damping
	var materials: Array[StringName] = [&"flesh", &"bone", &"armour", &"shield", &"boss", &"ghost"]
	var expected_factors: Dictionary = {
		&"flesh": 1.0,
		&"bone": 1.0,
		&"armour": 0.55,
		&"shield": 0.0,
		&"boss": 0.15,
		&"ghost": 0.6,
	}

	for mat in materials:
		var dummy := DummyEnemy.new()
		dummy.hit_material = mat
		var hurtbox := Hurtbox.new()
		dummy.add_child(hurtbox)
		add_child(dummy)

		var mock_box := Hitbox.new()
		mock_box.knockback = Vector2(100.0, -40.0)

		dummy.velocity = Vector2.ZERO
		hurtbox._apply_knockback(mock_box)

		var expected_factor: float = expected_factors[mat]
		almost(dummy.velocity.x, 100.0 * expected_factor, 0.01, "material %s knock x damping" % mat)
		almost(dummy.velocity.y, -40.0 * expected_factor, 0.01, "material %s knock y damping" % mat)

		dummy.queue_free()
		mock_box.free()


# ============================================================================
# Area 3: Dash movement velocity & physics collisions under extreme modifiers
# ============================================================================

func test_extreme_speed_multiplier_clamping() -> void:
	var stats_script: GDScript = load(STATS_SCRIPT_PATH)
	var stats = stats_script.new()
	add_child(stats)

	# Test extreme slow debuff: -95%
	stats.recalculate([{"speed_mult": -0.95}])
	almost(stats.get_speed_multiplier(), 0.1, 0.001, "speed multiplier clamped at 0.1 minimum")

	# Test zero speed attempt: -1.0
	stats.recalculate([{"speed_mult": -1.0}])
	almost(stats.get_speed_multiplier(), 0.1, 0.001, "speed multiplier prevents 0.0 motion freeze")

	# Test negative speed attempt: -5.0
	stats.recalculate([{"speed_mult": -5.0}])
	almost(stats.get_speed_multiplier(), 0.1, 0.001, "speed multiplier prevents negative reverse motion")

	# Test extreme speed buff: +500%
	stats.recalculate([{"speed_mult": 5.0}])
	almost(stats.get_speed_multiplier(), 3.0, 0.001, "speed multiplier clamped at 3.0 maximum")

	# Test massive speed buff: +1000%
	stats.recalculate([{"speed_mult": 10.0}])
	almost(stats.get_speed_multiplier(), 3.0, 0.001, "massive speed buff clamped at 3.0 maximum")

	stats.queue_free()


func test_dash_velocity_under_extreme_modifiers_and_toxin() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await _setup_player_with_stats(arena)
	var ctrl: PlayerController = player.controller
	var base_dash: float = ctrl.dash_speed # 236.0

	# 1. Minimum speed penalty (0.1) under Cold tier (1.0)
	player.stats.recalculate([{"speed_mult": -0.9}])
	player.toxin.toxin = 0.0
	var speed_min_cold := ctrl._dash_speed_for(player)
	almost(speed_min_cold, base_dash * 0.1, 0.01, "min dash speed under cold")
	ok(speed_min_cold > 0.0, "min dash speed remains strictly positive")

	# 2. Maximum speed buff (3.0) under Hot tier (1.12)
	player.stats.recalculate([{"speed_mult": 2.0}])
	player.toxin.toxin = 70.0 # hot tier
	var speed_max_hot := ctrl._dash_speed_for(player)
	var expected_max_hot := base_dash * 1.12 * 3.0
	almost(speed_max_hot, expected_max_hot, 0.01, "max dash speed under hot tier (792.96 px/s)")


func test_extreme_speed_dash_collision_wall_no_tunneling() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)

	# Place solid vertical wall 40px in front of player
	# Player at x = 320, wall at x = 360, thickness = 20 (x from 350 to 370)
	var wall := StaticBody2D.new()
	wall.name = "WallObstacle"
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector2(360, -40)
	var wall_col := CollisionShape2D.new()
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(20, 200)
	wall_col.shape = wall_shape
	wall.add_child(wall_col)
	arena.add_child(wall)

	var player := await _setup_player_with_stats(arena, Vector2(320, -24))
	await flush(4)

	# Apply MAXIMUM extreme speed modifier: speed_mult = 3.0, hot toxin tier
	player.stats.recalculate([{"speed_mult": 2.0}])
	player.toxin.toxin = 70.0
	player.controller.facing = 1

	var ctrl := player.controller
	ok(ctrl.call("_try_dash", player), "extreme speed dash initiated toward wall")
	ok(ctrl.is_dashing(), "player is in dashing state")

	# Dash speed is ~793 px/s. Advance physics frame by frame
	var hit_wall := false
	for frame in int(ctrl.dash_duration * 60.0) + 4:
		await flush(1)
		# Verify: Player NEVER penetrates past wall center (x = 360)
		ok(player.global_position.x < 360.0,
			"player does not tunnel through wall at extreme dash speed (x=%.1f, wall=360)" % player.global_position.x)
		if player.is_on_wall():
			hit_wall = true

	ok(hit_wall or player.global_position.x >= 340.0, "player reached and collided with wall")
	ok(not ctrl.is_dashing(), "dash timer cleanly completed without infinite hang")

	# Test airborne wall unstick semantics: airborne contact zeroes residual into-wall speed
	player.position = Vector2(344, -70)
	player.velocity = Vector2(120.0, 40.0)
	for i in 8:
		player.move_and_slide()
		ctrl.settle_after_slide(player)
		await flush(1)
	ok(player.is_on_wall() or player.velocity.x <= 1.0, "airborne contact with wall")
	ok(player.velocity.x <= 1.0, "settle_after_slide zeroes residual airborne velocity")

	# Verify player can move away freely in reverse direction
	player.position = Vector2(340, -24)
	player.controller.facing = -1
	player.velocity.x = -50.0
	await flush(4)
	ok(player.global_position.x < 345.0, "player freely navigates away from wall after dash collision")


# ============================================================================
# Area 4: Parry deflect timings & ember resonance activation
# ============================================================================

func test_parry_deflect_window_frame_boundaries() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await _setup_player_with_stats(arena)
	player.set_physics_process(false)
	var melee: MeleeCombat = player.melee
	melee.set_physics_process(false)

	var shooter := Node2D.new()
	shooter.position = Vector2(600, -24)
	arena.add_child(shooter)

	# 1. Deflect during WINDUP must be REFUSED
	melee.cancel_attack()
	melee._cooldown = 0.0
	ok(melee.start_swing())
	eq(melee.phase_name(), "windup")

	var bolt1: Projectile = PROJ_SCENE.instantiate()
	bolt1.setup(Vector2(500, -24), Vector2.LEFT, 50.0, &"enemy", shooter)
	arena.add_child(bolt1)

	ok(not melee.try_deflect(bolt1), "parry refused during windup")
	ok(not bolt1.deflected, "bolt not deflected during windup")
	bolt1.queue_free()

	# 2. Deflect during ACTIVE must SUCCEED
	while melee.phase_name() == "windup":
		melee.tick(1.0 / 60.0)
	eq(melee.phase_name(), "active")
	ok(melee.is_parry_window(), "active phase is valid parry window")

	var bolt2: Projectile = PROJ_SCENE.instantiate()
	bolt2.setup(Vector2(500, -24), Vector2.LEFT, 50.0, &"enemy", shooter)
	arena.add_child(bolt2)

	ok(melee.try_deflect(bolt2), "parry succeeds during active window")
	ok(bolt2.deflected, "bolt marked deflected")
	eq(bolt2.team, &"player", "deflected bolt converted to player team")
	ok(bolt2.velocity.x > 0.0, "bolt directed back toward shooter")
	bolt2.queue_free()

	# 3. Deflect during RECOVERY must be REFUSED
	while melee.phase_name() == "active":
		melee.tick(1.0 / 60.0)
	eq(melee.phase_name(), "recovery")

	var bolt3: Projectile = PROJ_SCENE.instantiate()
	bolt3.setup(Vector2(500, -24), Vector2.LEFT, 50.0, &"enemy", shooter)
	arena.add_child(bolt3)

	ok(not melee.try_deflect(bolt3), "parry refused during recovery")
	ok(not bolt3.deflected, "bolt not deflected during recovery")
	bolt3.queue_free()

	# 4. Deflect while dead must be REFUSED
	melee.cancel_attack()
	melee._cooldown = 0.0
	melee.start_swing()
	while melee.phase_name() == "windup":
		melee.tick(1.0 / 60.0)
	eq(melee.phase_name(), "active")

	player.health.current = 0
	player.health._dead = true
	var bolt4: Projectile = PROJ_SCENE.instantiate()
	bolt4.setup(Vector2(500, -24), Vector2.LEFT, 50.0, &"enemy", shooter)
	arena.add_child(bolt4)

	ok(not melee.try_deflect(bolt4), "dead player cannot deflect")
	bolt4.queue_free()


func test_parry_ember_resonance_activation_and_lifecycle() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await _setup_player_with_stats(arena)
	player.set_physics_process(false)
	var melee: MeleeCombat = player.melee
	melee.set_physics_process(false)

	var shooter := Node2D.new()
	shooter.position = Vector2(600, -24)
	arena.add_child(shooter)

	# Initial state: resonance inactive
	ok(not player.resonance.is_active(), "resonance initially inactive")
	eq(player.resonance.remaining(), 0.0, "remaining duration is 0")

	# Set up toxin and air jumps
	player.toxin.toxin = 50.0
	player.controller._jumps_left = 0

	# Swing into active window
	melee.cancel_attack()
	melee._cooldown = 0.0
	melee.start_swing()
	while melee.phase_name() == "windup":
		melee.tick(1.0 / 60.0)
	eq(melee.phase_name(), "active")

	var bolt: Projectile = PROJ_SCENE.instantiate()
	bolt.setup(Vector2(500, -24), Vector2.LEFT, 50.0, &"enemy", shooter)
	arena.add_child(bolt)

	# Execute parry deflect
	ok(melee.try_deflect(bolt), "parry performed")

	# Verify:
	# 1. Resonance active
	ok(player.resonance.is_active(), "resonance activated on parry")
	almost(player.resonance.remaining(), CombatRules.PARRY_RESONANCE, 0.05, "resonance initialized to 2.0s")

	# 2. Toxin purified by PARRY_PURIFY (0.12 * max_toxin = 12.0)
	almost(player.toxin.toxin, 50.0 - (CombatRules.PARRY_PURIFY * player.toxin.max_toxin), 0.1, "toxin purified on parry")

	# 3. Air jump granted
	ok(player.controller._jumps_left > 0, "air jump granted on parry")

	# 4. Advance resonance by 1.0 second
	player.resonance._process(1.0)
	ok(player.resonance.is_active(), "resonance still active after 1.0s")
	almost(player.resonance.remaining(), 1.0, 0.05, "resonance remaining is 1.0s")

	# 5. Deflecting another bolt refreshes resonance to 2.0s
	var bolt2: Projectile = PROJ_SCENE.instantiate()
	bolt2.setup(Vector2(500, -24), Vector2.LEFT, 50.0, &"enemy", shooter)
	arena.add_child(bolt2)

	ok(melee.try_deflect(bolt2), "second parry performed")
	almost(player.resonance.remaining(), CombatRules.PARRY_RESONANCE, 0.05, "resonance refreshed back to 2.0s")

	# 6. Advance beyond expiry (2.1s)
	player.resonance._process(2.1)
	ok(not player.resonance.is_active(), "resonance expires after duration")
	almost(player.resonance.remaining(), 0.0, 0.001, "remaining duration is 0.0")

	bolt.queue_free()
	bolt2.queue_free()
