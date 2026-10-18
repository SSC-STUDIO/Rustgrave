class_name CharacterEquipmentAdversarialTest
extends TestCase
## Adversarial Challenge & Stress Test Suite for M4 UI & Pause Arbitration.
## Specifically validates:
## 1. Rapid open/close/toggle cycling (re-entrance, idempotency, tree pause sync).
## 2. Director.choice_hold arbitration (blocks hotkeys, prevents premature unpausing).
## 3. PauseMenu Esc navigation lifecycle (Game -> PauseMenu -> Equipment -> PauseMenu -> Game).
## 4. Null actor / headless safety (full lifecycle without Player in scene tree).
## 5. Player death reception (auto-close on death, blocks opening while dead).
## 6. Tab hotkey hold vs tap threshold arbitration (<0.22s tap toggles, >=0.22s peek ignores).
## 7. Director fading, playing, and input lock guards.
## 8. Player cutscene lock guard.
## 9. Full bag unequip rejection and error feedback.
## 10. Mid-session player node deletion (freed player robustness).
## 11. Modal veil mouse click dismiss inside PauseMenu.

const UI_PANEL_SCENE := "res://scenes/ui/CharacterEquipmentPanel.tscn"
const CharacterEquipmentPanelScript := preload("res://scripts/ui/character_equipment_panel.gd")


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


func test_rapid_open_close_and_toggle_cycling() -> void:
	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	var open_count := [0]
	var close_count := [0]
	panel.opened.connect(func(): open_count[0] += 1)
	panel.closed.connect(func(): close_count[0] += 1)

	# 1. Repeated open_panel() idempotency
	for i in 5:
		panel.open_panel()
	eq(open_count[0], 1, "consecutive open_panel() only emits opened once")
	ok(panel.visible, "panel is visible")
	ok(panel.is_open, "panel is marked open")
	ok(get_tree().paused, "tree is paused")

	# 2. Repeated close_panel() idempotency
	for i in 5:
		panel.close_panel()
	eq(close_count[0], 1, "consecutive close_panel() only emits closed once")
	ok(not panel.visible, "panel is hidden")
	ok(not panel.is_open, "panel is marked closed")
	ok(not get_tree().paused, "tree is unpaused")

	# 3. High-frequency alternating toggle_panel() (20 iterations)
	for i in range(1, 21):
		panel.toggle_panel()
		if i % 2 == 1:
			ok(panel.visible, "iteration %d: panel open" % i)
			ok(get_tree().paused, "iteration %d: tree paused" % i)
		else:
			ok(not panel.visible, "iteration %d: panel closed" % i)
			ok(not get_tree().paused, "iteration %d: tree unpaused" % i)

	eq(open_count[0], 1 + 10, "total open emissions: 1 initial + 10 toggles")
	eq(close_count[0], 1 + 10, "total close emissions: 1 initial + 10 toggles")

	panel.queue_free()
	await flush(1)


func test_choice_hold_blocks_opening_and_prevents_premature_unpause() -> void:
	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. can_open() must return false when choice_hold is active
	Director.choice_hold = true
	ok(not panel.can_open(), "can_open() returns false when Director.choice_hold is true")

	# 2. Hotkey input (KEY_I) must be blocked while choice_hold is active
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.echo = false
	key_event.keycode = KEY_I
	panel._unhandled_input(key_event)

	ok(not panel.visible, "KEY_I does not open panel during choice_hold")
	ok(not panel.is_open, "panel is_open remains false")

	# 3. If tree is paused and choice_hold is active (e.g. ending choice), closing panel must NOT unpause
	get_tree().paused = true
	panel.open_panel(false) # Direct open
	ok(panel.visible, "panel forced open for stress check")
	ok(get_tree().paused, "tree remains paused")

	panel.close_panel()
	ok(not panel.visible, "panel closed")
	ok(get_tree().paused, "close_panel strictly preserves pause state when choice_hold is true")

	# 4. If opened normally, then choice_hold is activated, close_panel must NOT unpause
	Director.choice_hold = false
	get_tree().paused = false
	panel.open_panel(false) # Standalone open: pauses tree
	ok(get_tree().paused, "standalone open paused the tree")

	Director.choice_hold = true # Ending triggers while panel open
	panel.close_panel()
	ok(get_tree().paused, "close_panel did not unpause because choice_hold was engaged")

	Director.choice_hold = false
	get_tree().paused = false
	panel.queue_free()
	await flush(1)


func test_pause_menu_esc_stack_lifecycle() -> void:
	var pause_menu := PauseMenu.new()
	add_child(pause_menu)
	await flush(1)

	var equip_panel: CanvasLayer = pause_menu.equipment_panel()
	ok(equip_panel != null, "equipment panel child exists in PauseMenu")

	# 1. Open PauseMenu
	ok(not get_tree().paused, "tree initially unpaused")
	pause_menu.open()
	ok(pause_menu.is_open(), "PauseMenu is open")
	ok(get_tree().paused, "PauseMenu paused the tree")
	ok(not equip_panel.visible, "equipment panel is initially hidden")

	# 2. Select Equipment from PauseMenu rail
	pause_menu._on_chosen(PauseMenu.ID_EQUIPMENT)
	ok(equip_panel.visible, "equipment panel is now visible")
	ok(equip_panel.is_open, "equipment panel is marked open")
	ok(pause_menu.sub_screen_open(), "PauseMenu recognizes subscreen is open")
	ok(get_tree().paused, "tree remains paused in equipment panel")

	# 3. Press Esc (Esc 1: closes equipment panel back to PauseMenu)
	var esc_event := InputEventKey.new()
	esc_event.pressed = true
	esc_event.echo = false
	esc_event.keycode = KEY_ESCAPE
	equip_panel._unhandled_input(esc_event)

	ok(not equip_panel.visible, "Esc 1 closed equipment panel")
	ok(not equip_panel.is_open, "equipment panel is marked closed")
	ok(pause_menu.is_open(), "PauseMenu remains open after Esc 1")
	ok(not pause_menu.sub_screen_open(), "subscreen is no longer open")
	ok(get_tree().paused, "CRITICAL: tree must NOT unpause when returning to PauseMenu")

	# 4. Press Esc again (Esc 2: closes PauseMenu back to Game)
	pause_menu._unhandled_input(esc_event)

	ok(not pause_menu.is_open(), "Esc 2 closed PauseMenu")
	ok(not get_tree().paused, "CRITICAL: tree must unpause when exiting PauseMenu to game")

	# 5. Nested force close safety: if pause_menu.close() is called while equipment is open
	pause_menu.open()
	pause_menu._on_chosen(PauseMenu.ID_EQUIPMENT)
	ok(equip_panel.visible, "equipment reopened")
	pause_menu.close() # Direct close
	ok(not pause_menu.is_open(), "PauseMenu closed")
	ok(not equip_panel.visible, "equipment panel closed recursively")
	ok(not get_tree().paused, "tree resumed")

	pause_menu.queue_free()
	await flush(1)


func test_null_actor_headless_safety_without_player() -> void:
	# Ensure scene tree has no Player node
	var existing_player := get_tree().get_first_node_in_group("player")
	if existing_player != null:
		existing_player.queue_free()
		await flush(2)

	eq(get_tree().get_first_node_in_group("player"), null, "verified tree has no Player node")

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. can_open() without player must be safe
	ok(panel.can_open(), "can_open() is safe without player")

	# 2. open_panel() without player must not crash
	panel.open_panel()
	ok(panel.visible, "panel opened without player")
	ok(get_tree().paused, "tree paused without player")

	# 3. Label contents have safe fallbacks
	eq(panel._attr_rows[&"max_hp"]["val"].text, "5", "safe default HP is 5")
	eq(panel._attr_rows[&"attack"]["val"].text, "+0", "safe default attack is +0")
	eq(panel._attr_rows[&"defense"]["val"].text, "+0", "safe default defense is +0")
	eq(panel._attr_rows[&"toxin_resist"]["val"].text, "0%", "safe default toxin resist is 0%")
	eq(panel._attr_rows[&"toxin_decay"]["val"].text, "+0.0/s", "safe default toxin decay is +0.0/s")
	eq(panel._attr_rows[&"speed_mult"]["val"].text, "100%", "safe default speed mult is 100%")

	# 4. Button interactions without player must degrade safely without errors
	panel._on_slot_pressed(&"weapon")
	panel._on_slot_pressed(&"armor")
	panel._on_slot_pressed(&"trinket")
	panel._on_bag_pressed(0)
	panel._on_bag_pressed(15)
	panel._on_action_btn_pressed()
	panel._on_slot_focused(&"weapon")
	panel._on_bag_focused(0)

	# 5. close_panel() and toggle_panel() without player
	panel.close_panel()
	ok(not panel.visible, "closed cleanly without player")
	ok(not get_tree().paused, "unpaused cleanly without player")

	panel.toggle_panel()
	ok(panel.visible, "toggled open without player")
	panel.toggle_panel()
	ok(not panel.visible, "toggled closed without player")

	panel.queue_free()
	await flush(1)


func test_player_death_reception_and_block() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. Open panel while player is alive
	panel.open_panel()
	ok(panel.visible, "panel open with live player")

	# 2. Player dies while panel is open: panel must auto-close
	player.health.take_damage(999, null)
	eq(player.health.current, 0, "player HP is 0")
	ok(not panel.visible, "panel automatically closed upon player death")
	ok(not panel.is_open, "panel is_open is false")

	# 3. While player is dead, can_open() must return false
	ok(not panel.can_open(), "can_open() returns false while player is dead")

	# 4. KEY_I hotkey must be blocked while player is dead
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.echo = false
	key_event.keycode = KEY_I
	panel._unhandled_input(key_event)
	ok(not panel.visible, "KEY_I does not open panel while player is dead")

	panel.queue_free()
	player.queue_free()
	arena.queue_free()
	await flush(1)


func test_tab_key_hold_threshold_arbitration() -> void:
	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. Quick tap (< 0.22s): Tab down, immediate Tab up -> toggles open
	var tab_down := InputEventKey.new()
	tab_down.pressed = true
	tab_down.echo = false
	tab_down.keycode = KEY_TAB
	panel._unhandled_input(tab_down)

	var tab_up_quick := InputEventKey.new()
	tab_up_quick.pressed = false
	tab_up_quick.echo = false
	tab_up_quick.keycode = KEY_TAB
	panel._unhandled_input(tab_up_quick)

	ok(panel.visible, "quick Tab tap opens panel")
	ok(get_tree().paused, "tree is paused")

	# 2. Quick tap inside open panel: closes panel
	panel._unhandled_input(tab_down)
	panel._unhandled_input(tab_up_quick)
	ok(not panel.visible, "quick Tab tap closes panel")
	ok(not get_tree().paused, "tree is unpaused")

	# 3. Hold Tab (>= 0.22s): simulate long press
	panel._unhandled_input(tab_down)
	# Simulate time elapsed > threshold
	panel._tab_press_time = (Time.get_ticks_msec() / 1000.0) - 0.50 # 500ms ago

	var tab_up_hold := InputEventKey.new()
	tab_up_hold.pressed = false
	tab_up_hold.echo = false
	tab_up_hold.keycode = KEY_TAB
	panel._unhandled_input(tab_up_hold)

	ok(not panel.visible, "long Tab hold (>=0.22s) does NOT open panel (preserves HUD peeking)")
	ok(not get_tree().paused, "tree remains unpaused on Tab hold")

	panel.queue_free()
	await flush(1)


func test_director_states_block_opening() -> void:
	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. Director.playing blocks opening
	Director.playing = true
	ok(not panel.can_open(), "can_open() blocked while Director.playing is true")
	Director.playing = false

	# 2. Director lock blocks opening
	Director._locked = true
	ok(not panel.can_open(), "can_open() blocked while Director input is locked")
	Director._locked = false

	# 3. Director fading blocks opening
	Director._fading = true
	ok(not panel.can_open(), "can_open() blocked while Director is fading")
	Director._fading = false

	panel.queue_free()
	await flush(1)


func test_player_cutscene_lock_blocks_opening() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# When player has cutscene_locked = true
	player.cutscene_locked = true
	ok(not panel.can_open(), "can_open() blocked when player.cutscene_locked is true")

	player.cutscene_locked = false
	ok(panel.can_open(), "can_open() allowed when cutscene_locked is released")

	panel.queue_free()
	player.queue_free()
	arena.queue_free()
	await flush(1)


func test_full_bag_unequip_rejection_and_error_feedback() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	player.equipment.initialize_starter_kit(true)

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.open_panel()
	await flush(2)

	# Fill bag to 16 items
	player.equipment.bag.clear()
	for i in 16:
		player.equipment.bag.append(EquipmentCatalog.broken_sword())

	eq(player.equipment.bag.size(), 16, "bag is full with 16 items")

	# Ensure weapon is focused, then attempt to unequip weapon while bag is full
	panel._on_slot_focused(&"weapon")
	panel._on_slot_pressed(&"weapon")

	ok(player.equipment.get_equipped(&"weapon") != null, "weapon remains equipped when bag is full")
	eq(player.equipment.bag.size(), 16, "bag size remains 16")
	ok(panel._tooltip_action_hint.text.contains("背包已满"), "rejection message displayed in tooltip hint")
	await flush(1)

	panel.close_panel()
	panel.queue_free()
	player.queue_free()
	arena.queue_free()
	await flush(1)


func test_mid_session_freed_player_robustness() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)

	var panel: CanvasLayer = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.open_panel()
	ok(panel.visible)

	# Prematurely free player while panel is open
	player.queue_free()
	await flush(2)

	# Subsequent calls must degrade gracefully without crashing
	panel._refresh_all()
	panel._on_slot_pressed(&"weapon")
	panel._on_bag_pressed(0)
	panel._on_action_btn_pressed()
	panel.close_panel()

	ok(not panel.visible, "panel closed cleanly after player freed")
	ok(not get_tree().paused, "tree unpaused cleanly after player freed")

	panel.queue_free()
	arena.queue_free()
	await flush(1)


func test_modal_veil_mouse_click_dismiss_in_pause_menu() -> void:
	var pause_menu := PauseMenu.new()
	add_child(pause_menu)
	await flush(1)

	var equip_panel: CanvasLayer = pause_menu.equipment_panel()
	pause_menu.open()
	pause_menu._on_chosen(PauseMenu.ID_EQUIPMENT)
	ok(equip_panel.visible)
	ok(get_tree().paused)

	# Simulate clicking modal veil on _root
	var mouse_click := InputEventMouseButton.new()
	mouse_click.button_index = MOUSE_BUTTON_LEFT
	mouse_click.pressed = true
	equip_panel._root.gui_input.emit(mouse_click)

	ok(not equip_panel.visible, "clicking veil closed equipment panel")
	ok(pause_menu.is_open(), "PauseMenu remains open after veil click")
	ok(get_tree().paused, "tree remains paused after veil click dismiss")

	pause_menu.close()
	ok(not pause_menu.is_open())
	ok(not get_tree().paused)

	pause_menu.queue_free()
	await flush(1)
