extends TestCase
## First-time teaching must leave traversal and the parry follow-up playable.

var _flags_before: PackedStringArray
var _save_path_before: String
var _hints_before: bool
var _death_pending_before: bool


func setup() -> void:
	_flags_before = SaveData.flags.duplicate()
	_save_path_before = SaveData.save_path
	SaveData.save_path = "user://tutorial_handoff_%d.cfg" % Time.get_ticks_usec()
	SaveData.flags.clear()
	StoryStage.forget()
	Director.reset_view()
	Director.resume()
	Director.choice_hold = false
	_hints_before = HintService.enabled()
	_death_pending_before = HintService._death_pending
	HintService._death_pending = false
	Settings.set_value(HintService.SETTING_ENABLED, true)
	for action in [&"attack", &"jump", &"dash"]:
		Input.action_release(action)


func teardown() -> void:
	Director.reset_view()
	Director.resume()
	Director.choice_hold = false
	StoryStage.forget()
	SaveData.flags = _flags_before
	SaveData.save_path = _save_path_before
	Settings.set_value(HintService.SETTING_ENABLED, _hints_before)
	HintService._death_pending = _death_pending_before
	for action in [&"attack", &"jump", &"dash"]:
		Input.action_release(action)


func _rig() -> Dictionary:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.set_physics_process(false)
	player.melee.set_physics_process(false)
	player.toxin.set_process(false)
	player.resonance.set_process(false)
	var camera := GameCamera.new()
	arena.add_child(camera)
	camera.set_physics_process(false)
	camera.set_process(false)
	var beats := Level01StoryBeats.new()
	arena.add_child(beats)
	beats.bind(arena, player, null)
	SaveData.mark_flag("hint_peek")
	var hints := HintService.new()
	arena.add_child(hints)
	hints.set_process(false)
	return {"arena": arena, "player": player, "camera": camera, "hints": hints}


func test_first_toxin_keeps_camera_velocity_and_queued_escape_inputs() -> void:
	var rig := await _rig()
	var player: Player = rig.player
	var camera: GameCamera = rig.camera
	var hints: HintService = rig.hints
	player.velocity = Vector2(65.0, -120.0)
	player.controller._buffer = 0.10
	player.controller._dash_buffer = 0.08
	var zoom_before := camera.zoom
	player.toxin.expose(1.0)
	ok(SaveData.has_flag("toxin"), "legacy story flag is still recorded")
	ok(not Director.playing and not Director.is_input_locked(), "touching coolant starts no cinematic")
	ok(not player.cutscene_locked, "the player still owns movement")
	ok(not camera._focused, "the camera keeps following the player")
	eq(camera.zoom, zoom_before)
	eq(player.velocity, Vector2(65.0, -120.0), "no stop or knockback is introduced by teaching")
	almost(player.controller._buffer, 0.10, 0.0001, "jump buffer survives")
	almost(player.controller._dash_buffer, 0.08, 0.0001, "dash buffer survives")
	player.controller._dash_buffer = 0.0
	player.controller.physics_tick(player, 1.0 / 60.0, 1.0)
	ok(player.velocity.y < -200.0, "the buffered escape jump can fire immediately")
	hints._scan_state()
	hints._process(0.0)
	eq(hints.current_id(), &"toxin", "existing single-line teaching is used")
	player.toxin.expose(1.0)
	eq(SaveData.flags.count("toxin"), 1, "repeated exposure does not repeat the story")


func test_first_parry_preserves_active_swing_combo_and_resonance_reward() -> void:
	var rig := await _rig()
	var player: Player = rig.player
	var hints: HintService = rig.hints
	HintService.mark_seen(&"swing")
	var shooter := Node2D.new()
	rig.arena.add_child(shooter)
	const PROJECTILE := preload("res://scenes/combat/Projectile.tscn")
	var bolt: Projectile = PROJECTILE.instantiate()
	bolt.setup(Vector2(900.0, -300.0), Vector2.LEFT, 80.0, &"enemy", shooter)
	rig.arena.add_child(bolt)
	bolt.set_physics_process(false)
	player.toxin.toxin = 50.0
	ok(player.melee.start_swing())
	player.melee.tick(player.melee.windup_time + 0.001)
	ok(player.melee.is_parry_window())
	ok(player.melee.try_deflect(bolt), "the real parry path emits the first-time story event")
	ok(SaveData.has_flag("parry"), "legacy parry flag is preserved")
	ok(not Director.playing and not player.cutscene_locked, "no camera beat steals the follow-up")
	ok(player.melee.is_parry_window(), "teaching does not cancel the active sword")
	ok(player.resonance.is_active())
	almost(player.resonance.remaining(), CombatRules.PARRY_RESONANCE, 0.001)
	almost(player.toxin.toxin, 38.0, 0.001, "parry purification is unchanged")
	ok(player.melee.request_attack(), "the player can queue a follow-up on the parry frame")
	player.melee.tick(player.melee.active_time + 0.001)
	player.melee.tick(player.melee.recovery_time + 0.001)
	eq(player.melee.phase_name(), "windup", "the queued second slash starts")
	eq(player.melee._combo_index, 1)
	hints._process(0.0)
	eq(hints.current_id(), &"parry_reward")
	var found := false
	for entry in HintService.seen_entries():
		if entry.id == &"parry_reward":
			found = true
	ok(found, "the reward teaching can be recalled from the existing tutorial screen")


func test_parry_teaching_waits_for_busy_hint_slot_and_appears_once() -> void:
	var rig := await _rig()
	var hints: HintService = rig.hints
	ok(hints.offer(&"swing"))
	hints._process(0.0)
	ok(hints.offer(&"dash"), "one waiting slot is occupied")
	GameEvents.parried.emit(null, rig.player)
	eq(hints.current_id(), &"swing", "a reward never replaces a visible line")
	eq(hints.queued_id(), &"dash", "the bounded queue is retained")
	hints._process(HintService.HOLD + 0.01)
	hints._process(HintService.GAP + 0.01)
	eq(hints.current_id(), &"dash")
	hints._scan_state()
	eq(hints.queued_id(), &"parry_reward", "a busy first event is retried")
	hints._process(HintService.HOLD + 0.01)
	hints._process(HintService.GAP + 0.01)
	eq(hints.current_id(), &"parry_reward")
	hints.dismiss()
	GameEvents.parried.emit(null, rig.player)
	hints._scan_state()
	ok(hints.queued_id() != &"parry_reward", "seen teaching does not recur on every parry")
	ok(not Director.playing)


func test_legacy_story_flags_supply_nonblocking_teaching_after_reload() -> void:
	SaveData.mark_flag("toxin")
	SaveData.mark_flag("parry")
	var rig := await _rig()
	var hints: HintService = rig.hints
	hints._scan_state()
	hints._process(0.0)
	eq(hints.current_id(), &"parry_reward")
	hints.dismiss()
	hints._scan_state()
	hints._process(HintService.GAP + 0.01)
	eq(hints.current_id(), &"toxin", "coolant tip is not lost after the toxin drained away")
	ok(not Director.playing and not Director.is_input_locked())


func test_hints_off_and_death_never_leave_a_teaching_lock_or_waiting_line() -> void:
	var rig := await _rig()
	var hints: HintService = rig.hints
	Settings.set_value(HintService.SETTING_ENABLED, false)
	rig.player.toxin.expose(1.0)
	GameEvents.parried.emit(null, rig.player)
	hints._scan_state()
	hints._process(0.0)
	ok(not hints.is_showing())
	eq(hints.queued_id(), &"")
	ok(not Director.playing and not rig.player.cutscene_locked)
	Settings.set_value(HintService.SETTING_ENABLED, true)
	hints._scan_state()
	ok(hints.queued_id() != &"")
	GameEvents.player_died.emit()
	eq(hints.queued_id(), &"", "death clears pending teaching before a new HUD takes over")
	ok(not hints.is_showing())

