class_name SceneDetails
extends Node
## Level01 场景细节（set dressing）：用 PropCatalog 里已入库的真实贴图讲述
## 「锈炉城埋在墓园下面」的世界历史，替代以前不透明 ColorRect 占位方块
## （docs/UPGRADE_PLAN.md 1A / 缺陷 P0-1）。
##
## 设计原则（docs/art-spec.md「世界历史细节」「角色接地」「特效不遮挡」）：
## - 只种 PropCatalog.DECOR 键：贴图经 PropCatalog.path_for(key, "graveyard") 解析。
##   锈铁残骸（girder_r / chain）与被 tiles.png 底板包住的骨渣由
##   tools/gen_theme_tiles.py 的 rust_remains() 派生到 assets/env/props/ground/：
##   1x、硬边、吸附 16 色锈色阶，和墓园贴图同一像素密度。
## - 全部 1x、TEXTURE_FILTER_NEAREST、脚点钉在平台顶：走 Level01Env.plant 就自动
##   写 feet 元数据、入 grounded 组；LevelSanity 与 tests/scene_details_test.gd
##   复查「不悬空 / 不压台缘 / 不挡敌人起手和交互物」。
## - 按区域手排，只做西侧走廊（x < 1600）：东翼的 Boss 竞技场 / 炉心由 1D 负责，
##   这里不碰 level01_east_wing.gd 的布景。毒坑不摆接地道具（两岸矮唇是玩法结构），
##   只在悬空石台底下挂一截断链。
## - 静态、一次性：没有逐帧逻辑、没有信号连接、节点数固定。

## 墓园主题。PropCatalog 的素材族（graveyard → "ground"）决定锈铁残骸的变体贴图。
const THEME := "graveyard"
## 墓园地面线，等于 Level01Static.GROUND_TOP（手摆细节都站这一行；测试锁两者一致）。
const GROUND_TOP := 320.0
## 锈铁残骸压暗一档：夜里它们退到墓碑后面，只留剪影和断口，不抢玩法层。
const WRECK_TINT := Color(0.5, 0.44, 0.42)

## 允许直接种的 DECOR 键（docs/UPGRADE_PLAN.md 1A 白名单）。不在表里的键必须先
## 登记进 PropCatalog / tools/gen_theme_tiles.py，不许在 layout 里写死贴图路径。
const ALLOWED_KEYS := [
	"grave_cross", "statue", "stone_1", "stone_2", "stone_3", "stone_4",
	"tree_1", "tree_2", "bush_l", "bush_s",
	"rubble_dry", "rubble_dry_b", "rubble_dry_c", "rock_pile", "bones",
	"pipe_valve", "broken_machine", "girder_l", "girder_r", "warning_plate",
	"fence", "chain", "fire_vent", "life_remains", "skull_arch",
	"balustrade", "door_arch", "plate", "slab",
]

## 接地细节表：[区域, 键, 贴图左缘 x, 脚点 y, 色调]。
## feet.x 是贴图左缘（Level01Env.plant 的硬物 API）；脚点 y 是它踩着的那块台面顶。
## 只排进既有布景的空档：不叠 PLAY_DECOR、不盖路牌、不碰交互物和敌人起手位，
## 左右各留 1px 余量；浮台正下方的细节压到台底以下，不探出台缘；
## 「东翼」牌以东留给东翼 / Boss 竞技场 owner。
const GROUND_DETAILS := [
	# 起点台地：西墙根堆着上一轮埋葬剩下的骨石。
	["start_terrace", "rock_pile", 2.0, GROUND_TOP, Color.WHITE],
	# 中段攀爬：浮台底下压着上一班人的骨渣；压板两侧各立一块断碑。
	["mid_climb", "bones", 779.0, GROUND_TOP, Color.WHITE],
	["mid_climb", "stone_4", 999.0, GROUND_TOP, Color.WHITE],
	["mid_climb", "stone_4", 1069.0, GROUND_TOP, Color.WHITE],
	# 门区：决斗台门的石栏前倒着旧墓碑，大门与枯树之间是一根断斜撑，
	# 铁栅外的石栏边还有第二块碑。
	["gate_approach", "rubble_dry", 1096.0, GROUND_TOP, Color.WHITE],
	["gate_approach", "girder_r", 1170.0, GROUND_TOP, WRECK_TINT],
	["gate_approach", "rubble_dry_b", 1334.0, GROUND_TOP, Color.WHITE],
	["gate_approach", "rubble_dry_c", 1411.0, GROUND_TOP, Color.WHITE],
]

## 悬挂细节表：[区域, 键, 挂点节点路径, 相对挂点底边中点的偏移, 色调]。
## 挂点用真实节点（悬挂件不接地、不写死坐标）：毒坑上方的悬空石台底面挂着一截
## 断链，垂在腐液上空——它不接地，检查逻辑也只认 hang_top。
const HANGING_DETAILS := [
	["toxic_pit", "chain", "Platforms/Plat_420_236", Vector2(-31, 0), WRECK_TINT],
]

## 光照锚点表：[灯名, 地标节点路径, 相对地标的偏移, 类型]。
## 灯位 = 地标节点的全局位置 + 偏移；地标不存在就跳过——不再把坐标写死在数组里
## （缺陷 P2-1：光池落在空处）。每盏灯都记 anchor_path，测试能反查地标。
const LIGHT_ANCHORS := [
	# 余烬巢的暖池：火盆碗口。
	["NestWest", "Props/EmberNest", Vector2(8, -12), AmbientLighting.LightType.EMBER],
	# 毒池荧光：湿地表中心略上方，照亮两岸而不是坑底。
	["ToxicPool", "Props/ToxinPool", Vector2(56, -2), AmbientLighting.LightType.TOXIC],
	# 门区火把：决斗台大门 / 锈铁栅是玩家要读的两个关口。
	["ArenaDoor", "Props/Door", Vector2(16, 32), AmbientLighting.LightType.TORCH],
	["RustyGate", "Props/RustyGate", Vector2(16, 32), AmbientLighting.LightType.TORCH],
	# 月束打在余烬高台（钩锁锚点 + 余烬核）上，给跳跃目标一个冷色地标。
	["EmberLedge", "Platforms/EmberLedge", Vector2(40, -8), AmbientLighting.LightType.MOONBEAM],
	# Boss 门前的最后存档点。
	["NestEast", "Props/EmberNestEast", Vector2(8, -12), AmbientLighting.LightType.EMBER],
	# Boss 门 / 炉心：竞技场入口与章末锻炉各一盏。
	["BossGate", "BossGate", Vector2(0, 32), AmbientLighting.LightType.TORCH],
	["ForgeHeart", "Props/ForgeHeart", Vector2(8, 16), AmbientLighting.LightType.FURNACE],
]


## 把手工表里的场景细节一次种完。host 是关卡根（解析悬挂挂点），layer 是细节层。
## 返回实际种上的节点数（贴图缺失/挂点缺失会被跳过，计数可用于测试）。
static func populate_level01(host: Node, layer: Node2D) -> int:
	if host == null or layer == null:
		return 0
	var planted := 0
	for row in GROUND_DETAILS:
		var tint: Color = row[4]
		if plant_ground(layer, String(row[1]), float(row[2]), float(row[3]), tint) != null:
			planted += 1
	for row in HANGING_DETAILS:
		var top := anchor_bottom_center(host, String(row[2]))
		if not top.is_finite():
			continue
		var offset: Vector2 = row[3]
		var tint: Color = row[4]
		if hang_from(layer, String(row[1]), top + offset, tint) != null:
			planted += 1
	return planted


## 种一件接地细节：脚点落在平台顶，1x 最近邻，注册 grounded 组与 feet 元数据。
## feet.x 是贴图左缘（Level01Env.plant 的历史 API；脚点元数据写底边中点）。
static func plant_ground(layer: Node2D, key: String, left_x: float, feet_y: float,
		tint: Color = Color.WHITE) -> Sprite2D:
	if not ALLOWED_KEYS.has(key):
		push_warning("SceneDetails: '%s' 不在 Level01 的装饰白名单里" % key)
		return null
	var path := PropCatalog.path_for(key, THEME)
	if not ResourceLoader.exists(path):
		push_warning("SceneDetails: 贴图缺失 %s" % path)
		return null
	return Level01Env.plant(layer, path, Vector2(roundf(left_x), roundf(feet_y)), 1.0, tint)


## 挂一件悬挂细节（chain / vine）：bottom_center 是它挂在实体底边上的中点。
## 悬挂件不接地，所以不写 feet 元数据、只记 hang_top（与 ChapterLayout.hanging 一致）。
static func hang_from(layer: Node2D, key: String, bottom_center: Vector2,
		tint: Color = Color.WHITE) -> Sprite2D:
	if not ALLOWED_KEYS.has(key):
		push_warning("SceneDetails: '%s' 不在 Level01 的装饰白名单里" % key)
		return null
	var path := PropCatalog.path_for(key, THEME)
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(roundf(bottom_center.x - float(tex.get_width()) * 0.5),
			roundf(bottom_center.y))
	if tint != Color.WHITE:
		spr.modulate = tint
	spr.set_meta(&"hang_top", Vector2(roundf(bottom_center.x), roundf(bottom_center.y)))
	spr.set_meta(&"foot_anchor", "top_center")
	layer.add_child(spr)
	return spr


## 真实地标的底边中点：实心台用它的方块底边，其它节点用原点。
## 悬挂件只认节点的实际位置，绝不退回写死坐标。
static func anchor_bottom_center(host: Node, node_path: String) -> Vector2:
	var anchor := host.get_node_or_null(node_path) as Node2D
	if anchor == null:
		return Vector2.INF
	if anchor is SolidPlatform:
		var plat := anchor as SolidPlatform
		return Vector2(roundf(plat.global_position.x + plat.size.x * 0.5),
				roundf(plat.global_position.y + plat.size.y))
	return anchor.global_position


## 把 AmbientLighting 的灯锚定到实际地标：余烬巢、毒池、门 / 门区火把、Boss 门、
## 炉心、余烬高台。返回点亮的盏数；地标缺失时跳过而不是把光池留在空处。
static func add_level01_lighting(lighting: AmbientLighting, host: Node) -> int:
	if lighting == null or host == null:
		return 0
	var added := 0
	for row in LIGHT_ANCHORS:
		var anchor := host.get_node_or_null(String(row[1])) as Node2D
		if anchor == null:
			continue
		var offset: Vector2 = row[2]
		var light_type: AmbientLighting.LightType = row[3]
		var light := lighting.add_light_on(anchor, offset, light_type)
		if light == null:
			continue
		light.name = "Light_%s" % String(row[0])
		light.set_meta(&"anchor_path", String(row[1]))
		added += 1
	return added
