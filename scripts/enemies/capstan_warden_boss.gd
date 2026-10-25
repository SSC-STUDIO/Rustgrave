class_name CapstanWardenBoss
extends EnemyBase
## 绞盘守渠人（level02b · 运渣水渠的 Boss）。驾驶模式接入 BossKit/BossDirector/BossArena：
## 导演层按攻击表选招发 attack_requested(id)，本脚本执行前摇 -> 判定 -> 后摇，
## 收招 notify_attack_finished()，死亡 notify_death()。
##
## 人物（docs/story.md §2/§5）：他把八百下闸绞到底，锁着往上城的水。渠里漂着成排刻名字的剑。
## 可读性：链扫（横向 lane）/ 蒸汽柱（落点 zone）/ 开闸放水（场地一侧水位上升 + 推力）/
## 召唤碎铁犬；每次**泄压**时身侧的泄压阀是破防窗口（砸开 = 2 倍破绽 + 硬直）。
## 每招前摇 >= 0.35s，导演层串行出招 -> 同一时刻只有一条预警。
##
## 原创潜水甲、水平双绞筒与链锚，源稿tools/gen_original_choir_warden.py。

signal slain

## 帧素材：与齿轮盾卫共用（100×100，原图面朝左，脚底距底边 16.5px）。
const EXEC_CHAR := "original_capstan_warden"
const EXEC_POS := Vector2(0.0, -51.0)
const EXEC_DEATH_BASELINE := -51.0
const BODY_SIZE := Vector2(30, 52)
const HURT_SIZE := Vector2(40, 68)

const BOSS_TITLE := "绞盘守渠人 · 八百下闸"
const BOSS_SUBTITLE := "水渠的最后一班"
const BOSS_ID := &"capstan_warden"
const MAX_HP := 16
const DEATH_FLAG := &"capstan_dead"
## 冷青剪影：帧素材的近黑主色被冷色抬亮，地窖暗部里也能读出体块（骑士仍比 Boss 亮）。
const COLD_TINT := Color(0.95, 1.05, 1.08)
const COLD_TINT_P2 := Color(1.05, 1.12, 1.10)
## 背后的冷光 / 接地阴影：把 1× 剪影从深色砖墙上剥出来（不遮玩法层）。
const GLOW_TINT := Color(0.55, 0.85, 1.05, 0.20)

## 链扫：横向抽链。判定盒 = 预警矩形，贴膝盖高度。
const CHAIN_WINDUP := 0.55
const CHAIN_ACTIVE := 0.20
const CHAIN_RECOVERY := 0.45
const CHAIN_OFFSET := Vector2(64.0, -10.0)
const CHAIN_SIZE := Vector2(120.0, 20.0)
const CHAIN_LANE_LENGTH := 140.0
const CHAIN_COLOR := Color(1.0, 0.62, 0.30, 0.95)
## 蒸汽柱：骑士脚下（clamp 在场地内）喷一根蒸汽柱。
const STEAM_WINDUP := 0.60
const STEAM_ACTIVE := 0.35
const STEAM_RECOVERY := 0.40
const STEAM_SIZE := Vector2(30.0, 84.0)
const STEAM_COLOR := Color(0.62, 0.90, 1.0, 0.95)
## 开闸放水：场地一侧整片水位上升（推力，不直接伤害）。
const FLOOD_WINDUP := 0.70
const FLOOD_ACTIVE := 2.0
const FLOOD_RECOVERY := 0.50
const FLOOD_FLOW := 150.0
const FLOOD_COLOR := Color(0.55, 1.0, 0.78, 0.95)
## 召唤碎铁犬：ScrapperEnemy 复用，同屏上限 2。
const SUMMON_WINDUP := 0.55
const SUMMON_ACTIVE := 0.10
const SUMMON_RECOVERY := 0.50
const SUMMON_CAP := 2
const SUMMON_SCENE := "res://scenes/enemies/ScrapperEnemy.tscn"
## 泄压阀（破防窗口）：每次收招后开 1.3s，砸中 = 1.6s 硬直 + 破绽翻倍。
const VENT_TIME := 1.30
const BREAK_TIME := 1.60
const VALVE_RADIUS := 15.0
const VALVE_OFFSET := Vector2(-30.0, -22.0)
## 阶段转换：1.2s 无敌演出（契约 §4.1），期间导演层冻结、不开新招。
const TRANSITION_TIME := 1.2
const IDLE_SPEED := 28.0
const MIN_INTERVAL := 0.7
## 关卡里没有独立闸门触发器：骑士走进竞技场（接近 Boss）就开战，逻辑和梦魇一致。
const WAKE_RANGE := 320.0

## 竞技场边界（ChapterLayout.boss 通过 overrides 写入；未接线时用 ±300 兜底）。
@export var arena_left: float = -INF
@export var arena_right: float = INF

@onready var visual: Node2D = $Visual

enum Drive { NONE, WINDUP, ACTIVE, RECOVERY }

var _phase := 1
var _drive: Drive = Drive.NONE
var _drive_timer := 0.0
var _drive_id: StringName = &""
var _drive_entry: Dictionary = {}
var _warning: CombatMarker
var _active_box: Hitbox
var _vent_left := 0.0
var _break_left := 0.0
var _transition_left := 0.0
var _valve: Node2D
var _summoned: Array = []
var _facing := -1.0
var _announced := false
var _floor_y := 320.0
var _kit: BossKit
var _director: BossDirector
var _arena: BossArena
var _yoke: Node2D
var _steam_tint := COLD_TINT
var _glow: Sprite2D
var _lamp: Sprite2D
var _pulse_t := 0.0


func _enemy_ready() -> void:
	hit_material = &"boss"
	_mobile = true
	health.max_hp = MAX_HP
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	_floor_y = global_position.y
	_fit_silhouette()
	_build_visual()
	_build_presence()
	# The original frame carries its own horizontal winch; no legacy round yoke.
	_build_boss_framework()
	call_deferred("_bind_arena")


func _fit_silhouette() -> void:
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null:
		var rect := RectangleShape2D.new()
		rect.size = BODY_SIZE
		body.shape = rect
		body.position = Vector2(0.0, -BODY_SIZE.y * 0.5)
	var hurt := get_node_or_null("Hurtbox") as Hurtbox
	if hurt == null:
		return
	var hurt_shape := hurt.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if hurt_shape == null:
		return
	var hurt_rect := RectangleShape2D.new()
	hurt_rect.size = HURT_SIZE
	hurt_shape.shape = hurt_rect
	hurt.position = Vector2(0.0, -HURT_SIZE.y * 0.5)


func body_clearance() -> Vector2:
	return Vector2(BODY_SIZE.x * 0.5 + 7.0, BODY_SIZE.y)


func _build_visual() -> void:
	_anim = _build_frame_anim(EXEC_CHAR, [
		["idle", "", 8.0, true, EXEC_POS],
		["guard", "guard", 8.0, true, EXEC_POS],
		["charge", "charge", 7.0, false, EXEC_POS],
		["release", "release", 8.0, false, EXEC_POS],
		["broken", "broken", 7.0, true, EXEC_POS],
		["hurt", "hurt", 8.0, false, EXEC_POS],
	])
	if _anim == null:
		return
	var attack_frames := CharFrames.anim(EXEC_CHAR, "sweep")
	if not attack_frames.is_empty():
		_anim.register("sweep", attack_frames,
				float(attack_frames.size()) / (CHAIN_WINDUP + CHAIN_ACTIVE), false, EXEC_POS)
	_anim.flip_h = false
	_anim.play("idle")
	visual.add_child(_anim)
	visual.move_child(_anim, 0)
	_hide_placeholder_rects(visual)
	visual.modulate = COLD_TINT
	_flash_target = visual


## 受击白闪收尾回冷青剪影色，而不是纯白；二阶段更亮一档。
func _flash_restore_color() -> Color:
	return COLD_TINT_P2 if _phase >= 2 else COLD_TINT


## 背光 + 接地影：1× 剪影在地窖暗部里也要能读出「人形 + 绞盘轭」两层。
func _build_presence() -> void:
	var glow := Sprite2D.new()
	glow.name = "ColdBacklight"
	if ResourceLoader.exists("res://assets/env/glow_soft.png"):
		glow.texture = DensityTextures.load_texture("res://assets/env/glow_soft.png")
	glow.centered = true
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.position = Vector2(0.0, -32.0)
	glow.scale = Vector2(2.9, 3.0)
	glow.z_index = -1
	glow.material = Fx.additive_mat()
	glow.modulate = GLOW_TINT
	add_child(glow)
	_glow = glow
	var shadow := Sprite2D.new()
	shadow.name = "GroundShadow"
	if ResourceLoader.exists("res://assets/env/glow_soft.png"):
		shadow.texture = DensityTextures.load_texture("res://assets/env/glow_soft.png")
	shadow.centered = true
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow.position = Vector2(0.0, -2.0)
	shadow.scale = Vector2(1.5, 0.45)
	shadow.z_index = -1
	shadow.modulate = Color(0.02, 0.03, 0.04, 0.38)
	add_child(shadow)
	# 冷补光：盖在暗剪影上的一层加法冷光，别让 1× 身体在暗砖墙上糊成一团黑。
	var fill := Sprite2D.new()
	fill.name = "ColdFill"
	if ResourceLoader.exists("res://assets/env/glow_soft.png"):
		fill.texture = DensityTextures.load_texture("res://assets/env/glow_soft.png")
	fill.centered = true
	fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fill.position = Vector2(0.0, -30.0)
	fill.scale = Vector2(1.05, 1.75)
	fill.z_index = 2
	fill.material = Fx.additive_mat()
	fill.modulate = Color(0.30, 0.62, 0.78, 0.34)
	add_child(fill)
	# 胸口压阀的冷光（焦点）：暗剪影身上留一盏可读的灯。
	var lamp := Sprite2D.new()
	lamp.name = "ValveLamp"
	if ResourceLoader.exists("res://assets/env/glow_soft.png"):
		lamp.texture = DensityTextures.load_texture("res://assets/env/glow_soft.png")
	lamp.centered = true
	lamp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	lamp.position = Vector2(2.0, -34.0)
	lamp.scale = Vector2(0.62, 0.62)
	lamp.z_index = 2
	lamp.material = Fx.additive_mat()
	lamp.modulate = Color(0.55, 1.0, 1.05, 0.62)
	add_child(lamp)
	_lamp = lamp
	# 肩上的冷蒸汽：第二层剪影（人形 + 蒸汽须），远处也能认出是「守渠人」。
	for side: float in [-1.0, 1.0]:
		var wisp := CapstanSteamWisp.new()
		wisp.name = "ShoulderSteam"
		wisp.position = Vector2(side * 13.0, -52.0)
		wisp.z_index = 1
		add_child(wisp)


## 身后的绞盘轭：一段锈铁大轮 + 两条垂到肩上的链子。纯表现，z=-1（玩法层之下）。
func _build_yoke() -> void:
	_yoke = CapstanYoke.new()
	_yoke.name = "CapstanYoke"
	_yoke.position = Vector2(0.0, -34.0)
	_yoke.set("cold", _phase < 2)
	add_child(_yoke)


# ---------------------------------------------------------------------------
# Boss 框架接线
# ---------------------------------------------------------------------------
func boss_kit() -> BossKit:
	return _kit


func boss_director() -> BossDirector:
	return _director


## 夹具 / 竞技场读取的边界；没有 layout 覆盖时给 ±300 的兜底。
func boss_arena_bounds() -> Vector2:
	var left := arena_left
	var right := arena_right
	if not is_finite(left) or not is_finite(right) or right <= left:
		left = global_position.x - 300.0
		right = global_position.x + 300.0
	return Vector2(left, right)


func announce() -> void:
	if _announced or _dead:
		return
	_announced = true
	GameEvents.boss_intro_started.emit(BOSS_TITLE)
	GameEvents.boss_appeared.emit(BOSS_TITLE, health.current, health.max_hp)
	if _director != null:
		_director.notify_intro()
		_director.start()


func is_announced() -> bool:
	return _announced


func phase() -> int:
	return _phase


func is_broken() -> bool:
	return _break_left > 0.0


func drive_phase() -> int:
	return int(_drive)


func current_attack_id() -> StringName:
	return _drive_id


func _build_boss_framework() -> void:
	_kit = CapstanKit.new()
	_director = BossDirector.attach(self, _kit, true)
	_director.rng_seed = 7
	_director.attack_requested.connect(_on_attack_requested)
	_director.phase_entered.connect(_on_phase_entered)


func _bind_arena() -> void:
	var world := GameContext.world_root(self)
	if world == null:
		return
	var arena_name := String(get_meta("boss_arena_name", ""))
	if arena_name == "":
		return
	_arena = world.get_node_or_null("Arenas/" + arena_name) as BossArena
	if _arena == null:
		return
	# 场地机关：进场蒸汽 / 二阶段泄压 / 死亡泄压（纯表现 + 可见预警，无伤）。
	_arena.register_hazard(&"steam_burst", Callable(self, "_hazard_steam_burst"))
	_arena.register_hazard(&"pressure_vent", Callable(self, "_hazard_pressure_vent"))
	_arena.register_hazard(&"vent_finale", Callable(self, "_hazard_vent_finale"))


# ---------------------------------------------------------------------------
# 生命 / 阶段 / 死亡
# ---------------------------------------------------------------------------
func _on_hp_changed(current: int, maximum: int) -> void:
	announce()
	if _director != null:
		_director.set_hp(current, maximum)
	GameEvents.boss_hp_changed.emit(current, maximum)


func _on_phase_entered(next_phase: int) -> void:
	_phase = next_phase
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, next_phase)
	Juice.boss_phase_beat(global_position + Vector2(0.0, -30.0), Color(0.62, 0.92, 1.0))
	Sfx.play_at(&"boss_roar", global_position, 0.05, -3.0)
	if next_phase >= 2:
		_steam_tint = COLD_TINT_P2
		visual.modulate = COLD_TINT_P2
		if _glow != null:
			_glow.modulate = Color(0.80, 0.95, 1.15, 0.26)
		if _yoke != null and _yoke.has_method("set_cold"):
			_yoke.call("set_cold", false)
		GameEvents.announcement.emit("水位漫过闸板 —— 守渠人开始泄压")
	else:
		GameEvents.announcement.emit("绞盘锁死。他不让你碰闸。")
	# 契约 §4.1：相变有 1.2s 无敌演出，期间不开新招。
	_transition_left = TRANSITION_TIME
	health.invincible = true
	_cancel_drive()
	if _director != null:
		_director.freeze()
	_spawn_steam_burst(global_position + Vector2(0.0, -8.0), 0, false)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	_cancel_drive()
	_close_valve()
	_clear_summons()
	if _director != null:
		_director.notify_death()
	slain.emit()
	Juice.boss_death_beat(global_position + Vector2(0.0, -28.0))
	GameEvents.boss_defeated.emit()
	SaveData.mark_flag(DEATH_FLAG)
	SaveData.persist_story()
	_death_burst(CharFrames.anim(EXEC_CHAR, "death"), 14.0,
			_facing >= 0.0, EXEC_DEATH_BASELINE, "守渠人跪进渣水，闸还锁着")


# ---------------------------------------------------------------------------
# 驾驶：导演层请求 -> 前摇 / 判定 / 后摇
# ---------------------------------------------------------------------------
func _on_attack_requested(id: StringName) -> void:
	# 冻结（夹具取景 / 过场）、破防硬直、相变无敌、死亡时都不开招，立刻把占用还回去。
	if _dead or not is_physics_processing() or _transition_left > 0.0 or _break_left > 0.0 \
			or _drive != Drive.NONE:
		if _director != null:
			_director.notify_attack_finished()
		return
	var entry := _entry(id)
	if entry.is_empty():
		if _director != null:
			_director.notify_attack_finished()
		return
	_drive_id = id
	_drive_entry = entry
	_drive = Drive.WINDUP
	_drive_timer = _kit.windup_for(entry, _phase)
	_begin_windup_pose(id)
	begin_telegraph(StringName(entry.get("telegraph", id)), _drive_timer)
	_spawn_warning(id, _drive_timer)


func _entry(id: StringName) -> Dictionary:
	if _kit == null:
		return {}
	for entry in _kit.attack_pool():
		if StringName(entry.id) == id:
			return entry
	return {}


## 相变 / 死亡时打断当前招式：预警、判定、导演层占用一起收干净。
func _cancel_drive() -> void:
	if _drive != Drive.NONE and _director != null:
		_director.notify_attack_finished()
	_drive = Drive.NONE
	_drive_id = &""
	_drive_entry = {}
	_drive_timer = 0.0
	_hide_warning()
	_clear_active_box()


func _interrupt_for_poise() -> void:
	_cancel_drive()
	_vent_left = 0.0
	_close_valve()


func _begin_windup_pose(id: StringName) -> void:
	if _anim == null:
		return
	match String(id):
		"chain_sweep":
			_anim.play("charge", true)
			Sfx.play_at(&"boss_axe_swing", global_position, 0.05, -2.0)
		"steam_column":
			_anim.play("guard", true)
			Sfx.play_at(&"spit_charge", global_position, 0.05, -3.0)
		"sluice_flood":
			_anim.play("charge", true)
			Sfx.play_at(&"gate", global_position, 0.05, -5.0)
		"summon_hounds":
			_anim.play("charge", true)
			Sfx.play_at(&"ghost_wail", global_position, 0.05, -6.0)


## 一条预警：导演层串行出招 + 这里每个招式只生成一个 CombatMarker。
func _spawn_warning(id: StringName, windup: float) -> void:
	var facing := _facing
	match String(id):
		"chain_sweep":
			_warning = CombatMarker.spawn(self, CombatMarker.Kind.LANE, Vector2(0.0, -8.0),
					windup, CHAIN_COLOR,
					{"length": CHAIN_LANE_LENGTH, "facing": facing})
		"steam_column":
			var target := _aim_point()
			_warning = CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
					Vector2(target.x - global_position.x, -STEAM_SIZE.y * 0.5),
					windup, STEAM_COLOR,
					{"rect": Rect2(-STEAM_SIZE * 0.5, STEAM_SIZE)})
		"sluice_flood":
			var side := _flood_span()
			_warning = CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
					Vector2(side.x - global_position.x, -6.0), windup, FLOOD_COLOR,
					{"rect": Rect2(-side.y * 0.5, -12.0, side.y, 24.0)})
		"summon_hounds":
			_warning = CombatMarker.spawn(self, CombatMarker.Kind.RING, Vector2(0.0, -26.0),
					windup, Color(0.92, 0.78, 0.52, 0.95), {"radius_from": 30.0, "radius_to": 8.0})


func _hide_warning() -> void:
	if _warning != null and is_instance_valid(_warning):
		_warning.dismiss()
	_warning = null


func _tick_drive(delta: float) -> void:
	_drive_timer -= delta
	var active := float(_drive_entry.get("active", 0.0))
	var recovery := float(_drive_entry.get("recovery", 0.4))
	if _drive == Drive.WINDUP and _drive_timer <= 0.0:
		_drive = Drive.ACTIVE
		_drive_timer = maxf(active, 0.05)
		_hide_warning()
		_execute_move(_drive_id)
	elif _drive == Drive.ACTIVE and _drive_timer <= 0.0:
		_clear_active_box()
		_drive = Drive.RECOVERY
		_drive_timer = maxf(recovery, 0.05)
	elif _drive == Drive.RECOVERY and _drive_timer <= 0.0:
		_drive = Drive.NONE
		_drive_id = &""
		_drive_entry = {}
		if _director != null:
			_director.notify_attack_finished()
		_open_valve()


func _execute_move(id: StringName) -> void:
	match String(id):
		"chain_sweep":
			_execute_chain()
		"steam_column":
			_execute_steam()
		"sluice_flood":
			_execute_flood()
		"summon_hounds":
			_execute_summon()


func _execute_chain() -> void:
	var facing := _facing
	var box := Hitbox.new()
	box.damage = 2
	box.team = &"enemy"
	box.blow = &"heavy"
	box.collision_layer = 8
	box.collision_mask = 32
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = CHAIN_SIZE
	shape.shape = rect
	box.add_child(shape)
	_effects().add_child(box)
	box.global_position = global_position + Vector2(facing * CHAIN_OFFSET.x, CHAIN_OFFSET.y)
	box.arm(Vector2(facing * 120.0, -30.0))
	_active_box = box
	if _anim != null and _anim.has_anim("sweep"):
		_anim.play("sweep", true)
	_spawn_chain_fx(facing)
	Sfx.play_at(&"boss_axe_slam", global_position, 0.04, -4.0)


func _execute_steam() -> void:
	var target := _aim_point()
	# 预警已在起手时画好（一条）；柱体本身只出判定与视觉，不再画第二条预警。
	_spawn_steam_burst(target, 1, false)
	Sfx.play_at(&"spit", target, 0.05, -3.0)


func _execute_flood() -> void:
	var side := _flood_span()
	var node := SluiceFlood.new()
	node.window = Rect2(side.x - side.y * 0.5, _floor_y - 80.0, side.y, 80.0)
	node.flow = FLOOD_FLOW
	node.lifetime = FLOOD_ACTIVE
	_effects().add_child(node)
	Sfx.play_at(&"splash", Vector2(side.x, _floor_y - 8.0), 0.04, -2.0)
	Juice.shake(2.0, 160)


func _execute_summon() -> void:
	_clear_summons()
	if not ResourceLoader.exists(SUMMON_SCENE):
		return
	var scene := load(SUMMON_SCENE) as PackedScene
	var left := boss_arena_bounds().x + 40.0
	var right := boss_arena_bounds().y - 40.0
	var spawn_xs := [clampf(global_position.x - 170.0, left, right),
			clampf(global_position.x + 170.0, left, right)]
	for x in spawn_xs:
		if _summoned.size() >= SUMMON_CAP:
			break
		var hound := scene.instantiate() as Node2D
		hound.set("patrol_range", 14.0)
		_effects().add_child(hound)
		hound.global_position = Vector2(x, _floor_y)
		_summoned.append(hound)
	GameEvents.announcement.emit("碎铁犬从渣里爬起来")
	Sfx.play_at(&"ghost_wail", global_position, 0.06, -6.0)


# ---------------------------------------------------------------------------
# 位置 / 每帧
# ---------------------------------------------------------------------------
func _tick_state(delta: float) -> void:
	if _dead:
		return
	if not _announced:
		# 走进竞技场就开战（没有独立闸门触发器；和梦魇同一条靠近唤醒逻辑）。
		var near := knight()
		var bounds := boss_arena_bounds()
		if near != null and near.global_position.x >= bounds.x and near.global_position.x <= bounds.y \
				and global_position.distance_to(near.global_position) <= WAKE_RANGE:
			announce()
		else:
			# Do not creep towards the approach/checkpoint before the fight.
			# Announcing from there activates BossArena's player clamp remotely.
			velocity.x = 0.0
	if _break_left > 0.0:
		_break_left = maxf(0.0, _break_left - delta)
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		if _break_left <= 0.0:
			hide_opening()
			if _director != null:
				_director.resume()
		return
	if _transition_left > 0.0:
		_transition_left = maxf(0.0, _transition_left - delta)
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		if _transition_left <= 0.0:
			health.invincible = false
			if _director != null:
				_director.resume()
		return
	if _drive != Drive.NONE:
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		_tick_drive(delta)
		return
	if not _announced:
		velocity.x = 0.0
		return
	# 两招之间缓慢靠近骑士（竞技场 clamp 由 BossArena 负责）。
	var player := knight()
	if player != null:
		var dx := player.global_position.x - global_position.x
		if absf(dx) > 46.0:
			velocity.x = move_toward(velocity.x, signf(dx) * IDLE_SPEED, 220.0 * delta)
			_facing = signf(dx)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 260.0 * delta)
			if absf(dx) > 2.0:
				_facing = signf(dx)
	_self_clamp()


func _after_move() -> void:
	if _anim != null:
		if _break_left > 0.0:
			_anim.play("broken")
		elif _drive == Drive.WINDUP:
			var duration := maxf(_kit.windup_for(_drive_entry, _phase), 0.01)
			_anim.pin_frame("charge", clampi(int((1.0 - _drive_timer / duration) * 6.0), 0, 5))
		elif _drive == Drive.ACTIVE:
			_anim.pin_frame("sweep" if _drive_id == &"chain_sweep" else "release", 2)
		elif _drive == Drive.RECOVERY or _vent_left > 0.0:
			_anim.play("release")
		else:
			_anim.play("idle")
	if visual != null:
		visual.scale.x = -1.0 if _facing < 0.0 else 1.0


func _self_clamp() -> void:
	var bounds := boss_arena_bounds()
	global_position.x = clampf(global_position.x, bounds.x + BODY_SIZE.x * 0.5,
			bounds.y - BODY_SIZE.x * 0.5)


# ---------------------------------------------------------------------------
# 破防窗口：泄压阀
# ---------------------------------------------------------------------------
func _open_valve() -> void:
	if _dead or _break_left > 0.0 or _vent_left > 0.0:
		return
	_vent_left = VENT_TIME
	_close_valve()
	var valve := ReliefValve.new()
	valve.name = "ReliefValve"
	valve.position = Vector2(_facing * VALVE_OFFSET.x, VALVE_OFFSET.y)
	valve.radius = VALVE_RADIUS
	valve.on_struck = Callable(self, "_on_valve_struck")
	add_child(valve)
	_valve = valve
	Sfx.play_at(&"spit_charge", global_position + Vector2(0.0, -18.0), 0.06, -8.0)


func _close_valve() -> void:
	if _valve != null and is_instance_valid(_valve):
		_valve.queue_free()
	_valve = null


func _on_valve_struck() -> void:
	if _dead or _vent_left <= 0.0:
		return
	_vent_left = 0.0
	_close_valve()
	_break_left = BREAK_TIME
	open_riposte(BREAK_TIME)
	show_opening(BREAK_TIME)
	Juice.shake(3.0, 180)
	Sfx.play_at(&"shield_break", global_position, 0.04, -1.0)
	GameEvents.announcement.emit("泄压阀被砸开 —— 守渠人僵在绞盘上")
	_spawn_steam_burst(global_position + Vector2(0.0, -20.0), 0, false)
	if _director != null:
		_director.freeze()


func _process(delta: float) -> void:
	super._process(delta)
	_pulse_t += delta
	if _lamp != null:
		var pulse := 0.52 + 0.18 * sin(_pulse_t * 2.6)
		_lamp.modulate = Color(0.55, 1.0, 1.05, pulse)
	if _vent_left > 0.0:
		_vent_left = maxf(0.0, _vent_left - delta)
		if _vent_left <= 0.0:
			_close_valve()


# ---------------------------------------------------------------------------
# 表现工具
# ---------------------------------------------------------------------------
func _effects() -> Node:
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	return host


func _aim_point() -> Vector2:
	var player := knight()
	var bounds := boss_arena_bounds()
	var x := global_position.x + _facing * 90.0
	if player != null:
		x = player.global_position.x
	x = clampf(x, bounds.x + 24.0, bounds.y - 24.0)
	return Vector2(x, _floor_y)


## 水淹没哪一半：返回 {x=中心, y=宽度}（Boss 另一侧的半场，逼走位）。
func _flood_span() -> Vector2:
	var bounds := boss_arena_bounds()
	var player := knight()
	var left_side := player == null or player.global_position.x < global_position.x
	if left_side:
		var width := maxf(64.0, global_position.x - bounds.x)
		return Vector2((bounds.x + global_position.x) * 0.5, width)
	var width := maxf(64.0, bounds.y - global_position.x)
	return Vector2((global_position.x + bounds.y) * 0.5, width)


func _spawn_chain_fx(facing: float) -> void:
	var fx := ChainSweepFx.new()
	fx.position = global_position + Vector2(0.0, CHAIN_OFFSET.y)
	fx.facing = facing
	fx.reach = CHAIN_OFFSET.x + CHAIN_SIZE.x * 0.5
	fx.lifetime = CHAIN_ACTIVE + CHAIN_RECOVERY
	_effects().add_child(fx)


func _spawn_steam_burst(at: Vector2, damage: int, warn: bool) -> void:
	var burst := SteamBurst.new()
	burst.warning = warn
	burst.telegraph = STEAM_WINDUP if warn else 0.35
	burst.damage = damage
	burst.size = STEAM_SIZE
	burst.color = STEAM_COLOR
	burst.position = Vector2(at.x, _floor_y)
	_effects().add_child(burst)


func _clear_active_box() -> void:
	if _active_box != null and is_instance_valid(_active_box):
		_active_box.disarm()
		_active_box.queue_free()
	_active_box = null


func _close_valve_all() -> void:
	_close_valve()


func _clear_summons() -> void:
	for hound in _summoned:
		if is_instance_valid(hound):
			hound.queue_free()
	_summoned.clear()


# --- 场地机关（BossArena 注册；纯表现 + 预警，无伤） ------------------------
func _hazard_steam_burst(_data: Dictionary = {}) -> void:
	var bounds := boss_arena_bounds()
	_spawn_steam_burst(Vector2(bounds.x + 120.0, _floor_y), 0, true)
	_spawn_steam_burst(Vector2(bounds.y - 120.0, _floor_y), 0, true)


func _hazard_pressure_vent(_data: Dictionary = {}) -> void:
	_spawn_steam_burst(global_position + Vector2(-50.0, -10.0), 0, false)
	_spawn_steam_burst(global_position + Vector2(50.0, -10.0), 0, false)


func _hazard_vent_finale(_data: Dictionary = {}) -> void:
	_spawn_steam_burst(global_position + Vector2(0.0, -20.0), 0, false)


# ---------------------------------------------------------------------------
# 程序化表现（像素层，1x 整数坐标）
# ---------------------------------------------------------------------------
## 身后的锈铁绞盘轭：一圈 8 段轮缘 + 4 根辐条 + 两条垂链。画在玩法层之下。
class CapstanYoke extends Node2D:
	var cold := true
	var _t := 0.0

	func _ready() -> void:
		z_index = -1
		set_process(true)

	func set_cold(value: bool) -> void:
		cold = value
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var rim := Color(0.58, 0.80, 0.88) if cold else Color(1.00, 0.68, 0.40)
		var iron := Color(0.38, 0.50, 0.56) if cold else Color(0.66, 0.44, 0.28)
		var chain := Color(0.72, 0.82, 0.88) if cold else Color(1.00, 0.78, 0.48)
		var r := 46.0
		var seg := 16
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			draw_line(Vector2(roundf(cos(a0) * r), roundf(sin(a0) * r)),
					Vector2(roundf(cos(a1) * r), roundf(sin(a1) * r)), rim, 2.0)
		for i in 4:
			var a := TAU * float(i) / 4.0 + 0.4
			var p := Vector2(roundf(cos(a) * (r - 4.0)), roundf(sin(a) * (r - 4.0)))
			draw_line(Vector2.ZERO, p, iron, 2.0)
		# 两条垂到肩上的链：每节 3px，轻微摆动。
		var sway := roundf(sin(_t * 1.6) * 2.0)
		for side: float in [-1.0, 1.0]:
			for link in 6:
				var y := -6.0 - float(link) * 7.0
				var x: float = side * (22.0 + float(link) * 0.8) + sway * (0.4 + 0.1 * float(link))
				draw_rect(Rect2(Vector2(roundf(x) - 2.0, roundf(y) - 3.0), Vector2(4, 6)),
						chain if link % 2 == 0 else iron)


## 肩上的冷蒸汽：三团循环上升的加法雾，给暗剪影补一条「蒸汽须」轮廓。
class CapstanSteamWisp extends Node2D:
	var _t := 0.0
	var _phase := 0.0

	func _ready() -> void:
		material = Fx.additive_mat()
		_phase = randf() * TAU
		z_index = 1

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for i in 3:
			var k := fmod(_t * 0.55 + float(i) / 3.0 + _phase * 0.16, 1.0)
			var y := -4.0 - k * 24.0
			var x := sin(_t * 1.7 + float(i) * 2.1) * (2.0 + k * 3.5)
			var alpha := (1.0 - k) * 0.22
			draw_circle(Vector2(roundf(x), roundf(y)), 2.5 + k * 3.0,
					Color(0.70, 0.92, 1.0, alpha))


## 链扫：一条 2px 铁链从 Boss 手边甩到最远处，末端带链锤。
class ChainSweepFx extends Node2D:
	var facing := 1.0
	var reach := 124.0
	var lifetime := 0.65
	var _age := 0.0
	var _arm := 2.0
	var _t := 0.0

	func _ready() -> void:
		z_index = 5
		material = Fx.additive_mat()
		_t = 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / maxf(lifetime * 0.35, 0.01), 0.0, 1.0)
		var sweep := lerpf(0.0, 1.0, k)
		var hand := Vector2(facing * 14.0, -30.0)
		var tip := Vector2(facing * reach * sweep, -16.0 + sin(sweep * PI) * 10.0)
		var links := int(hand.distance_to(tip) / 6.0)
		for i in links + 1:
			var p := hand.lerp(tip, float(i) / float(maxi(links, 1)))
			var wobble := 3.0 * sin(float(i) * 1.1 + _age * 30.0)
			draw_rect(Rect2(Vector2(roundf(p.x) - 2.0, roundf(p.y + wobble) - 1.0),
					Vector2(4, 2)), Color(0.95, 0.62, 0.30, 0.95))
		draw_rect(Rect2(Vector2(roundf(tip.x) - 4.0, roundf(tip.y) - 4.0), Vector2(8, 8)),
				Color(1.0, 0.82, 0.45, 0.95))


## 蒸汽柱：预警圈 -> 柱体（判定 + 加法白蓝视觉）。自管理生命周期。
class SteamBurst extends Node2D:
	var warning := true
	var telegraph := 0.45
	var active_time := 0.35
	var damage := 1
	var size := Vector2(30.0, 84.0)
	var color := Color(0.62, 0.90, 1.0)
	var _age := 0.0
	var _box: Hitbox

	func _ready() -> void:
		z_index = 4
		material = Fx.additive_mat()
		if warning:
			CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
					Vector2(0.0, -size.y * 0.5), telegraph, color,
					{"rect": Rect2(-size * 0.5, size)})
		set_process(true)

	func _process(delta: float) -> void:
		_age += delta
		if warning and _age >= telegraph and _box == null:
			if damage > 0:
				_box = Hitbox.new()
				_box.damage = damage
				_box.team = &"enemy"
				_box.blow = &"light"
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = size
				shape.shape = rect
				_box.add_child(shape)
				add_child(_box)
				_box.position = Vector2(0.0, -size.y * 0.5)
				_box.arm(Vector2(0.0, -80.0))
			Fx.dust_puff(global_position + Vector2(0.0, -6.0), -PI * 0.5)
		if _age >= telegraph + active_time + 0.2:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _age / maxf(telegraph + active_time, 0.01)
		var height := size.y * clampf((_age - telegraph * 0.5) / maxf(telegraph, 0.01), 0.0, 1.0)
		if height <= 1.0:
			return
		var a := clampf(1.0 - k, 0.0, 1.0) * 0.55
		var w := size.x * (1.0 - 0.3 * k)
		for i in 6:
			var t := float(i) / 5.0
			var row_y := -height * t
			var row_w := w * (0.55 + 0.45 * t)
			draw_rect(Rect2(Vector2(roundf(-row_w * 0.5), roundf(row_y)), Vector2(roundf(row_w), 6)),
					Color(color.r, color.g, color.b, a * (1.0 - t * 0.6)))


## 开闸放水：半场水位上升 + 向场中推。判定用 Area2D 推玩家（和 BossArena.WaterZone 同口径）。
class SluiceFlood extends Node2D:
	var window := Rect2(0, 0, 300, 80)
	var flow := 150.0
	var lifetime := 2.0
	var _age := 0.0
	var _zone: Area2D
	var _bodies: Array[Node2D] = []

	func _ready() -> void:
		z_index = 1
		_zone = Area2D.new()
		_zone.collision_layer = 0
		_zone.collision_mask = 2
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(window.size.x, 28.0)
		shape.shape = rect
		_zone.add_child(shape)
		_zone.position = Vector2(0.0, -14.0)
		add_child(_zone)
		_zone.body_entered.connect(_on_body_entered)
		_zone.body_exited.connect(_on_body_exited)
		set_process(true)

	func _on_body_entered(body: Node2D) -> void:
		if not _bodies.has(body):
			_bodies.append(body)

	func _on_body_exited(body: Node2D) -> void:
		_bodies.erase(body)

	func _physics_process(delta: float) -> void:
		var dir := signf(flow)
		for body in _bodies:
			if is_instance_valid(body) and body is CharacterBody2D:
				(body as CharacterBody2D).velocity.x += dir * absf(flow) * delta

	func _process(delta: float) -> void:
		_age += delta
		if _age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var rise := clampf(_age / 0.45, 0.0, 1.0) * 46.0
		var fade := clampf((lifetime - _age) / 0.5, 0.0, 1.0)
		var w := window.size.x
		draw_rect(Rect2(Vector2(roundf(-w * 0.5), -rise), Vector2(roundf(w), roundf(rise))),
				Color(0.24, 0.52, 0.48, 0.42 * fade))
		draw_rect(Rect2(Vector2(roundf(-w * 0.5), roundf(-rise)), Vector2(roundf(w), 2)),
				Color(0.68, 1.0, 0.86, 0.75 * fade))


## 泄压阀：破防窗口。玩家剑的 Hitbox 扫到它 -> 回调 Boss。
class ReliefValve extends Area2D:
	var radius := 15.0
	var on_struck: Callable = Callable()
	var _struck := false
	var _t := 0.0

	func _ready() -> void:
		monitoring = true
		monitorable = true
		collision_layer = 32
		collision_mask = 8
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = radius
		shape.shape = circle
		add_child(shape)
		area_entered.connect(_on_area_entered)
		z_index = 3
		set_process(true)

	func _on_area_entered(area: Area2D) -> void:
		if _struck or not (area is Hitbox):
			return
		if (area as Hitbox).team != &"player" or not (area as Hitbox).monitoring:
			return
		_struck = true
		if on_struck.is_valid():
			on_struck.call()
		queue_free()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.65 + 0.35 * sin(_t * 9.0)
		var iron := Color(0.72, 0.82, 0.88, pulse)
		var r := radius - 2.0
		for i in 10:
			var a0 := TAU * float(i) / 10.0
			var a1 := TAU * float(i + 1) / 10.0
			draw_line(Vector2(roundf(cos(a0) * r), roundf(sin(a0) * r)),
					Vector2(roundf(cos(a1) * r), roundf(sin(a1) * r)), iron, 2.0)
		for i in 4:
			var a := TAU * float(i) / 4.0
			draw_line(Vector2.ZERO, Vector2(roundf(cos(a) * (r - 3.0)), roundf(sin(a) * (r - 3.0))),
					Color(0.92, 0.55, 0.30, pulse), 2.0)
		draw_rect(Rect2(Vector2(-2, -2), Vector2(4, 4)), Color(1.0, 0.86, 0.52, pulse))


# ---------------------------------------------------------------------------
# 数据：攻击表 / 场地事件
# ---------------------------------------------------------------------------
class CapstanKit extends BossKit:
	func boss_id() -> StringName:
		return &"capstan_warden"

	func boss_title() -> String:
		return "绞盘守渠人 · 八百下闸"

	func boss_subtitle() -> String:
		return "水渠的最后一班"

	func max_phases() -> int:
		return 2

	func phase_thresholds() -> Array[float]:
		return [1.0, 0.5]

	func min_interval() -> float:
		return 0.7

	func attack_table() -> Array[Dictionary]:
		return [
			{
				"id": &"chain_sweep", "phase": 1, "weight": 2.0,
				"cooldown": 2.4, "cooldown_by_phase": [2.4, 1.6],
				"min_range": 0.0, "max_range": 230.0,
				"windup": 0.55, "windup_by_phase": [0.55, 0.45],
				"active": 0.20, "recovery": 0.45,
				"telegraph": &"chain_sweep",
				"hitbox": {"offset": Vector2(64.0, -10.0), "size": Vector2(120.0, 20.0)},
			},
			{
				"id": &"steam_column", "phase": 1, "weight": 1.6,
				"cooldown": 3.0, "cooldown_by_phase": [3.0, 2.0],
				"min_range": 0.0, "max_range": 620.0,
				"windup": 0.60, "windup_by_phase": [0.60, 0.50],
				"active": 0.35, "recovery": 0.40,
				"telegraph": &"steam_column",
				"hitbox": {},
			},
			{
				"id": &"sluice_flood", "phase": 1, "weight": 1.0,
				"cooldown": 7.0, "cooldown_by_phase": [7.0, 5.0],
				"min_range": 0.0, "max_range": 0.0,
				"windup": 0.70, "windup_by_phase": [0.70, 0.60],
				"active": 2.0, "recovery": 0.50,
				"telegraph": &"sluice_flood", "damaging": false,
				"hitbox": {},
			},
			{
				"id": &"summon_hounds", "phase": 2, "weight": 1.2,
				"cooldown": 9.0,
				"min_range": 0.0, "max_range": 0.0,
				"windup": 0.55, "active": 0.10, "recovery": 0.50,
				"telegraph": &"summon_hounds", "damaging": false,
				"hitbox": {},
			},
		]

	func arena_events() -> Array[Dictionary]:
		return [
			{"id": &"steam_burst", "at_phase": 1, "once": true},
			{"id": &"pressure_vent", "at_phase": 2, "once": true},
			{"id": &"vent_finale", "at_phase": 0, "once": true},
		]
