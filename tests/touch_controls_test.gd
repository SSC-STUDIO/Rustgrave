extends TestCase
## Headless-safe coverage for the mobile touch pad.


func teardown() -> void:
	TouchInput.force_show = 0
	# Clear any leftover synthetic presses from pulses.
	for action in TouchInput.GAMEPLAY_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)


func test_gameplay_actions_exist_in_input_map() -> void:
	for action in TouchInput.GAMEPLAY_ACTIONS:
		ok(InputMap.has_action(action), "InputMap missing %s" % String(action))


func test_headless_hides_overlay_by_default() -> void:
	TouchInput.force_show = 0
	eq(TouchInput.is_headless(), true, "suite runs headless")
	eq(TouchInput.wants_overlay(), false, "pure headless does not want the pad")


func test_force_show_builds_and_toggles_without_error() -> void:
	TouchInput.force_show = 1
	ok(TouchInput.wants_overlay())
	var pad := TouchControls.new()
	add_child(pad)
	await flush(2)
	ok(is_instance_valid(pad))
	ok(pad.get_node_or_null("Root/Pad") != null, "pad root built")
	pad.visible = true
	pad.release_all()
	pad.visible = false
	pad.queue_free()
	await flush(1)


func test_action_press_pulse_reaches_input_singleton() -> void:
	TouchInput.force_show = 1
	var pad := TouchControls.new()
	add_child(pad)
	await flush(1)
	pad._pulse_action(&"jump")
	ok(Input.is_action_pressed("jump") or Input.is_action_just_pressed("jump"),
			"pulse presses jump")
	await flush(2)
	ok(not Input.is_action_pressed("jump"), "deferred release clears jump")
	pad.queue_free()
	await flush(1)


func test_hud_mounts_touch_controls_child() -> void:
	TouchInput.force_show = 1
	const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	add_child(hud)
	await flush(2)
	var touch := hud.get_node_or_null("TouchControls")
	ok(touch is TouchControls, "HUD always mounts TouchControls")
	hud.queue_free()
	await flush(1)


func test_safe_insets_headless_are_zero() -> void:
	var insets := TouchInput.safe_insets_ui(get_tree().root)
	eq(insets, Vector4.ZERO, "headless safe insets stay zero")
