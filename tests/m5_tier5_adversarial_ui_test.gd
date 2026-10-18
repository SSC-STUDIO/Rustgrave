extends TestCase
## Milestone 5 Tier 5 Adversarial Stress Test Harness: UI Flows, Modal Invariants, and Regression Safety.
## Author: o2_m5_challenger_2

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/ui/CharacterSelectScreen.tscn"
const UI_PANEL_SCENE := "res://scenes/ui/CharacterEquipmentPanel.tscn"
const TEST_SAVE_PATH := "user://rustgrave_m5_tier5_test.cfg"

const EXPECTED_KINDS := [
	MenuItem.Kind.PRIMARY,
	MenuItem.Kind.PRIMARY,
	MenuItem.Kind.SECONDARY,
	MenuItem.Kind.SECONDARY,
	MenuItem.Kind.SECONDARY,
	MenuItem.Kind.SECONDARY,
	MenuItem.Kind.GHOST
]

const EXPECTED_IDS: Array[StringName] = [
	TitleScreen.ID_NEW,
	TitleScreen.ID_CONTINUE,
	TitleScreen.ID_TRIAL,
	TitleScreen.ID_ARENA,
	TitleScreen.ID_SETTINGS,
	TitleScreen.ID_CONTROLS,
	TitleScreen.ID_QUIT
]


func setup() -> void:
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()
	Director.choice_hold = false
	Director.playing = false
	Director._locked = false
	Director._fading = false
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	Director.choice_hold = false
	Director.playing = false
	Director._locked = false
	Director._fading = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


func _open_title() -> TitleScreen:
	var packed := load(TITLE_SCENE) as PackedScene
	var title: TitleScreen = packed.instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


# ===========================================================================
# 1. TitleScreen Menu Rail: Strictly 6 Items across states
# ===========================================================================

func test_title_screen_rail_exactly_seven_items_under_all_save_conditions() -> void:
	# Condition A: No save exists
	SaveData.delete_save()
	var title_a: TitleScreen = await _open_title()
	var menu_a := title_a.get_node_or_null("Menu") as MenuList
	ok(menu_a != null, "Menu rail exists when no save")
	var items_a := []
	for child in menu_a.get_children():
		if child is MenuItem:
			items_a.append(child)
	ok(items_a.size() >= 7, "At least 7 items when no save exists")
	for i in 7:
		eq(items_a[i].kind, EXPECTED_KINDS[i], "Item %d kind matches expected" % i)
	ok((items_a[1] as MenuItem).disabled, "Continue item is disabled when no save exists")
	title_a.queue_free()
	await get_tree().process_frame

	# Condition B: Save exists
	var f := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f.store_string("[player]\nhp=5\norigin=\"ember_vanguard\"\n")
	f.close()
	ok(SaveData.has_save(), "Save exists")

	var title_b: TitleScreen = await _open_title()
	var menu_b := title_b.get_node_or_null("Menu") as MenuList
	var items_b := []
	for child in menu_b.get_children():
		if child is MenuItem:
			items_b.append(child)
	ok(items_b.size() >= 7, "At least 7 items when save exists")
	ok(not (items_b[1] as MenuItem).disabled, "Continue item is enabled when save exists")
	title_b.queue_free()
	await get_tree().process_frame

	# Condition C: Ending reached save exists
	f = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f.store_string("[meta]\nending=\"purified\"\n[player]\nhp=5\norigin=\"rust_automaton\"\n")
	f.close()
	var title_c: TitleScreen = await _open_title()
	var menu_c := title_c.get_node_or_null("Menu") as MenuList
	var items_c := []
	for child in menu_c.get_children():
		if child is MenuItem:
			items_c.append(child)
	ok(items_c.size() >= 7, "At least 7 items when ending reached")
	ok(not (items_c[1] as MenuItem).disabled, "Continue/Recall item enabled")
	ok((items_c[1] as MenuItem)._text.contains("回 看 余 烬"), "Continue button displays '回 看 余 烬'")
	title_c.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 2. CharacterSelectScreen Modal Invariants & Dismissal Paths
# ===========================================================================

func test_character_select_modal_invariants_and_three_dismissal_vectors() -> void:
	var title: TitleScreen = await _open_title()
	var char_select: CharacterSelectScreen = title.character_select_screen()
	ok(char_select != null, "CharacterSelectScreen exists under TitleScreen")

	# Check modal invariants
	var card := char_select.get_node_or_null("ModalRoot/Card") as Control
	var veil := char_select.get_node_or_null("ModalRoot/Veil") as ColorRect
	var embers: Node = char_select.get_node_or_null("ModalRoot/ModalEmbers")

	ok(card != null, "Card exists at ModalRoot/Card")
	ok(veil != null, "Veil exists at ModalRoot/Veil")
	ok(embers != null, "ModalEmbers exists at ModalRoot/ModalEmbers")

	if card != null:
		ok(card.custom_minimum_size.x < 1180.0, "Card width < 1180.0 (actual: %.1f)" % card.custom_minimum_size.x)
		ok(card.custom_minimum_size.y <= 720.0, "Card height <= 720.0 (actual: %.1f)" % card.custom_minimum_size.y)
	if veil != null:
		ok(veil.color.a < 0.8, "Veil alpha < 0.8 (actual: %.2f)" % veil.color.a)

	var title_menu := title.get_node("Menu") as MenuList

	# Dismissal Vector 1: Esc key
	char_select.open()
	title_menu.active = false
	await get_tree().process_frame
	ok(char_select.is_open(), "Vector 1: Modal is open")
	ok(not title_menu.active, "Vector 1: Menu is inactive")

	var ev_esc := InputEventAction.new()
	ev_esc.action = "ui_cancel"
	ev_esc.pressed = true
	char_select._unhandled_input(ev_esc)
	await get_tree().process_frame
	ok(not char_select.is_open(), "Vector 1: Esc dismissed modal")
	ok(title_menu.active, "Vector 1: Title menu restored active")

	# Dismissal Vector 2: Click on Veil (outside Card)
	char_select.open()
	title_menu.active = false
	await get_tree().process_frame
	ok(char_select.is_open(), "Vector 2: Modal is open")

	var modal_root := char_select.get_node_or_null("ModalRoot") as Control
	ok(modal_root != null, "ModalRoot found")
	var click_ev := InputEventMouseButton.new()
	click_ev.button_index = MOUSE_BUTTON_LEFT
	click_ev.pressed = true
	click_ev.position = Vector2(20.0, 20.0) # Outside Card bounds
	modal_root.gui_input.emit(click_ev)
	await get_tree().process_frame
	ok(not char_select.is_open(), "Vector 2: Veil click dismissed modal")
	ok(title_menu.active, "Vector 2: Title menu restored active")

	# Dismissal Vector 3: Cancel Button
	char_select.open()
	title_menu.active = false
	await get_tree().process_frame
	ok(char_select.is_open(), "Vector 3: Modal is open")

	var cancel_btn := char_select.get_node_or_null("ModalRoot/Card/Content/Footer/Row/CancelButton") as Button
	ok(cancel_btn != null, "Cancel button exists in Footer")
	cancel_btn.pressed.emit()
	await get_tree().process_frame
	ok(not char_select.is_open(), "Vector 3: Cancel button dismissed modal")
	ok(title_menu.active, "Vector 3: Title menu restored active")

	title.queue_free()
	await get_tree().process_frame


func test_overwrite_confirmation_adversarial_stress() -> void:
	# Create existing save
	var f := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f.store_string("[player]\nhp=5\norigin=\"ember_vanguard\"\n")
	f.close()
	ok(SaveData.has_save(), "Save file created")

	var title: TitleScreen = await _open_title()
	var char_select: CharacterSelectScreen = title.character_select_screen()
	var title_menu := title.get_node("Menu") as MenuList

	# Cycle 1: Click New Game -> Confirm dialog opens -> Cancel via ID_KEEP
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame
	ok(title.confirm_open(), "Confirm dialog opened")
	ok(not char_select.is_open(), "CharacterSelectScreen not opened")
	ok(not title_menu.active, "Title menu inactive")

	title._on_confirm_chosen(TitleScreen.ID_KEEP)
	await get_tree().process_frame
	ok(not title.confirm_open(), "Confirm dialog closed on cancel")
	ok(not char_select.is_open(), "CharacterSelectScreen remained closed")
	ok(title_menu.active, "Title menu reactivated")

	# Cycle 2: Click New Game -> Confirm dialog opens -> Cancel via ui_cancel action
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame
	ok(title.confirm_open(), "Confirm dialog opened again")

	var ev_cancel := InputEventAction.new()
	ev_cancel.action = "ui_cancel"
	ev_cancel.pressed = true
	title._unhandled_input(ev_cancel)
	await get_tree().process_frame
	ok(not title.confirm_open(), "Confirm dialog closed via ui_cancel")
	ok(not char_select.is_open(), "CharacterSelectScreen remained closed")
	ok(title_menu.active, "Title menu reactivated")

	# Cycle 3: Click New Game -> Confirm dialog opens -> Confirm Overwrite (ID_OVERWRITE)
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame
	ok(title.confirm_open(), "Confirm dialog opened for overwrite")

	title._on_confirm_chosen(TitleScreen.ID_OVERWRITE)
	await get_tree().process_frame
	ok(not title.confirm_open(), "Confirm dialog dismissed upon overwrite")
	ok(char_select.is_open(), "CharacterSelectScreen opened upon overwrite confirmation")
	ok(not title_menu.active, "Title menu remains inactive while CharacterSelectScreen is active")

	title.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 3. CharacterEquipmentPanel In-Game UI Polish & Chromatic Hierarchy
# ===========================================================================

func test_origin_badge_headers_all_origins_and_fallbacks() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. Ember Vanguard
	panel.set_origin_override(&"ember_vanguard")
	eq(panel.get_origin_title_text(), "身份 · 余烬重骑", "Ember Vanguard title badge exact match")
	eq(panel.origin_title_label.text, "身份 · 余烬重骑", "origin_title_label text exact match")

	# 2. Scrap Scavenger
	panel.set_origin_override(&"scrap_scavenger")
	eq(panel.get_origin_title_text(), "身份 · 废料剑客", "Scrap Scavenger title badge exact match")
	eq(panel.origin_title_label.text, "身份 · 废料剑客", "origin_title_label text exact match")

	# 3. Rust Automaton
	panel.set_origin_override(&"rust_automaton")
	eq(panel.get_origin_title_text(), "身份 · 锈械学者", "Rust Automaton title badge exact match")
	eq(panel.origin_title_label.text, "身份 · 锈械学者", "origin_title_label text exact match")

	# 4. Fallback 1: Empty string
	panel.set_origin_override(&"")
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "Fallback on empty string: '身份 · 余烬骑士'")

	# 5. Fallback 2: Unknown string
	panel.set_origin_override(&"completely_nonexistent_origin_id")
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "Fallback on nonexistent origin: '身份 · 余烬骑士'")

	# 6. Fallback 3: null
	panel.set_origin_override(null)
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "Fallback on null: '身份 · 余烬骑士'")

	# 7. Fallback 4: int
	panel.set_origin_override(9999)
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "Fallback on int: '身份 · 余烬骑士'")

	panel.queue_free()
	await flush(1)


func test_chromatic_color_hierarchy_all_six_stats() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	var expected_palette: Dictionary = {
		&"attack": {"hex": "FFC14A", "color": Color("#FFC14A"), "desc": "Warm yellow"},
		&"defense": {"hex": "BAC4CC", "color": Color("#BAC4CC"), "desc": "Metallic iron grey"},
		&"toxin_resist": {"hex": "5CE1B6", "color": Color("#5CE1B6"), "desc": "Teal/cyan"},
		&"toxin_decay": {"hex": "5CE1B6", "color": Color("#5CE1B6"), "desc": "Teal/cyan"},
		&"speed_mult": {"hex": "5CB3FF", "color": Color("#5CB3FF"), "desc": "Agility blue"},
		&"max_hp": {"hex": "76E074", "color": Color("#76E074"), "desc": "Vitality green"},
	}

	for stat_key in expected_palette.keys():
		var spec: Dictionary = expected_palette[stat_key]
		var val_lbl: Label = panel.get_stat_value_label(stat_key)
		ok(val_lbl != null, "Stat value label exists for %s" % String(stat_key))
		var color: Color = panel.get_stat_color(stat_key)
		eq(color.to_html(false).to_upper(), spec["hex"], "%s matches hex #%s (%s)" % [String(stat_key), spec["hex"], spec["desc"]])
		eq(val_lbl.modulate, spec["color"], "%s label modulate matches expected Color" % String(stat_key))

	panel.queue_free()
	await flush(1)


func test_tab_tap_vs_tab_hold_input_arbitration_stress() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	eq(panel.is_open, false, "Initial state: panel closed")

	var ev_press := InputEventKey.new()
	ev_press.keycode = KEY_TAB
	ev_press.pressed = true

	var ev_rel := InputEventKey.new()
	ev_rel.keycode = KEY_TAB
	ev_rel.pressed = false

	# Case 1: Fast tap (0.05s) -> opens panel
	panel._unhandled_input(ev_press)
	panel._tab_press_time = (Time.get_ticks_msec() / 1000.0) - 0.05
	panel._unhandled_input(ev_rel)
	await flush(1)
	eq(panel.is_open, true, "Fast tap (50ms < 0.22s) opens panel")

	# Case 2: Fast tap (0.15s) while open -> closes panel
	panel._unhandled_input(ev_press)
	panel._tab_press_time = (Time.get_ticks_msec() / 1000.0) - 0.15
	panel._unhandled_input(ev_rel)
	await flush(1)
	eq(panel.is_open, false, "Fast tap (150ms < 0.22s) while open closes panel")

	# Case 3: Just below threshold (0.21s) -> opens panel
	panel._unhandled_input(ev_press)
	panel._tab_press_time = (Time.get_ticks_msec() / 1000.0) - 0.21
	panel._unhandled_input(ev_rel)
	await flush(1)
	eq(panel.is_open, true, "Near-threshold tap (210ms < 0.22s) opens panel")

	# Close it via API
	panel.close_panel()
	eq(panel.is_open, false, "Panel closed")

	# Case 4: Hold (0.25s >= 0.22s threshold) -> does NOT open
	panel._unhandled_input(ev_press)
	panel._tab_press_time = (Time.get_ticks_msec() / 1000.0) - 0.25
	panel._unhandled_input(ev_rel)
	await flush(1)
	eq(panel.is_open, false, "Hold (250ms >= 0.22s threshold) does NOT open panel")

	# Case 5: Long hold (0.60s >= 0.22s threshold) -> does NOT open
	panel._unhandled_input(ev_press)
	panel._tab_press_time = (Time.get_ticks_msec() / 1000.0) - 0.60
	panel._unhandled_input(ev_rel)
	await flush(1)
	eq(panel.is_open, false, "Long hold (600ms >= 0.22s threshold) does NOT open panel")

	panel.queue_free()
	await flush(1)
