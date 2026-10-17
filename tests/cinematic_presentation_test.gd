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
