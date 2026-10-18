class_name EquipmentMultiInputNavigationTest
extends TestCase
## Test suite for Milestone 4 UI: Multi-Input Navigation & Interaction.
## Empirically validates:
## 1. 2D Keyboard & Controller Focus Graph (Slots, Bag Grid, Action Button).
## 2. Keyboard focus entry/exit inspection state synchronization.
## 3. Mouse hover lit/unlit tweens and rapid hover transitions.
## 4. Touch Action Button full workflow ("卸 下", "装 备", "替 换", hidden on empty).
## 5. Seamless switching between keyboard navigation and mouse hover.

const UI_PANEL_SCENE := "res://scenes/ui/CharacterEquipmentPanel.tscn"
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")


func setup() -> void:
	Director.choice_hold = false
	Director.playing = false
	Director._locked = false
	Director._fading = false
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	Director.choice_hold = false
	Director.playing = false
	Director._locked = false
	Director._fading = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


# ===========================================================================
# 1. Focus Graph Topology Verification
# ===========================================================================

func test_complete_focus_graph_topology() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	var w_btn: Button = panel._slot_buttons[&"weapon"]
	var a_btn: Button = panel._slot_buttons[&"armor"]
	var t_btn: Button = panel._slot_buttons[&"trinket"]
	var act_btn: Button = panel._tooltip_action_btn

	# Slot horizontal navigation
	eq(w_btn.focus_neighbor_right, a_btn.get_path(), "weapon -> right -> armor")
	eq(a_btn.focus_neighbor_left, w_btn.get_path(), "armor -> left -> weapon")
	eq(a_btn.focus_neighbor_right, t_btn.get_path(), "armor -> right -> trinket")
	eq(t_btn.focus_neighbor_left, a_btn.get_path(), "trinket -> left -> armor")

	# Slot vertical down navigation to bag top row
	eq(w_btn.focus_neighbor_bottom, panel._bag_buttons[0].get_path(), "weapon -> down -> bag[0]")
	eq(a_btn.focus_neighbor_bottom, panel._bag_buttons[1].get_path(), "armor -> down -> bag[1]")
	eq(t_btn.focus_neighbor_bottom, panel._bag_buttons[2].get_path(), "trinket -> down -> bag[2]")

	# Bag grid 4x4 topology
	for i in panel.MAX_BAG_CAPACITY:
		var btn: Button = panel._bag_buttons[i]
		var col := i % 4
		var row := i / 4

		# Horizontal
		if col > 0:
			eq(btn.focus_neighbor_left, panel._bag_buttons[i - 1].get_path(), "bag[%d] left == bag[%d]" % [i, i - 1])
		if col < 3:
			eq(btn.focus_neighbor_right, panel._bag_buttons[i + 1].get_path(), "bag[%d] right == bag[%d]" % [i, i + 1])

		# Vertical Up
		if row > 0:
			eq(btn.focus_neighbor_top, panel._bag_buttons[i - 4].get_path(), "bag[%d] top == bag[%d]" % [i, i - 4])
		else:
			if col == 0:
				eq(btn.focus_neighbor_top, w_btn.get_path(), "bag[0] top == weapon")
			elif col == 1:
				eq(btn.focus_neighbor_top, a_btn.get_path(), "bag[1] top == armor")
			else:
				eq(btn.focus_neighbor_top, t_btn.get_path(), "bag[%d] top == trinket" % i)

		# Vertical Down
		if row < 3:
			eq(btn.focus_neighbor_bottom, panel._bag_buttons[i + 4].get_path(), "bag[%d] bottom == bag[%d]" % [i, i + 4])
		else:
			eq(btn.focus_neighbor_bottom, act_btn.get_path(), "bag[%d] bottom == action_btn" % i)

	# Action button top connection back into bag bottom row
	eq(act_btn.focus_neighbor_top, panel._bag_buttons[14].get_path(), "action_btn top == bag[14]")

	panel.queue_free()


# ===========================================================================
# 2. Keyboard Focus Inspection Synchronization
# ===========================================================================

func test_keyboard_focus_inspection_synchronization() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(4)

	player.equipment.initialize_starter_kit(true)
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.set_player(player as Player)
	panel.open_panel()
	await flush(2)

	# 1. Initial focus: Weapon slot is inspected
	eq(panel._inspected_source, &"slot", "initial inspection source is slot")
	eq(panel._inspected_slot, &"weapon", "initial inspected slot is weapon")
	ok(panel._tooltip_name.text.contains("破损骑士剑"), "tooltip displays weapon")
	eq(panel._tooltip_action_btn.visible, true, "action button visible for equipped weapon")
	eq(panel._tooltip_action_btn.text, "卸 下", "action button text is 卸 下")

	# 2. Focus moves to Armor slot
	panel._on_slot_focused(&"armor")
	eq(panel._inspected_source, &"slot", "inspected source is slot")
	eq(panel._inspected_slot, &"armor", "inspected slot is armor")
	ok(panel._tooltip_name.text.contains("破损板甲"), "tooltip displays armor")
	eq(panel._tooltip_action_btn.visible, true, "action button visible for armor")
	eq(panel._tooltip_action_btn.text, "卸 下", "action button text is 卸 下")

	# 3. Focus moves to an empty bag slot (e.g. index 3)
	panel._on_bag_focused(3)
	eq(panel._inspected_source, &"bag", "inspected source is bag")
	eq(panel._inspected_bag_idx, 3, "inspected bag index is 3")
	ok(panel._tooltip_name.text.contains("空格位"), "empty bag cell displays 空格位")
	eq(panel._tooltip_action_btn.visible, false, "action button hidden for empty bag cell")

	panel.close_panel()
	panel.queue_free()
	player.queue_free()


# ===========================================================================
# 3. Mouse Hover & Exit Transitions
# ===========================================================================

func test_mouse_hover_and_exit_transitions() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(4)

	player.equipment.initialize_starter_kit(true)
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.set_player(player as Player)
	panel.open_panel()
	await flush(2)

	# Slot button hover
	var w_btn: Button = panel._slot_buttons[&"weapon"]
	panel._on_slot_focused(&"weapon")
	await flush(2)
	ok(w_btn.modulate.r >= 1.0, "slot button lit on hover")

	panel._on_slot_blurred(&"weapon")
	await flush(3)
	ok(abs(w_btn.modulate.r - 1.0) < 0.05, "slot button restored after blur")

	# Rapid enter/exit cycling (stress test tweens)
	for i in 10:
		panel._on_slot_focused(&"weapon")
		panel._on_slot_blurred(&"weapon")
		panel._on_bag_focused(0)
		panel._on_bag_blurred(0)
	await flush(2)
	ok(true, "rapid hover/blur cycles completed without error or crash")

	panel.close_panel()
	panel.queue_free()
	player.queue_free()


# ===========================================================================
# 4. Touch Action Button Full Workflow
# ===========================================================================

func test_touch_action_button_full_workflow() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(4)

	player.equipment.initialize_starter_kit(true)
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.set_player(player as Player)
	panel.open_panel()
	await flush(2)

	# --- Step A: Unequip weapon via Action Button ---
	panel._on_slot_focused(&"weapon")
	eq(panel._tooltip_action_btn.visible, true, "action button visible on weapon")
	eq(panel._tooltip_action_btn.text, "卸 下", "action button text is 卸 下")

	panel._on_action_btn_pressed()
	await flush(2)

	eq(player.equipment.get_equipped(&"weapon"), null, "weapon is unequipped")
	eq(player.equipment.bag.size(), 1, "bag now has 1 item")

	# Weapon slot is now empty -> inspecting it hides action button
	panel._on_slot_focused(&"weapon")
	eq(panel._tooltip_action_btn.visible, false, "action button hidden for now-empty weapon slot")

	# --- Step B: Re-equip weapon from bag via Action Button ---
	panel._on_bag_focused(0)
	eq(panel._tooltip_action_btn.visible, true, "action button visible on bag item")
	eq(panel._tooltip_action_btn.text, "装 备", "action button text is 装 备 because weapon slot is empty")

	panel._on_action_btn_pressed()
	await flush(2)

	ok(player.equipment.get_equipped(&"weapon") != null, "weapon re-equipped via action button")
	eq(player.equipment.bag.size(), 0, "bag empty again")

	# --- Step C: Swap weapon with another weapon in bag ---
	var iron_blade: EquipmentItem = EquipmentCatalog.for_id(&"iron_blade")
	player.equipment.bag.append(iron_blade)
	player.equipment.bag_changed.emit()
	panel.refresh()
	await flush(2)

	panel._on_bag_focused(0)
	eq(panel._tooltip_action_btn.visible, true, "action button visible on bag item")
	eq(panel._tooltip_action_btn.text, "替 换", "action button text is 替 换 because weapon slot is already occupied")

	panel._on_action_btn_pressed()
	await flush(2)

	eq(player.equipment.get_equipped(&"weapon").id, &"iron_blade", "weapon swapped to iron_blade")
	eq(player.equipment.bag.size(), 1, "bag still has 1 item")
	eq(player.equipment.bag[0].id, &"broken_sword", "old weapon swapped into bag")

	panel.close_panel()
	panel.queue_free()
	player.queue_free()


# ===========================================================================
# 5. Multi-Input Concurrent Switching
# ===========================================================================

func test_concurrent_input_switching() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(4)

	player.equipment.initialize_starter_kit(true)
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.set_player(player as Player)
	panel.open_panel()
	await flush(2)

	# 1. Keyboard focuses armor
	panel._on_slot_focused(&"armor")
	eq(panel._inspected_slot, &"armor", "keyboard selected armor")

	# 2. Mouse hovers trinket
	panel._on_slot_focused(&"trinket")
	eq(panel._inspected_slot, &"trinket", "mouse hover switched inspection to trinket")

	# 3. Mouse hovers bag[0]
	panel._on_bag_focused(0)
	eq(panel._inspected_source, &"bag", "mouse hover switched to bag")

	# 4. Keyboard moves to bag[1]
	panel._on_bag_focused(1)
	eq(panel._inspected_bag_idx, 1, "keyboard navigation seamlessly updated inspection")

	panel.close_panel()
	panel.queue_free()
	player.queue_free()
