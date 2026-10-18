extends Node2D
## Fx autoload: presentation-only particle effects — drifting embers, dust
## puffs, weapon-hit sparks, rust debris, and toxin bubbles. Pure visuals,
## never gameplay state. Headless runs and missing art degrade silently.
##
## Particles are lightweight self-managing Node2D/Polygon2D squares or
## Sprite2D sheet cuts (no GPUParticles2D). One-shot effects parent here in
## world space and free themselves; attach_ember parents to its target so
## scene reloads clean it up automatically.

const WEAPONHIT_SHEET_PATH := "res://assets/kenney_clean/vfx/10_weaponhit_spritesheet.png"
const BRIGHTFIRE_SHEET_PATH := "res://assets/kenney_clean/vfx/9_brightfire_spritesheet.png"

## One-shot particles live under this autoload, which sits early in the tree
## (autoloads come before the current scene), so z_index must lift them above
## scene content to stay visible.
const FX_Z := 100
const MOTE_CAP := 48
const RING_CAP := 4
## 精灵火花 / 一次性帧动画的同屏上限（预算表见 CombatRules.BUDGET）。超出时火花
## 退化为池化小方块，尸体动画直接跳过；两者都只是表现，不影响逻辑。
const SPARK_CAP := 6
const ONESHOT_CAP := 8
const HEAT_LICK_NAME := "HeatLick"

const EMBER_FIELD_NAME := "FxEmberField"

## 环境打击（火球撞地 / 剑刃扫墙）走 ImpactCatalog 的表现表；痕迹放进每个世界
## 自己的 DecalField（环形复用，上限 24）。
const ImpactCatalog := preload("res://scripts/data/impact_catalog.gd")
const DecalField := preload("res://scripts/world/decal_field.gd")

var _headless := false
var _weaponhit_sheet: Texture2D = null
var _brightfire_sheet: Texture2D = null
var _pool_root: Node2D
var _motes: Array[PooledMote] = []
var _rings: Array[PooledRing] = []
var _mote_cursor := 0
var _ring_cursor := 0
var _live_sparks := 0
var _live_oneshots := 0
## 环境打击计数（headless 也记）：测试用它验证火球撞地只触发一次、
## 剑刃每刀对同一面只触发一次。
var _impact_count := 0
var _last_impact: Dictionary = {}
var _decal_field: Node = null
static var _additive: CanvasItemMaterial = null


static func next_slot(cursor: int, cap: int) -> int:
	if cap <= 0:
		return 0
	return posmod(cursor, cap)


## 预算判定：live 未满才允许再生成一个临时节点。
static func has_room(live: int, cap: int) -> bool:
	return live < cap


## 池是否需要重建：池已离树 / 还没建过 / 它挂的宿主不是当前世界的特效节点。
static func pool_needs_rebuild(pool_alive: bool, has_motes: bool, pool_parent: Object,
		host: Object) -> bool:
	return not pool_alive or not has_motes or pool_parent != host


## 同屏临时节点的实时数目（测试 / 诊断读）。headless 恒为 0。
func live_sparks() -> int:
	return _live_sparks


func live_oneshots() -> int:
	return _live_oneshots


func _on_spark_gone() -> void:
	_live_sparks = maxi(0, _live_sparks - 1)


func _on_oneshot_gone() -> void:
	_live_oneshots = maxi(0, _live_oneshots - 1)


func burst_cap() -> int:
	return 0 if _headless else MOTE_CAP


func burst_live_count() -> int:
	if _headless:
		return 0
	var n := 0
	for mote in _motes:
		if is_instance_valid(mote) and mote.alive:
			n += 1
	return n


## Shared additive material so night CanvasModulate cannot crush 2px motes.
static func additive_mat() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		set_process(false)
		return
	if ResourceLoader.exists(WEAPONHIT_SHEET_PATH):
		_weaponhit_sheet = load(WEAPONHIT_SHEET_PATH) as Texture2D
	if ResourceLoader.exists(BRIGHTFIRE_SHEET_PATH):
		_brightfire_sheet = load(BRIGHTFIRE_SHEET_PATH) as Texture2D


## One-shot particles must render inside the world viewport. The level runs in
## GamePresentation's 640×360 SubViewport with its own World2D and camera, so
## anything parented to this autoload would sit in root-window space and never
## line up with the knight. Fall back to self for standalone scenes (TestArena).
func _effects_host() -> Node:
	var scene_tree := get_tree()
	if scene_tree != null and scene_tree.get_first_node_in_group("game_world") != null:
		var host := GameContext.world_effects()
		if host != null and host.is_inside_tree():
			return host
	return self


## Persistent embers drifting around a living actor (the ember knight keeps
## its trail). Idempotent: repeated calls never stack. The emitter parents to
## the target so death / reload_scene clears it with the target itself.
func attach_ember(target: Node2D) -> void:
	if _headless or target == null or not is_instance_valid(target):
		return
	if target.get_node_or_null(EMBER_FIELD_NAME) != null:
		return
	var field := EmberField.new()
	field.name = EMBER_FIELD_NAME
	field.sheet = _brightfire_sheet
	target.add_child(field)


## Dust kicked up by landing or dashing. Routed through the capped pixel pool.
func dust_puff(pos: Vector2, dir: float = 0.0) -> void:
	burst(&"dust", pos, dir)


## Weapon-hit flash: sprite sheet when present, otherwise pooled sparks.
func hit_sparks(pos: Vector2) -> void:
	if _headless:
		return
	if _weaponhit_sheet == null or not has_room(_live_sparks, SPARK_CAP):
		burst(&"spark", pos)
		return
	var spark := HitSpark.new(_weaponhit_sheet)
	spark.position = pos
	spark.z_index = FX_Z
	_live_sparks += 1
	spark.tree_exited.connect(_on_spark_gone)
	_effects_host().add_child(spark)


## Rust debris bursting out of a destroyed enemy.
func rust_debris(pos: Vector2) -> void:
	burst(&"rust", pos)


## 命中反馈矩阵的 Fx 出口：spark / debris 取自 CombatRules.HIT_FEEL 的种类名。
## 全部走预算池（sheet 火花走 SPARK_CAP），headless 什么也不建。
func hit_effect(spark: StringName, debris: StringName, ring: bool, pos: Vector2,
		dir: float = 0.0) -> void:
	if _headless:
		return
	match spark:
		&"sheet":
			hit_sparks(pos)
		&"metal", &"bone", &"ghost":
			burst(spark, pos, dir)
	match debris:
		&"rust":
			rust_debris(pos)
		&"bone", &"ghost":
			burst(debris, pos, dir + PI * 0.5)
	if ring:
		burst(&"ring", pos)


## 环境打击的累计次数与最后一次（材质/位置/分量），headless 下也可用。
func impact_count() -> int:
	return _impact_count


func last_impact() -> Dictionary:
	return _last_impact


func decal_field() -> Node:
	return _decal_field


func reset_impact_counters() -> void:
	_impact_count = 0
	_last_impact = {}


## 环境打击（火球撞地/墙、剑刃扫到地面/墙体）。只做表现，不造成伤害：
## 火花 + 碎屑 + 材质贴花 + 短辉光 + 音效 + 轻微震动，全部走现有预算池。
## headless 只记 impact_count/last_impact，不建任何节点。
func impact(material: StringName, pos: Vector2, normal: Vector2 = Vector2.UP,
		weight: StringName = &"light") -> void:
	var prof := ImpactCatalog.profile(material)
	var scale := ImpactCatalog.weight_scale(weight)
	_impact_count += 1
	_last_impact = {"material": material, "pos": pos, "weight": weight, "scale": scale}
	if _headless:
		return
	var dir := normal.angle()
	var spark := StringName(prof["spark"])
	var debris := StringName(prof["debris"])
	_impact_burst(spark, pos, dir, scale)
	if debris != &"none" and debris != spark:
		# 碎屑用 debris_* 变体：受重力、落到地面就停住再淡出，而不是在空中消失。
		_impact_burst(debris_burst_kind(debris), pos + normal * 2.0, dir, scale)
	_spawn_decals(StringName(prof["decal"]), material, pos, normal, scale)
	# 余烬类材质再补两粒飘起来的火点：砸地之后不是一瞬就干净。
	if material == &"dirt" or material == &"stone" or material == &"metal":
		burst(&"ember", pos + normal * -3.0, dir)
	_spawn_impact_flash(pos, prof["light"] as Color, float(prof["energy"]) * scale)
	var sfx := StringName(prof["sfx"])
	if sfx != &"":
		Sfx.play_at(sfx, pos, 0.1, float(prof["volume_db"]))
	Juice.shake(float(prof["shake"]) * scale, 90)


## 火花/碎屑的口径：碎屑用 debris_* 变体（会落地），火花保持短促。
static func debris_burst_kind(kind: StringName) -> StringName:
	match kind:
		&"dirt":
			return &"debris_dirt"
		&"stone":
			return &"debris_stone"
		&"metal", &"rust":
			return &"debris_metal"
		&"wood":
			return &"debris_wood"
		&"wet", &"wetsplash":
			return &"debris_wet"
	return kind


func _impact_burst(kind: StringName, pos: Vector2, dir: float, scale: float) -> void:
	var times := 1 if scale < 1.4 else 2
	for _i in times:
		burst(kind, pos + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)), dir)


func _spawn_decals(kind: StringName, material: StringName, pos: Vector2, normal: Vector2,
		scale: float) -> void:
	if kind == &"none":
		return
	var host := _effects_host()
	if host == null or not is_instance_valid(host):
		return
	if _decal_field == null or not is_instance_valid(_decal_field) \
			or _decal_field.get_parent() != host:
		if is_instance_valid(_decal_field):
			_decal_field.queue_free()
		_decal_field = DecalField.new()
		host.add_child(_decal_field)
	_decal_field.call(&"add", kind, material, pos, normal, scale)


func _spawn_impact_flash(pos: Vector2, tint: Color, energy: float) -> void:
	if energy <= 0.02:
		return
	var flash := ImpactFlash.new(tint, clampf(energy, 0.15, 1.4))
	flash.position = Vector2(roundf(pos.x), roundf(pos.y))
	_effects_host().add_child(flash)


## Budgeted pixel burst. Headless creates nothing. Exhausted slots recycle.
func burst(kind: StringName, pos: Vector2, dir: float = 0.0) -> void:
	if _headless:
		return
	_ensure_pool()
	if kind == &"ring":
		_fire_ring(pos)
		return
	var count := 5
	if kind == &"rust":
		count = 6
	elif kind == &"spark" or kind == &"ghost":
		count = 4
	elif kind == &"trail":
		count = 4
	elif kind == &"dirt" or kind == &"stone" or kind == &"wetsplash":
		count = 8
	elif kind == &"wood":
		count = 6
	elif kind == &"ember":
		count = 3
	elif kind == &"debris_dirt" or kind == &"debris_stone" or kind == &"debris_metal" \
			or kind == &"debris_wood" or kind == &"debris_wet":
		count = 4
	for i in count:
		var at := pos
		var aim := dir
		if kind == &"trail":
			at = pos + Vector2(cos(dir), sin(dir)) * (5.0 * float(i))
		else:
			aim = dir + randf_range(-0.75, 0.75)
		_fire_mote(kind, at, aim)


func attach_heat_lick(target: Node2D) -> void:
	if _headless or target == null or not is_instance_valid(target):
		return
	if target.get_node_or_null(HEAT_LICK_NAME) != null:
		return
	var lick := HeatLick.new()
	lick.name = HEAT_LICK_NAME
	lick.position = Vector2(18.0, -24.0)
	target.add_child(lick)


func detach_heat_lick(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var lick := target.get_node_or_null(HEAT_LICK_NAME)
	if lick != null:
		lick.queue_free()


func _ensure_pool() -> void:
	if _headless:
		return
	var host := _effects_host()
	# 池必须挂在「当前世界」的特效节点下：标题界面 / 两个世界之间的空档里第一次
	# burst 会把池挂到自动加载（根窗口坐标系），之后再用就画在错的视口里。
	# 所以宿主变了（或旧池已离树）就整池重建。
	var alive := is_instance_valid(_pool_root) and _pool_root.is_inside_tree()
	var parent: Object = _pool_root.get_parent() if alive else null
	if not pool_needs_rebuild(alive, not _motes.is_empty(), parent, host):
		return
	if is_instance_valid(_pool_root):
		_pool_root.queue_free()
	_motes.clear()
	_rings.clear()
	_mote_cursor = 0
	_ring_cursor = 0
	_pool_root = Node2D.new()
	_pool_root.name = "FxPool"
	_pool_root.z_index = FX_Z
	host.add_child(_pool_root)
	for i in MOTE_CAP:
		var mote := PooledMote.new()
		mote.name = "Mote%d" % i
		_pool_root.add_child(mote)
		_motes.append(mote)
	for i in RING_CAP:
		var ring := PooledRing.new()
		ring.name = "Ring%d" % i
		_pool_root.add_child(ring)
		_rings.append(ring)


func _fire_mote(kind: StringName, pos: Vector2, dir: float) -> void:
	if _motes.is_empty():
		return
	var mote: PooledMote = _motes[_mote_cursor]
	_mote_cursor = next_slot(_mote_cursor + 1, _motes.size())
	if is_instance_valid(mote):
		mote.launch(kind, pos, dir)


func _fire_ring(pos: Vector2) -> void:
	if _rings.is_empty():
		return
	var ring: PooledRing = _rings[_ring_cursor]
	_ring_cursor = next_slot(_ring_cursor + 1, _rings.size())
	if is_instance_valid(ring):
		ring.launch(pos)


## 世界坐标一次性帧动画（敌人死亡尸体动画/烟雾等）。播完自毁；headless 或
## 空帧列表时静默退化——调用方逻辑（queue_free 等）不受影响。
## `pos` 为脚底世界坐标；`baseline` 为帧画布内容的基线偏移
## （centered Sprite：-(画布高/2 - 底部透明边距)）。
func play_frames_once(frames: Array[Texture2D], pos: Vector2, fps: float,
		flip: bool = false, baseline: float = 0.0) -> void:
	if _headless or frames.is_empty() or not has_room(_live_oneshots, ONESHOT_CAP):
		return
	var player := OneShotFrames.new(frames, fps)
	player.position = pos + Vector2(0.0, baseline)
	player.flip_h = flip
	player.z_index = FX_Z
	_live_oneshots += 1
	player.tree_exited.connect(_on_oneshot_gone)
	_effects_host().add_child(player)


## 通用敌人死亡烟雾（Gothicvania cemetery 5 帧，44x52，底部留白 2px）。
func enemy_death_smoke(pos: Vector2) -> void:
	play_frames_once(CharFrames.anim("fx_enemy_death", "death"), pos, 12.0, false, -24.0)


## 毒池气泡：从池面上升的 1–2px 酸液泡，整数像素、竖直上升（带 1px 内摆动）。
## 以前这里用 Kenney 的 `20_magicbubbles` 彩色粒子喷溅表，再缩到 0.06–0.1 倍：
## 缩小后是一团乱码白点，玩家会误读成"明明没下雨却有雨滴打在水面"（用户报告）。
## 现在改用程序化像素泡；`tint` 跟池子的液面/毒雾一致（第 4 章橙色冷却液也成立）。
const BUBBLE_CAP := 16


func toxin_bubbles(parent: Node2D, rect: Rect2, tint: Color = Color(0.55, 0.95, 0.62)) -> void:
	if _headless:
		return
	if parent == null or not is_instance_valid(parent):
		return
	var alive := 0
	for child in parent.get_children():
		if child is ToxinBubble:
			alive += 1
	if alive >= BUBBLE_CAP:
		return
	var bubble := ToxinBubble.new(tint)
	bubble.position = (rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)).round()
	parent.add_child(bubble)


## 一次性帧序列播放器：固定 fps 播完即自由。像素素材 NEAREST。
class OneShotFrames extends Sprite2D:
	var _frames: Array[Texture2D] = []
	var _fps := 12.0
	var _age := 0.0


	func _init(frames: Array[Texture2D], fps: float) -> void:
		_frames = frames
		_fps = maxf(fps, 0.001)
		texture = _frames[0]
		centered = true
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


	func _process(delta: float) -> void:
		_age += delta
		var idx := int(_age * _fps)
		if idx >= _frames.size():
			queue_free()
			return
		if texture != _frames[idx]:
			texture = _frames[idx]


## Spawns and owns up to six drifting embers around the target's body.
## Actor origins sit near the feet, so embers spread upward and sideways.
class EmberField extends Node2D:
	const MAX_EMBERS := 3
	const SPAWN_INTERVAL := 0.7

	## brightfire 帧动画表（可为 null → EmberBit 回退为色块方形）。
	var sheet: Texture2D = null

	var _accum := 0.25


	func _process(delta: float) -> void:
		_accum += delta
		if _accum >= SPAWN_INTERVAL and get_child_count() < MAX_EMBERS:
			_accum = 0.0
			var bit := EmberBit.new(sheet)
			bit.position = Vector2(randf_range(-8.0, 8.0), randf_range(-40.0, -12.0))
			add_child(bit)


## One rising, swaying, fading ember. With the brightfire sheet available it
## plays a tiny flame-lick animation; otherwise an orange square (2-3 px).
class EmberBit extends Node2D:
	## brightfire: 8x8 grid of 100px frames, 61 frames populated.
	const SHEET_HFRAMES := 8
	const SHEET_VFRAMES := 8
	const SHEET_FRAME_COUNT := 61
	const FRAME_STEP := 0.09

	var _age := 0.0
	var _lifetime := 2.0
	var _rise := 8.0
	var _sway_amp := 6.0
	var _sway_freq := 2.0
	var _phase := 0.0
	var _sheet: Texture2D = null
	var _sprite: Sprite2D = null
	var _frame_start := 0


	func _init(sheet: Texture2D = null) -> void:
		_sheet = sheet
		_lifetime = randf_range(1.5, 3.0)
		_rise = randf_range(5.0, 12.0)
		_sway_amp = randf_range(4.0, 10.0)
		_sway_freq = randf_range(1.5, 3.5)
		_phase = randf() * TAU


	func _ready() -> void:
		if _sheet != null:
			_sprite = Sprite2D.new()
			_sprite.texture = _sheet
			_sprite.hframes = SHEET_HFRAMES
			_sprite.vframes = SHEET_VFRAMES
			_frame_start = randi_range(0, SHEET_FRAME_COUNT - 1)
			_sprite.frame = _frame_start
			# 100px 帧里的火苗 ~20px 高；缩到 ~5px 的余烬尺度。
			var s := randf_range(0.035, 0.055)
			_sprite.scale = Vector2(s, s)
			_sprite.modulate = Color(1.0, 0.62, 0.38, 0.55)
			add_child(_sprite)
			return
		var half := randf_range(1.0, 1.5)
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half),
		])
		poly.color = Palette.EMBER.lerp(Palette.TOXIC, randf() * 0.7)
		add_child(poly)


	func _process(delta: float) -> void:
		_age += delta
		if _age >= _lifetime:
			queue_free()
			return
		position.y -= _rise * delta
		position.x += sin(_age * _sway_freq + _phase) * _sway_amp * delta
		if _sprite != null:
			_sprite.frame = (_frame_start + int(_age / FRAME_STEP)) % SHEET_FRAME_COUNT
		var k := _age / _lifetime
		modulate.a = minf(k * 8.0, 1.0) * (1.0 - k)


## 一次性短辉光：加法混合的像素菱形环，0.11 秒烧完。不参与光照系统，
## 所以不会和关卡灯光/WorldLight 打架；只是让命中点在暗处"亮一下"。
class ImpactFlash extends Node2D:
	const LIFE := 0.09
	var _age := 0.0
	var _tint := Color.WHITE
	var _energy := 0.6


	func _init(tint: Color, energy: float) -> void:
		_tint = tint
		_energy = energy
		z_index = FX_Z - 1


	func _ready() -> void:
		material = Fx.additive_mat()


	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			queue_free()
			return
		modulate.a = 1.0 - _age / LIFE


	func _draw() -> void:
		# 实心像素圆：横条按半径逐行铺。颜色跟材质走（土黄/石灰/金属暖），
		# 不再有近白核心——之前那层白在草叶上会被读成"白方块"。
		var strength := clampf(_energy, 0.15, 1.4)
		var outer := Color(_tint.r, _tint.g, _tint.b, 0.16 * strength)
		var inner := Color(minf(_tint.r * 1.15, 1.0), minf(_tint.g * 1.1, 1.0),
				minf(_tint.b * 1.05, 1.0), 0.22 * strength)
		for r in [2, 4, 6]:
			var rr := int(r)
			for dy in range(-rr, rr + 1, 2):
				var w := int(sqrt(float(rr * rr - dy * dy)))
				if w <= 0:
					continue
				draw_rect(Rect2(float(-w), float(dy), float(w * 2), 2.0),
						inner if rr <= 2 else outer)




## Recycled pixel square. Hidden until launch; never queue_free.
class PooledMote extends Node2D:
	var alive := false
	var _settle := false
	var _vel := Vector2.ZERO
	var _drift := Vector2.ZERO
	var _age := 0.0
	var _life := 0.45
	var _grav := 90.0
	var _poly: Polygon2D


	func _ready() -> void:
		_poly = Polygon2D.new()
		_poly.polygon = PackedVector2Array([
			Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1),
		])
		_poly.material = Fx.additive_mat()
		add_child(_poly)
		visible = false
		set_process(false)


	func launch(kind: StringName, pos: Vector2, dir: float) -> void:
		alive = true
		visible = true
		set_process(true)
		_age = 0.0
		_settle = false
		_drift = pos
		position = Vector2(roundf(pos.x), roundf(pos.y))
		modulate.a = 1.0
		match kind:
			&"rust":
				_life = randf_range(0.45, 0.7)
				_grav = 160.0
				var ang := randf() * TAU
				_vel = Vector2(cos(ang), sin(ang)) * randf_range(36.0, 88.0)
				_vel.y -= 28.0
				_poly.color = Palette.RUST_LIGHT
			&"spark":
				_life = randf_range(0.28, 0.48)
				_grav = -16.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(8.0, 22.0)
				_vel.y -= randf_range(14.0, 36.0)
				_poly.color = Palette.EMBER
			&"trail":
				_life = randf_range(0.12, 0.22)
				_grav = 0.0
				_vel = Vector2(cos(dir), sin(dir)) * 8.0
				_poly.color = Color(1.0, 0.92, 0.78)
			&"metal":
				# 金属火星：短、快、亮，沿出手方向喷。
				_life = randf_range(0.16, 0.30)
				_grav = 60.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(60.0, 130.0)
				_vel.y -= randf_range(10.0, 40.0)
				_poly.color = Color(1.0, 0.93, 0.62)
			&"bone":
				# 骨渣：淡骨色，重力大，落得快。
				_life = randf_range(0.35, 0.6)
				_grav = 180.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(30.0, 70.0)
				_vel.y -= randf_range(24.0, 52.0)
				_poly.color = Color(0.88, 0.84, 0.74)
			&"ghost":
				# 灵雾：青白，几乎不受重力，缓缓上浮。
				_life = randf_range(0.4, 0.7)
				_grav = -30.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(8.0, 24.0)
				_vel.y -= randf_range(6.0, 20.0)
				_poly.color = Color(0.55, 0.95, 1.0)
			&"dirt":
				# 泥土碎块：受重力、落得快，锈土色。
				_life = randf_range(0.5, 0.8)
				_grav = 170.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(30.0, 70.0)
				_vel.y -= randf_range(20.0, 48.0)
				_poly.color = Palette.RUST_SHADOW.lerp(Palette.CONCRETE, randf() * 0.6)
			&"stone":
				# 石屑：灰白碎渣，重力最大。
				_life = randf_range(0.4, 0.7)
				_grav = 200.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(36.0, 84.0)
				_vel.y -= randf_range(18.0, 44.0)
				_poly.color = Palette.IRON.lerp(Palette.CONCRETE, randf() * 0.7)
			&"wood":
				# 木屑：暖褐，轻一点。
				_life = randf_range(0.4, 0.65)
				_grav = 150.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(26.0, 62.0)
				_vel.y -= randf_range(20.0, 46.0)
				_poly.color = Palette.RUST_DARK.lerp(Palette.EMBER_ASH, randf() * 0.45)
			&"wetsplash":
				# 水点：青白，短促地溅开。
				_life = randf_range(0.25, 0.45)
				_grav = 220.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(40.0, 92.0)
				_vel.y -= randf_range(20.0, 50.0)
				_poly.color = Palette.TEAL.lerp(Palette.FOG, randf() * 0.6)
			&"ember":
				# 落地溅起的余烬：向上飘、慢慢冷。
				_life = randf_range(0.35, 0.6)
				_grav = -20.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(10.0, 28.0)
				_vel.y -= randf_range(8.0, 24.0)
				_poly.color = Palette.EMBER.lerp(Palette.TOXIC, randf() * 0.5)
			&"debris_dirt":
				# 泥土碎屑：会落地。颜色压暗，避免在暗场景里读成白方块。
				_settle = true
				_life = randf_range(1.1, 1.6)
				_grav = 520.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(20.0, 52.0)
				_vel.y -= randf_range(8.0, 22.0)
				_poly.color = Palette.RUST_SHADOW.lerp(Palette.RUST_DARK, randf() * 0.6)
			&"debris_stone":
				_settle = true
				_life = randf_range(1.0, 1.5)
				_grav = 560.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(24.0, 58.0)
				_vel.y -= randf_range(6.0, 20.0)
				_poly.color = Palette.IRON.lerp(Palette.SHADOW, 0.35 + randf() * 0.3)
			&"debris_metal":
				_settle = true
				_life = randf_range(0.9, 1.3)
				_grav = 520.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(26.0, 62.0)
				_vel.y -= randf_range(6.0, 20.0)
				_poly.color = Palette.RUST_LIGHT.lerp(Palette.RUST_DARK, 0.55 + randf() * 0.25)
			&"debris_wood":
				_settle = true
				_life = randf_range(1.0, 1.5)
				_grav = 500.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(20.0, 54.0)
				_vel.y -= randf_range(8.0, 20.0)
				_poly.color = Palette.RUST_DARK.lerp(Palette.EMBER_ASH, 0.3)
			&"debris_wet":
				_settle = true
				_life = randf_range(0.9, 1.3)
				_grav = 560.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(22.0, 56.0)
				_vel.y -= randf_range(10.0, 24.0)
				_poly.color = Palette.TEAL.lerp(Palette.SHADOW, 0.45)
			_:
				_life = randf_range(0.32, 0.55)
				_grav = 90.0
				_vel = Vector2(cos(dir), sin(dir)) * randf_range(24.0, 58.0)
				_vel.y -= randf_range(16.0, 38.0)
				_poly.color = Palette.IRON.lerp(Palette.CONCRETE, randf()) * 1.35


	func _process(delta: float) -> void:
		if not alive:
			return
		_age += delta
		if _age >= _life:
			alive = false
			visible = false
			set_process(false)
			return
		_vel.y += _grav * delta
		_drift += _vel * delta
		position = Vector2(roundf(_drift.x), roundf(_drift.y))
		if _settle:
			_try_settle(delta)
		var k := _age / _life
		modulate.a = minf(k * 8.0, 1.0) * (1.0 - k)


	## 碎屑落到地面：贴住地表、停住，再用剩余寿命淡出（不再穿过地板消失）。
	func _try_settle(delta: float) -> void:
		var space := get_world_2d().direct_space_state
		if space == null:
			return
		var drop := maxf(6.0, absf(_vel.y) * delta + 6.0)
		var query := PhysicsRayQueryParameters2D.create(position, position + Vector2(0.0, drop), 1)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return
		_settle = false
		_vel = Vector2.ZERO
		_grav = 0.0
		position = Vector2(roundf(position.x), roundf((hit.get("position") as Vector2).y) - 1.0)
		_drift = position
		_life = minf(_life, _age + 0.45)


## A few ember licks parented to the sword visual while heat forge is socketed.
class HeatLick extends Node2D:
	const MAX_BITS := 3
	var _accum := 0.0


	func _process(delta: float) -> void:
		_accum += delta
		if _accum < 0.22 or get_child_count() >= MAX_BITS:
			return
		_accum = 0.0
		var bit := EmberBit.new(null)
		bit.position = Vector2(randf_range(6.0, 26.0), randf_range(-4.0, 6.0))
		add_child(bit)


## Sprite-sheet hit flash: 6 frames across, ~0.25 s, scale ~0.5.
class HitSpark extends Sprite2D:
	const DURATION := 0.25
	const FRAME_COUNT := 6

	var _age := 0.0


	func _init(sheet: Texture2D) -> void:
		texture = sheet
		hframes = 6
		vframes = 6
		scale = Vector2(0.5, 0.5)


	func _process(delta: float) -> void:
		_age += delta
		if _age >= DURATION:
			queue_free()
			return
		frame = mini(int(_age / DURATION * FRAME_COUNT), FRAME_COUNT - 1)


## One-pixel ring of dots. Recycled; expands and fades in about 0.35s.
class PooledRing extends Node2D:
	const DOTS := 10
	const LIFE := 0.35

	var alive := false
	var _age := 0.0
	var _dots: Array[Polygon2D] = []


	func _ready() -> void:
		for _i in DOTS:
			var dot := Polygon2D.new()
			dot.polygon = PackedVector2Array([
				Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1),
			])
			dot.color = Color(1.0, 0.95, 0.88)
			dot.material = Fx.additive_mat()
			add_child(dot)
			_dots.append(dot)
		visible = false
		set_process(false)


	func launch(pos: Vector2) -> void:
		alive = true
		visible = true
		set_process(true)
		_age = 0.0
		position = Vector2(roundf(pos.x), roundf(pos.y))
		modulate.a = 1.0


	func _process(delta: float) -> void:
		if not alive:
			return
		_age += delta
		if _age >= LIFE:
			alive = false
			visible = false
			set_process(false)
			return
		var k := _age / LIFE
		var radius := lerpf(4.0, 28.0, k)
		for i in _dots.size():
			var ang := TAU * float(i) / float(_dots.size())
			_dots[i].position = Vector2(roundf(cos(ang) * radius), roundf(sin(ang) * radius))
		modulate.a = 1.0 - k


## One small sludge bubble: three-frame wiggle, upward drift, fade-out pop.
## 一颗酸液泡：像素圆环，只朝上飘，到顶淡出。整数像素绘制、整数坐标，
## 半径 1–2px（不做小数缩放）。视觉上明确是"池子在冒泡"，不是水花/涟漪。
class ToxinBubble extends Node2D:
	var _age := 0.0
	var _lifetime := 1.2
	var _rise := 10.0
	var _phase := 0.0
	var _radius := 1
	var _tint := Color(0.55, 0.95, 0.62)
	var _pos := Vector2.ZERO
	var _started := false

	func _init(tint: Color) -> void:
		_tint = tint
		_lifetime = randf_range(0.8, 1.6)
		_rise = randf_range(8.0, 15.0)
		_phase = randf() * TAU
		_radius = randi_range(1, 2)
		z_index = 3
		set_process(true)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= _lifetime:
			queue_free()
			return
		# 单方向：只往上飘；横向只有 ±2px 的摆动，位置取整保持像素边缘。
		# 亚像素累计在 _pos 里，只把显示位置取整：直接对 position 取整时，60fps 下每帧
		# 位移 <0.5px 会被 round() 吃掉，气泡原地不动（toxin_bubbles_test 偶发失败）。
		if not _started:
			_pos = position
			_started = true
		_pos.y -= _rise * delta
		_pos.x += sin(_age * 2.2 + _phase) * 4.0 * delta
		position = _pos.round()
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / _lifetime, 0.0, 1.0)
		var a := minf(k * 6.0, 1.0) * clampf((1.0 - k) * 2.4, 0.0, 1.0) * 0.90
		if a <= 0.01:
			return
		# 颜色只用液面色调：**不要纯白高光**——纯白小点会被玩家读成"雨滴/闪光"，
		# 正是用户报告里"明明没下雨"的错觉来源之一。
		var glint := Color(
				_tint.r + (1.0 - _tint.r) * 0.42,
				_tint.g + (1.0 - _tint.g) * 0.34,
				_tint.b + (1.0 - _tint.b) * 0.42, a)
		var body := Color(_tint.r * 0.80, _tint.g * 0.88, _tint.b * 0.80, a * 0.80)
		var rim := Color(_tint.r * 0.52, _tint.g * 0.66, _tint.b * 0.52, a * 0.85)
		if _radius <= 1:
			# 单像素泡：一颗亮点 + 下方 1px 暗边（读作气泡，不是环形）
			draw_rect(Rect2(0, 0, 1, 1), glint)
			draw_rect(Rect2(0, 1, 1, 1), rim)
			return
		# 3×3 小圆泡：上下暗边、左右液色、中心一点亮。缩到 1px 时仍是一团，
		# 不会变成"八点扩散环"。
		draw_rect(Rect2(0, -1, 1, 1), rim)
		draw_rect(Rect2(-1, 0, 3, 1), body)
		draw_rect(Rect2(0, 1, 1, 1), rim)
		draw_rect(Rect2(0, 0, 1, 1), glint)


