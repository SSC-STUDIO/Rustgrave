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
	Director.play([{"kind": "lock"}, {"kind": "tableau", "id": "relic"}, {"kind": "wait", "seconds": 5.0}])
	await flush(3)
	eq(presentation.active_shot, "relic")
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
		{"kind": "lock"}, {"kind": "tableau", "id": "grave"},
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
	Director.play([{"kind": "tableau", "id": "relic"}, {"kind": "wait", "seconds": 2.0}])
	await flush(2)
	presentation.show_shot("furnace")
	ok(presentation.back.visible)
	Director.abort()
	ok(not presentation.front.visible)
	ok(not presentation.back.visible)
	ok(not presentation.skip_button.visible)
	ok(not SaveData.has_flag(opening.FLAG))
	SaveData.flags = flags


func test_queued_cutscene_replaces_the_opening_without_leaking_a_tableau() -> void:
	Director.play([{"kind": "lock"}, {"kind": "tableau", "id": "relic"}, {"kind": "wait", "seconds": 5.0}], true)
	Director.play([{"kind": "lock"}, {"kind": "tableau", "id": "grave"}, {"kind": "wait", "seconds": 5.0}], true)
	Director.skip_step()
	ok(Director.playing, "next script is still playing")
	ok(Director.is_input_locked(), "no input gap between scripts")
	eq(presentation.active_shot, "grave")
	Director.skip_step()
	ok(not Director.playing)
	ok(not Director.is_input_locked())
	await wait_until(func() -> bool: return not presentation.front.visible, 120)
	ok(not presentation.front.visible)
	ok(not presentation.back.visible)
