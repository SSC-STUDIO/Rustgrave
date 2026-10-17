extends TestCase
## 过场锁：满溢不伤、毒池停灌、敌人停手、fade_to 掐剧本。


func setup() -> void:
	Director.abort()
	Director.resume()
	Director.choice_hold = false


func teardown() -> void:
	Director.abort()
	Director.resume()


func test_overflow_does_not_damage_while_cutscene_locked() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var hp := player.health.current
	player.cutscene_locked = true
	player._on_toxin_overflow()
	eq(player.health.current, hp, "locked knight is not overflow-chipped")
	player.cutscene_locked = false
	player._on_toxin_overflow()
	eq(player.health.current, hp - 1, "overflow resumes after unlock")


func test_toxin_pool_stops_expose_while_director_locked() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var pool := ToxinPool.new()
	pool.position = player.global_position + Vector2(-56, -8)
	arena.add_child(pool)
	pool._bodies.append(player)
	player.toxin.toxin = 10.0
	Director.play([{"kind": "lock"}, {"kind": "wait", "seconds": 8.0}])
	ok(Director.is_input_locked())
	pool._physics_process(1.0)
	almost(player.toxin.toxin, 10.0, 0.01, "pool does not fill during lock")
	Director.abort()
	ok(not Director.is_input_locked())
	pool._physics_process(1.0)
	ok(player.toxin.toxin > 10.0, "pool resumes after unlock")


func test_gear_shield_freezes_ai_while_locked() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	const SCENE := preload("res://scenes/enemies/GearShieldEnemy.tscn")
	var guard := SCENE.instantiate() as GearShieldEnemy
	guard.position = player.global_position + Vector2(40, 0)
	arena.add_child(guard)
	await flush(2)
	guard._state = guard.State.BLOCK
	guard._shoot_timer = 0.05
	Director.play([{"kind": "lock"}, {"kind": "wait", "seconds": 8.0}])
	await flush(10)
	eq(guard._state, guard.State.BLOCK, "cutscene freeze keeps the guard from charging")
	almost(guard._shoot_timer, 0.05, 0.02, "shoot clock does not advance")
	Director.abort()


func test_death_aborts_cutscene_lock() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	Director.play([{"kind": "lock"}, {"kind": "wait", "seconds": 8.0}])
	ok(Director.is_input_locked())
	ok(player.cutscene_locked)
	player._on_died()
	await flush(2)
	ok(not Director.playing, "death abort()s the live script")
	ok(not Director.is_input_locked(), "Director lock dies with the knight")
	ok(not player.cutscene_locked, "player lock is cleared")


func test_fade_to_aborts_playing_cutscene() -> void:
	Director.play([
		{"kind": "lock"},
		{"kind": "wait", "seconds": 8.0},
		{"kind": "unlock"},
	])
	ok(Director.playing)
	ok(Director.is_input_locked())
	Director.fade_to("res://scenes/ui/TitleScreen.tscn")
	ok(not Director.playing, "fade_to abort()s the live script")
	ok(not Director.is_input_locked(), "lock does not survive the fade")
	var done := await wait_until(func() -> bool: return not Director.is_fading(), 120)
	ok(done, "fade still completes")


## A forced/once cinematic must not replay after a pause, a suspend, a death, or a
## save-load round-trip. The opening keys off opening_seen (set on finish/skip, never
## on abort); StoryStage.once() keys off a persisted flag, so a re-bind after a
## round-trip still cannot re-fire an already-told beat.
func test_forced_cutscene_does_not_replay_after_interruptions() -> void:
	var Opening := preload("res://scripts/levels/opening_cinematic.gd")

	# Pause-then-abort mid-piece: the seen flag must stay unset, and the next clean
	# new game is the only thing allowed to play it again.
	Director.play([{"kind": "lock"}, {"kind": "caption", "text": "剑先锈了。里面还有人。", "hold": 8.0}, {"kind": "unlock"}])
	ok(Director.playing)
	get_tree().paused = true
	await get_tree().process_frame
	Director.abort()
	get_tree().paused = false
	ok(not SaveData.has_flag(Opening.FLAG), "abort never marks the opening seen")
	ok(Opening.should_play(), "a clean save may still play it once")

	# Skip marks it seen; a second try_start (re-entering the level, loading a save)
	# must not replay — the flag is persisted, not session-scoped.
	SaveData.mark_flag(Opening.FLAG)
	ok(not Opening.should_play(), "a seen opening never replays, even from a fresh bind")
	SaveData.flags.erase(Opening.FLAG)

	# StoryStage.once() blocks a second fire of the same event: the persisted flag is
	# the real guard, so a re-bind after a save-load round-trip cannot re-fire a beat.
	ok(StoryStage.once("boss_intro"), "first intro fire is allowed")
	ok(not StoryStage.once("boss_intro"), "the same beat cannot fire twice in one session")
	ok(SaveData.has_flag("boss_intro"), "once() persists the guard flag")
	# forget() clears session memory only; the persisted flag still blocks the replay
	# (a new game wipes SaveData, which is what actually re-arms the beat).
	StoryStage.forget()
	ok(not StoryStage.once("boss_intro"), "the persisted flag still blocks after forget()")
	SaveData.flags.erase("boss_intro")
	ok(StoryStage.once("boss_intro"), "clearing the flag (a new game) re-arms the beat")
	SaveData.flags.erase("boss_intro")


## The three boss beats are all Director scripts with the same lock/unlock and skip
## contract, and each one actually stages the event it is named for: intro pushes in,
## phase relies on the boss's own announcement instead of repeating it, defeat hands
## the lens to the next door.
func test_boss_beats_stage_intro_phase_and_defeat_with_one_contract() -> void:
	var boss := Node2D.new()
	boss.position = Vector2(300, -40)
	add_child(boss)
	var door := Node2D.new()
	door.position = Vector2(420, -40)
	add_child(door)

	var intro := StoryStage.boss_intro_steps(boss)
	eq(String(intro[0].get("kind", "")), "lock", "intro takes the input")
	eq(String(intro[intro.size() - 1].get("kind", "")), "unlock", "intro gives it back")
	var intro_focus := 0
	for step in intro:
		if String(step.get("kind", "")) == "cam_focus":
			intro_focus += 1
	ok(intro_focus >= 2, "intro frames the arena and then pushes in")

	var phase := StoryStage.phase_steps(boss, "")
	var phase_captions := 0
	for step in phase:
		if String(step.get("kind", "")) == "caption":
			phase_captions += 1
	eq(phase_captions, 0, "phase does not repeat the boss's own announcement as a subtitle")
	var phase_with_line := StoryStage.phase_steps(boss, "换了一副样子。")
	var line_captions := 0
	for step in phase_with_line:
		if String(step.get("kind", "")) == "caption":
			line_captions += 1
	eq(line_captions, 1, "a caller can still stage one explicit phase line")

	var defeat := StoryStage.boss_defeat_steps(boss, door)
	var defeat_door_focus := false
	for step in defeat:
		if String(step.get("kind", "")) == "cam_focus" and step.get("target") == door:
			defeat_door_focus = true
	ok(defeat_door_focus, "defeat walks the lens from the body to the next door")
	var no_door := StoryStage.boss_defeat_steps(boss, null)
	eq(String(no_door[0].get("kind", "")), "lock")
	eq(String(no_door[no_door.size() - 1].get("kind", "")), "unlock")

	# All three are skippable through the existing whole-script skip.
	var cam := GameCamera.new()
	add_child(cam)
	Director.play(intro, true)
	ok(Director.playing and cam._focused, "intro starts with the camera in hand")
	Director.skip_step()
	ok(not Director.playing, "one accept ends the intro")
	ok(not Director.is_input_locked(), "and gives the input back")
	ok(not cam._focused, "and releases the camera")
	cam.queue_free()
	boss.queue_free()
	door.queue_free()


## A seated core reports the new verb on a picture-layer card; the script still ends
## with unlock and never needs the player node to exist in a unit fixture.
func test_core_insert_stage_names_the_new_verb() -> void:
	var steps := StoryStage.core_steps(null, "窑匠：把火留在刃上。", "热锻")
	var ability := {}
	for step in steps:
		if String(step.get("id", "")) == "ability":
			ability = step
	eq(String(ability.get("kind", "")), "tableau", "the ability is a tableau, not another caption")
	eq(String(ability.get("title", "")), "热锻", "the card carries the ability name")
	eq(String(ability.get("subtitle", "")), "新 的 动 词", "and frames it as a new verb")
	eq(String(steps[0].get("kind", "")), "lock")
	eq(String(steps[steps.size() - 1].get("kind", "")), "unlock")
	ok(Director.estimate_seconds(steps) < 6.0, "the insert beat stays a beat, not a scene")


## A chapter (re)load wins over any story beat that belonged to the old scene:
## after chapter_started there is no lock, camera focus, caption, card, bar or hint.
func test_chapter_start_resets_a_stale_script_and_the_view() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var cam := GameCamera.new()
	arena.add_child(cam)
	Director.set_letterbox(false, true)
	Director.play([
		{"kind": "lock"},
		{"kind": "tableau", "id": "chapter", "title": "旧章", "subtitle": "锈 墓"},
		{"kind": "cam_focus", "target": Vector2(180, 200), "zoom": 1.6, "duration": 8.0},
		{"kind": "unlock"},
	])
	await flush(3)
	ok(Director.is_input_locked(), "old chapter holds the knight")
	ok(player.cutscene_locked)
	ok(cam._focused, "old chapter holds the camera")
	ok(Director.get_node("CinematicPresentation").active_shot == "chapter")

	GameEvents.chapter_started.emit("level03")
	ok(not Director.playing, "a new chapter aborts the old script")
	ok(not Director.is_input_locked(), "input belongs to the new chapter")
	ok(not player.cutscene_locked, "the knight is released")
	ok(not cam._focused, "the camera is released")
	almost(Director.letterbox_amount(), 0.0, 0.001, "the bars are gone in the same frame")
	ok(not Director.caption().is_busy(), "no old caption survives the load")
	var presentation := Director.get_node("CinematicPresentation")
	eq(presentation.active_shot, "", "no old card survives")
	ok(not presentation.hint_visible(), "no old hint survives")
	cam.queue_free()
	arena.queue_free()
