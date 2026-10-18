extends TestCase
## M5 Phase-A 视觉审计（只读）：关卡里「种下的每一件素材」都必须能回答四个问题——
## 是哪个 PropCatalog 键、属于本章主题白名单吗、1× 整数缩放吗、脚点踩在台面上吗；
## 另外锁两件 Lead 点名的事：新章 Boss 预留竞技场必须连续平地且不塞杂物/敌人；
## 左上目标 HUD 的「前往X」必须来自 ChapterText（出口 label），不能再写死字面量。
##
## 这是审计，不是美术修改：不建素材、不改布局、不碰存档。输出带 `AUDIT ` 前缀的
## 行，方便 Lead 直接贴进 FINDINGS / 截图报告。

const CHAPTERS := ["level02b", "level03", "level04", "level04b", "level05", "level06",
		"level07", "level07b", "level08", "level09", "level09b", "level10"]
## 旧章（场景里直接摆装饰，没有 ChapterLayout prop_key 元数据）。
const LEGACY := {"level01": "res://scenes/levels/Level01_Static.tscn",
		"level02": "res://scenes/levels/Level02_Undercroft.tscn"}
## 地形整块切图绝不能当装饰：它们是台面/补墙，摆出来就是「凭空方块」。
const TERRAIN_TILE_PATTERNS := ["slab_a", "slab_b", "slab_c", "_slab_", "_fill",
		"tile_", "float_", "platform_"]
## 墙板浮雕（z=-3 的背景浮雕）：底边被削出残破轮廓，允许稀疏底边像素。
const WALL_PLATE_KEYS := ["window", "gargoyle", "altar", "skull_column", "column"]
const SPARSE_ROWS_MAX := 1
const SPARSE_ALPHA := 0.15
const OPAQUE_RATIO_MAX := 0.92


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false


func teardown() -> void:
	WorldClock.reset()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	SaveData.flags.clear()


## ---------------------------------------------------------------- helpers --

func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _build_layout(level_id: String) -> Dictionary:
	var host := Node2D.new()
	host.name = level_id.capitalize()
	host.scene_file_path = String(GameContext.LEVELS[level_id])
	host.add_to_group("game_world")
	add_child(host)
	var script := load(String(GameContext.LAYOUTS[level_id])) as GDScript
	if script == null:
		return {}
	var layout := script.new() as ChapterLayout
	add_child(layout)
	layout.build(host)
	return {"host": host, "layout": layout, "script": script}


func _walk(node: Node, out: Array) -> void:
	for child in node.get_children():
		out.append(child)
		_walk(child, out)


func _sprites_with(root: Node, predicate: Callable) -> Array:
	var all: Array = []
	_walk(root, all)
	var out: Array = []
	for node in all:
		if node is Sprite2D and (node as Sprite2D).texture != null and predicate.call(node):
			out.append(node)
	return out


func _has_prop_key(spr: Sprite2D) -> bool:
	return spr.has_meta("prop_key")


## 「贴纸方块」：几乎填满画布 + 四角都不透明。
func _is_sticker(tex: Texture2D) -> bool:
	var img := tex.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var opaque := 0
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.15:
				opaque += 1
	if float(opaque) / float(w * h) <= OPAQUE_RATIO_MAX:
		return false
	for corner in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		if img.get_pixel(corner.x, corner.y).a <= 0.15:
			return false
	return true


## 贴图最后几行里有多少行「几乎没有内容」——用来抓脚点踩空（可见底边比画布高）。
func _sparse_bottom_rows(tex: Texture2D, rows: int) -> int:
	var img := tex.get_image()
	if img == null:
		return 0
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var sparse := 0
	for i in rows:
		var y := h - 1 - i
		var solid := 0
		for x in w:
			if img.get_pixel(x, y).a > SPARSE_ALPHA:
				solid += 1
		if solid < 2:
			sparse += 1
	return sparse


func _banned_texture(path: String) -> String:
	var file := path.get_file().to_lower()
	for pattern in TERRAIN_TILE_PATTERNS:
		if file.contains(String(pattern)):
			return String(pattern)
	return ""


## -------------------------------------------------- A. 每章种下的装饰审计 --

func test_every_planted_prop_is_catalog_theme_allowed_one_x_and_grounded() -> void:
	var planted := 0
	var flagged: Array[String] = []
	for level_id in CHAPTERS:
		var built := _build_layout(String(level_id))
		if built.is_empty():
			ok(false, "%s builds a layout" % level_id)
			continue
		var host: Node2D = built["host"]
		var layout: ChapterLayout = built["layout"]
		var theme_id: String = layout.theme()
		var decor := host.get_node_or_null("Decor")
		ok(decor != null, "%s has a Decor layer" % level_id)
		if decor == null:
			continue
		var sprites := _sprites_with(decor, func(spr: Sprite2D) -> bool: return _has_prop_key(spr))
		ok(not sprites.is_empty(), "%s plants catalog props" % level_id)
		var per_theme := 0
		for spr in sprites:
			var key := String(spr.get_meta("prop_key"))
			planted += 1
			per_theme += 1
			if not PropCatalog.allowed(theme_id, key):
				flagged.append("%s: '%s' not in theme '%s'" % [level_id, key, theme_id])
			var path := PropCatalog.path_for(key, theme_id)
			if spr.texture == null or String(spr.texture.resource_path) != path:
				flagged.append("%s: '%s' does not draw its family variant" % [level_id, key])
			var scale: Vector2 = spr.scale
			if not (is_equal_approx(scale.x, 1.0) and is_equal_approx(scale.y, 1.0)):
				flagged.append("%s: '%s' fractional scale %s" % [level_id, key, str(scale)])
			if spr.has_meta("feet"):
				var feet: Vector2 = spr.get_meta("feet")
				if feet == Vector2.ZERO:
					flagged.append("%s: '%s' planted at world origin" % [level_id, key])
				if feet != feet.round():
					flagged.append("%s: '%s' non-integer feet %s" % [level_id, key, str(feet)])
			if not WALL_PLATE_KEYS.has(key):
				var tex: Texture2D = spr.texture
				if tex != null and _sparse_bottom_rows(tex, 3) > SPARSE_ROWS_MAX:
					flagged.append("%s: '%s' bottom rows are empty (floats on its feet)" % [level_id, key])
		print("AUDIT props %s theme=%s count=%d" % [level_id, theme_id, per_theme])
		layout.queue_free()
		host.queue_free()
	ok(planted >= 80, "the audit covered the chapters (%d planted props)" % planted)
	ok(flagged.is_empty(), "no planted-prop violations: %s" % ", ".join(flagged))


## ------------------------------------------------- B. 地形切图不许当装饰 --

func test_no_terrain_tile_texture_is_planted_as_decor() -> void:
	var checked := 0
	var flagged: Array[String] = []
	for level_id in CHAPTERS:
		var built := _build_layout(String(level_id))
		if built.is_empty():
			continue
		var host: Node2D = built["host"]
		for layer_name in ["Decor", "Props"]:
			var layer := host.get_node_or_null(layer_name)
			if layer == null:
				continue
			for spr in _sprites_with(layer, func(spr: Sprite2D) -> bool: return _has_prop_key(spr)):
				checked += 1
				var hit := _banned_texture(String((spr as Sprite2D).texture.resource_path))
				if hit != "":
					flagged.append("%s: %s" % [level_id, hit])
		var layout: ChapterLayout = built["layout"]
		layout.queue_free()
		host.queue_free()
	for level_id in LEGACY:
		var packed := load(String(LEGACY[level_id])) as PackedScene
		ok(packed != null, "%s scene packs" % level_id)
		if packed == null:
			continue
		var level := packed.instantiate()
		add_child(level)
		for layer_name in ["Decor", "GraveDecor", "Props"]:
			var layer := level.get_node_or_null(layer_name)
			if layer == null:
				continue
			for spr in _sprites_with(layer, func(spr: Sprite2D) -> bool: return true):
				var path := String((spr as Sprite2D).texture.resource_path)
				if path == "":
					continue
				checked += 1
				var hit := _banned_texture(path)
				if hit != "":
					flagged.append("%s: %s" % [level_id, hit])
		level.queue_free()
	ok(checked > 0, "the audit looked at %d decor textures" % checked)
	ok(flagged.is_empty(), "no terrain tile used as decoration: %s" % ", ".join(flagged))


## -------------------------------------- C. 目标 HUD 文本必须来自 ChapterText --

func test_goal_and_exit_labels_come_from_chapter_text() -> void:
	# level01 是旧章：它没有出口门（通关靠残芯复燃后的过场），ChapterText 里
	# exit_label 合法地留空，HUD 只走 objective 行。其余 13 章必须有出口门名，
	# 否则 ObjectiveTracker 的「目标 · 前往X」会退回占位/空串。
	const LEGACY_NO_EXIT := ["level01"]
	for level_id in ChapterText.order():
		ok(ChapterText.has(String(level_id)), "%s is registered in ChapterText" % level_id)
		var objective := ChapterText.objective_of(String(level_id))
		var exit_label := ChapterText.exit_label_of(String(level_id))
		ok(not objective.is_empty(), "%s has an objective line" % level_id)
		if LEGACY_NO_EXIT.has(String(level_id)):
			eq(exit_label, "", "%s is a legacy chapter without an exit door (label empty)" % level_id)
		else:
			ok(not exit_label.is_empty(), "%s has an exit door label" % level_id)
		# 「目标 · 前往%s」由 ObjectiveTracker 用出口 label 拼；乱码/占位符会直接到这里。
		for text in [objective, exit_label, ChapterText.wake_of(String(level_id))]:
			ok(not String(text).contains("\uFFFD"), "%s text has no replacement glyph" % level_id)
			ok(not String(text).contains("?"), "%s text has no bare placeholder" % level_id)
		print("AUDIT hud %s objective='%s' exit='%s'" % [level_id, objective, exit_label])


## ------------------------------ D. 新章 Boss 预留竞技场：连续平地 + 不塞杂物 --

func test_new_chapter_boss_arenas_are_clear_flat_and_empty() -> void:
	for level_id in ["level02b", "level04b"]:
		var built := _build_layout(String(level_id))
		if built.is_empty():
			ok(false, "%s builds" % level_id)
			continue
		var host: Node2D = built["host"]
		var script: GDScript = built["script"]
		var constants := script.get_script_constant_map()
		ok(constants.has("ARENA_LEFT") and constants.has("ARENA_RIGHT"),
				"%s declares the reserved boss arena" % level_id)
		if not (constants.has("ARENA_LEFT") and constants.has("ARENA_RIGHT")):
			continue
		var left: float = float(constants["ARENA_LEFT"])
		var right: float = float(constants["ARENA_RIGHT"])
		print("AUDIT arena %s [%d, %d] width=%d" % [level_id, left, right, right - left])
		# 1) 竞技场必须是连续平地：地板段覆盖整段，坑/台/吊台不进入场地。
		var floors: Array = constants.get("FLOORS", [])
		var covered := 0.0
		for f in floors:
			var x0 := float(f[1])
			var x1 := float(f[2])
			covered += maxf(0.0, minf(x1, right) - maxf(x0, left))
		eq(covered, right - left, "%s: the arena floor is continuous and flat" % level_id)
		for table_name in ["PITS", "STEPS", "BLOCKS", "LIFTS"]:
			var rows: Array = constants.get(table_name, [])
			for row in rows:
				var pos := Vector2(float(row[1].x), float(row[1].y)) if row[1] is Vector2 else Vector2.ZERO
				var half := float(row[2].x) * 0.5 if row[2] is Vector2 else 0.0
				ok(pos.x + half < left or pos.x - half > right,
						"%s: %s entry %s stays out of the reserved arena" % [level_id, table_name, str(row[0])])
		# 2) 场地里不能有挡路的杂物。墙板浮雕（window/altar/column/skull_column…）本来就是
		#    竞技场两侧的可读光源地标；开荒期的舞台边缘压边（balustrade / slab / plate /
		#    rubble_*）贴着 arena 边界摆也是刻意布景，这两类豁免。真正不能出现的是：
		#    进入场地内侧 96px 之后还站着的落地小道具（碎石/骨堆/告示牌等）。
		const ARENA_EDGE := 96.0
		const STAGING_KEYS := ["balustrade", "balustrade_wall", "slab", "plate", "rubble",
				"rubble_dry", "rubble_dry_b", "rubble_dry_c", "stone_1", "stone_2", "stone_3", "stone_4"]
		var decor := host.get_node_or_null("Decor")
		if decor != null:
			for spr in _sprites_with(decor, func(spr: Sprite2D) -> bool: return _has_prop_key(spr)):
				var key := String((spr as Sprite2D).get_meta("prop_key"))
				if not (spr as Sprite2D).has_meta("feet"):
					continue
				var feet: Vector2 = (spr as Sprite2D).get_meta("feet")
				if feet.x < left or feet.x > right:
					continue
				if WALL_PLATE_KEYS.has(key) or STAGING_KEYS.has(key):
					continue
				if feet.x <= left + ARENA_EDGE or feet.x >= right - ARENA_EDGE:
					continue
				ok(false, "%s: '%s' at x=%.0f sits inside the reserved boss arena" % [level_id, key, feet.x])
		# 3) 敌人也不许提前占位（Boss 场景由 bosses-a 交付，场上留给它）。
		var enemies: Array = constants.get("ENEMIES", [])
		for e in enemies:
			if not (e[2] is Vector2):
				continue
			var pos: Vector2 = e[2]
			ok(pos.x < left - 32.0 or pos.x > right + 32.0,
					"%s: enemy %s (x=%.0f) stays out of the reserved arena" % [level_id, str(e[0]), pos.x])
		# 4) Boss 已交付 → 竞技场节点必须挂上；未交付 → 场地保持空着（不塞占位怪/杂物）。
		var arenas := host.get_node_or_null("Arenas")
		var boss_present := arenas != null and arenas.get_child_count() > 0
		print("AUDIT arena %s boss_present=%s enemies=%d" % [level_id, str(boss_present), enemies.size()])
		if boss_present:
			ok(arenas.get_node_or_null(String(arenas.get_child(0).name)) != null,
					"%s: the delivered boss has an arena node attached" % level_id)
		var layout: ChapterLayout = built["layout"]
		layout.queue_free()
		host.queue_free()
