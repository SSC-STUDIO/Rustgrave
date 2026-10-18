extends TestCase
## 角色选择里的外观决策：皮肤/刻印条存在、默认跟随起源、选择进入 loadout。

const SkinCatalog := preload("res://scripts/data/skin_catalog.gd")
const RuneCatalog := preload("res://scripts/data/rune_catalog.gd")


func _screen() -> CharacterSelectScreen:
	var screen := CharacterSelectScreen.new()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func test_appearance_strip_exists_with_all_skins_and_runes() -> void:
	var screen := await _screen()
	var strip := screen.find_child("AppearanceStrip", true, false) as VBoxContainer
	ok(strip != null, "外观条存在（皮肤/刻印两行）")
	ok(screen.find_child("SkinRow", true, false) is HBoxContainer, "皮肤行")
	ok(screen.find_child("RuneRow", true, false) is HBoxContainer, "刻印行")
	for skin_id in SkinCatalog.ids():
		ok(screen.find_child("SkinBtn_" + String(skin_id), true, false) is Button,
				"皮肤按钮 %s" % skin_id)
	ok(screen.find_child("RuneBtn_none", true, false) is Button, "无刻印按钮")
	for rune_id in RuneCatalog.ids():
		ok(screen.find_child("RuneBtn_" + String(rune_id), true, false) is Button,
				"刻印按钮 %s" % rune_id)
	screen.free()


func test_default_skin_follows_origin_until_player_picks() -> void:
	var screen := await _screen()
	eq(screen.get_selected_skin_id(), SkinCatalog.default_for_origin(
			OriginCatalog.ORIGIN_EMBER_VANGUARD), "重骑默认余烬骑士")
	screen.select_origin(OriginCatalog.ORIGIN_SCRAP_SCAVENGER)
	eq(screen.get_selected_skin_id(), SkinCatalog.default_for_origin(
			OriginCatalog.ORIGIN_SCRAP_SCAVENGER), "未手动选肤时跟随起源")
	screen.select_skin(&"skin_gothic_hero")
	screen.select_origin(OriginCatalog.ORIGIN_RUST_AUTOMATON)
	eq(screen.get_selected_skin_id(), &"skin_gothic_hero", "手动选过就不再跟随")
	screen.free()


func test_selection_lands_in_the_loadout() -> void:
	var screen := await _screen()
	screen.select_skin(&"skin_cemetery_hero")
	screen.select_rune(&"rune_toxin_filter")
	var loadout := screen.get_selected_loadout()
	eq(StringName(loadout.get("skin", &"")), &"skin_cemetery_hero")
	eq(StringName(loadout.get("rune", &"")), &"rune_toxin_filter")
	# 非法选择被拒绝，保留原值。
	screen.select_skin(&"skin_not_real")
	screen.select_rune(&"rune_not_real")
	eq(screen.get_selected_skin_id(), &"skin_cemetery_hero")
	eq(screen.get_selected_rune_id(), &"rune_toxin_filter")
	# 清空刻印
	screen.select_rune(&"")
	eq(screen.get_selected_rune_id(), &"")
	screen.free()


func test_embark_emits_skin_and_rune() -> void:
	var screen := await _screen()
	screen.select_skin(&"skin_gothic_hero")
	screen.select_rune(&"rune_unbroken")
	var got := {}
	screen.embark_requested.connect(func(origin_id: StringName, loadout: Dictionary) -> void:
		got["origin"] = origin_id
		got["loadout"] = loadout)
	screen.open()
	screen.embark()
	ok(got.has("loadout"), "启程信号带 loadout")
	if got.has("loadout"):
		eq(StringName((got["loadout"] as Dictionary).get("skin", &"")), &"skin_gothic_hero")
		eq(StringName((got["loadout"] as Dictionary).get("rune", &"")), &"rune_unbroken")
	screen.free()
