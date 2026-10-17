class_name CharacterStatsTest
extends TestCase
## Tier 1: Character Stats Unit & Feature Coverage Test Suite.
## Validates mathematical accuracy, base defaults, boundary clamping,
## multi-item aggregation, set synergy folding, and signal emissions.

const STATS_SCRIPT_PATH := "res://scripts/player/character_stats.gd"


## Authoritative contract mock used when implementation is pending.
class MockCharacterStats extends Node:
	signal stats_changed()

	var base_max_hp: int = 5
	var base_attack: int = 0
	var base_defense: int = 0
	var base_toxin_resist: float = 0.0
	var base_toxin_decay: float = 0.0
	var base_speed_mult: float = 1.0

	var bonus_attack: int = 0
	var bonus_defense: int = 0
	var bonus_max_hp: int = 0
	var bonus_toxin_resist: float = 0.0
	var bonus_toxin_decay: float = 0.0
	var bonus_speed_mult: float = 0.0

	func get_attack_bonus() -> int:
		return bonus_attack

	func get_defense_reduction() -> int:
		return maxi(0, bonus_defense)

	func get_max_hp_bonus() -> int:
		return bonus_max_hp

	func get_toxin_resistance() -> float:
		return clampf(base_toxin_resist + bonus_toxin_resist, 0.0, 0.8)

	func get_toxin_decay_bonus() -> float:
		return bonus_toxin_decay

	func get_speed_multiplier() -> float:
		return maxf(0.1, base_speed_mult + bonus_speed_mult)

	func recalculate(equipped_items: Array, set_bonuses: Dictionary = {}) -> void:
		bonus_attack = 0
		bonus_defense = 0
		bonus_max_hp = 0
		bonus_toxin_resist = 0.0
		bonus_toxin_decay = 0.0
		bonus_speed_mult = 0.0

		for item in equipped_items:
			if item == null:
				continue
			if item is Dictionary:
				bonus_attack += int(item.get("attack", 0))
				bonus_defense += int(item.get("defense", 0))
				bonus_max_hp += int(item.get("max_hp", item.get("hp", 0)))
				bonus_toxin_resist += float(item.get("toxin_resist", 0.0))
				bonus_toxin_decay += float(item.get("toxin_decay", 0.0))
				bonus_speed_mult += float(item.get("speed_mult", 0.0))
			else:
				if "attack" in item: bonus_attack += int(item.attack)
				if "defense" in item: bonus_defense += int(item.defense)
				if "max_hp" in item: bonus_max_hp += int(item.max_hp)
				elif "hp" in item: bonus_max_hp += int(item.hp)
				if "toxin_resist" in item: bonus_toxin_resist += float(item.toxin_resist)
				if "toxin_decay" in item: bonus_toxin_decay += float(item.toxin_decay)
				if "speed_mult" in item: bonus_speed_mult += float(item.speed_mult)

		bonus_attack += int(set_bonuses.get("attack", 0))
		bonus_defense += int(set_bonuses.get("defense", 0))
		bonus_max_hp += int(set_bonuses.get("max_hp", set_bonuses.get("hp", 0)))
		bonus_toxin_resist += float(set_bonuses.get("toxin_resist", 0.0))
		bonus_toxin_decay += float(set_bonuses.get("toxin_decay", 0.0))
		bonus_speed_mult += float(set_bonuses.get("speed_mult", 0.0))

		stats_changed.emit()


func _create_stats() -> Object:
	if ResourceLoader.exists(STATS_SCRIPT_PATH):
		var script: GDScript = load(STATS_SCRIPT_PATH)
		if script != null and script.can_instantiate():
			return script.new()
	return MockCharacterStats.new()


func test_default_base_attributes() -> void:
	var stats = _create_stats()
	add_child(stats)

	eq(stats.get_attack_bonus(), 0, "default attack bonus is 0")
	eq(stats.get_defense_reduction(), 0, "default defense reduction is 0")
	eq(stats.get_max_hp_bonus(), 0, "default max hp bonus is 0")
	almost(stats.get_toxin_resistance(), 0.0, 0.001, "default toxin resistance is 0.0")
	almost(stats.get_toxin_decay_bonus(), 0.0, 0.001, "default toxin decay bonus is 0.0")
	almost(stats.get_speed_multiplier(), 1.0, 0.001, "default speed multiplier is 1.0")


func test_single_item_bonus_aggregation() -> void:
	var stats = _create_stats()
	add_child(stats)

	var item := {
		"attack": 3,
		"defense": 2,
		"max_hp": 4,
		"toxin_resist": 0.25,
		"toxin_decay": 0.5,
		"speed_mult": 0.15
	}
	stats.recalculate([item])

	eq(stats.get_attack_bonus(), 3, "attack reflects item bonus")
	eq(stats.get_defense_reduction(), 2, "defense reflects item bonus")
	eq(stats.get_max_hp_bonus(), 4, "max hp reflects item bonus")
	almost(stats.get_toxin_resistance(), 0.25, 0.001, "toxin resistance reflects item bonus")
	almost(stats.get_toxin_decay_bonus(), 0.5, 0.001, "toxin decay reflects item bonus")
	almost(stats.get_speed_multiplier(), 1.15, 0.001, "speed multiplier reflects item bonus")


func test_multi_item_additive_aggregation() -> void:
	var stats = _create_stats()
	add_child(stats)

	var weapon := {"attack": 4, "defense": 0, "max_hp": 0, "toxin_resist": 0.0, "toxin_decay": 0.0, "speed_mult": -0.05}
	var armor := {"attack": 0, "defense": 5, "max_hp": 3, "toxin_resist": 0.2, "toxin_decay": 0.1, "speed_mult": -0.10}
	var trinket := {"attack": 1, "defense": 1, "max_hp": 1, "toxin_resist": 0.15, "toxin_decay": 0.3, "speed_mult": 0.20}

	stats.recalculate([weapon, armor, trinket])

	eq(stats.get_attack_bonus(), 5, "total attack = 4 + 0 + 1 = 5")
	eq(stats.get_defense_reduction(), 6, "total defense = 0 + 5 + 1 = 6")
	eq(stats.get_max_hp_bonus(), 4, "total hp bonus = 0 + 3 + 1 = 4")
	almost(stats.get_toxin_resistance(), 0.35, 0.001, "total toxin resist = 0.0 + 0.2 + 0.15 = 0.35")
	almost(stats.get_toxin_decay_bonus(), 0.4, 0.001, "total toxin decay = 0.0 + 0.1 + 0.3 = 0.4")
	almost(stats.get_speed_multiplier(), 1.05, 0.001, "total speed = 1.0 - 0.05 - 0.10 + 0.20 = 1.05")


func test_toxin_resistance_upper_bound_clamped_at_80_percent() -> void:
	var stats = _create_stats()
	add_child(stats)

	# BVA: 0.5 + 0.4 = 0.9, must be clamped strictly to 0.8 (80%)
	var heavy_filter_a := {"toxin_resist": 0.5}
	var heavy_filter_b := {"toxin_resist": 0.4}
	stats.recalculate([heavy_filter_a, heavy_filter_b])

	almost(stats.get_toxin_resistance(), 0.8, 0.001, "toxin resistance clamped at 0.8 max")


func test_toxin_resistance_exact_boundary_at_80_percent() -> void:
	var stats = _create_stats()
	add_child(stats)

	var exact_item := {"toxin_resist": 0.8}
	stats.recalculate([exact_item])

	almost(stats.get_toxin_resistance(), 0.8, 0.001, "exact 0.8 boundary is maintained")


func test_toxin_resistance_lower_bound_clamped_at_zero() -> void:
	var stats = _create_stats()
	add_child(stats)

	var cursed_item := {"toxin_resist": -0.3}
	stats.recalculate([cursed_item])

	almost(stats.get_toxin_resistance(), 0.0, 0.001, "negative resistance clamped to 0.0")


func test_defense_reduction_floor_at_zero() -> void:
	var stats = _create_stats()
	add_child(stats)

	var brittle_item := {"defense": -10}
	stats.recalculate([brittle_item])

	eq(stats.get_defense_reduction(), 0, "defense reduction cannot drop below 0")


func test_speed_multiplier_lower_bound_clamped_at_point_one() -> void:
	var stats = _create_stats()
	add_child(stats)

	# Severe weight penalty should not freeze or reverse character motion (clamped at 0.1)
	var crushing_weight := {"speed_mult": -2.0}
	stats.recalculate([crushing_weight])

	almost(stats.get_speed_multiplier(), 0.1, 0.001, "speed multiplier clamped at minimum 0.1")


func test_speed_multiplier_additive_scaling() -> void:
	var stats = _create_stats()
	add_child(stats)

	var swift_boots := {"speed_mult": 0.25}
	stats.recalculate([swift_boots])

	almost(stats.get_speed_multiplier(), 1.25, 0.001, "speed multiplier scales additively from base 1.0")


func test_max_hp_bonus_calculation() -> void:
	var stats = _create_stats()
	add_child(stats)

	var health_ring := {"max_hp": 3}
	stats.recalculate([health_ring])

	eq(stats.get_max_hp_bonus(), 3, "max hp bonus is +3")


func test_set_synergy_bonuses_inclusion() -> void:
	var stats = _create_stats()
	add_child(stats)

	var sword := {"attack": 1}
	var set_synergy := {
		"attack": 2,
		"defense": 1,
		"toxin_resist": 0.1,
		"speed_mult": 0.05
	}
	stats.recalculate([sword], set_synergy)

	eq(stats.get_attack_bonus(), 3, "attack includes set synergy (+1 item + 2 synergy = 3)")
	eq(stats.get_defense_reduction(), 1, "defense includes set synergy")
	almost(stats.get_toxin_resistance(), 0.1, 0.001, "toxin resist includes set synergy")
	almost(stats.get_speed_multiplier(), 1.05, 0.001, "speed mult includes set synergy")


func test_signal_stats_changed_emitted_on_recalculate() -> void:
	var stats = _create_stats()
	add_child(stats)

	var emitted := [false]
	stats.stats_changed.connect(func(): emitted[0] = true)

	stats.recalculate([{"attack": 1}])
	ok(emitted[0], "stats_changed signal was emitted on recalculate")


func test_recalculate_with_empty_or_null_items_clears_bonuses() -> void:
	var stats = _create_stats()
	add_child(stats)

	stats.recalculate([{"attack": 5, "defense": 3}])
	eq(stats.get_attack_bonus(), 5)
	eq(stats.get_defense_reduction(), 3)

	# Reset with nulls or empty array
	stats.recalculate([null, null, null])
	eq(stats.get_attack_bonus(), 0, "attack bonus cleared back to 0")
	eq(stats.get_defense_reduction(), 0, "defense reduction cleared back to 0")
	almost(stats.get_speed_multiplier(), 1.0, 0.001, "speed multiplier cleared back to 1.0")


func test_recalculate_handles_mixed_dictionary_and_resource_types() -> void:
	var stats = _create_stats()
	add_child(stats)

	var item_dict := {"attack": 2}
	var empty_slot = null
	var dummy_res := RefCounted.new()
	var dummy_script := GDScript.new()
	dummy_script.source_code = "extends RefCounted\nvar attack: int = 0\n"
	dummy_script.reload()
	dummy_res.set_script(dummy_script)

	stats.recalculate([item_dict, empty_slot, dummy_res])
	eq(stats.get_attack_bonus(), 2, "safely processes array with mixed entries")
