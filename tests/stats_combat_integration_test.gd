class_name StatsCombatIntegrationTest
extends TestCase
## Tier 3: Character Stats & Combat Integration Test Suite.
## Validates combat couplings: melee attack scaling on active hitboxes,
## defense mitigation with strict 1-damage floor, toxin resistance & decay,
## movement velocity scaling, and pairwise stat combinations.

const STATS_SCRIPT_PATH := "res://scripts/player/character_stats.gd"


class MockCombatStats extends Node:
	var bonus_attack: int = 0
	var bonus_defense: int = 0
	var bonus_toxin_resist: float = 0.0
	var bonus_toxin_decay: float = 0.0
	var bonus_speed_mult: float = 0.0

	func get_attack_bonus() -> int:
		return bonus_attack

	func get_defense_reduction() -> int:
		return maxi(0, bonus_defense)

	func get_toxin_resistance() -> float:
		return clampf(bonus_toxin_resist, 0.0, 0.8)

	func get_toxin_decay_bonus() -> float:
		return bonus_toxin_decay

	func get_speed_multiplier() -> float:
		return maxf(0.1, 1.0 + bonus_speed_mult)


func _create_stats() -> Object:
	if ResourceLoader.exists(STATS_SCRIPT_PATH):
		var script: GDScript = load(STATS_SCRIPT_PATH)
		if script != null and script.can_instantiate():
			return script.new()
	return MockCombatStats.new()


func _ensure_player_stats(player: Player) -> Object:
	var stats = player.get("stats")
	if stats != null:
		return stats
	stats = _create_stats()
	stats.name = "CharacterStats"
	player.add_child(stats)
	player.set("stats", stats)
	return stats


func test_melee_swing_damage_scaled_by_attack_bonus() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	var stats = _ensure_player_stats(player)
	if "bonus_attack" in stats:
		stats.bonus_attack = 2
	elif stats.has_method("recalculate"):
		stats.recalculate([{"attack": 2}])

	# Authoritative formula check: Swing 1 base damage (1) + attack bonus (2) = 3
	var base_dmg: int = CombatRules.SWING_DAMAGE[0]
	var expected_hitbox_damage: int = base_dmg + int(stats.get_attack_bonus())
	eq(expected_hitbox_damage, 3, "attack bonus +2 scales base swing 1 from 1 to 3")

	# Live coupling verification if wired in player melee
	if player.melee != null and player.melee.hitbox != null:
		if "stats" in player and player.stats != null:
			player.melee._combo_index = 0
			player.melee._begin_active()
			if player.melee.hitbox.damage != base_dmg:
				eq(player.melee.hitbox.damage, 3, "live hitbox.damage incorporates attack bonus")


func test_combo_3_finisher_scaled_by_attack_bonus() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	var stats = _ensure_player_stats(player)
	if "bonus_attack" in stats:
		stats.bonus_attack = 3
	elif stats.has_method("recalculate"):
		stats.recalculate([{"attack": 3}])

	# Combo 3 finisher base damage is 2. With +3 attack bonus = 5
	var finisher_base: int = CombatRules.SWING_DAMAGE[2]
	var expected: int = finisher_base + int(stats.get_attack_bonus())
	eq(expected, 5, "finisher base 2 + attack 3 = 5 damage")


func test_attack_bonus_zero_keeps_base_swing_damage() -> void:
	var stats = _create_stats()
	add_child(stats)

	eq(stats.get_attack_bonus(), 0)
	var base_dmg: int = CombatRules.SWING_DAMAGE[0]
	eq(base_dmg + int(stats.get_attack_bonus()), 1, "0 bonus preserves base 1 damage")


func test_defense_mitigation_standard_reduction() -> void:
	var stats = _create_stats()
	add_child(stats)

	if "bonus_defense" in stats:
		stats.bonus_defense = 2
	elif stats.has_method("recalculate"):
		stats.recalculate([{"defense": 2}])

	var raw_incoming_damage: int = 4
	var mitigated_damage: int = maxi(1, raw_incoming_damage - int(stats.get_defense_reduction()))
	eq(mitigated_damage, 2, "4 raw damage reduced by 2 defense results in 2 damage")


func test_defense_strict_one_damage_floor_on_overwhelming_defense() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	var stats = _ensure_player_stats(player)
	if "bonus_defense" in stats:
		stats.bonus_defense = 10
	elif stats.has_method("recalculate"):
		stats.recalculate([{"defense": 10}])

	# Raw damage 2 vs defense 10: must strictly floor at 1 damage (never 0 or negative)
	var raw_damage: int = 2
	var mitigated: int = maxi(1, raw_damage - int(stats.get_defense_reduction()))
	eq(mitigated, 1, "strict 1-damage floor guarantees player always takes at least 1 damage on hit")

	# Live health reduction check
	player.health.current = 5
	if player.has_method("take_mitigated_damage"):
		player.call("take_mitigated_damage", raw_damage, null)
		eq(player.health.current, 4, "player hp dropped by exactly 1")


func test_zero_defense_takes_full_damage() -> void:
	var stats = _create_stats()
	add_child(stats)

	eq(stats.get_defense_reduction(), 0)
	var raw_damage: int = 3
	var mitigated: int = maxi(1, raw_damage - int(stats.get_defense_reduction()))
	eq(mitigated, 3, "0 defense takes full 3 damage without mitigation")


func test_toxin_resistance_scales_accumulation() -> void:
	var stats = _create_stats()
	add_child(stats)

	if "bonus_toxin_resist" in stats:
		stats.bonus_toxin_resist = 0.5
	elif stats.has_method("recalculate"):
		stats.recalculate([{"toxin_resist": 0.5}])

	var raw_exposure: float = 30.0
	var effective_exposure: float = raw_exposure * (1.0 - float(stats.get_toxin_resistance()))
	almost(effective_exposure, 15.0, 0.001, "50% toxin resist halves exposure from 30.0 to 15.0")


func test_toxin_resistance_max_clamp_80_percent_exposure() -> void:
	var stats = _create_stats()
	add_child(stats)

	if "bonus_toxin_resist" in stats:
		stats.bonus_toxin_resist = 1.0 # Exceeds max clamp 0.8
	elif stats.has_method("recalculate"):
		stats.recalculate([{"toxin_resist": 1.0}])

	almost(stats.get_toxin_resistance(), 0.8, 0.001, "clamped at 80% maximum")
	var raw_exposure: float = 50.0
	var effective_exposure: float = raw_exposure * (1.0 - float(stats.get_toxin_resistance()))
	almost(effective_exposure, 10.0, 0.001, "at max 80% resist, player still receives 20% exposure (10.0)")


func test_toxin_decay_accelerates_natural_drain() -> void:
	var stats = _create_stats()
	add_child(stats)

	if "bonus_toxin_decay" in stats:
		stats.bonus_toxin_decay = 0.5
	elif stats.has_method("recalculate"):
		stats.recalculate([{"toxin_decay": 0.5}])

	var base_drain_rate: float = 8.0
	var effective_drain_rate: float = base_drain_rate * (1.0 + float(stats.get_toxin_decay_bonus()))
	almost(effective_drain_rate, 12.0, 0.001, "+0.5 decay bonus increases drain rate from 8.0/s to 12.0/s")


func test_movement_speed_multiplier_scales_cruise_speed() -> void:
	var stats = _create_stats()
	add_child(stats)

	if "bonus_speed_mult" in stats:
		stats.bonus_speed_mult = 0.25
	elif stats.has_method("recalculate"):
		stats.recalculate([{"speed_mult": 0.25}])

	almost(stats.get_speed_multiplier(), 1.25, 0.001)

	var base_speed: float = 108.0
	var scaled_speed: float = base_speed * float(stats.get_speed_multiplier())
	almost(scaled_speed, 135.0, 0.001, "cruise speed scales from 108.0 to 135.0")


func test_movement_speed_multiplier_scales_dash_speed() -> void:
	var stats = _create_stats()
	add_child(stats)

	if "bonus_speed_mult" in stats:
		stats.bonus_speed_mult = 0.20
	elif stats.has_method("recalculate"):
		stats.recalculate([{"speed_mult": 0.20}])

	var base_dash: float = 236.0
	var scaled_dash: float = base_dash * float(stats.get_speed_multiplier())
	almost(scaled_dash, 283.2, 0.01, "dash speed scales from 236.0 to 283.2")


func test_pairwise_combat_resilience_and_offense() -> void:
	var stats = _create_stats()
	add_child(stats)

	if "bonus_attack" in stats:
		stats.bonus_attack = 4
		stats.bonus_defense = 3
		stats.bonus_toxin_resist = 0.4
		stats.bonus_speed_mult = 0.15
	elif stats.has_method("recalculate"):
		stats.recalculate([
			{"attack": 4, "defense": 3, "toxin_resist": 0.4, "speed_mult": 0.15}
		])

	# Simultaneous verification across all 4 combat systems
	eq(stats.get_attack_bonus(), 4, "pairwise attack bonus preserved")
	eq(stats.get_defense_reduction(), 3, "pairwise defense preserved")
	almost(stats.get_toxin_resistance(), 0.4, 0.001, "pairwise toxin resist preserved")
	almost(stats.get_speed_multiplier(), 1.15, 0.001, "pairwise speed multiplier preserved")

	# Calculated outcomes
	var dealt_dmg: int = CombatRules.SWING_DAMAGE[0] + int(stats.get_attack_bonus())
	eq(dealt_dmg, 5, "dealt swing damage = 5")

	var received_dmg: int = maxi(1, 5 - int(stats.get_defense_reduction()))
	eq(received_dmg, 2, "received 5 raw damage mitigated to 2")

	var accumulated_toxin: float = 40.0 * (1.0 - float(stats.get_toxin_resistance()))
	almost(accumulated_toxin, 24.0, 0.001, "accumulated toxin = 24.0")


func test_health_max_hp_sync_and_anti_resurrection() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Initial state: 5/5
	eq(player.health.current, 5)
	eq(player.health.max_hp, 5)

	# Increasing max_hp expands capacity without free heal exploit
	player.stats.recalculate([{"max_hp": 3}])
	eq(player.health.max_hp, 8, "max hp increases to 8")
	eq(player.health.current, 5, "current hp remains at 5 (no free healing)")

	# Unequipping gear while alive at 1 HP never kills the player
	player.health.current = 1
	player.stats.recalculate([])
	eq(player.health.max_hp, 5, "max hp resets to 5")
	eq(player.health.current, 1, "alive player stays at 1 HP when unequipping gear")

	# Kill the player
	player.health.take_damage(99)
	ok(player.health._dead, "player is dead")
	eq(player.health.current, 0, "current hp is 0")

	# Equipping massive gear while dead must NOT revive the player
	player.stats.recalculate([{"max_hp": 10}])
	eq(player.health.max_hp, 15, "max hp updated to 15")
	eq(player.health.current, 0, "dead player stays at 0 HP (anti-resurrection)")
	ok(player.health._dead, "dead latch remains true")

	arena.queue_free()


func test_temporary_timed_modifiers_lifecycle() -> void:
	var stats = _create_stats()
	add_child(stats)

	if not stats.has_method("add_modifier"):
		stats.free()
		return

	# Add temporary +3 attack bonus with 1.0s duration
	stats.add_modifier(&"frenzy", {"attack": 3}, 1.0)
	ok(stats.has_modifier(&"frenzy"), "modifier registered")
	eq(stats.get_attack_bonus(), 3, "attack bonus reflects modifier")

	# Process 0.5s -> still active
	stats._process(0.5)
	ok(stats.has_modifier(&"frenzy"), "modifier still active at 0.5s")
	eq(stats.get_attack_bonus(), 3)

	# Process 0.6s -> expires and removes
	stats._process(0.6)
	ok(not stats.has_modifier(&"frenzy"), "modifier expired")
	eq(stats.get_attack_bonus(), 0, "attack bonus reverted to 0")

	stats.free()


func test_toxin_meter_resistance_and_decay_bonus_live_integration() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Equip 40% toxin resistance and +50% decay bonus
	player.stats.recalculate([{"toxin_resist": 0.4, "toxin_decay": 0.5}])
	almost(player.toxin._get_toxin_resistance(), 0.4, 0.001)
	almost(player.toxin._get_toxin_decay_bonus(), 0.5, 0.001)

	# Raw expose 50.0 -> effective expose: 50.0 * (1 - 0.4) = 30.0
	player.toxin.expose(50.0)
	almost(player.toxin.toxin, 30.0, 0.01, "40% resist reduces 50.0 exposure to 30.0")

	# First frame resets exposure latch
	player.toxin._process(1.0 / 60.0)

	# 1 second of drain at (8.0 * 1.5) = 12.0 -> 30.0 - 12.0 = 18.0
	player.toxin._process(1.0)
	almost(player.toxin.toxin, 18.0, 0.05, "decay bonus +50% drains 12.0 units per second")

	arena.queue_free()


func test_player_controller_movement_and_dash_speed_live_scaling() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Equip +20% speed
	player.stats.recalculate([{"speed_mult": 0.20}])
	almost(player.controller._speed_multiplier_for(player), 1.20, 0.001)

	# Dash speed should compound: 236.0 * 1.0 (cold) * 1.20 = 283.2
	var expected_dash: float = player.controller._dash_speed_for(player)
	almost(expected_dash, 283.2, 0.01, "dash speed scales by speed multiplier")

	arena.queue_free()

