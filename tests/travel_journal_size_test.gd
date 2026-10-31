extends TestCase
## The travel journal must be smaller in both dimensions and retain two usable pages.


func test_travel_journal_is_smaller_than_ledger_and_pages_fit() -> void:
	var old_flags := SaveData.flags.duplicate()
	HintService.mark_seen(&"swing")
	HintService.mark_seen(&"dash")
	var settings := SettingsScreen.new()
	var journal := TutorialRecall.new()
	add_child(settings)
	add_child(journal)
	settings.open()
	journal.open()
	await flush(3)
	var ledger_card := settings.get_node("ModalRoot/Card") as Control
	var journal_card := journal.get_node("ModalRoot/Card") as Control
	ok(journal_card.size.x < ledger_card.size.x, "travel book is narrower than the desk ledger")
	ok(journal_card.size.y < ledger_card.size.y, "travel book is shorter than the desk ledger")
	var split := journal.get_node("ModalRoot/Card/Content/Body/Split") as Control
	var directory := split.get_node("Scroll") as Control
	var page := split.get_node("Card") as Control
	ok(directory.position.x + directory.size.x < page.position.x, "directory remains on the left page")
	ok(page.position.x + page.size.x <= split.size.x + 1.0, "lesson remains inside the right page")
	ok(page.size.y <= split.size.y + 1.0, "the compact lesson page fits its book")
	SaveData.flags = old_flags
	settings.queue_free()
	journal.queue_free()
	await flush(1)


func test_same_frame_open_and_refresh_discard_obsolete_directory_scrolls() -> void:
	var old_flags := SaveData.flags.duplicate()
	HintService.mark_seen(&"swing")
	HintService.mark_seen(&"dash")
	var journal := TutorialRecall.new()
	add_child(journal)
	journal.open()
	journal.refresh()
	journal.refresh()
	await flush(3)
	ok(journal.visible, "same-frame refresh retains the open journal")
	var menu := journal.get_node("ModalRoot/Card/Content/Body/Split/Scroll/List") as MenuList
	ok(menu.active and menu.items().size() >= 2, "the replacement directory remains usable")
	menu.select(1, false)
	await flush(1)
	var heading := journal.get_node("ModalRoot/Card/Content/Body/Split/Card/Lesson/LessonTitle") as Label
	ok(heading.text != "", "current rows still scroll to and open their lesson")
	SaveData.flags = old_flags
	journal.queue_free()
	await flush(1)
