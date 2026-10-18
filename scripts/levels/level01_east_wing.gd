class_name Level01EastWing
extends Node
## Level01 east wing: pit beams, east floor, ember ledge, Boss, ForgeHeart, gate.
## Builds into the host's existing Platforms / Hooks / Pickups / Props folders
## so authored node paths stay valid. Not a PackedScene — instancing a sub-scene
## would reparent those nodes and break SaveData / story lookups.

const PLATFORM := preload("res://scenes/world/Platform.tscn")
const ANCHOR := preload("res://scenes/interactables/HookAnchor.tscn")
const PICKUP := preload("res://scenes/interactables/CorePickup.tscn")
const BOSS := preload("res://scenes/enemies/ExecutionerBoss.tscn")
const FORGE := preload("res://scenes/interactables/ForgeHeart.tscn")
const NEST := preload("res://scenes/interactables/EmberNest.tscn")
## 东侧余烬巢：Boss 门前最后一个存档点。没有它，死在刽子手手里要从 x=150 重走整条走廊。
const EMBER_NEST_EAST_POS := Vector2(1536, 306)

const EAST_LIMIT := 2240
const EAST_FLOOR_X := 1600.0
## Roofed forge remnant past the Executioner — indoor lighting, rain stops.
const FORGE_SHELTER_POS := Vector2(2112, 240)
const FORGE_SHELTER_SIZE := Vector2(256, 160)
## 刽子手的竞技场：中殿石板（1600..1984）正中的决斗位。两侧各一座落地锻炉
## 火膛给他打光、把他夹在构图里；中央一片加法暖池把舞台从暗背景里抬出来。
## 这三盏灯也是演出用灯：进场涌一下、二阶段转炽红、Boss 倒地后暗下去。
const ARENA_CENTER_X := 1860.0
const ARENA_HEARTH_Y := 320.0
const ARENA_HEARTH_LEFT_X := 1790.0
const ARENA_HEARTH_RIGHT_X := 1930.0
const ARENA_HEARTH_ENERGY := 0.72
const ARENA_HEARTH_HOT_ENERGY := 1.05
const ARENA_HEARTH_RADIUS := 96.0
const ARENA_HEARTH_COLOR := Color(1.0, 0.62, 0.33)
const ARENA_HEARTH_HOT_COLOR := Color(1.0, 0.36, 0.14)
## 死亡后舞台灯熄掉：交接镜头只剩残芯自己的 HeartLight 在亮。
const ARENA_DEAD_SCALE := 0.0
## 中央暖池：半径有上限，不把整块东翼石板刷白。
const ARENA_POOL_POS := Vector2(ARENA_CENTER_X, 300.0)
const ARENA_POOL_RADIUS := 148.0
const ARENA_POOL_ENERGY := 0.5
const ARENA_POOL_HOT_ENERGY := 0.72
const ARENA_POOL_COLOR := Color(1.0, 0.56, 0.28)
const ARENA_POOL_HOT_COLOR := Color(1.0, 0.40, 0.18)
## 火膛贴图的脚点：gh_furnace 32×96，节点原点在贴图中心（旧壁炬约定）。
const HEARTH_ART_H := 96.0
## 余烬高台 + 钩锁锚点。锚点必须在台子左端外侧上方：以前放在台子正中上方 (1568,48)，
## 从左下拉过去的直线穿过台子左端底面，一撞就按「撞墙」脱钩掉下去；从正下方拉则顶在
## 台底卡住。锚点在 x=1512（台左沿 1528 之外）时牵引线净空，脱钩后向右弹到台面上。
const EMBER_LEDGE_POS := Vector2(1528, 112)
const EMBER_LEDGE_SIZE := Vector2(80, 16)
const EMBER_HOOK_POS := Vector2(1512, 56)
## 毒坑可读跳：踏步 32px（单跳约 37px）。悬空石只铺在坑上，岸边用实心抵地唇，避免挡头。
const PIT_X0 := 400.0
const PIT_X1 := 512.0
const PIT_BANK_Y := 320.0
## 水面（ToxinPool 顶，雨的 surface_rect）。坑底再往下，但必须 ≤ 单跳到岸。
const PIT_WATER_Y := 336.0
## 旧底 368 深 48px，单跳够不着岸。抬到 352 后深 32px。
const PIT_FLOOR_Y := 352.0
const PIT_FLOOR_SIZE := Vector2(112, 48)
const PIT_LIP_LEFT_POS := Vector2(368, 304)
const PIT_LIP_LEFT_SIZE := Vector2(32, 32)
const PIT_CROSS_POS := Vector2(432, 288)
const PIT_CROSS_SIZE := Vector2(64, 16)
const PIT_STEP_LOW_POS := Vector2(512, 304)
const PIT_STEP_LOW_SIZE := Vector2(40, 32)
const PIT_STEP_HIGH_POS := Vector2(548, 272)
const PIT_STEP_HIGH_SIZE := Vector2(56, 16)
## 两岸水面矮唇：顶在液面，坐在坑底上。池底→唇 16px、唇→岸 16px，点按也能爬。
## 实心抵地，不留「台下夹人」的缝。
const PIT_CLIMB_LEFT_POS := Vector2(400, 336)
const PIT_CLIMB_LEFT_SIZE := Vector2(32, 16)
const PIT_CLIMB_RIGHT_POS := Vector2(480, 336)
const PIT_CLIMB_RIGHT_SIZE := Vector2(32, 16)

signal boss_gate_entered(body: Node)
signal boss_slain

var boss: ExecutionerBoss
var heart: ForgeHeart
var _arena_hearths: Array[TorchLight] = []
var _arena_pool: WorldLight
## 演出状态：0 = 一阶段暖炉，1 = 二阶段炽红；dim 1 = Boss 已倒、灯暗下去。
var _arena_heat := 0.0
var _arena_dim := 0.0
var _arena_surge := 0.0
var _arena_hot := false
var _arena_dead := false


static func should_spawn_executioner() -> bool:
	return not SaveData.has_flag("boss_dead")


static func should_unlock_forge() -> bool:
	return SaveData.has_flag("boss_dead")


## GroundRight in Level01_Static.tscn is (512, 320) size (1088, 80) → ends at 1600.
## Floor must reach EAST_LIMIT (WallRight) or the boss room drops 32px into the void.
static func east_floor_rect() -> Rect2:
	return Rect2(EAST_FLOOR_X, 320.0, float(EAST_LIMIT) - EAST_FLOOR_X, 80.0)


static func mark_executioner_slain() -> void:
	SaveData.mark_flag("boss_dead")
	SaveData.persist_story()


func build(host: Node2D) -> ExecutionerBoss:
	var platforms := host.get_node_or_null("Platforms") as Node2D
	var hooks := host.get_node_or_null("Hooks") as Node2D
	var pickups := host.get_node_or_null("Pickups") as Node2D
	var props := host.get_node_or_null("Props") as Node2D
	if platforms == null or hooks == null or pickups == null or props == null:
		return null

	# 旧低梁 (424,300) 挡地面行人头顶；旧小台 (496,336) 埋进土。
	# 现链：左岸唇 32px → 坑中踏石同高 → 右岸唇 32px → 高台再 32px。
	# 掉进坑：抬高的坑底 + 两岸矮唇，单跳就能爬回地面（腐液照咬）。
	_tune_toxin_pit(platforms)
	_place_pit_step(platforms, "PitClimbLeft", "ground", PIT_CLIMB_LEFT_POS, PIT_CLIMB_LEFT_SIZE)
	_place_pit_step(platforms, "PitClimbRight", "ground", PIT_CLIMB_RIGHT_POS, PIT_CLIMB_RIGHT_SIZE)
	_place_pit_step(platforms, "PitLipLeft", "ground", PIT_LIP_LEFT_POS, PIT_LIP_LEFT_SIZE)
	_place_pit_step(platforms, "PitCross", "floating", PIT_CROSS_POS, PIT_CROSS_SIZE)
	_place_pit_step(platforms, "PitStepLow", "ground", PIT_STEP_LOW_POS, PIT_STEP_LOW_SIZE)
	_place_pit_step(platforms, "PitStepHigh", "floating", PIT_STEP_HIGH_POS, PIT_STEP_HIGH_SIZE)
	var wall := platforms.get_node_or_null("WallRight") as Node2D
	if wall:
		wall.position.x = float(EAST_LIMIT)
	var floor_rect := east_floor_rect()
	var floor := PLATFORM.instantiate()
	floor.name = "EastFloor"
	# 墓园草皮到此为止：刽子手的中殿铺的是教堂石板，脚下换材质就是换区。
	floor.skin = "stone"
	floor.position = floor_rect.position
	floor.size = floor_rect.size
	floor.cap_left = false
	floor.cap_right = false
	platforms.add_child(floor)
	var ledge := PLATFORM.instantiate()
	ledge.name = "EmberLedge"
	ledge.skin = "floating"
	ledge.position = EMBER_LEDGE_POS
	ledge.size = EMBER_LEDGE_SIZE
	platforms.add_child(ledge)
	var hook := ANCHOR.instantiate()
	hook.name = "Hook_Ember"
	hook.position = EMBER_HOOK_POS
	hooks.add_child(hook)
	var ember := PICKUP.instantiate() as CorePickup
	ember.name = "EmberCore"
	ember.position = Vector2(1568, 96)
	ember.core = AbilityCatalog.ember_core()
	pickups.add_child(ember)
	var shrine := props.get_node_or_null("PurificationShrine") as Node2D
	if shrine:
		shrine.position = Vector2(1464, 288)
	if props.get_node_or_null("EmberNestEast") == null:
		var nest := NEST.instantiate()
		nest.name = "EmberNestEast"
		nest.position = EMBER_NEST_EAST_POS
		props.add_child(nest)
	if should_spawn_executioner():
		boss = BOSS.instantiate()
		boss.position = Vector2(1860, 320)
		props.add_child(boss)
		boss.slain.connect(_on_boss_slain)
	heart = FORGE.instantiate()
	heart.position = Vector2(2064, 292)
	heart.name = "ForgeHeart"
	props.add_child(heart)
	if should_unlock_forge():
		heart.unlock()
	else:
		heart.lock()
	var zone := Area2D.new()
	zone.name = "BossGate"
	zone.collision_layer = 0
	zone.collision_mask = 2
	zone.monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 80)
	shape.shape = rect
	zone.add_child(shape)
	zone.position = Vector2(1688, 280)
	host.add_child(zone)
	zone.body_entered.connect(_on_boss_gate)
	place_forge_shelter(host)
	_decorate_cathedral(host)
	_build_boss_arena(host)
	return boss


const TORCH_SCENE := preload("res://scenes/world/TorchLight.tscn")
const STELE_SCENE := preload("res://scenes/interactables/LoreStele.tscn")


func _decorate_cathedral(host: Node2D) -> void:
	if host.get_node_or_null("CathedralDecor") != null:
		return
	var decor := Node2D.new()
	decor.name = "CathedralDecor"
	decor.z_index = -3
	host.add_child(decor)

	# Level01 keeps the open graveyard sky for the whole map. Tall indoor wall
	# plates (columns, skull columns, gargoyles, nave torch slabs) read as
	# floating masonry against the moon and purple mountains — especially near
	# the 东翼 sign and EmberLedge. Only low door/rails/rubble on the approach,
	# and roofed forge-remnant art under ForgeShelter.
	_plant_env_sprite(decor, "res://assets/env/door_arch.png", Vector2(1672, 256), Vector2(1, 1), Color(0.85, 0.82, 0.95, 0.95))

	# Low bastion rails along the nave — shared with the west cemetery, not
	# 192px indoor slabs over open sky. 东侧栏杆退到炉棚前，让出右火膛的位置。
	_plant_balustrade(decor, Vector2(1730, 320))
	_plant_balustrade(decor, Vector2(1988, 320))

	# Forge remnant under the shelter roof (altar + one wall torch).
	_plant_ruin_plate(decor, "res://assets/env/bg_altar_cut.png", Vector2(2004, 128), Vector2(1, 1), Color(0.85, 0.75, 0.7, 0.88))
	_plant_torch(decor, Vector2(2064, 224))

	# 矮墩上的残石：以前这里是 48×48 的地台铺石板（平顶方块），
	# 单独立在墓地行里读不懂；换成有轮廓的碎石，和旁边的 rubble_b 同一族。
	_plant_env_sprite(decor, "res://assets/env/rubble_c.png", Vector2(1724, 296), Vector2(1, 1), Color(0.7, 0.65, 0.75, 0.9))
	_plant_env_sprite(decor, "res://assets/env/rubble_b.png", Vector2(1810, 290), Vector2(1, 1), Color(0.7, 0.65, 0.75, 0.9))
	_plant_env_sprite(decor, "res://assets/env/rubble_b.png", Vector2(1990, 290), Vector2(1, 1), Color(0.7, 0.65, 0.75, 0.9))
	# 矮烟囱：32×96，脚在石板路上，顶不穿过女墙。放在拱门西侧，不挡刽子手的斧。
	_plant_env_sprite(decor, "res://assets/env/gh_furnace.png", Vector2(1616, 224), Vector2(1, 1), Color(0.78, 0.62, 0.48, 0.95))

	var vow := ChapterText.stele_of("level01", "SteleExecutioner")
	_plant_lore_stele(host, Vector2(1636, 320), "SteleExecutioner",
			String(vow.get("title", "")), String(vow.get("text", "")))


func _plant_balustrade(parent: Node2D, feet: Vector2) -> void:
	const PATH := "res://assets/env/balustrade.png"
	if not ResourceLoader.exists(PATH):
		return
	var tex := load(PATH) as Texture2D
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(feet.x - float(tex.get_width()) * 0.5, feet.y - float(tex.get_height()))
	spr.modulate = Color(0.75, 0.7, 0.8, 0.85)
	_mark_ground(spr, feet)
	parent.add_child(spr)


func _plant_env_sprite(parent: Node2D, path: String, pos: Vector2, scl: Vector2 = Vector2.ONE, tint: Color = Color.WHITE) -> Sprite2D:
	if not ResourceLoader.exists(path):
		return null
	var spr := Sprite2D.new()
	spr.texture = load(path) as Texture2D
	spr.centered = false
	spr.position = pos
	spr.scale = scl
	spr.modulate = tint
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(spr)
	return spr


## Same footprint as _plant_env_sprite (top-left at pos, scaled, tinted), but the
## plate goes through RuinPlate so its crown is broken instead of a ruler edge.
func _plant_ruin_plate(parent: Node2D, path: String, pos: Vector2, scl: Vector2 = Vector2.ONE, tint: Color = Color.WHITE) -> Node2D:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var root := Node2D.new()
	root.name = "Ruin_%s" % path.get_file().get_basename()
	root.position = pos
	root.scale = scl
	root.modulate = tint
	parent.add_child(root)
	RuinPlate.build(root, tex, pos)
	return root


func _plant_torch(parent: Node2D, pos: Vector2) -> void:
	if TORCH_SCENE == null:
		return
	var torch: Node2D = TORCH_SCENE.instantiate()
	torch.position = pos
	torch.set_meta("feet", pos + Vector2(0.0, 96.0))
	torch.add_to_group("grounded")
	parent.add_child(torch)


## feet is the bottom-centre. Returns the top-left that puts the texture there.
func _plate_topleft(path: String, feet: Vector2, scale: float) -> Vector2:
	var tex := load(path) as Texture2D
	var w := float(tex.get_width()) * scale
	var h := float(tex.get_height()) * scale
	return Vector2(feet.x - w * 0.5, feet.y - h)


## Keep an authored left edge: the foot x is the centre of that span.
func _plate_feet(path: String, left_x: float, feet_y: float, scale: float) -> Vector2:
	var tex := load(path) as Texture2D
	return Vector2(left_x + float(tex.get_width()) * scale * 0.5, feet_y)


func _mark_ground(node: Node2D, feet: Vector2) -> void:
	if node == null:
		return
	node.set_meta("feet", feet)
	node.add_to_group("grounded")


func _plant_lore_stele(parent: Node2D, pos: Vector2, stele_name: String, title: String, text: String) -> void:
	var props := parent.get_node_or_null("Props") as Node2D
	if props == null:
		props = parent
	if STELE_SCENE == null:
		return
	var stele: Node2D = STELE_SCENE.instantiate()
	stele.name = stele_name
	stele.position = pos
	stele.set("lore_title", title)
	stele.set("lore_text", text)
	props.add_child(stele)


static func pit_floor_to_bank() -> float:
	return PIT_FLOOR_Y - PIT_BANK_Y


static func water_to_bank() -> float:
	return PIT_WATER_Y - PIT_BANK_Y


func _tune_toxin_pit(platforms: Node2D) -> void:
	var pit := platforms.get_node_or_null("ToxinPit") as SolidPlatform
	if pit == null:
		return
	if absf(pit.position.y - PIT_FLOOR_Y) <= 0.01 and pit.size == PIT_FLOOR_SIZE:
		return
	var skin := pit.skin
	var tone := pit.tone
	var fill := pit.fill
	var cap := pit.cap_surface
	pit.free()
	var fresh: SolidPlatform = PLATFORM.instantiate()
	fresh.name = "ToxinPit"
	fresh.skin = skin
	fresh.tone = tone
	fresh.fill = fill
	fresh.cap_surface = cap
	fresh.position = Vector2(PIT_X0, PIT_FLOOR_Y)
	fresh.size = PIT_FLOOR_SIZE
	platforms.add_child(fresh)


func _place_pit_step(platforms: Node2D, node_name: String, skin: String, pos: Vector2, size: Vector2) -> void:
	if platforms.get_node_or_null(node_name) != null:
		return
	var step: SolidPlatform = PLATFORM.instantiate()
	step.name = node_name
	step.skin = skin
	step.position = pos
	step.size = size
	platforms.add_child(step)


static func place_forge_shelter(host: Node2D) -> AtmosphereZone:
	var existing := host.get_node_or_null("ForgeShelter") as AtmosphereZone
	if existing != null:
		return existing
	var shelter := AtmosphereZone.new()
	shelter.name = "ForgeShelter"
	shelter.zone = WorldClock.Zone.INDOORS
	shelter.position = FORGE_SHELTER_POS
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = FORGE_SHELTER_SIZE
	shape.shape = rect
	shelter.add_child(shape)
	var pool := WorldLight.new()
	pool.name = "WarmPool"
	pool.follow = &"indoor"
	pool.lit = true
	pool.color = Color(1.0, 0.62, 0.38)
	# Sit under the roof occluder. Clock radius 220 leaks past the 256×160 remnant.
	pool.position = Vector2(0.0, -8.0)
	pool.radius_cap = 108.0
	shelter.add_child(pool)
	_add_shelter_occluders(shelter)
	host.add_child(shelter)
	return shelter


## Thin walls + roof. Left wall leaves a door so the arena reads as an opening,
## not a sealed box. Ground platform already occludes the floor.
static func _add_shelter_occluders(shelter: AtmosphereZone) -> void:
	var hw := FORGE_SHELTER_SIZE.x * 0.5
	var hh := FORGE_SHELTER_SIZE.y * 0.5
	const THICK := 8.0
	const DOOR := 64.0
	shelter.add_child(_box_occluder("RoofOccluder", Rect2(-hw, -hh, FORGE_SHELTER_SIZE.x, THICK)))
	shelter.add_child(_box_occluder("WallROccluder", Rect2(hw - THICK, -hh, THICK, FORGE_SHELTER_SIZE.y)))
	shelter.add_child(_box_occluder("WallLOccluder", Rect2(-hw, -hh, THICK, FORGE_SHELTER_SIZE.y - DOOR)))


static func _box_occluder(node_name: String, rect: Rect2) -> LightOccluder2D:
	var occ := LightOccluder2D.new()
	occ.name = node_name
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	])
	occ.occluder = poly
	return occ


## Boss 竞技场的舞台灯（演出用，见文件头 const 注释）。三盏灯都走现有 WorldLight：
## 两座落地锻炉火膛（TorchLight 的 furnace 样式，复用 gh_furnace 贴图与壁炬逻辑）
## 左右夹住刽子手，中央一片加法暖池照亮中殿石板。灯本身在玩法层（z<0），不遮剪影。
func _build_boss_arena(host: Node2D) -> void:
	if host.get_node_or_null("ArenaPresentation") != null:
		return
	var layer := Node2D.new()
	layer.name = "ArenaPresentation"
	host.add_child(layer)
	for x in [ARENA_HEARTH_LEFT_X, ARENA_HEARTH_RIGHT_X]:
		_plant_arena_hearth(layer, x)
	_arena_pool = WorldLight.new()
	_arena_pool.name = "ArenaPool"
	_arena_pool.follow = &"authored"
	_arena_pool.authored_radius = ARENA_POOL_RADIUS
	_arena_pool.radius_cap = ARENA_POOL_RADIUS
	_arena_pool.color = ARENA_POOL_COLOR
	_arena_pool.lit = true
	_arena_pool.set_base_energy(ARENA_POOL_ENERGY)
	_arena_pool.position = ARENA_POOL_POS
	layer.add_child(_arena_pool)
	# WorldLight._ready() 会打开阴影。氛围暖池只照亮石板 / 墙体，不参与遮挡计算，
	# 也不让台面把光挡在自己外面。
	_arena_pool.shadow_enabled = false
	_arena_pool.apply(true)
	# 演出接线：进场涌光、二阶段转炽红。死亡由 boss.slain 自己接（build 里已连）。
	if not GameEvents.boss_intro_started.is_connected(_on_boss_intro_started):
		GameEvents.boss_intro_started.connect(_on_boss_intro_started)
	if not GameEvents.boss_phase_changed.is_connected(_on_boss_phase_changed):
		GameEvents.boss_phase_changed.connect(_on_boss_phase_changed)


func _plant_arena_hearth(parent: Node2D, x: float) -> void:
	var hearth: TorchLight = TORCH_SCENE.instantiate()
	hearth.name = "ArenaHearth%d" % int(x)
	# 炉火口比教堂壁炬矮、贴地：gh_furnace 32×96 的砖炉膛，火在炉口。
	hearth.style = "furnace"
	hearth.light_color = ARENA_HEARTH_COLOR
	hearth.base_energy = ARENA_HEARTH_ENERGY
	hearth.light_radius = ARENA_HEARTH_RADIUS
	hearth.position = Vector2(x, ARENA_HEARTH_Y - HEARTH_ART_H)
	# 接地审计：脚点写在节点上（世界坐标经父节点换算），和壁炬同一套约定。
	hearth.set_meta("feet", Vector2(x, ARENA_HEARTH_Y))
	hearth.add_to_group("grounded")
	parent.add_child(hearth)
	_arena_hearths.append(hearth)


func _process(_delta: float) -> void:
	if _arena_hearths.is_empty():
		return
	var lit := lerpf(1.0, ARENA_DEAD_SCALE, _arena_dim)
	for hearth in _arena_hearths:
		if not is_instance_valid(hearth):
			continue
		var light := hearth.get_node_or_null("FlameGlow") as WorldLight
		if light == null:
			continue
		light.color = ARENA_HEARTH_COLOR.lerp(ARENA_HEARTH_HOT_COLOR, _arena_heat)
		light.set_base_energy(
				lerpf(ARENA_HEARTH_ENERGY, ARENA_HEARTH_HOT_ENERGY, _arena_heat)
				* lit * (1.0 + _arena_surge))
	if _arena_pool != null and is_instance_valid(_arena_pool):
		_arena_pool.color = ARENA_POOL_COLOR.lerp(ARENA_POOL_HOT_COLOR, _arena_heat)
		_arena_pool.set_base_energy(
				lerpf(ARENA_POOL_ENERGY, ARENA_POOL_HOT_ENERGY, _arena_heat)
				* lit * (1.0 + _arena_surge * 0.7))


## 进场那一拍：门砸下 + 炉火涌起（灯先亮到上限再落回一阶段亮度）。
func surge_arena_lights() -> void:
	if _arena_dead or not is_inside_tree() or get_tree() == null:
		return
	var tween := create_tween()
	tween.tween_method(_set_arena_surge, _arena_surge, 1.0, 0.14)
	tween.tween_method(_set_arena_surge, 1.0, 0.0, 0.9).set_trans(Tween.TRANS_SINE)


func _set_arena_surge(value: float) -> void:
	_arena_surge = maxf(value, 0.0)


## 二阶段：中殿的炉火转炽红。只动灯色/亮度，不碰输入、时间或敌人状态。
func _set_arena_hot(hot: bool) -> void:
	if _arena_hot == hot:
		return
	_arena_hot = hot
	if not is_inside_tree() or get_tree() == null:
		_arena_heat = 1.0 if hot else 0.0
		return
	var tween := create_tween()
	tween.tween_method(_set_arena_heat, _arena_heat, 1.0 if hot else 0.0, 0.45)


func _set_arena_heat(value: float) -> void:
	_arena_heat = clampf(value, 0.0, 1.0)


## 倒地：竞技场暗下去，交接镜头只剩残芯的 HeartLight 在亮。
func _dim_arena_lights() -> void:
	if _arena_dead:
		return
	_arena_dead = true
	if not is_inside_tree() or get_tree() == null:
		_arena_dim = 1.0
		return
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_method(_set_arena_dim, _arena_dim, 1.0, 1.5)


func _set_arena_dim(value: float) -> void:
	_arena_dim = clampf(value, 0.0, 1.0)


func _on_boss_intro_started(_boss_name: String) -> void:
	surge_arena_lights()
	if boss != null and is_instance_valid(boss) and not boss.is_queued_for_deletion():
		boss.presentation_surge()


func _on_boss_phase_changed(_boss_name: String, phase: int) -> void:
	if phase >= 2:
		_set_arena_hot(true)


# --- test / diagnostic views -------------------------------------------------
func arena_hearth_count() -> int:
	return _arena_hearths.size()


func arena_lights_hot() -> bool:
	return _arena_hot


func arena_lights_dimmed() -> bool:
	return _arena_dead


func arena_light_energy() -> float:
	if _arena_hearths.is_empty():
		return 0.0
	var light := _arena_hearths[0].get_node_or_null("FlameGlow") as WorldLight
	return light._base_energy if light != null else 0.0


func _on_boss_gate(body: Node) -> void:
	if body is Player and boss != null and is_instance_valid(boss):
		boss.announce()
	boss_gate_entered.emit(body)


func _on_boss_slain() -> void:
	# Boss 一倒，舞台灯先暗下去；残芯的 HeartLight 和新解锁的可交互性才是下一拍的焦点。
	_dim_arena_lights()
	boss_slain.emit()
