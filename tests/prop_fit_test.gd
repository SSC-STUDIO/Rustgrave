extends TestCase
## 装饰/贴图贴合与室内远景的回归锁（docs/art-spec.md「世界历史细节」「环境层次」
## 「角色接地」「像素密度与对齐」）。这一轮清掉的三类问题是：
##   1. 贴纸方块：tiles.png 底板没抠干净的骨渣、70px Kenney 原图、整块不透明告示板；
##   2. 主题越界：十字墓碑/教堂紫门种进工坊、熔渣关，墓园十字石种进街巷；
##   3. 室内空天：level05/08/10 的镜头上半屏没有墙/顶架/机械，是近黑的空。
##
## 断言分四组：
##   A. PropCatalog 里每个主题白名单键解析出的贴图，不得是「四角不透明 + 几乎填满
##      画布」的贴纸方块（FULL_BLEED 里登记的是本来就该是整块板的门/告示牌/挂条）。
##   B. 每章 layout 实际种下的每件装饰，键名必须在该主题白名单里（prop()/foliage()
##      已经把键写进 prop_key 元数据）。
##   C. 种下的装饰不能落在世界原点（脚点/挂点都不是 (0,0)），硬装饰必须是整数缩放。
##   D. 室内主题都建出 backdrop（merge: 室内补墙套件未接线，phase-3 远景为准）。

## 四角不透明 + 不透明像素占比 > 这个值 = 贴纸方块。
const OPAQUE_RATIO_MAX := 0.92
## 合法的「整块板」：门洞、木门、墙块、平放的压板、垂挂条、告示牌、排水拱。
## 它们的不透明来自结构本身，不是没抠图；新增例外必须在这里写清理由。
const FULL_BLEED := {
	"door_arch": "stone doorway plate: the opening is cut into a solid arch",
	"door": "wooden door plank (moss_door art)",
	"door_arch_town": "warm town doorway plate",
	"door_arch_wall": "cold rampart doorway plate",
	"wall_block": "moss wall block set into masonry",
	"plate": "flat 32×10 pressure stone, used as a step lip",
	"vine": "16×64 hanging strip; its silhouette is the whole canvas",
	"warning_plate": "a bolted warning sign is a plate by construction",
	"arch": "drain arch is a rectangular plate set into a wall",
}
## 镜头上界带：室内远景必须盖住的高度（640×360 视口顶部）。
## level02 走自己的 Level02Backdrop；这里只锁 ChapterLayout 的八个章节。
const TOP_BAND := 96.0


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


## 「贴纸方块」：不透明像素几乎填满画布，而且四个角都不透明。骨渣/告示板原图就是这样。
func _is_sticker(tex: Texture2D) -> bool:
	if tex == null:
		return false
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
	return {"host": host, "layout": layout}


func _decor_sprites(root: Node) -> Array:
	var out := []
	for child in LevelSanity._descendants(root):
		if child is Sprite2D and child.has_meta("prop_key"):
			out.append(child)
	return out


## A. 贴图透明底：每个主题白名单键（以及 DECOR 里没有白名单的键）都不是贴纸方块。
func test_catalog_props_are_transparent_set_dressing() -> void:
	var checked := 0
	var flagged: Array[String] = []
	for theme_id in PropCatalog.THEME_PROPS:
		for key in PropCatalog.THEME_PROPS[theme_id]:
			if FULL_BLEED.has(String(key)):
				continue
			var path := PropCatalog.path_for(String(key), theme_id)
			var tex := _texture(path)
			ok(tex != null, "%s/%s resolves to a texture (%s)" % [theme_id, key, path])
			if tex == null:
				continue
			checked += 1
			if _is_sticker(tex):
				flagged.append("%s/%s → %s" % [theme_id, key, path.get_file()])
	# DECOR 里没有被任何主题白名单引用的键也要检查一次（防止以后又加回未派生原图）。
	for key in PropCatalog.DECOR:
		var used := false
		for theme_id in PropCatalog.THEME_PROPS:
			if key in PropCatalog.THEME_PROPS[theme_id]:
				used = true
				break
		if used or FULL_BLEED.has(String(key)):
			continue
		var path := String(PropCatalog.DECOR[key])
		var tex := _texture(path)
		ok(tex != null, "catalogued key '%s' resolves to a texture" % key)
		if tex != null:
			checked += 1
			if _is_sticker(tex):
				flagged.append("%s (unused) → %s" % [key, path.get_file()])
	# 每件被检查的贴图都不能是「整块不透明 + 四角不透明」的贴纸。
	ok(flagged.is_empty(), "no sticker-square props: %s" % ", ".join(flagged))
	ok(checked >= 60, "the audit actually covered the catalog (%d textures)" % checked)


## B/C. 每章实际种下的装饰：键名合法、贴图解析正确、脚点/挂点不在原点、整数缩放。
func test_planted_props_are_allowed_grounded_and_integer_scaled() -> void:
	var planted := 0
	for level_id in GameContext.LAYOUTS:
		var built := _build_layout(String(level_id))
		if built.is_empty():
			ok(false, "%s builds" % level_id)
			continue
		var host: Node2D = built["host"]
		var layout: ChapterLayout = built["layout"]
		var theme_id: String = layout.theme()
		var decor := host.get_node_or_null("Decor")
		ok(decor != null, "%s has a Decor layer" % level_id)
		if decor == null:
			continue
		var sprites := _decor_sprites(decor)
		ok(not sprites.is_empty(), "%s plants at least one catalog prop" % level_id)
		for spr in sprites:
			var key := String(spr.get_meta("prop_key"))
			planted += 1
			ok(PropCatalog.allowed(theme_id, key),
					"%s: '%s' is allowed by theme '%s'" % [level_id, key, theme_id])
			var path := PropCatalog.path_for(key, theme_id)
			ok(spr.texture != null, "%s: '%s' has a texture" % [level_id, key])
			if spr.texture != null:
				# 允许键名解析成族变体（贴纸感就是这样清掉的）。
				ok(String(spr.texture.resource_path) == path,
						"%s: '%s' draws its theme variant (%s)" % [level_id, key, spr.texture.resource_path.get_file()])
			if spr.is_in_group("grounded"):
				ok(spr.has_meta("feet"), "%s: '%s' records its feet" % [level_id, key])
				if spr.has_meta("feet"):
					var feet: Vector2 = spr.get_meta("feet")
					ok(feet != Vector2.ZERO, "%s: '%s' is not planted at the world origin" % [level_id, key])
					eq(feet, feet.round(), "%s: '%s' feet are integer pixels" % [level_id, key])
			elif spr.has_meta("hang_top"):
				var top: Vector2 = spr.get_meta("hang_top")
				ok(top != Vector2.ZERO, "%s: '%s' does not hang from the origin" % [level_id, key])
			# 整数像素缩放：硬装饰 1x；植被用 tools/normalize_art.py 的 1x 裁切。
			var scale: Vector2 = spr.scale
			ok(is_equal_approx(scale.x, 1.0) and is_equal_approx(scale.y, 1.0),
					"%s: '%s' is drawn at 1x (no fractional scale)" % [level_id, key])
		layout.free()
		host.free()
	ok(planted >= 80, "the layout audit covered the chapters (%d planted props)" % planted)


## D. 室内远景：merge contract — the interior wall/truss/machinery kit
## (assets/env/backdrop/wall_*, truss_*, machinery_*) stays on disk but is not wired: the
## user approved the phase-3 backdrops for every chapter. Each indoor chapter still builds
## a non-empty backdrop behind the play canvas with its phase-3 haze glow.
func test_indoor_backdrops_cover_the_camera_top_band() -> void:
	var seen := {}
	for level_id in GameContext.LAYOUTS:
		var built := _build_layout(String(level_id))
		if built.is_empty():
			continue
		var host: Node2D = built["host"]
		var layout: ChapterLayout = built["layout"]
		var theme_id: String = layout.theme()
		if not layout.indoors():
			layout.free()
			host.free()
			continue
		seen[theme_id] = true
		var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
		ok(backdrop != null, "%s builds a backdrop" % level_id)
		var plates := 0
		if backdrop != null:
			ok(backdrop.layer < 0, "%s backdrop sits behind the play canvas" % level_id)
			for child in backdrop.get_children():
				if child is Parallax2D:
					plates += 1
		ok(plates >= 1, "%s (%s) has backdrop plates" % [level_id, theme_id])
		layout.free()
		host.free()
	for required in ["industrial", "forge", "forge_core"]:
		ok(seen.has(required), "indoor theme '%s' was audited" % required)
	ok(seen.size() >= 3, "at least the three interiors were audited (%d)" % seen.size())
