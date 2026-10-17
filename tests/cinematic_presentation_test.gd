extends TestCase

var presentation


func setup() -> void:
	Director.abort()
	Director.resume()
	get_tree().paused = false
	presentation = Director.get_node("CinematicPresentation")
	presentation.dismiss(true)


func teardown() -> void:
	get_tree().paused = false
	Director.resume()
	Director.abort()


func test_pause_and_suspend_freeze_the_entire_dissolve() -> void:
	Director.play([{"kind": "lock"}, {"kind": "tableau", "id": "chapter", "title": "腐液回廊", "subtitle": "锈墓・壹"}, {"kind": "wait", "seconds": 5.0}])
	await flush(3)
	eq(presentation.active_shot, "chapter")
	Director.suspend()
	var age: float = presentation.front.age
	var alpha: float = presentation.front.modulate.a
	await flush(5)
	almost(presentation.front.age, age, 0.0001)
	almost(presentation.front.modulate.a, alpha, 0.0001)
	ok(not presentation.skip_button.visible, "pause cannot accidentally advance a cutscene")
	Director.resume()
	get_tree().paused = true
	await flush(5)
	almost(presentation.front.age, age, 0.0001)
	get_tree().paused = false
	await flush(3)
	ok(presentation.front.age > age, "motion resumes with the sequence")


func test_skip_releases_camera_and_dissolves_back_to_world() -> void:
	var cam := GameCamera.new()
	add_child(cam)
	Director.play([
		{"kind": "lock"}, {"kind": "tableau", "id": "chapter", "title": "腐液回廊", "subtitle": "锈墓・壹"},
		{"kind": "cam_focus", "target": Vector2(180, 200), "duration": 4.0},
		{"kind": "cam_release"}, {"kind": "unlock"},
	], true)
	ok(cam._focused)
	await flush(3)
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Director._unhandled_input(event)
	ok(not Director.playing)
	ok(not Director.is_input_locked())
	ok(not cam._focused, "whole-script skip must not leave a focused camera behind")
	var hidden := await wait_until(func() -> bool: return not presentation.front.visible, 120)
	ok(hidden, "tableau fades away after a skip")
	ok(not presentation.back.visible)
	cam.queue_free()


func test_abort_clears_both_canvases_and_does_not_mark_opening_seen() -> void:
	var opening := preload("res://scripts/levels/opening_cinematic.gd")
	var flags := SaveData.flags.duplicate()
	SaveData.flags.erase(opening.FLAG)
	Director.play([{"kind": "tableau", "id": "chapter", "title": "腐液回廊"}, {"kind": "wait", "seconds": 2.0}])
	await flush(2)
	presentation.show_shot("boss", "炉约刽子手", "守 芯 者")
	ok(presentation.back.visible)
	Director.abort()
	ok(not presentation.front.visible)
	ok(not presentation.back.visible)
	ok(not presentation.skip_button.visible)
	ok(not SaveData.has_flag(opening.FLAG))
	SaveData.flags = flags


func test_queued_cutscene_replaces_the_opening_without_leaking_a_tableau() -> void:
	Director.play([{"kind": "lock"}, {"kind": "tableau", "id": "chapter", "title": "腐液回廊"}, {"kind": "wait", "seconds": 5.0}], true)
	Director.play([{"kind": "lock"}, {"kind": "tableau", "id": "boss", "title": "炉约刽子手"}, {"kind": "wait", "seconds": 5.0}], true)
	Director.skip_step()
	ok(Director.playing, "next script is still playing")
	ok(Director.is_input_locked(), "no input gap between scripts")
	eq(presentation.active_shot, "boss")
	Director.skip_step()
	ok(not Director.playing)
	ok(not Director.is_input_locked())
	await wait_until(func() -> bool: return not presentation.front.visible, 120)
	ok(not presentation.front.visible)
	ok(not presentation.back.visible)


func test_timed_chapter_card_holds_input_then_yields_to_story() -> void:
	var lines: Array[String] = []
	var on_step := func(_i: int, step: Dictionary) -> void:
		if step.get("kind", "") == "caption":
			lines.append(String(step.get("text", "")))
	Director.step_started.connect(on_step)
	var card := ChapterLevel.chapter_card("锈墓・贰 — 沉钟地窟")
	Director.play([{"kind": "lock"}, card, {"kind": "caption", "text": "钟在数人。", "hold": 0.1}, {"kind": "unlock"}])
	eq(presentation.front.heading, "沉钟地窟")
	eq(presentation.front.subheading, "锈墓・贰")
	ok(Director.is_input_locked())
	await flush(2)
	eq(lines.size(), 0, "story does not start under the chapter card")
	Director.skip_step()
	eq(lines, ["钟在数人。"], "one continue advances to the story")
	eq(presentation.active_shot, "", "card dissolves when the narrative resumes")
	Director.step_started.disconnect(on_step)


func test_boss_flourish_never_locks_live_combat_and_abort_clears_it() -> void:
	GameEvents.boss_appeared.emit("锈 墓 梦 魇 · 无 主 之 马", 16, 16)
	eq(presentation.active_shot, "boss")
	eq(presentation.front.heading, "锈墓梦魇")
	ok(not Director.is_input_locked(), "boss title cannot steal combat controls")
	ok(not Director.playing, "boss title does not enqueue a story")
	Director.abort()
	ok(not presentation.front.visible, "abort also cleans standalone boss titles")
	GameEvents.boss_appeared.emit("炉约刽子手 · 铸渣残躯", 13, 13)
	GameEvents.boss_defeated.emit()
	eq(presentation.active_shot, "", "defeat immediately dismisses the name card")


func test_boss_title_times_out_without_a_director_sequence() -> void:
	GameEvents.boss_appeared.emit("锈墓梦魇", 16, 16)
	var hidden := await wait_until(func() -> bool: return not presentation.front.visible, 250)
	ok(hidden, "standalone title expires and dissolves without needing finished")
	ok(not presentation.back.visible)
	ok(not presentation.skip_button.visible)


## The phase ticks on the boss name card follow boss_phase_changed without a new
## Director sequence: the words stay the same, only the marker under the title climbs.
func test_boss_phase_ticks_follow_the_signal() -> void:
	GameEvents.boss_appeared.emit("炉约刽子手 · 铸渣残躯", 13, 13)
	eq(presentation.active_shot, "boss")
	eq(presentation.front.phase_marks, 1, "a fresh encounter starts at phase one")
	GameEvents.boss_phase_changed.emit("炉约刽子手 · 铸渣残躯", 2)
	eq(presentation.front.phase_marks, 2, "the tick climbs on phase two")
	eq(presentation.back.phase_marks, 2, "the back canvas mirrors it")
	GameEvents.boss_phase_changed.emit("炉约刽子手 · 铸渣残躯", 3)
	eq(presentation.front.phase_marks, 3, "and keeps climbing")
	# A phase signal with no live boss card is ignored, not stored.
	GameEvents.boss_defeated.emit()
	eq(presentation.active_shot, "", "defeat dismisses the card")
	GameEvents.boss_phase_changed.emit("炉约刽子手 · 铸渣残躯", 2)
	eq(presentation.front.phase_marks, 3, "no card means the tick is not moved")
	Director.abort()


## The nameplate is a 2.6 s flourish, but a phase-two fight usually lasts longer than
## that. When the signal arrives after the card has gone, the card must come back with
## the new tick — the phase cinematic depends on the player seeing that mark climb.
func test_boss_phase_re_raises_the_nameplate_after_it_timed_out() -> void:
	GameEvents.boss_appeared.emit("炉约刽子手 · 铸渣残躯", 13, 13)
	eq(presentation.active_shot, "boss")
	var gone := await wait_until(func() -> bool: return not presentation.front.visible, 220)
	ok(gone, "the standalone nameplate expires on its own")
	eq(presentation.active_shot, "", "no shot is active after the timeout")
	GameEvents.boss_phase_changed.emit("炉约刽子手 · 铸渣残躯", 2)
	eq(presentation.active_shot, "boss", "phase two re-raises the same name")
	eq(presentation.front.heading, "炉约刽子手", "the name is preserved")
	eq(presentation.front.phase_marks, 2, "with the new phase tick")
	ok(presentation.front.visible, "and it is visible during the phase beat")
	ok(not Director.is_input_locked(), "the reminder card never locks combat")
	GameEvents.boss_defeated.emit()
	eq(presentation.active_shot, "", "defeat clears it again")
	Director.abort()


## A new ability gets a compact card of its own: the name of the verb is shown as a
## picture-layer beat, without stealing input from a live fight.
func test_ability_card_names_the_new_verb_without_locking_combat() -> void:
	presentation.show_shot("ability", "热锻", "新 的 动 词")
	eq(presentation.active_shot, "ability")
	eq(presentation.front.heading, "热锻", "the card is titled with the ability")
	eq(presentation.front.subheading, "新 的 动 词", "the subtitle frames it as a verb, not loot")
	ok(presentation.front.visible, "the card is drawn")
	ok(not Director.playing, "the card does not queue a story by itself")
	ok(not Director.is_input_locked(), "and cannot steal input")
	presentation.dismiss(true)
	ok(not presentation.front.visible, "a hard dismiss clears it")
	eq(presentation.active_shot, "", "and leaves no active shot")

	# The stage's insert script uses the same shot id, so a live ability insert shows it.
	var card := {}
	for step in StoryStage.core_steps(null, "窑匠：把火留在刃上。", "热锻"):
		if step.get("id", "") == "ability":
			card = step
	eq(String(card.get("title", "")), "热锻", "core_steps carries the ability name")
	eq(String(card.get("subtitle", "")), "新 的 动 词", "and the new-verb subtitle")
