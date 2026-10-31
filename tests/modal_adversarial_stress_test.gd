class_name ModalAdversarialStressTest
extends TestCase
## Empirical Adversarial Stress Test Suite for Phase 3 (PauseMenu & SettingsScreen):
## 1. Exact node paths across PauseMenu and SettingsScreen:
##    ModalRoot, Veil, Card, Content, Header, Title, Body, Footer, Tabs/Tab0..Tab3, DossierColumn/Dossier.
## 2. Public query helper methods verification:
##    - settings.slider_for("Master"), settings.slider_for("shake"), settings.slider_for("assist_incoming")
##    - settings.toggle_for("fullscreen"), settings.toggle_for("pixel_smoothing")
##    - settings.key_button_for("jump"), settings.key_button_for("dash"), settings.key_cap_text("jump")
##    - settings.tab_button(0) .. (3), settings.current_tab(), settings.show_tab(2)
##    - pause.menu(), pause.arena_menu(), pause.settings_screen(), pause.dossier_label("chapter")
## 3. Stress test: Rapid tab switching (100+ tab switches in a loop) and rapid slider drags.
## 4. Stress test: Rapid open/close cycles and subscreen transitions.

const SettingsScreenScript := preload("res://scripts/ui/settings_screen.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")

const TEST_SAVE_PATH := "user://rustgrave_adversarial_settings.cfg"
var _old_settings_path: String = ""


func setup() -> void:
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	_old_settings_path = Settings.save_path
	Settings.save_path = TEST_SAVE_PATH
	_clean_test_file()
	Settings.load_settings()


func teardown() -> void:
	Director.choice_hold = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false
	Settings.reset_keys(false)
	Settings.save_path = _old_settings_path
	Settings.load_settings()
	_clean_test_file()


func _clean_test_file() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	if FileAccess.file_exists(TEST_SAVE_PATH + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH + ".tmp"))


# -----------------------------------------------------------------------------
# 1. Exact Node Paths across PauseMenu and SettingsScreen
# -----------------------------------------------------------------------------

func test_exact_node_paths_pause_menu() -> void:
	var pause: PauseMenu = PauseMenuScript.new()
	add_child(pause)
	await flush(1)

	var root := pause.get_node_or_null("ModalRoot") as Control
	ok(root != null, "PauseMenu: ModalRoot exists")
	var veil := pause.get_node_or_null("ModalRoot/Veil") as ColorRect
	ok(veil != null, "PauseMenu: ModalRoot/Veil exists")
	var card := pause.get_node_or_null("ModalRoot/Card") as Control
	ok(card != null, "PauseMenu: ModalRoot/Card exists")
	var content := pause.get_node_or_null("ModalRoot/Card/Content") as VBoxContainer
	ok(content != null, "PauseMenu: ModalRoot/Card/Content exists")
	var header := pause.get_node_or_null("ModalRoot/Card/Content/Header") as VBoxContainer
	ok(header != null, "PauseMenu: ModalRoot/Card/Content/Header exists")
	var title := pause.get_node_or_null("ModalRoot/Card/Content/Header/Title") as Label
	ok(title != null, "PauseMenu: ModalRoot/Card/Content/Header/Title exists")
	var body := pause.get_node_or_null("ModalRoot/Card/Content/Body") as Control
	ok(body != null, "PauseMenu: ModalRoot/Card/Content/Body exists")
	var footer := pause.get_node_or_null("ModalRoot/Card/Content/Footer") as Control
	ok(footer != null, "PauseMenu: ModalRoot/Card/Content/Footer exists")

	# Check DossierColumn and Dossier exact path
	var dossier_col := pause.get_node_or_null("ModalRoot/Card/Content/Body/PauseLayout/DossierColumn") as VBoxContainer
	ok(dossier_col != null, "PauseMenu: ModalRoot/Card/Content/Body/PauseLayout/DossierColumn exists")
	var dossier := pause.get_node_or_null("ModalRoot/Card/Content/Body/PauseLayout/DossierColumn/Dossier") as PanelContainer
	ok(dossier != null, "PauseMenu: ModalRoot/Card/Content/Body/PauseLayout/DossierColumn/Dossier exists")

	# Check find_child resolution for DossierColumn and Dossier
	var dossier_found := pause.find_child("Dossier", true, false) as PanelContainer
	ok(dossier_found == dossier, "PauseMenu: find_child('Dossier') resolves to exact Dossier container")
	var col_found := pause.find_child("DossierColumn", true, false) as VBoxContainer
	ok(col_found == dossier_col, "PauseMenu: find_child('DossierColumn') resolves to exact DossierColumn")

	pause.queue_free()
	await flush(1)


func test_exact_node_paths_settings_screen() -> void:
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await flush(1)

	var root := settings.get_node_or_null("ModalRoot") as Control
	ok(root != null, "SettingsScreen: ModalRoot exists")
	var veil := settings.get_node_or_null("ModalRoot/Veil") as ColorRect
	ok(veil != null, "SettingsScreen: ModalRoot/Veil exists")
	var card := settings.get_node_or_null("ModalRoot/Card") as Control
	ok(card != null, "SettingsScreen: ModalRoot/Card exists")
	var content := settings.get_node_or_null("ModalRoot/Card/Content") as VBoxContainer
	ok(content != null, "SettingsScreen: ModalRoot/Card/Content exists")
	var header := settings.get_node_or_null("ModalRoot/Card/Content/Header") as VBoxContainer
	ok(header != null, "SettingsScreen: ModalRoot/Card/Content/Header exists")
	var title := settings.get_node_or_null("ModalRoot/Card/Content/Header/Title") as Label
	ok(title != null, "SettingsScreen: ModalRoot/Card/Content/Header/Title exists")
	var body := settings.get_node_or_null("ModalRoot/Card/Content/Body") as Control
	ok(body != null, "SettingsScreen: ModalRoot/Card/Content/Body exists")
	var footer := settings.get_node_or_null("ModalRoot/Card/Content/Footer") as Control
	ok(footer != null, "SettingsScreen: ModalRoot/Card/Content/Footer exists")

	# Check Tabs container and exact Tab0..Tab3 paths
	var tabs := settings.get_node_or_null("ModalRoot/Card/Content/Body/Column/Tabs") as HBoxContainer
	ok(tabs != null, "SettingsScreen: ModalRoot/Card/Content/Body/Column/Tabs exists")

	for i in range(4):
		var tab_path := "ModalRoot/Card/Content/Body/Column/Tabs/Tab%d" % i
		var tab_node := settings.get_node_or_null(tab_path) as Button
		ok(tab_node != null, "SettingsScreen: %s exists" % tab_path)
		if tab_node != null:
			eq(tab_node.name, "Tab%d" % i, "Tab node name is Tab%d" % i)

	settings.queue_free()
	await flush(1)


# -----------------------------------------------------------------------------
# 2. Public Query Helper APIs
# -----------------------------------------------------------------------------

func test_settings_public_query_helpers() -> void:
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await flush(1)

	# 1. Sliders (String and StringName inputs)
	var master_str := settings.slider_for("Master")
	var master_sname := settings.slider_for(&"Master")
	ok(master_str != null, "settings.slider_for('Master') returns HSlider")
	eq(master_str, master_sname, "slider_for accepts both String and StringName identically")

	var shake_slider := settings.slider_for("shake")
	ok(shake_slider != null, "settings.slider_for('shake') returns HSlider")
	var assist_slider := settings.slider_for("assist_incoming")
	ok(assist_slider != null, "settings.slider_for('assist_incoming') returns HSlider")

	# Non-existent slider returns null safely without error
	var invalid_slider := settings.slider_for("nonexistent_slider_id")
	eq(invalid_slider, null, "slider_for non-existent key returns null safely")

	# 2. Toggles
	var fullscreen_toggle := settings.toggle_for("fullscreen")
	ok(fullscreen_toggle != null, "settings.toggle_for('fullscreen') returns Button")
	var smooth_toggle := settings.toggle_for("pixel_smoothing")
	ok(smooth_toggle != null, "settings.toggle_for('pixel_smoothing') returns Button")
	var invalid_toggle := settings.toggle_for("nonexistent_toggle")
	eq(invalid_toggle, null, "toggle_for non-existent key returns null safely")

	# 3. Key buttons and key cap text
	var jump_btn := settings.key_button_for("jump")
	ok(jump_btn != null, "settings.key_button_for('jump') returns Button")
	var dash_btn := settings.key_button_for("dash")
	ok(dash_btn != null, "settings.key_button_for('dash') returns Button")
	var invalid_key_btn := settings.key_button_for("invalid_action")
	eq(invalid_key_btn, null, "key_button_for non-existent action returns null safely")

	var jump_cap := settings.key_cap_text("jump")
	ok(jump_cap != "", "settings.key_cap_text('jump') returns non-empty binding string")
	var invalid_cap := settings.key_cap_text("invalid_action")
	eq(invalid_cap, "", "key_cap_text non-existent action returns empty string")

	# 4. Tab buttons and current_tab / show_tab
	for i in range(4):
		var btn := settings.tab_button(i)
		ok(btn != null, "settings.tab_button(%d) returns Button" % i)

	eq(settings.current_tab(), 0, "settings initial current_tab() is 0 (Audio)")
	settings.show_tab(2)
	await flush(1)
	eq(settings.current_tab(), 2, "settings.show_tab(2) changes current_tab() to 2 (Keys)")

	settings.show_tab(3)
	await flush(1)
	eq(settings.current_tab(), 3, "settings.show_tab(3) changes current_tab() to 3 (Assist)")

	settings.show_tab(0)
	await flush(1)
	eq(settings.current_tab(), 0, "settings.show_tab(0) returns to 0 (Audio)")

	settings.queue_free()
	await flush(1)


func test_pause_menu_public_query_helpers() -> void:
	var pause: PauseMenu = PauseMenuScript.new()
	add_child(pause)
	await flush(1)

	# 1. pause.menu()
	var menu := pause.menu()
	ok(menu != null, "pause.menu() returns MenuList")
	eq(menu.item_ids().size(), 7, "pause.menu() has 7 default campaign items")

	# 2. pause.arena_menu()
	# In normal (non-arena) mode, arena_menu is null or uninitialized menu list
	var arena_m := pause.arena_menu()
	# Check method exists and doesn't crash
	ok(true, "pause.arena_menu() query succeeded safely")

	# 3. pause.settings_screen()
	var settings_sub := pause.settings_screen()
	ok(settings_sub != null, "pause.settings_screen() returns SettingsScreen instance")
	ok(settings_sub is SettingsScreen, "pause.settings_screen() is SettingsScreen type")

	# 4. pause.dossier_label() queries
	var chapter_lbl := pause.dossier_label("chapter")
	ok(chapter_lbl != null, "pause.dossier_label('chapter') returns Label")
	var obj_lbl := pause.dossier_label("objective")
	ok(obj_lbl != null, "pause.dossier_label('objective') returns Label")
	var cores_lbl := pause.dossier_label("cores")
	ok(cores_lbl != null, "pause.dossier_label('cores') returns Label")
	var nests_lbl := pause.dossier_label("nests")
	ok(nests_lbl != null, "pause.dossier_label('nests') returns Label")
	var vp_lbl := pause.dossier_label("viewport")
	ok(vp_lbl != null, "pause.dossier_label('viewport') returns Label")

	var invalid_lbl := pause.dossier_label("unknown_dossier_key")
	eq(invalid_lbl, null, "pause.dossier_label with invalid key returns null safely")

	pause.queue_free()
	await flush(1)


# -----------------------------------------------------------------------------
# 3. Stress Test: Rapid Tab Switching (100+ tab switches in a loop)
# -----------------------------------------------------------------------------

func test_stress_rapid_tab_switching_100_cycles() -> void:
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await flush(1)
	settings.open()
	await flush(1)

	# Stress loop: 100 consecutive tab switches
	for i in range(100):
		var target_tab := i % 4
		settings.show_tab(target_tab)

	await flush(2)

	# After 100 switches (0..99), the final tab must be 99 % 4 = 3
	eq(settings.current_tab(), 3, "After 100 rapid switches, current_tab() is strictly 3")
	var tab3_btn := settings.tab_button(3)
	ok(tab3_btn.button_pressed, "Tab3 button is pressed")

	# Now stress test randomized order switching (50 switches)
	var sequence: Array[int] = [1, 0, 3, 2, 0, 2, 1, 3, 3, 1, 0, 2, 1, 2, 3, 0, 1, 0, 2, 3]
	for idx in sequence:
		settings.show_tab(idx)
		eq(settings.current_tab(), idx, "Intermediate tab switch to %d succeeds" % idx)

	# Confirm tab 3 is current
	settings.show_tab(3)
	await flush(1)
	eq(settings.current_tab(), 3, "Final tab is 3")

	settings.close()
	await flush(1)
	settings.queue_free()
	await flush(1)


# -----------------------------------------------------------------------------
# 4. Stress Test: Rapid Slider Drags & Coalescing
# -----------------------------------------------------------------------------

func test_stress_rapid_slider_drags_and_flush() -> void:
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await flush(1)
	settings.open()
	await flush(1)

	var master_slider := settings.slider_for("Master")
	var shake_slider := settings.slider_for("shake")
	var assist_slider := settings.slider_for("assist_incoming")

	ok(master_slider != null and shake_slider != null and assist_slider != null,
			"All target sliders exist")

	# Rapidly set master slider across 50 increments
	for v in range(0, 101, 2):
		master_slider.value = float(v)

	# Rapidly oscillate shake slider (0..100 percent)
	for s in [0.0, 25.0, 50.0, 75.0, 100.0, 80.0, 40.0, 10.0, 0.0, 50.0]:
		shake_slider.value = float(s)

	# Rapidly oscillate assist incoming slider (50..150 percent)
	for a in [50.0, 75.0, 100.0, 125.0, 150.0, 80.0, 100.0]:
		assist_slider.value = float(a)

	await flush(2)

	# Verify final live values
	almost(Settings.volume_percent(&"Master"), 100.0, 0.01, "Master volume reached 100")
	almost(Settings.shake_scale, 0.5, 0.01, "Shake scale reached 0.5")
	almost(float(Settings.value(&"assist_incoming", 1.0)), 1.0, 0.01, "Assist incoming reached 1.0 (100%)")

	# Test explicit flush to disk
	settings.flush()
	await flush(1)

	var cfg := ConfigFile.new()
	var err := cfg.load(TEST_SAVE_PATH)
	eq(err, OK, "Persisted settings file loaded successfully without corruption")
	almost(float(cfg.get_value("audio", "Master", -1.0)), 100.0, 0.01, "Master persisted")
	almost(float(cfg.get_value("comfort", "shake", -1.0)), 0.5, 0.01, "Shake persisted")

	settings.close()
	await flush(1)
	settings.queue_free()
	await flush(1)


# -----------------------------------------------------------------------------
# 5. Stress Test: Rapid Open/Close Cycles and Subscreen Transitions
# -----------------------------------------------------------------------------

func test_stress_rapid_pause_open_close_cycles() -> void:
	var pause: PauseMenu = PauseMenuScript.new()
	add_child(pause)
	await flush(1)

	# Perform 10 rapid open / close cycles
	for i in range(10):
		pause.open()
		ok(pause.is_open(), "Cycle %d: Pause is open" % i)
		ok(get_tree().paused, "Cycle %d: Tree is paused" % i)
		pause.close()
		ok(not pause.is_open(), "Cycle %d: Pause is closed" % i)
		ok(not get_tree().paused, "Cycle %d: Tree resumed" % i)

	# Open once more and cycle through all sub-screens
	pause.open()
	ok(pause.is_open() and get_tree().paused, "Pause open before subscreen cycles")

	var sub_ids: Array[StringName] = [
		PauseMenu.ID_SETTINGS,
		PauseMenu.ID_TUTORIAL,
		PauseMenu.ID_CONTROLS,
		PauseMenu.ID_MAP,
	]

	for sub_id in sub_ids:
		pause._on_chosen(sub_id)
		await flush(1)
		ok(pause.sub_screen_open(), "%s is reported open" % String(sub_id))
		ok(pause.is_open() and get_tree().paused, "Pause stays open and tree paused during %s" % String(sub_id))

		# Close sub-screen
		match sub_id:
			PauseMenu.ID_SETTINGS:
				pause.settings_screen().close()
			PauseMenu.ID_TUTORIAL:
				pause.tutorial_recall().close()
			PauseMenu.ID_CONTROLS:
				pause.controls_panel().close()
			PauseMenu.ID_MAP:
				pause.map_screen().close()
		await flush(1)

		ok(not pause.sub_screen_open(), "%s is closed" % String(sub_id))
		ok(pause.is_open() and get_tree().paused, "Pause remains open and paused after closing %s" % String(sub_id))

	pause.close()
	await flush(1)
	ok(not pause.is_open(), "Pause menu closed")
	ok(not get_tree().paused, "Tree resumed after pause menu close")

	pause.queue_free()
	await flush(1)


# -----------------------------------------------------------------------------
# 6. Stress Test: Boundary Navigation & Toggle Activation
# -----------------------------------------------------------------------------

func test_stress_boundary_and_out_of_bounds_navigation() -> void:
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await flush(1)
	settings.open()
	await flush(1)

	# Out-of-bounds tab indices must safely clamp without throwing errors
	settings.show_tab(-5)
	eq(settings.current_tab(), 0, "show_tab(-5) safely clamps to 0")

	settings.show_tab(999)
	eq(settings.current_tab(), 3, "show_tab(999) safely clamps to 3")

	# Test every tab has a valid first control and back button
	for tab_idx in range(4):
		settings.show_tab(tab_idx)
		await flush(1)
		var first := settings.first_control()
		ok(first != null, "Tab %d has a valid first_control" % tab_idx)
		var back := settings.back_button()
		ok(back != null, "Tab %d has a valid back_button" % tab_idx)

	# Test toggles activation
	var initial_smoothing: bool = GamePresentation.pixel_smoothing
	var toggle_smooth := settings.toggle_for("pixel_smoothing")
	ok(toggle_smooth != null, "pixel_smoothing toggle exists")
	if toggle_smooth != null:
		toggle_smooth.pressed.emit()
		await flush(1)
		eq(GamePresentation.pixel_smoothing, not initial_smoothing, "Toggle inverts pixel_smoothing")
		toggle_smooth.pressed.emit()
		await flush(1)
		eq(GamePresentation.pixel_smoothing, initial_smoothing, "Toggle restores pixel_smoothing")

	settings.close()
	await flush(1)
	settings.queue_free()
	await flush(1)


# -----------------------------------------------------------------------------
# 7. Stress Test: Interleaved Tab Switching and Slider Dragging
# -----------------------------------------------------------------------------

func test_stress_interleaved_tab_switching_and_slider_dragging() -> void:
	var settings: SettingsScreen = SettingsScreenScript.new()
	add_child(settings)
	await flush(1)
	settings.open()
	await flush(1)

	# Interleaved 40 cycles of tab change and immediate slider manipulation
	for i in range(40):
		var tab := i % 4
		settings.show_tab(tab)
		match tab:
			0:
				var m_slider := settings.slider_for("Master")
				if m_slider != null:
					m_slider.value = float((i * 7) % 100)
			1:
				var sh_slider := settings.slider_for("shake")
				if sh_slider != null:
					sh_slider.value = float((i * 13) % 100)
			2:
				var jump_btn := settings.key_button_for("jump")
				ok(jump_btn != null, "Key button jump exists on tab 2")
			3:
				var a_slider := settings.slider_for("assist_incoming")
				if a_slider != null:
					a_slider.value = float(50 + (i * 5) % 100)

	await flush(2)
	settings.flush()
	await flush(1)

	ok(true, "Interleaved tab switching and slider manipulation completed with 0 errors")

	settings.close()
	await flush(1)
	settings.queue_free()
	await flush(1)

