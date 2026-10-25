extends Node
## 窗口截图：大厅三机位、纵深交战、塔、祭台、泉水、前景、跳跃阴影、结算。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const PRESENTATION := preload("res://scenes/ui/GamePresentation.tscn")

var _out := ""
var _presentation: Node = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("arena_shots needs a window")
		get_tree().quit(2)
		return
	_out = OS.get_environment("RUSTGRAVE_ARENA_SHOTS")
	if _out == "":
		_out = "res://screenshots/arena25d"
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	GameContext.pending_world_path = ArenaCatalog.SCENE
	ArenaRun.auto_begin = false
	ArenaRun.abandon()
	_presentation = PRESENTATION.instantiate()
	add_child(_presentation)
	GamePresentation.set_pixel_smoothing(false)
	await _frames(10)
	_aim(Vector2(320, 180))
	await _frames(4)
	await _shot("01_lobby_blue")
	_aim(Vector2(1920, 180))
	await _frames(4)
	await _shot("02_lobby_lane")
	_aim(Vector2(3520, 180))
	await _frames(4)
	await _shot("03_lobby_red")
	_set_window(Vector2i(960, 540))
	_aim(Vector2(320, 180))
	await _frames(6)
	await _shot("04_lobby_960")
	_set_window(Vector2i(1280, 720))
	await _frames(4)
	_skip_fly()
	ArenaRun.begin_match()
	await _seconds(4.6)
	_stage_fight()
	await _frames(8)
	await _shot("05_fight_depths")
	_aim(Vector2(1280, 180))
	await _frames(6)
	await _shot("06_tower")
	_flash_tower(ArenaCatalog.TEAM_PLAYER, 0)
	await _frames(1)
	await _shot("07_tower_hit")
	_aim(Vector2(460, 180))
	await _frames(4)
	await _shot("08_crystal_locked")
	_aim(Vector2(1920, 180))
	await _frames(4)
	await _shot("09_altar")
	_aim(Vector2(160, 180))
	await _frames(4)
	await _shot("10_blue_base")
	_aim(Vector2(3700, 180))
	await _frames(4)
	await _shot("11_red_base")
	_stage_foreground()
	await _frames(6)
	await _shot("12_foreground")
	_stage_jump()
	await _frames(4)
	await _shot("13_jump_shadow")
	_break_tower(ArenaCatalog.TEAM_PLAYER, 0)
	_aim(Vector2(1280, 180))
	await _frames(4)
	await _shot("14_tower_down")
	_break_tower(ArenaCatalog.TEAM_PLAYER, 1)
	_aim(Vector2(460, 180))
	await _frames(4)
	await _shot("15_crystal_open")
	Engine.time_scale = 1.0
	ArenaRun.finish(true)
	await _frames(8)
	await _shot("16_result")
	print("ARENA_SHOTS done ", _out)
	get_tree().quit(0)


func _set_window(size: Vector2i) -> void:
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.size = size
	DisplayServer.window_set_size(size)


func _find_structure(team: String, index: int) -> Node:
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node):
			continue
		if String(node.get("team")) != team:
			continue
		if int(node.get("structure_index")) != index:
			continue
		return node
	return null


func _flash_tower(team: String, index: int) -> void:
	var tower := _find_structure(team, index)
	if tower == null:
		return
	var health := tower.get_node_or_null("Health") as Health
	if health != null and health.current > 4:
		health.take_damage(3, null)
	var glyph := tower.find_child("Glyph", true, false) as CanvasItem
	if glyph != null:
		glyph.modulate = Color(1.8, 1.8, 1.7)


func _break_tower(team: String, index: int) -> void:
	var guard := 0
	while ArenaRun.structure_vulnerable(team, index) and guard < 8:
		guard += 1
		var row := {}
		for raw in ArenaRun.tower_status():
			if raw is Dictionary:
				var item: Dictionary = raw
				if String(item.get("team", "")) == team and int(item.get("index", -1)) == index:
					row = item
		var left := int(row.get("hp", 0))
		if left <= 0:
			return
		ArenaRun.apply_structure_damage(team, index, left, "")


func _stage_fight() -> void:
	var spots: Array[Vector2] = [
		Vector2(1320, ArenaCatalog.lane_y(0)),
		Vector2(1388, ArenaCatalog.lane_y(1)),
		Vector2(1456, ArenaCatalog.lane_y(2)),
		Vector2(1540, ArenaCatalog.lane_y(0)),
		Vector2(1608, ArenaCatalog.lane_y(2)),
	]
	var slot := 0
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var kind := String(node.get("unit_kind"))
		if kind == "tower" or kind == "crystal" or kind == "elite":
			continue
		if slot >= spots.size():
			break
		var body := node as Node2D
		body.global_position = spots[slot]
		if body.has_method(&"move_toward_depth"):
			body.call(&"move_toward_depth", spots[slot].y)
		body.set_physics_process(false)
		slot += 1
	var knight := get_tree().get_first_node_in_group("player") as Node2D
	if knight != null:
		knight.global_position = Vector2(1490, ArenaCatalog.lane_y(1))
		knight.set_physics_process(false)
	_aim(Vector2(1460, 180))


func _stage_foreground() -> void:
	var knight := get_tree().get_first_node_in_group("player") as Node2D
	if knight != null:
		knight.global_position = Vector2(652, ArenaCatalog.DEPTH_FRONT - 6.0)
		knight.set_physics_process(false)
	_aim(Vector2(700, 180))


func _stage_jump() -> void:
	var knight := get_tree().get_first_node_in_group("player") as Node2D
	if knight == null:
		return
	knight.global_position = Vector2(420, ArenaCatalog.lane_y(2))
	knight.set("cutscene_locked", false)
	knight.set_physics_process(false)
	if knight.has_method(&"arena_force_z"):
		knight.call(&"arena_force_z", ArenaCatalog.JUMP_Z_MAX)
	var slot := 0
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node) or String(node.get("unit_kind")) != "hero":
			continue
		var body := node as Node2D
		body.global_position = Vector2(360.0 + float(slot) * 36.0, ArenaCatalog.lane_y(slot))
		body.set_physics_process(false)
		slot += 1
		if slot >= 3:
			break
	_aim(Vector2(430, 180))


func _spread_lanes() -> void:
	var slot := 0
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var kind := String(node.get("unit_kind"))
		if kind == "tower" or kind == "crystal":
			continue
		var body := node as Node2D
		body.global_position.y = ArenaCatalog.lane_y(slot)
		slot += 1


func _skip_fly() -> void:
	var hud := get_tree().root.find_child("ArenaInterface", true, false)
	if hud != null and hud.has_method(&"_end_fly"):
		hud.call(&"_end_fly", true)


func _aim(at: Vector2) -> void:
	var world := get_tree().get_first_node_in_group("game_world")
	if world == null:
		return
	if world.has_method(&"set_camera_driver"):
		world.call(&"set_camera_driver", false)
	if not world.has_method(&"camera"):
		return
	var cam: Variant = world.call(&"camera")
	if cam != null and cam.has_method(&"focus"):
		cam.call(&"focus", at, 1.0, 0.05)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	var path := _out.path_join(tag + ".png")
	DirAccess.make_dir_recursive_absolute(_out if _out.is_absolute_path() else ProjectSettings.globalize_path(_out))
	var err := image.save_png(path)
	print("ARENA_SHOT ", tag, " ", err)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _seconds(span: float) -> void:
	await get_tree().create_timer(span).timeout
