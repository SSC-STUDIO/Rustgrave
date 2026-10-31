extends TestCase

const Objects := preload("res://scripts/ui/ui_object.gd")
const TEST_SAVE := "user://overwrite_letter_test.cfg"
var _old_path := ""


func setup() -> void:
	_old_path = SaveData.save_path
	SaveData.save_path = TEST_SAVE
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("sentinel", "preserve_until_embark", "letter-test")
	cfg.save(TEST_SAVE)


func teardown() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	SaveData.save_path = _old_path


func _title() -> TitleScreen:
	var title := (load("res://scenes/ui/TitleScreen.tscn") as PackedScene).instantiate() as TitleScreen
	add_child(title)
	await flush(2)
	title._skip_intro()
	return title


func test_letter_has_a_real_seal_and_defaults_to_safe_ink_action() -> void:
	var title := await _title()
	title.open_confirm()
	await flush(2)
	var card := title.get_node("OverwriteConfirm/ModalRoot/Card") as Control
	eq(card.get_meta("object_kind"), Objects.Kind.LETTER)
	ok(card.get_rect().has_point(title._confirm_shell["dressing"].seal_center()))
	ok(card.size.x <= 640.0 and card.size.y <= 440.0)
	eq(title._confirm_menu.selected_id(), TitleScreen.ID_KEEP)
	for item in title._confirm_menu.items():
		ok(item.ink)
	eq(card.get_node("Content/Header/Title").get_theme_constant("outline_size"), 0)
	title.queue_free()
	await flush(1)


func test_repeated_cancel_preserves_save_bytes_and_restores_title_input() -> void:
	var before := FileAccess.get_file_as_bytes(TEST_SAVE)
	var title := await _title()
	for i in 8:
		title.open_confirm()
		title.close_confirm()
		ok(not title.confirm_open())
		ok(title._menu.active)
	eq(FileAccess.get_file_as_bytes(TEST_SAVE), before)
	title.queue_free()
	await flush(1)


func test_seal_acceptance_still_waits_for_character_embark_before_replacing_save() -> void:
	var before := FileAccess.get_file_as_bytes(TEST_SAVE)
	var title := await _title()
	title.open_confirm()
	title._on_confirm_chosen(TitleScreen.ID_OVERWRITE)
	ok(not title.confirm_open())
	ok(title.character_select_screen().visible)
	ok(not title._menu.active)
	eq(FileAccess.get_file_as_bytes(TEST_SAVE), before)
	title._on_char_select_cancelled()
	ok(title._menu.active)
	eq(FileAccess.get_file_as_bytes(TEST_SAVE), before)
	title.queue_free()
	await flush(1)
