extends ChapterLayout
## 锈墓・捌 — 墓园夜雨。从工坊的运渣道爬回地面，是墓园的另一侧：锈雨、浓雾、
## 锈泥沼与从土里成群起身的骸骨。室外，第一关同款天空（graveyard 主题，冷月色阶）。
##
## v3 重做结构（宽 4000，打破 y=320 单线：下沉陵室/泥沟 y=352、地面 y=320、土坟 y=288/256、
## 外圈陵顶 y=224→192→176→208、树顶支路 y=232）：
##   ① 出土口     0–448     运渣道石门洞、起点巢（176）、墓志「哈伦」、老树、路牌「墓园」
##   ② 西坟群     448–832   落地浓雾（GraveFog）+ 土坟 MoundB；三具骸骨成群埋伏（alert_radius 160 / lose_range 260）
##   ③ 首遇锈泥沼 832–1008  安全教学泥沼（MudIntro，前后各 ≥80px 安全平地）+ 两块跳石（StoneC1/C2）
##   ④ 陵门分岔   1008–1312 压板土丘 MoundD 开陵门（MausoleumDoor）、陵门后第二巢（EmberNestCrypt 1184）、路牌「陵墓」
##   ⑤ 中央大陵墓 1312–1888 环绕陵墓的双路线（两条路都能到出口）：
##                          · 外圈露天墓道（y=288→256→224→192→176→208）：长但覆浓雾（RoofFog），陵顶喷吐者 + 骸骨守卫，
##                            东侧单向落下（RoofDropLedge 240 → 地面 320）
##                          · 内圈陵墓捷径（下沉陵室 y=352）：短但幽暗危险（CryptShade），窄道爆裂骸骨（留 192px 西退路）+
##                            陵室泥沼（MudCrypt + 跳石）+ 幽魂；东口压板门（CryptShortcut）打通双向捷径
##   ⑥ 骸骨林     1888–2304 第三巢（EmberNestGrove 2120）、墓志「薇尔」；老树顶钩锁支路（TreeTopStone y=232）
##                          含余烬核 + 墓志「战马」+ 可选挑战奖励位（RewardTreeTop「滤毒符印」）
##   ⑦ 斜雨泥沼沟 2304–2608 下沉泥沟（y=352）+ 斜锈雨（DitchSquall）+ 锈泥沼（MudSquall）+ 三块浮石（StoneG1..G3）
##   ⑧ 荒坟坡     2608–3136 第四巢（EmberNestMire 2680）；东段浓雾（EastGraveFog）+ 第二处坟群起身 + 幽魂
##   ⑨ 东墓泥洼   3136–3360 下沉泥洼（y=352）+ 锈泥沼（MudEast）+ 两块浮石（StoneK1/K2）
##   ⑩ 钟楼门前   3360–4000 第五巢（EmberNestEast 3424）、双层高坟台（TerraceJ1/J2）+ 装甲碎铁犬守门、出口「钟楼门」

const EAST := 4000
const SUNKEN_Y := 352.0
const SLAB_TONE := Color(0.98, 0.9, 0.62)

## [name, x0, x1, cap_left, cap_right, top_y]
const FLOORS: Array = [
	["FloorA", 0.0, 1312.0, false, true, FLOOR_Y],
	["FloorCrypt", 1312.0, 1888.0, false, false, SUNKEN_Y],
	["FloorD", 1888.0, 2304.0, true, true, FLOOR_Y],
	["FloorSquall", 2304.0, 2608.0, false, false, SUNKEN_Y],
	["FloorH", 2608.0, 3136.0, true, true, FLOOR_Y],
	["FloorHollow", 3136.0, 3360.0, false, false, SUNKEN_Y],
	["FloorJ", 3360.0, 4000.0, true, false, FLOOR_Y],
]

## 土丘 / 土台：[name, pos, size]（ground 皮肤，48 厚 = 32 上升 + 一格埋进下方台面）
const MOUNDS: Array = [
	["MoundB", Vector2(560, 288), Vector2(96, 48)],
	["MoundD", Vector2(1024, 288), Vector2(80, 48)],
	["MoundI", Vector2(2880, 288), Vector2(96, 48)],
	["TerraceJ1", Vector2(3504, 288), Vector2(160, 48)],
	["TerraceJ2", Vector2(3536, 256), Vector2(96, 48)],
]

## 浮石与外圈陵墓石阶：[name, pos, width]（floating 皮肤，16 厚）
const STONES: Array = [
	# ③ 首遇锈泥沼跳石
	["StoneC1", Vector2(856, 288), 48.0],
	["StoneC2", Vector2(936, 288), 48.0],
	# ⑤ 外圈露天墓道（陵墓顶环线）与东侧单向落台
	["RoofStepW1", Vector2(1248, 288), 48.0],
	["RoofStepW2", Vector2(1312, 256), 48.0],
	["RoofStepW3", Vector2(1376, 224), 48.0],
	["MausoleumRoofW", Vector2(1440, 192), 160.0],
	["MausoleumRoofTop", Vector2(1616, 176), 96.0],
	["MausoleumRoofE", Vector2(1728, 208), 112.0],
	["RoofDropLedge", Vector2(1848, 240), 48.0],
	# ⑤ 内圈地下陵室泥沼跳石
	["StoneCrypt", Vector2(1600, 320), 48.0],
	# ⑥ 树顶钩锁支路（加宽以容纳碑文、余烬核与挑战奖励位）
	["TreeTopStone", Vector2(2016, 232), 80.0],
	# ⑦ 斜锈雨泥沟跳石
	["StoneG1", Vector2(2352, 288), 48.0],
	["StoneG2", Vector2(2448, 272), 48.0],
	["StoneG3", Vector2(2544, 288), 48.0],
	# ⑨ 东墓泥洼跳石
	["StoneK1", Vector2(3184, 288), 48.0],
	["StoneK2", Vector2(3264, 272), 48.0],
]

## 锈泥沼外力区：[name, rect, drag, toxin_per_second]
const MUD_ZONES: Array = [
	["MudIntro", Rect2(832, 296, 176, 24), 0.40, 12.0],
	["MudCrypt", Rect2(1536, 328, 176, 24), 0.42, 14.0],
	["MudSquall", Rect2(2320, 328, 272, 24), 0.42, 15.0],
	["MudEast", Rect2(3152, 328, 192, 24), 0.45, 16.0],
]

## 主路线与双路线台阶链（测试用）：每一步上升 ≤32、横跨 ≤72（下落可更远）。
const CHAINS: Array = [
	# ② 西坟堆：地面 → 土坟顶 → 地面
	[Vector2(556, 320), Vector2(564, 288), Vector2(652, 288), Vector2(660, 320)],
	# ③ 首遇泥沼跳石：地面 → 浮石 → 浮石 → 地面
	[Vector2(828, 320), Vector2(864, 288), Vector2(952, 288), Vector2(1012, 320)],
	# ④ 陵门压板：地面 → 压板土丘
	[Vector2(1020, 320), Vector2(1032, 288)],
	# ⑤A 外圈露天墓道：地面 → 西阶三级 → 陵顶三段 → 单向落台 → 东庭地面
	[Vector2(1240, 320), Vector2(1264, 288), Vector2(1328, 256), Vector2(1392, 224),
			Vector2(1456, 192), Vector2(1632, 176), Vector2(1744, 208), Vector2(1864, 240), Vector2(1900, 320)],
	# ⑤B 内圈陵墓内部捷径：西口地面 → 下沉陵室 → 陵室跳石 → 下沉陵室 → 东口地面
	[Vector2(1304, 320), Vector2(1320, 352), Vector2(1592, 352), Vector2(1616, 320),
			Vector2(1656, 352), Vector2(1880, 352), Vector2(1896, 320)],
	# ⑦ 斜雨泥沼沟：沟沿 → 三块浮石 → 对岸
	[Vector2(2300, 320), Vector2(2360, 288), Vector2(2464, 272), Vector2(2560, 288), Vector2(2612, 320)],
	# ⑧ 荒坟坡：地面 → 土坟顶 → 地面
	[Vector2(2876, 320), Vector2(2888, 288), Vector2(2968, 288), Vector2(2980, 320)],
	# ⑨ 东墓泥洼：洼沿 → 两块浮石 → 对岸
	[Vector2(3132, 320), Vector2(3192, 288), Vector2(3280, 272), Vector2(3364, 320)],
	# ⑩ 钟楼门前坟台：地面 → 一级 → 二级 → 一级 → 地面
	[Vector2(3500, 320), Vector2(3512, 288), Vector2(3544, 256), Vector2(3640, 288), Vector2(3668, 320)],
]

const PLATE_FEET := Vector2(1064, 288)
const DOOR_POS := Vector2(1120, 256)
## 陵室东口的单向/双向捷径门：从内圈走出或从外圈屋顶落台跳下均可踩开，打通回程捷径。
const CRYPT_SHORTCUT_PLATE_FEET := Vector2(1896, 320)
const CRYPT_SHORTCUT_DOOR_POS := Vector2(1928, 256)

const HOOK_POS := Vector2(2046, 144)
const PICKUP_POS := Vector2(2046, 184)
const STELE_TREE_POS := Vector2(2030, 232)
## 树顶钩锁支路奖励位：滤毒符印（EquipmentPickup 的 Fill 底边在 +7px，落在 232 台面）。
const REWARD_POS := Vector2(2076, 225)
const REWARD_KIND := "equipment"
const REWARD_REF := "toxic_ward"
const REWARD_LABEL := "滤毒符印"

## 五处余烬巢：间距 ≤1008px（176 → 1184 → 2120 → 2680 → 3424 → 出口 3840）。
const NEST_START_X := 176.0
const NEST_CRYPT_X := 1184.0
const NEST_GROVE_X := 2120.0
const NEST_MIRE_X := 2680.0
const NEST_EAST_X := 3424.0

const STELE_A_POS := Vector2(256, 320)
const STELE_B_POS := Vector2(2176, 320)
const EXIT_X := 3840.0

## [name, kind, pos, overrides]：雾中坟群骸骨带 alert_radius / lose_range；内圈窄道配爆裂骸骨。
const ENEMIES: Array = [
	# ② 西坟群（GraveFog 浓雾内成群起身）
	["Skeleton1", "skeleton", Vector2(520, 320), {"alert_radius": 160.0, "lose_range": 260.0, "wake_range": 130.0}],
	["Skeleton2", "skeleton", Vector2(608, 288), {"alert_radius": 160.0, "lose_range": 260.0, "wake_range": 130.0}],
	["Skeleton5", "skeleton", Vector2(704, 320), {"alert_radius": 160.0, "lose_range": 260.0, "wake_range": 130.0}],
	# ⑤A 外圈露天陵顶遭遇
	["Ghost1", "ghost", Vector2(1384, 168), {}],
	["Spitter1", "spitter", Vector2(1664, 176), {}],
	["SkeletonRoof", "skeleton", Vector2(1784, 208), {"alert_radius": 160.0, "lose_range": 260.0, "wake_range": 120.0}],
	# ⑤B 内圈地下陵室窄道遭遇（爆裂骸骨西侧留 192px 退路）
	["Scrapper1", "scrapper", Vector2(1416, 352), {"patrol_range": 24.0}],
	["Skeleton3", "skeleton", Vector2(1504, 352), {"variant": &"exploder_skeleton", "alert_radius": 160.0, "lose_range": 260.0, "wake_range": 130.0}],
	["Ghost2", "ghost", Vector2(1624, 280), {}],
	["Skeleton4", "skeleton", Vector2(1760, 352), {"alert_radius": 160.0, "lose_range": 260.0, "wake_range": 130.0}],
	# ⑧⑩ 东段浓雾坟群与钟楼门前守卫
	["Skeleton6", "skeleton", Vector2(2928, 288), {"alert_radius": 160.0, "lose_range": 260.0, "wake_range": 130.0}],
	["Skeleton7", "skeleton", Vector2(3024, 320), {"alert_radius": 160.0, "lose_range": 260.0, "wake_range": 130.0}],
	["Ghost3", "ghost", Vector2(3088, 236), {}],
	["Scrapper2", "scrapper", Vector2(3744, 320), {"variant": &"armored_scrapper", "patrol_range": 24.0}],
]

const WAYMARKS: Array = [
	[Vector2(384, 320), "墓园"],
	[Vector2(1216, 320), "陵墓"],
	[Vector2(3788, 320), "钟楼"],
]


func level_id() -> String:
	return "level06"


func title() -> String:
	return ChapterText.title_of(level_id())


func wake_line() -> String:
	return ChapterText.wake_of(level_id())


func _stele(host: Node2D, node_name: String, pos: Vector2) -> void:
	var entry := ChapterText.stele_of(level_id(), node_name)
	stele(host, node_name, pos, String(entry.get("title", "")), String(entry.get("text", "")))


func entry_spawn() -> Vector2:
	return Vector2(96, 300)


func default_spawn() -> Vector2:
	return entry_spawn()


func east_limit() -> int:
	return EAST


func camera_top() -> int:
	return -48


func theme() -> String:
	return "graveyard"


func ambient() -> Dictionary:
	return {"time": 0.82, "weather": "rain", "hold": 420.0}


func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.RAIN, WorldClock.Weather.RUST_RAIN,
				WorldClock.Weather.FOG, WorldClock.Weather.CLEAR],
		"weights": {
			"night": {"rust_rain": 6, "rain": 3, "fog": 1},
			"*": {"rain": 4, "rust_rain": 3, "fog": 2, "clear": 1},
		},
		"hold": Vector2(220.0, 360.0),
		"intensity": Vector2(0.75, 1.0),
	}


## 局部天气区域：
##   · GraveFog（448–928）：西坟群落地浓雾
##   · RoofFog（1360–1888）：中央大陵墓外圈露天墓道浓雾
##   · CryptShade（1312–1888）：中央大陵墓内圈地下陵室（切室内，幽暗无雨）
##   · DitchSquall（2304–2608）：长泥沟上空斜锈雨
##   · EastGraveFog（2848–4000）：东段荒坟坡浓雾
func weather_regions() -> Array:
	return [
		{"name": "GraveFog", "rect": Rect2(448, 96, 480, 160),
			"weather": WorldClock.Weather.FOG, "intensity": 1.0, "wind_scale": 0.35},
		{"name": "RoofFog", "rect": Rect2(1360, 80, 528, 144),
			"weather": WorldClock.Weather.FOG, "intensity": 0.95, "wind_scale": 0.4},
		{"name": "CryptShade", "rect": Rect2(1312, 264, 576, 120),
			"intensity": 0.0, "wind_scale": 0.0, "indoor": true},
		{"name": "DitchSquall", "rect": Rect2(2304, 128, 304, 160),
			"weather": WorldClock.Weather.RUST_RAIN, "intensity": 1.0, "wind_scale": 1.35},
		{"name": "EastGraveFog", "rect": Rect2(2848, 96, 1152, 160),
			"weather": WorldClock.Weather.FOG, "intensity": 0.85, "wind_scale": 0.45},
	]


func build(host: Node2D) -> void:
	_build_terrain(host)
	_build_hazards(host)
	_build_props(host)
	_build_enemies(host)
	_build_decor(host)
	exit_door(host, EXIT_X, ChapterText.exit_label_of(level_id()),
			ChapterText.exit_captions_of(level_id()), "level06_done",
			GameContext.next_level_id(level_id()))
	finish(host)


func _build_terrain(host: Node2D) -> void:
	for f in FLOORS:
		floor_strip(host, String(f[0]), float(f[1]), float(f[2]), "ground",
				bool(f[3]), bool(f[4]), float(f[5]))
	for m in MOUNDS:
		platform(host, String(m[0]), m[1] as Vector2, m[2] as Vector2, "ground")
	for s in STONES:
		step(host, String(s[0]), s[1] as Vector2, float(s[2]), "floating", SLAB_TONE)
	walls(host, "ground")


func _build_hazards(host: Node2D) -> void:
	for z in MUD_ZONES:
		force_zone(host, String(z[0]), z[1] as Rect2, "mud", Vector2.ZERO,
				{"drag": float(z[2]), "toxin_per_second": float(z[3])})


func _build_props(host: Node2D) -> void:
	nest(host, "EmberNestStart", NEST_START_X)
	nest(host, "EmberNestCrypt", NEST_CRYPT_X)
	nest(host, "EmberNestGrove", NEST_GROVE_X)
	nest(host, "EmberNestMire", NEST_MIRE_X)
	nest(host, "EmberNestEast", NEST_EAST_X)
	_stele(host, "SteleHallen", STELE_A_POS)
	_stele(host, "SteleVeil", STELE_B_POS)
	plate_door(host, "Mausoleum", PLATE_FEET, DOOR_POS)
	plate_door(host, "CryptShortcut", CRYPT_SHORTCUT_PLATE_FEET, CRYPT_SHORTCUT_DOOR_POS)
	hook(host, "HookTreeTop", HOOK_POS)
	pickup(host, "EmberCoreTreeTop", PICKUP_POS, &"ember_core")
	_stele(host, "SteleTree", STELE_TREE_POS)
	reward(host, "RewardTreeTop", REWARD_POS, REWARD_KIND, REWARD_REF, REWARD_LABEL)
	destructible(host, "CryptUrnWest", &"rust_urn", Vector2(1360, 352))
	destructible(host, "CryptHeapEast", &"scrap_heap", Vector2(1832, 352))
	for w in WAYMARKS:
		waymark(host, w[0] as Vector2, String(w[1]))


func _build_enemies(host: Node2D) -> void:
	for e in ENEMIES:
		enemy(host, String(e[0]), String(e[1]), e[2] as Vector2,
				e[3] as Dictionary if e.size() > 3 else {})


func _build_decor(host: Node2D) -> void:
	# ① 出土口
	prop(host, "door_arch", Vector2(40, 320), 1.0, Color(0.62, 0.6, 0.72))
	foliage(host, "bush_s", Vector2(112, 320), 1.0)
	prop(host, "stone_1", Vector2(222, 320))
	foliage(host, "tree_2_px", Vector2(296, 320), 1.0, true)
	prop(host, "stone_3", Vector2(452, 320))
	# ② 西坟群
	foliage(host, "bush_l_px", Vector2(492, 320), 1.0)
	prop(host, "grave_cross", Vector2(608, 288))
	prop(host, "stone_4", Vector2(680, 320))
	foliage(host, "tree_1_px", Vector2(728, 320), 1.0, true)
	prop(host, "grave_cross", Vector2(800, 320))
	# ④ 陵门分岔
	prop(host, "stone_1", Vector2(1016, 320))
	prop(host, "balustrade", Vector2(1152, 320))
	# ⑤ 中央大陵墓（内圈下沉陵室 y=352 + 外圈露天墓道 y=192/176/208）
	prop(host, "door_arch", Vector2(1344, 352), 1.0, Color(0.55, 0.54, 0.66))
	prop(host, "stone_2", Vector2(1464, 352))
	prop(host, "grave_cross", Vector2(1504, 192))
	prop(host, "statue", Vector2(1664, 176))
	prop(host, "stone_4", Vector2(1800, 208))
	prop(host, "door_arch", Vector2(1856, 352), 1.0, Color(0.55, 0.54, 0.66))
	# ⑥ 骸骨林
	foliage(host, "tree_1_px", Vector2(1996, 320), 1.0, true)
	prop(host, "stone_3", Vector2(2080, 320))
	foliage(host, "tree_2_px", Vector2(2204, 320), 1.0, true)
	foliage(host, "bush_s", Vector2(2272, 320), 1.0)
	# ⑧ 荒坟坡
	prop(host, "stone_2", Vector2(2632, 320))
	prop(host, "balustrade", Vector2(2744, 320))
	prop(host, "grave_cross", Vector2(2928, 288))
	prop(host, "stone_4", Vector2(3000, 320))
	foliage(host, "tree_2_px", Vector2(3048, 320), 1.0, true)
	prop(host, "stone_1", Vector2(3112, 320))
	# ⑩ 钟楼门前
	prop(host, "stone_4", Vector2(3384, 320))
	prop(host, "grave_cross", Vector2(3524, 288))
	prop(host, "stone_1", Vector2(3584, 256))
	prop(host, "statue", Vector2(3704, 320))
	prop(host, "balustrade", Vector2(3912, 320))
	foliage(host, "tree_1_px", Vector2(3948, 320), 1.0, true)
