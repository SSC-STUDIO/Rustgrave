extends TestCase
## Every registered level passes LevelSanity: nothing floats, nothing is
## buried, nothing overlaps, and the exit / checkpoints are reachable.


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	Director.abort()


## RUSTGRAVE_LEVEL_FILTER=level05 (environment) restricts both tests to one level,
## so concurrent level authors only see their own problems.
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


func _spawn_of(level: Node) -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return player.global_position if player != null else Vector2.INF


func _camera_limits(level: Node) -> Rect2:
	var cam := get_tree().get_first_node_in_group("game_camera") as Camera2D
	if cam == null:
		return Rect2()
	return Rect2(Vector2(cam.limit_left, cam.limit_top), Vector2(cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top))


func test_every_registered_level_is_sane() -> void:
	for id in _level_ids():
		var path: String = GameContext.LEVELS[id]
		var level := await _load_level(path)
		if level == null:
			continue
		var problems := LevelSanity.check(level, _camera_limits(level))
		for p in problems:
			ok(false, "%s: %s" % [id, p])
		ok(problems.is_empty(), "%s: LevelSanity clean (%d problems)" % [id, problems.size()])
		level.free()
		await flush(1)


## 世界历史细节（docs/art-spec.md「世界历史细节」）：每个主题都从 PropCatalog
## 拿到本主题的 set dressing 键，且这些键的贴图必须真实存在——否则
## ChapterLayout.prop() 会静默返回 null，历史细节凭空消失。
func test_world_history_props_resolve_for_their_theme() -> void:
	var history_keys := ["pipe_valve", "broken_machine", "life_remains", "fire_vent",
			"beam", "beam_bolts", "beam_narrow", "metal_panel", "skull_arch",
			"grave_cross", "bones", "statue", "rock_pile", "rubble_dry"]
	for key in history_keys:
		ok(PropCatalog.DECOR.has(key), "'%s' is a catalogued decor key" % key)
	for theme_id in PropCatalog.THEME_PROPS:
		for key in PropCatalog.THEME_PROPS[theme_id]:
			var path := PropCatalog.path_for(key, theme_id)
			ok(ResourceLoader.exists(path),
					"%s: '%s' resolves to a real texture (%s)" % [theme_id, key, path])
	# 工坊 / 熔渣要有「上一班没干完的活」：坏机械 + 锈管道 / 炉火口。
	for theme_id in ["industrial", "forge"]:
		ok(PropCatalog.THEME_PROPS[theme_id].has("pipe_valve"),
				"%s plants rust pipes" % theme_id)
		ok(PropCatalog.THEME_PROPS[theme_id].has("broken_machine"),
				"%s plants broken machinery" % theme_id)
	# 越界键必须被拒（prop_allowed），否则教堂柱会长到工坊地上。
	ok(not PropCatalog.allowed("industrial", "window"),
			"indoor cathedral window is not allowed in the workshop")
	ok(not PropCatalog.allowed("forge", "grave_cross"),
			"graveyard cross is not allowed in the slag")
	# 分类表本身也要可追溯：每个「世界历史」类都有键，且每个主题至少能种一件。
	for category in PropCatalog.HISTORY_KEYS:
		var keys: Array = PropCatalog.HISTORY_KEYS[category]
		ok(not keys.is_empty(), "history category '%s' lists keys" % category)
		for key in keys:
			ok(PropCatalog.DECOR.has(String(key)),
					"history category '%s' key '%s' is catalogued" % [category, key])
	for theme_id in PropCatalog.THEME_PROPS:
		var planted := false
		for key in PropCatalog.THEME_PROPS[theme_id]:
			if PropCatalog.DECOR.has(String(key)):
				planted = true
				break
		ok(planted, "%s can plant at least one history prop" % theme_id)
	# 悬挂件（链条/藤蔓）不能带接地脚点；它用 hanging() 的顶部中点。
	var layout := ChapterLayout.new()
	var host := Node2D.new()
	add_child(host)
	var chain := layout.hanging(host, "chain", Vector2(40, 10))
	ok(chain != null, "chain is a registered hanging prop")
	if chain != null:
		ok(not chain.is_in_group("grounded"), "hanging props never join the grounded audit")
		eq(String(chain.get_meta("foot_anchor", "")), "top_center")
		ok(chain.has_meta("hang_top"))
		eq(chain.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	layout.free()
	host.free()


## 角色接地（docs/art-spec.md）：接地装饰的「最后一行不透明像素」必须落在
## 登记的 feet 上。prop() 过去按画布底边摆，Kenney / 墓园素材底部 1–8px 的
## 透明留白会让所有道具看起来悬空；这条检查防止回退。
func test_every_grounded_prop_lands_on_its_opaque_pixels() -> void:
	for id in _level_ids():
		var path: String = GameContext.LEVELS[id]
		var level := await _load_level(path)
		if level == null:
			continue
		var checked := 0
		for node in level.get_tree().get_nodes_in_group("grounded"):
			if not (node is Sprite2D):
				continue
			var spr := node as Sprite2D
			if spr.texture == null or not spr.has_meta("feet") or not spr.has_meta("foot_anchor"):
				continue
			var feet: Vector2 = spr.get_meta("feet")
			eq(feet, feet.round(), "%s/%s feet are integer pixels" % [id, spr.name])
			almost(Level01Env.sprite_opaque_bottom_y(spr), feet.y, 1.01,
					"%s/%s opaque bottom sits on its feet" % [id, spr.name])
			checked += 1
		var min_props := 1 if level is StageLevel else 3
		ok(checked >= min_props, "%s has pinned grounded props to audit (%d)" % [id, checked])
		level.free()
		await flush(1)


func test_exit_and_checkpoints_are_reachable_from_spawn() -> void:
	for id in _level_ids():
		var path: String = GameContext.LEVELS[id]
		var level := await _load_level(path)
		if level == null:
			continue
		var spawn := _spawn_of(level)
		var allow_hook := not GameContext.LAYOUTS.has(id)
		ok(spawn != Vector2.INF, "%s spawns a knight" % id)
		for nest in get_tree().get_nodes_in_group("ember_nests"):
			var feet := LevelSanity.feet_of(nest)
			ok(LevelSanity.is_reachable(level, spawn, feet, allow_hook), "%s: nest %s is reachable from spawn" % [id, nest.name])
		var goal_pts: Array[Vector2] = []
		for node in LevelSanity._descendants(level):
			if node is LevelExit or node is ForgeHeart or (not allow_hook and (node is PressurePlate or node is RustyGate)):
				goal_pts.append(LevelSanity.feet_of(node))
			elif node is RoomGate:
				var gp := (node as RoomGate).walkable_goal_point()
				if gp != Vector2.INF:
					goal_pts.append(gp)
		ok(not goal_pts.is_empty(), "%s has an exit, room gate, or forge heart" % id)
		for gp in goal_pts:
			ok(LevelSanity.is_reachable(level, spawn, gp, allow_hook), "%s: %s is reachable from spawn without optional abilities" % [id, str(gp)])
		level.free()
		await flush(1)
