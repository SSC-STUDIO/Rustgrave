extends TestCase
## Focused diagnostics for the two failures whose cause is not yet proven.

const SaveDataScript := preload("res://scripts/autoload/save_data.gd")
const EquipmentPanelScript := preload("res://scripts/ui/character_equipment_panel.gd")

const PLAYER := preload("res://scenes/player/Player.tscn")


func test_legacy_hp_after_real_load() -> void:
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
	cfg.save(sd.save_path)
	var ok_load: bool = sd.load_game()
	print("load_game -> %s" % ok_load)
	print("data.player = %s" % sd.data.get("player"))
	var player: Node = PLAYER.instantiate()
	add_child(player)
	await flush(4)
	sd.apply_player(player)
	var hp_node = player.get_node_or_null("Health")
	print("hp node max_hp=%s current=%s" % [hp_node.max_hp, hp_node.current])
	var stats = player.stats
	if stats != null:
		print("stats origin='%s' eff_hp=%d atk=%d def=%d" % [
				String(stats.get_origin_id()), stats.get_effective_max_hp(),
				stats.get_attack_bonus(), stats.get_defense_reduction()])
	player.queue_free()
	sd.delete_save()
	sd.queue_free()


func test_tab_press_opens_panel() -> void:
	var panel := EquipmentPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	print("panel process_unhandled_input=%s" % panel.is_processing_unhandled_input())
	print("panel visible before=%s" % panel.visible)
	print("can_open=%s" % panel.can_open())
	if Director != null:
		print("Director: fading=%s choice_hold=%s locked=%s playing=%s" % [
				Director.is_fading(), Director.choice_hold, Director.is_input_locked(), Director.playing])
	var p = panel._resolve_player()
	print("resolved player=%s" % (p != null))
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	ev.echo = false
	print("--- direct press ---")
	panel._unhandled_input(ev)
	print("tab_press_time after press=%s" % panel._tab_press_time)
	var ev_rel := InputEventKey.new()
	ev_rel.keycode = KEY_TAB
	ev_rel.pressed = false
	ev_rel.echo = false
	panel._unhandled_input(ev_rel)
	print("panel visible after release=%s" % panel.visible)
	panel.queue_free()


func test_equipment_panel_label_dump() -> void:
	var panel := EquipmentPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	print("panel children: %s" % [panel.get_child_count()])
	var labels: Array[String] = []
	for child in panel.find_children("*", "Label", true, true):
		var lbl := child as Label
		if lbl != null:
			labels.append(lbl.text)
	print("labels (%d): %s" % [labels.size(), str(labels)])
	# recursive manual walk
	var manual: Array[String] = []
	_walk(panel, manual)
	print("manual labels (%d): %s" % [manual.size(), str(manual)])
	panel.queue_free()


func _walk(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_walk(c, out)
