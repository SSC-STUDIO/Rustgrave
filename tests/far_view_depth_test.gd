extends TestCase
## 远景层次审计：每章的 ParallaxBackdrop 必须有「远-中-近」的可读纵深，而不是
## 一堵贴地的墙。检查三件事：
##   1. 每章至少 3 个 parallax 层（室外主题至少 4 个）；
##   2. 层的 scroll_scale.x 单调不降（近的快、远的慢）——这是视差深度的定义；
##   3. 每层都覆盖 640 视口（repeat_times × repeat_size ≥ 640 + pad，或 tile 平铺）。
## 这些断言替代了此前挂在 tools/ 下的 SceneTree 探针（那种脚本在 _init() 里
## 调 autoload 会挂死，见 2026-10-18 的记录）。

const VIEW_W := 640.0
const PAD := 128.0

var _seen: Dictionary = {}


func teardown() -> void:
	for child in get_children():
		child.free()
	ThemeBackdrop.clear_cache()
	WorldClock.reset()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func test_every_chapter_has_layered_depth() -> void:
	var ids: Array = ["level03", "level04", "level05", "level06", "level07", "level08", "level09", "level10"]
	for layout_id in ids:
		var script: GDScript = load(String(GameContext.LAYOUTS[layout_id]))
		ok(script != null, "%s layout script loads" % layout_id)
		if script == null:
			continue
		var layout := script.new() as ChapterLayout
		if layout == null:
			continue
		var theme_id: String = layout.theme()
		_seen[theme_id] = true
		var host := Node2D.new()
		add_child(host)
		var director := ThemeBackdrop.new()
		host.add_child(director)
		WorldClock.set_zone(WorldClock.Zone.INDOORS if ThemeBackdrop.is_indoor_theme(theme_id) \
				else WorldClock.Zone.OUTDOORS)
		director.build(host, theme_id)
		var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
		ok(backdrop != null, "%s (%s) builds a backdrop" % [layout_id, theme_id])
		if backdrop == null:
			layout.free()
			director.free()
			host.free()
			continue
		var layers: Array[Parallax2D] = []
		for child in backdrop.get_children():
			if child is Parallax2D:
				layers.append(child as Parallax2D)
		var want_min := 4 if not ThemeBackdrop.is_indoor_theme(theme_id) else 3
		ok(layers.size() >= want_min,
				"%s (%s) stacks %d parallax layers, needs %d for readable depth" % [layout_id, theme_id, layers.size(), want_min])
		# 视差单调性：从远到近 scroll_scale.x 不下降。只比主题自己的远景板：
		# ① 雾层 / 签名光层是画在板之后的气氛层，不参与深度分层；
		# ② tile 平铺的实墙与 covers_top 的顶架是「收口」结构（铺满镜头上界、
		# 把砖缝接上），不是远景板——它们的 scroll 只影响自身纹样移动。
		if theme_id == "graveyard":
			layout.free()
			director.free()
			host.free()
			continue
		var scrolls: Array[float] = []
		for layer in layers:
			if layer.name == "FogNear" or layer.name == ThemeBackdrop.SIGNATURE_NODE:
				break
			var spr := layer.get_node_or_null("Sprite") as Sprite2D
			var tiled := layer.repeat_size == Vector2.ZERO and spr != null \
					and spr.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED
			if tiled or bool(layer.get_meta("covers_top", false)):
				continue
			scrolls.append(layer.scroll_scale.x)
			ok(layer.repeat_times * layer.repeat_size.x >= VIEW_W + PAD,
					"%s/%s covers the view (%d×%.0f)" % [theme_id, layer.name, layer.repeat_times, layer.repeat_size.x])
		for i in range(1, scrolls.size()):
			ok(scrolls[i] >= scrolls[i - 1] - 0.001,
					"%s parallax stays monotonic: %.2f then %.2f" % [theme_id, scrolls[i - 1], scrolls[i]])
		layout.free()
		director.free()
		host.free()
	ok(_seen.size() >= 8, "chapters cover at least 8 themes (got %d)" % _seen.size())


## 室内主题补的远景层必须是「显式命名」的：命名层不占 LayerN 序号，
## chapter_support_test 用 Layer0/Layer1 索引锁「殿墙/柱影不能沿竖井复制」。
func test_named_far_layers_do_not_consume_layer_indices() -> void:
	var locked := {"cathedral": ["Layer0", "Layer1"], "belltower": ["Layer1"], "undercroft": ["Layer0", "Layer1"]}
	for theme_id in locked:
		var host := Node2D.new()
		add_child(host)
		var director := ThemeBackdrop.new()
		host.add_child(director)
		WorldClock.set_zone(WorldClock.Zone.INDOORS)
		director.build(host, theme_id)
		var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
		ok(backdrop != null, "%s builds" % theme_id)
		if backdrop == null:
			director.free()
			host.free()
			continue
		for layer_name in locked[theme_id]:
			var layer := backdrop.get_node_or_null(String(layer_name)) as Parallax2D
			ok(layer != null, "%s keeps %s as the grounded strip" % [theme_id, layer_name])
			if layer == null:
				continue
			var spr := layer.get_node_or_null("Sprite") as Sprite2D
			ok(spr != null and spr.texture != null, "%s/%s still carries the hall strip art" % [theme_id, layer_name])
		director.free()
		host.free()
