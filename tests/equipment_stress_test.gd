class_name EquipmentStressTest
extends TestCase
## Adversarial Stress Test Suite for Equipment Set Synergies,
## Dynamic Combat Recalculations, and Max HP Health Invariants.

const CATALOG_PATH := "res://scripts/data/equipment_catalog.gd"
const INVENTORY_PATH := "res://scripts/player/equipment_inventory.gd"
const STATS_PATH := "res://scripts/player/character_stats.gd"


func test_broken_knight_gear_equip_unequip_cycling_and_synergy_toggle() -> void:
	var inv: EquipmentInventory = EquipmentInventory.new()
	add_child(inv)
	var stats: CharacterStats = CharacterStats.new()
	add_child(stats)

	# Wire inventory equipment_changed to stats recalculate exactly as Player does
	inv.equipment_changed.connect(func():
		stats.recalculate(inv.get_all_equipped(), inv.get_active_set_bonuses())
	)

	var sword: EquipmentItem = EquipmentCatalog.broken_sword()
	var armor: EquipmentItem = EquipmentCatalog.broken_armor()
	var pendant: EquipmentItem = EquipmentCatalog.broken_pendant()

	# --- Cycle Phase 0: 0 Pieces Equipped ---
	eq(inv.get_equipped_items().size(), 0, "Phase 0: 0 items equipped")
	eq(inv.get_set_synergies().size(), 0, "Phase 0: no set synergies active")
	eq(stats.get_attack_bonus(), 0, "Phase 0: attack bonus is 0")
	eq(stats.get_defense_reduction(), 0, "Phase 0: defense reduction is 0")
	eq(stats.get_max_hp_bonus(), 0, "Phase 0: max hp bonus is 0")
	almost(stats.get_toxin_resistance(), 0.0, 0.001, "Phase 0: toxin resist is 0.0")

	# --- Cycle Phase 1: Equip 1 Piece (broken_sword in weapon slot) ---
	var ok1 := inv.equip_item(sword, EquipmentInventory.SLOT_WEAPON)
	ok(ok1, "equipped broken_sword to weapon slot")
	eq(inv.get_equipped_items().size(), 1, "Phase 1: 1 item equipped")
	eq(inv.get_set_synergies().size(), 0, "Phase 1: 1 piece activates 0 synergies")
	eq(stats.get_attack_bonus(), 1, "Phase 1: attack bonus is 1 (sword)")
	eq(stats.get_defense_reduction(), 0, "Phase 1: defense is 0")
	eq(stats.get_max_hp_bonus(), 0, "Phase 1: max hp bonus is 0")
	almost(stats.get_toxin_resistance(), 0.0, 0.001, "Phase 1: toxin resist is 0.0")

	# --- Cycle Phase 2: Equip 2nd Piece (broken_armor in armor slot) ---
	var ok2 := inv.equip_item(armor, EquipmentInventory.SLOT_ARMOR)
	ok(ok2, "equipped broken_armor to armor slot")
	eq(inv.get_equipped_items().size(), 2, "Phase 2: 2 items equipped")
	var syn2 := inv.get_set_synergies()
	eq(syn2.size(), 1, "Phase 2: exactly 1 synergy active (2pc)")
	eq(syn2[0].get("pieces", 0), 2, "Phase 2: 2pc synergy triggered")
	# broken_sword (+1 atk), broken_armor (+1 def, +1 hp), 2pc bonus (+1 def, +1 hp)
	eq(stats.get_attack_bonus(), 1, "Phase 2: attack bonus is 1")
	eq(stats.get_defense_reduction(), 2, "Phase 2: defense reduction is 2 (1 armor + 1 set)")
	eq(stats.get_max_hp_bonus(), 2, "Phase 2: max hp bonus is 2 (1 armor + 1 set)")
	almost(stats.get_toxin_resistance(), 0.0, 0.001, "Phase 2: toxin resist is 0.0")

	# --- Cycle Phase 3: Equip 3rd Piece (broken_pendant in trinket slot) ---
	var ok3 := inv.equip_item(pendant, EquipmentInventory.SLOT_TRINKET)
	ok(ok3, "equipped broken_pendant to trinket slot")
	eq(inv.get_equipped_items().size(), 3, "Phase 3: 3 items equipped")
	var syn3 := inv.get_set_synergies()
	eq(syn3.size(), 2, "Phase 3: both 2pc and 3pc synergies active")
	# broken_sword (+1 atk), broken_armor (+1 def, +1 hp), broken_pendant (+0.05 toxin)
	# 2pc bonus: +1 def, +1 hp
	# 3pc bonus: +1 atk, +0.10 toxin
	# Total: atk = 2, def = 2, max_hp = 2, toxin_resist = 0.15
	eq(stats.get_attack_bonus(), 2, "Phase 3: attack bonus is 2 (1 sword + 1 3pc)")
	eq(stats.get_defense_reduction(), 2, "Phase 3: defense reduction is 2 (1 armor + 1 2pc)")
	eq(stats.get_max_hp_bonus(), 2, "Phase 3: max hp bonus is 2 (1 armor + 1 2pc)")
	almost(stats.get_toxin_resistance(), 0.15, 0.001, "Phase 3: toxin resist is 0.15 (0.05 pendant + 0.10 3pc)")

	# --- Cycle Phase 4: Unequip 3rd Piece (trinket) -> 3pc revoked dynamically ---
	var ok_u3 := inv.unequip_slot(EquipmentInventory.SLOT_TRINKET)
	ok(ok_u3, "unequipped trinket slot")
	eq(inv.get_equipped_items().size(), 2, "Phase 4: back to 2 items")
	var syn4 := inv.get_set_synergies()
	eq(syn4.size(), 1, "Phase 4: 3pc revoked, only 2pc active")
	eq(syn4[0].get("pieces", 0), 2, "Phase 4: 2pc remains active")
	eq(stats.get_attack_bonus(), 1, "Phase 4: attack reverted to 1 (3pc atk revoked)")
	eq(stats.get_defense_reduction(), 2, "Phase 4: defense remains 2 (2pc active)")
	eq(stats.get_max_hp_bonus(), 2, "Phase 4: max hp remains 2 (2pc active)")
	almost(stats.get_toxin_resistance(), 0.0, 0.001, "Phase 4: toxin resist reverted to 0.0")

	# --- Cycle Phase 5: Unequip 2nd Piece (armor) -> 2pc revoked dynamically ---
	var ok_u2 := inv.unequip_slot(EquipmentInventory.SLOT_ARMOR)
	ok(ok_u2, "unequipped armor slot")
	eq(inv.get_equipped_items().size(), 1, "Phase 5: back to 1 item")
	eq(inv.get_set_synergies().size(), 0, "Phase 5: 2pc revoked, 0 synergies active")
	eq(stats.get_attack_bonus(), 1, "Phase 5: attack is 1 (sword)")
	eq(stats.get_defense_reduction(), 0, "Phase 5: defense reverted to 0")
	eq(stats.get_max_hp_bonus(), 0, "Phase 5: max hp reverted to 0")

	# --- Cycle Phase 6: Unequip 1st Piece (weapon) -> completely empty ---
	var ok_u1 := inv.unequip_slot(EquipmentInventory.SLOT_WEAPON)
	ok(ok_u1, "unequipped weapon slot")
	eq(inv.get_equipped_items().size(), 0, "Phase 6: 0 items equipped")
	eq(inv.get_set_synergies().size(), 0, "Phase 6: 0 synergies active")
	eq(stats.get_attack_bonus(), 0, "Phase 6: attack is 0")
	eq(stats.get_defense_reduction(), 0, "Phase 6: defense is 0")
	eq(stats.get_max_hp_bonus(), 0, "Phase 6: max hp is 0")
	almost(stats.get_toxin_resistance(), 0.0, 0.001, "Phase 6: toxin resist is 0.0")

	# --- Cycle Phase 7: Non-sequential 2pc without weapon (armor + pendant) ---
	inv.equip_item(armor, EquipmentInventory.SLOT_ARMOR)
	inv.equip_item(pendant, EquipmentInventory.SLOT_TRINKET)
	eq(inv.get_equipped_items().size(), 2, "Phase 7: armor + pendant equipped")
	var syn7 := inv.get_set_synergies()
	eq(syn7.size(), 1, "Phase 7: 2pc active without weapon")
	eq(syn7[0].get("pieces", 0), 2, "Phase 7: 2pc verified")
	eq(stats.get_attack_bonus(), 0, "Phase 7: attack is 0 (no sword, no 3pc)")
	eq(stats.get_defense_reduction(), 2, "Phase 7: defense is 2 (1 armor + 1 2pc)")
	eq(stats.get_max_hp_bonus(), 2, "Phase 7: max hp is 2 (1 armor + 1 2pc)")
	almost(stats.get_toxin_resistance(), 0.05, 0.001, "Phase 7: toxin resist is 0.05 (pendant only)")

	# Clean up
	inv.queue_free()
	stats.queue_free()


func test_rapid_equip_unequip_stress_cycles() -> void:
	var inv: EquipmentInventory = EquipmentInventory.new()
	add_child(inv)
	var stats: CharacterStats = CharacterStats.new()
	add_child(stats)
	inv.equipment_changed.connect(func():
		stats.recalculate(inv.get_all_equipped(), inv.get_active_set_bonuses())
	)

	var sword := EquipmentCatalog.broken_sword()
	var armor := EquipmentCatalog.broken_armor()
	var pendant := EquipmentCatalog.broken_pendant()

	# Perform 20 rapid equip/unequip cycles to detect state drift or accumulation
	for cycle in 20:
		inv.equip_item(sword, EquipmentInventory.SLOT_WEAPON)
		inv.equip_item(armor, EquipmentInventory.SLOT_ARMOR)
		inv.equip_item(pendant, EquipmentInventory.SLOT_TRINKET)
		eq(stats.get_attack_bonus(), 2, "Cycle %d: attack is 2 at 3pc" % cycle)
		eq(stats.get_defense_reduction(), 2, "Cycle %d: defense is 2 at 3pc" % cycle)
		almost(stats.get_toxin_resistance(), 0.15, 0.001, "Cycle %d: resist is 0.15 at 3pc" % cycle)

		# Clear bag to avoid bag overflow blocking unequip
		inv.bag.clear()
		inv.unequip_slot(EquipmentInventory.SLOT_WEAPON)
		inv.unequip_slot(EquipmentInventory.SLOT_ARMOR)
		inv.unequip_slot(EquipmentInventory.SLOT_TRINKET)
		inv.bag.clear()

		eq(stats.get_attack_bonus(), 0, "Cycle %d: attack reset to 0" % cycle)
		eq(stats.get_defense_reduction(), 0, "Cycle %d: defense reset to 0" % cycle)
		eq(stats.get_max_hp_bonus(), 0, "Cycle %d: max hp reset to 0" % cycle)
		almost(stats.get_toxin_resistance(), 0.0, 0.001, "Cycle %d: resist reset to 0.0" % cycle)

	inv.queue_free()
	stats.queue_free()


func test_stat_recalculations_trigger_signals_and_update_live_combat_numbers() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Ensure fresh test player with clean baseline
	player.equipment.equipped[EquipmentInventory.SLOT_WEAPON] = null
	player.equipment.equipped[EquipmentInventory.SLOT_ARMOR] = null
	player.equipment.equipped[EquipmentInventory.SLOT_TRINKET] = null
	player.equipment.bag.clear()
	player.stats.recalculate([], {})

	var counts := {"stats": 0, "equipment": 0}
	player.stats.stats_changed.connect(func(): counts["stats"] += 1)
	player.equipment.equipment_changed.connect(func(): counts["equipment"] += 1)

	# Baseline state
	eq(player.stats.get_attack_bonus(), 0, "baseline attack bonus = 0")
	eq(player.stats.get_defense_reduction(), 0, "baseline defense = 0")
	almost(player.stats.get_toxin_resistance(), 0.0, 0.001, "baseline toxin resist = 0.0")
	eq(player.health.max_hp, 5, "baseline max hp = 5")
	eq(player.health.current, 5, "baseline current hp = 5")

	# Equip Broken Knight 3-piece set
	var sword := EquipmentCatalog.broken_sword()
	var armor := EquipmentCatalog.broken_armor()
	var pendant := EquipmentCatalog.broken_pendant()

	player.equipment.equip_item(sword, EquipmentInventory.SLOT_WEAPON)
	player.equipment.equip_item(armor, EquipmentInventory.SLOT_ARMOR)
	player.equipment.equip_item(pendant, EquipmentInventory.SLOT_TRINKET)

	ok(counts["equipment"] >= 3, "equipment_changed emitted on each equip")
	ok(counts["stats"] >= 3, "stats_changed emitted on each recalculate")
	eq(player.stats.get_attack_bonus(), 2, "effective attack bonus is 2 (1 item + 1 3pc)")
	eq(player.stats.get_defense_reduction(), 2, "effective defense reduction is 2 (1 item + 1 2pc)")
	eq(player.health.max_hp, 7, "live health max_hp updated to 7 (5 base + 1 armor + 1 2pc)")

	# 1. Live Melee Swing Check: Hitbox damage must reflect attack bonus immediately
	player.melee._combo_index = 0
	player.melee._begin_active()
	# Base swing 0 damage is 1. With +2 attack bonus -> hitbox.damage = 3
	eq(player.melee.hitbox.damage, 3, "live melee swing 0 hitbox damage is 3 immediately")

	# Finisher combo swing check: Base combo finisher damage is 2. With +2 attack -> 4
	player.melee._combo_index = 2
	player.melee._begin_active()
	eq(player.melee.hitbox.damage, 4, "live melee finisher hitbox damage is 4 immediately")

	# 2. Live Defense Check: Mitigated damage reduction with floor at 1
	player.health.current = 5
	# Incoming raw damage 4 vs defense 2: effective damage = 4 - 2 = 2
	player.take_mitigated_damage(4, null)
	eq(player.health.current, 3, "player current hp dropped from 5 to 3 (mitigated by 2 defense)")

	# Reset i-frames and test overwhelming defense
	player.health._hit_iframe = 0.0
	# Add temporary modifier with defense 100
	player.stats.add_modifier(&"god_shield", {"defense": 100})
	eq(player.stats.get_defense_reduction(), 102, "overwhelming defense active")
	# Incoming raw damage 2 vs defense 102: strictly floors at 1
	player.take_mitigated_damage(2, null)
	eq(player.health.current, 2, "overwhelming defense strictly floors at 1 damage")
	player.stats.remove_modifier(&"god_shield")

	# 3. Live Toxin Meter Check: Resistance reduces accumulation immediately
	player.toxin.toxin = 0.0
	player.toxin._exposing = false
	# 3pc gives 0.15 toxin resistance. Exposure 40.0 -> effective exposure = 40 * (1 - 0.15) = 34.0
	player.toxin.expose(40.0)
	almost(player.toxin.toxin, 34.0, 0.05, "live toxin exposure scaled by active set resistance (34.0)")

	# 4. Unequip gear and verify live values reset immediately
	player.toxin.toxin = 0.0 # Reset to cold tier so toxin band bonus is 0
	player.equipment.bag.clear()
	var u1 = player.equipment.unequip_slot(EquipmentInventory.SLOT_WEAPON)
	var u2 = player.equipment.unequip_slot(EquipmentInventory.SLOT_ARMOR)
	var u3 = player.equipment.unequip_slot(EquipmentInventory.SLOT_TRINKET)
	ok(u1 and u2 and u3, "all 3 slots successfully unequipped")
	eq(player.stats.get_attack_bonus(), 0, "attack bonus reverted to 0")

	# Verify Melee damage dropped back to base
	player.melee._combo_index = 0
	player.melee._begin_active()
	eq(player.melee.hitbox.damage, 1, "melee swing damage immediately reverted to base 1")

	player.melee._combo_index = 2
	player.melee._begin_active()
	eq(player.melee.hitbox.damage, 2, "melee finisher damage immediately reverted to base 2")

	# Verify max hp dropped back to base 5
	eq(player.health.max_hp, 5, "health max_hp immediately reverted to base 5")

	arena.queue_free()


func test_max_hp_bonuses_anti_resurrection_and_no_suicide_on_unequip() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Clean baseline
	player.equipment.equipped[EquipmentInventory.SLOT_WEAPON] = null
	player.equipment.equipped[EquipmentInventory.SLOT_ARMOR] = null
	player.equipment.equipped[EquipmentInventory.SLOT_TRINKET] = null
	player.equipment.bag.clear()
	player.stats.recalculate([], {})

	eq(player.health.current, 5, "initial hp = 5")
	eq(player.health.max_hp, 5, "initial max hp = 5")

	# --- PART 1: Alive Player At 1 HP Unequipping Gear Never Suicides ---
	# Equip Iron Carapace (+2 max_hp)
	var heavy_armor := EquipmentCatalog.iron_carapace()
	player.equipment.equip_item(heavy_armor, EquipmentInventory.SLOT_ARMOR)
	eq(player.health.max_hp, 7, "max hp increased to 7")
	eq(player.health.current, 5, "current hp remains at 5 (no free healing)")

	# Lower player health to exactly 1
	player.health.current = 1
	player.health._dead = false
	eq(player.health.current, 1, "player is critically wounded at 1 HP")

	# Unequip heavy armor: max HP drops from 7 to 5.
	# CRITICAL INVARIANT: Player MUST NOT die or suicide!
	player.equipment.bag.clear()
	player.equipment.unequip_slot(EquipmentInventory.SLOT_ARMOR)
	eq(player.health.max_hp, 5, "max hp reverted to 5")
	eq(player.health.current, 1, "current hp strictly preserved at 1 (never suicides)")
	ok(not player.health._dead, "player is definitely still alive")

	# --- PART 2: Max HP Clamping When Current HP Exceeds New Lower Max HP ---
	player.equipment.equip_item(heavy_armor, EquipmentInventory.SLOT_ARMOR)
	eq(player.health.max_hp, 7, "max hp is 7")
	player.health.heal_full()
	eq(player.health.current, 7, "player fully healed to 7 HP")

	# Unequip: current HP (7) exceeds new max (5) -> must clamp to exactly 5
	player.equipment.bag.clear()
	player.equipment.unequip_slot(EquipmentInventory.SLOT_ARMOR)
	eq(player.health.max_hp, 5, "max hp reverted to 5")
	eq(player.health.current, 5, "current hp clamped to new max 5")
	ok(not player.health._dead, "player alive and capped at max")

	# --- PART 3: Dead Player Cannot Be Revived By Equipping Armor Or Set Bonuses ---
	# Kill the player
	player.health._hit_iframe = 0.0
	player.health.take_damage(999, null)
	eq(player.health.current, 0, "player current hp is 0")
	ok(player.health._dead, "player is dead (_dead is true)")

	# Equip Broken Knight armor (+1 HP) and Broken Knight 2pc (+1 HP)
	var sword := EquipmentCatalog.broken_sword()
	var armor := EquipmentCatalog.broken_armor()
	player.equipment.equip_item(sword, EquipmentInventory.SLOT_WEAPON)
	player.equipment.equip_item(armor, EquipmentInventory.SLOT_ARMOR)
	# Max HP capacity updates to 7
	eq(player.health.max_hp, 7, "dead player max hp pool expanded to 7")
	eq(player.health.current, 0, "ANTI-RESURRECTION: dead player current hp MUST STAY 0")
	ok(player.health._dead, "ANTI-RESURRECTION: dead player _dead latch MUST REMAIN TRUE")

	# Swap armor with iron_carapace (+2 max_hp) while dead
	player.equipment.bag.clear()
	player.equipment.add_to_bag(heavy_armor)
	player.equipment.swap_item(EquipmentInventory.SLOT_ARMOR, 0)
	eq(player.health.current, 0, "ANTI-RESURRECTION: swapping armor while dead preserves 0 HP")
	ok(player.health._dead, "ANTI-RESURRECTION: dead latch remains true after armor swap")

	# Unequip all gear while dead
	player.equipment.bag.clear()
	player.equipment.unequip_slot(EquipmentInventory.SLOT_WEAPON)
	player.equipment.unequip_slot(EquipmentInventory.SLOT_ARMOR)
	player.equipment.unequip_slot(EquipmentInventory.SLOT_TRINKET)
	eq(player.health.max_hp, 5, "max hp reverted to 5")
	eq(player.health.current, 0, "dead player still at 0 HP after full unequip")
	ok(player.health._dead, "dead player still dead after full unequip")

	arena.queue_free()


func test_adversarial_mismatched_and_atomic_swap_tampering() -> void:
	var inv: EquipmentInventory = EquipmentInventory.new()
	add_child(inv)
	var stats: CharacterStats = CharacterStats.new()
	add_child(stats)
	inv.equipment_changed.connect(func():
		stats.recalculate(inv.get_all_equipped(), inv.get_active_set_bonuses())
	)

	var sword := EquipmentCatalog.broken_sword()
	var armor := EquipmentCatalog.broken_armor()
	var blade := EquipmentCatalog.iron_blade()

	# Equip weapon
	inv.equip_item(sword, EquipmentInventory.SLOT_WEAPON)
	eq(stats.get_attack_bonus(), 1, "sword gives attack 1")

	# Put armor into bag
	inv.add_to_bag(armor)
	eq(inv.bag.size(), 1, "armor in bag index 0")

	# Attempt illegal swap: weapon slot with armor item at bag_index 0
	var swap_result := inv.swap_item(EquipmentInventory.SLOT_WEAPON, 0)
	ok(not swap_result, "swapping weapon slot with armor item is strictly rejected")
	eq(inv.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"broken_sword", "equipped weapon untouched")
	eq(inv.bag[0].id, &"broken_armor", "bag item untouched")
	eq(stats.get_attack_bonus(), 1, "attack bonus untouched")

	# Put blade into bag (matching weapon slot)
	inv.add_to_bag(blade)
	eq(inv.bag.size(), 2, "blade in bag index 1")

	# Legal swap: weapon slot (broken_sword, atk 1) with bag index 1 (iron_blade, atk 2)
	var legal_swap := inv.swap_item(EquipmentInventory.SLOT_WEAPON, 1)
	ok(legal_swap, "legal weapon swap succeeded")
	eq(inv.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"iron_blade", "equipped is now iron_blade")
	eq(inv.bag[1].id, &"broken_sword", "bag index 1 now holds old broken_sword")
	eq(stats.get_attack_bonus(), 2, "stats recalculated immediately: attack bonus is 2")

	inv.queue_free()
	stats.queue_free()
