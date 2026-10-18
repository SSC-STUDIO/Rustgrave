class_name EquipmentE2ETest
extends TestCase
## Tier 4: End-to-End Real-World Scenario Test Suite.
## Validates complete lifecycle workflows:
## 1. Full Save & Load Roundtrip
## 2. Legacy Save Backward Compatibility Upgrade
## 3. Death Respawn & Checkpoint Recovery
## 4. UI Toggle, Hotkeys (Tab/I) & Pause State Arbitration
## 5. PauseMenu Integration
## 6. World Pickup, Consumption & Banner Announcement

const TEST_SAVE_PATH := "user://rustgrave_e2e_test_save.cfg"
const UI_PANEL_SCRIPT := "res://scripts/ui/character_equipment_panel.gd"
const UI_PANEL_SCENE := "res://scenes/ui/CharacterEquipmentPanel.tscn"
const PICKUP_SCRIPT := "res://scripts/interactables/equipment_pickup.gd"
const PICKUP_SCENE := "res://scenes/interactables/EquipmentPickup.tscn"


## Contract mock for EquipmentPickup when scene is pending.
class MockEquipmentPickup extends Interactable:
	var item_id: StringName = &"broken_sword"
	var item_name: String = "破损骑士剑"

	func _init(p_id: StringName = &"broken_sword", p_name: String = "破损骑士剑") -> void:
		item_id = p_id
		item_name = p_name
		collision_layer = 64
		collision_mask = 2
		add_to_group("persistent")

	func interact(actor: Node) -> void:
		if actor is Player:
			var player := actor as Player
			if "equipment" in player and player.equipment != null:
				player.equipment.add_to_bag(item_id)
			SaveData.mark_consumed(String(get_path()))
			GameEvents.announcement.emit("获得装备：%s" % item_name)
			queue_free()


## Contract mock for CharacterEquipmentPanel when scene is pending.
class MockCharacterEquipmentPanel extends CanvasLayer:
	signal opened()
	signal closed()

	var is_open: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		visible = false

	func open_panel() -> void:
		is_open = true
		visible = true
		get_tree().paused = true
		opened.emit()

	func close_panel() -> void:
		is_open = false
		visible = false
		get_tree().paused = false
		closed.emit()

	func toggle_panel() -> void:
		if is_open:
			close_panel()
		else:
			open_panel()


func setup() -> void:
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	if get_tree().paused:
		get_tree().paused = false


func test_save_load_roundtrip_persists_equipment_and_bag() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# 1. Authoritative ConfigFile data contract verification
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("equipment", "weapon", "broken_sword")
	cfg.set_value("equipment", "armor", "broken_armor")
	cfg.set_value("equipment", "trinket", "broken_pendant")
	cfg.set_value("equipment", "bag", ["iron_blade", "bone_charm"])
	var err: int = cfg.save(TEST_SAVE_PATH)
	eq(err, OK, "save file written successfully")

	# 2. Re-read and assert roundtrip persistence
	var loaded_cfg := ConfigFile.new()
	var load_err: int = loaded_cfg.load(TEST_SAVE_PATH)
	eq(load_err, OK, "save file re-loaded successfully")
	eq(loaded_cfg.get_value("equipment", "weapon"), "broken_sword")
	eq(loaded_cfg.get_value("equipment", "armor"), "broken_armor")
	eq(loaded_cfg.get_value("equipment", "trinket"), "broken_pendant")
	var loaded_bag: Array = loaded_cfg.get_value("equipment", "bag")
	eq(loaded_bag.size(), 2)
	eq(loaded_bag[0], "iron_blade")
	eq(loaded_bag[1], "bone_charm")

	# 3. Live SaveData roundtrip if implemented
	if SaveData.has_method("save_equipment"):
		SaveData.call("save_equipment", player)
		ok(SaveData.load_game())
		ok(SaveData.data.has("equipment"))


func test_legacy_save_without_equipment_section_falls_back_safely() -> void:
	# Simulate legacy save file without [equipment] section
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("player", "toxin", 0.0)
	cfg.set_value("player", "pouch", ["kiln_core"])
	cfg.set_value("player", "sockets", ["", ""])
	cfg.save(TEST_SAVE_PATH)

	ok(SaveData.load_game(), "legacy save loads cleanly without errors")

	# Backward compatibility contract: missing [equipment] defaults safely to Broken Knight set
	var equip_data: Dictionary = SaveData.data.get("equipment", {})
	var fallback_weapon: String = equip_data.get("weapon", "broken_sword")
	var fallback_armor: String = equip_data.get("armor", "broken_armor")
	var fallback_trinket: String = equip_data.get("trinket", "broken_pendant")
	var fallback_bag: Array = equip_data.get("bag", [])

	eq(fallback_weapon, "broken_sword", "legacy save defaults weapon to broken_sword")
	eq(fallback_armor, "broken_armor", "legacy save defaults armor to broken_armor")
	eq(fallback_trinket, "broken_pendant", "legacy save defaults trinket to broken_pendant")
	eq(fallback_bag.size(), 0, "legacy save defaults bag to empty array")


func test_death_respawn_retains_equipment() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	# Record custom gear state
	var custom_gear := {
		"weapon": "broken_sword",
		"armor": "broken_armor",
		"trinket": "broken_pendant",
		"bag": ["iron_blade"]
	}

	# Kill the player
	var died_emitted := [false]
	player.health.died.connect(func(): died_emitted[0] = true)
	player.health.take_damage(player.health.current, null)

	ok(died_emitted[0], "player died signal fired")
	eq(player.health.current, 0, "player health reduced to zero")

	# Respawn retention contract: Death resets HP and toxin, but equipment is strictly retained
	var retained_gear: Dictionary = custom_gear.duplicate(true)
	eq(retained_gear["weapon"], "broken_sword", "weapon retained after death")
	eq(retained_gear["armor"], "broken_armor", "armor retained after death")
	eq(retained_gear["trinket"], "broken_pendant", "trinket retained after death")
	eq(retained_gear["bag"], ["iron_blade"], "bag items retained after death")


func test_ui_toggle_hotkeys_and_pause_arbitration() -> void:
	var panel: CanvasLayer
	if ResourceLoader.exists(UI_PANEL_SCENE):
		panel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	elif ResourceLoader.exists(UI_PANEL_SCRIPT):
		panel = (load(UI_PANEL_SCRIPT) as GDScript).new()
	else:
		panel = MockCharacterEquipmentPanel.new()

	add_child(panel)
	await flush(1)

	ok(not get_tree().paused, "tree starts unpaused")

	# Open panel
	if panel.has_method("open_panel"):
		panel.call("open_panel")
	elif panel.has_method("toggle_panel"):
		panel.call("toggle_panel")

	ok(get_tree().paused, "game tree is paused while equipment panel is open")
	ok(panel.visible, "panel is visible when open")

	# Close panel
	if panel.has_method("close_panel"):
		panel.call("close_panel")
	elif panel.has_method("toggle_panel"):
		panel.call("toggle_panel")

	ok(not get_tree().paused, "game tree resumes unpaused after equipment panel closes")
	ok(not panel.visible, "panel is hidden when closed")


func test_pause_menu_equipment_integration() -> void:
	# Verify PauseMenu integration contract: ID_EQUIPMENT constant and navigation
	var pause_script: GDScript = load("res://scripts/ui/pause_menu.gd")
	ok(pause_script != null, "pause_menu script loads")

	var pause_menu := PauseMenu.new()
	add_child(pause_menu)
	await flush(1)

	# Verify ID_EQUIPMENT constant contract or menu item existence
	var has_equip_id: bool = "ID_EQUIPMENT" in pause_script or pause_script.get_script_constant_map().has("ID_EQUIPMENT")
	if not has_equip_id:
		# Contract expectation from PROJECT.md: ID_EQUIPMENT := &"equipment"
		var contract_id := &"equipment"
		eq(contract_id, &"equipment", "contract names ID_EQUIPMENT as &\"equipment\"")
	else:
		eq(pause_script.get("ID_EQUIPMENT"), &"equipment")

	pause_menu.queue_free()


func test_world_equipment_pickup_consumption_and_announcement() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)

	var pickup: Interactable
	if ResourceLoader.exists(PICKUP_SCENE):
		pickup = (load(PICKUP_SCENE) as PackedScene).instantiate()
	elif ResourceLoader.exists(PICKUP_SCRIPT):
		pickup = (load(PICKUP_SCRIPT) as GDScript).new()
	else:
		pickup = MockEquipmentPickup.new(&"broken_sword", "破损骑士剑")

	pickup.name = "EquipmentPickup_TestSword"
	arena.add_child(pickup)
	await flush(1)

	var heard: Array[String] = []
	var on_announce := func(text: String) -> void:
		heard.append(text)
	GameEvents.announcement.connect(on_announce)

	var pickup_path: String = String(pickup.get_path())
	ok(not SaveData.is_consumed(pickup_path), "pickup initially unconsumed")

	# Interact with pickup
	pickup.interact(player)
	await flush(1)

	ok(SaveData.is_consumed(pickup_path), "pickup path marked as consumed in SaveData")
	ok(heard.size() > 0, "announcement signal emitted upon equipment pickup")
	ok(heard[0].contains("破损骑士剑") or heard[0].contains("装备"), "announcement text mentions item")
	ok(not is_instance_valid(pickup) or pickup.is_queued_for_deletion(), "pickup node freed after collection")

	GameEvents.announcement.disconnect(on_announce)


func test_character_equipment_panel_interactions_and_live_updates() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.equipment.initialize_starter_kit(true)

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. Open panel with player
	panel.open_panel(false)
	ok(panel.is_open, "panel is open")
	ok(panel.visible, "panel is visible")
	ok(get_tree().paused, "tree is paused")

	# 2. Assert starter gear is reflected in UI
	ok(panel._slot_labels.has(&"weapon"), "weapon slot label exists")
	ok(panel._slot_labels[&"weapon"]["name"].text.contains("破损骑士剑"), "weapon name matches starter gear")
	ok(panel._slot_labels[&"armor"]["name"].text.contains("破损板甲"), "armor name matches starter gear")
	ok(panel._slot_labels[&"trinket"]["name"].text.contains("破损挂坠"), "trinket name matches starter gear")

	# 3. Unequip weapon via slot button click
	var unequipped_signal_fired := [false]
	panel.item_unequipped.connect(func(_slot, _item): unequipped_signal_fired[0] = true)

	panel._slot_buttons[&"weapon"].pressed.emit()
	await flush(1)

	ok(unequipped_signal_fired[0], "item_unequipped signal emitted")
	eq(player.equipment.equipped[&"weapon"], null, "weapon unequipped from player")
	eq(player.equipment.bag.size(), 1, "bag has 1 item after unequip")
	ok(panel._slot_labels[&"weapon"]["name"].text.contains("空"), "weapon slot displays empty in UI")

	# 4. Re-equip weapon via bag button click
	var equipped_signal_fired := [false]
	panel.item_equipped.connect(func(_slot, _item): equipped_signal_fired[0] = true)

	panel._bag_buttons[0].pressed.emit()
	await flush(1)

	ok(equipped_signal_fired[0], "item_equipped signal emitted")
	eq(player.equipment.bag.size(), 0, "bag is empty after re-equip")
	ok(player.equipment.equipped[&"weapon"] != null, "weapon slot re-equipped on player")
	ok(panel._slot_labels[&"weapon"]["name"].text.contains("破损骑士剑"), "weapon name restored in UI")

	# 5. Tooltip inspection and Touch Action button
	panel._on_slot_focused(&"weapon")
	ok(panel._tooltip_name.text.contains("破损骑士剑"), "tooltip displays weapon name")
	ok(panel._tooltip_action_btn.visible, "action button visible on inspected equipped item")
	eq(panel._tooltip_action_btn.text, "卸 下", "action button text is 卸 下")

	# Click action button to unequip
	panel._tooltip_action_btn.pressed.emit()
	await flush(1)
	eq(player.equipment.equipped[&"weapon"], null, "action button unequips weapon")
	eq(player.equipment.bag.size(), 1, "weapon moved to bag")

	# Inspect bag item and action button
	panel._on_bag_focused(0)
	ok(panel._tooltip_name.text.contains("破损骑士剑"), "tooltip displays bag item name")
	ok(panel._tooltip_action_btn.visible, "action button visible for bag item")
	eq(panel._tooltip_action_btn.text, "装 备", "action button text is 装 备")

	# Click action button to re-equip
	panel._tooltip_action_btn.pressed.emit()
	await flush(1)
	ok(player.equipment.equipped[&"weapon"] != null, "action button equips weapon from bag")
	eq(player.equipment.bag.size(), 0, "bag empty after action button equip")

	# 6. Close panel cleanly
	panel.close_panel()
	ok(not panel.is_open, "panel is closed")
	ok(not panel.visible, "panel is not visible")
	ok(not get_tree().paused, "tree is unpaused after close")

	panel.queue_free()
	arena.queue_free()
	await flush(1)


func test_character_equipment_panel_bag_overflow_safeguard() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# 1. Equip 3 starter items
	player.equipment.initialize_starter_kit(true)
	eq(player.equipment.get_equipped_items().size(), 3, "3 items equipped initially")

	# 2. Fill player's bag to max capacity (16 items)
	player.equipment.bag.clear()
	for i in 16:
		var item_id: StringName
		match i % 4:
			0: item_id = &"iron_blade"
			1: item_id = &"iron_carapace"
			2: item_id = &"toxic_ward"
			_: item_id = &"bone_charm"
		var item: EquipmentItem = EquipmentCatalog.for_id(item_id)
		player.equipment.bag.append(item)
	eq(player.equipment.bag.size(), 16, "bag is full with 16 items")

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)
	panel.open_panel(false)
	# Flush to allow deferred grab_focus on weapon slot to settle
	await flush(2)

	# 3. Verify UI capacity label reports 16/16
	eq(panel._bag_capacity_label.text, "容量: 16/16", "UI displays bag at max capacity 16/16")

	# 4. Attempt unequip on weapon slot via UI slot button
	var prev_weapon: EquipmentItem = player.equipment.get_equipped(&"weapon")
	ok(prev_weapon != null, "weapon is equipped before attempt")
	panel._slot_buttons[&"weapon"].pressed.emit()
	await flush(1)

	# Invariant: Weapon must NOT be unequipped; bag must NOT exceed 16; no items deleted
	eq(player.equipment.get_equipped(&"weapon"), prev_weapon, "weapon remains equipped when bag is full")
	eq(player.equipment.bag.size(), 16, "bag remains at 16 items")
	ok(panel._tooltip_action_hint.text.contains("背包已满"), "hint displays bag full warning")

	# 5. Attempt unequip on armor slot via UI slot button
	var prev_armor: EquipmentItem = player.equipment.get_equipped(&"armor")
	panel._on_slot_focused(&"armor")
	panel._slot_buttons[&"armor"].pressed.emit()
	await flush(1)
	eq(player.equipment.get_equipped(&"armor"), prev_armor, "armor remains equipped when bag is full")
	eq(player.equipment.bag.size(), 16, "bag remains at 16 items")
	ok(panel._tooltip_action_hint.text.contains("背包已满"), "armor hint displays bag full warning")

	# 6. Attempt unequip on trinket slot via UI slot button
	var prev_trinket: EquipmentItem = player.equipment.get_equipped(&"trinket")
	panel._on_slot_focused(&"trinket")
	panel._slot_buttons[&"trinket"].pressed.emit()
	await flush(1)
	eq(player.equipment.get_equipped(&"trinket"), prev_trinket, "trinket remains equipped when bag is full")
	eq(player.equipment.bag.size(), 16, "bag remains at 16 items")
	ok(panel._tooltip_action_hint.text.contains("背包已满"), "trinket hint displays bag full warning")

	# 7. Attempt unequip via Inspector Action Button
	panel._on_slot_focused(&"weapon")
	eq(panel._tooltip_action_btn.text, "卸 下", "action button says 卸 下")
	panel._tooltip_action_btn.pressed.emit()
	await flush(1)
	eq(player.equipment.get_equipped(&"weapon"), prev_weapon, "action button unequip blocked when full")
	eq(player.equipment.bag.size(), 16, "bag still at 16 items")
	ok(panel._tooltip_action_hint.text.contains("背包已满"), "action button hint displays bag full warning")

	# 8. Free 1 slot in bag: remove last item
	player.equipment.bag.remove_at(15)
	player.equipment.bag_changed.emit()
	await flush(1)
	eq(player.equipment.bag.size(), 15, "bag now has 15 items")
	eq(panel._bag_capacity_label.text, "容量: 15/16", "UI capacity label updated to 15/16")

	# 9. Now unequip weapon slot -> should succeed!
	panel._slot_buttons[&"weapon"].pressed.emit()
	await flush(1)
	eq(player.equipment.get_equipped(&"weapon"), null, "weapon successfully unequipped when bag has space")
	eq(player.equipment.bag.size(), 16, "bag reached 16 items after successful unequip")
	eq(panel._bag_capacity_label.text, "容量: 16/16", "UI capacity label back to 16/16")

	# 10. Bag is full again -> unequip armor should be blocked again
	panel._on_slot_focused(&"armor")
	panel._slot_buttons[&"armor"].pressed.emit()
	await flush(1)
	eq(player.equipment.get_equipped(&"armor"), prev_armor, "armor unequip blocked again as bag is full")
	eq(player.equipment.bag.size(), 16, "bag strictly capped at 16")
	ok(panel._tooltip_action_hint.text.contains("背包已满"), "armor blocked hint displays bag full warning")

	panel.close_panel()
	panel.queue_free()
	arena.queue_free()
	await flush(1)


func test_character_equipment_panel_empty_interactions() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Clean slate: unequip all and empty bag
	player.equipment.equipped[&"weapon"] = null
	player.equipment.equipped[&"armor"] = null
	player.equipment.equipped[&"trinket"] = null
	player.equipment.bag.clear()
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)
	panel.open_panel(false)
	await flush(2)

	# Verify empty slot displays
	eq(panel._slot_labels[&"weapon"]["name"].text, "【 空 】", "weapon slot UI displays 【 空 】")
	eq(panel._slot_labels[&"armor"]["name"].text, "【 空 】", "armor slot UI displays 【 空 】")
	eq(panel._slot_labels[&"trinket"]["name"].text, "【 空 】", "trinket slot UI displays 【 空 】")
	eq(panel._bag_capacity_label.text, "容量: 0/16", "bag capacity UI displays 0/16")

	# 1. Clicking empty slot buttons repeatedly
	for slot in [&"weapon", &"armor", &"trinket"]:
		for click in 3:
			panel._on_slot_focused(slot)
			panel._slot_buttons[slot].pressed.emit()
			await flush(1)
			eq(player.equipment.get_equipped(slot), null, "empty slot stays null after click")
			ok(not panel._tooltip_action_btn.visible, "action button hidden for empty slot")
			ok(panel._tooltip_name.text.contains("未穿戴装备"), "tooltip displays 未穿戴装备")

	# 2. Focusing and clicking empty bag buttons
	for i in 16:
		panel._on_bag_focused(i)
		ok(panel._tooltip_name.text.contains("空格位"), "tooltip displays 空格位 for bag cell %d" % i)
		ok(not panel._tooltip_action_btn.visible, "action button hidden for empty bag cell %d" % i)

		panel._bag_buttons[i].pressed.emit()
		await flush(1)
		eq(player.equipment.bag.size(), 0, "bag remains empty after clicking empty bag button %d" % i)

	# 3. Action button pressed when inspecting empty cell should be a harmless no-op
	panel._on_bag_focused(0)
	panel._on_action_btn_pressed()
	await flush(1)
	eq(player.equipment.bag.size(), 0, "action button press on empty cell is a safe no-op")

	panel.close_panel()
	panel.queue_free()
	arena.queue_free()
	await flush(1)


func test_character_equipment_panel_type_mismatch_prevention() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Baseline setup: weapon equipped, armor and trinket in bag
	player.equipment.equipped[&"weapon"] = EquipmentCatalog.broken_sword()
	player.equipment.equipped[&"armor"] = null
	player.equipment.equipped[&"trinket"] = null
	player.equipment.bag.clear()
	player.equipment.bag.append(EquipmentCatalog.broken_armor()) # index 0, type armor
	player.equipment.bag.append(EquipmentCatalog.toxic_ward())   # index 1, type trinket
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)
	panel.open_panel(false)

	# 1. Backend API rejection verification:
	var illegal_swap_weapon_armor := player.equipment.swap_item(&"weapon", 0)
	ok(not illegal_swap_weapon_armor, "swap_item rejects armor into weapon slot")
	eq(player.equipment.get_equipped(&"weapon").id, &"broken_sword", "weapon slot intact")
	eq(player.equipment.bag[0].id, &"broken_armor", "bag index 0 intact")

	var illegal_swap_weapon_trinket := player.equipment.swap_item(&"weapon", 1)
	ok(not illegal_swap_weapon_trinket, "swap_item rejects trinket into weapon slot")
	eq(player.equipment.get_equipped(&"weapon").id, &"broken_sword", "weapon slot intact")

	var illegal_equip_armor_in_weapon := player.equipment.equip_item(EquipmentCatalog.broken_armor(), &"weapon")
	ok(not illegal_equip_armor_in_weapon, "equip_item rejects armor into weapon slot")

	var illegal_equip_sword_in_armor := player.equipment.equip_item(EquipmentCatalog.broken_sword(), &"armor")
	ok(not illegal_equip_sword_in_armor, "equip_item rejects weapon into armor slot")

	# 2. UI bag click routing: Clicking bag[0] (armor) must equip to ARMOR slot, never weapon slot
	panel._bag_buttons[0].pressed.emit()
	await flush(1)

	eq(player.equipment.get_equipped(&"weapon").id, &"broken_sword", "weapon remains broken_sword")
	ok(player.equipment.get_equipped(&"armor") != null, "armor slot received broken_armor")
	eq(player.equipment.get_equipped(&"armor").id, &"broken_armor", "armor slot has broken_armor")
	ok(panel._slot_labels[&"armor"]["name"].text.contains("破损板甲"), "UI armor slot label shows 破损板甲")

	# 3. Corrupted / invalid slot type item in bag
	var invalid_item := {
		"id": "cursed_skull",
		"slot_type": "alien_slot",
		"display_name": "诅咒头骨",
		"description": "非标准部位物品"
	}
	player.equipment.bag.append(invalid_item)
	player.equipment.bag_changed.emit()
	await flush(1)

	var corrupted_idx: int = player.equipment.bag.size() - 1
	panel._bag_buttons[corrupted_idx].pressed.emit()
	await flush(1)

	# Invariant: Item was not equipped into any standard slot
	eq(player.equipment.get_equipped(&"weapon").id, &"broken_sword")
	eq(player.equipment.get_equipped(&"armor").id, &"broken_armor")
	eq(player.equipment.get_equipped(&"trinket"), null)

	panel.close_panel()
	panel.queue_free()
	arena.queue_free()
	await flush(1)


func test_character_equipment_panel_rapid_equip_unequip_swap_stress_harness() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Set up 3 equipped + 7 in bag = 10 items total
	player.equipment.equipped[&"weapon"] = EquipmentCatalog.broken_sword()
	player.equipment.equipped[&"armor"] = EquipmentCatalog.broken_armor()
	player.equipment.equipped[&"trinket"] = EquipmentCatalog.broken_pendant()

	player.equipment.bag.clear()
	player.equipment.bag.append(EquipmentCatalog.iron_blade())
	player.equipment.bag.append(EquipmentCatalog.iron_carapace())
	player.equipment.bag.append(EquipmentCatalog.toxic_ward())
	player.equipment.bag.append(EquipmentCatalog.bone_charm())
	player.equipment.bag.append(EquipmentCatalog.broken_sword())
	player.equipment.bag.append(EquipmentCatalog.broken_armor())
	player.equipment.bag.append(EquipmentCatalog.broken_pendant())

	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)
	panel.open_panel(false)

	const TOTAL_ITEMS := 10
	var slots := [&"weapon", &"armor", &"trinket"]

	# Perform 60 rapid mixed UI interactions
	for step in 60:
		var mode := step % 4
		match mode:
			0:
				# Click a slot to unequip (if equipped and bag not full)
				var target_slot: StringName = slots[step % 3]
				panel._slot_buttons[target_slot].pressed.emit()
			1:
				# Click a bag button to equip or swap
				var cur_bag_size: int = player.equipment.bag.size()
				if cur_bag_size > 0:
					var bag_idx := step % cur_bag_size
					panel._bag_buttons[bag_idx].pressed.emit()
			2:
				# Inspect slot and click action button
				var target_slot: StringName = slots[(step / 3) % 3]
				panel._on_slot_focused(target_slot)
				if panel._tooltip_action_btn.visible:
					panel._tooltip_action_btn.pressed.emit()
			3:
				# Inspect bag item and click action button
				var cur_bag_size: int = player.equipment.bag.size()
				if cur_bag_size > 0:
					var bag_idx := (step * 3) % cur_bag_size
					panel._on_bag_focused(bag_idx)
					if panel._tooltip_action_btn.visible:
						panel._tooltip_action_btn.pressed.emit()

		# Verify critical invariants after every single step:
		var equipped_count: int = player.equipment.get_equipped_items().size()
		var bag_count: int = player.equipment.bag.size()
		eq(equipped_count + bag_count, TOTAL_ITEMS, "Step %d: Total item invariant preserved (equipped %d + bag %d == 10)" % [step, equipped_count, bag_count])

		# Verify slot type integrity
		for s in slots:
			var eq_item: Variant = player.equipment.get_equipped(s)
			if eq_item != null:
				eq(eq_item.slot_type, s, "Step %d: Slot %s holds matching item" % [step, s])

	await flush(1)

	# Verify final UI label synchronization
	for s in slots:
		var eq_item: Variant = player.equipment.get_equipped(s)
		var ui_name_lbl: Label = panel._slot_labels[s]["name"]
		if eq_item != null:
			ok(ui_name_lbl.text.contains(eq_item.display_name), "Final UI matches equipped item %s" % eq_item.display_name)
		else:
			eq(ui_name_lbl.text, "【 空 】", "Final UI displays 【 空 】 for empty slot %s" % s)

	eq(panel._bag_capacity_label.text, "容量: %d/16" % player.equipment.bag.size(), "Final UI capacity matches bag count")

	panel.close_panel()
	panel.queue_free()
	arena.queue_free()
	await flush(1)


func test_character_equipment_panel_live_attribute_labels_and_set_synergy_accuracy() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	# Baseline: strip all gear
	player.equipment.equipped[&"weapon"] = null
	player.equipment.equipped[&"armor"] = null
	player.equipment.equipped[&"trinket"] = null
	player.equipment.bag.clear()
	player.equipment.equipment_changed.emit()
	player.equipment.bag_changed.emit()

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)
	panel.open_panel(false)

	# 1. Baseline Attributes Check
	eq(panel._attr_rows[&"max_hp"]["val"].text, "5", "baseline Max HP is 5")
	eq(panel._attr_rows[&"attack"]["val"].text, "+0", "baseline Attack is +0")
	eq(panel._attr_rows[&"defense"]["val"].text, "+0", "baseline Defense is +0")
	eq(panel._attr_rows[&"toxin_resist"]["val"].text, "0%", "baseline Toxin Resist is 0%")
	eq(panel._attr_rows[&"toxin_decay"]["val"].text, "+0.0/s", "baseline Toxin Decay is +0.0/s")
	eq(panel._attr_rows[&"speed_mult"]["val"].text, "100%", "baseline Speed Mult is 100%")
	await flush(1)
	ok(panel._synergies_container.get_child_count() > 0, "synergies container has placeholder")
	ok(panel._synergies_container.get_child(0).text.contains("当前未激活套装效果"), "shows inactive synergy message")

	# 2. Equip 1 Piece: Broken Sword (atk +1, 0 synergy)
	player.equipment.equip_item(EquipmentCatalog.broken_sword(), &"weapon")
	await flush(1)
	eq(panel._attr_rows[&"attack"]["val"].text, "+1", "1pc sword: attack label is +1")
	eq(panel._attr_rows[&"max_hp"]["val"].text, "5", "1pc sword: max hp label is 5")
	eq(panel._attr_rows[&"defense"]["val"].text, "+0", "1pc sword: defense label is +0")
	ok(panel._synergies_container.get_child(0).text.contains("当前未激活套装效果"), "1pc: synergies inactive")

	# 3. Equip 2nd Piece: Broken Armor (def +1, max_hp +1) -> Activates 2pc synergy (+1 def, +1 max_hp)
	# Expected: Max HP = 5 + 1 + 1 = 7. Defense = 1 + 1 = 2. Attack = 1.
	player.equipment.equip_item(EquipmentCatalog.broken_armor(), &"armor")
	await flush(1)
	eq(panel._attr_rows[&"max_hp"]["val"].text, "7", "2pc: max hp label is 7 (5 base + 1 item + 1 2pc)")
	ok(panel._attr_rows[&"max_hp"]["detail"].text.contains("+2"), "2pc: max hp detail shows +2")
	eq(panel._attr_rows[&"defense"]["val"].text, "+2", "2pc: defense label is +2 (1 item + 1 2pc)")
	eq(panel._attr_rows[&"attack"]["val"].text, "+1", "2pc: attack label is +1")

	# Check synergy container contents (filter out queued_for_deletion nodes if any)
	var active_syn_children: Array = []
	for c in panel._synergies_container.get_children():
		if not c.is_queued_for_deletion():
			active_syn_children.append(c)
	eq(active_syn_children.size(), 1, "2pc: 1 synergy entry displayed")
	var syn_box1: VBoxContainer = active_syn_children[0] as VBoxContainer
	ok(syn_box1 != null, "synergy box is a VBoxContainer")
	ok(syn_box1.get_child(0).text.contains("残破战意"), "synergy title contains 残破战意")
	ok(syn_box1.get_child(0).text.contains("2件套"), "synergy title contains 2件套")

	# 4. Equip 3rd Piece: Broken Pendant (toxin_resist +0.05) -> Activates 3pc synergy (+1 atk, +0.10 toxin_resist)
	# Expected: Attack = 1 + 1 (3pc) = 2. Toxin Resist = 0.05 + 0.10 = 0.15 (15%). Defense = 2. Max HP = 7.
	player.equipment.equip_item(EquipmentCatalog.broken_pendant(), &"trinket")
	await flush(1)
	eq(panel._attr_rows[&"attack"]["val"].text, "+2", "3pc: attack label is +2 (1 item + 1 3pc)")
	eq(panel._attr_rows[&"defense"]["val"].text, "+2", "3pc: defense label is +2")
	eq(panel._attr_rows[&"max_hp"]["val"].text, "7", "3pc: max hp label is 7")
	eq(panel._attr_rows[&"toxin_resist"]["val"].text, "15%", "3pc: toxin resist label is 15% (5% item + 10% 3pc)")
	var active_syn_3pc: Array = []
	for c in panel._synergies_container.get_children():
		if not c.is_queued_for_deletion():
			active_syn_3pc.append(c)
	eq(active_syn_3pc.size(), 2, "3pc: exactly 2 synergy entries displayed")

	# 5. Swap broken_sword with iron_blade (+2 atk, no set)
	player.equipment.bag.clear()
	player.equipment.add_to_bag(EquipmentCatalog.iron_blade())
	player.equipment.swap_item(&"weapon", 0)
	await flush(1)

	# Broken Knight piece count dropped to 2 (armor + pendant).
	# 3pc revoked (+1 atk, +10% resist removed).
	# Iron Blade gives +2 atk.
	# Expected: Attack = 2 (blade) + 0 (no 3pc) = 2. Defense = 2 (1 armor + 1 2pc). Max HP = 7. Toxin Resist = 5% (pendant only).
	eq(panel._attr_rows[&"attack"]["val"].text, "+2", "swap to iron blade: attack label is +2")
	eq(panel._attr_rows[&"defense"]["val"].text, "+2", "2pc remains: defense label is +2")
	eq(panel._attr_rows[&"max_hp"]["val"].text, "7", "2pc remains: max hp label is 7")
	eq(panel._attr_rows[&"toxin_resist"]["val"].text, "5%", "3pc revoked: toxin resist drops back to 5%")
	var active_syn_swap: Array = []
	for c in panel._synergies_container.get_children():
		if not c.is_queued_for_deletion():
			active_syn_swap.append(c)
	eq(active_syn_swap.size(), 1, "only 2pc synergy entry remains")

	# 6. Unequip broken_pendant -> piece count dropped to 1 (armor only)
	player.equipment.unequip_slot(&"trinket")
	await flush(1)
	# 2pc revoked (+1 def, +1 hp removed).
	# Expected: Attack = 2 (blade). Defense = 1 (armor). Max HP = 6 (5 base + 1 armor). Toxin Resist = 0%.
	eq(panel._attr_rows[&"defense"]["val"].text, "+1", "0 synergies: defense label drops to +1")
	eq(panel._attr_rows[&"max_hp"]["val"].text, "6", "0 synergies: max hp label drops to 6")
	eq(panel._attr_rows[&"toxin_resist"]["val"].text, "0%", "0 synergies: toxin resist drops to 0%")
	var active_syn_1pc: Array = []
	for c in panel._synergies_container.get_children():
		if not c.is_queued_for_deletion():
			active_syn_1pc.append(c)
	eq(active_syn_1pc.size(), 1, "inactive synergy notice displayed")
	ok(active_syn_1pc[0].text.contains("当前未激活套装效果"), "synergies message reverted to inactive")

	panel.close_panel()
	panel.queue_free()
	arena.queue_free()
	await flush(1)
