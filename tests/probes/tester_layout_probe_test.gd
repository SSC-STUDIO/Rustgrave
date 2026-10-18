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
	var hud: Node = preload("res://scenes/ui/Hud.tscn").instantiate()
	add_child(hud)
	await flush(6)
	var offscreen: Array = []
	_collect_offscreen(hud, offscreen)
	print("--- HUD offscreen controls: %d ---" % offscreen.size())
	for o in offscreen:
		print("   %s rect=%s" % [String((o as Control).name), str((o as Control).get_global_rect())])
	# Hidden fallback labels (e.g. MapScreen's "地图暂不可用") are PRESET_FULL_RECT
	# with visible=false — they never draw, so they cannot be an appearance defect.
	var visible_off: Array = []
	for o in offscreen:
		if (o as Control).visible:
			visible_off.append(o)
	ok(visible_off.is_empty(),
			"no *visible* HUD control sits outside the viewport (%d hidden fallbacks ignored)" % [offscreen.size() - visible_off.size()])
	hud.queue_free()
	await get_tree().process_frame


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append(c)
		_collect(c, out)


func _collect_offscreen(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control:
			var r := (c as Control).get_global_rect()
			if r.size.length() > 0.0 and (r.position.x < -2.0 or r.position.y < -2.0
					or r.end.x > VIEWPORT.x + 2.0 or r.end.y > VIEWPORT.y + 2.0):
				out.append(c)
		_collect_offscreen(c, out)
