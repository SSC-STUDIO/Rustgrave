class_name CharacterOriginTest
extends TestCase
## Test suite for Character Origin System, Starting Loadouts, and Dynamic Preview Math.
## Validates CharacterOrigin resource, OriginCatalog definitions, EquipmentCatalog aliasing,
## CharacterStats origin integration, boundary clamping, and 9-combination parity.

const CharacterOriginScript := preload("res://scripts/data/character_origin.gd")
const OriginCatalogScript := preload("res://scripts/data/origin_catalog.gd")
const EquipmentCatalogScript := preload("res://scripts/data/equipment_catalog.gd")
const CharacterStatsScript := preload("res://scripts/player/character_stats.gd")


func _create_stats() -> CharacterStats:
	var stats: CharacterStats = CharacterStatsScript.new()
	add_child(stats)
	return stats


# ===========================================================================
# 1. Origin Catalog & Resource Definitions
# ===========================================================================

func test_origin_catalog_contains_three_defined_origins() -> void:
	var origins: Array[CharacterOrigin] = OriginCatalogScript.get_all_origins()
	eq(origins.size(), 3, "Origin catalog contains exactly 3 origins")

	var ids: Array[StringName] = OriginCatalogScript.get_all_origin_ids()
	eq(ids.size(), 3, "Catalog defines 3 origin IDs")
	ok(ids.has(&"ember_vanguard"), "has ember_vanguard")
	ok(ids.has(&"scrap_scavenger"), "has scrap_scavenger")
	ok(ids.has(&"rust_automaton"), "has rust_automaton")

	ok(OriginCatalogScript.has_origin(&"ember_vanguard"), "has_origin ember_vanguard")
	ok(OriginCatalogScript.has_origin(&"scrap_scavenger"), "has_origin scrap_scavenger")
	ok(OriginCatalogScript.has_origin(&"rust_automaton"), "has_origin rust_automaton")
	ok(not OriginCatalogScript.has_origin(&"nonexistent_origin"), "has_origin false for invalid")
	ok(not OriginCatalogScript.has_origin(""), "has_origin false for empty string")
	ok(not OriginCatalogScript.has_origin(null), "has_origin false for null")


func test_origin_metadata_and_stat_modifiers() -> void:
	# Ember Vanguard
	var ember: CharacterOrigin = OriginCatalogScript.get_origin(&"ember_vanguard")
	ok(ember != null, "ember_vanguard retrieved")
	ok(ember.is_valid(), "ember_vanguard is valid")
	eq(ember.id, &"ember_vanguard")
	eq(ember.title, "余烬重骑")
	eq(ember.combat_focus, "稳固防御与高生存")
	ok(not ember.lore.is_empty(), "ember lore not empty")
	eq(ember.default_weapon, &"broken_sword")
	eq(ember.default_armor, &"broken_armor")
	eq(int(ember.stat_modifiers.get("max_hp", 0)), 1, "ember max_hp modifier +1")
	eq(int(ember.stat_modifiers.get("defense", 0)), 1, "ember defense modifier +1")
	eq(int(ember.stat_modifiers.get("attack", 0)), 0, "ember attack modifier 0")

	# Scrap Scavenger
	var scrap: CharacterOrigin = OriginCatalogScript.get_origin(&"scrap_scavenger")
	ok(scrap != null, "scrap_scavenger retrieved")
	ok(scrap.is_valid(), "scrap_scavenger is valid")
	eq(scrap.id, &"scrap_scavenger")
	eq(scrap.title, "废料剑客")
	eq(scrap.combat_focus, "敏捷规避与高机动斩击")
	ok(not scrap.lore.is_empty(), "scrap lore not empty")
	eq(scrap.default_weapon, &"scavenger_blade")
	eq(scrap.default_armor, &"scavenger_rags")
	eq(int(scrap.stat_modifiers.get("attack", 0)), 1, "scrap attack modifier +1")
	almost(float(scrap.stat_modifiers.get("speed_mult", 0.0)), 0.10, 0.001, "scrap speed_mult modifier +0.10")

	# Rust Automaton
	var rust: CharacterOrigin = OriginCatalogScript.get_origin(&"rust_automaton")
	ok(rust != null, "rust_automaton retrieved")
	ok(rust.is_valid(), "rust_automaton is valid")
	eq(rust.id, &"rust_automaton")
	eq(rust.title, "锈械学者")
	eq(rust.combat_focus, "腐液耐受与毒池战斗特化")
	ok(not rust.lore.is_empty(), "rust lore not empty")
	eq(rust.default_weapon, &"scholar_probe")
	eq(rust.default_armor, &"scholar_cowl")
	almost(float(rust.stat_modifiers.get("toxin_resist", 0.0)), 0.20, 0.001, "rust toxin_resist +0.20")
	almost(float(rust.stat_modifiers.get("toxin_decay", 0.0)), 0.50, 0.001, "rust toxin_decay +0.50")


func test_universal_trinket_pool_in_origins() -> void:
	var pool: Array[StringName] = OriginCatalogScript.get_trinket_pool()
	eq(pool.size(), 3, "Trinket pool has 3 entries")
	ok(pool.has(&"broken_pendant"), "trinket pool has broken_pendant")
	ok(pool.has(&"bone_amulet"), "trinket pool has bone_amulet")
	ok(pool.has(&"toxic_filter_talisman"), "trinket pool has toxic_filter_talisman")

	for origin in OriginCatalogScript.get_all_origins():
		ok(origin.allows_trinket(&"broken_pendant"), "%s allows broken_pendant" % origin.id)
		ok(origin.allows_trinket(&"bone_amulet"), "%s allows bone_amulet" % origin.id)
		ok(origin.allows_trinket(&"toxic_filter_talisman"), "%s allows toxic_filter_talisman" % origin.id)
		ok(not origin.allows_trinket(&"invalid_trinket"), "%s rejects invalid trinket" % origin.id)


# ===========================================================================
# 2. Equipment Catalog Aliasing & Starter Gear
# ===========================================================================

func test_equipment_catalog_symmetrical_trinket_aliasing() -> void:
	# bone_amulet <-> bone_charm
	var bone_a: EquipmentItem = EquipmentCatalogScript.for_id(&"bone_amulet")
	var bone_c: EquipmentItem = EquipmentCatalogScript.for_id(&"bone_charm")
	ok(bone_a != null, "bone_amulet resolves")
	ok(bone_c != null, "bone_charm resolves")
	eq(bone_a.display_name, "白骨护身符")
	eq(bone_c.display_name, "白骨护身符")
	eq(bone_a.max_hp, 1)
	eq(bone_c.max_hp, 1)
	almost(bone_a.speed_mult, 0.05, 0.001)
	almost(bone_c.speed_mult, 0.05, 0.001)

	# toxic_filter_talisman <-> toxic_ward
	var tox_a: EquipmentItem = EquipmentCatalogScript.for_id(&"toxic_filter_talisman")
	var tox_w: EquipmentItem = EquipmentCatalogScript.for_id(&"toxic_ward")
	ok(tox_a != null, "toxic_filter_talisman resolves")
	ok(tox_w != null, "toxic_ward resolves")
	eq(tox_a.display_name, "滤毒符印")
	eq(tox_w.display_name, "滤毒符印")
	almost(tox_a.toxin_resist, 0.15, 0.001)
	almost(tox_w.toxin_resist, 0.15, 0.001)
	almost(tox_a.toxin_decay, 0.50, 0.001)
	almost(tox_w.toxin_decay, 0.50, 0.001)


func test_equipment_catalog_origin_starter_weapons_and_armors() -> void:
	# Scavenger Blade & Rags
	var sc_blade: EquipmentItem = EquipmentCatalogScript.for_id(&"scavenger_blade")
	ok(sc_blade != null, "scavenger_blade exists")
	eq(sc_blade.slot_type, EquipmentItem.SLOT_WEAPON)
	eq(sc_blade.display_name, "废料短刃")
	eq(sc_blade.attack, 1)

	var sc_rags: EquipmentItem = EquipmentCatalogScript.for_id(&"scavenger_rags")
	ok(sc_rags != null, "scavenger_rags exists")
	eq(sc_rags.slot_type, EquipmentItem.SLOT_ARMOR)
	eq(sc_rags.display_name, "拾荒残革")
	eq(sc_rags.defense, 1)

	# Scholar Probe & Cowl
	var sch_probe: EquipmentItem = EquipmentCatalogScript.for_id(&"scholar_probe")
	ok(sch_probe != null, "scholar_probe exists")
	eq(sch_probe.slot_type, EquipmentItem.SLOT_WEAPON)
	eq(sch_probe.display_name, "探针短杖")
	eq(sch_probe.attack, 1)

	var sch_cowl: EquipmentItem = EquipmentCatalogScript.for_id(&"scholar_cowl")
	ok(sch_cowl != null, "scholar_cowl exists")
	eq(sch_cowl.slot_type, EquipmentItem.SLOT_ARMOR)
	eq(sch_cowl.display_name, "耐酸头罩")
	eq(sch_cowl.defense, 1)
	almost(sch_cowl.toxin_resist, 0.05, 0.001)

	# Registered IDs completeness
	var all_ids: Array[StringName] = EquipmentCatalogScript.get_all_registered_ids()
	for expected in [
		&"broken_sword", &"broken_armor", &"broken_pendant",
		&"iron_blade", &"iron_carapace",
		&"toxic_ward", &"toxic_filter_talisman",
		&"bone_charm", &"bone_amulet",
		&"scavenger_blade", &"scavenger_rags",
		&"scholar_probe", &"scholar_cowl"
	]:
		ok(all_ids.has(expected), "registered IDs includes %s" % expected)
		ok(EquipmentCatalogScript.has_id(expected), "has_id true for %s" % expected)


# ===========================================================================
# 3. Character Stats Origin Integration & Lifecycle Parity
# ===========================================================================

func test_character_stats_unassigned_bare_defaults() -> void:
	var stats := _create_stats()
	eq(stats.get_origin_id(), &"", "origin ID is empty by default")
	eq(stats.get_effective_max_hp(), 5, "bare default max HP is 5")
	eq(stats.get_total_max_hp(), 5, "bare default total max HP is 5")
	eq(stats.get_max_hp_bonus(), 0, "bare default max HP bonus is 0")
	eq(stats.get_attack_bonus(), 0, "bare default attack bonus is 0")
	eq(stats.get_defense_reduction(), 0, "bare default defense reduction is 0")
	almost(stats.get_toxin_resistance(), 0.0, 0.001, "bare default toxin resist is 0.0")
	almost(stats.get_toxin_decay_bonus(), 0.0, 0.001, "bare default toxin decay is 0.0")
	almost(stats.get_speed_multiplier(), 1.0, 0.001, "bare default speed mult is 1.0")


func test_character_stats_apply_each_origin_dynamically() -> void:
	var stats := _create_stats()

	# 1. Apply Ember Vanguard
	stats.apply_origin(&"ember_vanguard")
	eq(stats.get_origin_id(), &"ember_vanguard")
	eq(stats.get_effective_max_hp(), 6, "ember vanguard increases max HP to 6 (5+1)")
	eq(stats.get_defense_reduction(), 1, "ember vanguard increases defense to 1")
	eq(stats.get_attack_bonus(), 0, "ember vanguard attack remains 0")
	almost(stats.get_speed_multiplier(), 1.0, 0.001)

	# 2. Switch to Scrap Scavenger
	stats.apply_origin(&"scrap_scavenger")
	eq(stats.get_origin_id(), &"scrap_scavenger")
	eq(stats.get_effective_max_hp(), 5, "scrap scavenger max HP resets to 5")
	eq(stats.get_defense_reduction(), 0, "scrap scavenger defense resets to 0")
	eq(stats.get_attack_bonus(), 1, "scrap scavenger attack is 1")
	almost(stats.get_speed_multiplier(), 1.10, 0.001, "scrap scavenger speed mult is 1.10 (+10%)")

	# 3. Switch to Rust Automaton
	stats.apply_origin(&"rust_automaton")
	eq(stats.get_origin_id(), &"rust_automaton")
	eq(stats.get_attack_bonus(), 0, "rust automaton attack resets to 0")
	almost(stats.get_speed_multiplier(), 1.0, 0.001, "rust automaton speed resets to 1.0")
	almost(stats.get_toxin_resistance(), 0.20, 0.001, "rust automaton toxin resist is 0.20 (+20%)")
	almost(stats.get_toxin_decay_bonus(), 0.50, 0.001, "rust automaton toxin decay is 0.50 (+50%)")

	# 4. Clear Origin back to bare
	stats.apply_origin("")
	eq(stats.get_origin_id(), &"", "origin cleared")
	eq(stats.get_effective_max_hp(), 5, "max HP returned to 5")
	eq(stats.get_defense_reduction(), 0, "defense returned to 0")
	eq(stats.get_attack_bonus(), 0, "attack returned to 0")
	almost(stats.get_toxin_resistance(), 0.0, 0.001)
	almost(stats.get_toxin_decay_bonus(), 0.0, 0.001)
	almost(stats.get_speed_multiplier(), 1.0, 0.001)


func test_character_stats_signal_stats_changed_emitted_on_origin_change() -> void:
	var stats := _create_stats()
	var emitted_count := [0]
	stats.stats_changed.connect(func(): emitted_count[0] += 1)

	stats.apply_origin(&"ember_vanguard")
	eq(emitted_count[0], 1, "stats_changed emitted on apply_origin")

	stats.apply_origin(&"scrap_scavenger")
	eq(emitted_count[0], 2, "stats_changed emitted on switching origin")

	stats.apply_origin(null)
	eq(emitted_count[0], 3, "stats_changed emitted on clearing origin")


# ===========================================================================
# 4. Preview Math Parity Across All 9 Origin × Trinket Combinations
# ===========================================================================

func test_preview_stats_exact_parity_with_character_stats_all_nine_combinations() -> void:
	var stats := _create_stats()
	var origins := OriginCatalogScript.get_all_origin_ids()
	var trinkets := OriginCatalogScript.get_trinket_pool()

	for origin_id in origins:
		var origin_data := OriginCatalogScript.get_origin(origin_id)
		var weapon_id: StringName = origin_data.default_weapon
		var armor_id: StringName = origin_data.default_armor

		for trinket_id in trinkets:
			# 1. Compute dynamic live stats on CharacterStats
			stats.apply_origin(origin_id)
			var w_item: EquipmentItem = EquipmentCatalogScript.for_id(weapon_id)
			var a_item: EquipmentItem = EquipmentCatalogScript.for_id(armor_id)
			var t_item: EquipmentItem = EquipmentCatalogScript.for_id(trinket_id)
			var equipped := [w_item, a_item, t_item]
			var synergies := EquipmentCatalogScript.calculate_set_synergies(equipped)
			stats.recalculate(equipped, synergies)

			# 2. Compute preview stats via static helper
			var preview: Dictionary = OriginCatalogScript.calculate_preview_stats(
				origin_id,
				weapon_id,
				armor_id,
				trinket_id
			)

			# 3. Assert mathematical parity
			var context_msg := "Combination (%s, %s, %s, %s)" % [origin_id, weapon_id, armor_id, trinket_id]
			eq(preview["max_hp"], stats.get_effective_max_hp(), "%s max_hp parity" % context_msg)
			eq(preview["attack"], stats.get_attack_bonus(), "%s attack parity" % context_msg)
			eq(preview["defense"], stats.get_defense_reduction(), "%s defense parity" % context_msg)
			almost(float(preview["toxin_resist"]), stats.get_toxin_resistance(), 0.001, "%s toxin_resist parity" % context_msg)
			almost(float(preview["toxin_decay"]), stats.get_toxin_decay_bonus(), 0.001, "%s toxin_decay parity" % context_msg)
			almost(float(preview["speed_mult"]), stats.get_speed_multiplier(), 0.001, "%s speed_mult parity" % context_msg)


func test_ember_vanguard_with_broken_knight_three_piece_set_synergy() -> void:
	# Ember Vanguard + Broken Sword + Broken Armor + Broken Pendant triggers Broken Knight 3pc!
	var preview: Dictionary = OriginCatalogScript.calculate_preview_stats(
		&"ember_vanguard",
		&"broken_sword",
		&"broken_armor",
		&"broken_pendant"
	)
	# Math breakdown:
	# HP: 5 (base) + 1 (origin) + 1 (broken_armor) + 1 (2pc synergy) = 8
	# Atk: 0 (base) + 0 (origin) + 1 (broken_sword) + 1 (3pc synergy) = 2
	# Def: 0 (base) + 1 (origin) + 1 (broken_armor) + 1 (2pc synergy) = 3
	# Res: 0.0 (base) + 0.0 (origin) + 0.05 (broken_pendant) + 0.10 (3pc synergy) = 0.15 (15%)
	# Decay: 0.0
	# Speed: 1.0 (100%)
	eq(preview["max_hp"], 8, "Ember Vanguard 3pc HP is 8")
	eq(preview["attack"], 2, "Ember Vanguard 3pc Atk is 2")
	eq(preview["defense"], 3, "Ember Vanguard 3pc Def is 3")
	almost(float(preview["toxin_resist"]), 0.15, 0.001, "Ember Vanguard 3pc Resist is 15%")
	almost(float(preview["toxin_decay"]), 0.0, 0.001, "Ember Vanguard 3pc Decay is 0.0")
	almost(float(preview["speed_mult"]), 1.0, 0.001, "Ember Vanguard 3pc Speed is 100%")


func test_boundary_clamping_in_preview_and_stats() -> void:
	# 1. Toxin resistance clamped to 0.8 max
	var preview_high_res: Dictionary = OriginCatalogScript.calculate_preview_stats(
		&"rust_automaton", # +20%
		&"broken_sword",
		&"scholar_cowl",   # +5%
		&"toxic_filter_talisman" # +15%
	)
	# 20% + 5% + 15% = 40%, within bound
	almost(float(preview_high_res["toxin_resist"]), 0.40, 0.001)

	# Direct test on CharacterStats with extreme stacked values
	var stats := _create_stats()
	stats.apply_origin(&"rust_automaton") # 0.20
	stats.recalculate([
		{"toxin_resist": 0.50},
		{"toxin_resist": 0.40}
	])
	# 0.20 + 0.50 + 0.40 = 1.10 -> clamped to 0.80
	almost(stats.get_toxin_resistance(), 0.80, 0.001, "Toxin resist clamped to 0.80 max")

	# 2. Speed multiplier floor clamped to 0.1 min
	stats.recalculate([
		{"speed_mult": -2.0}
	])
	almost(stats.get_speed_multiplier(), 0.10, 0.001, "Speed multiplier clamped to 0.10 min")

	# 3. Defense reduction floor clamped to 0 min
	stats.recalculate([
		{"defense": -10}
	])
	eq(stats.get_defense_reduction(), 0, "Defense reduction floor is 0")
