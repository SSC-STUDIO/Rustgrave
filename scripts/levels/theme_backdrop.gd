class_name ThemeBackdrop
extends Node2D
## 章节关卡的背景主题库。每个主题 = 底色 + 若干 Parallax2D 图层 + 整关 CanvasModulate
## 色调 + 室内/室外。室外主题接 Level01 的天空板/云雾/天气/风尘；室内主题只有
## CineFx，没有天气与风。ChapterLayout 调 build(host, theme_id)。
##
## 图层字段：path / scroll / pos / scale / tint / region（可选，只取贴图子矩形）。
##
## Prop packs must stay with their theme (see ChapterLayout.THEME_PROPS):
##   graveyard  — cemetery foliage / stones / rails (no bg_wall_torch, no cathedral plates)
##   undercroft — moss brick / arches / vines
##   cathedral  — gothic columns / windows / gargoyles / altar / skull columns
##   town       — rails / dry rubble / door arches (no torch slabs outdoors)
##   industrial — plates / slabs / dry rubble / optional rust-tinted vine cables
##   forge      — same dry-stone set, brick hearths instead of torch plates
##   forge_core — Level10: altar / column / skull column setpieces
##   belltower  — cathedral plates on castle brick
##   ramparts   — rails / arches / rubble on the wall top
## Do not copy indoor hall/column strips up tall shafts (see build()).

const COLUMN_PATH := "res://assets/env/column_big_cut.png"
const CASTLE_INTERIOR := "res://assets/external/gothicvania_patreon/Old-dark-Castle-tileset-Files/PNG/old-dark-castle-interior-background.png"
const GOTHIC_CASTLE := "res://assets/external/gothicvania_patreon/Gothic-Castle-Files/PNG/layers/gothic-castle-background.png"
const TOWN_DIR := "res://assets/external/gothicvania_patreon/night-town-background-files/layers/"
const INDUSTRIAL_DIR := "res://assets/external/oga_parallax/pack/parallax-industrial-pack/layers/"
## Gradient-mapped copies from tools/gen_theme_tiles.py: chapters that share a
## pack still get their own sky.
const BACKDROP_DIR := "res://assets/env/backdrop/"

const THEMES := {
	# 地窟：青黑苔砖、拱窗壁龛（Level02 同款）。
	"undercroft": {
		"look": {"far": 0.6, "near": 0.72, "glow": Color(0.45, 0.85, 0.75, 0.06), "glow_stops": "centre", "top_light": Color(0.78, 1.0, 0.82, 0.3)},
		"indoors": true,
		"void": Color(0.035, 0.07, 0.085),
		"mood": Color(0.66, 0.82, 0.84),
		"layers": [
			{"path": CASTLE_INTERIOR, "scroll": Vector2(0.42, 0.18), "pos": Vector2(0, 48), "scale": 1.0, "tint": Color(0.78, 0.9, 0.9)},
			{"path": COLUMN_PATH, "scroll": Vector2(0.66, 0.3), "pos": Vector2(96, 336 - 171), "scale": 0.9, "tint": Color(0.16, 0.24, 0.25, 0.9), "repeat": 352.0},
		],
	},
	# 熔渣深渊：同一套工业剪影，离线映射成炉口的红光（天在下面烧，不在上面亮）。
	# 和工坊（industrial）同包，但工坊是灰绿的冷车间，这里是渣海。
	"forge": {
		"look": {"far": 0.74, "near": 0.86, "glow": Color(1.0, 0.42, 0.12, 0.3), "glow_stops": "bottom", "top_light": Color(1.0, 0.62, 0.3, 0.42)},
		"indoors": true,
		"void": Color(0.07, 0.02, 0.015),
		"mood": Color(1.0, 0.8, 0.66),
		"layers": [
			{"path": BACKDROP_DIR + "forge_sky.png", "scroll": Vector2(0.04, 0.02), "pos": Vector2(0, 0), "scale": 2.25, "tint": Color.WHITE},
			{"path": BACKDROP_DIR + "forge_far.png", "scroll": Vector2(0.18, 0.06), "pos": Vector2(0, 40), "scale": 2.25, "tint": Color.WHITE},
			{"path": BACKDROP_DIR + "forge_mid.png", "scroll": Vector2(0.4, 0.1), "pos": Vector2(0, 8), "scale": 2.25, "tint": Color.WHITE},
			{"path": BACKDROP_DIR + "forge_near.png", "scroll": Vector2(0.62, 0.14), "pos": Vector2(0, 120), "scale": 2.1, "tint": Color(1, 1, 1, 0.9)},
		],
	},
	# 炉心深处：地窟的拱窗内景烧成暗红——终关是一座被火从里面舔过的殿。
	"forge_core": {
		"look": {"far": 0.62, "near": 0.74, "glow": Color(1.0, 0.24, 0.2, 0.07), "glow_stops": "centre", "top_light": Color(1.0, 0.52, 0.4, 0.4)},
		"indoors": true,
		"void": Color(0.05, 0.012, 0.016),
		"mood": Color(1.0, 0.84, 0.8),
		"layers": [
			{"path": BACKDROP_DIR + "core_hall.png", "scroll": Vector2(0.42, 0.18), "pos": Vector2(0, 48), "scale": 1.0, "tint": Color.WHITE},
			{"path": COLUMN_PATH, "scroll": Vector2(0.66, 0.3), "pos": Vector2(96, 336 - 171), "scale": 0.9, "tint": Color(0.3, 0.08, 0.07, 0.92), "repeat": 352.0},
		],
	},
	# 圣殿：哥特城堡大厅面板（楼梯、尖窗、石像鬼、烛龛）拼成一条重复的殿墙。
	# 冷石殿：板岩青灰石，暖光只来自烛台（不是第一章的锈红、第八章的炉橙，也不再是薰衣草紫）。
	"cathedral": {
		"look": {"far": 0.8, "near": 0.86, "glow": Color(0.6, 0.7, 0.95, 0.05), "glow_stops": "top", "top_light": Color(1.0, 0.84, 0.58, 0.32)},
		"indoors": true,
		"void": Color(0.035, 0.04, 0.05),
		"mood": Color(0.84, 0.88, 0.96),
		"layers": [
			{"path": GOTHIC_CASTLE, "scroll": Vector2(0.4, 0.16), "pos": Vector2(0, 110), "scale": 1.25, "tint": Color.WHITE, "region": Rect2(0, 0, 480, 168)},
			{"path": COLUMN_PATH, "scroll": Vector2(0.62, 0.28), "pos": Vector2(220, 336 - 190), "scale": 1.0, "tint": Color(0.14, 0.16, 0.2, 0.9), "repeat": 448.0},
		],
		"grade": {
			"ramp": [Color("#08090c"), Color("#1a1e25"), Color("#363d47"), Color("#6f7a86"), Color("#d3dade")],
			"plates": {"Layer0": 0.85, "Layer1": 0.8},
			"values": {"Layer0": 0.95, "Layer1": 1.0},
			"play_ramp": [Color("#0d0e11"), Color("#2b3037"), Color("#555d66"), Color("#a3a9ab"), Color("#f4eee0")],
			"play_amount": 0.7,
		},
	},
	# 钟楼：竖井。橄榄色城砖墙双向平铺爬满整座塔（没有地面线，抬多高都不穿帮），
	# 箭窗透冷光；地面一层再压一条殿墙。
	"belltower": {
		"look": {"far": 0.85, "near": 0.9, "glow": Color(0.55, 0.62, 0.95, 0.06), "glow_stops": "top", "top_light": Color(1.0, 0.86, 0.5, 0.42)},
		"indoors": true,
		"void": Color(0.03, 0.03, 0.04),
		# Lifted from 0.78 / 0.9: the shaft read as near-black (phase-2 peeks).
		"mood": Color(0.86, 0.86, 0.97),
		"layers": [
			{"path": BACKDROP_DIR + "tower_wall.png", "scroll": Vector2(0.3, 0.3), "pos": Vector2(0, 0), "scale": 1.0, "tint": Color.WHITE, "tile": true},
			{"path": COLUMN_PATH, "scroll": Vector2(0.62, 0.28), "pos": Vector2(220, 336 - 190), "scale": 1.0, "tint": Color(0.16, 0.15, 0.2, 0.9), "repeat": 448.0},
		],
	},
	# 锈城城墙：站在墙顶往下看城。青灰云、远山，城和钟塔缩在脚下的雾里。
	"ramparts": {
		"look": {"far": 0.74, "near": 0.84, "glow": Color(0.95, 0.88, 0.7, 0.16), "glow_stops": "horizon", "top_light": Color(0.95, 0.95, 0.86, 0.32)},
		"indoors": false,
		"void": Color(0.06, 0.1, 0.11),
		"mood": Color(0.8, 0.86, 0.86),
		"layers": [
			{"path": TOWN_DIR + "night-town-background-sky.png", "scroll": Vector2(0.03, 0.02), "pos": Vector2(0, -40), "scale": 1.8, "tint": Color(0.8, 0.9, 0.92)},
			{"path": BACKDROP_DIR + "wall_clouds.png", "scroll": Vector2(0.07, 0.03), "pos": Vector2(0, -60), "scale": 2.0, "tint": Color(1, 1, 1, 0.85)},
			{"path": TOWN_DIR + "night-town-background-mountains.png", "scroll": Vector2(0.14, 0.05), "pos": Vector2(0, 20), "scale": 1.6, "tint": Color(0.82, 0.9, 0.9)},
			{"path": BACKDROP_DIR + "wall_town.png", "scroll": Vector2(0.3, 0.08), "pos": Vector2(0, 160), "scale": 2.0, "tint": Color.WHITE},
		],
	},
	# 锈城：夜色小镇——天、云、山、林、远屋、近屋。室外，有天气与风。
	"town": {
		"look": {"far": 0.72, "near": 0.8, "glow": Color(0.4, 0.7, 0.75, 0.2), "glow_stops": "horizon", "top_light": Color(1.0, 0.82, 0.55, 0.38)},
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
		"look": {"far": 0.72, "near": 0.8, "glow": Color(0.65, 0.85, 0.6, 0.16), "glow_stops": "top", "top_light": Color(1.0, 0.66, 0.38, 0.38)},
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

## Level06 night graveyard reuses chapter 1's sky stack; this palette makes it a cold,
## moonlit place (bone, ash, fog-teal) instead of a second rust dusk.
const NIGHT_GRAVEYARD := {
	"ramp": [Color("#080b10"), Color("#18222c"), Color("#2f4250"), Color("#68848c"), Color("#d2e0da")],
	"plates": {"Far": 0.9, "Mid": 0.9, "Hills": 0.85, "SkyCloudsHigh": 0.85, "SkyCloudsLow": 0.85, "Foreground": 0.8},
	"values": {"Far": 1.0, "Mid": 0.82, "Hills": 0.7, "SkyCloudsHigh": 0.95, "SkyCloudsLow": 0.9, "Foreground": 0.8},
	"warm": Color(0.86, 1.0, 1.12),
	"cloud_tint": Color(1.0, 1.1, 1.18),
	"veil": Color(0.74, 0.82, 0.84),
	"sil_tint": Color(0.08, 0.11, 0.13, 0.95),
	"play_ramp": [Color("#0a0c0e"), Color("#1d2526"), Color("#3c4a47"), Color("#7e8f86"), Color("#dfe2d2")],
	"play_amount": 0.72,
	"play_value": 1.0,
	# Cold moon haze over the horizon and a cold rim on ledge tops (not chapter 1's ember).
	"glow": Color(0.55, 0.72, 0.9, 0.22),
	"top_light": Color(0.75, 0.86, 0.95, 0.3),
}
## Play-layer folders a ChapterLayout builds (see ChapterLayout.group / decor_layer).
const PLAY_FOLDERS := ["Platforms", "Decor"]

const BREATH_AMP := 0.03
const BREATH_RATE := 0.35

var _mood: CanvasModulate
var _base_mood := Color.WHITE
var _indoors := true
var _t := 0.0


## WorldAtmosphere darkens the backdrop CanvasLayer by this step below the play canvas
## (shared constant; tests/world_atmosphere_test.gd pins it).
const BACKDROP_SUBORDINATE := 0.24


static func has_theme(theme_id: String) -> bool:
	return THEMES.has(theme_id) or theme_id == "graveyard"


static func is_indoor_theme(theme_id: String) -> bool:
	if theme_id == "graveyard":
		return false
	return bool((THEMES.get(theme_id, {}) as Dictionary).get("indoors", true))


func build(host: Node2D, theme_id: String, _camera_top: float = -48.0) -> void:
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
		# 显式 "name" 的层不占 LayerN 序号（与 cursor/theme-fit-level-props 的约定一致）。
		var layer_name := String((layer_def as Dictionary).get("name", ""))
		if layer_name == "":
			layer_name = "Layer%d" % i
			i += 1
		_add_layer(backdrop, layer_name, layer_def)
	var grade: Dictionary = theme.get("grade", {})
	if not grade.is_empty():
		Level01Parallax.grade_plates(backdrop, grade)
		Level01Parallax.grade_play_layer(host, grade, PLAY_FOLDERS)
	ChapterLook.apply(host, backdrop, theme.get("look", {}))
	# Do not copy these strips up a tall shaft. Each plate is a scene with its
	# ground line on the bottom edge (hall at y=320, columns at y=336). A copy
	# shifted by the texture height plants that same wall in the air.
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
	# Foreground CanvasLayer 只留给 GroundFog / FogVeil（贴地雾与雾幕）。离地最近的
	# 「幕前草」剪影（Foreground / ForegroundFringe）在墓园主题里**整段删除**：
	# 它们的屏幕 y 贴在视口底边（约 347–352），而横截面镜头的底边就是地面平台的土壤
	# 剖面；深色草影扫过亮土会被读成「土里长出来的移动植物」（2026 用户复查）。
	# 近景层次交给平台草皮顶和 NearSilhouette 树丛。
	var front := host.get_node_or_null("ParallaxForeground") as CanvasLayer
	if front == null:
		front = CanvasLayer.new()
		front.name = "ParallaxForeground"
		front.layer = 1
		front.follow_viewport_enabled = false
		host.add_child(front)
	var extras := Level01Parallax.new()
	extras.name = "ParallaxExtras"
	extras.palette = NIGHT_GRAVEYARD
	host.add_child(extras)
	extras.build(host)
	Level01Parallax.grade_play_layer(host, NIGHT_GRAVEYARD, PLAY_FOLDERS)
	ChapterLook._finish_deferred.call_deferred(host.get_instance_id(), Color(0, 0, 0, 0), NIGHT_GRAVEYARD)


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
	spr.texture = DensityTextures.load_texture(path)
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
	var tex := DensityTextures.load_texture(path)
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
	if bool(def.get("tile", false)):
		# Plain wall texture for a tall shaft: one oversized sprite that tiles on both
		# axes by texture repeat. Parallax2D's own repeat only covers a strip of the
		# view on the second axis. The sprite spans every camera position of every chapter
		# (scroll shifts it by at most travel * scroll_scale) plus a view of margin, so
		# the wall can never run off the top of a tall shaft (the old fixed
		# `-18 * cell` offset left the top of the bell tower black).
		var cell := Vector2(tex.get_size()) * k
		var span := Vector2(cell.x * ceilf(6000.0 / cell.x), cell.y * ceilf(4200.0 / cell.y))
		spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		spr.region_enabled = true
		spr.region_rect = Rect2(Vector2.ZERO, span / k)
		spr.position = Vector2(-cell.x * 8.0, -cell.y * 11.0)
		layer.repeat_size = Vector2.ZERO
	elif repeat > 0.0:
		layer.repeat_size = Vector2(repeat, 0.0)
		layer.repeat_times = Level01Parallax.copies_for_view(repeat)
	else:
		var tile := (region.size.x if region.has_area() else float(tex.get_width())) * k
		var step := floorf(tile)
		layer.repeat_size = Vector2(step, 0.0)
		layer.repeat_times = Level01Parallax.copies_for_view(step)
	return layer
