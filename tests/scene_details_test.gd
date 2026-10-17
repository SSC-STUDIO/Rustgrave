extends TestCase
## 1A 场景细节与光照（docs/UPGRADE_PLAN.md P0-1 / P2-1）：
##   · SceneDetails 种的是 PropCatalog 里已入库的真实贴图（1x、NEAREST、脚点钉台面），
##     不再是 ColorRect / Polygon2D 占位方块；
##   · 每件接地细节都踩在平台顶上，不压台缘、不盖路牌、不挡敌人起手与交互物；
##   · 氛围灯锚定真实地标（余烬巢 / 毒池 / 门 / Boss 门 / 炉心），没有写死坐标；
##   · 墓园族锈铁残骸来自 tools/gen_theme_tiles.py 的 rust_remains()。

var _level: Node = null
## 敌人出生位的身体盒（physics 跑起来前抓的；walker 会挪窝，占用检查按出生位算）。
var _enemy_boxes: Array[Rect2] = []


func setup() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	Director.abort()
	Director.resume()
	Director.choice_hold = false


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	_level = null
	_enemy_boxes.clear()


func _load_level() -> Node:
	_level = null
	_enemy_boxes.clear()
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	ok(packed != null, "Level01 scene loads")
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	# 先抓出生位再跑物理：Scrapper 落地后会走开，出生脚点是布景要绕开的点。
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or not level.is_ancestor_of(enemy):
			continue
		if enemy is FlyingDemonEnemy or enemy is GhostEnemy:
			continue
		if absf(enemy.global_position.y - Level01Static.GROUND_TOP) > 4.0:
			continue  # 站在浮台上的敌人，脚下那块台面不是地面线
		_enemy_boxes.append(Rect2(enemy.global_position - Vector2(14.0, 48.0), Vector2(28.0, 48.0)))
	await flush(3)
	Director.abort()
	_level = level
	return level


func _details(level: Node) -> Node2D:
	return level.get_node_or_null("SceneDetails") as Node2D


func _sprite_rect(spr: Sprite2D) -> Rect2:
	return spr.get_global_transform() * spr.get_rect()


## 实体占地：只算有真实贴图的可见精灵；发光光晕 / 程序化光束是表现层，不算轮廓。
func _body_aabb(node: Node2D) -> Rect2:
	var box := Rect2()
	var any := false
	for child in LevelSanity._descendants(node):
		var spr := child as Sprite2D
		if spr == null or not spr.visible or spr.texture == null:
			continue
		var path := String(spr.texture.resource_path)
		if path == "" or path.contains("glow"):
			continue
		var r := _sprite_rect(spr)
		box = r if not any else box.merge(r)
		any = true
	return box if any else Rect2(node.global_position - Vector2(8, 8), Vector2(16, 16))


func _expected_paths() -> Array[String]:
	var out: Array[String] = []
	for row in SceneDetails.GROUND_DETAILS:
		out.append(PropCatalog.path_for(String(row[1]), SceneDetails.THEME))
	for row in SceneDetails.HANGING_DETAILS:
		out.append(PropCatalog.path_for(String(row[1]), SceneDetails.THEME))
	return out


## 占位方块必须消失：每件细节都是 PropCatalog 解析出的真实贴图，1x、NEAREST。
func test_scene_details_are_real_catalog_props() -> void:
	var level := await _load_level()
	if level == null:
		return
	var layer := _details(level)
	ok(layer != null, "SceneDetails layer exists")
	if layer == null:
		return
	ok(layer.z_index < 0, "set dressing stays behind the play canvas")
	var placeholders := 0
	for node in LevelSanity._descendants(layer):
		if node is ColorRect or node is Polygon2D:
			placeholders += 1
	eq(placeholders, 0, "no ColorRect / Polygon2D stands in for a detail")
	var expected := _expected_paths()
	eq(layer.get_child_count(), expected.size(), "one node per authored detail")
	var matched: Array[String] = []
	for child in layer.get_children():
		var spr := child as Sprite2D
		ok(spr != null, "%s detail is a Sprite2D" % String(child.name))
		if spr == null:
			continue
		ok(spr.texture != null, "%s has a texture" % String(spr.name))
		if spr.texture == null:
			continue
		matched.append(String(spr.texture.resource_path))
		eq(spr.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "%s is nearest-filtered" % spr.name)
		eq(spr.scale, Vector2.ONE, "%s is drawn at world 1x" % spr.name)
	for path in expected:
		ok(matched.has(path), "detail '%s' is planted" % path.get_file())
	# 墓园族的锈铁残骸必须是派生的 1x 变体，而不是 70px 的光滑灰原图；
	# 骨渣变体还要把 tiles.png 的底板抠掉，否则是一块深色方块。
	for key in ["girder_l", "girder_r", "chain", "bones"]:
		ok(PropCatalog.DECOR.has(key), "'%s' is a catalogued DECOR key" % key)
		var path := PropCatalog.path_for(key, SceneDetails.THEME)
		eq(path, "res://assets/env/props/ground/%s.png" % key,
				"'%s' resolves to its graveyard-family variant" % key)
		ok(ResourceLoader.exists(path), "generated variant exists: %s" % path)
		var tex := load(path) as Texture2D
		ok(tex != null and tex.get_width() <= 40 and tex.get_height() <= 40,
				"'%s' variant is a 1x pixel sprite, not the 70px source" % key)
	level.free()
	await flush(1)


## 角色接地（docs/art-spec.md）：脚点（底边中点）必须落在台面顶上，不悬空。
func test_every_ground_detail_stands_on_a_platform_top() -> void:
	var level := await _load_level()
	if level == null:
		return
	var layer := _details(level)
	if layer == null:
		ok(false, "SceneDetails layer exists")
		return
	var tops := LevelSanity.top_segments(level)
	var grounded := 0
	var hanging := 0
	for child in layer.get_children():
		var spr := child as Sprite2D
		ok(spr != null)
		if spr == null:
			continue
		if spr.get_meta(&"foot_anchor", "") == "top_center":
			hanging += 1
			ok(not spr.is_in_group("grounded"), "%s hangs; it is not a grounded prop" % spr.name)
			ok(spr.has_meta("hang_top"), "%s records its hang point" % spr.name)
			ok(not spr.has_meta("feet"), "%s never fakes a foot point" % spr.name)
			continue
		grounded += 1
		ok(spr.is_in_group("grounded"), "%s is registered as grounded" % spr.name)
		ok(spr.has_meta("feet"), "%s records its foot point" % spr.name)
		if not spr.has_meta("feet"):
			continue
		var feet: Vector2 = spr.get_meta("feet")
		eq(feet, feet.round(), "%s feet are integer pixels" % spr.name)
		ok(LevelSanity.standing_on(tops, feet) != null,
				"%s stands on a platform top (feet %s)" % [spr.name, feet])
		almost(Level01Env.sprite_opaque_bottom_y(spr), feet.y, 1.01,
				"%s opaque pixels sit on its feet" % spr.name)
	eq(grounded, SceneDetails.GROUND_DETAILS.size(), "every ground detail is a grounded prop")
	eq(hanging, SceneDetails.HANGING_DETAILS.size(), "every hanging detail hangs")
	level.free()
	await flush(1)


## 不遮玩法：细节不压台缘（顶面 8px）、不叠既有墓碑线 / 路牌 / 敌人出生位 / 交互物，
## 也不进毒坑两岸的矮唇。
func test_details_keep_off_the_route_and_landmarks() -> void:
	var level := await _load_level()
	if level == null:
		return
	var layer := _details(level)
	if layer == null:
		ok(false, "SceneDetails layer exists")
		return
	# 可站台面的顶缘 8px：踩在台面上可以，压住台缘不行。
	var bands: Array[Rect2] = []
	for seg in LevelSanity.top_segments(level):
		bands.append(Rect2(seg.x0, seg.y, seg.x1 - seg.x0, 8.0))
	# 既有墓碑线（GraveDecor）的贴图占地。
	var decor_spans: Array[Rect2] = []
	for item in Level01Static.PLAY_DECOR:
		var tex := load(String(item[0])) as Texture2D
		if tex == null:
			continue
		var feet: Vector2 = item[1]
		decor_spans.append(Rect2(feet.x, feet.y - float(tex.get_height()),
				float(tex.get_width()), float(tex.get_height())))
	# 路牌牌面（牌子画在玩法层上面，细节不许从牌子后面探头）。
	var boards: Array[Rect2] = []
	for mark in Level01Static.WAYMARKS:
		var feet: Vector2 = mark[0]
		boards.append(Rect2(feet.x - 17.0, feet.y - 35.0, 35.0, 35.0))
	# 交互物实体占地（光晕不算）。
	var landmark_boxes: Array[Rect2] = []
	var landmark_names: Array[String] = []
	for node in level.find_children("*", "Interactable", true, false):
		if node is ToxinPool or node is HookAnchor or node is AtmosphereZone:
			continue
		landmark_boxes.append(_body_aabb(node as Node2D))
		landmark_names.append(String(node.name))
	for child in layer.get_children():
		var spr := child as Sprite2D
		if spr == null:
			continue
		var r := _sprite_rect(spr)
		for i in bands.size():
			ok(not r.intersects(bands[i]), "%s covers a platform top edge (%.0f,%.0f)"
					% [spr.name, bands[i].position.x, bands[i].position.y])
		for i in decor_spans.size():
			ok(not r.intersects(decor_spans[i]), "%s overlaps the grave decor line (%d)" % [spr.name, i])
		for i in boards.size():
			ok(not r.intersects(boards[i]), "%s overlaps a waymark board (%d)" % [spr.name, i])
		for i in _enemy_boxes.size():
			ok(not r.intersects(_enemy_boxes[i]), "%s overlaps an enemy spawn (%d)" % [spr.name, i])
		for i in landmark_boxes.size():
			ok(not r.intersects(landmark_boxes[i]),
					"%s overlaps interactable %s" % [spr.name, landmark_names[i]])
	# 细节之间也不许叠：叠起来就是一块读不懂的色块。
	var rects: Array[Rect2] = []
	for child in layer.get_children():
		var spr := child as Sprite2D
		if spr != null:
			rects.append(_sprite_rect(spr))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			ok(not rects[i].intersects(rects[j]), "details %d and %d overlap" % [i, j])
	level.free()
	await flush(1)


## 光照锚定真实地标：每盏灯都记着它挂在哪个节点上，光池落在地标而不是空处。
func test_lights_are_anchored_to_landmarks() -> void:
	var level := await _load_level()
	if level == null:
		return
	var lighting := level.get_node_or_null("AmbientLighting") as AmbientLighting
	ok(lighting != null, "AmbientLighting is planted")
	if lighting == null:
		return
	ok(lighting.light_count() > 0, "level carries ambience lights")
	ok(lighting.light_count() <= AmbientLighting.MAX_LIGHTS, "light budget respected")
	eq(lighting.light_count(), SceneDetails.LIGHT_ANCHORS.size(), "one light per authored landmark")
	for light in lighting.get_children():
		var world_light := light as WorldLight
		ok(world_light != null, "light is a WorldLight")
		if world_light == null:
			continue
		ok(world_light.texture != null, "%s has a real falloff texture" % world_light.name)
		ok(world_light.enabled, "%s is enabled" % world_light.name)
		eq(world_light.follow, &"authored", "%s is a local authored light" % world_light.name)
		var anchor_path := String(world_light.get_meta(&"anchor_path", ""))
		ok(anchor_path != "", "%s records the landmark it is anchored to" % world_light.name)
		ok(level.get_node_or_null(anchor_path) != null,
				"%s anchors to a real node (%s)" % [world_light.name, anchor_path])
	# 关键地标：灯位必须贴着地标，而不是写死坐标落在空处。
	for pair in [
		["Props/EmberNest", 60.0],
		["Props/ToxinPool", 80.0],
		["Props/Door", 60.0],
		["Props/RustyGate", 60.0],
		["BossGate", 60.0],
		["Props/ForgeHeart", 60.0],
	]:
		var anchor_path := String(pair[0])
		var landmark := level.get_node_or_null(anchor_path) as Node2D
		ok(landmark != null, "%s exists" % anchor_path)
		if landmark == null:
			continue
		var light := _light_for(lighting, anchor_path)
		ok(light != null, "a light is anchored to %s" % anchor_path)
		if light == null:
			continue
		var distance := light.global_position.distance_to(landmark.global_position)
		ok(distance <= float(pair[1]),
				"%s light sits on its landmark (%.1fpx)" % [anchor_path, distance])
	level.free()
	await flush(1)


func _light_for(lighting: AmbientLighting, anchor_path: String) -> WorldLight:
	for light in lighting.get_children():
		var world_light := light as WorldLight
		if world_light != null and String(world_light.get_meta(&"anchor_path", "")) == anchor_path:
			return world_light
	return null


## 没有地标就没有灯：锚定缺失时优雅跳过，绝不退回写死坐标。
func test_lighting_skips_missing_landmarks() -> void:
	var host := Node2D.new()
	add_child(host)
	var lighting := AmbientLighting.create_for_level(host)
	eq(SceneDetails.add_level01_lighting(lighting, host), 0, "no landmarks, no free-floating lights")
	eq(lighting.light_count(), 0, "nothing was added")
	host.free()
	await flush(1)


## 区域覆盖：起点台地 / 毒坑 / 中段攀爬 / 门区各有细节；东翼（Boss 竞技场、炉心）
## 归 1D，1A 的细节全部留在西侧走廊。
func test_layout_covers_regions_west_of_the_nave() -> void:
	var dressed: Array[String] = []
	var rows: Array = []
	rows.append_array(SceneDetails.GROUND_DETAILS)
	rows.append_array(SceneDetails.HANGING_DETAILS)
	for row in rows:
		var region := String(row[0])
		if not dressed.has(region):
			dressed.append(region)
		ok(SceneDetails.ALLOWED_KEYS.has(String(row[1])),
				"'%s' is an allowed Level01 decor key" % String(row[1]))
	for want in ["start_terrace", "toxic_pit", "mid_climb", "gate_approach"]:
		ok(dressed.has(want), "region '%s' is dressed" % want)
	for row in SceneDetails.GROUND_DETAILS:
		ok(float(row[2]) < Level01Static.EAST_FLOOR_X,
				"%s stays west of the nave (arena is 1D's)" % String(row[1]))
	# 手摆表的脚点常量必须和关卡几何一致，否则细节会悬空或埋进土里。
	eq(SceneDetails.GROUND_TOP, Level01Static.GROUND_TOP, "detail ground line matches the level")
	ok(SceneDetails.GROUND_DETAILS.size() >= 8, "the pass dresses the corridor, not a corner")
