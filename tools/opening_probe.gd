extends Node
## 诊断用探针（非测试、非门禁）：复现开场第一拍，打印骑士可见性状态并截图。
##   godot --path . --windowed --resolution 1280x720 res://scenes/tools/OpeningProbe.tscn

const OUT := "res://screenshots/peek/lead-probe"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("OpeningProbe needs a render target")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	SaveData.save_path = OUT + "/probe-save.cfg"
	SaveData.delete_save()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	OpeningCinematic.reset()
	Director.abort()
	GameContext.pending_world_path = GameContext.WORLD_PATH
	var world := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(world)
	for _i in 40:
		await get_tree().process_frame
		if Director.playing:
			break
	if not Director.playing:
		printerr("opening did not start")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.35).timeout
	_dump("at-0.35s")
	await _capture("opening-first-beat")
	await get_tree().create_timer(2.2).timeout
	_dump("at-2.5s")
	await _capture("opening-stand")
	await get_tree().create_timer(1.6).timeout
	_dump("at-4.1s")
	await _capture("opening-after-stand")
	get_tree().quit(0)


func _dump(tag: String) -> void:
	print("=== PROBE ", tag, " ===")
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		print("no player in group")
		return
	print("player pos=", player.global_position, " visible=", player.visible,
			" cutscene_locked=", player.cutscene_locked,
			" visual.visible=", player.visual.visible, " visual.scale=", player.visual.scale)
	for c in player.visual.get_children():
		var line := "  child=%s class=%s visible=%s pos=%s" % [
			c.name, c.get_class(), c.visible,
			str((c as Node2D).position) if c is Node2D else "?"]
		if c is Sprite2D:
			var t := (c as Sprite2D).texture
			line += " tex=%s size=%s" % [
				t.resource_path.get_file() if t != null else "null",
				str(t.get_size()) if t != null else "0"]
		print(line)
	var cam := get_tree().get_first_node_in_group("game_camera")
	if cam != null:
		print("camera pos=", (cam as Node2D).global_position, " zoom=", (cam as GameCamera).zoom)
	var rise := player.visual.get_node_or_null("OpeningRise") as Node2D
	if rise != null:
		print("rise xform=", rise.get_global_transform_with_canvas())
	print("player xform=", player.get_global_transform_with_canvas())
	for nest in get_tree().get_nodes_in_group("ember_nests"):
		print("nest ", nest.name, " pos=", (nest as Node2D).global_position)


func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [OUT, id]
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("PROBE capture ", path, " err=", err)
	# 世界 SubViewport 的原生 640x360 帧：用来确认骑士在不在“世界”里。
	var pres := get_tree().get_first_node_in_group("game_presentation") as GamePresentation
	if pres != null and pres.world_viewport != null:
		var wpath := "%s/%s-world.png" % [OUT, id]
		var werr := pres.world_viewport.get_texture().get_image().save_png(wpath)
		print("PROBE world capture err=", werr)
