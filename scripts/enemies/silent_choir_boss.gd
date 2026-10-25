class_name SilentChoirBoss
extends EnemyBase
## 无声唱诗班（level04b · 圣殿地窖的 Boss）。驾驶模式接入 BossKit/BossDirector/BossArena。
##
## 人物（docs/story.md §2/§5）：账本末页被他们守着 —— 没有声音的唱诗班，还在唱。
## 原创管风琴面具指挥与三种唱诗壳；均为独立1倍像素帧，不读取ghost素材。
## 可读性：声波锥（lane）/ 烛雨区（zone）/ 静默区（zone，里面歌声听不见你）/
## 二阶段合声光束（可弹反 -> 打回指挥身上破防）。指挥是唯一受击点；壳只是和声。
## 每招前摇 >= 0.35s，导演层串行出招 -> 同一时刻只有一条预警。

signal slain

const GHOST_CHAR := "original_silent_choir"
## ghost 帧 64×80，内容居中（bbox 20..44 × 19..61）：centered Sprite 原点即内容中心。
const CONDUCTOR_SCALE := 1
const CONDUCTOR_POS := Vector2(0.0, -46.0)
const BOSS_TITLE := "无声唱诗班 · 末页的守夜"
const BOSS_SUBTITLE := "把名字唱成账的人"
const BOSS_ID := &"silent_choir"
const MAX_HP := 15
const DEATH_FLAG := &"choir_dead"
## 冷白指挥 / 暖烛壳：两层色相 + 2x 对 1x 的两层剪影。
const CONDUCTOR_TINT := Color(1.0, 1.0, 1.08)
const CONDUCTOR_TINT_P2 := Color(1.12, 1.04, 1.10)
const SHELL_TINT := Color(1.0, 0.98, 0.92)
const SHELL_TINT_P2 := Color(1.12, 1.02, 0.92)
const BODY_SIZE := Vector2(30, 66)
const HURT_SIZE := Vector2(44, 88)

## 声波锥：从一个唱诗壳朝骑士方向放锥形声波（lane 预警 = 判定盒）。
const CONE_WINDUP := 0.60
const CONE_ACTIVE := 0.30
const CONE_RECOVERY := 0.40
const CONE_LENGTH := 140.0
const CONE_HEIGHT := 44.0
const CONE_COLOR := Color(0.95, 0.80, 0.45, 0.95)
## 烛雨区：一片落下的烛泪（zone 预警 = 整片雨区，一次预警）。
const RAIN_WINDUP := 0.65
const RAIN_ACTIVE := 0.60
const RAIN_RECOVERY := 0.50
const RAIN_WIDTH := 200.0
const RAIN_COLOR := Color(0.98, 0.72, 0.42, 0.95)
const RAIN_DROPS := 3
## 静默区：歌声听不见你（安全口袋），但烛雨照落。
const SILENCE_WINDUP := 0.70
const SILENCE_ACTIVE := 2.60
const SILENCE_RECOVERY := 0.50
const SILENCE_SIZE := Vector2(110.0, 90.0)
const SILENCE_COLOR := Color(0.58, 0.66, 0.95, 0.95)
## 合声光束（二阶段）：可被弹反，打回指挥身上会自动 open_riposte 破防。
const BEAM_WINDUP := 0.70
const BEAM_ACTIVE := 0.25
const BEAM_RECOVERY := 0.55
const BEAM_SPEED := 200.0
const BEAM_COLOR := Color(0.82, 0.92, 1.0, 0.95)
const TRANSITION_TIME := 1.2
const IDLE_SPEED := 30.0
const MIN_INTERVAL := 0.8
## 关卡里没有独立闸门触发器：骑士走进竞技场（接近唱诗班）就开战。
const WAKE_RANGE := 320.0
const FLOAT_HEIGHT := 0.0

## 唱诗壳相对指挥的站位（局部坐标，绕着指挥的半圆）。
const SHELL_OFFSETS: Array[Vector2] = [Vector2(-74.0, -118.0), Vector2(74.0, -118.0), Vector2(0.0, -170.0)]

@export var arena_left: float = -INF
@export var arena_right: float = INF

@onready var visual: Node2D = $Visual
@onready var hurtbox: Hurtbox = $Hurtbox

enum Drive { NONE, WINDUP, ACTIVE, RECOVERY }

var _phase := 1
var _drive: Drive = Drive.NONE
var _drive_timer := 0.0
var _drive_id: StringName = &""
var _drive_entry: Dictionary = {}
var _warning: CombatMarker
var _active_box: Hitbox
var _transition_left := 0.0
var _facing := -1.0
var _announced := false
var _floor_y := 320.0
var _kit: BossKit
var _director: BossDirector
var _arena: BossArena
var _shells: Array = []
var _shell_cursor := 0
var _silence_left := 0.0
var _silence_rect := Rect2()
var _last_heard := Vector2.ZERO
var _behind_beam := false
var _was_marked := false
var _marked_announced := false


func _enemy_ready() -> void:
	hit_material = &"boss"
	health.max_hp = MAX_HP
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	_floor_y = global_position.y
	_fit_silhouette()
	_build_visual()
	_build_shells()
	_build_presence()
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


## 唱诗班浮在空中：LevelSanity 不按「落地敌人」检查脚点。
func is_airborne() -> bool:
	return true


func _build_visual() -> void:
	_anim = _build_frame_anim(GHOST_CHAR, [
		["idle", "idle", 8.0, true, CONDUCTOR_POS],
		["sing", "windup", 7.0, true, CONDUCTOR_POS],
		["cast", "cast", 8.0, true, CONDUCTOR_POS],
		["recover", "recover", 7.0, false, CONDUCTOR_POS],
		["broken", "broken", 7.0, true, CONDUCTOR_POS],
	])
	if _anim == null:
		return
	_anim.scale = Vector2(CONDUCTOR_SCALE, CONDUCTOR_SCALE)
	_anim.play("idle")
	visual.add_child(_anim)
	visual.move_child(_anim, 0)
	_hide_placeholder_rects(visual)
	visual.modulate = CONDUCTOR_TINT
	_flash_target = visual


func _flash_restore_color() -> Color:
	return CONDUCTOR_TINT_P2 if _phase >= 2 else CONDUCTOR_TINT


## 指挥身后的冷光 + 脚下的暗影，把浮空主体从地窖暗部里剥出来。
func _build_presence() -> void:
	var glow := Sprite2D.new()
	glow.name = "ChoirGlow"
	if ResourceLoader.exists("res://assets/env/glow_soft.png"):
		glow.texture = DensityTextures.load_texture("res://assets/env/glow_soft.png")
	glow.centered = true
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.scale = Vector2(3.0, 3.4)
	glow.position = CONDUCTOR_POS + Vector2(0.0, -18.0)
	glow.z_index = -1
	glow.material = Fx.additive_mat()
	glow.modulate = Color(0.55, 0.72, 1.0, 0.22)
	add_child(glow)


func _build_shells() -> void:
	for i in SHELL_OFFSETS.size():
		var shell := ChoirShell.new()
		shell.name = "Shell%s" % String(char(65 + i))
		shell.position = SHELL_OFFSETS[i]
		shell.art_variant = i
		shell.tint = SHELL_TINT
		add_child(shell)
		_shells.append(shell)
	for i in 2:
		var wisp := ChoirWisp.new()
		wisp.position = Vector2(-40.0 + 40.0 * float(i), -60.0)
		wisp.z_index = -1
		add_child(wisp)


# ---------------------------------------------------------------------------
# Boss 框架
# ---------------------------------------------------------------------------
func boss_kit() -> BossKit:
	return _kit


func boss_director() -> BossDirector:
	return _director


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


func drive_phase() -> int:
	return int(_drive)


func current_attack_id() -> StringName:
	return _drive_id


func shells() -> Array:
	return _shells.duplicate()


## 静默区里骑士「听不见」：返回 true 时声波锥/光束瞄准的是记忆中的位置。
func is_player_silenced() -> bool:
	if _silence_left <= 0.0 or _silence_rect.size == Vector2.ZERO:
		return false
	var player := knight()
	if player == null:
		return false
	# 区域贴地：水平在区里、脚点不低于区底（Rect2.end 不含端点，脚下 y==floor 要算进去）。
	var center := _silence_rect.get_center()
	return absf(player.global_position.x - center.x) <= _silence_rect.size.x * 0.5 \
			and player.global_position.y >= _silence_rect.position.y - 8.0


func _build_boss_framework() -> void:
	_kit = ChoirKit.new()
	_director = BossDirector.attach(self, _kit, true)
	_director.rng_seed = 11
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
	_arena.register_hazard(&"choir_rise", Callable(self, "_hazard_choir_rise"))
	_arena.register_hazard(&"silence_veil", Callable(self, "_hazard_silence_veil"))
	_arena.register_hazard(&"choir_fade", Callable(self, "_hazard_choir_fade"))


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
	Juice.boss_phase_beat(global_position + Vector2(0.0, -50.0), Color(0.78, 0.88, 1.0))
	Sfx.play_at(&"boss_roar", global_position, 0.05, -5.0)
	if next_phase >= 2:
		visual.modulate = CONDUCTOR_TINT_P2
		for shell in _shells:
			if shell is Node:
				(shell as Node).call("set_tint", SHELL_TINT_P2)
		GameEvents.announcement.emit("三声合成一声 —— 合声光束可以打回去")
	else:
		GameEvents.announcement.emit("他们在唱，但没有声音")
	_transition_left = TRANSITION_TIME
	health.invincible = true
	_cancel_drive()
	if _director != null:
		_director.freeze()


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	_cancel_drive()
	if _director != null:
		_director.notify_death()
	slain.emit()
	Juice.boss_death_beat(global_position + Vector2(0.0, -50.0))
	GameEvents.boss_defeated.emit()
	SaveData.mark_flag(DEATH_FLAG)
	SaveData.persist_story()
	var vanish := CharFrames.anim(GHOST_CHAR, "death")
	_death_burst(vanish, 12.0, false, CONDUCTOR_POS.y, "唱诗班停了。没有声音")


# ---------------------------------------------------------------------------
# 驾驶：前摇 / 判定 / 后摇
# ---------------------------------------------------------------------------
func _on_attack_requested(id: StringName) -> void:
	if _dead or not is_physics_processing() or _transition_left > 0.0 or _drive != Drive.NONE:
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


## 相变 / 死亡时打断当前招式：预警、判定、导演层占用一起收干净，别把伤害带进过场。
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


func _begin_windup_pose(id: StringName) -> void:
	if _anim != null:
		_anim.play("sing", true)
	match String(id):
		"sound_cone":
			Sfx.play_at(&"ghost_wail", global_position, 0.05, -4.0)
		"candle_rain":
			Sfx.play_at(&"bell_toll", global_position, 0.05, -8.0)
		"silence_zone":
			Sfx.play_at(&"ghost_wail", global_position, 0.03, -8.0)
		"harmony_beam":
			Sfx.play_at(&"spit_charge", global_position, 0.04, -4.0)


func _spawn_warning(id: StringName, windup: float) -> void:
	match String(id):
		"sound_cone":
			# 声波从唱诗壳扫到骑士脚下：地面一条横带 = 判定带（同一条预警）。
			var shell_pos := _next_shell_local()
			var target := _aim_point()
			var span := absf(target.x - (global_position.x + shell_pos.x))
			var mid_x := (target.x + global_position.x + shell_pos.x) * 0.5 - global_position.x
			_warning = CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
					Vector2(mid_x, -14.0), windup, CONE_COLOR,
					{"rect": Rect2(-(span + 40.0) * 0.5, -17.0, span + 40.0, 34.0)})
		"candle_rain":
			var target := _aim_point()
			_warning = CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
					Vector2(target.x - global_position.x, -RAIN_ACTIVE * 10.0 - 6.0),
					windup, RAIN_COLOR,
					{"rect": Rect2(-RAIN_WIDTH * 0.5, -12.0, RAIN_WIDTH, 24.0)})
		"silence_zone":
			var zone_center := _silence_target()
			_warning = CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
					Vector2(zone_center.x - global_position.x, -SILENCE_SIZE.y * 0.5 + 8.0),
					windup, SILENCE_COLOR,
					{"rect": Rect2(-SILENCE_SIZE * 0.5, SILENCE_SIZE)})
		"harmony_beam":
			var origin := CONDUCTOR_POS + Vector2(0.0, -6.0)
			var dir := _aim_direction(origin)
			_warning = CombatMarker.spawn(self, CombatMarker.Kind.LANE, origin,
					windup, BEAM_COLOR,
					{"length": 420.0, "facing": signf(dir.x) if absf(dir.x) > 0.01 else _facing})


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


func _execute_move(id: StringName) -> void:
	match String(id):
		"sound_cone":
			_execute_cone()
		"candle_rain":
			_execute_rain()
		"silence_zone":
			_execute_silence()
		"harmony_beam":
			_execute_beam()


func _execute_cone() -> void:
	var shell_pos := _next_shell_local()
	var origin := global_position + shell_pos
	var target := _aim_point()
	var span := absf(target.x - origin.x) + 40.0
	var center := Vector2((origin.x + target.x) * 0.5, _floor_y - 14.0)
	var box := Hitbox.new()
	box.damage = 1
	box.team = &"enemy"
	box.blow = &"light"
	box.collision_layer = 8
	box.collision_mask = 32
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(span, 34.0)
	shape.shape = rect
	box.add_child(shape)
	_effects().add_child(box)
	box.global_position = center
	box.arm(Vector2(signf(target.x - origin.x) * 90.0, -20.0))
	_active_box = box
	var fx := SonicConeFx.new()
	fx.position = origin
	fx.direction = Vector2(signf(target.x - origin.x), 0.55).normalized()
	fx.length = maxf(span * 0.6, CONE_LENGTH * 0.5)
	fx.lifetime = CONE_ACTIVE + 0.35
	_effects().add_child(fx)
	Sfx.play_at(&"ghost_wail", origin, 0.04, -3.0)


func _execute_rain() -> void:
	var target := _aim_point()
	var rain := CandleRain.new()
	rain.position = Vector2(target.x, _floor_y)
	rain.width = RAIN_WIDTH
	rain.drops = RAIN_DROPS
	rain.fall_time = 0.45
	rain.damage = 1
	_effects().add_child(rain)
	Sfx.play_at(&"bell_toll", target, 0.04, -6.0)


func _execute_silence() -> void:
	var center := _silence_target()
	_silence_left = SILENCE_ACTIVE
	_silence_rect = Rect2(center - SILENCE_SIZE * 0.5, SILENCE_SIZE)
	var zone := SilenceZone.new()
	zone.position = center
	zone.size = SILENCE_SIZE
	zone.lifetime = SILENCE_ACTIVE
	_effects().add_child(zone)
	if not _marked_announced:
		_marked_announced = true
		GameEvents.announcement.emit("静默区：歌声听不见你，烛雨照落")
	Sfx.play_at(&"ghost_wail", center, 0.04, -9.0)


func _execute_beam() -> void:
	var origin := global_position + CONDUCTOR_POS + Vector2(0.0, -6.0)
	var dir := _aim_direction(CONDUCTOR_POS)
	var host := _effects()
	var bolt := preload("res://scenes/combat/Projectile.tscn").instantiate() as Projectile
	host.add_child(bolt)
	bolt.setup(origin, dir, BEAM_SPEED, &"enemy", self)
	bolt.damage = 1
	_behind_beam = true
	var fx := SonicConeFx.new()
	fx.position = origin
	fx.direction = dir
	fx.length = 90.0
	fx.lifetime = 0.25
	fx.tint = BEAM_COLOR
	host.add_child(fx)
	Sfx.play_at(&"spit", origin, 0.05, -4.0)


# ---------------------------------------------------------------------------
# 每帧
# ---------------------------------------------------------------------------
func _tick_state(delta: float) -> void:
	if _dead:
		return
	# 浮空：抵消重力，悬停在地面线以上。
	velocity.y = 0.0
	if not _announced:
		# 走进竞技场就开战（没有独立闸门触发器；和梦魇同一条靠近唤醒逻辑）。
		var near := knight()
		if near != null and global_position.distance_to(near.global_position) <= WAKE_RANGE:
			announce()
	if _transition_left > 0.0:
		_transition_left = maxf(0.0, _transition_left - delta)
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		if _transition_left <= 0.0:
			health.invincible = false
			if _director != null:
				_director.resume()
		return
	if _silence_left > 0.0:
		_silence_left = maxf(0.0, _silence_left - delta)
	if _drive != Drive.NONE:
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		_tick_drive(delta)
		return
	var player := knight()
	if player != null and not is_player_silenced():
		_last_heard = player.global_position
	if player != null:
		var dx := player.global_position.x - global_position.x
		if absf(dx) > 90.0:
			velocity.x = move_toward(velocity.x, signf(dx) * IDLE_SPEED, 200.0 * delta)
			_facing = signf(dx)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 240.0 * delta)
			if absf(dx) > 2.0:
				_facing = signf(dx)
	_self_clamp()


func _after_move() -> void:
	if _anim != null:
		if is_marked():
			_anim.play("broken")
		elif _drive == Drive.WINDUP:
			var duration := maxf(_kit.windup_for(_drive_entry, _phase), 0.01)
			_anim.pin_frame("sing", clampi(int((1.0 - _drive_timer / duration) * 6.0), 0, 5))
		elif _drive == Drive.ACTIVE:
			_anim.play("cast")
		elif _drive == Drive.RECOVERY:
			_anim.play("recover")
		else:
			_anim.play("idle")
	# 弹反打回来自动开的破绽：给一句提示（只提示一次）。
	if is_marked() and not _was_marked:
		GameEvents.announcement.emit("合声被打断 —— 指挥露出来了")
	_was_marked = is_marked()
	_behind_beam = false


func _self_clamp() -> void:
	var bounds := boss_arena_bounds()
	global_position.x = clampf(global_position.x, bounds.x + BODY_SIZE.x * 0.5,
			bounds.y - BODY_SIZE.x * 0.5)


# ---------------------------------------------------------------------------
# 瞄准工具（静默区里听不见 -> 用记忆位置）
# ---------------------------------------------------------------------------
func _aim_point() -> Vector2:
	var bounds := boss_arena_bounds()
	var player := knight()
	var point := Vector2(global_position.x + _facing * 90.0, _floor_y)
	if player != null:
		point = player.global_position if not is_player_silenced() else _last_heard
	point.x = clampf(point.x, bounds.x + 24.0, bounds.y - 24.0)
	return Vector2(point.x, _floor_y)


func _silence_target() -> Vector2:
	var player := knight()
	var center := Vector2(global_position.x, _floor_y - 4.0)
	if player != null:
		center = player.global_position + Vector2(0.0, -6.0)
	var bounds := boss_arena_bounds()
	center.x = clampf(center.x, bounds.x + SILENCE_SIZE.x * 0.5, bounds.y - SILENCE_SIZE.x * 0.5)
	return Vector2(center.x, _floor_y - SILENCE_SIZE.y * 0.5)


func _aim_direction(from_local: Vector2) -> Vector2:
	var origin := global_position + from_local
	var target := _aim_point()
	var dir := target - origin
	if dir.length() < 1.0:
		return Vector2(_facing, 0.0)
	return dir.normalized()


func _next_shell_local() -> Vector2:
	if _shells.is_empty():
		return CONDUCTOR_POS
	var shell: Node2D = _shells[_shell_cursor % _shells.size()]
	_shell_cursor += 1
	return shell.position


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------
func _effects() -> Node:
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	return host


func _clear_active_box() -> void:
	if _active_box != null and is_instance_valid(_active_box):
		_active_box.disarm()
		_active_box.queue_free()
	_active_box = null


# --- 场地机关（BossArena 注册；纯表现，不伤） --------------------------------
func _hazard_choir_rise(_data: Dictionary = {}) -> void:
	for shell in _shells:
		if shell is Node:
			(shell as Node).call("sing_pulse")
	Juice.shake(1.4, 200)


func _hazard_silence_veil(_data: Dictionary = {}) -> void:
	var player := knight()
	if player != null:
		var veil := SilenceZone.new()
		veil.position = Vector2(player.global_position.x, _floor_y - SILENCE_SIZE.y * 0.5)
		veil.size = SILENCE_SIZE
		veil.lifetime = 1.2
		_effects().add_child(veil)


func _hazard_choir_fade(_data: Dictionary = {}) -> void:
	for shell in _shells:
		if shell is Node and is_instance_valid(shell):
			(shell as Node).queue_free()
	_shells.clear()


# ---------------------------------------------------------------------------
# 程序化表现
# ---------------------------------------------------------------------------
## 一个唱诗壳：ghost 帧 1x，暖烛色，轻轻悬浮；被点名放声时亮一下。
class ChoirShell extends Node2D:
	var art_variant := 0
	var tint := Color(1.45, 1.12, 0.62)
	var _frames: Array[Texture2D] = []
	var _sing_frames: Array[Texture2D] = []
	var _sprite: Sprite2D
	var _t := 0.0
	var _sing := 0.0

	func _ready() -> void:
		var source := "original_silent_choir/cantor_%d" % clampi(art_variant,0,2)
		_frames = CharFrames.anim(source, "idle")
		_sing_frames = CharFrames.anim(source, "sing")
		_sprite = Sprite2D.new()
		if not _frames.is_empty():
			_sprite.texture = _frames[0]
		_sprite.centered = true
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.modulate = tint
		add_child(_sprite)
		_t = randf() * TAU

	func set_tint(value: Color) -> void:
		tint = value
		if _sprite != null:
			_sprite.modulate = tint

	func sing_pulse() -> void:
		_sing = 0.45

	func _process(delta: float) -> void:
		_t += delta
		_sing = maxf(0.0, _sing - delta)
		position.y += sin(_t * 1.8) * 3.2 * delta
		if _sprite != null and not _frames.is_empty():
			var active := _sing_frames if _sing > 0.0 and not _sing_frames.is_empty() else _frames
			var idx := int(_t * 7.0) % active.size()
			_sprite.texture = active[idx]
			var glow := 1.0 + 5.0 * _sing
			_sprite.modulate = Color(tint.r * glow, tint.g * glow, tint.b * glow, 1.0)


## 唱诗堂的残烛雾：两团极淡的加法光，只是氛围。
class ChoirWisp extends Node2D:
	var _t := 0.0

	func _ready() -> void:
		material = Fx.additive_mat()
		var spr := Sprite2D.new()
		if ResourceLoader.exists("res://assets/env/glow_soft.png"):
			spr.texture = DensityTextures.load_texture("res://assets/env/glow_soft.png")
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.scale = Vector2(1.1, 0.7)
		spr.modulate = Color(0.95, 0.72, 0.42, 0.16)
		add_child(spr)

	func _process(delta: float) -> void:
		_t += delta
		position.y += sin(_t * 0.9) * 4.0 * delta


## 声波锥：三道向外扩散的弧线（加法），跟着朝向。
class SonicConeFx extends Node2D:
	var direction := Vector2.LEFT
	var length := 140.0
	var lifetime := 0.6
	var tint := Color(0.95, 0.80, 0.45)
	var _age := 0.0

	func _ready() -> void:
		z_index = 5
		material = Fx.additive_mat()
		rotation = direction.angle()

	func _process(delta: float) -> void:
		_age += delta
		if _age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / maxf(lifetime, 0.01), 0.0, 1.0)
		for i in 3:
			var r := length * (0.35 + 0.55 * k + 0.08 * float(i))
			var a := clampf((1.0 - k) * 0.55 - 0.12 * float(i), 0.0, 1.0)
			var pts := PackedVector2Array()
			for st in 7:
				var ang := lerpf(-0.42, 0.42, float(st) / 6.0)
				pts.append(Vector2(cos(ang) * r, sin(ang) * r))
			draw_polyline(pts, Color(tint.r, tint.g, tint.b, a), 2.0)


## 烛雨：几滴烛泪从顶上落下，落地时在脚下炸一小片判定。
class CandleRain extends Node2D:
	var width := 200.0
	var drops := 3
	var fall_time := 0.45
	var damage := 1
	var _age := 0.0
	var _boxes: Array[Hitbox] = []
	var _offsets: Array[float] = []

	func _ready() -> void:
		for i in drops:
			_offsets.append(-width * 0.5 + width * (float(i) + 0.5) / float(maxi(drops, 1)))
		z_index = 5
		material = Fx.additive_mat()
		set_process(true)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= fall_time and _boxes.is_empty():
			for x in _offsets:
				var box := Hitbox.new()
				box.damage = damage
				box.team = &"enemy"
				box.blow = &"light"
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2(26.0, 30.0)
				shape.shape = rect
				box.add_child(shape)
				add_child(box)
				box.position = Vector2(x, -15.0)
				box.arm(Vector2(0.0, -70.0))
				_boxes.append(box)
				Fx.dust_puff(global_position + Vector2(x, -4.0))
			Sfx.play_at(&"hit_bone", global_position, 0.06, -10.0)
		if _age >= fall_time + 0.28:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fall := clampf(_age / maxf(fall_time, 0.01), 0.0, 1.0)
		for i in _offsets.size():
			var x := _offsets[i]
			var y := lerpf(-210.0, -6.0, fall)
			draw_rect(Rect2(Vector2(roundf(x) - 1.0, roundf(y) - 6.0), Vector2(3, 9)),
					Color(1.0, 0.82, 0.48, 0.95))
			draw_rect(Rect2(Vector2(roundf(x) - 2.0, roundf(y) + 3.0), Vector2(5, 3)),
					Color(1.0, 0.62, 0.30, 0.8))


## 静默区：一圈暗下去的吸音雾。里面歌声听不见骑士（判定逻辑在 Boss 上）。
class SilenceZone extends Node2D:
	var size := Vector2(110.0, 90.0)
	var lifetime := 2.6
	var _age := 0.0

	func _ready() -> void:
		z_index = 6
		material = Fx.additive_mat()
		set_process(true)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / maxf(lifetime, 0.01), 0.0, 1.0)
		var a := clampf(0.35 * sin(k * PI), 0.0, 1.0)
		var r := size * 0.5 * (1.0 - 0.06 * k)
		for i in 14:
			var a0 := TAU * float(i) / 14.0
			var a1 := TAU * float(i + 1) / 14.0
			draw_line(Vector2(roundf(cos(a0) * r.x), roundf(sin(a0) * r.y)),
					Vector2(roundf(cos(a1) * r.x), roundf(sin(a1) * r.y)),
					Color(0.48, 0.56, 0.92, a), 2.0)
		draw_circle(Vector2.ZERO, 12.0, Color(0.30, 0.36, 0.68, a * 0.4))


# ---------------------------------------------------------------------------
# 数据：攻击表 / 场地事件
# ---------------------------------------------------------------------------
class ChoirKit extends BossKit:
	func boss_id() -> StringName:
		return &"silent_choir"

	func boss_title() -> String:
		return "无声唱诗班 · 末页的守夜"

	func boss_subtitle() -> String:
		return "把名字唱成账的人"

	func max_phases() -> int:
		return 2

	func phase_thresholds() -> Array[float]:
		return [1.0, 0.5]

	func min_interval() -> float:
		return 0.8

	func attack_table() -> Array[Dictionary]:
		return [
			{
				"id": &"sound_cone", "phase": 1, "weight": 2.0,
				"cooldown": 2.5, "cooldown_by_phase": [2.5, 1.8],
				"min_range": 0.0, "max_range": 380.0,
				"windup": 0.60, "windup_by_phase": [0.60, 0.50],
				"active": 0.30, "recovery": 0.40,
				"telegraph": &"sound_cone",
				"hitbox": {"offset": Vector2(70.0, -10.0), "size": Vector2(140.0, 44.0)},
			},
			{
				"id": &"candle_rain", "phase": 1, "weight": 1.7,
				"cooldown": 3.2, "cooldown_by_phase": [3.2, 2.4],
				"min_range": 0.0, "max_range": 620.0,
				"windup": 0.65, "windup_by_phase": [0.65, 0.55],
				"active": 0.60, "recovery": 0.50,
				"telegraph": &"candle_rain",
				"hitbox": {},
			},
			{
				"id": &"silence_zone", "phase": 1, "weight": 1.0,
				"cooldown": 6.5, "cooldown_by_phase": [6.5, 4.5],
				"min_range": 0.0, "max_range": 0.0,
				"windup": 0.70, "windup_by_phase": [0.70, 0.60],
				"active": 2.60, "recovery": 0.50,
				"telegraph": &"silence_zone", "damaging": false,
				"hitbox": {},
			},
			{
				"id": &"harmony_beam", "phase": 2, "weight": 1.6,
				"cooldown": 3.4,
				"min_range": 0.0, "max_range": 0.0,
				"windup": 0.70, "active": 0.25, "recovery": 0.55,
				"telegraph": &"harmony_beam",
				"hitbox": {},
			},
		]

	func arena_events() -> Array[Dictionary]:
		return [
			{"id": &"choir_rise", "at_phase": 1, "once": true},
			{"id": &"silence_veil", "at_phase": 2, "once": true},
			{"id": &"choir_fade", "at_phase": 0, "once": true},
		]
