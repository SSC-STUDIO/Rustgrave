class_name ThemeBackdrop
extends Node2D
## 章节关卡的背景主题库。每个主题 = 底色 + 若干 Parallax2D 图层 + 整关 CanvasModulate
## 色调 + 室内/室外。室外主题接 Level01 的天空板/云雾/天气/风尘；室内主题只有
## CineFx，没有天气与风。ChapterLayout 调 build(host, theme_id)。
##
## 图层字段：path / scroll / pos / scale / tint / region（可选，只取贴图子矩形）。

const COLUMN_PATH := "res://assets/env/column_big.png"
const CASTLE_INTERIOR := "res://assets/external/gothicvania_patreon/Old-dark-Castle-tileset-Files/PNG/old-dark-castle-interior-background.png"
const GOTHIC_CASTLE := "res://assets/external/gothicvania_patreon/Gothic-Castle-Files/PNG/layers/gothic-castle-background.png"
const TOWN_DIR := "res://assets/external/gothicvania_patreon/night-town-background-files/layers/"
const INDUSTRIAL_DIR := "res://assets/external/oga_parallax/pack/parallax-industrial-pack/layers/"

const THEMES := {
	# 地窟：青黑苔砖、拱窗壁龛（Level02 同款）。
	"undercroft": {
		"indoors": true,
		"void": Color(0.035, 0.07, 0.085),
		"mood": Color(0.66, 0.82, 0.84),
		"layers": [
			{"path": CASTLE_INTERIOR, "scroll": Vector2(0.42, 0.18), "pos": Vector2(0, 48), "scale": 1.0, "tint": Color(0.78, 0.9, 0.9)},
			{"path": COLUMN_PATH, "scroll": Vector2(0.66, 0.3), "pos": Vector2(96, 336 - 171), "scale": 0.9, "tint": Color(0.16, 0.24, 0.25, 0.9), "repeat": 352.0},
		],
	},
	# 熔炉：同一套地窟墙，压成琥珀色；底色偏赭。
	"forge": {
		"indoors": true,
		"void": Color(0.09, 0.04, 0.025),
		"mood": Color(0.95, 0.74, 0.56),
		"layers": [
			{"path": CASTLE_INTERIOR, "scroll": Vector2(0.42, 0.18), "pos": Vector2(0, 48), "scale": 1.0, "tint": Color(1.0, 0.78, 0.6)},
			{"path": COLUMN_PATH, "scroll": Vector2(0.66, 0.3), "pos": Vector2(96, 336 - 171), "scale": 0.9, "tint": Color(0.28, 0.16, 0.1, 0.9), "repeat": 352.0},
		],
	},
	# 圣殿：哥特城堡大厅面板（楼梯、尖窗、石像鬼、烛龛）拼成一条重复的殿墙。
	"cathedral": {
		"indoors": true,
		"void": Color(0.045, 0.04, 0.075),
		"mood": Color(0.72, 0.7, 0.9),
		"layers": [
			{"path": GOTHIC_CASTLE, "scroll": Vector2(0.4, 0.16), "pos": Vector2(0, 110), "scale": 1.25, "tint": Color(0.9, 0.9, 1.0), "region": Rect2(0, 0, 480, 168)},
			{"path": COLUMN_PATH, "scroll": Vector2(0.62, 0.28), "pos": Vector2(220, 336 - 190), "scale": 1.0, "tint": Color(0.2, 0.17, 0.3, 0.9), "repeat": 448.0},
		],
	},
	# 锈城：夜色小镇——天、云、山、林、远屋、近屋。室外，有天气与风。
	"town": {
		"indoors": false,
		"void": Color(0.04, 0.08, 0.09),
		"mood": Color(0.74, 0.82, 0.84),
		"layers": [
			{"path": TOWN_DIR + "night-town-background-sky.png", "scroll": Vector2(0.03, 0.02), "pos": Vector2(0, -40), "scale": 1.8, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-clouds.png", "scroll": Vector2(0.08, 0.03), "pos": Vector2(0, -20), "scale": 1.6, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-mountains.png", "scroll": Vector2(0.16, 0.05), "pos": Vector2(0, -4), "scale": 1.6, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-forest.png", "scroll": Vector2(0.3, 0.08), "pos": Vector2(0, 168), "scale": 1.6, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-far-buildings.png", "scroll": Vector2(0.42, 0.1), "pos": Vector2(0, 200), "scale": 1.6, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-town.png", "scroll": Vector2(0.62, 0.14), "pos": Vector2(0, 178), "scale": 1.6, "tint": Color.WHITE},
		],
	},
	# 锈厂：工业剪影——脚手架、厂房、烟囱。有顶棚，算室内（无雨），暖灰色调。
	"industrial": {
		"indoors": true,
		"void": Color(0.06, 0.06, 0.06),
		"mood": Color(0.82, 0.74, 0.68),
		"layers": [
			{"path": INDUSTRIAL_DIR + "skill-desc_0003_bg.png", "scroll": Vector2(0.04, 0.02), "pos": Vector2(0, 0), "scale": 2.25, "tint": Color(0.9, 0.85, 0.85)},
			{"path": INDUSTRIAL_DIR + "skill-desc_0002_far-buildings.png", "scroll": Vector2(0.18, 0.06), "pos": Vector2(0, 40), "scale": 2.25, "tint": Color(0.75, 0.7, 0.7)},
			{"path": INDUSTRIAL_DIR + "skill-desc_0001_buildings.png", "scroll": Vector2(0.4, 0.1), "pos": Vector2(0, 8), "scale": 2.25, "tint": Color(0.6, 0.55, 0.55)},
		],
	},
}

const BREATH_AMP := 0.03
const BREATH_RATE := 0.35

var _mood: CanvasModulate
var _base_mood := Color.WHITE
var _indoors := true
var _t := 0.0


static func has_theme(theme_id: String) -> bool:
	return THEMES.has(theme_id) or theme_id == "graveyard"


static func is_indoor_theme(theme_id: String) -> bool:
	if theme_id == "graveyard":
		return false
	return bool((THEMES.get(theme_id, {}) as Dictionary).get("indoors", true))


func build(host: Node2D, theme_id: String) -> void:
	if theme_id == "graveyard":
		_build_graveyard(host)
		return
	var theme: Dictionary = THEMES.get(theme_id, THEMES["undercroft"])
	_indoors = bool(theme.get("indoors", true))
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	if backdrop == null:
		backdrop = CanvasLayer.new()
		backdrop.name = "ParallaxBackdrop"
		backdrop.layer = -10
		host.add_child(backdrop)
	backdrop.follow_viewport_enabled = false
	if backdrop.get_node_or_null("Void") == null:
		var void_rect := ColorRect.new()
		void_rect.name = "Void"
		void_rect.color = theme.get("void", Color.BLACK)
		void_rect.position = Vector2(-64, -64)
		void_rect.size = Vector2(PresentationMetrics.WORLD_SIZE) + Vector2(128, 128)
		void_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.add_child(void_rect)
	var i := 0
	for layer_def in theme.get("layers", []):
		_add_layer(backdrop, "Layer%d" % i, layer_def)
		i += 1
	var tint := host.get_node_or_null("MoodTint") as CanvasModulate
	if tint == null:
		tint = CanvasModulate.new()
		tint.name = "MoodTint"
		host.add_child(tint)
	_base_mood = theme.get("mood", Color.WHITE)
	tint.color = _base_mood
	_mood = tint
	if host.get_node_or_null("CineFx") == null:
		var cine := CineFx.new()
		cine.name = "CineFx"
		host.add_child(cine)
	if not _indoors:
		if host.get_node_or_null("WeatherFx") == null:
			var wx := WeatherFx.new()
			wx.name = "WeatherFx"
			host.add_child(wx)
		if host.get_node_or_null("WindFx") == null:
			var wind := WindFx.new()
			wind.name = "WindFx"
			host.add_child(wind)


## Level01's authored sky stack, rebuilt in code, then handed to Level01Parallax
## for clouds / fog / mood / weather / moon.
func _build_graveyard(host: Node2D) -> void:
	_indoors = false
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	if backdrop == null:
		backdrop = CanvasLayer.new()
		backdrop.name = "ParallaxBackdrop"
		backdrop.layer = -10
		backdrop.follow_viewport_enabled = false
		host.add_child(backdrop)
		_add_plate(backdrop, "Far", "res://assets/env/parallax_sky.png", Vector2(0.08, 0.04), Vector2(0, -24), 1.9)
		_add_plate(backdrop, "Mid", "res://assets/env/parallax_mountains.png", Vector2(0.22, 0.06), Vector2(0, 48), 1.7)
		_add_plate(backdrop, "Hills", "res://assets/env/parallax_graveyard.png", Vector2(0.48, 0.1), Vector2(0, 168), 1.85)
	var front := host.get_node_or_null("ParallaxForeground") as CanvasLayer
	if front == null:
		front = CanvasLayer.new()
		front.name = "ParallaxForeground"
		front.layer = 1
		front.follow_viewport_enabled = false
		host.add_child(front)
		_add_plate(front, "Foreground", "res://assets/env/normalized/parallax_foreground_px.png", Vector2(1.22, 0.18), Vector2(0, 352), 1.0, Color(0.16, 0.12, 0.2, 0.78))
	var extras := Level01Parallax.new()
	extras.name = "ParallaxExtras"
	host.add_child(extras)
	extras.build(host)


func _add_plate(parent: Node, plate_name: String, path: String, scroll: Vector2, pos: Vector2, scale_k: float,
		tint: Color = Color.WHITE) -> void:
	if not ResourceLoader.exists(path):
		return
	var layer := Parallax2D.new()
	layer.name = plate_name
	layer.scroll_scale = scroll
	layer.follow_viewport = false
	parent.add_child(layer)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = load(path) as Texture2D
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = pos
	spr.scale = Vector2(scale_k, scale_k)
	spr.modulate = tint
	layer.add_child(spr)
	Level01Parallax.cover_layer(layer)


func _process(delta: float) -> void:
	if _mood == null or not _indoors:
		return
	_t += delta * BREATH_RATE
	var k := 1.0 + sin(_t * TAU) * BREATH_AMP
	_mood.color = Color(_base_mood.r * k, _base_mood.g * k, _base_mood.b * k, 1.0)


func _add_layer(parent: Node, layer_name: String, def: Dictionary) -> Parallax2D:
	var path: String = def.get("path", "")
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var layer := Parallax2D.new()
	layer.name = layer_name
	layer.scroll_scale = def.get("scroll", Vector2(0.5, 0.1))
	layer.follow_viewport = false
	parent.add_child(layer)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = def.get("pos", Vector2.ZERO)
	var k: float = def.get("scale", 1.0)
	spr.scale = Vector2(k, k)
	spr.modulate = def.get("tint", Color.WHITE)
	var region: Rect2 = def.get("region", Rect2())
	if region.has_area():
		spr.region_enabled = true
		spr.region_rect = region
	layer.add_child(spr)
	var repeat: float = def.get("repeat", 0.0)
	if repeat > 0.0:
		layer.repeat_size = Vector2(repeat, 0.0)
		layer.repeat_times = Level01Parallax.copies_for_view(repeat)
	else:
		var tile := (region.size.x if region.has_area() else float(tex.get_width())) * k
		var step := floorf(tile)
		layer.repeat_size = Vector2(step, 0.0)
		layer.repeat_times = Level01Parallax.copies_for_view(step)
	return layer
