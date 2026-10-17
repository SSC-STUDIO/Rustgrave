extends Node
## 诊断用探针（非测试/非门禁）：在真实窗口（渲染）会话里检查 ui_cancel 是否能让
## 暂停菜单打开，以及菜单本身是否正常工作。
##   godot --path . --windowed --resolution 1280x720 res://scenes/tools/PauseInputProbe.tscn

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("needs render target")
		get_tree().quit(2)
		return
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	SaveData.save_path = "user://pause_probe.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.mark_flag("opening_seen")
	SaveData.mark_flag("wake")
	GameContext.pending_world_path = GameContext.WORLD_PATH
	var pres := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(pres)
	for _i in 10:
		await get_tree().process_frame
	Director.abort()
	await get_tree().create_timer(0.4).timeout
	var pause := _find_pause()
	print("PROBE pause_found=", pause != null, " visible=", pause.visible if pause else false,
			" paused=", get_tree().paused, " host=", GameContext.ui_host(get_tree().get_first_node_in_group("player")) != null)
	print("PROBE window focused=", win.has_focus(), " gui_focus=", win.gui_get_focus_owner())
	# 1) 真实输入事件
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	var rel := InputEventAction.new()
	rel.action = &"ui_cancel"
	rel.pressed = false
	Input.parse_input_event(rel)
	for _i in 8:
		await get_tree().process_frame
	print("PROBE after_input visible=", pause.visible if pause else false, " paused=", get_tree().paused)
	# 2) 直接调用菜单（排除输入路径）
	if pause != null and not pause.is_open():
		pause.open()
	await get_tree().process_frame
	print("PROBE after_direct_open visible=", pause.visible if pause else false, " paused=", get_tree().paused)
	if pause != null and pause.is_open():
		pause.close()
	await get_tree().process_frame
	print("PROBE after_close paused=", get_tree().paused)
	SaveData.delete_save()
	get_tree().quit(0)


func _find_pause() -> PauseMenu:
	var player := get_tree().get_first_node_in_group("player")
	var host := GameContext.ui_host(player)
	if host == null:
		return null
	for node in host.find_children("*", "", true, false):
		if node is PauseMenu:
			return node
	return null
