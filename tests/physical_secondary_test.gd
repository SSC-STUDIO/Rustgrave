extends TestCase
## 实物化不能破坏选章、已见提示与当前键位，也不能让书页跨过中缝。

var _flags_before: PackedStringArray
var _save_path_before: String


func setup() -> void:
	_flags_before = SaveData.flags.duplicate()
	_save_path_before = SaveData.save_path
	SaveData.save_path = "user://physical_secondary_%d.cfg" % Time.get_ticks_usec()
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.flags = _flags_before
	SaveData.save_path = _save_path_before
	Director.resume()
	get_tree().paused = false


func test_controls_four_papers_preserve_bound_keys_and_scroll_input() -> void:
	var screen := ControlsPanel.new()
	add_child(screen)
	await get_tree().process_frame
	screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var grid := screen.get_node("ModalRoot/Card/Content/Body/Scroll/Column/Grid") as GridContainer
	eq(grid.get_child_count(), 4, "four independently laid out sheets")
	var viewport := screen.get_node("ModalRoot/Card/Content/Body/Scroll") as ScrollContainer
	for note in grid.get_children():
		ok(note is PanelContainer, "each group owns its paper panel")
		var style: StyleBox = (note as PanelContainer).get_theme_stylebox("panel")
		ok(style is StyleBoxTexture, "paper uses the cached material texture")
		ok((style as StyleBoxTexture).modulate_color.a > 0.99, "paper does not reveal menu text underneath")
		ok(note.position.y + note.size.y <= viewport.size.y,
				"all four sheets fit the initial instruction viewport: %s within %s" % [note.get_rect(), viewport.size])
		for row in note.get_node("Inner").get_children():
			var keys := row.get_node_or_null("Keys") as HBoxContainer
			if keys != null:
				ok(keys.position.x + keys.size.x <= row.size.x + 1.0, "keycaps remain inside their paper row")
	almost(grid.get_child(0).size.x, grid.get_child(1).size.x, 1.0, "both paper columns have equal width")
	eq(screen.key_text(1), KeyLabels.label(&"jump"), "paper prints the live jump binding")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	(screen.get_node("ModalRoot") as Control).gui_input.emit(wheel)
	ok(screen.visible, "wheel scrolling does not dismiss the instructions")
	screen.close()
	await get_tree().process_frame
	ok(not screen.visible, "Esc close contract still reaches hidden state")
	screen.queue_free()
	await get_tree().process_frame


func test_journal_directory_turns_to_seen_lesson_without_crossing_gutter() -> void:
	HintService.mark_seen(&"swing")
	HintService.mark_seen(&"dash")
	var screen := TutorialRecall.new()
	add_child(screen)
	await get_tree().process_frame
	screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	eq(screen.entry_count(), 2, "journal lists only the two seen lessons")
	var split := screen.get_node("ModalRoot/Card/Content/Body/Split") as HBoxContainer
	var directory := split.get_node("Scroll") as ScrollContainer
	var page := split.get_node("Card") as PanelContainer
	ok(directory.position.x + directory.size.x < page.position.x, "directory and lesson leave a real gutter")
	ok(absf((directory.position.x + directory.size.x + page.position.x) * 0.5 - split.size.x * 0.5) <= 2.0,
			"the two columns align with the book spine")
	var menu := directory.get_node("List") as MenuList
	for item in menu.items():
		ok((item as MenuItem).ink, "lesson navigation uses ink on paper")
	menu.select(1, false)
	var heading := page.get_node("Lesson/LessonTitle") as Label
	var body := page.get_node("Lesson/LessonBody") as Label
	eq(heading.text, "冲刺", "moving the directory selects the matching lesson")
	eq(body.text, KeyLabels.format(String(HintService.CATALOG[&"dash"]["text"])), "lesson uses current bound key text")
	screen.close()
	screen.queue_free()
	await get_tree().process_frame


func test_map_punch_selection_keeps_chapter_dossier_in_sync() -> void:
	var screen := MapScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.open()
	await get_tree().process_frame
	var route := screen.get_node("ModalRoot/Card/Content/Body/Column/Route") as Control
	var order := ChapterText.order()
	var geometry := MapScreen.RouteRail.geometry(route.size.x, order.size())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(geometry.x + geometry.y, MapScreen.RAIL_NODE_Y)
	route.call("_gui_input", click)
	eq(screen.selected_chapter(), order[1], "second punched chapter can still be selected by mouse")
	var dossier := screen.get_node("ModalRoot/Card/Content/Body/Column/Middle/Dossier") as PanelContainer
	ok(dossier.get_theme_stylebox("panel") is StyleBoxTexture, "dossier is a paper attachment")
	var chapter := dossier.get_node("DossierBox/ChapterName") as Label
	eq(chapter.text, ChapterText.name_of(order[1]), "pinned chapter note follows route selection")
	ok(chapter.get_theme_color("font_color").get_luminance() < 0.2, "chapter note uses readable dark ink")
	screen.close()
	screen.queue_free()
	await get_tree().process_frame
