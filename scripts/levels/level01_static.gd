class_name Level01Static
extends Node2D
## Level01 — 静态手摆关卡。
## 锚点、拾取物、视差背景等全部固化在 .tscn 里，可直接在 Godot 编辑器中
## 可视化编辑；本脚本只负责生成玩家/相机/HUD 三件套并接线机关信号。

const PLAYER := preload("res://scenes/player/Player.tscn")
const CAMERA := preload("res://scenes/camera/GameCamera.tscn")
const HUD := preload("res://scenes/ui/HUD.tscn")
const PLATFORM := preload("res://scenes/world/Platform.tscn")

@onready var plate: PressurePlate = get_node_or_null("Props/PressurePlate")
@onready var door: ArenaDoor = get_node_or_null("Props/Door")

const DEFAULT_SPAWN := Vector2(96, 320)
## GroundLeft / GroundRight / east floor 顶。单跳约 37px（v=-268, g=980）。
const GROUND_TOP := 320.0
## 单跳顶点；踏步用 32px，留约 5px 余量，且不挡地面行人头顶（碰撞高 26px）。
const JUMP_REACH := 37.0
const STEP_RISE := 32.0
## 毒坑：水面 y=336（ToxinPool.surface_rect），坑底见 Level01EastWing.PIT_FLOOR_Y。
## 余烬巢右侧的第一级教学台：实心抵地，人从台上过而不是从台下钻。
## 高 48 而不是 32：底部 16px 埋进地面，用自己的土盖掉地面那行草——
## 否则是一块草皮方砖摆在草皮上（草下面还是草），读作土丘才自然。
const TEACH_TERRACE_POS := Vector2(228, 288)
const TEACH_TERRACE_SIZE := Vector2(40, 48)
## 路牌：1x 木牌 35×35（normalized/props），字写在牌面上而不是飘在牌子上方。
const SIGN_TEX := "res://assets/env/normalized/props/waymark_sign.png"
## 牌面在贴图里的矩形（贴图 y 3–22；柱脚在 (17,35)）；12px 像素字体两个字 24×12 正好落在牌面里。
const SIGN_PLANK := Rect2(0, 3, 35, 20)
const SIGN_FONT_SIZE := 12
## Plat_268 降到第二级（64px），从教学台再单跳 32px 上去。
const TEACH_MID_Y := 256.0
const WAYMARKS := [
	[Vector2(118, 320), "余烬"],
	# 牌面 35px，左缘 = 脚点 - 17。枯树右缘 264，石块从 330 起。
	[Vector2(300, 320), "腐液"],
	# 压板偏殿的门口：上层路（Plat_920_248 → Plat_980_180）从这里头顶过，楼座在东边。
	[Vector2(1040, 320), "压板"],
	# 牌面 35px。锈门前最后一站：炉廊的炉口已经在身后，门后是中殿。
	[Vector2(2536, 320), "东翼"],
]
## 硬物只在玩法层：scale=1，脚钉 GROUND_TOP，无 WindSway。近景视差条不画碑。
## 位置是贴图左缘。路牌牌面是脚点 x-17 起、宽 35。两边不许叠。
## 注意：**不要把 SolidPlatform 的地台贴图（*_slab_*.png / iron_slab_*.png）当装饰种**。
## 它们是"平顶 + 断裂底边"的铺地素材，单独立在墓地行里就是一块读不懂的方块
## （用户反馈的原图）。塌落的锈蚀结构用断梁 / 碎石 / 机械残骸这类有轮廓的道具。
const DECOR_ROCK_PILE := "res://assets/env/gh_rock_pile.png"
const DECOR_RUBBLE := "res://assets/env/rubble_c.png"
const PLAY_DECOR := [
	# 大灌木 49px，右缘 89，离「余烬」牌面（101 起）还有空。
	[Level01Env.DECOR_BUSH_L_65, Vector2(40, 320), 1.0],
	[Level01Env.DECOR_STONE_1, Vector2(148, 320), 1.0],
	# 枯树 76px，右缘 264。教学土丘从 228 起会挡住树干，树冠仍露在丘顶上面。
	[Level01Env.DECOR_TREE_2_PX, Vector2(188, 320), 1.0],
	[Level01Env.DECOR_STONE_3, Vector2(330, 320), 1.0],
	# 坑东岸：碑在 548 附近；碑东侧塌着一堆墓土碎石
	# （以前这里种的是 iron_slab 地台贴图，读作一块方碑）。
	[DECOR_ROCK_PILE, Vector2(550, 320), 1.0],
	[DECOR_RUBBLE, Vector2(586, 320), 1.0],
	[Level01Env.DECOR_STONE_4, Vector2(624, 320), 1.0],
	[Level01Env.DECOR_BUSH_S, Vector2(656, 320), 1.0],
	[Level01Env.DECOR_GRAVE_CROSS, Vector2(700, 320), 1.0],
	[Level01Env.DECOR_STATUE, Vector2(880, 320), 1.0],
	# 草地到 1168 为止：之后是偏殿的石板地，墓园的树与灌木不再往里长
	# （偏殿 / 工坊 / 中殿的装饰由 level01_east_layout.gd 摆）。
]

const EAST_LIMIT := Level01EastWing.EAST_LIMIT
const EAST_FLOOR_X := Level01EastWing.EAST_FLOOR_X

var _player: Player
var _boss: ExecutionerBoss
var _wing: Level01EastWing
var _beats: Level01StoryBeats


func _enter_tree() -> void:
	add_to_group("game_world")


func _ready() -> void:
	DisplayFit.apply()
	# 先读档再铺东翼：否则 boss_dead 还在磁盘上，刽子手会先进场。
	var restored := false
	if SaveData.has_save():
		restored = SaveData.load_game()
	_extend_east()
	_tune_play_layout()
	_spawn_decor()
	_spawn_waymarks()
	_spawn_steles_and_bastion_decor()
	_build_parallax_extras()
	_spawn_actors(restored)
	_wire_props()
	_bind_story()
	# Chapter palette on the play layer once every folder is built (east wing included);
	# deferred again so late-built pieces (rebuilt toxin pit, sway pivots) are covered.
	Level01Parallax.grade_play_layer(self)
	Level01Parallax.grade_play_layer.call_deferred(self)
	Level01Parallax.add_light_pools.call_deferred(self)
	call_deferred("_try_wake")


func _wire_props() -> void:
	if plate != null and door != null and not plate.activated.is_connected(door.open_door):
		plate.activated.connect(door.open_door)
	var toxin := get_node_or_null("Props/ToxinPool") as ToxinPool
	if toxin != null:
		# 水面几何只有一个来源：Level01EastWing 的 PIT_WATER_*（雨滴/毒性/石阶都按它）。
		toxin.position = Vector2(Level01EastWing.PIT_X0, Level01EastWing.PIT_WATER_Y)
		toxin.configure(Level01EastWing.PIT_WATER_SIZE)


func _spawn_actors(restored: bool) -> void:
	_player = PLAYER.instantiate()
	_player.position = DEFAULT_SPAWN
	add_child(_player)

	var from_checkpoint := SaveData.entering_from_checkpoint
	if SaveData.has_pending_spawn():
		_player.position = SaveData.consume_pending_spawn()
	elif restored and SaveData.data.has("player") and (SaveData.data["player"] as Dictionary).has("pos"):
		_player.position = SaveData.data["player"]["pos"]
	_player.position = SpawnSafety.safe_position(self, _player.position, DEFAULT_SPAWN)
	if restored:
		SaveData.apply_player(_player)
		SaveData.apply_world(self)
		SaveData.apply_consumed(self)
	SaveData.apply_lit_nests(self)
	if from_checkpoint:
		_player.health.heal_full()
		_player.toxin.purify(1.0)
		GameEvents.player_health_changed.emit(_player.health.current, _player.health.max_hp)

	var cam: GameCamera = CAMERA.instantiate()
	add_child(cam)
	cam.limit_right = EAST_LIMIT
	cam.global_position = _player.global_position + Vector2(0, -18)

	var hud: CanvasLayer = HUD.instantiate()
	GameContext.ui_host(self).add_child(hud)


func _tune_play_layout() -> void:
	var platforms := get_node_or_null("Platforms") as Node2D
	if platforms == null:
		return
	place_teach_layout(platforms)
	# Merge note: the chapter-1 colour is the phase-3 grade (Level01Parallax play material +
	# plates). The per-material tones below are kept for reference but not applied: they
	# re-tinted ground / floating stone / toxin away from the agreed authored hues.
	if APPLY_MATERIAL_TONES:
		_grade_materials(platforms)


## 第一章材质色阶（不换贴图、不动碰撞）：让墓园的地面、悬空石台和毒液
## 收进同一个"锈/余烬"温度里，而不是鲜草绿 + 薰衣草紫 + 青苔绿三套色板打架。
## 颜色经 SolidPlatform.apply_tone 乘在每一块贴片上；东翼的石头铺面同样收暖。
const GROUND_TONE := Color(1.14, 0.76, 0.38)   # 草地 → 枯橄榄/墓土（去鲜绿）
const FLOAT_TONE := Color(1.10, 0.88, 0.60)    # 悬浮石板 → 暖灰石（去薰衣草紫）
const STONE_TONE := Color(1.12, 0.90, 0.62)    # 决斗台铺路 → 暖石
const TOXIN_TINT := Color(1.16, 1.08, 0.48)    # 腐液 → 酸黄绿（与草地绿分开）
## Off: the phase-3 grade owns chapter-1 colour (user-approved look).
const APPLY_MATERIAL_TONES := false


func _grade_materials(platforms: Node2D) -> void:
	for plat in _solid_platforms(platforms):
		var skin := plat.skin
		var grade := Color.WHITE
		if skin == "floating" or (skin == "auto" and plat.size.y <= SolidPlatform.WORLD + 0.5
				and plat.size.x > SolidPlatform.WORLD + 0.5):
			grade = FLOAT_TONE
		elif skin == "ground" or skin == "auto" or skin == "":
			grade = GROUND_TONE
		elif skin == "stone" or skin == "nave":
			grade = STONE_TONE
		if grade == Color.WHITE:
			continue
		plat.apply_tone(plat.tone * grade)
	# 齿轮也复用原石板纹理，和可站立石台保持同一材质色阶。
	var gear := platforms.get_node_or_null("Gear") as CanvasItem
	if gear != null:
		gear.modulate = FLOAT_TONE
	# 草地去饱和后保留毒池的独立青绿，危险边界不靠亮度区分。
	var toxin := get_node_or_null("Props/ToxinPool") as ToxinPool
	if toxin != null:
		toxin.tint = TOXIN_TINT


func _solid_platforms(root: Node) -> Array[SolidPlatform]:
	var out: Array[SolidPlatform] = []
	for child in root.get_children():
		if child is SolidPlatform:
			out.append(child as SolidPlatform)
		elif child is Node:
			out.append_array(_solid_platforms(child))
	return out


## 开局单跳链：地面 → 32px 实心教学台 → 再 32px 到 Plat_268。
func place_teach_layout(platforms: Node2D) -> void:
	if platforms == null:
		return
	if platforms.get_node_or_null("TeachTerrace") == null:
		var terrace: SolidPlatform = PLATFORM.instantiate()
		terrace.name = "TeachTerrace"
		terrace.skin = "ground"
		terrace.position = TEACH_TERRACE_POS
		terrace.size = TEACH_TERRACE_SIZE
		terrace.cap_left = true
		terrace.cap_right = true
		platforms.add_child(terrace)
	var mid := platforms.get_node_or_null("Plat_268_248") as SolidPlatform
	if mid != null:
		mid.position.y = TEACH_MID_Y


func _spawn_waymarks() -> void:
	if get_node_or_null("Waymarks") != null:
		return
	var layer := Node2D.new()
	layer.name = "Waymarks"
	layer.z_index = 2
	add_child(layer)
	for item in WAYMARKS:
		_waymark(layer, item[0] as Vector2, String(item[1]))


func _waymark(parent: Node2D, feet: Vector2, text: String) -> void:
	var root := Node2D.new()
	root.name = "Sign_%s" % text
	root.position = feet
	parent.add_child(root)
	var plank := SIGN_PLANK
	var origin := Vector2(-17.0, -35.0)
	if ResourceLoader.exists(SIGN_TEX):
		var spr := Sprite2D.new()
		spr.name = "Board"
		spr.texture = DensityTextures.load_texture(SIGN_TEX)
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = origin
		root.add_child(spr)
	# 字写在牌面上：按 12px 像素字体的实际排版尺寸在牌面矩形里居中，坐标取整。
	var lab := Label.new()
	lab.name = "Text"
	lab.text = text
	lab.add_theme_font_size_override("font_size", SIGN_FONT_SIZE)
	lab.add_theme_color_override("font_color", Palette.PALE)
	lab.add_theme_color_override("font_outline_color", Palette.VOID)
	lab.add_theme_constant_override("outline_size", 1)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(lab)
	# Size after entering the tree: the theme resolves the font on enter and
	# would otherwise grow the label to its pre-theme fallback minimum.
	lab.position = (origin + plank.position).round()
	lab.size = plank.size


func _spawn_decor() -> void:
	var layer := Node2D.new()
	layer.name = "GraveDecor"
	layer.z_index = -2
	add_child(layer)
	for item in PLAY_DECOR:
		var path := String(item[0])
		# 墓园里的活绿收成枯橄榄，墓石略暖：和地面 / 悬浮石台的色阶同一温度。
		var tint := Color.WHITE
		match Level01Env.hardness_of(path):
			Level01Env.Hardness.TREE, Level01Env.Hardness.BUSH:
				tint = FOLIAGE_TONE
			Level01Env.Hardness.STONE:
				tint = GRAVE_STONE_TONE
		Level01Env.plant(layer, path, item[1] as Vector2, float(item[2]), tint, true)


## 植被去饱和：鲜绿是"刚浇过水"，枯橄榄才是墓园长出来的东西。
const FOLIAGE_TONE := Color.WHITE  # phase-3 grade owns colour (was Color(0.98, 0.80, 0.48))
## 墓石统一微暖，避免灰蓝石头在暖锈天空下显脏。
const GRAVE_STONE_TONE := Color.WHITE  # phase-3 grade owns colour (was Color(1.04, 0.94, 0.82))


const STELE_SCENE := preload("res://scenes/interactables/LoreStele.tscn")
const BALUSTRADE_TEX := "res://assets/env/balustrade.png"


func _spawn_steles_and_bastion_decor() -> void:
	var props := get_node_or_null("Props") as Node2D
	if props != null:
		# Plat_48_144 只铺到 x=48..104。碑宽 28、以脚点为中心，放在石台东侧：
		# 中线 76 会探到 Kiln_LowTower 窑核（悬在台西沿上方 24px）身上。
		_add_registry_stele(props, Vector2(88, 144), "SteleForge")
		# 枯树右缘 264，「腐液」牌面从 283 起。碑站到坑东岸的矮唇上（512..552）：
		# 站在地面 320 时碑身左下会嵌进 PitStepLow 土丘，右缘还会贴上 x=568 的锈块。
		_add_registry_stele(props, Vector2(532, 304), "SteleCoolant")

	var decor_layer := Node2D.new()
	decor_layer.name = "BastionDecor"
	decor_layer.z_index = -2
	add_child(decor_layer)
	# 女墙 80×52，底边贴地面。墓园夜空不用 64×192 的壁炬墙板：
	# 那张贴图几乎是一块平的暗矩形，会挡掉月亮和远山。火在栏杆贴图上。
	_add_balustrade(decor_layer, Vector2(1000, GROUND_TOP))
	_add_balustrade(decor_layer, Vector2(1236, GROUND_TOP))


## 碑文文本从 ChapterText 取；位置常量留在本文件（几何归关卡，文本归注册表）。
func _add_registry_stele(parent: Node2D, pos: Vector2, stele_name: String) -> void:
	var entry := ChapterText.stele_of("level01", stele_name)
	_add_stele(parent, pos, stele_name, String(entry.get("title", "")), String(entry.get("text", "")))


func _add_stele(parent: Node2D, pos: Vector2, stele_name: String, title: String, text: String) -> void:
	if STELE_SCENE == null:
		return
	var stele: Node2D = STELE_SCENE.instantiate()
	stele.name = stele_name
	stele.position = pos
	stele.set("lore_title", title)
	stele.set("lore_text", text)
	parent.add_child(stele)


## feet = 底边中点。贴图向上长，底边落在 feet.y。
func _add_balustrade(parent: Node2D, feet: Vector2) -> void:
	if not ResourceLoader.exists(BALUSTRADE_TEX):
		return
	var tex := DensityTextures.load_texture(BALUSTRADE_TEX)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.position = Vector2(feet.x - float(tex.get_width()) * 0.5, feet.y - float(tex.get_height()))
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(0.75, 0.7, 0.8, 0.85)
	spr.set_meta("feet", feet)
	spr.add_to_group("grounded")
	parent.add_child(spr)


func _build_parallax_extras() -> void:
	var extras := Level01Parallax.new()
	extras.name = "ParallaxExtras"
	add_child(extras)
	extras.build(self)
	_add_visual_enhancements()


func _extend_east() -> void:
	_wing = Level01EastWing.new()
	_wing.name = "EastWing"
	add_child(_wing)
	_boss = _wing.build(self)


func _bind_story() -> void:
	_beats = Level01StoryBeats.new()
	_beats.name = "StoryBeats"
	add_child(_beats)
	_beats.bind(self, _player, _boss)
	if _wing != null:
		if not _wing.boss_gate_entered.is_connected(_beats.on_boss_gate):
			_wing.boss_gate_entered.connect(_beats.on_boss_gate)
		if not _wing.boss_slain.is_connected(_beats.on_boss_slain):
			_wing.boss_slain.connect(_beats.on_boss_slain)


func _try_wake() -> void:
	if _beats != null:
		_beats.try_wake()
	SaveData.entering_from_checkpoint = false


static func should_spawn_executioner() -> bool:
	return Level01EastWing.should_spawn_executioner()


static func should_unlock_forge() -> bool:
	return Level01EastWing.should_unlock_forge()


static func east_floor_rect() -> Rect2:
	return Level01EastWing.east_floor_rect()


static func mark_executioner_slain() -> void:
	Level01EastWing.mark_executioner_slain()


## 视觉增强：光照 + 场景细节
## Off: phase-3 LightPool owns chapter-1 fire light (see _add_visual_enhancements).
const PLANT_AMBIENT_LIGHTS := false


func _add_visual_enhancements() -> void:
	# 场景细节：PropCatalog 的真实贴图（脚点钉台面、1x 最近邻），画在玩法层后面。
	var details_layer := Node2D.new()
	details_layer.name = "SceneDetails"
	details_layer.z_index = -1  # 在玩法层后面
	add_child(details_layer)
	SceneDetails.populate_level01(self, details_layer)

	# 环境光照：全部锚定到真实地标（余烬巢 / 毒池 / 门 / Boss 门 / 炉心），
	# 不再用写死坐标——关卡布局一改，光池跟着地标走。
	# Merge note: the landmark Light2D set (AmbientLighting) is not planted in chapter 1.
	# Fire light here is the phase-3 LightPool (follows each WorldLight's on/off state, so
	# an unlit nest stays dark); the always-on ambient lights re-lit the scene away from the
	# agreed grade. AmbientLighting / SceneDetails.add_level01_lighting stay available.
	if PLANT_AMBIENT_LIGHTS:
		var lighting := AmbientLighting.create_for_level(self)
		SceneDetails.add_level01_lighting(lighting, self)
