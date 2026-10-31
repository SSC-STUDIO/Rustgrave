extends TestCase
## 动画测试主动推进真实 tween，覆盖 headless 瞬时分支看不到的重入与像素对齐。

const Transitions := preload("res://scripts/ui/ui_transition.gd")
const HOME := Vector2(128.0, 44.0)


func _rig() -> Dictionary:
	var root := Control.new()
	add_child(root)
	var veil := ColorRect.new()
	root.add_child(veil)
	var card := Control.new()
	root.add_child(card)
	card.position = HOME
	return {"root": root, "veil": veil, "card": card}


func _step(tw: Tween, delta: float) -> void:
	if tw != null and tw.is_valid():
		tw.custom_step(delta)


func test_all_materials_keep_integer_pixels_through_the_entire_entry() -> void:
	for kind in 6:
		var rig := _rig()
		var card: Control = rig.card
		var tw := Transitions.object_in(kind, rig.root, card, rig.veil, null, [], true)
		for frame in 26:
			_step(tw, 0.013)
			eq(card.position, card.position.round(), "kind %d frame %d is pixel aligned" % [kind, frame])
			eq(card.scale, Vector2.ONE, "lettering never scales")
		eq(card.position, HOME, "each material lands at its stable home")
		almost(card.modulate.a, 1.0)
		ok(not rig.root.has_meta("_tween"), "completed transitions release their handle")


func test_reopening_board_cancels_both_fall_and_stale_close_callback() -> void:
	var rig := _rig()
	var card: Control = rig.card
	var callbacks := [0]
	var entering := Transitions.object_in(0, rig.root, card, rig.veil, null, [], true)
	_step(entering, 0.09)
	var leaving := Transitions.object_out(0, rig.root, card, rig.veil, null, func() -> void:
		callbacks[0] += 1
		rig.root.visible = false, true)
	ok(not entering.is_valid(), "closing cancels the entire board fall")
	_step(leaving, 0.04)
	var reopening := Transitions.object_in(0, rig.root, card, rig.veil, null, [], true)
	ok(not leaving.is_valid(), "reopening cancels the pending close")
	_step(entering, 1.0)
	_step(leaving, 1.0)
	_step(reopening, 0.4)
	eq(callbacks[0], 0, "an obsolete close must never hide the reopened screen")
	ok(rig.root.visible)
	eq(card.position, HOME, "reopening must not record an animated offset as home")


func test_reset_cancels_board_rebound_and_restores_the_supplied_layout_home() -> void:
	var rig := _rig()
	var card: Control = rig.card
	var tw := Transitions.object_in(0, rig.root, card, rig.veil, null, [], true)
	_step(tw, 0.18)
	var resized_home := Vector2(144.0, 58.0)
	Transitions.modal_reset(rig.root, card, rig.veil, resized_home, 1.0)
	ok(not tw.is_valid(), "reset cancels the rebound as well as opacity")
	_step(tw, 1.0)
	eq(card.position, resized_home)
	var next := Transitions.object_in(0, rig.root, card, rig.veil, null, [], true)
	_step(next, 0.4)
	eq(card.position, resized_home, "the next entry respects the updated layout")


func test_close_during_entry_completes_once_without_drifting_the_origin() -> void:
	for kind in 6:
		var rig := _rig()
		var card: Control = rig.card
		var callbacks := [0]
		var entering := Transitions.object_in(kind, rig.root, card, rig.veil, null, [], true)
		_step(entering, 0.07)
		var leaving := Transitions.object_out(kind, rig.root, card, rig.veil, null,
				func() -> void: callbacks[0] += 1, true)
		for frame in 16:
			_step(leaving, 0.013)
			eq(card.position, card.position.round())
		eq(callbacks[0], 1, "only the current close completes")
		eq(card.position, HOME, "closing mid-entry restores the unshifted origin")


func test_headless_snap_cancels_a_live_outro_instead_of_running_its_callback_later() -> void:
	var rig := _rig()
	var callbacks := [0]
	var leaving := Transitions.object_out(1, rig.root, rig.card, rig.veil, null,
			func() -> void: callbacks[0] += 1, true)
	_step(leaving, 0.04)
	Transitions.object_in(1, rig.root, rig.card, rig.veil)
	_step(leaving, 1.0)
	eq(callbacks[0], 0)
	eq(rig.card.position, HOME)
	almost(rig.card.modulate.a, 1.0)


func test_legacy_modal_uses_the_same_cancellable_transition_lifecycle() -> void:
	var rig := _rig()
	var callbacks := [0]
	var entering := Transitions.modal_in(rig.root, rig.card, rig.veil, [], true)
	_step(entering, 0.06)
	var leaving := Transitions.modal_out(rig.root, rig.card, rig.veil,
			func() -> void: callbacks[0] += 1, true)
	_step(leaving, 0.03)
	var reopening := Transitions.modal_in(rig.root, rig.card, rig.veil, [], true)
	_step(reopening, 0.4)
	_step(leaving, 1.0)
	eq(callbacks[0], 0)
	eq(rig.card.position, HOME)
	almost(rig.veil.modulate.a, 1.0)
