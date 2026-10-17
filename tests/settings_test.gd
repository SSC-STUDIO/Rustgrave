extends TestCase
## Settings autoload: persistence, corrupt-file fallback, key rebinding, volume.
## Redirects the settings file and restores live InputMap / buses afterwards.

const TEST_PATH := "user://rustgrave_test_settings.cfg"

var _old_path := ""


func setup() -> void:
	_old_path = Settings.save_path
	Settings.save_path = TEST_PATH
	_remove(TEST_PATH)
	_remove(TEST_PATH + ".tmp")
	Settings.load_settings()


func teardown() -> void:
	Settings.reset_keys(false)
	Settings.save_path = _old_path
	Settings.load_settings()
	_remove(TEST_PATH)
	_remove(TEST_PATH + ".tmp")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_defaults_without_a_file() -> void:
	ok(not Settings.load_settings(), "no file means defaults, not success")
	almost(Settings.shake_scale, 1.0)
	almost(Settings.flash_scale, 1.0)
	almost(Settings.volume_percent(&"Sfx"), 100.0)
	almost(Settings.volume_percent(&"Music"), 80.0)


func test_round_trip_keeps_volume_comfort_and_extra() -> void:
	Settings.set_volume_percent(&"Sfx", 35.0)
	Settings.set_shake_scale(0.25)
	Settings.set_flash_scale(0.0)
	Settings.set_value(&"hints_on", false)
	Settings.save_settings()
	ok(FileAccess.file_exists(TEST_PATH), "settings written")
	ok(not FileAccess.file_exists(TEST_PATH + ".tmp"), "temp file renamed away")
	Settings.shake_scale = 1.0
	Settings.flash_scale = 1.0
	Settings.set_volume_percent(&"Sfx", 100.0, false)
	ok(Settings.load_settings(), "valid file loads")
	almost(Settings.volume_percent(&"Sfx"), 35.0)
	almost(Settings.shake_scale, 0.25)
	almost(Settings.flash_scale, 0.0)
	eq(Settings.value(&"hints_on", true), false)


func test_corrupt_file_falls_back_to_defaults() -> void:
	# Syntactically valid but meaningless / empty files must not leak into the settings.
	# (A truly unparsable file makes ConfigFile log an engine error; the fallback path
	# is the same because load() simply returns non-OK.)
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[meta]\nversion=\"nonsense\"\n[audio]\nSfx=\"loud\"\n")
	file.close()
	ok(not Settings.load_settings(), "garbage version rejected")
	almost(Settings.volume_percent(&"Master"), 100.0)
	almost(Settings.shake_scale, 1.0)
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.close()
	ok(not Settings.load_settings(), "empty file rejected")
	var foreign := ConfigFile.new()
	foreign.set_value("meta", "version", 99)
	foreign.set_value("audio", "Sfx", 5.0)
	foreign.save(TEST_PATH)
	ok(not Settings.load_settings(), "foreign version rejected")
	almost(Settings.volume_percent(&"Sfx"), 100.0)


func test_out_of_range_values_are_clamped() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", Settings.VERSION)
	cfg.set_value("audio", "Sfx", 900.0)
	cfg.set_value("audio", "Music", -4.0)
	cfg.set_value("comfort", "shake", 7.0)
	cfg.save(TEST_PATH)
	ok(Settings.load_settings())
	almost(Settings.volume_percent(&"Sfx"), 100.0)
	almost(Settings.volume_percent(&"Music"), 0.0)
	almost(Settings.shake_scale, 1.0)


func test_volume_reaches_the_audio_server() -> void:
	var idx := AudioServer.get_bus_index(&"Sfx")
	ok(idx >= 0, "Sfx bus exists")
	Settings.set_volume_percent(&"Sfx", 50.0, false)
	almost(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.5, 0.01)
	Settings.set_volume_percent(&"Sfx", 0.0, false)
	ok(AudioServer.is_bus_mute(idx), "zero mutes the bus")
	Settings.set_volume_percent(&"Sfx", 100.0, false)
	ok(not AudioServer.is_bus_mute(idx))


func test_rebind_replaces_only_the_first_key() -> void:
	var before := InputMap.action_get_events(&"move_left").size()
	eq(Settings.rebind_action(&"move_left", KEY_Q, false), &"")
	eq(Settings.key_for(&"move_left"), int(KEY_Q))
	eq(InputMap.action_get_events(&"move_left").size(), before, "arrow-key alias kept")
	var probe := InputEventKey.new()
	probe.physical_keycode = KEY_Q
	probe.pressed = true
	ok(InputMap.event_is_action(probe, &"move_left"), "Q now moves left")
	var old := InputEventKey.new()
	old.physical_keycode = KEY_A
	old.pressed = true
	ok(not InputMap.event_is_action(old, &"move_left"), "A no longer moves left")


func test_rebind_to_a_taken_key_swaps_instead_of_leaving_a_hole() -> void:
	var jump_key := Settings.key_for(&"jump")
	var dash_key := Settings.key_for(&"dash")
	eq(Settings.rebind_action(&"jump", dash_key, false), &"dash", "swap reported")
	eq(Settings.key_for(&"jump"), dash_key)
	eq(Settings.key_for(&"dash"), jump_key, "dash took jump's old key")
	for action in Settings.REBINDABLE:
		ok(Settings.key_for(action) > 0, "%s still bound" % action)


func test_reserved_keys_are_refused() -> void:
	var before := Settings.key_for(&"jump")
	eq(Settings.rebind_action(&"jump", KEY_ESCAPE, false), &"reserved")
	eq(Settings.rebind_action(&"jump", KEY_ENTER, false), &"reserved")
	eq(Settings.key_for(&"jump"), before)
	eq(Settings.rebind_action(&"ui_cancel", KEY_Q, false), &"reserved", "unknown action refused")


func test_bindings_persist_and_reset_restores_defaults() -> void:
	var default_attack := Settings.default_key_for(&"attack")
	Settings.rebind_action(&"attack", KEY_L)
	Settings.reset_keys(false)
	eq(Settings.key_for(&"attack"), default_attack)
	Settings.rebind_action(&"attack", KEY_L)
	Settings.load_settings()
	eq(Settings.key_for(&"attack"), int(KEY_L), "binding survives a reload")
	Settings.reset_keys()
	Settings.load_settings()
	eq(Settings.key_for(&"attack"), default_attack, "reset persisted")


func test_slider_drags_coalesce_into_one_delayed_write() -> void:
	_remove(TEST_PATH)
	for i in 40:
		Settings.set_volume_percent(&"Music", float(i))
	ok(not FileAccess.file_exists(TEST_PATH), "nothing is written while the slider is still moving")
	await get_tree().create_timer(0.7, true, false, true).timeout
	ok(FileAccess.file_exists(TEST_PATH), "one write lands shortly after the last change")
	var cfg := ConfigFile.new()
	eq(cfg.load(TEST_PATH), OK)
	almost(float(cfg.get_value("audio", "Music", -1.0)), 39.0, 0.01, "the final value is what got written")


## 设置页必须把持久化过的每一项都摆出来：四条总线、震屏 / 闪光、全屏 / 平滑、
## 教学提示，以及全部可改键动作。
func test_settings_screen_exposes_every_persisted_option() -> void:
	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	for bus in Settings.VOLUME_BUSES:
		ok(screen.slider_for(bus) != null, "声音页有 %s 滑条" % String(bus))
	ok(screen.slider_for(&"shake") != null, "震屏强度滑条")
	ok(screen.slider_for(&"flash") != null, "闪光强度滑条")
	ok(screen.toggle_for(SettingsScreen.OPT_FULLSCREEN) != null, "全屏开关")
	ok(screen.toggle_for(SettingsScreen.OPT_SMOOTHING) != null, "像素平滑开关")
	ok(screen.toggle_for(HintService.SETTING_ENABLED) != null, "教学提示开关")
	screen.show_tab(SettingsScreen.TAB_KEYS)
	for action in Settings.REBINDABLE:
		ok(screen.key_button_for(action) != null, "键位页有 %s" % String(action))
	screen.queue_free()
	await get_tree().process_frame


## 滑条拖动只改内存；关闭 / 停手后由设置页 flush 落盘，且持久化格式不变。
func test_settings_screen_slider_flushes_to_the_same_config_file() -> void:
	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var slider := screen.slider_for(&"Sfx")
	ok(slider != null, "Sfx slider exists")
	if slider != null:
		slider.value = 45.0
		await get_tree().process_frame
		almost(Settings.volume_percent(&"Sfx"), 45.0, 0.01, "slider reaches Settings live")
		screen.flush()
		var cfg := ConfigFile.new()
		eq(cfg.load(TEST_PATH), OK, "settings file stays readable")
		almost(float(cfg.get_value("audio", "Sfx", -1.0)), 45.0, 0.01,
				"slider value persisted in the audio section")
		eq(int(cfg.get_value("meta", "version", 0)), Settings.VERSION, "version unchanged")
	screen.queue_free()
	await get_tree().process_frame


## 键位页的两列网格必须装进 900px 花边卡的内容宽（832），不能在中文键名和
## 「恢复默认键位」同时在场时向两侧挤出卡片。
func test_settings_key_grid_fits_inside_the_card() -> void:
	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.show_tab(SettingsScreen.TAB_KEYS)
	await get_tree().process_frame
	var card := screen.get_node_or_null("ModalRoot/Card") as Control
	var grid := screen.find_child("KeyGrid", true, false) as GridContainer
	ok(card != null, "settings card exists")
	ok(grid != null, "key grid exists")
	if card != null and grid != null:
		var card_rect := card.get_global_rect()
		var body_width := card_rect.size.x - 68.0
		ok(grid.get_combined_minimum_size().x <= body_width,
				"key grid fits the card content width (%.0f <= %.0f)"
				% [grid.get_combined_minimum_size().x, body_width])
		var grid_rect := grid.get_global_rect()
		ok(card_rect.encloses(grid_rect),
				"key grid stays inside the ornate card (%s in %s)" % [grid_rect, card_rect])
		for action in Settings.REBINDABLE:
			var button := screen.key_button_for(action)
			if button != null:
				ok(card_rect.encloses(button.get_global_rect()),
						"%s row stays inside the card" % String(action))
	screen.queue_free()
	await get_tree().process_frame


## 键盘 / 手柄焦点：页内第一行 ↑ 回本页标签，页脚 ↑ 回当前页最后一行；
## 页尾 ↓ 到「返回」，键位页的「恢复默认」与「返回」用 ←→ 相连。
func test_settings_focus_chain_links_tabs_pages_and_footer() -> void:
	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.open()
	await get_tree().process_frame
	var first := screen.first_control()
	ok(first != null, "声音页有第一焦点")
	if first != null:
		ok(not first.focus_neighbor_top.is_empty(), "第一行有 ↑ 邻居")
		var tab := first.get_node_or_null(first.focus_neighbor_top)
		ok(tab is Button, "第一行 ↑ 回到标签")
		if tab is Button:
			eq((tab as Button).theme_type_variation, &"TabButton", "回到的是本页标签")
	var back := screen.back_button()
	ok(back != null, "页脚有返回按钮")
	if back != null:
		ok(not back.focus_neighbor_top.is_empty(), "返回按钮有 ↑ 邻居")
		var last := back.get_node_or_null(back.focus_neighbor_top)
		ok(last != null and last.is_visible_in_tree(), "返回 ↑ 回到当前页最后一行")
	screen.close()
	screen.queue_free()
	await get_tree().process_frame


## 切页后焦点必须落进新页：否则焦点还留在上一页已隐藏的控件上，整个页面
## 一个高亮都没有（鼠标点标签页 / 肩键换页 / 工具截图都会这样）。
func test_show_tab_moves_focus_into_the_new_page() -> void:
	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	for tab in [SettingsScreen.TAB_DISPLAY, SettingsScreen.TAB_KEYS, SettingsScreen.TAB_AUDIO]:
		screen.show_tab(tab)
		await get_tree().process_frame
		await get_tree().process_frame
		eq(screen.current_tab(), tab, "tab %d is current" % tab)
		var first := screen.first_control()
		ok(first != null, "tab %d has a first control" % tab)
		if first != null:
			ok(first.has_focus(), "focus lands on the first row of tab %d" % tab)
			ok(first.is_visible_in_tree(), "the focused row is visible (no focus on a hidden page)")
	# 鼠标悬停走的是同一个可见选中信号：悬停行拿焦点。
	screen.show_tab(SettingsScreen.TAB_AUDIO)
	await get_tree().process_frame
	var slider := screen.slider_for(&"Master")
	ok(slider != null, "master volume slider exists")
	if slider != null:
		slider.mouse_entered.emit()
		await get_tree().process_frame
		ok(slider.has_focus(), "hovering a settings row focuses it (gold row, same as keyboard)")
	screen.close()
	screen.queue_free()
	await get_tree().process_frame


## 改键后，设置页的键帽和操作说明的键位列都要立刻跟着换 —— 不经重开界面，
## 玩家不会看到"设置里写成 Q、操作说明还写着空格"的两套说法。
func test_rebinding_refreshes_every_key_label() -> void:
	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.show_tab(SettingsScreen.TAB_KEYS)
	await get_tree().process_frame
	await get_tree().process_frame
	var controls := ControlsPanel.new()
	add_child(controls)
	await get_tree().process_frame
	var old := Settings.key_for(&"jump")
	eq(screen.key_cap_text(&"jump"), KeyLabels.label(&"jump"),
			"settings key page starts on the bound key")
	eq(controls.key_text(1), KeyLabels.label(&"jump"),
			"controls panel starts on the bound key")
	Settings.rebind_action(&"jump", KEY_Q, false)
	await get_tree().process_frame
	eq(screen.key_cap_text(&"jump"), "Q", "settings key page refreshes live after a rebind")
	eq(controls.key_text(1), "Q", "controls panel refreshes live after a rebind")
	Settings.rebind_action(&"jump", old, false)
	await get_tree().process_frame
	eq(screen.key_cap_text(&"jump"), KeyLabels.label(&"jump"), "the restored binding is shown")
	screen.queue_free()
	controls.queue_free()
	await get_tree().process_frame
