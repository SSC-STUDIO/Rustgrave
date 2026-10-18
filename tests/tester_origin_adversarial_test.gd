extends TestCase
## Tester-authored adversarial probes for the uncommitted character-origin work.
## These do NOT exist in the repo suite — they probe the gaps TEST_INFRA.md
## claims are covered (origin_persistence_lifecycle_test / origin_ui_polish_test)
## but whose files are missing.

const SaveDataScript := preload("res://scripts/autoload/save_data.gd")
const CharacterStatsScript := preload("res://scripts/player/character_stats.gd")
const TitleScreenScript := preload("res://scripts/ui/title_screen.gd")
const EquipmentPanelScript := preload("res://scripts/ui/character_equipment_panel.gd")
const OriginCatalogScript := preload("res://scripts/data/origin_catalog.gd")
const EquipmentCatalogScript := preload("res://scripts/data/equipment_catalog.gd")

const PLAYER := preload("res://scenes/player/Player.tscn")


# ---------------------------------------------------------------------------
# 1. The documented SaveData.init_new_game() contract does not exist.
# ---------------------------------------------------------------------------

func test_init_new_game_api_exists() -> void:
	var sd := SaveDataScript.new()
	ok(sd.has_method("init_new_game"),
			"SaveData.init_new_game() must exist (PROJECT.md Interface Contract)")
	sd.free()


func test_init_new_game_persists_origin_to_disk() -> void:
	var sd := SaveDataScript.new()
	add_child(sd)
	await get_tree().process_frame
	if not sd.has_method("init_new_game"):
		ok(false, "SaveData.init_new_game() missing — title_screen falls back to a save with no origin persisted")
		sd.queue_free()
		return
	var loadout := {"weapon": &"broken_sword", "armor": &"broken_armor", "trinket": &"broken_pendant"}
	sd.init_new_game(&"ember_vanguard", loadout)
	ok(sd.has_save(), "init_new_game must create the save immediately")
	var cfg := ConfigFile.new()
	cfg.load(sd.save_path)
	ok(cfg.has_section("player"), "save has [player] section")
	eq(String(cfg.get_value("player", "origin", "")), "ember_vanguard",
			"[player] origin must be written to disk")
	sd.delete_save()
	sd.queue_free()


# ---------------------------------------------------------------------------
# 2. apply_player() never re-applies the origin, so a loaded save silently
#    loses all origin stat bonuses (documented order is origin -> equipment).
# ---------------------------------------------------------------------------

func test_apply_player_reapplies_origin() -> void:
	var sd := SaveDataScript.new()
	add_child(sd)
	await get_tree().process_frame
	# Simulate a save written by the character-select flow.
	sd.data = {
		"player": {"hp": 6, "max_hp": 6, "origin": "ember_vanguard"},
		"equipment": {"weapon": "broken_sword", "armor": "broken_armor",
				"trinket": "broken_pendant", "bag": []}
	}
	var player: Node = PLAYER.instantiate()
	add_child(player)
	await flush(4)
	sd.apply_player(player)
	var stats = player.stats
	ok(stats != null, "player has stats")
	if stats != null:
		eq(String(stats.get_origin_id()), "ember_vanguard",
				"apply_player must restore origin id onto stats")
		# get_max_hp_bonus / get_defense_reduction are TOTAL bonuses
		# (origin + equipment + set synergy), not origin-only. The origin's own
		# contribution is in get_origin_stat_modifiers().
		var mods: Dictionary = stats.get_origin_stat_modifiers()
		eq(int(mods.get("max_hp", 0)), 1,
				"apply_player must restore origin max_hp +1 (Ember Vanguard)")
		eq(int(mods.get("defense", 0)), 1,
				"apply_player must restore origin defense +1 (Ember Vanguard)")
		# Totals: origin +1 hp, broken_armor +1 hp, Broken Knight 2-piece +1 hp = 3.
		eq(stats.get_max_hp_bonus(), 3,
				"total max_hp bonus = origin +1 + armor +1 + 2-piece +1")
		eq(stats.get_defense_reduction(), 3,
				"total defense = origin +1 + armor +1 + 2-piece +1")
		eq(stats.get_effective_max_hp(), 8,
				"effective max hp = base 5 + 3 bonuses")
	player.queue_free()
	sd.queue_free()


func test_apply_player_origin_survives_equipment_first() -> void:
	var sd := SaveDataScript.new()
	add_child(sd)
	await get_tree().process_frame
	sd.data = {
		"player": {"hp": 5, "max_hp": 5, "origin": "scrap_scavenger"},
		"equipment": {"weapon": "scavenger_blade", "armor": "scavenger_rags",
				"trinket": "bone_amulet", "bag": []}
	}
	var player: Node = PLAYER.instantiate()
	add_child(player)
	await flush(4)
	sd.apply_player(player)
	var stats = player.stats
	if stats != null:
		eq(String(stats.get_origin_id()), "scrap_scavenger",
				"apply_player restores scrap_scavenger origin")
		eq(stats.get_attack_bonus(), 2,
				"origin +1 atk + blade +1 atk = 2 (documented preview parity)")
		almost(stats.get_speed_multiplier(), 1.15, 0.001,
				"origin +0.10 + amulet +0.05 = 1.15 (documented preview parity)")
	player.queue_free()
	sd.queue_free()


# ---------------------------------------------------------------------------
# 3. Legacy saves (no origin key) must load cleanly.
# ---------------------------------------------------------------------------

func test_legacy_save_without_origin_loads_safely() -> void:
	var sd := SaveDataScript.new()
	add_child(sd)
	await get_tree().process_frame
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", "res://scenes/levels/Level01_Static.tscn")
	cfg.set_value("player", "hp", 5)
	cfg.set_value("player", "max_hp", 5)
	cfg.set_value("player", "pos_x", 96.0)
	cfg.set_value("player", "pos_y", 320.0)
	cfg.set_value("player", "facing", 1)
	cfg.set_value("equipment", "weapon", "broken_sword")
	cfg.set_value("equipment", "armor", "broken_armor")
	cfg.set_value("equipment", "trinket", "broken_pendant")
	cfg.set_value("equipment", "bag", [])
	ok(cfg.save(sd.save_path) == OK, "write legacy save fixture")
	ok(sd.load_game(), "legacy save loads")
	eq(sd.data.get("player", {}).get("origin", "<missing>"), "<missing>",
			"legacy save has no origin key")
	var player: Node = PLAYER.instantiate()
	add_child(player)
	await flush(4)
	sd.apply_player(player)
	var stats = player.stats
	if stats != null:
		eq(String(stats.get_origin_id()), "", "legacy save leaves origin empty")
		# Equipment restored from the save: broken_armor +1 hp and the
		# 2-piece Broken Knight set +1 hp = effective 7, NOT the bare 5.
		eq(stats.get_effective_max_hp(), 7,
				"legacy save restores equipment bonuses (armor +1, set +1 = 7)")
		eq(stats.get_attack_bonus(), 2, "legacy save restores sword +1 and set +1 atk")
	player.queue_free()
	sd.delete_save()
	sd.queue_free()


# ---------------------------------------------------------------------------
# 4. TAB key conflict: HUD peek uses KEY_TAB (hud.gd:542) and the equipment
#    panel also binds KEY_TAB to toggle (character_equipment_panel.gd:195).
# ---------------------------------------------------------------------------

func test_tab_key_binding_conflict() -> void:
	# The HUD's "peek" (secondary info strip) reads Input.is_key_pressed(KEY_TAB)
	# every frame; the equipment panel also consumes Tab in _unhandled_input.
	# Both live on the same tree at the same time -> double response.
	var panel := EquipmentPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	ev.echo = false
	panel._unhandled_input(ev)
	var ev_rel := InputEventKey.new()
	ev_rel.keycode = KEY_TAB
	ev_rel.pressed = false
	ev_rel.echo = false
	panel._unhandled_input(ev_rel)
	await get_tree().process_frame
	ok(panel.visible == true, "Tab tap opens the equipment panel (consumes the key)")
	# And the reverse: tapping again closes it.
	panel._unhandled_input(ev)
	panel._unhandled_input(ev_rel)
	await get_tree().process_frame
	ok(panel.visible == false, "Tab tap closes the panel (tap-to-toggle)")
	panel.queue_free()


func test_tab_hold_does_not_open_panel() -> void:
	# Holding Tab >= 0.22s is the HUD's "peek" gesture; the panel must NOT open.
	var panel := EquipmentPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	ev.echo = false
	panel._unhandled_input(ev)
	panel._tab_press_time = Time.get_ticks_msec() / 1000.0 - 0.5  # simulate a 0.5s hold
	var ev_rel := InputEventKey.new()
	ev_rel.keycode = KEY_TAB
	ev_rel.pressed = false
	ev_rel.echo = false
	panel._unhandled_input(ev_rel)
	await get_tree().process_frame
	ok(panel.visible == false, "Tab hold (>=0.22s) must not open the equipment panel")
	panel.queue_free()


# ---------------------------------------------------------------------------
# 5. Character select: cancel restores the title menu.
# ---------------------------------------------------------------------------

func test_char_select_cancel_restores_title_menu() -> void:
	var ts := TitleScreenScript.new()
	add_child(ts)
	await flush(2)
	var select := ts.character_select_screen()
	ok(select != null, "title screen builds the character select modal")
	if select != null:
		select.open()
		await get_tree().process_frame
		ok(select.is_open(), "select opens")
		select.cancel()
		await get_tree().process_frame
		ok(not select.is_open(), "cancel closes the select screen")
	ts.queue_free()


func test_char_select_layer_sits_above_title_menu() -> void:
	var ts := TitleScreenScript.new()
	add_child(ts)
	await flush(2)
	var select := ts.character_select_screen()
	ok(select != null, "select exists")
	if select != null:
		ok(select.layer > 6, "select layer (%d) must sit above the confirm layer 6" % select.layer)
	ts.queue_free()


# ---------------------------------------------------------------------------
# 6. Equipment panel layer declaration.
# ---------------------------------------------------------------------------

func test_pause_menu_equipment_panel_layer() -> void:
	var panel := EquipmentPanelScript.new()
	ok(panel is CanvasLayer, "equipment panel is a CanvasLayer")
	panel.free()


# ---------------------------------------------------------------------------
# 7. Origin preview parity: PROJECT.md claims calculate_preview_stats matches
#    CharacterStats exactly. Verify each origin end-to-end.
# ---------------------------------------------------------------------------

func test_preview_parity_all_origins() -> void:
	# Origin + preset weapon + preset armor + first trinket.
	var cases := [
		# [origin, expected max_hp, atk, def, resist, decay, speed]
		[&"ember_vanguard", 8, 2, 3, 0.15, 0.0, 1.0],
		[&"scrap_scavenger", 5, 2, 1, 0.05, 0.0, 1.10],
		[&"rust_automaton", 5, 1, 1, 0.30, 0.50, 1.0],
	]
	for c in cases:
		var stats := CharacterStatsScript.new()
		stats.apply_origin(c[0])
		var loadout := OriginCatalogScript.get_starter_loadout(c[0], &"broken_pendant")
		var w = loadout.get(EquipmentItem.SLOT_WEAPON)
		var a = loadout.get(EquipmentItem.SLOT_ARMOR)
		var t = loadout.get(EquipmentItem.SLOT_TRINKET)
		# Feed the items through the stats engine too, so we compare
		# preview-vs-runtime, not just two static calls.
		var items := [w, a, t]
		var syns: Array = EquipmentCatalogScript.calculate_set_synergies(items)
		stats.recalculate(items, syns)
		var preview := OriginCatalogScript.calculate_preview_stats(c[0], w.id, a.id, t.id)
		eq(int(preview["max_hp"]), int(c[1]), "%s preview max_hp %d" % [String(c[0]), int(c[1])])
		eq(int(preview["attack"]), int(c[2]), "%s preview attack %d" % [String(c[0]), int(c[2])])
		eq(int(preview["defense"]), int(c[3]), "%s preview defense %d" % [String(c[0]), int(c[3])])
		var pv_res: float = float(preview["toxin_resist"])
		almost(pv_res, float(c[4]), 0.001, "%s preview resist %.2f" % [String(c[0]), float(c[4])])
		almost(float(preview["speed_mult"]), float(c[6]), 0.001, "%s preview speed %.2f" % [String(c[0]), float(c[6])])
		# Runtime parity
		eq(stats.get_effective_max_hp(), int(preview["max_hp"]), "%s runtime == preview max_hp" % String(c[0]))
		eq(stats.get_attack_bonus(), int(preview["attack"]), "%s runtime == preview attack" % String(c[0]))
		eq(stats.get_defense_reduction(), int(preview["defense"]), "%s runtime == preview defense" % String(c[0]))
		var rt_res: float = stats.get_toxin_resistance()
		almost(rt_res, pv_res, 0.001, "%s runtime == preview resist" % String(c[0]))
		var rt_spd: float = stats.get_speed_multiplier()
		almost(rt_spd, float(preview["speed_mult"]), 0.001, "%s runtime == preview speed" % String(c[0]))
		stats.free()


# ---------------------------------------------------------------------------
# 8. Origin badge: PROJECT.md claims the equipment panel shows
#    "身份 · <Origin Title>" in its header. Verify the panel has one.
# ---------------------------------------------------------------------------

func test_equipment_panel_has_origin_badge() -> void:
	var panel := EquipmentPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	var found := ""
	var labels: Array[String] = []
	_collect_labels(panel, labels)
	for text in labels:
		if text.contains("身份"):
			found = text
			break
	ok(found != "", "equipment panel must render an origin badge containing 身份 (labels: %s)" % str(labels))
	panel.queue_free()


func _collect_labels(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_collect_labels(c, out)


# ---------------------------------------------------------------------------
# 9. Trinket pool aliasing: bone_amulet / bone_charm and
#    toxic_filter_talisman / toxic_ward must be interchangeable.
# ---------------------------------------------------------------------------

func test_trinket_alias_symmetry() -> void:
	var pairs := [[&"bone_amulet", &"bone_charm"], [&"toxic_filter_talisman", &"toxic_ward"]]
	for p in pairs:
		var a: EquipmentItem = EquipmentCatalogScript.for_id(p[0])
		var b: EquipmentItem = EquipmentCatalogScript.for_id(p[1])
		ok(a != null and b != null, "both aliases resolve: %s / %s" % [String(p[0]), String(p[1])])
		if a != null and b != null:
			eq(a.attack, b.attack, "%s attack parity" % String(p[0]))
			eq(a.defense, b.defense, "%s defense parity" % String(p[0]))
			eq(a.max_hp, b.max_hp, "%s max_hp parity" % String(p[0]))
			eq(a.toxin_resist, b.toxin_resist, "%s resist parity" % String(p[0]))
			eq(a.toxin_decay, b.toxin_decay, "%s decay parity" % String(p[0]))
			eq(a.speed_mult, b.speed_mult, "%s speed parity" % String(p[0]))
