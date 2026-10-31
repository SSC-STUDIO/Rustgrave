extends TestCase
## Saved identity -> opening -> first control. These exercise the real scene and
## delayed modal completion, not just the individual menu/saving helpers.

const Opening := preload("res://scripts/levels/opening_cinematic.gd")
const SaveScript := preload("res://scripts/autoload/save_data.gd")
const TEST_SAVE := "user://rustgrave_new_game_handoff_test.cfg"

class RefusingSave extends "res://scripts/autoload/save_data.gd":
	var attempted_profiles: Array[Dictionary] = []
	func _write_cfg(cfg: ConfigFile) -> bool:
		attempted_profiles.append({
			"skin_id": String(cfg.get_value("profile", "skin_id", "")),
			"skin_rune": String(cfg.get_value("profile", "skin_rune", "")),
		})
		return false

class RecordingSave extends "res://scripts/autoload/save_data.gd":
	var written_profiles: Array[Dictionary] = []
	func _write_cfg(cfg: ConfigFile) -> bool:
		written_profiles.append({
			"skin_id": String(cfg.get_value("profile", "skin_id", "")),
			"skin_rune": String(cfg.get_value("profile", "skin_rune", "")),
		})
		return super._write_cfg(cfg)

class RefusingTitle extends "res://scripts/ui/title_screen.gd":
	func _initialize_new_game(_origin_id: StringName, _loadout: Dictionary) -> bool:
		return false

var _old_path := ""

func setup() -> void:
	_old_path = SaveData.save_path
	SaveData.save_path = TEST_SAVE
	SaveData.delete_save()
	Director.abort()
	Director.resume()
	Director.hide_hint()
	Director.choice_hold = false
	Opening.reset()
	StoryStage.forget()
	get_tree().paused = false

func teardown() -> void:
	Director.abort()
	Director.resume()
	Director.hide_hint()
	Director.choice_hold = false
	Opening.reset()
	StoryStage.forget()
	SaveData.delete_save()
	SaveData.save_path = _old_path
	get_tree().paused = false

func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	eq(cfg.load(TEST_SAVE), OK, "saved file can be read")
	return cfg

func _accept() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	Director._unhandled_input(event)

func _forget_session() -> void:
	SaveData.data.clear()
	SaveData.flags.clear()
	SaveData.opening_pending = false
	Opening.reset()
	StoryStage.forget()

func _legacy_cfg() -> ConfigFile:
	ok(SaveData.init_new_game(&"ember_vanguard"))
	var cfg := _cfg()
	cfg.erase_section_key("story", "opening_pending")
	cfg.set_value("player", "pos_x", 0.0)
	cfg.set_value("player", "pos_y", 0.0)
	return cfg

func test_all_identities_start_at_authored_spawn_and_keep_loadout() -> void:
	eq(SaveScript.NEW_GAME_SPAWN, Level01Static.DEFAULT_SPAWN,
			"initializer agrees with the authored level foot point")
	var recording := RecordingSave.new()
	recording.save_path = TEST_SAVE
	for origin in OriginCatalog.get_all_origins():
		var skin := SkinCatalog.default_for_origin(origin.id)
		var rune := &"rune_ember_grip"
		var loadout := {"weapon": origin.default_weapon, "armor": origin.default_armor,
				"trinket": &"bone_amulet", "bag": [&"broken_sword"], "skin": skin, "rune": rune}
		var writes_before := recording.written_profiles.size()
		ok(recording.init_new_game(origin.id, loadout), "new identity was saved")
		eq(recording.written_profiles.size(), writes_before + 1,
				"identity, gear and appearance are committed by one write")
		eq(recording.written_profiles.back(), {"skin_id": String(skin), "skin_rune": String(rune)},
				"the first write already contains the selected appearance")
		var cfg := _cfg()
		eq(Vector2(cfg.get_value("player", "pos_x"), cfg.get_value("player", "pos_y")),
				Level01Static.DEFAULT_SPAWN, "fresh save never starts at world zero")
		ok(bool(cfg.get_value("story", "opening_pending", false)))
		eq(String(cfg.get_value("player", "origin")), String(origin.id))
		eq(String(cfg.get_value("equipment", "weapon")), String(origin.default_weapon))
		eq(String(cfg.get_value("equipment", "armor")), String(origin.default_armor))
		eq(String(cfg.get_value("equipment", "trinket")), "bone_amulet")
		eq(cfg.get_value("equipment", "bag"), ["broken_sword"])
		eq(String(cfg.get_value("profile", "skin_id")), String(skin))
		eq(String(cfg.get_value("profile", "skin_rune")), String(rune))
		eq(recording.skin_id, String(skin), "successful write updates the live skin")
		eq(recording.skin_rune, String(rune), "successful write updates the live rune")
		ok(SaveData.load_game(), "the committed identity can be restored")
		eq(SaveData.skin_id, String(skin))
		eq(SaveData.skin_rune, String(rune))
		ok(Opening.should_play(), "a saved selection still receives its opening")
	recording.free()

func test_real_first_level_restores_safe_spawn_and_skip_survives_continue() -> void:
	var origin := OriginCatalog.rust_automaton()
	ok(SaveData.init_new_game(origin.id, {"weapon": origin.default_weapon,
			"armor": origin.default_armor, "trinket": &"toxic_filter_talisman"}))
	var level := (load(GameContext.WORLD_PATH) as PackedScene).instantiate() as StageLevel
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var player := level._player
	almost(player.global_position.x, Level01Static.DEFAULT_SPAWN.x, 0.01)
	almost(player.global_position.y, Level01Static.DEFAULT_SPAWN.y, 0.5)
	eq(player.stats.get_origin_id(), origin.id, "actual player retains selected identity")
	ok(Opening.is_active(), "real level starts opening after loading selected identity")
	ok(player.cutscene_locked)
	_accept()
	ok(not Opening.is_active())
	ok(not Director.is_input_locked(), "skip returns gameplay input")
	ok(not player.cutscene_locked)
	level.queue_free()
	await get_tree().process_frame
	_forget_session()
	ok(SaveData.load_game())
	ok(SaveData.has_flag(Opening.FLAG), "skip completion was flushed before the first nest")
	ok(SaveData.has_flag(Opening.WAKE_FLAG))
	ok(not SaveData.opening_pending)
	ok(not Opening.should_play(), "Continue does not repeat the opening")
	SaveData.entering_from_checkpoint = true
	SaveData.pending_spawn = Level01Static.DEFAULT_SPAWN
	ok(not Opening.should_play(), "checkpoint respawn does not repeat it either")

func test_saved_identity_natural_completion_is_persisted() -> void:
	ok(SaveData.init_new_game(&"scrap_scavenger"))
	ok(Opening.try_start())
	ok(await wait_until(func() -> bool: return not Director.playing, 1500),
			"the existing beat sheet reaches its natural handoff")
	_forget_session()
	ok(SaveData.load_game())
	ok(SaveData.has_flag(Opening.FLAG))
	ok(SaveData.has_flag(Opening.WAKE_FLAG))
	ok(not SaveData.opening_pending)
	ok(not Opening.should_play())
	eq(SaveData.ending, "", "opening never manufactures an ending")

func test_aborted_saved_opening_remains_pending_after_reload() -> void:
	ok(SaveData.init_new_game())
	ok(Opening.try_start())
	Director.abort()
	ok(not Opening.is_active())
	ok(not Director.is_input_locked())
	_forget_session()
	ok(SaveData.load_game())
	ok(SaveData.opening_pending)
	ok(not SaveData.has_flag(Opening.FLAG))
	ok(Opening.should_play(), "an interrupted introduction is retryable")
	ok(Opening.try_start())
	_accept()
	ok(not Director.is_input_locked())

func test_only_pristine_legacy_zero_spawn_is_repaired() -> void:
	var cfg := _legacy_cfg()
	eq(cfg.save(TEST_SAVE), OK)
	_forget_session()
	ok(SaveData.load_game())
	eq(SaveData.data["player"]["pos"], Level01Static.DEFAULT_SPAWN)
	ok(SaveData.opening_pending)
	ok(Opening.should_play())
	var repaired := _cfg()
	eq(float(repaired.get_value("player", "pos_x")), Level01Static.DEFAULT_SPAWN.x)
	eq(float(repaired.get_value("player", "pos_y")), Level01Static.DEFAULT_SPAWN.y)
	ok(bool(repaired.get_value("story", "opening_pending", false)), "repair persists once")

func test_legacy_repair_never_rewinds_progress_or_an_explicit_continue() -> void:
	var progressed := [
		["story", "flags", ["wake"]], ["consumed", "paths", ["Props/Core"]],
		["lit_nests", "paths", ["Props/EmberNest"]], ["meta", "ending", "give"],
		["world", "Props/Door", {"open": true}], ["player", "pouch", ["ember"]],
		["player", "sockets", ["ember"]], ["equipment", "bag", ["broken_sword"]],
		["player", "hp", 1], ["player", "toxin", 25.0],
		["story", "opening_pending", false], ["player", "pos_x", 128.0],
	]
	for change in progressed:
		var cfg := _legacy_cfg()
		cfg.set_value(change[0], change[1], change[2])
		eq(cfg.save(TEST_SAVE), OK)
		_forget_session()
		ok(SaveData.load_game())
		var expected := Vector2(128, 0) if change[1] == "pos_x" else Vector2.ZERO
		eq(SaveData.data["player"]["pos"], expected, "leave progressed coordinates alone")
		ok(not SaveData.opening_pending, "do not replay opening for an ambiguous old save")

func test_failed_initializer_preserves_previous_disk_session_and_clock() -> void:
	ok(SaveData.init_new_game(&"ember_vanguard", {
		"skin": &"skin_ash_runner", "rune": &"rune_toxin_filter"}))
	var before_bytes := FileAccess.get_file_as_bytes(TEST_SAVE)
	var refusing := RefusingSave.new()
	add_child(refusing)
	refusing.save_path = TEST_SAVE
	refusing.data = SaveData.data.duplicate(true)
	refusing.skin_id = SaveData.skin_id
	refusing.skin_rune = SaveData.skin_rune
	refusing.flags = PackedStringArray(["wake", "boss_dead"])
	refusing.consumed = PackedStringArray(["Props/Remnant"])
	refusing.lit_nests = PackedStringArray(["Props/EmberNest"])
	refusing.ending = "give"
	refusing.opening_pending = false
	refusing.pending_spawn = Vector2(640, 320)
	refusing.entering_from_checkpoint = true
	WorldClock.set_time(0.8)
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	var before_data: Dictionary = refusing.data.duplicate(true)
	var before_clock := WorldClock.snapshot()
	ok(not refusing.init_new_game(&"rust_automaton", {
		"skin": &"skin_cemetery_hero", "rune": &"rune_unbroken"}), "failure is reported to the caller")
	eq(refusing.attempted_profiles, [{"skin_id": "skin_cemetery_hero", "skin_rune": "rune_unbroken"}],
			"the failed atomic write included the replacement appearance")
	eq(FileAccess.get_file_as_bytes(TEST_SAVE), before_bytes, "old save remains byte for byte")
	eq(refusing.data, before_data, "old character and equipment remain live")
	eq(refusing.skin_id, "skin_ash_runner", "failed write keeps the previous live skin")
	eq(refusing.skin_rune, "rune_toxin_filter", "failed write keeps the previous live rune")
	eq(refusing.flags, PackedStringArray(["wake", "boss_dead"]))
	eq(refusing.consumed, PackedStringArray(["Props/Remnant"]))
	eq(refusing.lit_nests, PackedStringArray(["Props/EmberNest"]))
	eq(refusing.ending, "give")
	ok(not refusing.opening_pending)
	eq(refusing.pending_spawn, Vector2(640, 320))
	ok(refusing.entering_from_checkpoint)
	eq(WorldClock.snapshot(), before_clock, "new-game failure does not reset atmosphere")
	refusing.queue_free()
	await get_tree().process_frame

func test_delayed_embark_is_one_outcome_after_outro_with_frozen_payload() -> void:
	var screen := CharacterSelectScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.select_origin(&"scrap_scavenger")
	screen.select_trinket(&"bone_amulet")
	var completions: Array[Callable] = []
	screen._shell["play_outro"] = func(done: Callable) -> void: completions.append(done)
	var results: Array = []
	var cancellations: Array = []
	screen.embark_requested.connect(func(origin: StringName, gear: Dictionary) -> void:
		results.append({"origin": origin, "gear": gear}))
	screen.cancelled.connect(func() -> void: cancellations.append(true))
	screen.open()
	screen.embark()
	screen.embark()
	screen.cancel()
	screen.select_origin(&"rust_automaton")
	screen.select_trinket(&"broken_pendant")
	eq(completions.size(), 1, "repeat input cannot queue another outro")
	eq(results.size(), 0, "no scene handoff while the old veil still covers the screen")
	ok(screen._embark_btn.disabled and screen._cancel_btn.disabled)
	for button in screen._origin_buttons + screen._trinket_buttons:
		ok(button.disabled, "mouse actions are disabled during outro")
	if completions.size() == 1:
		completions[0].call()
		completions[0].call()
	eq(results.size(), 1, "outro completion emits one result even if repeated")
	eq(cancellations.size(), 0)
	if results.size() == 1:
		eq(results[0]["origin"], &"scrap_scavenger")
		eq(results[0]["gear"]["trinket"], &"bone_amulet")
	ok(not screen.is_open())
	screen.queue_free()
	await get_tree().process_frame

func test_delayed_cancel_waits_for_outro_and_blocks_late_embark() -> void:
	var screen := CharacterSelectScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var completions: Array[Callable] = []
	screen._shell["play_outro"] = func(done: Callable) -> void: completions.append(done)
	var outcomes: Array[String] = []
	screen.cancelled.connect(func() -> void: outcomes.append("cancel"))
	screen.embark_requested.connect(func(_origin: StringName, _gear: Dictionary) -> void:
		outcomes.append("embark"))
	screen.open()
	screen.cancel()
	screen.cancel()
	screen.embark()
	eq(outcomes.size(), 0)
	eq(completions.size(), 1)
	if completions.size() == 1:
		completions[0].call()
		completions[0].call()
	eq(outcomes, ["cancel"])
	screen.open()
	ok(not screen._embark_btn.disabled, "a fresh opening restores usable controls")
	ok(not screen._cancel_btn.disabled)
	screen.cancel()
	eq(completions.size(), 2)
	if completions.size() == 2:
		completions[0].call()
		ok(screen.is_open() and screen._closing, "late old callback cannot complete a new outro")
		eq(outcomes, ["cancel"])
		completions[1].call()
	eq(outcomes, ["cancel", "cancel"], "the new outro keeps its own outcome")
	screen.queue_free()
	await get_tree().process_frame

func test_title_failure_returns_to_selection_and_success_is_idempotent() -> void:
	ok(SaveData.init_new_game(&"ember_vanguard"))
	var old_bytes := FileAccess.get_file_as_bytes(TEST_SAVE)
	var refusing := RefusingTitle.new()
	add_child(refusing)
	await get_tree().process_frame
	refusing._on_char_select_embark(&"rust_automaton", {})
	ok(not refusing._started)
	ok(refusing.character_select_screen().is_open(), "failed save returns to a usable selection")
	ok(not (refusing.get_node("Menu") as MenuList).active)
	var hint := refusing.character_select_screen()._shell["hint"] as Label
	ok(hint.text.contains("保存失败"))
	eq(FileAccess.get_file_as_bytes(TEST_SAVE), old_bytes)
	refusing.character_select_screen().cancel()
	ok((refusing.get_node("Menu") as MenuList).active, "cancel remains available after failure")
	refusing.queue_free()
	await get_tree().process_frame
	var title := TitleScreen.new()
	add_child(title)
	await get_tree().process_frame
	var saves: Array[bool] = []
	var on_save := func() -> void: saves.append(true)
	GameEvents.game_saved.connect(on_save)
	title._on_char_select_embark(&"scrap_scavenger", {})
	title._on_char_select_embark(&"rust_automaton", {})
	title._start(true)
	title._on_char_select_cancelled()
	title._on_confirm_chosen(TitleScreen.ID_OVERWRITE)
	GameEvents.game_saved.disconnect(on_save)
	eq(saves.size(), 1, "only one save/fade may be started from a title")
	eq(SaveData.get_current_origin(), &"scrap_scavenger")
	ok(title._started)
	ok(not title.character_select_screen().is_open(), "late overwrite cannot reopen selection")
	ok(not (title.get_node("Menu") as MenuList).active)
	title.queue_free()
	await get_tree().process_frame

func test_real_level_reload_heals_checkpoint_but_preserves_wounded_continue() -> void:
	for level_id in ["stage01", "stage03"]:
		var path: String = GameContext.LEVELS[level_id]
		var spawn := Level01Static.DEFAULT_SPAWN
		if level_id != "stage01":
			var layout := (load(GameContext.STAGE_SCRIPTS[level_id]) as GDScript).new() as StageRoomBuilder
			spawn = layout.spawn_for_room(layout.default_room(), "west")
			layout.free()
		for origin in OriginCatalog.get_all_origins():
			ok(SaveData.init_new_game(origin.id, {"weapon": origin.default_weapon,
					"armor": origin.default_armor, "trinket": &"bone_amulet"}))
			var cfg := _cfg()
			cfg.set_value("meta", "scene", path)
			cfg.set_value("player", "pos_x", spawn.x)
			cfg.set_value("player", "pos_y", spawn.y)
			cfg.set_value("player", "hp", 1)
			cfg.set_value("player", "toxin", 50.0)
			# This fixture tests arrival replay, so its existing toxin is already familiar.
			# Otherwise the first nonzero toxin tick starts the separate toxin tutorial.
			cfg.set_value("story", "flags", ["wake", "opening_seen", "stage01_wake", "stage03_wake", "toxin"])
			cfg.set_value("story", "opening_pending", false)
			eq(cfg.save(TEST_SAVE), OK)
			SaveData.pending_spawn = spawn + Vector2(12, 0)
			SaveData.entering_from_checkpoint = true
			var checkpoint := (load(path) as PackedScene).instantiate()
			add_child(checkpoint)
			var returned: Player = checkpoint._player
			eq(returned.health.current, returned.health.max_hp,
					"real %s checkpoint fully heals %s" % [level_id, origin.id])
			almost(returned.toxin.toxin, 0.0, 0.001, "checkpoint clears saved toxin")
			eq(returned.global_position, spawn + Vector2(12, 0), "pending nest spawn wins")
			eq(returned.stats.get_origin_id(), origin.id)
			await get_tree().process_frame
			ok(not Director.is_input_locked(), "checkpoint does not replay arrival")
			checkpoint.queue_free()
			await get_tree().process_frame
			Director.abort()
			SaveData.pending_spawn = Vector2.INF
			SaveData.entering_from_checkpoint = false
			var continued := (load(path) as PackedScene).instantiate()
			add_child(continued)
			var wounded: Player = continued._player
			eq(wounded.health.current, 1, "ordinary %s Continue retains saved wounds" % level_id)
			almost(wounded.toxin.toxin, 50.0, 0.001, "ordinary Continue retains saved toxin")
			eq(wounded.global_position, spawn, "ordinary Continue keeps saved position")
			eq(wounded.stats.get_origin_id(), origin.id)
			await get_tree().process_frame
			ok(not Director.is_input_locked(), "ordinary Continue does not replay arrival")
			continued.queue_free()
			await get_tree().process_frame
			Director.abort()
