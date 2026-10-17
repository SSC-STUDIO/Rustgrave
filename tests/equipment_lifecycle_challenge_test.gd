class_name EquipmentLifecycleChallengeTest
extends TestCase
## Adversarial Stress & Lifecycle Retention Challenge Suite for Milestone 3.
## Formally tests:
## 1. Player death and respawn at checkpoint (custom loadout, bag retention, 0 duplication, 0 starter overwrite).
## 2. Repeated consecutive deaths/respawns (stress loop, zero item drift/duplication).
## 3. Fully unequipped loadout survival (ensures starter gear is not forcefully restored or duplicated into bag).
## 4. Maximum bag capacity (16 items) roundtrip across death/respawn without truncation.
## 5. Cross-level scene transitions via LevelExit.travel() (persistence, set synergies, health sync).
## 6. Multi-level chained transitions with equipment mutations between levels.
## 7. Death after level transition before lighting checkpoint (preserves transition arrival state).

const TEST_SAVE_PATH := "user://rustgrave_lifecycle_challenge_save.cfg"

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


func test_checkpoint_respawn_retains_equipment_and_bag_without_reset_or_duplication() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# 1. Equip non-starter gear: iron_blade, iron_carapace, empty trinket
	player.equipment.equipped[EquipmentInventory.SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player.equipment.equipped[EquipmentInventory.SLOT_ARMOR] = EquipmentCatalog.iron_carapace()
	player.equipment.equipped[EquipmentInventory.SLOT_TRINKET] = null
	player.equipment.bag.clear()
	player.equipment.bag.append(EquipmentCatalog.broken_sword())
	player.equipment.bag.append(EquipmentCatalog.broken_armor())
	player.equipment.bag.append(EquipmentCatalog.broken_pendant())
	player.equipment.bag.append(EquipmentCatalog.bone_charm())
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	eq(player.equipment.bag.size(), 4, "setup 4 items in bag")
	eq(player.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade")
	eq(player.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR).id, &"iron_carapace")
	ok(player.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET) == null, "trinket slot is empty")

	# 2. Checkpoint save (simulating lighting an Ember Nest)
	var saved: bool = SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(120, 240))
	ok(saved, "checkpoint save succeeded")

	# 3. Kill player
	var died_fired: Array = [false]
	player.health.died.connect(func(): died_fired[0] = true)
	player.health.take_damage(999, null)
	ok(died_fired[0], "player died signal emitted")
	eq(player.health.current, 0, "player health reduced to 0")

	# 4. Clean up dead player
	player.queue_free()
	await flush(2)

	# 5. Respawn: instantiate fresh Player scene (simulating level reload at checkpoint)
	var fresh_player: Player = await spawn_player(arena)
	ok(SaveData.load_game(), "save re-loaded successfully")
	SaveData.apply_player(fresh_player)

	# 6. Strict Verifications:
	# A: Equipment must NOT be reset to broken knight starter gear
	var weapon: EquipmentItem = fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON)
	ok(weapon != null, "weapon is equipped")
	eq(weapon.id, &"iron_blade", "weapon is iron_blade, not broken_sword")

	var armor: EquipmentItem = fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR)
	ok(armor != null, "armor is equipped")
	eq(armor.id, &"iron_carapace", "armor is iron_carapace, not broken_armor")

	var trinket: EquipmentItem = fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET)
	ok(trinket == null, "trinket slot strictly retained as null, not filled with broken_pendant")

	# B: Bag items must be 100% retained and NOT duplicated
	eq(fresh_player.equipment.bag.size(), 4, "bag size strictly 4 (no duplicates, no omissions)")
	eq(fresh_player.equipment.bag[0].id, &"broken_sword")
	eq(fresh_player.equipment.bag[1].id, &"broken_armor")
	eq(fresh_player.equipment.bag[2].id, &"broken_pendant")
	eq(fresh_player.equipment.bag[3].id, &"bone_charm")

	# C: Stats calculation must match equipped items immediately
	eq(fresh_player.stats.get_attack_bonus(), 2, "effective attack bonus is 2 (iron_blade)")
	eq(fresh_player.stats.get_defense_reduction(), 2, "effective defense reduction is 2 (iron_carapace)")
	eq(fresh_player.health.max_hp, 7, "max HP expanded to 7 (5 base + 2 iron_carapace)")

	fresh_player.queue_free()
	arena.queue_free()


func test_repeated_death_respawns_zero_item_duplication_or_drift() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Setup custom loadout
	player.equipment.equipped[EquipmentInventory.SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player.equipment.equipped[EquipmentInventory.SLOT_ARMOR] = EquipmentCatalog.iron_carapace()
	player.equipment.equipped[EquipmentInventory.SLOT_TRINKET] = EquipmentCatalog.bone_charm()
	player.equipment.bag.clear()
	player.equipment.bag.append(EquipmentCatalog.broken_sword())
	player.equipment.bag.append(EquipmentCatalog.broken_armor())
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(100, 100))
	player.queue_free()
	await flush(2)

	# Stress loop: 10 consecutive respawns without re-saving
	for cycle in 10:
		var respawned_player: Player = await spawn_player(arena)
		ok(SaveData.load_game(), "Cycle %d: load_game" % cycle)
		SaveData.apply_player(respawned_player)

		# Check strict invariance
		eq(respawned_player.equipment.bag.size(), 2, "Cycle %d: bag size strictly remains 2" % cycle)
		eq(respawned_player.equipment.bag[0].id, &"broken_sword", "Cycle %d: bag[0] unchanged" % cycle)
		eq(respawned_player.equipment.bag[1].id, &"broken_armor", "Cycle %d: bag[1] unchanged" % cycle)

		eq(respawned_player.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade")
		eq(respawned_player.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR).id, &"iron_carapace")
		eq(respawned_player.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET).id, &"bone_charm")

		respawned_player.queue_free()
		await flush(1)

	arena.queue_free()


func test_fully_unequipped_player_death_respawn_not_overwritten_by_starter_gear() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Unequip all 3 slots completely
	player.equipment.equipped[EquipmentInventory.SLOT_WEAPON] = null
	player.equipment.equipped[EquipmentInventory.SLOT_ARMOR] = null
	player.equipment.equipped[EquipmentInventory.SLOT_TRINKET] = null
	player.equipment.bag.clear()
	player.equipment.bag.append(EquipmentCatalog.iron_blade())
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	eq(player.equipment.get_equipped_items().size(), 0, "completely unequipped")
	eq(player.equipment.bag.size(), 1, "1 item in bag")

	# Save checkpoint
	SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(200, 200))
	player.queue_free()
	await flush(2)

	# Respawn
	var fresh_player: Player = await spawn_player(arena)
	SaveData.load_game()
	SaveData.apply_player(fresh_player)

	# Verify: player remains completely unequipped; starter gear NOT forced
	ok(fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON) == null, "weapon remains empty")
	ok(fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR) == null, "armor remains empty")
	ok(fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET) == null, "trinket remains empty")
	eq(fresh_player.equipment.bag.size(), 1, "bag strictly has 1 item (no starter items pushed to bag)")
	eq(fresh_player.equipment.bag[0].id, &"iron_blade")

	fresh_player.queue_free()
	arena.queue_free()


func test_max_bag_capacity_full_retention_on_death_respawn() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Equip 3 items
	player.equipment.equipped[EquipmentInventory.SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player.equipment.equipped[EquipmentInventory.SLOT_ARMOR] = EquipmentCatalog.iron_carapace()
	player.equipment.equipped[EquipmentInventory.SLOT_TRINKET] = EquipmentCatalog.toxic_ward()

	# Fill bag to max capacity: 16 items
	player.equipment.bag.clear()
	var sample_ids: Array[String] = ["broken_sword", "broken_armor", "broken_pendant", "iron_blade", "iron_carapace", "toxic_ward", "bone_charm"]
	for i in 16:
		var id_choice: String = sample_ids[i % sample_ids.size()]
		var item: EquipmentItem = EquipmentCatalog.for_id(StringName(id_choice))
		player.equipment.bag.append(item)
	eq(player.equipment.bag.size(), 16, "bag filled to exact capacity 16")

	SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(300, 300))
	player.queue_free()
	await flush(2)

	# Respawn
	var fresh_player: Player = await spawn_player(arena)
	SaveData.load_game()
	SaveData.apply_player(fresh_player)

	eq(fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade")
	eq(fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR).id, &"iron_carapace")
	eq(fresh_player.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET).id, &"toxic_ward")
	eq(fresh_player.equipment.bag.size(), 16, "all 16 bag items retained without drop or overflow")

	for i in 16:
		var expected_id: String = sample_ids[i % sample_ids.size()]
		eq(fresh_player.equipment.bag[i].id, StringName(expected_id), "bag index %d matches" % i)

	fresh_player.queue_free()
	arena.queue_free()


func test_cross_level_scene_transition_persists_and_restores_equipment_seamlessly() -> void:
	var arena1 := Node2D.new()
	add_child(arena1)
	build_floor(arena1)
	var player_a: Player = await spawn_player(arena1)

	# Level 1 Loadout: iron_blade, broken_armor, broken_pendant (activates 2pc Broken Knight)
	player_a.equipment.equipped[EquipmentInventory.SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player_a.equipment.equipped[EquipmentInventory.SLOT_ARMOR] = EquipmentCatalog.broken_armor()
	player_a.equipment.equipped[EquipmentInventory.SLOT_TRINKET] = EquipmentCatalog.broken_pendant()
	player_a.equipment.bag.clear()
	player_a.equipment.bag.append(EquipmentCatalog.broken_sword())
	player_a.equipment.bag.append(EquipmentCatalog.iron_carapace())
	player_a.equipment.bag.append(EquipmentCatalog.bone_charm())
	player_a.equipment.equipment_changed.emit()
	player_a.equipment.bag_changed.emit()

	# Cross-level travel to Level 2
	var destination: String = "res://scenes/levels/Level02_Undercroft.tscn"
	var arrival_spawn: Vector2 = Vector2(480, 220)
	LevelExit.travel(destination, arrival_spawn, player_a)

	eq(SaveData.pending_spawn, arrival_spawn, "pending spawn point set to destination arrival")
	ok(not SaveData.entering_from_checkpoint, "entering_from_checkpoint is false on level transition")

	# Transition: Clean up Level 1 arena and player_a
	player_a.queue_free()
	arena1.queue_free()
	await flush(2)

	# Simulate Level 2 loading and instantiating player_b
	var arena2 := Node2D.new()
	add_child(arena2)
	build_floor(arena2)
	var player_b: Player = await spawn_player(arena2)

	# Level 2 runs SaveData.load_game() and SaveData.apply_player()
	ok(SaveData.load_game(), "Level 2 loads game state")
	SaveData.apply_player(player_b)

	# Assertions on restored Player in Level 2:
	eq(player_b.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade", "weapon preserved in Level 2")
	eq(player_b.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR).id, &"broken_armor", "armor preserved in Level 2")
	eq(player_b.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET).id, &"broken_pendant", "trinket preserved in Level 2")

	# Broken Knight 2-piece synergy must be active! (broken_armor + broken_pendant)
	var synergies: Array[Dictionary] = player_b.equipment.get_set_synergies()
	eq(synergies.size(), 1, "Level 2: 2pc synergy active")
	eq(synergies[0].get("pieces", 0), 2)

	# Effective stats calculation in Level 2:
	# iron_blade (+2 atk)
	# broken_armor (+1 def, +1 hp)
	# broken_pendant (+0.05 toxin)
	# 2pc bonus (+1 def, +1 hp)
	# Total: atk = 2, def = 2, max_hp = 2, toxin = 0.05
	eq(player_b.stats.get_attack_bonus(), 2, "Level 2 attack bonus = 2")
	eq(player_b.stats.get_defense_reduction(), 2, "Level 2 defense reduction = 2")
	eq(player_b.stats.get_max_hp_bonus(), 2, "Level 2 max hp bonus = 2")
	almost(player_b.stats.get_toxin_resistance(), 0.05, 0.001, "Level 2 toxin resist = 0.05")
	eq(player_b.health.max_hp, 7, "Level 2 max HP is 7 (5 base + 2 bonus)")
	eq(player_b.health.current, 7, "Level 2 health is fully restored upon travel")

	# Bag items in Level 2
	eq(player_b.equipment.bag.size(), 3, "bag preserved in Level 2")
	eq(player_b.equipment.bag[0].id, &"broken_sword")
	eq(player_b.equipment.bag[1].id, &"iron_carapace")
	eq(player_b.equipment.bag[2].id, &"bone_charm")

	player_b.queue_free()
	arena2.queue_free()


func test_multi_level_consecutive_travel_with_equipment_mutations() -> void:
	# Sequence: Level 1 -> travel -> Level 2 (equip blade) -> travel -> Level 3 (unequip armor)
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)

	# Stage 1: Level 1 (Starter set)
	var p1: Player = await spawn_player(arena)
	p1.initialize_starter_equipment(true)
	LevelExit.travel("res://scenes/levels/Level02_Undercroft.tscn", Vector2(100, 100), p1)
	p1.queue_free()
	await flush(2)

	# Stage 2: Level 2
	var p2: Player = await spawn_player(arena)
	SaveData.load_game()
	SaveData.apply_player(p2)
	eq(p2.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"broken_sword")

	# Swap weapon with iron_blade in Level 2
	p2.equipment.bag.append(EquipmentCatalog.iron_blade())
	p2.equipment.swap_item(EquipmentInventory.SLOT_WEAPON, 0)
	eq(p2.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade")
	eq(p2.equipment.bag[0].id, &"broken_sword")

	# Travel from Level 2 to Level 3
	LevelExit.travel("res://scenes/levels/Level03_Catacombs.tscn", Vector2(200, 200), p2)
	p2.queue_free()
	await flush(2)

	# Stage 3: Level 3
	var p3: Player = await spawn_player(arena)
	SaveData.load_game()
	SaveData.apply_player(p3)

	eq(p3.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade", "Level 3: weapon is iron_blade")
	eq(p3.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR).id, &"broken_armor", "Level 3: armor is broken_armor")
	eq(p3.equipment.bag.size(), 1, "Level 3: bag has 1 item")
	eq(p3.equipment.bag[0].id, &"broken_sword", "Level 3: bag has swapped broken_sword")

	# Unequip armor in Level 3
	p3.equipment.unequip_slot(EquipmentInventory.SLOT_ARMOR)
	ok(p3.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR) == null, "Level 3: armor unequipped")
	eq(p3.equipment.bag.size(), 2, "Level 3: bag now has 2 items")

	# Save in Level 3
	SaveData.save_game("res://scenes/levels/Level03_Catacombs.tscn", p3)
	p3.queue_free()
	await flush(2)

	# Stage 4: Reload Level 3
	var p4: Player = await spawn_player(arena)
	SaveData.load_game()
	SaveData.apply_player(p4)

	eq(p4.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade")
	ok(p4.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR) == null, "armor remains unequipped after reload")
	eq(p4.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET).id, &"broken_pendant")
	eq(p4.equipment.bag.size(), 2)

	p4.queue_free()
	arena.queue_free()


func test_death_after_level_transition_reloads_level_arrival_state() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)

	# 1. Player in Level 1 with custom gear
	var p1: Player = await spawn_player(arena)
	p1.equipment.equipped[EquipmentInventory.SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	p1.equipment.equipped[EquipmentInventory.SLOT_ARMOR] = EquipmentCatalog.iron_carapace()
	p1.equipment.equipped[EquipmentInventory.SLOT_TRINKET] = EquipmentCatalog.bone_charm()
	p1.equipment.bag.clear()
	p1.equipment.equipment_changed.emit()

	# 2. Travel to Level 2
	var spawn_l2 := Vector2(500, 150)
	LevelExit.travel("res://scenes/levels/Level02_Undercroft.tscn", spawn_l2, p1)
	p1.queue_free()
	await flush(2)

	# 3. Arrive in Level 2
	var p2: Player = await spawn_player(arena)
	SaveData.load_game()
	SaveData.apply_player(p2)

	# 4. Player takes fatal damage in Level 2 before lighting any Ember Nest
	p2.health.take_damage(999, null)
	eq(p2.health.current, 0, "player died in Level 2")
	p2.queue_free()
	await flush(2)

	# 5. Respawn reloads Level 2 arrival save
	var p3: Player = await spawn_player(arena)
	SaveData.load_game()
	SaveData.apply_player(p3)

	# 6. Verify equipment and stats remain intact from arrival
	eq(p3.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade", "weapon preserved on death")
	eq(p3.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR).id, &"iron_carapace", "armor preserved on death")
	eq(p3.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET).id, &"bone_charm", "trinket preserved on death")
	eq(p3.equipment.bag.size(), 0, "bag empty preserved")
	eq(p3.health.max_hp, 7, "max HP is 7")

	p3.queue_free()
	arena.queue_free()
