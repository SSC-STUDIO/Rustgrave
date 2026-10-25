extends TestCase
## 贴图放置回归：全部战役关卡 + 模式场景 + 标题活景的装饰贴图都要过 SpriteAudit
## （悬空/沉地、悬挂锚点、穿墙、互叠、越界、z 层级）。白名单
## （SpriteAudit.AUDIT_WHITELIST）里登记的是逐条复核过的有意摆放；新装饰
## 错位会直接红。RUSTGRAVE_LEVEL_FILTER=level05 只扫一章。


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	TitleWorld.forced_state = {}


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	TitleWorld.forced_state = {}
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


func _level_ids() -> Array:
	var only := OS.get_environment("RUSTGRAVE_LEVEL_FILTER")
	if only != "" and GameContext.LEVELS.has(only):
		return [only]
	return GameContext.LEVELS.keys()


func _load_level(path: String) -> Node:
	var packed := load(path) as PackedScene
	ok(packed != null, "%s loads" % path)
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	return level


func _camera_limits() -> Rect2:
	var cam := get_tree().get_first_node_in_group("game_camera") as Camera2D
	if cam == null:
		return Rect2()
	return Rect2(Vector2(cam.limit_left, cam.limit_top),
			Vector2(cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top))


func _assert_clean(scene_id: String, found: Array[Dictionary]) -> void:
	for f in found:
		var pos: Array = f["pos"]
		var pos_str := "(%d,%d)" % [int(pos[0]), int(pos[1])] if pos.size() == 2 else "-"
		ok(false, "%s: [%s] %s %s %s :: %s" % [scene_id, f["category"], f["node"],
				f["texture"], pos_str, f["detail"]])
	ok(found.is_empty(), "%s: SpriteAudit clean (%d findings)" % [scene_id, found.size()])


func test_every_level_sprites_are_placed_sanely() -> void:
	for id in _level_ids():
		var level := await _load_level(String(GameContext.LEVELS[id]))
		if level == null:
			continue
		_assert_clean(String(id), SpriteAudit.filter_whitelisted(String(id),
				SpriteAudit.findings(level, _camera_limits())))
		level.free()
		await flush(1)


func test_mode_scenes_sprites_are_sane() -> void:
	for path in GameContext.MODE_SCENES:
		var label := String(path).get_file().get_basename().to_snake_case()
		var level := await _load_level(String(path))
		if level == null:
			continue
		_assert_clean(label, SpriteAudit.filter_whitelisted(label,
				SpriteAudit.findings(level, _camera_limits())))
		level.free()
		await flush(1)


func test_title_world_layers_are_anchored() -> void:
	TitleWorld.forced_state = {}
	var vp := SubViewport.new()
	vp.size = Vector2i(TitleWorld.WORLD)
	vp.world_2d = World2D.new()
	vp.disable_3d = true
	vp.snap_2d_transforms_to_pixel = true
	add_child(vp)
	var world := (load("res://scenes/ui/TitleWorld.tscn") as PackedScene).instantiate()
	vp.add_child(world)
	await flush(3)
	_assert_clean("title_world", SpriteAudit.check_title(world))
	vp.free()
	await flush(1)
