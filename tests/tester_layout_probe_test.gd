extends TestCase
## Tester probe: deep appearance scan of the equipment panel and HUD —
## overlapping labels, clipped text, and modal geometry vs the 1280x720 viewport.

const VIEWPORT := Vector2(1280.0, 720.0)


func test_equipment_panel_label_layout() -> void:
	var panel: Node = preload("res://scripts/ui/character_equipment_panel.gd").new()
	add_child(panel)
	await flush(6)
	var labels: Array = []
	_collect(panel, labels)
	print("--- %d labels ---" % labels.size())
	var overlapping := 0
	var clipped := 0
	for i in labels.size():
		var a: Label = labels[i]
		if a.text.strip_edges() == "":
			continue
		var ra := a.get_global_rect()
		# A label wider than the card with no wrapping is a clipping risk.
		if a.get_visible_characters() >= 0 and a.get_line_count() <= 1:
			var w := a.get_theme_font("font").get_string_size(
					a.text, a.get_theme_font_size("font_size")).x
			if w > ra.size.x + 2.0 and a.autowrap_mode == TextServer.AUTOWRAP_OFF:
				clipped += 1
				print("   CLIPPED: %s text_w=%.0f box_w=%.0f" % [a.name, w, ra.size.x])
		for j in range(i + 1, labels.size()):
			var b: Label = labels[j]
			if b.text.strip_edges() == "":
				continue
			var rb := b.get_global_rect()
			if ra.intersects(rb) and ra.size.length() > 1.0 and rb.size.length() > 1.0:
				var inter := ra.intersection(rb)
				if inter.size.length() > 4.0:
					overlapping += 1
					if overlapping <= 6:
						print("   OVERLAP: %s x %s inter=%s" % [a.name, b.name, str(inter)])
	print("--- overlaps=%d clipped=%d ---" % [overlapping, clipped])
	panel.queue_free()
	await get_tree().process_frame


func test_hud_layout() -> void:
	var hud: Node = preload("res://scenes/ui/HUD.tscn").instantiate()
	add_child(hud)
	await flush(6)
	var offscreen: Array = []
	_collect_offscreen(hud, offscreen)
	print("--- HUD offscreen controls: %d ---" % offscreen.size())
	for o in offscreen:
		print("   %s rect=%s" % [String((o as Control).name), str((o as Control).get_global_rect())])
	# The collector already excludes hidden controls and explicit decoration.
	ok(offscreen.is_empty(), "no visible HUD control sits outside the viewport")
	hud.queue_free()
	await get_tree().process_frame


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append(c)
		_collect(c, out)


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
