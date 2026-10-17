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


## 触控板不能有半个按钮伸出 1280×720，也不能有低于 52px 的命中格。
## 旧版动作簇把"互"摆在 120,120 + 56，右下角会伸出屏幕 24px；次级键只有 47.6。
func test_pad_buttons_stay_inside_design_rect_and_touch_sized() -> void:
	TouchInput.force_show = 1
	var pad := TouchControls.new()
	add_child(pad)
	await flush(3)
	var buttons := pad.buttons()
	eq(buttons.size(), 10, "two move + four action + three secondary + pause")
	var screen := Rect2(Vector2.ZERO, Vector2(PresentationMetrics.UI_SIZE))
	for button in buttons:
		var rect := button.get_global_rect()
		ok(rect.size.x >= UiKit.TOUCH_MIN and rect.size.y >= UiKit.TOUCH_MIN,
				"%s 触控高度够 (%.1f×%.1f)" % [button.name, rect.size.x, rect.size.y])
		ok(screen.encloses(rect), "%s 完整落在设计画布内 %s" % [button.name, rect])
	pad.queue_free()
	await flush(1)


## 手机刘海 / 圆角安全区：喂一组边距进去，整块触控板缩进安全区，按钮仍然 ≥52px。
## （真实设备才能给出真实刘海值；这里验证的是排版把安全区当回事。）
func test_safe_insets_keep_the_pad_inside_the_notch() -> void:
	TouchInput.force_show = 1
	var pad := TouchControls.new()
	add_child(pad)
	await flush(3)
	var insets := Vector4(44.0, 24.0, 44.0, 20.0)
	pad.apply_safe_insets(insets)
	await flush(3)
	var safe := Rect2(Vector2(insets.x, insets.y),
			Vector2(PresentationMetrics.UI_SIZE) - Vector2(insets.x + insets.z,
					insets.y + insets.w))
	for button in pad.buttons():
		var rect := button.get_global_rect()
		ok(rect.size.x >= UiKit.TOUCH_MIN and rect.size.y >= UiKit.TOUCH_MIN,
				"%s keeps the 52px touch minimum under a notch" % button.name)
		ok(safe.encloses(rect), "%s stays inside the safe area %s" % [button.name, rect])
	pad.apply_safe_insets(Vector4.ZERO)
	pad.queue_free()
	await flush(1)
