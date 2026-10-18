extends TestCase
## Adversarial verification harness for TitleScreen flow and menu rail invariants.
## Specifically challenges:
## 1. Strictly 6 MenuItem child nodes in Menu rail, with correct IDs and kinds.
## 2. New game flow without save: directly opens CharacterSelectScreen; Esc/cancel reactivates title menu.
## 3. New game flow with save: triggers confirm dialog; cancel (button or Esc) keeps save & title menu intact;
##    confirm overwrite opens CharacterSelectScreen.
## 4. Re-entrancy, rapid repeated input, and embark state updates.

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const TEST_SAVE_PATH := "user://rustgrave_m2_challenger_test.cfg"

const EXPECTED_KINDS := [
	MenuItem.Kind.PRIMARY,
	MenuItem.Kind.PRIMARY,
	MenuItem.Kind.SECONDARY,
	MenuItem.Kind.SECONDARY,
	MenuItem.Kind.SECONDARY,
	MenuItem.Kind.SECONDARY,
	MenuItem.Kind.GHOST
]

const EXPECTED_IDS: Array[StringName] = [
	TitleScreen.ID_NEW,
	TitleScreen.ID_CONTINUE,
	TitleScreen.ID_TRIAL,
	TitleScreen.ID_ARENA,
	TitleScreen.ID_SETTINGS,
	TitleScreen.ID_CONTROLS,
	TitleScreen.ID_QUIT
]


func setup() -> void:
	SaveData.save_path = TEST_SAVE_PATH
	SaveData.delete_save()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	Director.choice_hold = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


func _open_title() -> TitleScreen:
	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


func _create_dummy_save() -> void:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	ok(file != null, "Able to create test save file")
	file.store_string("[meta]\nversion=1\nscene=\"res://scenes/levels/Level01_Static.tscn\"\n[player]\nhp=5\nmax_hp=5\norigin=\"ember_vanguard\"\n")
	file.close()


# ===========================================================================
# 1. Menu Rail: Exactly 7 MenuItem Child Nodes (modes grouped) & Invariants
# ===========================================================================

func test_menu_rail_strictly_six_menu_items_and_structure() -> void:
	var title: TitleScreen = await _open_title()
	var menu := title.get_node_or_null("Menu") as MenuList
	ok(menu != null, "Menu exists on TitleScreen")
	if menu == null:
		title.queue_free()
		return

	var all_children := menu.get_children()
	var menu_items: Array[MenuItem] = []
	var other_children: Array[Node] = []

	for child in all_children:
		if child is MenuItem:
			menu_items.append(child)
		else:
			other_children.append(child)

	eq(menu_items.size(), 7, "Menu rail has exactly 7 child MenuItem nodes (2 actions + 4 modes/system + quit)")

	for i in mini(menu_items.size(), EXPECTED_KINDS.size()):
		eq(menu_items[i].kind, EXPECTED_KINDS[i], "MenuItem %d has expected kind" % i)

	# Verify menu internal _items and _ids list matches
	eq(menu._items.size(), 7, "MenuList._items internally tracks 7 items")
	eq(menu._ids.size(), 7, "MenuList._ids internally tracks 7 IDs")
	for i in mini(menu._ids.size(), EXPECTED_IDS.size()):
		eq(menu._ids[i], EXPECTED_IDS[i], "MenuItem %d has expected ID %s" % [i, String(EXPECTED_IDS[i])])

	# Non-menuitem children should be purely spacers/dividers
	for child in other_children:
		ok(child is Control, "Non-menu-item child is a Control spacer/divider")
		ok(not (child is BaseButton), "Non-menu-item child is not a clickable button")

	title.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 2. New Game Flow Without Save File
# ===========================================================================

func test_new_game_flow_without_save() -> void:
	ok(not SaveData.has_save(), "Precondition: No save file")

	var title: TitleScreen = await _open_title()
	var char_select := title.character_select_screen()
	var menu := title.get_node("Menu") as MenuList

	ok(char_select != null, "CharacterSelectScreen exists on TitleScreen")
	ok(not char_select.is_open(), "CharacterSelectScreen initially closed")
	ok(menu.active, "Menu initially active")

	# Trigger "点燃余烬"
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame

	ok(not title.confirm_open(), "Without save: confirm dialog is NOT opened")
	ok(char_select.is_open(), "Without save: CharacterSelectScreen opened directly")
	ok(not menu.active, "Title menu disabled while CharacterSelectScreen is open")

	# Cancel character selection
	char_select.cancel()
	await get_tree().process_frame

	ok(not char_select.is_open(), "CharacterSelectScreen closed after cancellation")
	ok(menu.active, "Title menu reactivated after CharacterSelectScreen cancelled")

	title.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 3. New Game Flow With Save File: Confirm -> Cancel keeps title intact
# ===========================================================================

func test_new_game_flow_with_save_cancel_flow() -> void:
	_create_dummy_save()
	ok(SaveData.has_save(), "Precondition: Save file exists")

	var title: TitleScreen = await _open_title()
	var char_select := title.character_select_screen()
	var menu := title.get_node("Menu") as MenuList

	# Trigger "点燃余烬"
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame

	ok(title.confirm_open(), "With save: confirm overwrite dialog opened")
	ok(not char_select.is_open(), "CharacterSelectScreen NOT opened yet")
	ok(not menu.active, "Title menu disabled while confirm dialog is open")

	# Sub-case A: Cancel via Confirm Menu "取 消" (ID_KEEP)
	title._on_confirm_chosen(TitleScreen.ID_KEEP)
	await get_tree().process_frame

	ok(not title.confirm_open(), "Confirm dialog closed on ID_KEEP")
	ok(not char_select.is_open(), "CharacterSelectScreen remains closed")
	ok(menu.active, "Title menu restored to active")
	ok(SaveData.has_save(), "Save file is intact and NOT deleted on cancel")

	# Sub-case B: Cancel via ui_cancel (Escape key)
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame
	ok(title.confirm_open(), "Confirm dialog opened again")

	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	title._unhandled_input(cancel_event)
	await get_tree().process_frame

	ok(not title.confirm_open(), "Confirm dialog closed by ui_cancel (Esc)")
	ok(not char_select.is_open(), "CharacterSelectScreen remains closed")
	ok(menu.active, "Title menu restored to active after Esc")
	ok(SaveData.has_save(), "Save file remains intact after Esc")

	title.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 4. New Game Flow With Save File: Confirm -> Overwrite opens CharacterSelect
# ===========================================================================

func test_new_game_flow_with_save_confirm_overwrite() -> void:
	_create_dummy_save()
	ok(SaveData.has_save(), "Precondition: Save file exists")

	var title: TitleScreen = await _open_title()
	var char_select := title.character_select_screen()
	var menu := title.get_node("Menu") as MenuList

	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame
	ok(title.confirm_open(), "Confirm dialog opened")

	# Choose overwrite
	title._on_confirm_chosen(TitleScreen.ID_OVERWRITE)
	await get_tree().process_frame

	ok(not title.confirm_open(), "Confirm dialog closed after choosing overwrite")
	ok(char_select.is_open(), "CharacterSelectScreen opened upon overwrite confirmation")
	ok(not menu.active, "Title menu inactive while CharacterSelectScreen is open")

	title.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 5. Stress Test: Re-entrancy, Rapid Triggers, and Embark State
# ===========================================================================

func test_adversarial_reentrancy_and_embarkation() -> void:
	var title: TitleScreen = await _open_title()
	var char_select := title.character_select_screen()

	# Rapidly call ID_NEW 5 times without save
	for _i in 5:
		title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame

	ok(char_select.is_open(), "CharacterSelectScreen is open after repeated ID_NEW")
	ok(not title.confirm_open(), "Confirm dialog never opened")

	# In CharacterSelectScreen: select origin and trinket, then embark
	char_select.select_origin(OriginCatalog.ORIGIN_SCRAP_SCAVENGER)
	char_select.select_trinket(OriginCatalog.ALLOWED_TRINKETS[1])

	# Embark
	char_select.embark()
	await get_tree().process_frame

	ok(not char_select.is_open(), "CharacterSelectScreen closed after embark")
	eq(SaveData.pending_spawn, Vector2.INF, "SaveData.pending_spawn reset to Vector2.INF")
	ok(not SaveData.entering_from_checkpoint, "entering_from_checkpoint is false")

	# Calling ID_NEW after game started should be completely ignored
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame
	ok(not char_select.is_open(), "ID_NEW ignored after game has started")

	title.queue_free()
	await get_tree().process_frame
