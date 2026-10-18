class_name SaveLegacyMigrationChallengeTest
extends TestCase
## Adversarial Challenge Suite: Legacy Save Migration & Backward Compatibility
## Formally tests:
## 1. Loading legacy save files lacking both [player].origin and [equipment] sections.
## 2. Loading legacy save files lacking only [equipment] section (origin present).
## 3. Loading legacy save files lacking only [player].origin key (custom equipment present).
## 4. Corrupted, whitespace, numeric, and unrecognized origin strings safe fallback.
## 5. Corrupted equipment keys/values (invalid item IDs, mixed bag types) graceful degradation.
## 6. Migration roundtrip: legacy save loaded -> re-saved to disk -> re-loaded as modern format.
## 7. save_equipment() on legacy-loaded state persists equipment without corrupting legacy data.

const TEST_SAVE_PATH := "user://rustgrave_legacy_migration_challenge_save.cfg"

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


# ===========================================================================
# 1. Legacy save lacking BOTH [player].origin AND [equipment]
# ===========================================================================

func test_legacy_save_lacking_both_origin_and_equipment_sections() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "hp", 4)
	cfg.set_value("player", "max_hp", 5)
	cfg.set_value("player", "toxin", 15.0)
	cfg.set_value("player", "max_toxin", 100.0)
	cfg.set_value("player", "pos_x", 100.0)
	cfg.set_value("player", "pos_y", 200.0)
	cfg.set_value("player", "facing", -1)
	cfg.set_value("player", "pouch", [])
	cfg.set_value("player", "sockets", [])
	# Intentionally NO [player].origin and NO [equipment] section
	ok(cfg.save(TEST_SAVE_PATH) == OK, "Saved raw legacy file without origin or equipment")

	ok(SaveData.load_game(), "SaveData.load_game() loaded successfully")
	eq(SaveData.get_current_origin(), &"", "Origin defaults to empty StringName")

	# Check default fallback in memory
	ok(SaveData.data.has("equipment"), "data has equipment section populated with defaults")
	eq(SaveData.data["equipment"].get("weapon", ""), "broken_sword", "Default weapon fallback")
	eq(SaveData.data["equipment"].get("armor", ""), "broken_armor", "Default armor fallback")
	eq(SaveData.data["equipment"].get("trinket", ""), "broken_pendant", "Default trinket fallback")
	eq(SaveData.data["equipment"].get("bag", []).size(), 0, "Default bag fallback is empty")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Apply player must execute with zero errors and no crashes
	SaveData.apply_player(player)

	# Origin fallback
	eq(player.origin, &"", "Player origin is empty StringName")
	eq(player.stats.get_origin_id(), &"", "CharacterStats origin_id is empty StringName")

	# Equipment fallback
	var w = player.equipment.get_equipped(SLOT_WEAPON)
	var a = player.equipment.get_equipped(SLOT_ARMOR)
	var t = player.equipment.get_equipped(SLOT_TRINKET)
	ok(w != null and w.id == &"broken_sword", "Equipped broken_sword by fallback")
	ok(a != null and a.id == &"broken_armor", "Equipped broken_armor by fallback")
	ok(t != null and t.id == &"broken_pendant", "Equipped broken_pendant by fallback")

	# Effective stats calculation: 5 base + 1 armor + 1 set = 7 max HP
	eq(player.health.max_hp, 7, "Max HP is 7 (5 base + 2 from fallback broken knight set)")
	eq(player.health.current, 4, "Current HP preserved from save (4)")
	eq(player.stats.get_attack_bonus(), 2, "Attack bonus is 2 (1 sword + 1 set)")
	eq(player.stats.get_defense_reduction(), 2, "Defense reduction is 2 (1 armor + 1 set)")
	almost(player.stats.get_toxin_resistance(), 0.15, 0.001, "Toxin resist is 15% (5% pendant + 10% set)")

	player.queue_free()
	arena.queue_free()


# ===========================================================================
# 2. Legacy save lacking ONLY [equipment] (Origin present)
# ===========================================================================

func test_legacy_save_lacking_only_equipment_section() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "origin", "ember_vanguard")
	cfg.set_value("player", "hp", 6)
	cfg.set_value("player", "max_hp", 6)
	cfg.set_value("player", "pos_x", 50.0)
	cfg.set_value("player", "pos_y", 150.0)
	ok(cfg.save(TEST_SAVE_PATH) == OK, "Saved file with origin but no equipment section")

	ok(SaveData.load_game(), "load_game succeeds")
	eq(SaveData.get_current_origin(), &"ember_vanguard", "Origin recognized as ember_vanguard")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	SaveData.apply_player(player)

	eq(player.origin, &"ember_vanguard")
	eq(player.stats.get_origin_id(), &"ember_vanguard")

	# Equipment falls back to default broken knight gear
	eq(player.equipment.get_equipped(SLOT_WEAPON).id, &"broken_sword")
	eq(player.equipment.get_equipped(SLOT_ARMOR).id, &"broken_armor")
	eq(player.equipment.get_equipped(SLOT_TRINKET).id, &"broken_pendant")

	# Stats: 5 base + 1 origin + 1 armor + 1 set = 8 HP
	eq(player.health.max_hp, 8, "Max HP is 8 (Ember Vanguard + 3pc Broken Knight)")
	eq(player.stats.get_defense_reduction(), 3, "Defense reduction is 3 (1 origin + 1 armor + 1 set)")

	player.queue_free()
	arena.queue_free()


# ===========================================================================
# 3. Legacy save lacking ONLY [player].origin (Custom Equipment present)
# ===========================================================================

func test_legacy_save_lacking_only_origin_with_custom_equipment() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("player", "max_hp", 5)
	cfg.set_value("equipment", "weapon", "iron_blade")
	cfg.set_value("equipment", "armor", "iron_carapace")
	cfg.set_value("equipment", "trinket", "")
	cfg.set_value("equipment", "bag", ["bone_charm"])
	ok(cfg.save(TEST_SAVE_PATH) == OK, "Saved file with custom equipment but no origin")

	ok(SaveData.load_game(), "load_game succeeds")
	eq(SaveData.get_current_origin(), &"", "Origin is empty")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	SaveData.apply_player(player)

	eq(player.origin, &"")
	eq(player.equipment.get_equipped(SLOT_WEAPON).id, &"iron_blade")
	eq(player.equipment.get_equipped(SLOT_ARMOR).id, &"iron_carapace")
	ok(player.equipment.get_equipped(SLOT_TRINKET) == null, "Empty trinket preserved as null")
	eq(player.equipment.bag.size(), 1)
	eq(player.equipment.bag[0].id, &"bone_charm")

	# Stats: 5 base + 0 origin + 2 iron_carapace = 7 HP; atk = 2; def = 2
	eq(player.health.max_hp, 7)
	eq(player.stats.get_attack_bonus(), 2)
	eq(player.stats.get_defense_reduction(), 2)

	player.queue_free()
	arena.queue_free()


# ===========================================================================
# 4. Corrupted, Whitespace, Numeric & Unrecognized Origin Strings Fallback
# ===========================================================================

func test_corrupted_origin_variants_graceful_fallback() -> void:
	var test_variants: Array = [
		"nonexistent_unknown_origin_class",
		"   ",
		"\t  \n",
		"123456",
		"!@#$%^&*()_+{}[]:;<>?,./"
	]

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)

	for variant in test_variants:
		var cfg := ConfigFile.new()
		cfg.set_value("meta", "version", 1)
		cfg.set_value("player", "origin", variant)
		cfg.set_value("player", "hp", 5)
		cfg.set_value("player", "max_hp", 5)
		cfg.set_value("equipment", "weapon", "broken_sword")
		cfg.set_value("equipment", "armor", "broken_armor")
		cfg.set_value("equipment", "trinket", "broken_pendant")
		cfg.set_value("equipment", "bag", [])
		ok(cfg.save(TEST_SAVE_PATH) == OK, "Saved corrupted origin variant: %s" % str(variant))

		ok(SaveData.load_game(), "load_game handles variant without crashing")

		var player: Player = await spawn_player(arena)
		SaveData.apply_player(player)

		# Verify stats calculation didn't produce NaN or negative values
		ok(player.health.max_hp >= 5, "Max HP is valid (>= 5)")
		ok(player.stats.get_attack_bonus() >= 0, "Attack bonus is valid (>= 0)")
		ok(player.stats.get_defense_reduction() >= 0, "Defense reduction is valid (>= 0)")
		ok(player.stats.get_toxin_resistance() >= 0.0, "Toxin resist is valid (>= 0.0)")
		ok(player.stats.get_speed_multiplier() >= 0.1, "Speed multiplier is valid (>= 0.1)")

		player.queue_free()
		await flush(1)

	arena.queue_free()


# ===========================================================================
# 5. Corrupted Equipment Keys & Bag Types Fallback
# ===========================================================================

func test_corrupted_equipment_keys_and_bag_types_fallback() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("player", "origin", "ember_vanguard")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("player", "max_hp", 5)
	# Corrupted item IDs
	cfg.set_value("equipment", "weapon", "totally_bogus_weapon_id_9999")
	cfg.set_value("equipment", "armor", "imaginary_plate_mail")
	cfg.set_value("equipment", "trinket", "")
	# Corrupted bag with mixed invalid types
	cfg.set_value("equipment", "bag", [
		"broken_sword",
		"phantom_item_xyz",
		"",
		"   ",
		"broken_pendant"
	])
	ok(cfg.save(TEST_SAVE_PATH) == OK, "Saved corrupted equipment file")

	ok(SaveData.load_game(), "load_game loaded corrupted equipment file")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Must not throw runtime error or crash
	SaveData.apply_player(player)

	# Invalid equipped IDs should gracefully evaluate to null
	ok(player.equipment.get_equipped(SLOT_WEAPON) == null, "Unrecognized weapon evaluates to null")
	ok(player.equipment.get_equipped(SLOT_ARMOR) == null, "Unrecognized armor evaluates to null")
	ok(player.equipment.get_equipped(SLOT_TRINKET) == null, "Empty trinket evaluates to null")

	# Bag should filter out empty or invalid items and keep only valid equipment items
	eq(player.equipment.bag.size(), 2, "Bag retained exactly the 2 valid items")
	eq(player.equipment.bag[0].id, &"broken_sword")
	eq(player.equipment.bag[1].id, &"broken_pendant")

	# Stats calculation with ember_vanguard + 0 equipped items
	# Base 5 + 1 origin = 6 HP
	eq(player.health.max_hp, 6, "Max HP is 6 (5 base + 1 origin + 0 equipment)")
	eq(player.stats.get_attack_bonus(), 0, "Attack bonus is 0")
	eq(player.stats.get_defense_reduction(), 1, "Defense reduction is 1 (origin)")

	player.queue_free()
	arena.queue_free()


# ===========================================================================
# 6. Legacy Save Migration Roundtrip Resave
# ===========================================================================

func test_legacy_save_migration_roundtrip_resave() -> void:
	# 1. Start with bare minimum legacy file (Version 1, no origin, no equipment)
	var legacy_cfg := ConfigFile.new()
	legacy_cfg.set_value("meta", "version", 1)
	legacy_cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	legacy_cfg.set_value("player", "hp", 3)
	legacy_cfg.set_value("player", "max_hp", 5)
	legacy_cfg.set_value("player", "toxin", 10.0)
	legacy_cfg.set_value("player", "max_toxin", 100.0)
	legacy_cfg.set_value("player", "pos_x", 120.0)
	legacy_cfg.set_value("player", "pos_y", 240.0)
	legacy_cfg.set_value("player", "facing", 1)
	ok(legacy_cfg.save(TEST_SAVE_PATH) == OK, "Saved minimal legacy file")

	# 2. Load into SaveData
	ok(SaveData.load_game(), "Legacy save loads successfully")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# 3. Apply legacy save to player
	SaveData.apply_player(player)

	# 4. Re-save modern state (e.g. at next checkpoint or level exit)
	var saved := SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(150, 250))
	ok(saved, "SaveData.save_game() successfully writes migrated state")

	# 5. Clear all in-memory data
	SaveData.data = {}
	player.queue_free()
	await flush(2)

	# 6. Verify modern disk format directly
	var disk_cfg := ConfigFile.new()
	var err := disk_cfg.load(TEST_SAVE_PATH)
	eq(err, OK, "Disk save re-loads cleanly as ConfigFile")
	ok(disk_cfg.has_section("equipment"), "Migrated save now contains [equipment] section")
	eq(String(disk_cfg.get_value("equipment", "weapon", "")), "broken_sword", "Persisted default weapon")
	eq(String(disk_cfg.get_value("equipment", "armor", "")), "broken_armor", "Persisted default armor")
	eq(String(disk_cfg.get_value("equipment", "trinket", "")), "broken_pendant", "Persisted default trinket")

	# 7. Re-hydrate player from migrated save
	ok(SaveData.load_game(), "SaveData.load_game() reads migrated file")
	var fresh_player: Player = await spawn_player(arena)
	SaveData.apply_player(fresh_player)

	eq(fresh_player.equipment.get_equipped(SLOT_WEAPON).id, &"broken_sword")
	eq(fresh_player.equipment.get_equipped(SLOT_ARMOR).id, &"broken_armor")
	eq(fresh_player.equipment.get_equipped(SLOT_TRINKET).id, &"broken_pendant")
	eq(fresh_player.health.max_hp, 7, "Effective max HP matches migrated loadout")

	fresh_player.queue_free()
	arena.queue_free()


# ===========================================================================
# 7. save_equipment() on Legacy State
# ===========================================================================

func test_save_equipment_on_legacy_state() -> void:
	var legacy_cfg := ConfigFile.new()
	legacy_cfg.set_value("meta", "version", 1)
	legacy_cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	legacy_cfg.set_value("player", "hp", 5)
	legacy_cfg.set_value("player", "max_hp", 5)
	ok(legacy_cfg.save(TEST_SAVE_PATH) == OK, "Saved minimal legacy file")

	ok(SaveData.load_game(), "Loaded legacy file")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	SaveData.apply_player(player)

	# Change equipment
	player.equipment.equipped[SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player.equipment.equipment_changed.emit()

	# Call standalone save_equipment()
	ok(SaveData.save_equipment(player), "save_equipment succeeded")

	# Inspect disk ConfigFile
	var check_cfg := ConfigFile.new()
	ok(check_cfg.load(TEST_SAVE_PATH) == OK)
	ok(check_cfg.has_section("equipment"))
	eq(String(check_cfg.get_value("equipment", "weapon", "")), "iron_blade")
	# Legacy player data should be preserved
	ok(check_cfg.has_section("player"))
	eq(int(check_cfg.get_value("player", "hp", 0)), 5)

	player.queue_free()
	arena.queue_free()
