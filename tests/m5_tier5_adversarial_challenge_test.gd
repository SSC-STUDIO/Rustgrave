class_name M5Tier5AdversarialChallengeTest
extends TestCase
## Tier 5 Adversarial Stress Testing & Boundary Hardening Test Suite.
## Validates:
## 1. Cross-feature integration across all 3 origins:
##    Origin selection -> custom trinket -> embarkation -> save creation ->
##    level transition -> mutated gear & damage -> save/load roundtrip ->
##    death respawn at checkpoint -> 100% preservation of origin, badge, gear, stats.
## 2. Boundary & extreme conditions:
##    - Toxin resist cap at 80% (0.80) & floor at 0.00
##    - Speed multiplier floor (0.10) and ceiling (3.00)
##    - Damage floor at 1 (minimum 1 damage regardless of massive enemy or player defense)
##    - Unassigned bare player defaults (5 HP, 0 ATK, 0 DEF, origin = "") and safe null/empty resets.

const TEST_SAVE_PATH := "user://rustgrave_m5_tier5_adversarial_test.cfg"
const UI_PANEL_SCENE := preload("res://scenes/ui/CharacterEquipmentPanel.tscn")
const CHAR_SELECT_SCENE := preload("res://scenes/ui/CharacterSelectScreen.tscn")
const CharacterStatsScript := preload("res://scripts/player/character_stats.gd")
const OriginCatalogScript := preload("res://scripts/data/origin_catalog.gd")
const EquipmentCatalogScript := preload("res://scripts/data/equipment_catalog.gd")

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
	Director.choice_hold = false
	Director.playing = false
	Director._locked = false
	Director._fading = false
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.lit_nests.clear()
	SaveData.consumed.clear()
	Director.choice_hold = false
	Director.playing = false
	Director._locked = false
	Director._fading = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


# ===========================================================================
# 1. Cross-Feature Integration: Ember Vanguard
# ===========================================================================

func test_cross_feature_integration_ember_vanguard() -> void:
	# 1. Origin & Trinket Selection
	var char_select: CharacterSelectScreen = CHAR_SELECT_SCENE.instantiate()
	add_child(char_select)
	char_select.select_origin(OriginCatalogScript.ORIGIN_EMBER_VANGUARD)
	char_select.select_trinket(&"broken_pendant")
	var preview := char_select.get_preview_stats()
	eq(int(preview["max_hp"]), 8, "Ember Vanguard + Broken Knight 3pc preview HP is 8")
	eq(int(preview["defense"]), 3, "Ember Vanguard + Broken Knight 3pc preview Def is 3")
	var loadout := char_select.get_selected_loadout()
	char_select.queue_free()

	# 2. Embarkation & Initial Save Creation
	SaveData.init_new_game(&"ember_vanguard", loadout)
	ok(SaveData.has_save(), "Save exists immediately on embarkation")
	eq(SaveData.get_current_origin(), &"ember_vanguard", "Current origin is ember_vanguard")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	SaveData.apply_player(player)

	# 3. Verify Initial Runtime Stats & UI Badge
	eq(player.origin, &"ember_vanguard", "Player origin is ember_vanguard")
	eq(player.health.max_hp, 8, "Runtime max HP is 8")
	eq(player.stats.get_defense_reduction(), 3, "Runtime defense reduction is 3")
	eq(player.equipment.get_equipped(SLOT_WEAPON).id, &"broken_sword", "Equipped broken_sword")
	eq(player.equipment.get_equipped(SLOT_ARMOR).id, &"broken_armor", "Equipped broken_armor")
	eq(player.equipment.get_equipped(SLOT_TRINKET).id, &"broken_pendant", "Equipped broken_pendant")

	var panel: CharacterEquipmentPanel = UI_PANEL_SCENE.instantiate()
	add_child(panel)
	panel.set_player(player)
	panel.open_panel()
	eq(panel.get_origin_title_text(), "身份 · 余烬重骑", "Origin badge displays '身份 · 余烬重骑'")
	panel.close_panel()
	panel.queue_free()

	# 4. Level Transition to Level02
	var level2_path := "res://scenes/levels/Level02_Undercroft.tscn"
	var lvl_saved := SaveData.save_game(level2_path, player, Vector2(120, 240))
	ok(lvl_saved, "Level transition save succeeded")

	# 5. Mutate Gear & Take Combat Damage
	var old_sword = player.equipment.get_equipped(SLOT_WEAPON)
	player.equipment.equipped[SLOT_WEAPON] = EquipmentCatalog.scavenger_blade()
	player.equipment.bag.append(old_sword)
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	var dmg_taken := player.health.take_damage(2, null)
	ok(dmg_taken, "Player took 2 damage")
	eq(player.health.current, 7, "Defense absorbs damage with a one-point floor")

	# 6. Register Checkpoint & Save State
	SaveData.register_lit_nest("Props/EmberNest_01")
	var cp_saved := SaveData.save_game(level2_path, player, Vector2(200, 300))
	ok(cp_saved, "Checkpoint save succeeded")

	# 7. Save/Load Roundtrip (Wipe Memory State)
	SaveData.data = {}
	player.queue_free()
	await flush(2)

	ok(SaveData.load_game(), "load_game succeeded after wipe")
	eq(SaveData.get_current_origin(), &"ember_vanguard", "Origin persisted across roundtrip")

	# 8. Death & Respawn at Checkpoint
	var dying_player: Player = await spawn_player(arena)
	SaveData.apply_player(dying_player)
	dying_player.health.take_damage(999, null)
	eq(dying_player.health.current, 0, "Player suffered fatal damage")
	dying_player.queue_free()
	await flush(2)

	# Respawn fresh player
	SaveData.entering_from_checkpoint = true
	ok(SaveData.load_game(), "load_game for checkpoint respawn")
	var respawned: Player = await spawn_player(arena)
	SaveData.apply_player(respawned)

	# 9. Verify 100% Preservation
	eq(respawned.origin, &"ember_vanguard", "Respawned player origin 100% preserved")
	eq(respawned.equipment.get_equipped(SLOT_WEAPON).id, &"scavenger_blade", "Mutated weapon scavenger_blade preserved")
	eq(respawned.equipment.bag.size(), 1, "Bag contains 1 item")
	eq(respawned.equipment.bag[0].id, &"broken_sword", "Bag item broken_sword preserved")
	eq(respawned.health.max_hp, 8, "Armor and pendant retain the two-piece HP bonus")
	eq(respawned.health.current, 7, "Raw player restoration retains saved damage")

	var panel2: CharacterEquipmentPanel = UI_PANEL_SCENE.instantiate()
	add_child(panel2)
	panel2.set_player(respawned)
	panel2.open_panel()
	eq(panel2.get_origin_title_text(), "身份 · 余烬重骑", "Origin badge 100% preserved after respawn")
	panel2.close_panel()
	panel2.queue_free()

	arena.queue_free()


# ===========================================================================
# 2. Cross-Feature Integration: Scrap Scavenger
# ===========================================================================

func test_cross_feature_integration_scrap_scavenger() -> void:
	# 1. Custom Loadout Selection
	var char_select: CharacterSelectScreen = CHAR_SELECT_SCENE.instantiate()
	add_child(char_select)
	char_select.select_origin(OriginCatalogScript.ORIGIN_SCRAP_SCAVENGER)
	char_select.select_trinket(&"bone_amulet")
	var preview := char_select.get_preview_stats()
	eq(int(preview["max_hp"]), 6, "Scrap Scavenger + Bone Amulet preview HP is 6 (5 + 1)")
	eq(int(preview["attack"]), 2, "Scrap Scavenger + Scavenger Blade preview Atk is 2")
	almost(float(preview["speed_mult"]), 1.15, 0.001, "Scrap Scavenger (10%) + Bone Amulet (5%) preview Speed is 1.15")
	var loadout := char_select.get_selected_loadout()
	char_select.queue_free()

	# 2. Embark & Init Save
	SaveData.init_new_game(&"scrap_scavenger", loadout)
	ok(SaveData.has_save(), "Save created for Scrap Scavenger")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	SaveData.apply_player(player)

	# 3. Verify Runtime Stats & Badge
	eq(player.origin, &"scrap_scavenger", "Player origin is scrap_scavenger")
	eq(player.health.max_hp, 6, "Runtime max HP is 6")
	eq(player.stats.get_attack_bonus(), 2, "Runtime attack bonus is 2")
	almost(player.stats.get_speed_multiplier(), 1.15, 0.001, "Runtime speed mult is 1.15")

	var panel: CharacterEquipmentPanel = UI_PANEL_SCENE.instantiate()
	add_child(panel)
	panel.set_player(player)
	panel.open_panel()
	eq(panel.get_origin_title_text(), "身份 · 废料剑客", "Origin badge displays '身份 · 废料剑客'")
	panel.close_panel()
	panel.queue_free()

	# 4. Mutate Armor & Bag
	var old_rags = player.equipment.get_equipped(SLOT_ARMOR)
	player.equipment.equipped[SLOT_ARMOR] = EquipmentCatalog.broken_armor()
	player.equipment.bag.append(old_rags)
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	# Take damage
	player.health.take_damage(2, null)

	# Save state at checkpoint
	SaveData.register_lit_nest("Props/EmberNest_02")
	SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(100, 100))

	# 5. Roundtrip wipe and respawn
	SaveData.data = {}
	player.queue_free()
	await flush(2)

	SaveData.entering_from_checkpoint = true
	ok(SaveData.load_game(), "SaveData loaded")
	var respawned: Player = await spawn_player(arena)
	SaveData.apply_player(respawned)

	# 6. Verify 100% preservation
	eq(respawned.origin, &"scrap_scavenger", "Origin scrap_scavenger preserved")
	eq(respawned.equipment.get_equipped(SLOT_ARMOR).id, &"broken_armor", "Mutated armor broken_armor preserved")
	eq(respawned.equipment.bag.size(), 1, "Bag preserved")
	eq(respawned.equipment.bag[0].id, &"scavenger_rags", "Bag contains scavenger_rags")
	# Base 5 + Bone Amulet 1 + Broken Armor 1 = 7 HP
	eq(respawned.health.max_hp, 7, "Max HP with broken_armor and bone_amulet is 7")
	eq(respawned.health.current, 5, "Raw player restoration retains saved damage after max-HP growth")

	var panel2: CharacterEquipmentPanel = UI_PANEL_SCENE.instantiate()
	add_child(panel2)
	panel2.set_player(respawned)
	panel2.open_panel()
	eq(panel2.get_origin_title_text(), "身份 · 废料剑客", "Badge preserved as '身份 · 废料剑客'")
	panel2.close_panel()
	panel2.queue_free()

	arena.queue_free()


# ===========================================================================
# 3. Cross-Feature Integration: Rust Automaton
# ===========================================================================

func test_cross_feature_integration_rust_automaton() -> void:
	# 1. Custom Loadout Selection
	var char_select: CharacterSelectScreen = CHAR_SELECT_SCENE.instantiate()
	add_child(char_select)
	char_select.select_origin(OriginCatalogScript.ORIGIN_RUST_AUTOMATON)
	char_select.select_trinket(&"toxic_filter_talisman")
	var preview := char_select.get_preview_stats()
	# Origin 20% + Cowl 5% + Talisman 15% = 40%
	almost(float(preview["toxin_resist"]), 0.40, 0.001, "Preview toxin resist is 40%")
	# Origin 0.50 + Talisman 0.50 = 1.00
	almost(float(preview["toxin_decay"]), 1.00, 0.001, "Preview toxin decay is 1.00/s")
	var loadout := char_select.get_selected_loadout()
	char_select.queue_free()

	# 2. Embark & Init Save
	SaveData.init_new_game(&"rust_automaton", loadout)
	ok(SaveData.has_save(), "Save created for Rust Automaton")

	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	SaveData.apply_player(player)

	# 3. Verify Runtime Stats & Badge
	eq(player.origin, &"rust_automaton", "Player origin is rust_automaton")
	almost(player.stats.get_toxin_resistance(), 0.40, 0.001, "Runtime toxin resist is 40%")
	almost(player.stats.get_toxin_decay_bonus(), 1.00, 0.001, "Runtime toxin decay is 1.00/s")

	var panel: CharacterEquipmentPanel = UI_PANEL_SCENE.instantiate()
	add_child(panel)
	panel.set_player(player)
	panel.open_panel()
	eq(panel.get_origin_title_text(), "身份 · 锈械学者", "Origin badge displays '身份 · 锈械学者'")
	panel.close_panel()
	panel.queue_free()

	# 4. Mutate Weapon & Bag
	var old_probe = player.equipment.get_equipped(SLOT_WEAPON)
	player.equipment.equipped[SLOT_WEAPON] = EquipmentCatalog.iron_blade()
	player.equipment.bag.append(old_probe)
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	# Take damage
	player.health.take_damage(1, null)

	# Save state at checkpoint
	SaveData.register_lit_nest("Props/EmberNest_03")
	SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player, Vector2(100, 100))

	# 5. Roundtrip wipe and respawn
	SaveData.data = {}
	player.queue_free()
	await flush(2)

	SaveData.entering_from_checkpoint = true
	ok(SaveData.load_game(), "SaveData loaded")
	var respawned: Player = await spawn_player(arena)
	SaveData.apply_player(respawned)

	# 6. Verify 100% preservation
	eq(respawned.origin, &"rust_automaton", "Origin rust_automaton preserved")
	eq(respawned.equipment.get_equipped(SLOT_WEAPON).id, &"iron_blade", "Mutated weapon iron_blade preserved")
	eq(respawned.equipment.bag.size(), 1, "Bag preserved")
	eq(respawned.equipment.bag[0].id, &"scholar_probe", "Bag contains scholar_probe")
	almost(respawned.stats.get_toxin_resistance(), 0.40, 0.001, "Toxin resist preserved")
	almost(respawned.stats.get_toxin_decay_bonus(), 1.00, 0.001, "Toxin decay preserved")
	eq(respawned.health.current, 4, "Raw player restoration does not grant free healing")

	var panel2: CharacterEquipmentPanel = UI_PANEL_SCENE.instantiate()
	add_child(panel2)
	panel2.set_player(respawned)
	panel2.open_panel()
	eq(panel2.get_origin_title_text(), "身份 · 锈械学者", "Badge preserved as '身份 · 锈械学者'")
	panel2.close_panel()
	panel2.queue_free()

	arena.queue_free()


# ===========================================================================
# 4. Boundary & Extreme Condition: Toxin Resist Cap (80%) and Floor (0%)
# ===========================================================================

func test_boundary_toxin_resist_cap_and_floor() -> void:
	var stats: CharacterStats = CharacterStatsScript.new()
	add_child(stats)

	# 1. Apply Rust Automaton (+0.20)
	stats.apply_origin(&"rust_automaton")
	almost(stats.get_toxin_resistance(), 0.20, 0.001, "Initial resist is 0.20")

	# 2. Add extreme equipment bonus (+0.80) -> total 1.00
	stats.bonus_toxin_resist = 0.80
	# 3. Add temporary modifier (+0.50) -> total 1.50
	stats.add_modifier(&"test_resist_buff", {"toxin_resist": 0.50})
	almost(stats.get_toxin_resistance(), 0.80, 0.0001, "Toxin resist strictly clamped to ceiling 0.80 (80%)")

	# 4. Remove buff and add severe negative debuff (-0.80) -> total 0.20 - 0.80 = -0.60
	stats.remove_modifier(&"test_resist_buff")
	stats.bonus_toxin_resist = 0.0
	stats.add_modifier(&"test_resist_curse", {"toxin_resist": -0.80})
	almost(stats.get_toxin_resistance(), 0.0, 0.0001, "Toxin resist strictly clamped to floor 0.00 (0%)")

	# 5. Parity with OriginCatalog.calculate_preview_stats
	var extreme_preview := OriginCatalogScript.calculate_preview_stats(
		&"rust_automaton",
		&"broken_sword",
		&"broken_armor",
		&"toxic_filter_talisman"
	)
	ok(float(extreme_preview["toxin_resist"]) <= 0.80, "Preview stat toxin resist does not exceed 0.80")

	stats.queue_free()


# ===========================================================================
# 5. Boundary & Extreme Condition: Speed Multiplier Floor (0.10) and Ceiling (3.00)
# ===========================================================================

func test_boundary_speed_multiplier_floor_and_ceiling() -> void:
	var stats: CharacterStats = CharacterStatsScript.new()
	add_child(stats)

	# 1. Apply Scrap Scavenger (+0.10 speed)
	stats.apply_origin(&"scrap_scavenger")
	almost(stats.get_speed_multiplier(), 1.10, 0.001, "Initial speed is 1.10")

	# 2. Add extreme positive speed bonus (+2.50) + modifier (+1.00) -> total 4.60
	stats.bonus_speed_mult = 2.50
	stats.add_modifier(&"super_haste", {"speed_mult": 1.00})
	almost(stats.get_speed_multiplier(), 3.00, 0.0001, "Speed multiplier strictly clamped to ceiling 3.00")

	# 3. Remove haste and add severe slow debuff (-2.00) -> total 1.10 - 2.00 = -0.90
	stats.remove_modifier(&"super_haste")
	stats.bonus_speed_mult = 0.0
	stats.add_modifier(&"deep_freeze", {"speed_mult": -2.00})
	almost(stats.get_speed_multiplier(), 0.10, 0.0001, "Speed multiplier strictly clamped to floor 0.10")

	stats.queue_free()


# ===========================================================================
# 6. Boundary & Extreme Condition: Damage Floor at 1
# ===========================================================================

func test_boundary_damage_floor_at_one() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Give player extreme defense (+100 defense)
	player.stats.base_defense = 100
	eq(player.stats.get_defense_reduction(), 100, "Player defense reduction is 100")

	player.health.current = 5
	player.health.max_hp = 5

	# Attacker deals 1 incoming damage: (1 - 100 = -99 <= 0)
	var dealt := player.health.take_damage(1, null)
	ok(dealt, "take_damage returned true")
	eq(player.health.current, 4, "Damage floor at 1: exactly 1 damage taken despite 100 defense")

	# Reset iframes to allow next hit
	player.health._hit_iframe = 0.0

	# Attacker deals 10 incoming damage: (10 - 100 = -90 <= 0)
	var dealt2 := player.health.take_damage(10, null)
	ok(dealt2, "take_damage returned true for 10 incoming damage")
	eq(player.health.current, 3, "Damage floor at 1: exactly 1 damage taken again")

	# Attacker deals 0 damage: should be rejected
	player.health._hit_iframe = 0.0
	var dealt_zero := player.health.take_damage(0, null)
	ok(not dealt_zero, "0 incoming damage is rejected (returns false)")
	eq(player.health.current, 3, "Health unchanged on 0 damage")

	# Attacker deals 105 damage: (105 - 100 = 5)
	player.health._hit_iframe = 0.0
	var dealt_higher := player.health.take_damage(105, null)
	ok(dealt_higher, "Damage exceeding defense penetrates")
	eq(player.health.current, 0, "Player health dropped by 5 to 0")

	arena.queue_free()


# ===========================================================================
# 7. Boundary & Extreme Condition: Unassigned Bare Player Defaults
# ===========================================================================

func test_boundary_unassigned_bare_player_defaults() -> void:
	# 1. Bare CharacterStats node defaults
	var stats: CharacterStats = CharacterStatsScript.new()
	add_child(stats)

	eq(stats.get_origin_id(), &"", "Bare origin_id is empty StringName")
	eq(stats.base_max_hp, 5, "Bare base_max_hp is 5")
	eq(stats.get_effective_max_hp(), 5, "Bare effective_max_hp is 5")
	eq(stats.base_attack, 0, "Bare base_attack is 0")
	eq(stats.get_attack_bonus(), 0, "Bare attack_bonus is 0")
	eq(stats.base_defense, 0, "Bare base_defense is 0")
	eq(stats.get_defense_reduction(), 0, "Bare defense_reduction is 0")
	almost(stats.get_toxin_resistance(), 0.0, 0.001, "Bare toxin_resistance is 0.0")
	almost(stats.get_toxin_decay_bonus(), 0.0, 0.001, "Bare toxin_decay is 0.0")
	almost(stats.get_speed_multiplier(), 1.0, 0.001, "Bare speed_multiplier is 1.0")

	# 2. Origin Reset Safety (apply valid then reset with "" and null)
	stats.apply_origin(&"ember_vanguard")
	eq(stats.get_origin_id(), &"ember_vanguard", "Origin applied")
	eq(stats.get_effective_max_hp(), 6, "HP increased to 6")

	stats.apply_origin("")
	eq(stats.get_origin_id(), &"", "Origin reset to empty string cleanly")
	eq(stats.get_effective_max_hp(), 5, "HP reset to 5")

	stats.apply_origin(&"scrap_scavenger")
	eq(stats.get_origin_id(), &"scrap_scavenger", "Origin applied")

	stats.apply_origin(null)
	eq(stats.get_origin_id(), &"", "Origin reset to null cleanly without errors")
	eq(stats.get_effective_max_hp(), 5, "HP reset to 5")

	stats.queue_free()

	# 3. Bare Player in Game
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var bare_player: Player = await spawn_player(arena)

	eq(bare_player.origin, &"", "Bare player origin is empty StringName")
	eq(bare_player.health.max_hp, 5, "Bare player health max_hp is 5")
	eq(bare_player.health.current, 5, "Bare player health current is 5")
	eq(bare_player.stats.get_attack_bonus(), 0, "Bare player attack bonus is 0")
	eq(bare_player.stats.get_defense_reduction(), 0, "Bare player defense reduction is 0")

	# 4. Bare Player UI Panel Badge Fallback
	var panel: CharacterEquipmentPanel = UI_PANEL_SCENE.instantiate()
	add_child(panel)
	panel.set_player(bare_player)
	panel.open_panel()
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "Bare player UI displays fallback badge '身份 · 余烬骑士'")
	panel.close_panel()
	panel.queue_free()

	arena.queue_free()
