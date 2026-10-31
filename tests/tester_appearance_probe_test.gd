extends TestCase
## Tester probe: appearance/defect scan of UI surfaces — layer ordering,
## off-screen geometry, and the title screen's visual rail.

const TITLE_SCENE := preload("res://scenes/ui/TitleScreen.tscn")
const VIEWPORT := Vector2(1280.0, 720.0)


func test_title_screen_layers_and_geometry() -> void:
	var title: Node = TITLE_SCENE.instantiate()
	add_child(title)
	await flush(6)
	# Collect every CanvasLayer with its layer number.
	var layers: Array = []
	_collect_layers(title, layers)
	print("--- title screen layers ---")
	for l in layers:
		print("   %s layer=%d" % [String((l as Node).name), (l as CanvasLayer).layer])
	# Any control that pokes outside the viewport is an appearance defect.
	var offscreen: Array = []
	_collect_offscreen(title, offscreen)
	print("--- offscreen controls: %d ---" % offscreen.size())
	for o in offscreen:
		print("   %s rect=%s" % [String((o as Control).name), str((o as Control).get_global_rect())])
	ok(offscreen.is_empty(), "no title-screen control sits outside the %s viewport" % str(VIEWPORT))
	title.queue_free()
	await get_tree().process_frame


func test_pause_menu_and_equipment_panel_geometry() -> void:
	var panel: Node = preload("res://scripts/ui/character_equipment_panel.gd").new()
	add_child(panel)
	await flush(6)
	print("--- equipment panel ---")
	print("   layer=%d" % panel.layer)
	ok(panel is CanvasLayer, "panel is a CanvasLayer")
	# The panel card must fit the viewport.
	var card: Control = null
	_find_first_control(panel, &"Card", card)
	if card != null:
		var r := card.get_global_rect()
		print("   card rect=%s" % str(r))
		ok(r.size.x <= VIEWPORT.x + 1.0 and r.size.y <= VIEWPORT.y + 1.0,
				"card fits inside the viewport (got %s)" % str(r.size))
	panel.queue_free()
	await get_tree().process_frame


func _collect_layers(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			out.append(c)
		_collect_layers(c, out)


func test_offscreen_probe_keeps_visible_interaction_checks() -> void:
	var fixture := Node.new()
	add_child(fixture)
	var hidden_layer := CanvasLayer.new()
	hidden_layer.visible = false
	fixture.add_child(hidden_layer)
	var hidden_by_layer := Control.new()
	hidden_by_layer.position = Vector2(1400.0, 20.0)
	hidden_by_layer.size = Vector2(40.0, 40.0)
	hidden_layer.add_child(hidden_by_layer)
	var hidden := Control.new()
	hidden.position = Vector2(1400.0, 80.0)
	hidden.size = Vector2(40.0, 40.0)
	hidden.visible = false
	fixture.add_child(hidden)
	var halo := TextureRect.new()
	halo.position = Vector2(-30.0, 20.0)
	halo.size = Vector2(40.0, 40.0)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.set_meta("allow_viewport_bleed", true)
	fixture.add_child(halo)
	var interactive := Button.new()
	interactive.position = Vector2(1400.0, 140.0)
	interactive.size = Vector2(40.0, 40.0)
	fixture.add_child(interactive)
	# A decorative parent's exemption must never hide its interactive descendants.
	var interactive_child := Button.new()
	interactive_child.position = Vector2(1450.0, 0.0)
	interactive_child.size = Vector2(40.0, 40.0)
	halo.add_child(interactive_child)
	var offscreen: Array = []
	_collect_offscreen(fixture, offscreen)
	ok(not offscreen.has(hidden_by_layer), "a hidden CanvasLayer hides its controls from appearance checks")
	ok(not offscreen.has(hidden), "an individually hidden control is ignored")
	ok(not offscreen.has(halo), "explicit decorative bleed is allowed")
	ok(offscreen.has(interactive), "visible offscreen buttons remain appearance defects")
	ok(offscreen.has(interactive_child), "decorative exemption does not propagate to interactive children")
	eq(offscreen.size(), 2, "only the two actual visible interaction defects are reported")
	fixture.queue_free()
	await get_tree().process_frame


func _collect_offscreen(n: Node, out: Array) -> void:
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree() \
				and not bool(c.get_meta("allow_viewport_bleed", false)):
			var r := (c as Control).get_global_rect()
			if r.size.length() > 0.0 and (r.position.x < -2.0 or r.position.y < -2.0
					or r.end.x > VIEWPORT.x + 2.0 or r.end.y > VIEWPORT.y + 2.0):
				out.append(c)
		_collect_offscreen(c, out)


func _find_first_control(n: Node, target: StringName, out: Control) -> void:
	if out != null:
		return
	for c in n.get_children():
		if c is Control and String(c.name) == String(target):
			out = c
			return
		_find_first_control(c, target, out)
