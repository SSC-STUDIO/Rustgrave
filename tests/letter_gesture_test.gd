extends TestCase
## Exercise real hit routing and forced animation poses, including cancellation.

const Transitions := preload("res://scripts/ui/ui_transition.gd")
const TEST_SAVE := "user://letter_gesture_test.cfg"
var _old_path := ""
var _old_flash := 1.0


func setup() -> void:
	_old_path = SaveData.save_path
	_old_flash = Settings.flash_scale
	SaveData.save_path = TEST_SAVE
	var cfg := ConfigFile.new()
	cfg.set_value("sentinel", "until_embark", "letter-gesture")
	cfg.save(TEST_SAVE)


func teardown() -> void:
	Settings.set_flash_scale(_old_flash, false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	SaveData.save_path = _old_path


func _title() -> TitleScreen:
	var title := TitleScreen.new()
	add_child(title)
	await flush(2)
	title._skip_intro()
	title.open_confirm()
	await flush(2)
	return title


func _step(tween: Tween, delta: float) -> void:
	if tween != null and tween.is_valid():
		tween.custom_step(delta)


func _force_folding(title: TitleScreen, tweens: Array[Tween]) -> void:
	var root: Control = title._confirm_shell.root
	var card: Control = title._confirm_shell.card
	var veil: Control = title._confirm_shell.veil
	var dressing: Node2D = title._confirm_shell.dressing
	title._confirm_shell["play_outro"] = func(done: Callable) -> void:
		tweens.append(Transitions.object_out(5, root, card, veil, dressing, done, true))


func test_clicking_the_wax_itself_confirms_without_replacing_progress() -> void:
	var before := FileAccess.get_file_as_bytes(TEST_SAVE)
	var title := await _title()
	var button := title.get_node("OverwriteConfirm/ModalRoot/SealButton") as Button
	var seal: Node2D = title._confirm_shell.dressing
	var center: Vector2 = seal.call("seal_center")
	ok(button != null and not button.disabled, "the physical wax has a live action target")
	ok(button.get_rect().has_point(center), "the target covers the drawn wax center")
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await flush(1)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		get_viewport().push_input(event, true)
		await flush(1)
	await flush(1)
	ok(not title.confirm_open(), "a real mouse press and release on wax accepts the letter")
	ok(title.character_select_screen().is_open(), "wax acceptance opens character selection")
	eq(FileAccess.get_file_as_bytes(TEST_SAVE), before, "the old journey survives until embark")
	title.queue_free()
	await flush(1)


func test_confirmation_press_precedes_heat_and_respects_reduced_flash() -> void:
	var before := FileAccess.get_file_as_bytes(TEST_SAVE)
	for flash in [0.0, 1.0]:
		Settings.set_flash_scale(flash, false)
		var title := await _title()
		var seal: Node2D = title._confirm_shell.dressing
		var original: Rect2 = seal.call("seal_rect")
		var opens_before: int = title.character_select_screen()._close_serial
		seal.modulate.a = 0.2
		var tween := title._press_confirm_seal(true)
		almost(seal.modulate.a, 1.0, 0.001, "a quick press finishes arrival with opaque wax")
		_step(tween, 0.07)
		var compressed: Rect2 = seal.call("seal_rect")
		ok(compressed.size.y < original.size.y, "the wax visibly compresses before heating")
		ok(compressed.get_center().y > original.get_center().y, "the press moves into the paper")
		almost(float(seal.get("heat")), 0.0, 0.001, "heat waits for the downstroke")
		ok(title.confirm_open() and not title._confirm_menu.active)
		ok(title._confirm_seal_button.disabled, "repeat clicks are blocked during the press")
		title._on_confirm_chosen(TitleScreen.ID_OVERWRITE)
		title.close_confirm()
		_step(tween, 0.03)
		if flash == 0.0:
			almost(float(seal.get("heat")), 0.0, 0.001, "reduced flash keeps the wax unlit")
		else:
			ok(float(seal.get("heat")) > 0.0, "the pressed seal reaches white heat")
		_step(tween, 0.3)
		ok(not title.confirm_open())
		ok(title.character_select_screen().is_open())
		eq(title.character_select_screen()._close_serial, opens_before + 1, "one press opens selection once")
		eq(FileAccess.get_file_as_bytes(TEST_SAVE), before)
		title.queue_free()
		await flush(1)


func test_cancel_folds_a_closed_envelope_before_withdrawing_it() -> void:
	var before := FileAccess.get_file_as_bytes(TEST_SAVE)
	var title := await _title()
	var tweens: Array[Tween] = []
	_force_folding(title, tweens)
	var card: Control = title._confirm_shell.card
	var seal: Node2D = title._confirm_shell.dressing
	title.close_confirm()
	title.close_confirm()
	eq(tweens.size(), 1, "repeated cancel cannot restart the fold")
	almost(card.modulate.a, 0.0, 0.001, "the flat sheet is replaced by folding geometry")
	_step(tweens[0], 0.02)
	eq((seal.call("fold_pose") as Dictionary).stage, 0, "bottom-third fold")
	_step(tweens[0], 0.07)
	eq((seal.call("fold_pose") as Dictionary).stage, 1, "top flap folds onto the band")
	_step(tweens[0], 0.08)
	var closed: Dictionary = seal.call("fold_pose")
	ok(closed.closed, "the third pose is an actually closed envelope")
	var body: Rect2 = closed.body
	ok(body.size.y < card.size.y * 0.4, "the folded silhouette is a sealed band")
	almost(float(seal.get("withdraw")), 0.0, 0.001, "withdrawal waits until folding finishes")
	almost(seal.modulate.a, 1.0, 0.001, "the closed envelope remains opaque for inspection")
	ok(title.confirm_open(), "closing waits for the physical action")
	eq(card.scale, Vector2.ONE)
	_step(tweens[0], 0.10)
	ok(float(seal.get("withdraw")) > 0.0, "only the closed envelope starts retreating")
	_step(tweens[0], 0.2)
	ok(not title.confirm_open() and title._menu.active)
	eq(FileAccess.get_file_as_bytes(TEST_SAVE), before)
	title.queue_free()
	await flush(1)


func test_reopening_during_a_fold_cancels_its_late_close() -> void:
	var title := await _title()
	var tweens: Array[Tween] = []
	_force_folding(title, tweens)
	title.close_confirm()
	_step(tweens[0], 0.12)
	title.open_confirm()
	ok(not tweens[0].is_valid(), "reopening cancels the complete fold and withdrawal")
	_step(tweens[0], 1.0)
	ok(title.confirm_open() and title._confirm_menu.active)
	ok(not title._menu.active, "an obsolete callback cannot reactivate the underlying title")
	ok(not title._confirm_closing)
	ok(not bool(title._confirm_shell.dressing.get("folding")))
	almost((title._confirm_shell.card as Control).modulate.a, 1.0)
	almost((title._confirm_shell.dressing as Node2D).modulate.a, 1.0)
	ok(not title._confirm_seal_button.disabled)
	title.queue_free()
	await flush(1)
