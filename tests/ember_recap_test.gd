extends TestCase
const Recap := preload("res://scripts/ui/ember_recap.gd")
const Catalog := preload("res://scripts/data/trial_catalog.gd")
var _flags: PackedStringArray
var _ending: String
var _path: String


func setup() -> void:
	_flags = SaveData.flags.duplicate()
	_ending = SaveData.ending
	_path = SaveData.save_path
	SaveData.save_path = "user://recap_test_save.cfg"
	SaveData.flags = PackedStringArray(["boss_dead", "hollow_bell_dead", "nightmare_dead", "trial_unlocked"])
	SaveData.ending = "give"
	TrialRun.set_scene_requester(func(_scene: String) -> void: pass)
	Director.abort()
	Director.resume()


func teardown() -> void:
	TrialRun.abandon()
	TrialRun.clear_scene_requester()
	SaveData.flags = _flags
	SaveData.ending = _ending
	SaveData.save_path = _path
	if FileAccess.file_exists("user://recap_test_save.cfg"):
		DirAccess.remove_absolute("user://recap_test_save.cfg")
	Director.abort()


func test_summary_and_selected_rematch_preserve_campaign_state() -> void:
	var recap := Recap.new()
	add_child(recap)
	recap.open(false)
	ok(recap.visible)
	ok("章节" in recap.summary_text())
	ok("试炼" in recap.summary_text())
	ok("竞技场" in recap.summary_text())
	var before := SaveData.flags.duplicate()
	var cfg := ConfigFile.new()
	cfg.set_value("story", "ending", "give")
	cfg.set_value("story", "flags", Array(before))
	cfg.set_value("sentinel", "foreign_v2_data", {"keep": 17})
	cfg.save(SaveData.save_path)
	var bytes_before := FileAccess.get_file_as_bytes(SaveData.save_path)
	ok(recap.start_selected_rematch(), "summary enters the selected Boss practice")
	eq(TrialRun.stage_count(), 1, "one selected Boss, not the full rush or survival arena")
	eq(TrialRun.stage()["boss_kind"], "executioner")
	ok(TrialRun.blocks_campaign_save())
	ok(not SaveData.has_flag("boss_dead"), "current Boss is temporarily rebuilt")
	ok(SaveData.flags.has("boss_dead"), "underlying campaign flag stays intact")
	SaveData.mark_flag("practice_leak")
	SaveData.persist_story()
	eq(SaveData.flags, before)
	eq(FileAccess.get_file_as_bytes(SaveData.save_path), bytes_before, "existing campaign bytes remain unchanged")
	TrialRun.abandon()
	ok(SaveData.has_flag("boss_dead"), "ending practice restores campaign reads")


func test_selected_boss_scene_really_rebuilds_after_campaign_kills() -> void:
	SaveData.flags = PackedStringArray(["boss_dead", "hollow_bell_dead", "capstan_dead", "choir_dead", "founder_dead", "herald_dead", "nightmare_dead", "trial_unlocked"])
	var available := Catalog.available_bosses()
	for row in available:
		ok(TrialRun.start(Catalog.Track.BOSS_RUSH, String(row["kind"])))
		var world := load(GameContext.LEVELS[row["level_id"]]).instantiate() as Node2D
		add_child(world)
		await flush(3)
		await get_tree().process_frame
		await get_tree().process_frame
		var probe := load(row["scene"]).instantiate() as Node
		var script := probe.get_script() as GDScript
		probe.free()
		var count := 0
		for enemy in world.find_children("*", "EnemyBase", true, false):
			if enemy.get_script() == script:
				count += 1
		eq(count, 1, "%s: cleared campaign builds the real selected Boss" % row["kind"])
		var player := get_tree().get_first_node_in_group("player") as Player
		ok(player != null)
		if player != null:
			almost(player.global_position.x, Catalog.boss_spawn(row).x, 24.0)
		world.queue_free()
		await flush(2)
		TrialRun.abandon()


func test_individual_rematch_uses_current_chapter_and_safe_arena_entry() -> void:
	SaveData.flags = PackedStringArray(["boss_dead", "hollow_bell_dead", "capstan_dead", "choir_dead", "founder_dead", "herald_dead", "nightmare_dead", "trial_unlocked"])
	var expected := {"capstan_warden": "level02b", "silent_choir": "level04b", "hollow_bell": "level02"}
	for row in Catalog.available_bosses():
		var stages := Catalog.stages_for(Catalog.Track.BOSS_RUSH, String(row["kind"]))
		eq(stages.size(), 1)
		if expected.has(row["kind"]):
			eq(stages[0]["level_id"], expected[row["kind"]])
		ok((stages[0]["spawn"] as Vector2).x > 1800.0, "practice starts in the current arena")

