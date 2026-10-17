class_name M1StressChallengeTest
extends TestCase
## Adversarial Stress & Edge Case Challenge Test Suite for Milestone 1.
## Formally challenges:
## 1. Overwhelming defense (999 def vs 1 dmg -> strictly floors at 1 damage, not 0, not negative).
## 2. Toxin resistance overflow (resist = 1.5 -> clamped to <= 0.8, never granting 100% immunity).
## 3. Speed modifier extremes (negative / 0.0 -> clamped to >= 0.1, preventing freeze / reversal).
## 4. Dead player manipulation (recalculate / equip / max_hp change on dead player -> never revives).
## 5. Non-player defense isolation and attack boundary clamping.

const STATS_SCRIPT_PATH := "res://scripts/player/character_stats.gd"


func _create_stats() -> CharacterStats:
	var script: GDScript = load(STATS_SCRIPT_PATH)
	return script.new() as CharacterStats


# ---------------------------------------------------------------------------
# Stress Test 1: Overwhelming Defense Boundaries
# ---------------------------------------------------------------------------

func test_adversarial_overwhelming_defense_vs_one_damage() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Equip overwhelming defense: 999 defense
	player.stats.recalculate([{"defense": 999}])
	eq(player.stats.get_defense_reduction(), 999, "effective defense reduction is 999")

	# 1 raw damage vs 999 defense -> must strictly floor at 1 damage
	player.health.current = 5
	var hit_applied := player.health.take_damage(1, null)
	ok(hit_applied, "hit was applied")
	eq(player.health.current, 4, "player took exactly 1 damage (not 0, not negative)")

	# Reset iframes for next hit
	player.health._hit_iframe = 0.0

	# 2 raw damage vs 999 defense -> must strictly floor at 1 damage
	hit_applied = player.health.take_damage(2, null)
	ok(hit_applied, "hit was applied")
	eq(player.health.current, 3, "player took exactly 1 damage from 2 raw damage")

	player.health._hit_iframe = 0.0

	# 999 raw damage vs 999 defense -> 999 - 999 = 0 -> floors at 1 damage
	hit_applied = player.health.take_damage(999, null)
	ok(hit_applied, "hit was applied")
	eq(player.health.current, 2, "player took exactly 1 damage from 999 raw damage")

	player.health._hit_iframe = 0.0

	# 1000 raw damage vs 999 defense -> 1000 - 999 = 1 damage
	hit_applied = player.health.take_damage(1000, null)
	ok(hit_applied, "hit was applied")
	eq(player.health.current, 1, "player took exactly 1 damage from 1000 raw damage")

	player.health._hit_iframe = 0.0

	# 0 raw damage -> take_damage must reject and return false
	hit_applied = player.health.take_damage(0, null)
	ok(not hit_applied, "0 raw damage rejected")
	eq(player.health.current, 1, "current hp unchanged on 0 damage")

	# Negative raw damage -> take_damage must reject and return false
	hit_applied = player.health.take_damage(-10, null)
	ok(not hit_applied, "negative raw damage rejected")
	eq(player.health.current, 1, "current hp unchanged on negative damage")

	# Toxin overflow tick with 999 defense -> must still deal 1 damage to player
	player.health._hit_iframe = 0.0
	player._on_toxin_overflow()
	eq(player.health.current, 0, "toxin overflow dealt 1 damage despite 999 defense, killing player")
	ok(player.health._dead, "player is dead from toxin overflow")

	arena.queue_free()


func test_adversarial_enemy_does_not_inherit_player_defense() -> void:
	# An enemy health pool should take full unmitigated damage
	var enemy := CharacterBody2D.new()
	var enemy_health := Health.new()
	enemy_health.name = "Health"
	enemy_health.max_hp = 10
	enemy.add_child(enemy_health)
	add_child(enemy)

	enemy_health.take_damage(4, null)
	eq(enemy_health.current, 6, "enemy takes full 4 damage unmitigated by any player defense logic")

	enemy.queue_free()


# ---------------------------------------------------------------------------
# Stress Test 2: Toxin Resistance Overflow and Extremes
# ---------------------------------------------------------------------------

func test_adversarial_toxin_resistance_overflow_never_grants_immunity() -> void:
	var stats := _create_stats()
	add_child(stats)

	# Extreme overflow resistance: 1.5 (150%)
	stats.recalculate([{"toxin_resist": 1.5}])
	almost(stats.get_toxin_resistance(), 0.8, 0.0001, "1.5 resistance clamped strictly to 0.8")

	# Massive overflow: 1000.0 (100,000%)
	stats.recalculate([{"toxin_resist": 1000.0}])
	almost(stats.get_toxin_resistance(), 0.8, 0.0001, "1000.0 resistance clamped strictly to 0.8")

	# Negative resistance: -5.0 (cursed debuff)
	stats.recalculate([{"toxin_resist": -5.0}])
	almost(stats.get_toxin_resistance(), 0.0, 0.0001, "-5.0 resistance clamped strictly to 0.0")

	# Negative decay: -10.0
	stats.recalculate([{"toxin_decay": -10.0}])
	almost(stats.get_toxin_decay_bonus(), 0.0, 0.0001, "negative decay clamped strictly to 0.0")

	stats.queue_free()


func test_adversarial_toxin_meter_live_resistance_overflow() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Equip 150% toxin resistance
	player.stats.recalculate([{"toxin_resist": 1.5}])
	almost(player.toxin._get_toxin_resistance(), 0.8, 0.001, "meter clamps resistance to 0.8")

	# Raw expose 100.0 -> player MUST still receive at least 20.0 toxin (never 0.0 immunity)
	player.toxin.expose(100.0)
	almost(player.toxin.toxin, 20.0, 0.01, "at 1.5 input resist, player still receives 20% exposure (20.0)")

	# Exposing 4 more times of 100.0 -> reaches full 100.0 toxin and triggers overflow
	for i in range(4):
		player.toxin.expose(100.0)
	almost(player.toxin.toxin, 100.0, 0.01, "accumulates to full 100.0 toxin despite massive resistance")
	ok(player.toxin.is_full(), "meter is full and enters overflow")

	arena.queue_free()


# ---------------------------------------------------------------------------
# Stress Test 3: Speed Modifier Extremes (Anti-Freeze / Anti-Reversal)
# ---------------------------------------------------------------------------

func test_adversarial_speed_modifier_extremes_anti_freeze_and_reversal() -> void:
	var stats := _create_stats()
	add_child(stats)

	# Severe weight penalty: -1.0 (cancels base 1.0)
	stats.recalculate([{"speed_mult": -1.0}])
	almost(stats.get_speed_multiplier(), 0.1, 0.0001, "-1.0 penalty clamped to 0.1 minimum")

	# Massive negative: -999.0
	stats.recalculate([{"speed_mult": -999.0}])
	almost(stats.get_speed_multiplier(), 0.1, 0.0001, "-999.0 penalty clamped to 0.1 minimum")

	# Massive positive: +999.0
	stats.recalculate([{"speed_mult": 999.0}])
	almost(stats.get_speed_multiplier(), 3.0, 0.0001, "+999.0 bonus clamped to 3.0 maximum")

	stats.queue_free()


func test_adversarial_player_movement_velocity_with_extreme_speed_penalty() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Equip massive speed penalty
	player.stats.recalculate([{"speed_mult": -99.0}])
	almost(player.controller._speed_multiplier_for(player), 0.1, 0.001, "controller clamps speed mult to 0.1")

	# Target velocity check in _apply_move:
	# base max_speed = 108.0, axis = 1.0 -> target = 1.0 * 108.0 * 0.1 * 1.0 = 10.8
	var spd_mult := player.controller._speed_multiplier_for(player)
	var target_vel := 1.0 * player.controller.max_speed * spd_mult * 1.0
	almost(target_vel, 10.8, 0.01, "positive axis produces positive velocity (10.8 px/s)")
	ok(target_vel > 0.0, "velocity is strictly positive (no motion reversal)")
	ok(target_vel >= 10.0, "velocity is not zero (no complete freeze)")

	# Dash speed check: base 236.0 * 0.1 = 23.6
	var dash_spd := player.controller._dash_speed_for(player)
	almost(dash_spd, 23.6, 0.01, "dash speed is scaled to 23.6 px/s (positive and non-zero)")
	ok(dash_spd > 0.0, "dash velocity remains forward")

	arena.queue_free()


# ---------------------------------------------------------------------------
# Stress Test 4: Dead Player Manipulation (Anti-Resurrection Latch)
# ---------------------------------------------------------------------------

func test_adversarial_dead_player_manipulation_anti_resurrection() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# 1. Kill the player
	player.health.take_damage(999, null)
	eq(player.health.current, 0, "player health is 0")
	ok(player.health._dead, "player dead latch is true")

	# 2. Adversarially recalculate equipment bonuses with massive max HP bonus while dead
	player.stats.recalculate([{"max_hp": 100}])
	eq(player.health.max_hp, 105, "max_hp reflects new total capacity")
	eq(player.health.current, 0, "dead player current HP MUST remain 0")
	ok(player.health._dead, "dead player dead latch MUST remain true")

	# 3. Repeatedly cycle equipment 10 times while dead
	for i in range(10):
		var bonus_hp := 10 + i * 5
		player.stats.recalculate([{"max_hp": bonus_hp, "defense": 50, "attack": 20}])
		eq(player.health.current, 0, "cycle %d: dead player current HP remains 0" % i)
		ok(player.health._dead, "cycle %d: dead player dead latch remains true" % i)

	# 4. Unequip everything while dead
	player.stats.recalculate([])
	eq(player.health.max_hp, 5, "max_hp resets to base 5")
	eq(player.health.current, 0, "dead player remains at 0 HP after unequipping")
	ok(player.health._dead, "dead latch remains true")

	# 5. Direct call to set_max_hp on dead health component
	player.health.set_max_hp(50)
	eq(player.health.current, 0, "direct set_max_hp preserves 0 HP")
	ok(player.health._dead, "direct set_max_hp preserves _dead = true")

	player.health.set_max_hp(1)
	eq(player.health.current, 0, "direct set_max_hp(1) preserves 0 HP")
	ok(player.health._dead, "direct set_max_hp(1) preserves _dead = true")

	# 6. Dead player cannot take further damage or reset iframes
	var damage_taken := player.health.take_damage(5, null)
	ok(not damage_taken, "take_damage on dead player returns false")
	eq(player.health.current, 0)

	# 7. take_mitigated_damage on dead player returns false
	var mitigated_taken := player.take_mitigated_damage(5, null)
	ok(not mitigated_taken, "take_mitigated_damage on dead player returns false")
	eq(player.health.current, 0)

	arena.queue_free()


func test_adversarial_alive_player_vitality_swap_preservation() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Alive player at 1 HP: unequipping high-vitality armor must NOT kill the player
	player.stats.recalculate([{"max_hp": 20}])
	player.health.current = 1
	eq(player.health.current, 1)
	eq(player.health.max_hp, 25)

	# Unequip gear
	player.stats.recalculate([])
	eq(player.health.max_hp, 5)
	eq(player.health.current, 1, "alive player survives unequip at 1 HP without dying")
	ok(not player.health._dead, "player is still alive")

	# Alive player at 5 HP: equipping gear does NOT provide free healing
	player.health.current = 5
	player.stats.recalculate([{"max_hp": 10}])
	eq(player.health.max_hp, 15)
	eq(player.health.current, 5, "current HP stays at 5 (no free healing exploit)")

	# Alive player at 15 HP (healed): unequipping gear clamps HP down to new max 5
	player.health.heal_full()
	eq(player.health.current, 15)
	player.stats.recalculate([])
	eq(player.health.max_hp, 5)
	eq(player.health.current, 5, "current HP clamped cleanly to new maximum (5)")
	ok(not player.health._dead, "player is alive")

	arena.queue_free()


# ---------------------------------------------------------------------------
# Stress Test 5: Melee Attack and Damage Clamping Boundaries
# ---------------------------------------------------------------------------

func test_adversarial_attack_bonus_floor_and_melee_damage() -> void:
	var stats := _create_stats()
	add_child(stats)

	# Cursed weapon with -999 attack
	stats.recalculate([{"attack": -999}])
	eq(stats.get_attack_bonus(), 0, "attack bonus cannot drop below 0")

	stats.queue_free()


func test_adversarial_corrupted_data_types_in_recalculate() -> void:
	var stats := _create_stats()
	add_child(stats)

	# Recalculate with various malformed / unexpected types
	var junk_array: Array = [
		"just a string",
		42,
		3.14159,
		true,
		null,
		Vector2(10, 20),
		Color.RED,
		{"invalid_key": "some_value"},
		{"attack": "5", "defense": 3.7} # String/float numbers
	]

	# Must not crash or throw unhandled exceptions
	stats.recalculate(junk_array, "invalid_set_bonus_type")
	eq(stats.get_attack_bonus(), 5, "string numeric 5 parsed safely")
	eq(stats.get_defense_reduction(), 3, "float numeric 3.7 truncated safely to 3")

	stats.queue_free()


func test_adversarial_modifier_stacking_and_clamping() -> void:
	var stats := _create_stats()
	add_child(stats)

	# Add multiple extreme modifiers simultaneously
	stats.add_modifier(&"curse_defense", {"defense": -500})
	stats.add_modifier(&"bless_toxin", {"toxin_resist": 2.5})
	stats.add_modifier(&"crushing_slow", {"speed_mult": -10.0})
	stats.add_modifier(&"drain_hp", {"max_hp": -100})

	# Effective values must strictly respect bounds
	eq(stats.get_defense_reduction(), 0, "stacked negative defense clamped to 0")
	almost(stats.get_toxin_resistance(), 0.8, 0.0001, "stacked overflow toxin resist clamped to 0.8")
	almost(stats.get_speed_multiplier(), 0.1, 0.0001, "stacked negative speed clamped to 0.1")
	eq(stats.get_effective_max_hp(), 1, "stacked negative max hp floored at 1")

	# Remove modifiers one by one
	stats.remove_modifier(&"curse_defense")
	stats.remove_modifier(&"bless_toxin")
	stats.remove_modifier(&"crushing_slow")
	stats.remove_modifier(&"drain_hp")

	# Reverts to clean base values
	eq(stats.get_defense_reduction(), 0)
	almost(stats.get_toxin_resistance(), 0.0, 0.0001)
	almost(stats.get_speed_multiplier(), 1.0, 0.0001)
	eq(stats.get_effective_max_hp(), 5)

	stats.queue_free()


func test_adversarial_base_stat_corruption_bounded() -> void:
	var stats := _create_stats()
	add_child(stats)

	# Adversarially tamper with base exports directly
	stats.base_max_hp = -99
	stats.base_attack = -50
	stats.base_defense = -50
	stats.base_toxin_resist = 5.0
	stats.base_speed_mult = -10.0

	# Getters MUST enforce contract invariants
	eq(stats.get_effective_max_hp(), 1, "negative base max_hp floored at 1")
	eq(stats.get_attack_bonus(), 0, "negative base attack floored at 0")
	eq(stats.get_defense_reduction(), 0, "negative base defense floored at 0")
	almost(stats.get_toxin_resistance(), 0.8, 0.0001, "excessive base toxin resist clamped at 0.8")
	almost(stats.get_speed_multiplier(), 0.1, 0.0001, "negative base speed floored at 0.1")

	stats.queue_free()


func test_adversarial_graceful_degradation_without_stats_node() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Detach or nullify stats
	var old_stats = player.stats
	player.stats = null
	if old_stats != null:
		old_stats.queue_free()

	# 1. Health take_damage must not throw null error
	player.health.current = 5
	var hit_applied := player.health.take_damage(2, null)
	ok(hit_applied, "hit applied without stats")
	eq(player.health.current, 3, "took standard 2 damage")

	# 2. Controller speed multiplier must fall back cleanly to 1.0
	almost(player.controller._speed_multiplier_for(player), 1.0, 0.001, "controller falls back to 1.0")

	# 3. Toxin meter resistance must fall back cleanly to 0.0
	almost(player.toxin._get_toxin_resistance(), 0.0, 0.001, "toxin meter falls back to 0.0 resist")

	# 4. Melee swing must fall back cleanly to base damage
	player.melee._combo_index = 0
	player.melee._begin_active()
	eq(player.melee.hitbox.damage, CombatRules.SWING_DAMAGE[0], "melee falls back to base 1 damage")

	arena.queue_free()

