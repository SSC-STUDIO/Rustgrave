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


func _collect_offscreen(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control:
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
