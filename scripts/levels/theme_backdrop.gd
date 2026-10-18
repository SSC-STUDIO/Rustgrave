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

## ---- 显式美术规格（docs/art-spec.md） -------------------------------------
## 层级对比：远板 ≤ 天空 < 中景 < 近景，且永远输给角色（BackdropTint 再压一档）。
## 每个主题至少一个独有元素（IDENTITY_COLOR + Signature 灯型 / 剪影 / 窗光）。
## UNDERCRYPT → undercroft 是唯一回退主题；未知 theme() 会静默变成地窟，
## 这正是「只换底色」的失败模式，所以这里显式拒絕未知主题由 ThemeBackdrop 承担。
const THEME_FALLBACK := "undercroft"
## 每层 tint 的最高明度（scene 线性）：sky 0.13 < far 0.24 < mid 0.40 < near 0.62。
## 角色（玩家最低明度 0.227 在 MoodTint 之前）因此永远高出背景至少一档。
const TINT_LUMA_MAX := 0.62
## backdrop 的 CanvasModulate 额外压暗，保证远景输给角色（world_atmosphere.gd）。
const BACKDROP_SUBORDINATE := 0.24
## 轮廓对照：玩家躯干 #CD5C5C 的 sRGB 明度是 0.455；一档 = 0.045 明度。
## 背景层允许的平均明度上限 0.40，再被 BackdropTint 压 0.24（×0.76），
## 因此玩法层与背景的平均差 ≥ 0.455 - 0.40×0.76 ≈ 0.151，即至少 3 档。
const PLAYER_BODY_LUMA := 0.455
const SILHOUETTE_STEP := 0.045
const SILHOUETTE_STEPS_MIN := 3
const LAYER_LUMA_CAP := 0.40
## BackdropTint 跟随世界时钟的速率；和 WorldAtmosphere.FOLLOW_RATE 同档。
const BACKDROP_TINT_RATE := 3.5

## 每章身份色（只能用 Palette 的 16 色）：写在签名光 / 雾 / 窗光上。
## 单换背景色不算视觉身份，所以这张表和 SIGNATURES 一起被测试锁定。
const IDENTITY_COLOR := {
	"graveyard": Palette.RUST_LIGHT,
	"undercroft": Palette.TEAL,
	"forge": Palette.TOXIC,
	"forge_core": Palette.RUST_LIGHT,
	"cathedral": Palette.PALE,
	"belltower": Palette.EMBER,
	"ramparts": Palette.FOG,
	"town": Palette.EMBER_ASH,
	"industrial": Palette.RUST_MID,
}

## 每章的独有光型：shafts（天窗/箭窗光柱）、glow（炉口/故事光）、windows（街灯窗）。
## shafts / glows / windows 的坐标是 640×360 view 内的像素；层整体重复 640px。
const SIGNATURES := {
	"undercroft": {
		"kind": "shafts", "scroll": 0.34, "alpha": 0.17,
		"shafts": [Vector3(104, 16, 1), Vector3(356, -12, 1)],
		"glows": [Vector3(212, 292, 2)],
	},
	"forge": {
		"kind": "glow", "scroll": 0.44, "alpha": 0.16,
		"glows": [Vector3(108, 304, 3), Vector3(420, 320, 4), Vector3(300, 250, 2),
				Vector3(236, 148, 3), Vector3(524, 184, 2)],
	},
	"forge_core": {
		"kind": "glow", "scroll": 0.4, "alpha": 0.16,
		"glows": [Vector3(320, 258, 5), Vector3(120, 320, 2),
				Vector3(176, 168, 4), Vector3(484, 138, 3)],
		"shafts": [Vector3(320, 24, 1)],
	},
	"cathedral": {
		"kind": "shafts", "scroll": 0.3, "alpha": 0.15,
		"shafts": [Vector3(180, -8, 1), Vector3(330, -16, 1), Vector3(470, -4, 1)],
		"glows": [Vector3(330, 300, 2)],
	},
	"belltower": {
		"kind": "shafts", "scroll": 0.28, "alpha": 0.18,
		"shafts": [Vector3(96, 58, 1), Vector3(480, 18, 1)],
	},
	"ramparts": {
		"kind": "shafts", "scroll": 0.2, "alpha": 0.13,
		"shafts": [Vector3(220, -32, 1)],
		"glows": [Vector3(560, 300, 2)],
	},
	"town": {
		"kind": "windows", "scroll": 0.58, "alpha": 0.4,
		"windows": [Vector2(420, 214), Vector2(452, 214), Vector2(484, 206),
				Vector2(516, 214), Vector2(548, 206), Vector2(580, 214)],
		"glows": [Vector3(500, 306, 2)],
	},
	"industrial": {
		"kind": "shafts", "scroll": 0.38, "alpha": 0.15,
		"shafts": [Vector3(140, -8, 1), Vector3(420, -28, 1)],
		"glows": [Vector3(260, 320, 2)],
	},
}

## 每章的签名灯型（测试据此确认「不只换底色」）。
const SIGNATURE_KIND := {
	"graveyard": "moon",
	"undercroft": "shafts",
	"forge": "glow",
	"forge_core": "glow",
	"cathedral": "shafts",
	"belltower": "shafts",
	"ramparts": "shafts",
	"town": "windows",
	"industrial": "shafts",
}

const FOG_BAND_PATH := "res://assets/env/fog_band.png"
const GLOW_SOFT_PATH := "res://assets/env/glow_soft.png"
const SIGNATURE_NODE := "Signature"
const SIGNATURE_SPAN := 640.0
## 光柱 / 光晕贴图：程序化生成（Image），不下载、不新增外部素材。
const BEAM_TEX_SIZE := Vector2i(32, 192)
const GLOW_TEX_SIZE := 48

const THEMES := {
	# 地窟：青黑苔砖、拱窗壁龛（Level02 同款）。
	"undercroft": {
		"indoors": true,
		"void": Color(0.035, 0.07, 0.085),
		"mood": Color(0.66, 0.82, 0.84),
		"layers": [
			# 远景：更深的拱顶大厅剪影（慢速 0.16，只留窗光），和苔砖墙之间拉开
			# 一层空气。原 2 层叠在一起时墙与柱糊成一张纸。
			{"name": "HallFar", "path": GOTHIC_CASTLE, "scroll": Vector2(0.16, 0.06), "pos": Vector2(0, 40), "scale": 1.0, "tint": Color(0.34, 0.46, 0.48), "region": Rect2(0, 0, 480, 200)},
			{"path": CASTLE_INTERIOR, "scroll": Vector2(0.42, 0.18), "pos": Vector2(0, 48), "scale": 1.0, "tint": Color(0.78, 0.9, 0.9)},
			{"path": COLUMN_PATH, "scroll": Vector2(0.66, 0.3), "pos": Vector2(96, 336 - 190), "scale": 1.0, "tint": Color(0.16, 0.24, 0.25, 0.9), "repeat": 352.0},
		],
	},
	# 熔渣深渊：同一套工业剪影，离线映射成炉口的红光（天在下面烧，不在上面亮）。
	# 和工坊（industrial）同包，但工坊是灰绿的冷车间，这里是渣海。
	# 三层室内远景（wall/truss/machinery）由 tools/gen_theme_tiles.py 的
	# interior_backdrops() 生成：墙板铺满镜头，顶架给上缘收口，机械剪影给地面线。
	"forge": {
		"indoors": true,
		"void": Color(0.07, 0.02, 0.015),
		"mood": Color(1.0, 0.8, 0.66),
		"layers": [
			{"path": BACKDROP_DIR + "wall_forge.png", "scroll": Vector2(0.14, 0.1),
				 "pos": Vector2(0, 0), "scale": 1.0, "tint": Color(0.86, 0.72, 0.62),
				 "tile": true, "covers_top": true},
			{"path": BACKDROP_DIR + "forge_sky.png", "scroll": Vector2(0.04, 0.02), "pos": Vector2(0, 0), "scale": 2.0, "tint": Color(1, 1, 1, 0.5)},
			{"path": BACKDROP_DIR + "forge_far.png", "scroll": Vector2(0.18, 0.06), "pos": Vector2(0, 40), "scale": 2.0, "tint": Color.WHITE},
			{"path": BACKDROP_DIR + "forge_mid.png", "scroll": Vector2(0.4, 0.1), "pos": Vector2(0, 8), "scale": 2.0, "tint": Color.WHITE},
			{"path": BACKDROP_DIR + "forge_near.png", "scroll": Vector2(0.62, 0.14), "pos": Vector2(0, 120), "scale": 2.0, "tint": Color(1, 1, 1, 0.9)},
			{"path": BACKDROP_DIR + "truss_forge.png", "scroll": Vector2(0.22, 0.16),
				 "pos": Vector2(0, 0), "scale": 1.0, "tint": Color(0.86, 0.8, 0.74), "covers_top": true},
			# 机械剪影站在地面线上，是最近的一层：scroll 必须比 forge_near 快，
			# 否则「近的比远的慢」，视差方向反了，纵深读不出来。
			{"path": BACKDROP_DIR + "machinery_forge.png", "scroll": Vector2(0.7, 0.3),
				 "pos": Vector2(-48, 152), "scale": 1.0, "tint": Color(0.95, 0.88, 0.82)},
		],
	},
	# 炉心深处：地窟的拱窗内景烧成暗红——终关是一座被火从里面舔过的殿。
	"forge_core": {
		"indoors": true,
		"void": Color(0.05, 0.012, 0.016),
		"mood": Color(1.0, 0.84, 0.8),
		"layers": [
			{"path": BACKDROP_DIR + "wall_core.png", "scroll": Vector2(0.14, 0.1),
				 "pos": Vector2(0, 0), "scale": 1.0, "tint": Color(0.88, 0.72, 0.64),
				 "tile": true, "covers_top": true},
			{"path": BACKDROP_DIR + "core_hall.png", "scroll": Vector2(0.42, 0.18), "pos": Vector2(0, 48), "scale": 1.0, "tint": Color(1, 1, 1, 0.82)},
			{"path": COLUMN_PATH, "scroll": Vector2(0.66, 0.3), "pos": Vector2(96, 336 - 190), "scale": 1.0, "tint": Color(0.3, 0.08, 0.07, 0.92), "repeat": 352.0},
			{"path": BACKDROP_DIR + "truss_core.png", "scroll": Vector2(0.22, 0.16),
				 "pos": Vector2(0, 0), "scale": 1.0, "tint": Color(0.9, 0.82, 0.76), "covers_top": true},
			{"path": BACKDROP_DIR + "machinery_core.png", "scroll": Vector2(0.7, 0.3),
				 "pos": Vector2(-48, 152), "scale": 1.0, "tint": Color(1.0, 0.9, 0.84)},
		],
	},
	# 圣殿：哥特城堡大厅面板（楼梯、尖窗、石像鬼、烛龛）拼成一条重复的殿墙。
	# 大厅板画在地面线上，上半屏原本是空的：补一层冷紫砌石墙 + 顶架剪影（拱顶肋）。
	"cathedral": {
		"indoors": true,
		"void": Color(0.045, 0.04, 0.075),
		"mood": Color(0.72, 0.7, 0.9),
		"layers": [
			# 补墙/顶架用显式 layer 名：殿墙 hall strip 仍是 Layer0、柱影仍是 Layer1，
			# 竖井关「不能沿井复制殿墙」的索引断言不受影响。
			{"name": "WallPlate", "path": BACKDROP_DIR + "wall_slate.png", "scroll": Vector2(0.14, 0.1),
				 "pos": Vector2(0, 0), "scale": 1.0, "tint": Color(0.84, 0.82, 0.94),
				 "tile": true, "covers_top": true},
			{"path": GOTHIC_CASTLE, "scroll": Vector2(0.4, 0.16), "pos": Vector2(0, 152), "scale": 1.0, "tint": Color(0.9, 0.9, 1.0), "region": Rect2(0, 0, 480, 168)},
			{"path": COLUMN_PATH, "scroll": Vector2(0.62, 0.28), "pos": Vector2(220, 336 - 190), "scale": 1.0, "tint": Color(0.2, 0.17, 0.3, 0.9), "repeat": 448.0},
			{"name": "VaultTruss", "path": BACKDROP_DIR + "truss_slate.png", "scroll": Vector2(0.24, 0.18),
				 "pos": Vector2(0, 0), "scale": 1.0, "tint": Color(0.72, 0.7, 0.82), "covers_top": true},
		],
	},
	# 钟楼：竖井。橄榄色城砖墙双向平铺爬满整座塔（没有地面线，抬多高都不穿帮），
	# 箭窗透冷光；地面一层再压一条殿墙。
	"belltower": {
		"indoors": true,
		"void": Color(0.03, 0.03, 0.04),
		"mood": Color(0.78, 0.78, 0.9),
		"layers": [
			# 竖井远景：塔中塔。外层一座更暗、更窄的塔身剪影（慢速 0.12），只留
			# 顶部一列透光的箭窗；它和近处的 tower_wall 形成「墙在前、塔在后」
			# 的纵深，不然整座竖井只是一张贴着砖的纸。
			{"name": "TowerFar", "path": GOTHIC_CASTLE, "scroll": Vector2(0.12, 0.05), "pos": Vector2(64, 24), "scale": 1.4, "tint": Color(0.3, 0.3, 0.38), "region": Rect2(120, 0, 240, 300)},
			{"path": BACKDROP_DIR + "tower_wall.png", "scroll": Vector2(0.3, 0.3), "pos": Vector2(0, 0), "scale": 1.0, "tint": Color.WHITE, "tile": true, "covers_top": true},
			{"path": COLUMN_PATH, "scroll": Vector2(0.62, 0.28), "pos": Vector2(220, 336 - 190), "scale": 1.0, "tint": Color(0.16, 0.15, 0.2, 0.9), "repeat": 448.0},
		],
	},
	# 锈城城墙：站在墙顶往下看城。青灰云、远山，城和钟塔缩在脚下的雾里。
	"ramparts": {
		"indoors": false,
		"void": Color(0.06, 0.1, 0.11),
		"mood": Color(0.8, 0.86, 0.86),
		"layers": [
			{"path": TOWN_DIR + "night-town-background-sky.png", "scroll": Vector2(0.03, 0.02), "pos": Vector2(0, -40), "scale": 2.0, "tint": Color(0.8, 0.9, 0.92)},
			{"path": BACKDROP_DIR + "wall_clouds.png", "scroll": Vector2(0.07, 0.03), "pos": Vector2(0, -60), "scale": 2.0, "tint": Color(1, 1, 1, 0.85)},
			{"path": TOWN_DIR + "night-town-background-mountains.png", "scroll": Vector2(0.14, 0.05), "pos": Vector2(0, 20), "scale": 2.0, "tint": Color(0.82, 0.9, 0.9)},
			# 城墙脚下整座锈城：远一层的楼房剪影视差最慢（0.3），熄灯；近一层
			# （0.44）只有零星窗火——站在墙顶往下看，城是压暗的、有光的，不是
			# 一块贴纸。wall_town 的 0.62 是最后一道墙沿，仍然最快。
			{"name": "CityFar", "path": TOWN_DIR + "night-town-background-far-buildings.png", "scroll": Vector2(0.3, 0.08), "pos": Vector2(0, 210), "scale": 2.0, "tint": Color(0.7, 0.78, 0.8)},
			{"name": "CityLights", "path": TOWN_DIR + "night-town-background-mountains-lights.png", "scroll": Vector2(0.44, 0.12), "pos": Vector2(0, 240), "scale": 2.0, "tint": Color(0.85, 0.8, 0.7)},
			{"path": BACKDROP_DIR + "wall_town.png", "scroll": Vector2(0.62, 0.14), "pos": Vector2(0, 160), "scale": 2.0, "tint": Color.WHITE},
		],
	},
	# 锈城：夜色小镇——天、云、山、林、远屋、近屋。室外，有天气与风。
	"town": {
		"indoors": false,
		"void": Color(0.04, 0.08, 0.09),
		"mood": Color(0.74, 0.82, 0.84),
		"layers": [
			{"path": TOWN_DIR + "night-town-background-sky.png", "scroll": Vector2(0.03, 0.02), "pos": Vector2(0, -40), "scale": 2.0, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-clouds.png", "scroll": Vector2(0.08, 0.03), "pos": Vector2(0, -20), "scale": 2.0, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-mountains.png", "scroll": Vector2(0.16, 0.05), "pos": Vector2(0, -4), "scale": 2.0, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-forest.png", "scroll": Vector2(0.3, 0.08), "pos": Vector2(0, 168), "scale": 2.0, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-far-buildings.png", "scroll": Vector2(0.42, 0.1), "pos": Vector2(0, 200), "scale": 2.0, "tint": Color.WHITE},
			{"path": TOWN_DIR + "night-town-background-town.png", "scroll": Vector2(0.62, 0.14), "pos": Vector2(0, 178), "scale": 2.0, "tint": Color.WHITE},
		],
	},
	# 锈厂：工业剪影——脚手架、厂房、烟囱。有顶棚，算室内（无雨），暖灰色调。
	# 原包整族是绿的，和「暖灰铁」身份色打架；三张远景由 gen_theme_tiles.py 重映射到
	# 暖铁色阶。砌石墙（wall_iron）铺满镜头，顶架和机械剪影给上缘/地面线收口。
	"industrial": {
		"indoors": true,
		"void": Color(0.06, 0.06, 0.06),
		"mood": Color(0.82, 0.74, 0.68),
		"layers": [
			# 远景三件套（tools/gen_theme_tiles.py 的 workshop_* 派生板）：车间有顶棚，
			# 但顶棚上的天窗缝漏得进城——最远是霾里的天际线，中间是远处厂房，
			# 近一点是贴着工坊的邻楼。都在 wall_iron 这堵实墙前面，所以读作
			# 「墙外还有一座城」，而不是把室内墙糊成半透明。
			{"name": "CityFar", "path": BACKDROP_DIR + "workshop_haze.png", "scroll": Vector2(0.04, 0.02), "pos": Vector2(0, 0), "scale": 2.0, "tint": Color(1.0, 0.96, 0.92, 0.25)},
			{"name": "CityMid", "path": BACKDROP_DIR + "workshop_far.png", "scroll": Vector2(0.16, 0.05), "pos": Vector2(0, 128), "scale": 2.0, "tint": Color(0.94, 0.9, 0.86)},
			{"name": "CityNear", "path": BACKDROP_DIR + "workshop_near.png", "scroll": Vector2(0.34, 0.1), "pos": Vector2(0, 168), "scale": 2.0, "tint": Color(0.88, 0.84, 0.8)},
			{"path": BACKDROP_DIR + "wall_iron.png", "scroll": Vector2(0.14, 0.1),
				 "pos": Vector2(0, 0), "scale": 1.0, "tint": Color(0.86, 0.82, 0.78),
				 "tile": true, "covers_top": true},
			{"path": BACKDROP_DIR + "truss_iron.png", "scroll": Vector2(0.22, 0.16),
				 "pos": Vector2(0, 0), "scale": 1.0, "tint": Color(0.8, 0.76, 0.72), "covers_top": true},
			{"path": BACKDROP_DIR + "machinery_iron.png", "scroll": Vector2(0.7, 0.3),
				 "pos": Vector2(-48, 152), "scale": 1.0, "tint": Color(0.95, 0.9, 0.85)},
		],
	},
}

const BREATH_AMP := 0.03
const BREATH_RATE := 0.35

var _mood: CanvasModulate
var _backdrop_tint: CanvasModulate
var _base_mood := Color.WHITE
var _indoors := true
var _t := 0.0

## 程序化合成的共享贴图 / 材质（每个进程只做一次）。
static var _beam_tex: Texture2D
static var _glow_tex: Texture2D
static var _pixel_tex: Texture2D
static var _add_mat: CanvasItemMaterial
static var _luma_cache: Dictionary = {}


static func clear_cache() -> void:
	_beam_tex = null
	_glow_tex = null
	_pixel_tex = null
	_add_mat = null
	_luma_cache.clear()


static func has_theme(theme_id: String) -> bool:
	return THEMES.has(theme_id) or theme_id == "graveyard"


## 每主题的独有元素名（视觉身份：不能只换底色）。写在这里由测试锁定，
## 新增主题必须同时登记 THEMES、has_theme 与本表。
const SIGNATURE_LAYERS := {
	"undercroft": ["HallFar", "Layer1"],
	"forge": ["Layer0", "Layer5", "Layer6"],
	"forge_core": ["Layer0", "Layer3", "Layer4"],
	"cathedral": ["WallPlate", "VaultTruss"],
	"belltower": ["TowerFar", "Layer1"],
	"ramparts": ["Layer0", "Layer1", "Layer2", "CityFar", "CityLights", "Layer3"],
	"town": ["Layer0", "Layer1", "Layer2", "Layer3", "Layer4", "Layer5"],
	"industrial": ["CityFar", "CityMid", "CityNear", "Layer1", "Layer2"],
}


static func is_indoor_theme(theme_id: String) -> bool:
	if theme_id == "graveyard":
		return false
	return bool((THEMES.get(theme_id, {}) as Dictionary).get("indoors", true))


func build(host: Node2D, theme_id: String, _camera_top: float = -48.0) -> void:
	if theme_id == "graveyard":
		_build_graveyard(host, theme_id)
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
	# 命名：默认 Layer0..LayerN（图层顺序 = 绘制顺序）。新加的「室内补墙/顶架」层
	# 可以给 def "name" 覆盖自己的名字，这样垂直关的既有 hall strip 仍是 Layer0/Layer1
	# （chapter_support_test 用索引锁定「殿墙不能沿竖井复制」）。named 层不占 LayerN 序号。
	var i := 0
	for layer_def in theme.get("layers", []):
		var layer_name := String((layer_def as Dictionary).get("name", ""))
		if layer_name == "":
			layer_name = "Layer%d" % i
			i += 1
		_add_layer(backdrop, layer_name, layer_def)
	# 环境层次：每一章都有「雾 + 独有光型」两层。雾把远/中/近粘在同一空气里，
	# Signature 是本章的身份光（箭窗、炉口、街灯窗），两者都在玩法画布后面。
	if backdrop.get_node_or_null("FogNear") == null:
		_add_mist(backdrop, theme_id)
	if backdrop.get_node_or_null(SIGNATURE_NODE) == null:
		_add_signature(backdrop, theme_id)
	_ensure_backdrop_tint(backdrop)
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
## for clouds / fog / mood / weather / moon. The sky and far-mountain plates are
## the derived rust pair for the graveyard identity (Level01Parallax decides and
## falls back to the authored magenta plates if a derived asset is missing).
func _build_graveyard(host: Node2D, theme_id: String = "graveyard") -> void:
	_indoors = false
	var sky_path := Level01Parallax.sky_plate_path(theme_id)
	var mountain_path := Level01Parallax.mountains_plate_path(theme_id)
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	if backdrop == null:
		backdrop = CanvasLayer.new()
		backdrop.name = "ParallaxBackdrop"
		backdrop.layer = -10
		backdrop.follow_viewport_enabled = false
		host.add_child(backdrop)
		_add_plate(backdrop, "Far", sky_path, Vector2(0.08, 0.04), Vector2(0, -24), 2.0)
		_add_plate(backdrop, "Mid", mountain_path, Vector2(0.22, 0.06), Vector2(0, 48), 2.0)
		_add_plate(backdrop, "Hills", "res://assets/env/parallax_graveyard.png", Vector2(0.48, 0.1), Vector2(0, 168), 2.0)
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
	host.add_child(extras)
	extras.build(host, theme_id)
	_ensure_backdrop_tint(backdrop)


func _add_plate(parent: Node, plate_name: String, path: String, scroll: Vector2, pos: Vector2, scale_k: float,
		tint: Color = Color.WHITE) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var layer := Parallax2D.new()
	layer.name = plate_name
	layer.scroll_scale = scroll
	layer.follow_viewport = false
	parent.add_child(layer)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = pos
	spr.scale = Vector2(scale_k, scale_k)
	_apply_luma_cap(layer, spr, tex, tint)
	layer.add_child(spr)
	Level01Parallax.cover_layer(layer)


func _process(delta: float) -> void:
	_update_backdrop_tint(delta)
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
	_apply_luma_cap(layer, spr, tex, def.get("tint", Color.WHITE))
	var region: Rect2 = def.get("region", Rect2())
	if region.has_area():
		spr.region_enabled = true
		spr.region_rect = region
	layer.add_child(spr)
	var repeat: float = def.get("repeat", 0.0)
	if bool(def.get("tile", false)):
		# Plain wall texture for a tall interior: one oversized sprite that tiles on both
		# axes by texture repeat. Parallax2D's own repeat only covers a strip of the
		# view on the second axis. The sprite spans every camera position of every chapter
		# (scroll shifts it by at most travel * scroll_scale) plus a view of margin, so
		# the wall can never run off the top of a tall shaft — the old fixed
		# `-18 * cell` offset left the whole bell tower black.
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
	if bool(def.get("covers_top", false)):
		# 室内关的上缘必须有墙/梁压住（tests/prop_fit_test.gd 断言的「镜头上界带」）。
		layer.set_meta("covers_top", true)
	return layer


## ------------------------------------------------- 视觉身份 / 轮廓对比 --

## 主题身份色（Palette 16 色之一；未知主题回落到骨白）。
static func identity_color(theme_id: String) -> Color:
	return IDENTITY_COLOR.get(theme_id, Palette.PALE)


## 主题独有光型：shafts / glow / windows。graveyard 的月亮/剪影由
## Level01Parallax 负责，所以返回 "moon"。
static func signature_kind(theme_id: String) -> String:
	return String(SIGNATURE_KIND.get(theme_id, ""))


static func srgb_luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## 贴图不透明像素的平均 sRGB 明度（按最长边最多采样 48 个点）。
## 结果按 resource_path 缓存：每层只在建关时算一次。
static func texture_luma(tex: Texture2D) -> float:
	if tex == null:
		return 0.0
	var key := tex.resource_path
	if key == "":
		key = "rid:%d" % tex.get_instance_id()
	if _luma_cache.has(key):
		return float(_luma_cache[key])
	var img := tex.get_image()
	var total := 0.0
	var n := 0
	if img != null:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var step := maxi(1, int(maxf(float(w), float(h)) / 48.0))
		for y in range(0, h, step):
			for x in range(0, w, step):
				var c := img.get_pixel(x, y)
				if c.a <= 0.04:
					continue
				total += srgb_luma(c)
				n += 1
	var luma := total / float(n) if n > 0 else 0.0
	_luma_cache[key] = luma
	return luma


## 一层 backdrop 的平均明度上限：超出就整体压暗，既保留内部对比，
## 又保证「背景永远比玩家里最亮的主角躯干低至少 3 档」。
func _apply_luma_cap(layer: Parallax2D, spr: Sprite2D, tex: Texture2D, tint: Color) -> float:
	var avg := texture_luma(tex)
	var gain := 1.0
	if avg > LAYER_LUMA_CAP:
		gain = LAYER_LUMA_CAP / avg
	spr.modulate = Color(tint.r * gain, tint.g * gain, tint.b * gain, tint.a)
	if layer != null:
		layer.set_meta("luma", avg * gain)
		layer.set_meta("luma_cap", LAYER_LUMA_CAP)
		layer.set_meta("luma_gain", gain)
	return gain


## 背景 CanvasLay 的独立调色：永远比 MoodTint（玩法层）暗一档。
func _ensure_backdrop_tint(parent: CanvasLayer) -> void:
	if parent == null:
		return
	var cm := parent.get_node_or_null("BackdropTint") as CanvasModulate
	if cm == null:
		cm = CanvasModulate.new()
		cm.name = "BackdropTint"
		parent.add_child(cm)
	_backdrop_tint = cm
	_backdrop_tint.color = _backdrop_target_color()


func _backdrop_target_color() -> Color:
	var ambient: Color = WorldClock.indoor_tint() if WorldClock.zone == WorldClock.Zone.INDOORS \
			else WorldClock.outdoor_tint()
	return ambient.darkened(BACKDROP_SUBORDINATE)


func _update_backdrop_tint(delta: float) -> void:
	if _backdrop_tint == null:
		return
	var k := 1.0 if delta <= 0.0 else 1.0 - exp(-BACKDROP_TINT_RATE * maxf(delta, 0.0))
	_backdrop_tint.color = _backdrop_tint.color.lerp(_backdrop_target_color(), k)


## 当前 BackdropTint 颜色（测试 / 调试用）。
func backdrop_tint_color() -> Color:
	return _backdrop_tint.color if _backdrop_tint != null else Color.WHITE


## 雾层：所有章节共用一条 fog_band 贴图，但用本章身份色染色；
## 它把远 / 中 / 近三层粘进同一空气，近层不会像贴在天空上的贴纸。
func _add_mist(parent: CanvasLayer, theme_id: String) -> Parallax2D:
	if not ResourceLoader.exists(FOG_BAND_PATH):
		return null
	var tex := load(FOG_BAND_PATH) as Texture2D
	if tex == null:
		return null
	var layer := Parallax2D.new()
	layer.name = "FogNear"
	layer.scroll_scale = Vector2(0.76, 0.12)
	layer.follow_viewport = false
	parent.add_child(layer)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(0, 248)
	spr.scale = Vector2(2.0, 1.25)
	var c := identity_color(theme_id)
	spr.modulate = Color(c.r, c.g, c.b, 0.14)
	layer.add_child(spr)
	Level01Parallax.cover_layer(layer)
	layer.set_meta("identity_color", c)
	layer.set_meta("occlusion_alpha", 0.14)
	return layer


## 独有元素层：本章的一束光 / 一片炉火 / 一排街窗。坐标在 640×360 view 内，
## Parallax2D 按 640px 重复，所以镜头走多远都有同一组光。
func _add_signature(parent: CanvasLayer, theme_id: String) -> Parallax2D:
	var spec: Dictionary = SIGNATURES.get(theme_id, {})
	if spec.is_empty():
		return null
	var layer := Parallax2D.new()
	layer.name = SIGNATURE_NODE
	layer.scroll_scale = Vector2(float(spec.get("scroll", 0.5)), 0.08)
	layer.follow_viewport = false
	parent.add_child(layer)
	layer.repeat_size = Vector2(SIGNATURE_SPAN, 0.0)
	layer.repeat_times = Level01Parallax.copies_for_view(SIGNATURE_SPAN)
	var c := identity_color(theme_id)
	var alpha := float(spec.get("alpha", 0.16))
	var made := 0
	for spot in spec.get("shafts", []):
		var v: Vector3 = spot
		if _add_beam(layer, v, c, alpha):
			made += 1
	for spot in spec.get("glows", []):
		var v: Vector3 = spot
		if _add_glow(layer, v, c, alpha):
			made += 1
	for spot in spec.get("windows", []):
		var v: Vector2 = spot
		if _add_window(layer, v, c, alpha):
			made += 1
	if made == 0:
		layer.queue_free()
		return null
	layer.set_meta("theme", theme_id)
	layer.set_meta("kind", signature_kind(theme_id))
	layer.set_meta("identity_color", c)
	layer.set_meta("occlusion_alpha", alpha)
	return layer


## 光柱：32×192 的程序化渐变，顶部亮、底部收；加法混合，永远在 backdrop 层。
func _add_beam(layer: Parallax2D, spot: Vector3, c: Color, alpha: float) -> bool:
	var beam := _beam_texture()
	if beam == null:
		return false
	var spr := Sprite2D.new()
	spr.name = "Shaft"
	spr.texture = beam
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.material = _additive_material()
	spr.position = Vector2(roundf(spot.x), roundf(spot.y + 96.0))
	spr.rotation = deg_to_rad(-7.0 if int(spot.z) % 2 == 0 else 6.0)
	spr.modulate = Color(c.r, c.g, c.b, alpha)
	spr.set_meta("kind", "shaft")
	layer.add_child(spr)
	return true


## 局部光晕：炉口 / 烛台 / 烽火，加法混合的小半径光池。
func _add_glow(layer: Parallax2D, spot: Vector3, c: Color, alpha: float) -> bool:
	var tex := _glow_texture()
	if tex == null:
		return false
	var spr := Sprite2D.new()
	spr.name = "Pool"
	spr.texture = tex
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.material = _additive_material()
	spr.position = Vector2(roundf(spot.x), roundf(spot.y))
	spr.scale = Vector2(spot.z, spot.z)
	spr.modulate = Color(c.r, c.g, c.b, alpha * 0.8)
	spr.set_meta("kind", "glow")
	layer.add_child(spr)
	return true


## 街窗：4×6 的像素窗光，加法混合；窗框由暗背景自然切出。
func _add_window(layer: Parallax2D, at: Vector2, c: Color, alpha: float) -> bool:
	var tex := _pixel_texture()
	if tex == null:
		return false
	var spr := Sprite2D.new()
	spr.name = "Window"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.material = _additive_material()
	spr.position = at.round()
	spr.scale = Vector2(4, 6)
	spr.modulate = Color(c.r, c.g, c.b, alpha)
	spr.set_meta("kind", "window")
	layer.add_child(spr)
	return true


static func _additive_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


static func _beam_texture() -> Texture2D:
	if _beam_tex != null:
		return _beam_tex
	var w := BEAM_TEX_SIZE.x
	var h := BEAM_TEX_SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var along := pow(1.0 - t, 1.35) * 0.55
		for x in w:
			var cx := absf(float(x) - float(w - 1) * 0.5) / (float(w) * 0.5)
			var a := clampf(along * pow(1.0 - cx, 1.6), 0.0, 0.55)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_beam_tex = ImageTexture.create_from_image(img)
	return _beam_tex


static func _glow_texture() -> Texture2D:
	if _glow_tex != null:
		return _glow_tex
	if ResourceLoader.exists(GLOW_SOFT_PATH):
		_glow_tex = load(GLOW_SOFT_PATH) as Texture2D
		if _glow_tex != null:
			return _glow_tex
	var size := GLOW_TEX_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / (float(size) * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.0) * 0.7
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


static func _pixel_texture() -> Texture2D:
	if _pixel_tex != null:
		return _pixel_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex
