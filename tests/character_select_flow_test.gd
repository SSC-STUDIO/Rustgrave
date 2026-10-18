extends TestCase
## Automated test suite for CharacterSelectScreen modal and TitleScreen integration flow.
## Validates modal invariants, origin switching, trinket picking, dynamic preview math,
## title screen flow interception (no-save direct open vs save overwrite confirm),
## cancellation restoration, and embark signal contract.

const CharacterSelectScreenScript := preload("res://scripts/ui/character_select_screen.gd")
const CHARACTER_SELECT_SCENE := "res://scenes/ui/CharacterSelectScreen.tscn"
const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"

const TEST_SAVE_PATH := "user://rustgrave_char_select_flow_test.cfg"


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


func _create_char_select() -> CharacterSelectScreen:
	var packed := load(CHARACTER_SELECT_SCENE) as PackedScene
	var screen: CharacterSelectScreen = packed.instantiate() as CharacterSelectScreen
	add_child(screen)
	await get_tree().process_frame
	return screen


func _create_title_screen() -> TitleScreen:
	var packed := load(TITLE_SCENE) as PackedScene
	var title: TitleScreen = packed.instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


# ===========================================================================
# 1. Modal Structure & Invariants Tests
# ===========================================================================

func test_character_select_modal_structure_and_invariants() -> void:
	var screen: CharacterSelectScreen = await _create_char_select()
	ok(screen != null, "CharacterSelectScreen instantiates successfully")
	eq(screen.layer, 8, "CharacterSelectScreen runs on CanvasLayer 8")

	var card := screen.get_node_or_null("ModalRoot/Card") as Control
	ok(card != null, "Modal card exists under ModalRoot/Card")
	var veil := screen.get_node_or_null("ModalRoot/Veil") as ColorRect
	ok(veil != null, "Backdrop veil exists under ModalRoot/Veil")
	var embers := screen.get_node_or_null("ModalRoot/ModalEmbers")
	ok(embers != null, "Floating embers exist under ModalRoot/ModalEmbers")

	if card != null:
		ok(card.custom_minimum_size.x < 1180.0, "Card width < 1180 to leave room for underlying layers (%.1f)" % card.custom_minimum_size.x)
		ok(card.custom_minimum_size.y <= 720.0, "Card height fits design bounds (%.1f)" % card.custom_minimum_size.y)
	if veil != null:
		ok(veil.color.a < 0.8, "Veil alpha merely darkens without blacking out (a=%.2f)" % veil.color.a)

	screen.queue_free()
	await get_tree().process_frame


func test_character_select_ui_bounds_and_no_overflow() -> void:
	var screen: CharacterSelectScreen = await _create_char_select()
	screen.open()
	await flush(2)

	var card := screen.get_node_or_null("ModalRoot/Card") as Control
	ok(card != null, "Card exists")

	var card_rect := card.get_global_rect()

	# 1. Action buttons strictly within Card boundary
	var cancel_btn := screen.get_node_or_null("ModalRoot/Card/Content/Footer/Row/CancelButton") as Button
	var embark_btn := screen.get_node_or_null("ModalRoot/Card/Content/Footer/Row/EmbarkButton") as Button
	ok(cancel_btn != null, "Cancel button exists in Footer")
	ok(embark_btn != null, "Embark button exists in Footer")

	if cancel_btn != null and embark_btn != null and card != null:
		var c_rect := cancel_btn.get_global_rect()
		var e_rect := embark_btn.get_global_rect()
		ok(c_rect.position.y >= card_rect.position.y and c_rect.end.y <= card_rect.end.y + 4.0,
			"Cancel button strictly inside Card vertically (top: %.1f, bottom: %.1f vs card bottom: %.1f)" % [c_rect.position.y, c_rect.end.y, card_rect.end.y])
		ok(e_rect.position.y >= card_rect.position.y and e_rect.end.y <= card_rect.end.y + 4.0,
			"Embark button strictly inside Card vertically (top: %.1f, bottom: %.1f vs card bottom: %.1f)" % [e_rect.position.y, e_rect.end.y, card_rect.end.y])

	# 2. All 3 trinket buttons strictly within Card horizontally and vertically
	var trinket_tabs := screen.get_node_or_null("ModalRoot/Card/Content/Body/MainVBox/Columns/RightColumn/GearPlaque/Content/TrinketTabs") as Control
	ok(trinket_tabs != null, "TrinketTabs container exists")
	if trinket_tabs != null:
		var btns := trinket_tabs.get_children()
		eq(btns.size(), 3, "All 3 trinket buttons exist")
		for i in btns.size():
			var btn := btns[i] as Button
			var b_rect := btn.get_global_rect()
			ok(b_rect.size.x >= 60.0, "Trinket button %d has comfortable width (%.1f)" % [i, b_rect.size.x])
			ok(b_rect.end.x <= card_rect.end.x, "Trinket button %d strictly within Card horizontally (right: %.1f vs card: %.1f)" % [i, b_rect.end.x, card_rect.end.x])

	screen.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 2. Initial Defaults: Ember Vanguard & Broken Knight
# ===========================================================================

func test_initial_state_defaults_to_ember_vanguard() -> void:
	var screen: CharacterSelectScreen = await _create_char_select()

	eq(screen.get_selected_origin_id(), OriginCatalog.ORIGIN_EMBER_VANGUARD, "Defaults to Ember Vanguard")
	eq(screen.get_selected_trinket_id(), &"broken_pendant", "Defaults to Broken Pendant")

	var loadout := screen.get_selected_loadout()
	eq(loadout["weapon"], &"broken_sword", "Default weapon is broken_sword")
	eq(loadout["armor"], &"broken_armor", "Default armor is broken_armor")
	eq(loadout["trinket"], &"broken_pendant", "Default trinket is broken_pendant")

	var stats := screen.get_preview_stats()
	# Ember Vanguard (+1 HP, +1 Def) + Broken Knight 3-piece (+1 Atk, +1 Def, +2 HP, +15% Res)
	eq(int(stats["max_hp"]), 8, "Initial preview Max HP == 8 (5 + 1 origin + 1 armor + 2 set)")
	eq(int(stats["attack"]), 2, "Initial preview Attack == 2 (1 weapon + 1 set)")
	eq(int(stats["defense"]), 3, "Initial preview Defense == 3 (1 origin + 1 armor + 1 set)")
	almost(float(stats["toxin_resist"]), 0.15, 0.001, "Initial preview Toxin Resist == 15% (5% pendant + 10% set)")
	almost(float(stats["toxin_decay"]), 0.0, 0.001, "Initial preview Toxin Decay == 0.0")
	almost(float(stats["speed_mult"]), 1.0, 0.001, "Initial preview Speed Mult == 1.0")
	var syn: Array = stats["synergies"]
	eq(syn.size(), 2, "Both 2pc and 3pc Broken Knight synergies are active")

	screen.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 3. Origin Tab Switching & Dynamic Preview
# ===========================================================================

func test_origin_tab_switching_updates_loadout_and_preview() -> void:
	var screen: CharacterSelectScreen = await _create_char_select()

	# Switch to Scrap Scavenger
	screen.select_origin(OriginCatalog.ORIGIN_SCRAP_SCAVENGER)
	eq(screen.get_selected_origin_id(), OriginCatalog.ORIGIN_SCRAP_SCAVENGER, "Switched to Scrap Scavenger")

	var sc_loadout := screen.get_selected_loadout()
	eq(sc_loadout["weapon"], &"scavenger_blade", "Scrap Scavenger default weapon is scavenger_blade")
	eq(sc_loadout["armor"], &"scavenger_rags", "Scrap Scavenger default armor is scavenger_rags")
	eq(sc_loadout["trinket"], &"broken_pendant", "Retains chosen trinket")

	var sc_stats := screen.get_preview_stats()
	eq(int(sc_stats["max_hp"]), 5, "Scavenger Max HP == 5")
	eq(int(sc_stats["attack"]), 2, "Scavenger Attack == 2 (1 origin + 1 blade)")
	eq(int(sc_stats["defense"]), 1, "Scavenger Defense == 1 (1 rags)")
	almost(float(sc_stats["toxin_resist"]), 0.05, 0.001, "Scavenger Toxin Resist == 5% (pendant)")
	almost(float(sc_stats["speed_mult"]), 1.10, 0.001, "Scavenger Speed Mult == 1.10 (+10% origin)")

	# Switch to Rust Automaton
	screen.select_origin(OriginCatalog.ORIGIN_RUST_AUTOMATON)
	eq(screen.get_selected_origin_id(), OriginCatalog.ORIGIN_RUST_AUTOMATON, "Switched to Rust Automaton")

	var ra_loadout := screen.get_selected_loadout()
	eq(ra_loadout["weapon"], &"scholar_probe", "Rust Automaton default weapon is scholar_probe")
	eq(ra_loadout["armor"], &"scholar_cowl", "Rust Automaton default armor is scholar_cowl")

	var ra_stats := screen.get_preview_stats()
	eq(int(ra_stats["max_hp"]), 5, "Automaton Max HP == 5")
	eq(int(ra_stats["attack"]), 1, "Automaton Attack == 1 (probe)")
	eq(int(ra_stats["defense"]), 1, "Automaton Defense == 1 (cowl)")
	almost(float(ra_stats["toxin_resist"]), 0.30, 0.001, "Automaton Toxin Resist == 30% (20% origin + 5% cowl + 5% pendant)")
	almost(float(ra_stats["toxin_decay"]), 0.50, 0.001, "Automaton Toxin Decay == 0.50 (+50% origin)")
	almost(float(ra_stats["speed_mult"]), 1.0, 0.001, "Automaton Speed Mult == 1.0")

	screen.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 4. Trinket Selection & Cycling
# ===========================================================================

func test_trinket_selection_and_cycling() -> void:
	var screen: CharacterSelectScreen = await _create_char_select()
	screen.select_origin(OriginCatalog.ORIGIN_RUST_AUTOMATON)

	# Select toxic_filter_talisman
	screen.select_trinket(&"toxic_filter_talisman")
	eq(screen.get_selected_trinket_id(), &"toxic_filter_talisman", "Selected toxic_filter_talisman")

	var stats1 := screen.get_preview_stats()
	# 20% origin + 5% cowl + 15% talisman = 40%
	almost(float(stats1["toxin_resist"]), 0.40, 0.001, "Toxin Resist updated to 40%")
	# 0.50 origin + 0.50 talisman = 1.00
	almost(float(stats1["toxin_decay"]), 1.00, 0.001, "Toxin Decay updated to 1.00/s")

	# Select bone_amulet
	screen.select_trinket(&"bone_amulet")
	eq(screen.get_selected_trinket_id(), &"bone_amulet", "Selected bone_amulet")

	var stats2 := screen.get_preview_stats()
	eq(int(stats2["max_hp"]), 6, "Max HP updated to 6 (5 base + 1 bone amulet)")
	almost(float(stats2["speed_mult"]), 1.05, 0.001, "Speed Mult updated to 1.05 (+5% bone amulet)")

	# Test cycling
	screen.cycle_trinket(1)
	ok(screen.get_selected_trinket_id() != &"bone_amulet", "Cycling changes trinket")
	screen.cycle_trinket(-1)
	eq(screen.get_selected_trinket_id(), &"bone_amulet", "Cycling back restores bone_amulet")

	screen.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 5. Invalid Origin and Trinket Input Safety
# ===========================================================================

func test_invalid_origin_and_trinket_are_safely_ignored() -> void:
	var screen: CharacterSelectScreen = await _create_char_select()

	screen.select_origin(&"non_existent_hero")
	eq(screen.get_selected_origin_id(), OriginCatalog.ORIGIN_EMBER_VANGUARD, "Invalid origin ignored")

	screen.select_trinket(&"cursed_ring")
	eq(screen.get_selected_trinket_id(), &"broken_pendant", "Invalid trinket ignored")

	screen.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 6. Title Screen Flow: No Save -> Opens Select Screen Directly
# ===========================================================================

func test_title_screen_new_game_without_save_opens_character_select() -> void:
	ok(not SaveData.has_save(), "Precondition: No save file exists")

	var title: TitleScreen = await _create_title_screen()
	var char_select := title.character_select_screen()
	ok(char_select != null, "TitleScreen contains CharacterSelectScreen instance")
	ok(not char_select.is_open(), "CharacterSelectScreen is initially closed")
	ok((title.get_node("Menu") as MenuList).active, "Title menu is initially active")

	# Select "点燃余烬" (ID_NEW)
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame

	ok(not title.confirm_open(), "No overwrite confirm dialog shown when no save exists")
	ok(char_select.is_open(), "CharacterSelectScreen opens directly")
	ok(not (title.get_node("Menu") as MenuList).active, "Title menu is inactive while modal is open")

	title.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 7. Title Screen Flow: Save Exists -> Confirm -> Overwrite -> Select Screen
# ===========================================================================

func test_title_screen_new_game_with_save_prompts_confirm_then_character_select() -> void:
	# Create mock save file
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	ok(file != null, "Able to create test save file")
	file.store_string("[player]\nhp=5\norigin=\"ember_vanguard\"\n")
	file.close()
	ok(SaveData.has_save(), "Precondition: Save file exists")

	var title: TitleScreen = await _create_title_screen()
	var char_select := title.character_select_screen()
	ok(not char_select.is_open(), "CharacterSelectScreen initially closed")

	# Select "点燃余烬" (ID_NEW)
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame

	ok(title.confirm_open(), "Overwrite confirm dialog opened because save exists")
	ok(not char_select.is_open(), "CharacterSelectScreen not yet open")

	# Cancel confirm
	title._on_confirm_chosen(TitleScreen.ID_KEEP)
	await get_tree().process_frame

	ok(not title.confirm_open(), "Confirm dialog closed on cancel")
	ok(not char_select.is_open(), "CharacterSelectScreen remains closed")
	ok((title.get_node("Menu") as MenuList).active, "Title menu reactivated on cancel")

	# Select ID_NEW again, this time choose ID_OVERWRITE
	title._on_chosen(TitleScreen.ID_NEW)
	await get_tree().process_frame
	ok(title.confirm_open(), "Confirm dialog re-opened")

	title._on_confirm_chosen(TitleScreen.ID_OVERWRITE)
	await get_tree().process_frame

	ok(not title.confirm_open(), "Confirm dialog closed on overwrite")
	ok(char_select.is_open(), "CharacterSelectScreen opened upon overwrite confirmation")
	ok(not (title.get_node("Menu") as MenuList).active, "Title menu inactive while select screen is open")

	title.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 8. Cancellation Safely Restores Title Screen Menu
# ===========================================================================

func test_character_select_cancellation_restores_title_menu() -> void:
	var title: TitleScreen = await _create_title_screen()
	var char_select := title.character_select_screen()

	# Open character select screen directly
	char_select.open()
	(title.get_node("Menu") as MenuList).active = false
	await get_tree().process_frame

	ok(char_select.is_open(), "CharacterSelectScreen is open")
	ok(not (title.get_node("Menu") as MenuList).active, "Title menu inactive")

	# Cancel via screen cancel()
	char_select.cancel()
	await get_tree().process_frame

	ok(not char_select.is_open(), "CharacterSelectScreen closed on cancellation")
	ok((title.get_node("Menu") as MenuList).active, "Title menu restored to active")

	# Test cancellation via simulated ui_cancel action
	char_select.open()
	(title.get_node("Menu") as MenuList).active = false
	await get_tree().process_frame
	ok(char_select.is_open(), "CharacterSelectScreen is open again")

	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	char_select._unhandled_input(ev)
	await get_tree().process_frame

	ok(not char_select.is_open(), "CharacterSelectScreen closed on ui_cancel")
	ok((title.get_node("Menu") as MenuList).active, "Title menu restored on ui_cancel")

	title.queue_free()
	await get_tree().process_frame


# ===========================================================================
# 9. Embark Signal Contract and Loadout Dictionary Payload
# ===========================================================================

func test_embark_requested_signal_payload() -> void:
	var screen: CharacterSelectScreen = await _create_char_select()
	screen.select_origin(OriginCatalog.ORIGIN_SCRAP_SCAVENGER)
	screen.select_trinket(&"bone_amulet")

	var received: Array = []
	screen.embark_requested.connect(func(origin_id: StringName, loadout: Dictionary) -> void:
		received.append({"origin": origin_id, "loadout": loadout})
	)

	screen.open()
	await get_tree().process_frame
	ok(screen.is_open(), "Screen is open")

	screen.embark()
	await get_tree().process_frame

	eq(received.size(), 1, "embark_requested emitted exactly once")
	if received.size() == 1:
		var payload: Dictionary = received[0]
		eq(payload["origin"], OriginCatalog.ORIGIN_SCRAP_SCAVENGER, "Payload origin is Scrap Scavenger")
		var loadout: Dictionary = payload["loadout"]
		eq(loadout["weapon"], &"scavenger_blade", "Payload weapon is scavenger_blade")
		eq(loadout["armor"], &"scavenger_rags", "Payload armor is scavenger_rags")
		eq(loadout["trinket"], &"bone_amulet", "Payload trinket is bone_amulet")

	ok(not screen.is_open(), "Screen closes upon embark")

	screen.queue_free()
	await get_tree().process_frame
