class_name OriginPersistenceLifecycleTest
extends TestCase
## Automated test suite for Rustgrave Character Origin Persistence & Lifecycle Integration (Milestone 3).
## Formally verifies:
## 1. init_new_game() initializes fresh ConfigFile with origin and loadout.
## 2. apply_player() restores origin bonuses and loadout correctly for all 3 origins.
## 3. Persistence across save/load roundtrips with equipment mutations.
## 4. Checkpoint death respawn and level transition state retention.
## 5. Backward compatibility: loading a legacy save without origin field defaults safely without errors.
## 6. Corrupted/unknown origin ID handling with safe fallbacks.
## 7. Full bag (16 items) retention combined with origin persistence.

const TEST_SAVE_PATH := "user://rustgrave_origin_lifecycle_test_save.cfg"

const SLOT_WEAPON: StringName = &"weapon"
const SLOT_ARMOR: StringName = &"armor"
const SLOT_TRINKET: StringName = &"trinket"


func setup() -> void:
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.lit_nests.clear()
	SaveData.consumed.clear()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.lit_nests.clear()
	SaveData.consumed.clear()
	Director.choice_hold = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


# ===========================================================================
# 1. init_new_game() ConfigFile & In-Memory Initialization
# ===========================================================================

func test_init_new_game_initializes_memory_and_writes_disk_save() -> void:
	ok(not SaveData.has_save(), "Precondition: No save file exists")

	var loadout := {
		"weapon": &"broken_sword",
		"armor": &"broken_armor",
		"trinket": &"broken_pendant",
		"bag": []
	}
	SaveData.init_new_game(&"ember_vanguard", loadout)

	ok(SaveData.has_save(), "SaveData.has_save() is true immediately after init_new_game")
	eq(SaveData.get_current_origin(), &"ember_vanguard", "Current origin is ember_vanguard")

	# In-memory dictionary verification
	ok(SaveData.data.has("player"), "data has [player] section")
	eq(SaveData.data["player"].get("origin", ""), "ember_vanguard", "In-memory origin is ember_vanguard")
	eq(SaveData.data["player"].get("hp", 0), 8, "In-memory starting HP is 8 (Ember Vanguard + Broken Knight 3pc)")
	eq(SaveData.data["player"].get("max_hp", 0), 8, "In-memory starting max HP is 8")

	ok(SaveData.data.has("equipment"), "data has [equipment] section")
	eq(SaveData.data["equipment"].get("weapon", ""), "broken_sword", "In-memory weapon is broken_sword")
	eq(SaveData.data["equipment"].get("armor", ""), "broken_armor", "In-memory armor is broken_armor")
	eq(SaveData.data["equipment"].get("trinket", ""), "broken_pendant", "In-memory trinket is broken_pendant")

	# Authoritative ConfigFile verification on disk
	var cfg := ConfigFile.new()
	var err := cfg.load(TEST_SAVE_PATH)
	eq(err, OK, "ConfigFile loads successfully from disk")
	ok(cfg.has_section("player"), "ConfigFile has [player] section")
	eq(String(cfg.get_value("player", "origin", "")), "ember_vanguard", "Disk save persists origin = ember_vanguard")
	eq(int(cfg.get_value("player", "hp", 0)), 8, "Disk save persists hp = 8")
	eq(int(cfg.get_value("player", "max_hp", 0)), 8, "Disk save persists max_hp = 8")

	ok(cfg.has_section("equipment"), "ConfigFile has [equipment] section")
	eq(String(cfg.get_value("equipment", "weapon", "")), "broken_sword", "Disk save persists weapon = broken_sword")
	eq(String(cfg.get_value("equipment", "armor", "")), "broken_armor", "Disk save persists armor = broken_armor")
	eq(String(cfg.get_value("equipment", "trinket", "")), "broken_pendant", "Disk save persists trinket = broken_pendant")


# ===========================================================================
# 2. apply_player() Restoration: Ember Vanguard (HP +1, Def +1)
# ===========================================================================

func test_apply_player_ember_vanguard_restores_stats_and_loadout() -> void:
	var loadout := {
		"weapon": &"broken_sword",
		"armor": &"broken_armor",
		"trinket": &"broken_pendant",
		"bag": []
	}
	SaveData.init_new_game(&"ember_vanguard", loadout)

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	SaveData.apply_player(player)

	# Verify origin and gear assignment
	eq(player.origin, &"ember_vanguard", "Player.origin property restored to ember_vanguard")
	eq(player.stats.get_origin_id(), &"ember_vanguard", "CharacterStats.origin_id is ember_vanguard")
	eq(player.equipment.get_equipped(SLOT_WEAPON).id, &"broken_sword", "Equipped weapon is broken_sword")
	eq(player.equipment.get_equipped(SLOT_ARMOR).id, &"broken_armor", "Equipped armor is broken_armor")
	eq(player.equipment.get_equipped(SLOT_TRINKET).id, &"broken_pendant", "Equipped trinket is broken_pendant")

	# Stats calculation (5 base + 1 origin + 1 armor + 1 set_2pc = 8 HP)
	eq(player.health.max_hp, 8, "Max HP expanded to 8")
	eq(player.health.current, 8, "Current HP restored to 8")
	eq(player.stats.get_attack_bonus(), 2, "Attack bonus is 2 (0 base + 0 origin + 1 sword + 1 set_3pc)")
	eq(player.stats.get_defense_reduction(), 3, "Defense reduction is 3 (0 base + 1 origin + 1 armor + 1 set_2pc)")
	almost(player.stats.get_toxin_resistance(), 0.15, 0.001, "Toxin resist is 15% (0 base + 0 origin + 5% pendant + 10% set_3pc)")
	almost(player.stats.get_speed_multiplier(), 1.0, 0.001, "Speed multiplier is 1.0 (100%)")

	arena.queue_free()


# ===========================================================================
# 3. apply_player() Restoration: Scrap Scavenger (Atk +1, Speed +10%)
# ===========================================================================

func test_apply_player_scrap_scavenger_restores_stats_and_loadout() -> void:
	var loadout := {
		"weapon": &"scavenger_blade",
		"armor": &"scavenger_rags",
		"trinket": &"bone_amulet",
		"bag": []
	}
	SaveData.init_new_game(&"scrap_scavenger", loadout)

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	SaveData.apply_player(player)

	eq(player.origin, &"scrap_scavenger", "Player origin is scrap_scavenger")
	eq(player.stats.get_origin_id(), &"scrap_scavenger", "CharacterStats origin is scrap_scavenger")
	eq(player.equipment.get_equipped(SLOT_WEAPON).id, &"scavenger_blade", "Equipped weapon is scavenger_blade")
	eq(player.equipment.get_equipped(SLOT_ARMOR).id, &"scavenger_rags", "Equipped armor is scavenger_rags")
	eq(player.equipment.get_equipped(SLOT_TRINKET).id, &"bone_amulet", "Equipped trinket is bone_amulet")

	# Stats: 5 base + 0 origin + 0 armor + 1 bone_amulet = 6 HP
	eq(player.health.max_hp, 6, "Max HP is 6 (5 base + 1 bone_amulet)")
	eq(player.health.current, 6, "Current HP is 6")
	# Attack: 0 base + 1 origin + 1 blade = 2
	eq(player.stats.get_attack_bonus(), 2, "Attack bonus is 2 (origin + blade)")
	# Defense: 0 base + 0 origin + 1 rags = 1
	eq(player.stats.get_defense_reduction(), 1, "Defense reduction is 1 (rags)")
	# Speed: 1.0 base + 0.10 origin + 0.05 amulet = 1.15
	almost(player.stats.get_speed_multiplier(), 1.15, 0.001, "Speed multiplier is 1.15 (+15%)")

	arena.queue_free()


# ===========================================================================
# 4. apply_player() Restoration: Rust Automaton (Resist +20%, Decay +50%)
# ===========================================================================

func test_apply_player_rust_automaton_restores_stats_and_loadout() -> void:
	var loadout := {
		"weapon": &"scholar_probe",
		"armor": &"scholar_cowl",
		"trinket": &"toxic_filter_talisman",
		"bag": []
	}
	SaveData.init_new_game(&"rust_automaton", loadout)

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	SaveData.apply_player(player)

	eq(player.origin, &"rust_automaton", "Player origin is rust_automaton")
	eq(player.equipment.get_equipped(SLOT_WEAPON).id, &"scholar_probe", "Equipped weapon is scholar_probe")
	eq(player.equipment.get_equipped(SLOT_ARMOR).id, &"scholar_cowl", "Equipped armor is scholar_cowl")
	eq(player.equipment.get_equipped(SLOT_TRINKET).id, &"toxic_filter_talisman", "Equipped trinket is toxic_filter_talisman")

	# Toxin Resist: 0.0 base + 0.20 origin + 0.05 cowl + 0.15 talisman = 0.40 (40%)
	almost(player.stats.get_toxin_resistance(), 0.40, 0.001, "Toxin resist is 40%")
	# Toxin Decay: 0.0 base + 0.50 origin + 0.50 talisman = 1.0
	almost(player.stats.get_toxin_decay_bonus(), 1.0, 0.001, "Toxin decay is 1.0/s")

	arena.queue_free()


# ===========================================================================
# 5. Save/Load Roundtrip with Mid-Game Equipment Changes
# ===========================================================================

func test_save_load_roundtrip_preserves_origin_and_mutated_loadout() -> void:
	# Start as Scrap Scavenger
	var loadout := {
		"weapon": &"scavenger_blade",
		"armor": &"scavenger_rags",
		"trinket": &"bone_amulet",
		"bag": []
	}
	SaveData.init_new_game(&"scrap_scavenger", loadout)

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	SaveData.apply_player(player)

	# Swap weapon: player equips iron_blade, scavenger_blade placed in bag
	var old_weapon = player.equipment.get_equipped(SLOT_WEAPON)
	player.equipment.equipped[SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player.equipment.bag.append(old_weapon)
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	eq(player.stats.get_attack_bonus(), 3, "Scrap Scavenger (1) + Iron Blade (2) = 3 Attack")

	# Save game
	var saved := SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(250, 320))
	ok(saved, "save_game succeeded")

	# Completely wipe in-memory state to simulate clean game restart
	SaveData.data = {}
	player.queue_free()
	await flush(2)

	# Re-load save
	ok(SaveData.load_game(), "load_game succeeded from disk")
	eq(SaveData.get_current_origin(), &"scrap_scavenger", "Origin scrap_scavenger preserved across reload")

	# Spawn new player and apply loaded save
	var player2: Player = await spawn_player(arena)
	SaveData.apply_player(player2)

	eq(player2.origin, &"scrap_scavenger", "Rehydrated player retains scrap_scavenger origin")
	eq(player2.equipment.get_equipped(SLOT_WEAPON).id, &"iron_blade", "Rehydrated weapon is iron_blade")
	eq(player2.equipment.bag.size(), 1, "Bag contains 1 item")
	eq(player2.equipment.bag[0].id, &"scavenger_blade", "Bag item is scavenger_blade")
	eq(player2.stats.get_attack_bonus(), 3, "Attack bonus 3 correctly restored")

	arena.queue_free()


# ===========================================================================
# 6. Death & Checkpoint Respawn Retains Origin and Full Health
# ===========================================================================

func test_checkpoint_respawn_retains_origin_and_restores_full_health() -> void:
	SaveData.init_new_game(&"ember_vanguard", {
		"weapon": &"broken_sword",
		"armor": &"broken_armor",
		"trinket": &"broken_pendant"
	})

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	SaveData.apply_player(player)

	# Register lit nest checkpoint and save
	SaveData.register_lit_nest("Props/EmberNest_01")
	var saved := SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(150, 320))
	ok(saved, "Checkpoint saved")

	# Player takes fatal damage
	player.health.take_damage(999, null)
	eq(player.health.current, 0, "Player died")
	player.queue_free()
	await flush(2)

	# Respawn flow: load_game -> spawn player -> apply_player -> full health
	ok(SaveData.load_game(), "SaveData.load_game succeeded on respawn")
	var respawned_player: Player = await spawn_player(arena)
	SaveData.apply_player(respawned_player)

	eq(respawned_player.origin, &"ember_vanguard", "Respawned player origin retained as ember_vanguard")
	eq(respawned_player.health.max_hp, 8, "Respawned player max HP is 8")
	eq(respawned_player.stats.get_defense_reduction(), 3, "Respawned player defense reduction is 3")
	eq(respawned_player.equipment.get_equipped(SLOT_WEAPON).id, &"broken_sword", "Weapon retained")
	eq(respawned_player.equipment.get_equipped(SLOT_ARMOR).id, &"broken_armor", "Armor retained")

	arena.queue_free()


# ===========================================================================
# 7. Cross-Level Scene Transition Retains Origin
# ===========================================================================

func test_cross_level_scene_transition_retains_origin() -> void:
	SaveData.init_new_game(&"rust_automaton", {
		"weapon": &"scholar_probe",
		"armor": &"scholar_cowl",
		"trinket": &"toxic_filter_talisman"
	})

	var arena_lvl1 := Node2D.new()
	add_child(arena_lvl1)
	build_floor(arena_lvl1)
	var player_lvl1: Player = await spawn_player(arena_lvl1)
	SaveData.apply_player(player_lvl1)

	# Simulate LevelExit transition to Level 2
	var level2_path := "res://scenes/levels/Level02_Undercroft.tscn"
	var arrival_spawn := Vector2(80, 200)
	var saved := SaveData.save_game(level2_path, player_lvl1, arrival_spawn)
	ok(saved, "Level transition save succeeded")

	player_lvl1.queue_free()
	arena_lvl1.queue_free()
	await flush(2)

	# Level 2 boots up: load_game -> spawn player -> apply_player
	ok(SaveData.load_game(), "Level 2 load_game succeeded")
	eq(SaveData.saved_scene(), level2_path, "Saved scene is Level 2")

	var arena_lvl2 := Node2D.new()
	add_child(arena_lvl2)
	build_floor(arena_lvl2)
	var player_lvl2: Player = await spawn_player(arena_lvl2)
	SaveData.apply_player(player_lvl2)

	eq(player_lvl2.origin, &"rust_automaton", "Level 2 player origin retained as rust_automaton")
	almost(player_lvl2.stats.get_toxin_resistance(), 0.40, 0.001, "Level 2 toxin resist 40% preserved")
	almost(player_lvl2.stats.get_toxin_decay_bonus(), 1.0, 0.001, "Level 2 toxin decay 1.0/s preserved")

	arena_lvl2.queue_free()


# ===========================================================================
# 8. Backward Compatibility: Legacy Save Without Origin Key
# ===========================================================================

func test_legacy_save_without_origin_key_defaults_safely() -> void:
	# Craft a legacy save file with NO origin key in [player]
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("player", "max_hp", 5)
	cfg.set_value("player", "toxin", 0.0)
	cfg.set_value("player", "max_toxin", 100.0)
	cfg.set_value("player", "pos_x", 120.0)
	cfg.set_value("player", "pos_y", 240.0)
	cfg.set_value("player", "facing", 1)
	cfg.set_value("player", "pouch", [])
	cfg.set_value("player", "sockets", [])
	cfg.set_value("equipment", "weapon", "broken_sword")
	cfg.set_value("equipment", "armor", "broken_armor")
	cfg.set_value("equipment", "trinket", "broken_pendant")
	cfg.set_value("equipment", "bag", [])
	ok(cfg.save(TEST_SAVE_PATH) == OK, "Legacy save file created on disk")

	ok(SaveData.load_game(), "SaveData.load_game() cleanly loads legacy save")
	eq(SaveData.get_current_origin(), &"", "Legacy save returns empty StringName origin")
	ok(not SaveData.data["player"].has("origin"), "data[player] has no origin key (legacy format preserved)")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	SaveData.apply_player(player)

	eq(player.origin, &"", "Player origin is empty StringName")
	eq(player.stats.get_origin_id(), &"", "CharacterStats origin_id is empty StringName")
	# Equipment bonuses calculate normally (5 base + 1 armor + 1 set = 7 HP)
	eq(player.health.max_hp, 7, "Effective max HP is 7 (5 base + 2 equipment)")
	eq(player.stats.get_attack_bonus(), 2, "Attack bonus is 2 (1 sword + 1 set)")
	eq(player.stats.get_defense_reduction(), 2, "Defense reduction is 2 (1 armor + 1 set)")

	arena.queue_free()


# ===========================================================================
# 9. Corrupted / Unknown Origin ID Safe Fallback
# ===========================================================================

func test_corrupted_or_unknown_origin_id_safe_fallback() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "origin", "glitch_unknown_origin_999")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("player", "max_hp", 5)
	cfg.set_value("player", "pos_x", 0.0)
	cfg.set_value("player", "pos_y", 0.0)
	cfg.set_value("equipment", "weapon", "broken_sword")
	cfg.set_value("equipment", "armor", "broken_armor")
	cfg.set_value("equipment", "trinket", "broken_pendant")
	cfg.set_value("equipment", "bag", [])
	ok(cfg.save(TEST_SAVE_PATH) == OK, "Save with invalid origin created")

	ok(SaveData.load_game(), "load_game loads despite unknown origin ID")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# apply_player should handle unknown origin gracefully without crashing or throwing engine errors
	SaveData.apply_player(player)

	eq(player.stats.get_origin_id(), &"glitch_unknown_origin_999", "Origin ID string preserved")
	# Since origin is not in OriginCatalog, 0 origin modifiers are applied
	# Effective HP is 5 base + 2 equipment = 7 (not corrupted)
	eq(player.health.max_hp, 7, "Max HP falls back to equipment-only bonus (7)")

	arena.queue_free()


# ===========================================================================
# 10. Full Bag (16 Items) + Custom Origin Persistence
# ===========================================================================

func test_full_bag_16_items_combined_with_origin_persistence() -> void:
	SaveData.init_new_game(&"scrap_scavenger", {
		"weapon": &"scavenger_blade",
		"armor": &"scavenger_rags",
		"trinket": &"bone_amulet"
	})

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	SaveData.apply_player(player)

	# Fill bag with 16 distinct items
	player.equipment.bag.clear()
	for i in range(16):
		var item_id := &"broken_sword" if i % 2 == 0 else &"broken_armor"
		player.equipment.add_to_bag(EquipmentCatalog.for_id(item_id))
	eq(player.equipment.bag.size(), 16, "Player bag is at full 16 capacity")

	# Save game
	ok(SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player), "Save game succeeded")

	player.queue_free()
	await flush(2)

	# Re-load
	ok(SaveData.load_game(), "Load game succeeded")
	var player2: Player = await spawn_player(arena)
	SaveData.apply_player(player2)

	eq(player2.origin, &"scrap_scavenger", "Origin retained as scrap_scavenger")
	eq(player2.equipment.bag.size(), 16, "Bag retains exactly 16 items")
	eq(player2.stats.get_attack_bonus(), 2, "Attack bonus is 2")
	almost(player2.stats.get_speed_multiplier(), 1.15, 0.001, "Speed multiplier is 1.15")

	arena.queue_free()
