extends TestCase
## The 3D P0 has a standalone scene/session. Keep campaign routing, save bytes
## and progress untouched while exercising the real launcher through requests.

const Run := preload("res://scripts/moba/moba_run.gd")
const SAVE_PATH := "user://moba_mode_test_save.cfg"
const SAVE_FIELDS: Array[String] = [
	"data", "flags", "consumed", "lit_nests", "ending", "opening_pending",
	"pending_spawn", "entering_from_checkpoint", "checkpoint_notice_pending",
	"character_id", "extras", "ember_rank", "ember_xp", "attribute_points",
	"skill_1", "skill_2", "skin_id", "skin_rune",
]

var _original_save_path := ""
var _original_memory: Dictionary
var _original_pending := ""
var _original_clock: Dictionary
var _original_menu_hold := false
var _original_mouse_mode: int
var _owner: Node
var _requests: Array[Dictionary] = []


func setup() -> void:
	_original_save_path = SaveData.save_path
	_original_memory = _memory_snapshot()
	_original_pending = GameContext.pending_world_path
	_original_clock = WorldClock.snapshot()
	_original_menu_hold = WorldClock.menu_hold
	_original_mouse_mode = Input.mouse_mode
	Run.abandon()
	ArenaRun.abandon()
	TrialRun.abandon()
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	get_tree().paused = false
	WorldClock.menu_hold = false
	SaveData.save_path = SAVE_PATH
	_remove_files()
	_owner = Node.new()
	_owner.name = "MobaSceneOwner"
	add_child(_owner)
	_requests.clear()


func teardown() -> void:
	Run.abandon()
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	get_tree().paused = false
	_remove_files()
	for key in _original_memory:
		SaveData.set(key, _original_memory[key])
	SaveData.save_path = _original_save_path
	GameContext.pending_world_path = _original_pending
	WorldClock.apply_snapshot(_original_clock)
	WorldClock.menu_hold = _original_menu_hold
	Input.mouse_mode = _original_mouse_mode


func _request(path: String, duration: float) -> Error:
	_requests.append({"path": path, "duration": duration})
	return OK


func _memory_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for key in SAVE_FIELDS:
		var value: Variant = SaveData.get(key)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		elif value is PackedStringArray:
			value = value.duplicate()
		snapshot[key] = value
	return snapshot


func _disk_snapshot() -> Dictionary:
	var files: Dictionary = {}
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = SAVE_PATH + suffix
		var exists := FileAccess.file_exists(path)
		files[suffix] = {
			"exists": exists,
			"bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray(),
		}
	return files


func _remove_files() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_start_uses_standalone_3d_route_and_refuses_duplicate_requests() -> void:
	var atmosphere := WorldClock.snapshot()
	ok(ResourceLoader.exists(Run.SCENE), "the launcher targets an installed P0 scene")
	eq(GameContext.route_scene(Run.SCENE), Run.SCENE, "3D bypasses the presentation that disables 3D")
	ok(not GameContext.is_world_scene(Run.SCENE), "P0 is not a campaign checkpoint scene")
	ok(not GameContext.is_mode_scene(Run.SCENE), "P0 is not routed through the retired 2D mode viewport")
	ok(Run.start(_request), "standalone scene request starts the 3D session")
	eq(_requests.size(), 1, "one request owns the transition")
	if not _requests.is_empty():
		eq(_requests[0]["path"], Run.SCENE)
		ok(float(_requests[0]["duration"]) > 0.0)
	ok(Run.active())
	ok(not ArenaRun.active(), "starting P0 does not start the retired 2D match")
	ok(ArenaRun.blocks_campaign_save(), "the established campaign guard includes the 3D session")
	eq(GameContext.pending_world_path, _original_pending, "entering 3D preserves the campaign pending scene")
	ok(WorldClock.menu_hold, "P0 holds the campaign clock")
	WorldClock._process(10.0)
	eq(WorldClock.snapshot(), atmosphere, "the 3D clock hold does not alter campaign time/weather")
	ok(not Run.start(_request), "repeated confirm cannot start another scene request")
	eq(_requests.size(), 1)
	Run.attach(_owner)
	Run.detach(_owner)
	ok(not Run.active())
	ok(not ArenaRun.blocks_campaign_save())
	ok(not WorldClock.menu_hold, "leaving restores the previous unheld clock")


func test_direct_editor_attachment_has_owner_and_preserves_a_prior_clock_hold() -> void:
	WorldClock.menu_hold = true
	var atmosphere := WorldClock.snapshot()
	Run.attach(_owner)
	ok(Run.active(), "opening P0 directly also starts its save guard")
	ok(ArenaRun.blocks_campaign_save())
	var replacement := Node.new()
	add_child(replacement)
	Run.attach(replacement)
	Run.detach(_owner)
	ok(Run.active(), "a stale scene exit cannot detach its replacement")
	ok(ArenaRun.blocks_campaign_save())
	Run.detach(replacement)
	ok(not Run.active())
	ok(not ArenaRun.blocks_campaign_save())
	ok(WorldClock.menu_hold, "a pre-existing title hold survives P0 teardown")
	eq(WorldClock.snapshot(), atmosphere)


func test_scene_request_results_roll_back_failed_starts() -> void:
	for response in [OK, true, null, ERR_CANT_OPEN, false, "invalid"]:
		var callback := func(path: String, _duration: float) -> Variant:
			_requests.append({"path": path})
			return response
		var expected: bool = response == null or (response is bool and bool(response)) \
				or (response is int and int(response) == OK)
		eq(Run.start(callback), expected, "scene request result is handled without switching the runner: %s" % str(response))
		eq(Run.active(), expected, "failed requests leave no phantom session")
		eq(ArenaRun.blocks_campaign_save(), expected, "failed requests do not strand the campaign write lock")
		eq(WorldClock.menu_hold, expected, "failed requests restore the original clock hold")
		Run.abandon()
		eq(GameContext.pending_world_path, _original_pending)
	eq(_requests.size(), 6, "each independent attempt reaches the injected scene requester once")


func test_exit_releases_input_once_and_keeps_save_lock_until_detach() -> void:
	ok(Run.start(_request))
	Run.attach(_owner)
	get_tree().paused = true
	Director.suspend()
	Director.choice_hold = true
	ok(Run.exit_to_title(_request))
	eq(_requests.size(), 2, "exit requests exactly one title transition")
	if _requests.size() > 1:
		eq(_requests[1]["path"], Run.TITLE_SCENE)
	ok(not get_tree().paused, "title cannot inherit a paused scene tree")
	ok(not Director.is_suspended())
	ok(not Director.choice_hold)
	eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
	ok(Run.active(), "scene is still active during the outgoing transition")
	ok(ArenaRun.blocks_campaign_save(), "save writes stay blocked until the 3D owner actually exits")
	ok(not Run.exit_to_title(_request), "repeat Esc during the outro is idempotent")
	eq(_requests.size(), 2)
	Run.detach(_owner)
	ok(not Run.active())
	ok(not ArenaRun.blocks_campaign_save())
	ok(not WorldClock.menu_hold)


func test_failed_exit_stays_guarded_and_can_be_retried() -> void:
	Run.attach(_owner)
	var failed := func(path: String, _duration: float) -> Error:
		_requests.append({"path": path})
		return ERR_CANT_OPEN
	ok(not Run.exit_to_title(failed))
	ok(Run.active(), "failed title transition keeps the still-mounted P0 session")
	ok(ArenaRun.blocks_campaign_save())
	ok(WorldClock.menu_hold)
	ok(Run.exit_to_title(_request), "a later Esc may retry a failed transition")
	eq(_requests.size(), 2)
	Run.detach(_owner)
	ok(not ArenaRun.blocks_campaign_save())


func test_campaign_bytes_and_memory_are_read_only_until_the_3d_owner_exits() -> void:
	SaveData.flags = PackedStringArray(["campaign_flag"])
	SaveData.consumed = PackedStringArray(["Props/CampaignPickup"])
	SaveData.lit_nests = PackedStringArray(["Props/CampaignNest"])
	SaveData.ending = "keep"
	SaveData.pending_spawn = Vector2(123, 45)
	SaveData.entering_from_checkpoint = true
	SaveData.extras = {"saved_stage": "campaign_stage", "sentinel": [1, 2, 3]}
	SaveData.data = {"sentinel": {"keep": true}, "profile": SaveData.profile_snapshot()}
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SaveData.SAVE_VERSION)
	cfg.set_value("meta", "scene", GameContext.WORLD_PATH)
	cfg.set_value("player", "hp", 3)
	cfg.set_value("player", "max_hp", 5)
	cfg.set_value("player", "pos_x", 123.0)
	cfg.set_value("player", "pos_y", 45.0)
	cfg.set_value("story", "opening_pending", false)
	cfg.set_value("profile", "character_id", "campaign_character")
	eq(cfg.save(SAVE_PATH), OK, "fixture is a valid existing campaign save")
	var backup := FileAccess.open(SAVE_PATH + ".bak", FileAccess.WRITE)
	backup.store_string("campaign backup sentinel\n")
	backup.close()
	var before_disk := _disk_snapshot()
	var before_memory := _memory_snapshot()
	var dummy := Node2D.new()
	add_child(dummy)
	ok(Run.start(_request))
	Run.attach(_owner)
	eq(SaveData.save_game(Run.SCENE, dummy), false)
	eq(SaveData.load_game(), false)
	eq(SaveData.persist_progress(dummy), false)
	eq(SaveData.persist_profile(), false)
	eq(SaveData.save_equipment(dummy), false)
	SaveData.persist_story(dummy)
	SaveData.mark_flag("moba_leak")
	SaveData.mark_consumed("Props/MobaLeak")
	SaveData.register_lit_nest("Props/MobaNest")
	SaveData.delete_save()
	eq(_disk_snapshot(), before_disk, "save, backup and temporary-file state remain byte-for-byte identical")
	eq(_memory_snapshot(), before_memory, "flags, pickup history, spawn and profile memory remain unchanged")
	ok(Run.exit_to_title(_request))
	SaveData.mark_flag("outro_leak")
	eq(_memory_snapshot(), before_memory, "the title transition does not release the guard early")
	eq(SaveData.persist_profile(), false)
	eq(_disk_snapshot(), before_disk)
	Run.detach(_owner)
	ok(not ArenaRun.blocks_campaign_save())
	SaveData.mark_flag("campaign_after_3d")
	ok(SaveData.flags.has("campaign_after_3d"), "campaign progress can change again after the owner exits")
	SaveData.character_id = "campaign_after_3d"
	ok(SaveData.persist_profile(), "campaign disk writes recover in the same process")
	ok(_disk_snapshot() != before_disk, "successful profile persistence really changes the dedicated save")
