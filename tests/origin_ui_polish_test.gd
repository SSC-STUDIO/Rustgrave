class_name OriginUiPolishTest
extends TestCase
## Test suite for Milestone 4: Character Equipment Panel Polish.
## Validates:
## 1. Top-Left Origin Badge header display for all 3 origins and fallback for unassigned/legacy.
## 2. Dynamic refresh of origin badge on player stats change and panel opening.
## 3. Chromatic color hierarchy applied to the 6 stat value labels.
## 4. Stat tooltips, detail rows, and mathematical formula breakdowns.
## 5. Tab / I hotkey toggle, pause arbitration preservation, and input polish.
## 6. Safety against corrupted or unknown origin IDs.

const UI_PANEL_SCENE := "res://scenes/ui/CharacterEquipmentPanel.tscn"
const CharacterEquipmentPanelScript := preload("res://scripts/ui/character_equipment_panel.gd")
const OriginCatalogScript := preload("res://scripts/data/origin_catalog.gd")
const CharacterStatsScript := preload("res://scripts/player/character_stats.gd")
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")


func setup() -> void:
	Director.choice_hold = false
	Director.playing = false
	Director._locked = false
	Director._fading = false
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	Director.choice_hold = false
	Director.playing = false
	Director._locked = false
	Director._fading = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


# ===========================================================================
# 1. Origin Badge Display & Fallback
# ===========================================================================

func test_origin_badge_fallback_when_unassigned() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	ok(panel.origin_title_label != null, "origin_title_label node exists in panel")
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "unassigned origin displays fallback '身份 · 余烬骑士'")
	eq(panel.origin_title_label.text, "身份 · 余烬骑士", "origin_title_label.text equals '身份 · 余烬骑士'")
	ok(panel.origin_title_label.text.contains("身份"), "origin_title_label contains '身份'")
	eq(panel.origin_title_label.modulate, UiKit.EMBER, "origin title label styled with UiKit.EMBER")

	panel.queue_free()


func test_origin_badge_display_for_all_three_origins() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. Ember Vanguard
	panel.set_origin_override(&"ember_vanguard")
	eq(panel.get_origin_title_text(), "身份 · 余烬重骑", "Ember Vanguard badge displays '身份 · 余烬重骑'")
	eq(panel.origin_title_label.text, "身份 · 余烬重骑", "origin_title_label matches Ember Vanguard")

	# 2. Scrap Scavenger
	panel.set_origin_override(&"scrap_scavenger")
	eq(panel.get_origin_title_text(), "身份 · 废料剑客", "Scrap Scavenger badge displays '身份 · 废料剑客'")
	eq(panel.origin_title_label.text, "身份 · 废料剑客", "origin_title_label matches Scrap Scavenger")

	# 3. Rust Automaton
	panel.set_origin_override(&"rust_automaton")
	eq(panel.get_origin_title_text(), "身份 · 锈械学者", "Rust Automaton badge displays '身份 · 锈械学者'")
	eq(panel.origin_title_label.text, "身份 · 锈械学者", "origin_title_label matches Rust Automaton")

	# 4. Clear override -> safe default
	panel.set_origin_override(&"")
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "cleared override returns to '身份 · 余烬骑士'")

	panel.queue_free()


func test_dynamic_origin_badge_update_on_player_stats_changed() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(4)

	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.set_player(player as Player)
	panel.open_panel()
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "initially unassigned player shows fallback")

	# Dynamically apply Ember Vanguard
	player.stats.apply_origin(&"ember_vanguard")
	await flush(1)
	eq(panel.get_origin_title_text(), "身份 · 余烬重骑", "badge updates to Ember Vanguard upon stats_changed")

	# Dynamically apply Scrap Scavenger
	player.stats.apply_origin(&"scrap_scavenger")
	await flush(1)
	eq(panel.get_origin_title_text(), "身份 · 废料剑客", "badge updates to Scrap Scavenger upon stats_changed")

	# Dynamically apply Rust Automaton
	player.stats.apply_origin(&"rust_automaton")
	await flush(1)
	eq(panel.get_origin_title_text(), "身份 · 锈械学者", "badge updates to Rust Automaton upon stats_changed")

	# Clear origin
	player.stats.apply_origin(&"")
	await flush(1)
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "badge safely reverts to fallback when origin cleared")

	panel.close_panel()
	panel.queue_free()
	player.queue_free()


# ===========================================================================
# 2. Chromatic Color Hierarchy for Stat Values
# ===========================================================================

func test_chromatic_color_hierarchy_applied_to_six_stat_labels() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	var stat_keys: Array[StringName] = [
		&"attack",
		&"defense",
		&"toxin_resist",
		&"toxin_decay",
		&"speed_mult",
		&"max_hp"
	]

	# Verify every stat label exists and has the designated color
	for key in stat_keys:
		var val_lbl: Label = panel.get_stat_value_label(key)
		ok(val_lbl != null, "stat value label exists for %s" % String(key))
		var expected_color: Color = panel.get_stat_color(key)
		eq(val_lbl.modulate, expected_color, "stat label %s modulate matches chromatic color" % String(key))

	# Attack: Warm yellow (#FFC14A)
	var atk_color: Color = panel.get_stat_color(&"attack")
	eq(atk_color.to_html(false).to_upper(), "FFC14A", "Attack color is warm yellow #FFC14A")

	# Defense: Metallic iron grey (#BAC4CC)
	var def_color: Color = panel.get_stat_color(&"defense")
	eq(def_color.to_html(false).to_upper(), "BAC4CC", "Defense color is metallic iron grey #BAC4CC")

	# Toxin Resist & Decay: Teal/cyan (#5CE1B6)
	var tox_res_color: Color = panel.get_stat_color(&"toxin_resist")
	var tox_dec_color: Color = panel.get_stat_color(&"toxin_decay")
	eq(tox_res_color.to_html(false).to_upper(), "5CE1B6", "Toxin resist is teal/cyan #5CE1B6")
	eq(tox_dec_color.to_html(false).to_upper(), "5CE1B6", "Toxin decay is teal/cyan #5CE1B6")

	# Speed Multiplier: Agility blue (#5CB3FF)
	var spd_color: Color = panel.get_stat_color(&"speed_mult")
	eq(spd_color.to_html(false).to_upper(), "5CB3FF", "Speed mult is agility blue #5CB3FF")

	# Max HP: Vitality green (#76E074)
	var hp_color: Color = panel.get_stat_color(&"max_hp")
	eq(hp_color.to_html(false).to_upper(), "76E074", "Max HP is vitality green #76E074")

	# High contrast distinction check between key attributes
	ok(atk_color != def_color, "Attack and Defense have distinct colors")
	ok(atk_color != tox_res_color, "Attack and Toxin have distinct colors")
	ok(atk_color != spd_color, "Attack and Speed have distinct colors")
	ok(def_color != spd_color, "Defense and Speed have distinct colors")

	panel.queue_free()


# ===========================================================================
# 3. Tooltips & Formula Breakdowns
# ===========================================================================

func test_stat_tooltips_and_formula_breakdowns() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(4)

	# Configure Ember Vanguard with starter gear
	player.stats.apply_origin(&"ember_vanguard")
	player.equipment.equip_item(EquipmentCatalog.for_id(&"broken_sword"), &"weapon")
	player.equipment.equip_item(EquipmentCatalog.for_id(&"broken_armor"), &"armor")
	player.equipment.equip_item(EquipmentCatalog.for_id(&"broken_pendant"), &"trinket")
	await flush(1)

	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.set_player(player as Player)
	panel.open_panel()

	# 1. Max HP breakdown: base 5 + origin 1 + equipment 2 = 8
	var hp_detail: Label = panel.get_stat_detail_label(&"max_hp")
	ok(hp_detail != null, "max_hp detail label exists")
	ok(hp_detail.text.contains("基础 5"), "max_hp detail shows base 5")
	ok(hp_detail.text.contains("身份 +1"), "max_hp detail shows origin +1")
	var hp_tooltip := panel.get_stat_tooltip_text(&"max_hp")
	ok(hp_tooltip.contains("生命上限 (Max HP)"), "max_hp tooltip title")
	ok(hp_tooltip.contains("基础 5"), "max_hp tooltip base")
	ok(hp_tooltip.contains("身份 +1"), "max_hp tooltip origin")

	# 2. Attack breakdown
	var atk_detail: Label = panel.get_stat_detail_label(&"attack")
	ok(atk_detail != null, "attack detail label exists")
	ok(atk_detail.text.contains("挥砍"), "attack detail mentions slash damage")
	var atk_tooltip := panel.get_stat_tooltip_text(&"attack")
	ok(atk_tooltip.contains("近战攻击"), "attack tooltip title")
	ok(atk_tooltip.contains("基础挥砍 1"), "attack tooltip formula mentions base 1")

	# 3. Defense breakdown with damage floor 1
	var def_detail: Label = panel.get_stat_detail_label(&"defense")
	ok(def_detail != null, "defense detail label exists")
	ok(def_detail.text.contains("底线 1 点"), "defense detail explains damage floor")
	var def_tooltip := panel.get_stat_tooltip_text(&"defense")
	ok(def_tooltip.contains("伤害减免"), "defense tooltip title")
	ok(def_tooltip.contains("底线 1 点") or def_tooltip.contains("保底 1 点"), "defense tooltip explains damage floor")

	# 4. Toxin Resistance breakdown with 80% cap
	var tox_detail: Label = panel.get_stat_detail_label(&"toxin_resist")
	ok(tox_detail != null, "toxin_resist detail label exists")
	ok(tox_detail.text.contains("80%"), "toxin_resist detail explains 80% cap")
	var tox_tooltip := panel.get_stat_tooltip_text(&"toxin_resist")
	ok(tox_tooltip.contains("80%"), "toxin_resist tooltip explains 80% cap")

	# 5. Toxin Decay breakdown
	var dec_detail: Label = panel.get_stat_detail_label(&"toxin_decay")
	ok(dec_detail != null, "toxin_decay detail label exists")
	ok(dec_detail.text.contains("消散"), "toxin_decay detail explains cleansing")

	# 6. Speed Multiplier breakdown
	var spd_detail: Label = panel.get_stat_detail_label(&"speed_mult")
	ok(spd_detail != null, "speed_mult detail label exists")
	ok(spd_detail.text.contains("倍率") or spd_detail.text.contains("跑速"), "speed_mult detail explains speed scaling")

	panel.close_panel()
	panel.queue_free()
	player.queue_free()


# ===========================================================================
# 4. Panel Toggle Hotkeys & Pause State Preservation
# ===========================================================================

func test_panel_toggle_with_i_key_and_escape() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	eq(panel.is_open, false, "panel starts closed")
	eq(panel.visible, false, "panel starts invisible")

	# 1. 'I' key opens panel immediately
	var ev_i := InputEventKey.new()
	ev_i.keycode = KEY_I
	ev_i.pressed = true
	panel._unhandled_input(ev_i)
	await flush(1)
	eq(panel.is_open, true, "I key opens panel")
	eq(panel.visible, true, "panel is visible")

	# 2. 'I' key closes panel when open
	panel._unhandled_input(ev_i)
	await flush(1)
	eq(panel.is_open, false, "I key closes panel when open")
	eq(panel.visible, false, "panel is hidden")

	# 3. Escape key closes panel when open
	panel.open_panel()
	eq(panel.is_open, true, "panel opened via API")
	var ev_esc := InputEventKey.new()
	ev_esc.keycode = KEY_ESCAPE
	ev_esc.pressed = true
	panel._unhandled_input(ev_esc)
	await flush(1)
	eq(panel.is_open, false, "Escape closes panel")

	panel.queue_free()


func test_pause_arbitration_preservation() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# Scenario A: Opened in-game while unpaused -> manages pause
	get_tree().paused = false
	panel.open_panel(false)
	eq(get_tree().paused, true, "panel pauses tree when opened unpaused")
	panel.close_panel()
	eq(get_tree().paused, false, "panel unpauses tree when closed")

	# Scenario B: Opened from PauseMenu while tree is already paused -> preserves pause
	get_tree().paused = true
	panel.open_panel(true) # from_pause_menu = true
	eq(get_tree().paused, true, "tree remains paused while equipment panel open")
	panel.close_panel()
	eq(get_tree().paused, true, "tree REMAINS paused after closing inside PauseMenu")

	# Cleanup
	get_tree().paused = false
	panel.queue_free()


# ===========================================================================
# 5. Boundary & Corrupted Origin ID Safe Fallback
# ===========================================================================

func test_corrupted_or_unknown_origin_safe_fallback() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# Out-of-spec origin IDs
	panel.set_origin_override(&"corrupted_nonexistent_origin")
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "unknown origin defaults to '身份 · 余烬骑士'")

	panel.set_origin_override(null)
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "null origin defaults to '身份 · 余烬骑士'")

	panel.set_origin_override(12345)
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "integer origin defaults to '身份 · 余烬骑士'")

	panel.queue_free()


# ===========================================================================
# 6. Tab Key Tap vs Hold Threshold & Input Polish
# ===========================================================================

func test_tab_tap_and_hold_threshold_arbitration() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# 1. Tap Tab (< 0.22s) opens panel
	var ev_press := InputEventKey.new()
	ev_press.keycode = KEY_TAB
	ev_press.pressed = true
	panel._unhandled_input(ev_press)

	var ev_rel_quick := InputEventKey.new()
	ev_rel_quick.keycode = KEY_TAB
	ev_rel_quick.pressed = false
	panel._unhandled_input(ev_rel_quick)
	await flush(1)
	eq(panel.is_open, true, "quick tab tap (<0.22s) opens panel")

	# 2. Tap Tab (< 0.22s) while open closes panel
	panel._unhandled_input(ev_press)
	panel._unhandled_input(ev_rel_quick)
	await flush(1)
	eq(panel.is_open, false, "quick tab tap closes panel")

	# 3. Hold Tab (>= 0.22s peek mode) does NOT open panel
	panel._unhandled_input(ev_press)
	panel._tab_press_time = (Time.get_ticks_msec() / 1000.0) - 0.35 # Simulate 350ms hold
	panel._unhandled_input(ev_rel_quick)
	await flush(1)
	eq(panel.is_open, false, "tab hold (>=0.22s) does not toggle panel")

	panel.queue_free()


# ===========================================================================
# 7. Formula Breakdowns for Scrap Scavenger and Rust Automaton
# ===========================================================================

func test_scrap_scavenger_and_rust_automaton_formula_breakdowns() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(4)

	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.set_player(player as Player)
	panel.open_panel()

	# --- Scrap Scavenger: Attack +1, Speed Mult +10% ---
	player.stats.apply_origin(&"scrap_scavenger")
	await flush(1)

	var scrap_atk_detail: Label = panel.get_stat_detail_label(&"attack")
	ok(scrap_atk_detail.text.contains("身份 +1"), "Scrap Scavenger attack detail shows origin +1")
	ok(scrap_atk_detail.text.contains("挥砍"), "Scrap Scavenger attack detail mentions slash")

	var scrap_spd_detail: Label = panel.get_stat_detail_label(&"speed_mult")
	ok(scrap_spd_detail.text.contains("身份 +10%"), "Scrap Scavenger speed detail shows origin +10%")

	var scrap_title := panel.get_origin_title_text()
	eq(scrap_title, "身份 · 废料剑客", "Scrap Scavenger title text matches")

	# --- Rust Automaton: Toxin Resist +20%, Toxin Decay +50% ---
	player.stats.apply_origin(&"rust_automaton")
	await flush(1)

	var rust_res_detail: Label = panel.get_stat_detail_label(&"toxin_resist")
	ok(rust_res_detail.text.contains("80%"), "Rust Automaton resist explains 80% cap")

	var rust_dec_detail: Label = panel.get_stat_detail_label(&"toxin_decay")
	ok(rust_dec_detail.text.contains("身份 +50%"), "Rust Automaton decay detail shows origin +50%")

	var rust_title := panel.get_origin_title_text()
	eq(rust_title, "身份 · 锈械学者", "Rust Automaton title text matches")

	panel.close_panel()
	panel.queue_free()
	player.queue_free()


# ===========================================================================
# 8. SaveData Origin Fallback Inspection (Headless without Player)
# ===========================================================================

func test_savedata_origin_badge_fallback_when_player_absent() -> void:
	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	# Mock SaveData current origin in memory
	var prev_data: Dictionary = SaveData.data.duplicate(true) if SaveData.data != null else {}

	SaveData.data["player"] = {"origin": "scrap_scavenger"}
	panel.refresh()
	eq(panel.get_origin_title_text(), "身份 · 废料剑客", "reads scrap_scavenger from SaveData when player is null")

	SaveData.data["player"] = {"origin": "rust_automaton"}
	panel.refresh()
	eq(panel.get_origin_title_text(), "身份 · 锈械学者", "reads rust_automaton from SaveData when player is null")

	SaveData.data["player"] = {"origin": "ember_vanguard"}
	panel.refresh()
	eq(panel.get_origin_title_text(), "身份 · 余烬重骑", "reads ember_vanguard from SaveData when player is null")

	SaveData.data["player"] = {} # legacy save without origin
	panel.refresh()
	eq(panel.get_origin_title_text(), "身份 · 余烬骑士", "legacy save without origin defaults to '身份 · 余烬骑士'")

	# Restore SaveData data
	SaveData.data = prev_data
	panel.queue_free()


# ===========================================================================
# 9. Inspector Box Details & Action Button
# ===========================================================================

func test_inspector_box_details_and_action_button() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(4)

	player.equipment.equip_item(EquipmentCatalog.for_id(&"broken_sword"), &"weapon")
	await flush(1)

	var panel: CharacterEquipmentPanel = (load(UI_PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await flush(1)

	panel.set_player(player as Player)
	panel.open_panel()

	# Focus weapon slot
	panel._inspect_slot(&"weapon")
	eq(panel._tooltip_name.text, "破损骑士剑", "inspected weapon name matches")
	ok(panel._tooltip_type_set.text.contains("武器"), "inspected slot type is 武器")
	ok(panel._tooltip_type_set.text.contains("破损骑士"), "inspected set name is 破损骑士")
	eq(panel._tooltip_action_btn.visible, true, "action button visible on equipped item")
	eq(panel._tooltip_action_btn.text, "卸 下", "action button text is 卸 下")

	# Inspect empty armor slot
	panel._inspect_slot(&"armor")
	eq(panel._tooltip_name.text, "【 未穿戴装备 】", "empty slot inspection shows placeholder")
	eq(panel._tooltip_action_btn.visible, false, "action button hidden for empty slot")

	# Inspect empty bag cell #0
	panel._inspect_bag(0)
	eq(panel._tooltip_name.text, "【 空格位 】", "empty bag cell shows 空格位")
	eq(panel._tooltip_action_btn.visible, false, "action button hidden for empty bag cell")

	panel.close_panel()
	panel.queue_free()
	player.queue_free()

