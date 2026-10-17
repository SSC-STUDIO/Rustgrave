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
