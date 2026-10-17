class_name M3AdversarialStressTest
extends TestCase
## Adversarial Stress Test Suite for Milestone 3:
## 1. Roundtrip with full bag (16 items) -> all item IDs strictly preserved in order.
## 2. Bag capacity boundary & overflow dropping (> 16 items in saved file).
## 3. Missing keys in [equipment] section (missing weapon key, missing bag key).
## 4. Unknown item IDs in [equipment] section (unknown weapon/armor/trinket, unknown bag items).
## 5. Unequipped empty slots roundtrip preservation (empty string vs missing key).
## 6. Multiple consecutive save/load roundtrips (10 cycles) -> zero data corruption, zero duplicate bag items.
## 7. Non-string type corruption in [equipment] keys (e.g. integer value).

const INVENTORY_SCRIPT := preload("res://scripts/player/equipment_inventory.gd")
const ITEM_SCRIPT := preload("res://scripts/data/equipment_item.gd")
const CATALOG_SCRIPT := preload("res://scripts/data/equipment_catalog.gd")
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")

const TEST_SAVE_PATH := "user://rustgrave_m3_stress_test_save.cfg"

const SLOT_WEAPON := &"weapon"
const SLOT_ARMOR := &"armor"
const SLOT_TRINKET := &"trinket"


## Stress Test 1: Roundtrip with full bag (16 items) -> all item IDs strictly preserved in order.
func test_01_full_bag_16_items_roundtrip_order_preservation() -> void:
	var original_save_path: String = SaveData.save_path
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Configure equipped items
	player.equipment.equipped[SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player.equipment.equipped[SLOT_ARMOR] = EquipmentCatalog.iron_carapace()
	player.equipment.equipped[SLOT_TRINKET] = EquipmentCatalog.toxic_ward()
	player.equipment.bag.clear()

	# Create exactly 16 distinct ordered items in bag
	var expected_bag_ids: Array[String] = [
		"broken_sword",
		"broken_armor",
		"broken_pendant",
		"iron_blade",
		"iron_carapace",
		"toxic_ward",
		"bone_charm",
		"broken_sword",
		"iron_blade",
		"broken_armor",
		"iron_carapace",
		"toxic_ward",
		"bone_charm",
		"broken_pendant",
		"iron_blade",
		"toxic_ward",
	]
	eq(expected_bag_ids.size(), 16, "bag test sequence has exactly 16 items")

	for id_str in expected_bag_ids:
		var item: EquipmentItem = EquipmentCatalog.for_id(StringName(id_str))
		ok(item != null, "item created from catalog: %s" % id_str)
		var added: bool = player.equipment.add_to_bag(item)
		ok(added, "item successfully added to bag: %s" % id_str)

	eq(player.equipment.bag.size(), 16, "player bag is at full 16-item capacity")

	# Save game through SaveData
	var saved: bool = SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player)
	ok(saved, "SaveData.save_game succeeded with full bag")

	# 1. Authoritative verification of ConfigFile on disk
	var cfg := ConfigFile.new()
	var load_err: int = cfg.load(TEST_SAVE_PATH)
	eq(load_err, OK, "ConfigFile loaded successfully from disk")
	ok(cfg.has_section("equipment"), "ConfigFile has [equipment] section")
	eq(cfg.get_value("equipment", "weapon"), "iron_blade", "disk weapon is iron_blade")
	eq(cfg.get_value("equipment", "armor"), "iron_carapace", "disk armor is iron_carapace")
	eq(cfg.get_value("equipment", "trinket"), "toxic_ward", "disk trinket is toxic_ward")

	var disk_bag: Variant = cfg.get_value("equipment", "bag")
	ok(disk_bag is Array, "disk bag is an Array")
	eq(disk_bag.size(), 16, "disk bag contains exactly 16 items")
	for i in range(16):
		eq(disk_bag[i], expected_bag_ids[i], "disk bag item [%d] preserves order and ID" % i)

	# 2. Re-load game through SaveData
	ok(SaveData.load_game(), "SaveData.load_game succeeded")

	# 3. Apply to a fresh player instance and verify in-memory restoration
	var player2 := await spawn_player(arena, Vector2(400, -24))
	player2.equipment.equipped[SLOT_WEAPON] = null
	player2.equipment.equipped[SLOT_ARMOR] = null
	player2.equipment.equipped[SLOT_TRINKET] = null
	player2.equipment.bag.clear()

	SaveData.apply_player(player2)

	# Check equipped slots
	ok(player2.equipment.get_equipped(SLOT_WEAPON) != null, "restored weapon is non-null")
	eq(player2.equipment.get_equipped(SLOT_WEAPON).id, &"iron_blade", "restored weapon is iron_blade")
	ok(player2.equipment.get_equipped(SLOT_ARMOR) != null, "restored armor is non-null")
	eq(player2.equipment.get_equipped(SLOT_ARMOR).id, &"iron_carapace", "restored armor is iron_carapace")
	ok(player2.equipment.get_equipped(SLOT_TRINKET) != null, "restored trinket is non-null")
	eq(player2.equipment.get_equipped(SLOT_TRINKET).id, &"toxic_ward", "restored trinket is toxic_ward")

	# Check bag order and IDs
	eq(player2.equipment.bag.size(), 16, "restored bag has exactly 16 items")
	for i in range(16):
		var it: EquipmentItem = player2.equipment.bag[i]
		ok(it != null, "restored bag item [%d] is non-null" % i)
		eq(String(it.id), expected_bag_ids[i], "restored bag item [%d] ID strictly preserved in order" % i)

	arena.queue_free()
	SaveData.delete_save()
	SaveData.save_path = original_save_path


## Stress Test 2: Bag capacity boundary & overflow dropping (> 16 items in saved file).
func test_02_bag_overflow_and_invalid_elements_truncated_to_max_capacity() -> void:
	var original_save_path: String = SaveData.save_path
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()

	# Craft an oversized save file with 24 items, whitespace, and unknown IDs
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("equipment", "weapon", "broken_sword")
	cfg.set_value("equipment", "armor", "broken_armor")
	cfg.set_value("equipment", "trinket", "broken_pendant")

	var oversized_bag: Array = []
	for i in range(20):
		oversized_bag.append("iron_blade")
	oversized_bag.insert(2, "   ")
	oversized_bag.insert(5, "unknown_mythic_weapon_999")
	oversized_bag.append("toxic_ward")
	cfg.set_value("equipment", "bag", oversized_bag)
	cfg.save(TEST_SAVE_PATH)

	ok(SaveData.load_game(), "SaveData loaded oversized bag save cleanly")
	var loaded_bag: Array = SaveData.data["equipment"]["bag"]
	ok(not loaded_bag.has("   "), "whitespace item was filtered out during load_game")
	ok(not loaded_bag.has(""), "empty item was filtered out during load_game")

	var inv: EquipmentInventory = EquipmentInventory.new()
	add_child(inv)
	inv.deserialize(SaveData.data["equipment"])

	# Capacity must be strictly clamped to MAX_BAG_CAPACITY (16)
	eq(inv.bag.size(), EquipmentInventory.MAX_BAG_CAPACITY, "bag size strictly capped at 16 even when save had > 20 items")
	for it in inv.bag:
		ok(it != null, "all loaded items in bag are non-null")
		eq(it.id, &"iron_blade", "loaded items match valid catalog items")

	inv.queue_free()
	SaveData.delete_save()
	SaveData.save_path = original_save_path


## Stress Test 3: Missing keys in [equipment] section (missing weapon key, missing bag key).
func test_03_missing_keys_in_equipment_section_falls_back_safely() -> void:
	var original_save_path: String = SaveData.save_path
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()

	# Omit "weapon" key and "bag" key intentionally
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("equipment", "armor", "broken_armor")
	cfg.set_value("equipment", "trinket", "broken_pendant")
	cfg.save(TEST_SAVE_PATH)

	ok(SaveData.load_game(), "load_game succeeds when keys are missing from [equipment]")
	var eq_data: Dictionary = SaveData.data.get("equipment", {})
	eq(eq_data.get("weapon"), "broken_sword", "missing weapon key falls back to broken_sword default")
	eq(eq_data.get("armor"), "broken_armor", "armor key preserved")
	eq(eq_data.get("trinket"), "broken_pendant", "trinket key preserved")
	var bag_data: Variant = eq_data.get("bag", null)
	ok(bag_data is Array, "bag defaults to an Array")
	eq((bag_data as Array).size(), 0, "missing bag key falls back to empty array")

	var inv: EquipmentInventory = EquipmentInventory.new()
	add_child(inv)
	inv.deserialize(eq_data)

	ok(inv.get_equipped(SLOT_WEAPON) != null, "weapon rehydrated from broken_sword default")
	eq(inv.get_equipped(SLOT_WEAPON).id, &"broken_sword")
	ok(inv.get_equipped(SLOT_ARMOR) != null, "armor rehydrated")
	eq(inv.get_equipped(SLOT_ARMOR).id, &"broken_armor")
	ok(inv.get_equipped(SLOT_TRINKET) != null, "trinket rehydrated")
	eq(inv.get_equipped(SLOT_TRINKET).id, &"broken_pendant")
	eq(inv.bag.size(), 0, "bag remains empty")

	inv.queue_free()
	SaveData.delete_save()
	SaveData.save_path = original_save_path


## Stress Test 4: Unknown item IDs in [equipment] section (safe fallback without crash).
func test_04_unknown_item_ids_in_equipment_and_bag() -> void:
	var original_save_path: String = SaveData.save_path
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("equipment", "weapon", "non_existent_blade_999")
	cfg.set_value("equipment", "armor", "broken_armor")
	cfg.set_value("equipment", "trinket", "corrupted_trinket_xyz")
	cfg.set_value("equipment", "bag", ["unknown_bag_item", "broken_sword", "another_bad_id"])
	cfg.save(TEST_SAVE_PATH)

	ok(SaveData.load_game(), "load_game succeeds with unknown item IDs")
	var eq_data: Dictionary = SaveData.data.get("equipment", {})

	var inv: EquipmentInventory = EquipmentInventory.new()
	add_child(inv)
	inv.deserialize(eq_data)

	# Unknown weapon -> safely becomes null (empty slot)
	ok(inv.get_equipped(SLOT_WEAPON) == null, "unknown weapon ID resolves safely to null without crash")
	# Valid armor -> resolves correctly
	ok(inv.get_equipped(SLOT_ARMOR) != null, "valid armor resolves correctly")
	eq(inv.get_equipped(SLOT_ARMOR).id, &"broken_armor")
	# Unknown trinket -> safely becomes null (empty slot)
	ok(inv.get_equipped(SLOT_TRINKET) == null, "unknown trinket ID resolves safely to null without crash")
	# Bag only keeps the valid item
	eq(inv.bag.size(), 1, "bag filtered out unknown items")
	eq(inv.bag[0].id, &"broken_sword")

	inv.queue_free()
	SaveData.delete_save()
	SaveData.save_path = original_save_path


## Stress Test 5: Unequipped empty slots roundtrip preservation (empty string vs missing key).
func test_05_unequipped_empty_slots_roundtrip_preservation() -> void:
	var original_save_path: String = SaveData.save_path
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Intentionally unequip weapon and armor, keep only trinket
	player.equipment.equipped[SLOT_WEAPON] = null
	player.equipment.equipped[SLOT_ARMOR] = null
	player.equipment.equipped[SLOT_TRINKET] = EquipmentCatalog.broken_pendant()
	player.equipment.bag.clear()
	player.equipment.add_to_bag(EquipmentCatalog.iron_blade())

	SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player)

	# Verify serialized ConfigFile has empty string for unequipped slots
	var cfg := ConfigFile.new()
	cfg.load(TEST_SAVE_PATH)
	eq(cfg.get_value("equipment", "weapon"), "", "unequipped weapon serialized as empty string")
	eq(cfg.get_value("equipment", "armor"), "", "unequipped armor serialized as empty string")
	eq(cfg.get_value("equipment", "trinket"), "broken_pendant", "equipped trinket serialized as ID")

	# Re-load and apply to fresh player
	ok(SaveData.load_game(), "load_game succeeded")
	var player2 := await spawn_player(arena, Vector2(400, -24))
	SaveData.apply_player(player2)

	ok(player2.equipment.get_equipped(SLOT_WEAPON) == null, "weapon slot correctly restored as empty (null)")
	ok(player2.equipment.get_equipped(SLOT_ARMOR) == null, "armor slot correctly restored as empty (null)")
	ok(player2.equipment.get_equipped(SLOT_TRINKET) != null, "trinket restored")
	eq(player2.equipment.get_equipped(SLOT_TRINKET).id, &"broken_pendant")

	arena.queue_free()
	SaveData.delete_save()
	SaveData.save_path = original_save_path


## Stress Test 6: Multiple consecutive save/load roundtrips (10 cycles: zero corruption, zero duplicates).
func test_06_multiple_consecutive_save_load_roundtrips_idempotent() -> void:
	var original_save_path: String = SaveData.save_path
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Configure initial equipment loadout
	player.equipment.equipped[SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player.equipment.equipped[SLOT_ARMOR] = EquipmentCatalog.iron_carapace()
	player.equipment.equipped[SLOT_TRINKET] = EquipmentCatalog.toxic_ward()
	player.equipment.bag.clear()
	player.equipment.add_to_bag(EquipmentCatalog.broken_sword())
	player.equipment.add_to_bag(EquipmentCatalog.broken_armor())
	player.equipment.add_to_bag(EquipmentCatalog.bone_charm())

	# Baseline stats
	player.stats.recalculate(player.equipment.get_all_equipped(), player.equipment.get_active_set_bonuses())
	var baseline_atk: int = player.stats.get_attack_bonus()
	var baseline_def: int = player.stats.get_defense_reduction()
	var baseline_hp_bonus: int = player.stats.get_max_hp_bonus()
	var baseline_resist: float = player.stats.get_toxin_resistance()
	var initial_bag_size: int = player.equipment.bag.size()
	eq(initial_bag_size, 3, "initial bag has 3 items")

	# Perform 10 consecutive full save/load/apply cycles
	for cycle in range(10):
		var saved: bool = SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player)
		ok(saved, "Cycle %d: save_game succeeded" % cycle)

		var loaded: bool = SaveData.load_game()
		ok(loaded, "Cycle %d: load_game succeeded" % cycle)

		SaveData.apply_player(player)

		# Assert exact preservation and ZERO duplicate accumulation
		eq(player.equipment.bag.size(), 3, "Cycle %d: bag size strictly preserved at 3 (zero duplicates)" % cycle)
		eq(player.equipment.bag[0].id, &"broken_sword", "Cycle %d: bag[0] preserved" % cycle)
		eq(player.equipment.bag[1].id, &"broken_armor", "Cycle %d: bag[1] preserved" % cycle)
		eq(player.equipment.bag[2].id, &"bone_charm", "Cycle %d: bag[2] preserved" % cycle)

		eq(player.equipment.get_equipped(SLOT_WEAPON).id, &"iron_blade", "Cycle %d: weapon intact" % cycle)
		eq(player.equipment.get_equipped(SLOT_ARMOR).id, &"iron_carapace", "Cycle %d: armor intact" % cycle)
		eq(player.equipment.get_equipped(SLOT_TRINKET).id, &"toxic_ward", "Cycle %d: trinket intact" % cycle)

		eq(player.stats.get_attack_bonus(), baseline_atk, "Cycle %d: attack bonus unchanged" % cycle)
		eq(player.stats.get_defense_reduction(), baseline_def, "Cycle %d: defense reduction unchanged" % cycle)
		eq(player.stats.get_max_hp_bonus(), baseline_hp_bonus, "Cycle %d: max hp bonus unchanged" % cycle)
		almost(player.stats.get_toxin_resistance(), baseline_resist, 0.001, "Cycle %d: toxin resist unchanged" % cycle)

	arena.queue_free()
	SaveData.delete_save()
	SaveData.save_path = original_save_path
