extends EnemyBase
## 梦魇（终关 Boss）：一匹无主的战马。站在竞技场一侧等骑士靠近，之后循环
## 「蓄势 → 直线冲锋 → 撞墙/冲过头后喘息」；身体低矮，起跳能越过。
##
## 三期重做（M3b）：保留原有「冲锋 + 火骷髅 + 撞墙」行为与测试语义，在其上叠
## 三个阶段：
##   一阶段：冲锋（原样）。
##   二阶段（<= 2/3 生命）：冲锋更快 + 火骷髅 + **余烬雨**（鬃毛火星周期性落
##          在竞技场地面，落点先亮预警框）。
##   三阶段（<= 1/3 生命）：**地裂**（沿地面三段爆裂）与**热浪**（左右扩散的
##          可弹反热浪）加入轮转；竞技场边界向内收，炉心的热度再上一档。
## 入场 / 死亡演出不锁输入（Director 层可随时 skip），演出步骤数据在 Kit 里。

signal slain

enum State { IDLE, WINDUP, CHARGE, REST, NEIGH, QUAKE, HEAT_WAVE }

@export var aggro_range: float = 340.0
@export var windup_time: float = 0.7
@export var charge_speed: float = 260.0
## 冲过骑士这么远还没撞墙就自己刹车。
@export var overshoot: float = 260.0
@export var rest_time: float = 1.1
@export var neigh_time: float = 1.4
@export var contact_damage: int = 1
## Optional world-space arena bounds. The body and its summons stay inside.
@export var arena_left: float = -INF
@export var arena_right: float = INF

const HORSE_CHAR := "original_nightmare"
## idle 128×96 / gallop 144×96，蹄底都贴画布底边：centered Sprite 中心抬 48px。
const HORSE_POS := Vector2(0.0, -48.0)
const IDLE_FPS := 6.0
const WINDUP_IDLE_FPS := 11.0
const GALLOP_FPS := 12.0
const BOSS_TITLE := "锈 墓 梦 魇 · 无 主 之 马"
const MAX_HP := 16
const WINDUP_TINT := Color(1.3, 0.78, 0.72)
const DIRECTION_LOCK_TIME := 0.2
const CHARGE_KNOCKBACK := Vector2(120.0, -80.0)
## 没墙也没骑士时的冲锋上限，防止一路跑出关。
const CHARGE_MAX_TIME := 3.0
## 冲锋探针：身前 30px、从膝盖到脚下的竖直射线，探不到地面就刹车。
const PROBE_AHEAD := 30.0
const PROBE_TOP := 20.0
const PROBE_BOTTOM := 12.0
const FACE_DEADZONE := 8.0
## 马身比基类默认的 16px 宽：站定时把钻进身子里的骑士挤到这个半宽之外。
const BODY_HALF_W := 26.0
## 半血后每第 NEIGH_EVERY 次出手改成嘶鸣。
const NEIGH_EVERY := 3
const SKULL_SCENE_PATH := "res://scenes/enemies/FireSkullEnemy.tscn"
const SKULL_PREFIX := "Nightmare_Skull_"
const SKULLS_PER_NEIGH := 2
const MAX_SKULLS := 4
const SKULL_SPAWN_HEIGHT := 60.0
const SKULL_SPAWN_SPREAD := 22.0

## --- 三期新增：阶段 / 余烬雨 / 地裂 / 热浪 -----------------------------------
const PHASE_COUNT := 3
## 阈值：2/3 生命进二阶段，1/3 生命进三阶段（Kit 与本脚本同源）。
const PHASE2_RATIO := 2.0 / 3.0
const PHASE3_RATIO := 1.0 / 3.0
## 三阶段竞技场每侧向内收这么多像素（炉心的地缝把它困住）。
const PHASE3_ARENA_INSET := 96.0
const PHASE_TRANSITION_TIME := 1.2
## 余烬雨：二阶段起，每隔 EMBER_RAIN_EVERY 秒从鬃毛落一阵火星（预警 0.5s）。
const EMBER_RAIN_EVERY := 4.2
const EMBER_RAIN_WARN := 0.5
const EMBER_RAIN_ZONE := Vector2(44.0, 60.0)
const EMBER_RAIN_MAX := 6
## 地裂：三阶段，沿地面三段爆裂（预警框 -> 判定）。
const QUAKE_WINDUP := 0.62
const QUAKE_ACTIVE := 0.30
const QUAKE_RECOVERY := 0.55
const QUAKE_SPAN := 110.0
const QUAKE_ZONE := Vector2(52.0, 70.0)
## 热浪：三阶段，左右各一道可弹反的热浪（Projectile 管线）。
const WAVE_WINDUP := 0.55
const WAVE_ACTIVE := 0.20
const WAVE_RECOVERY := 0.60
const HEAT_WAVE_SPEED := 170.0
const PROJECTILE_PATH := "res://scenes/combat/Projectile.tscn"

var _state: State = State.IDLE
var _timer: float = 0.0
var _facing: float = -1.0
var _announced := false
var _enraged := false
var _charges := 0
var _since_neigh := 0
var _skulls_spawned := 0
var _direction_locked := false
var _lane: CombatMarker
## 三期新增状态。
var _phase := 1
var _heat_level := 0
var _phase3_done := false
var _transition_left := 0.0
var _ember_timer := EMBER_RAIN_EVERY
var _ember_rain := 0
var _quake_count := 0
var _heat_wave_count := 0
var _special_index := 0
var _base_left := -INF
var _base_right := INF
var _transient: Array[Node] = []
## Boss 框架（契约 §4.1）：攻击表 / 阶段 / 场地事件的数据与观测。
var _boss_kit: BossKit
var _boss_director: BossDirector

## 冲锋路径线：从马头前方向冲锋方向伸出这么长（锁向前跟随骑士，锁向后定死变白）。
const LANE_LENGTH := 240.0
const LANE_START := Vector2(34.0, -3.0)
const LANE_COLOR := Color(1.0, 0.45, 0.35, 0.95)

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox


func _enemy_ready() -> void:
	hit_material = &"boss"
	health.max_hp = MAX_HP
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	hitbox.team = &"enemy"
	hitbox.damage = contact_damage
	hitbox.disarm()
	_anchor_x = global_position.x
	_base_left = arena_left
	_base_right = arena_right
	_build_visual()
	_build_boss_framework()


func _build_visual() -> void:
	_anim = _build_frame_anim(HORSE_CHAR, [
		["idle", "", IDLE_FPS, true, HORSE_POS],
		["gallop", "", GALLOP_FPS, true, HORSE_POS],
		["windup", "", 8.0, false, HORSE_POS],
		["rest", "", 7.0, true, HORSE_POS],
		["neigh", "", 6.0, true, HORSE_POS],
		["quake", "", 7.0, true, HORSE_POS],
		["heat_wave", "", 7.0, true, HORSE_POS],
	])
	if _anim != null:
		_anim.play("idle")
		visual.add_child(_anim)
		_flash_target = _anim
		_hide_placeholder_rects(visual)
	elif visual.has_node("Placeholder"):
		_flash_target = visual.get_node("Placeholder") as CanvasItem


## Boss 血条只在骑士跨进 aggro 圈（或先手打到它）时出现，且只出现一次。
func announce() -> void:
	if _announced:
		return
	_announced = true
	# 先发「开场开始」（音乐 / 演出据此起势），紧接着才是 Boss 血条。
	GameEvents.boss_intro_started.emit(BOSS_TITLE)
	GameEvents.boss_appeared.emit(BOSS_TITLE, health.current, health.max_hp)
	# 框架侧：开战场地事件（舞台灯 / 机关）由 kit 的 arena_events 统一登记。
	if _boss_director != null:
		_boss_director.notify_intro()


func is_announced() -> bool:
	return _announced


func is_enraged() -> bool:
	return _enraged


func state() -> State:
	return _state


func charge_count() -> int:
	return _charges


func _on_hp_changed(current: int, maximum: int) -> void:
	announce()
	GameEvents.boss_hp_changed.emit(current, maximum)
	if current <= 0 or maximum <= 0:
		_sync_boss_framework(current, maximum)
		return
	if _state == State.IDLE and current < maximum:
		# 远程先手也算开战。
		var player := _player()
		if player != null:
			_face_player(player)
		_enter_windup()
	var ratio := float(current) / float(maximum)
	if not _enraged and ratio <= PHASE2_RATIO:
		_enter_phase_two()
	elif not _phase3_done and ratio <= PHASE3_RATIO:
		_enter_phase_three()
	_sync_boss_framework(current, maximum)


## 二阶段：相变演出 + 节奏收紧（前摇 0.7→0.58、喘息 1.1→0.9、冲速 x1.12，锁向仍留最后 0.2 秒，
## 召唤上限不变）；相变后的第一手固定是嘶鸣召火骷髅，让「变强了」先被看见再被打到。
## 三期：阈值改为 <= 2/3 生命；热度上到 1，余烬雨开始落。
func _enter_phase_two() -> void:
	if _enraged:
		return
	_enraged = true
	_phase = 2
	_heat_level = 1
	windup_time = CombatRules.NIGHTMARE_P2_WINDUP
	rest_time = CombatRules.NIGHTMARE_P2_REST
	charge_speed *= CombatRules.NIGHTMARE_P2_SPEED_K
	_since_neigh = NEIGH_EVERY - 1
	_transition_left = PHASE_TRANSITION_TIME
	health.invincible = true
	_ember_timer = EMBER_RAIN_EVERY * 0.5
	Juice.boss_phase_beat(global_position + Vector2(0.0, -40.0), Color(1.0, 0.82, 0.7))
	Fx.attach_heat_lick(visual)
	GameEvents.announcement.emit("梦魇的鬃毛烧成了白焰——余烬开始落")
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, 2)


## 三阶段：地缝把竞技场收窄、热度再上一档；地裂与热浪加入轮转。
func _enter_phase_three() -> void:
	if _phase3_done:
		return
	_phase3_done = true
	_phase = 3
	_heat_level = 2
	_transition_left = PHASE_TRANSITION_TIME
	health.invincible = true
	Juice.boss_phase_beat(global_position + Vector2(0.0, -40.0), Color(1.0, 0.42, 0.18))
	Fx.attach_ember(visual)
	_apply_phase_bounds()
	GameEvents.announcement.emit("地裂开了。炉心把梦魇和骑士一起往中间挤")
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, 3)


## 三阶段：竞技场每侧向内收 PHASE3_ARENA_INSET；若布局挂了 BossArena 一并同步。
func _apply_phase_bounds() -> void:
	if not is_finite(_base_left) and is_finite(arena_left):
		_base_left = arena_left
	if not is_finite(_base_right) and is_finite(arena_right):
		_base_right = arena_right
	if is_finite(_base_left):
		arena_left = _base_left + PHASE3_ARENA_INSET
	if is_finite(_base_right):
		arena_right = _base_right - PHASE3_ARENA_INSET
	if is_finite(arena_left) and is_finite(arena_right) and arena_right <= arena_left:
		# 边界数据异常时不要把自己夹成负宽度：退回原值。
		arena_left = _base_left
		arena_right = _base_right
	var arena := _find_arena()
	if arena != null:
		arena.set("arena_left", arena_left)
		arena.set("arena_right", arena_right)
		if arena.has_method("sync_camera_limits"):
			arena.call("sync_camera_limits")


func _find_arena() -> Node:
	var arena_name := String(get_meta("boss_arena_name", ""))
	if arena_name == "":
		return null
	var world := GameContext.world_root(self)
	if world == null:
		return null
	return world.get_node_or_null("Arenas/" + arena_name)


func phase() -> int:
	return _phase


func heat_level() -> int:
	return _heat_level


func ember_rain_count() -> int:
	return _ember_rain


func quake_count() -> int:
	return _quake_count


func heat_wave_count() -> int:
	return _heat_wave_count


func arena_bounds_now() -> Vector2:
	return Vector2(arena_left, arena_right)


func _tick_phase_transition(delta: float) -> bool:
	if _transition_left <= 0.0:
		return false
	_transition_left = maxf(0.0, _transition_left - delta)
	if _transition_left <= 0.0:
		health.invincible = false
	return true


func _tick_state(delta: float) -> void:
	if _dead:
		return
	if _tick_phase_transition(delta):
		return
	var player := _player()
	match _state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			if player != null and global_position.distance_to(player.global_position) <= aggro_range:
				announce()
				_face_player(player)
				_enter_windup()
		State.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			if player != null and not _direction_locked:
				_face_player(player)
			_timer -= delta
			if _timer <= DIRECTION_LOCK_TIME and not _direction_locked:
				_direction_locked = true
				Sfx.play(&"land", 0.0, -8.0)
				# 锁向：路径线定死并变白实线——这条线就是冲锋的路。
				if _lane != null and is_instance_valid(_lane):
					_lane.lock()
			_sync_lane()
			if _timer <= 0.0:
				_begin_charge()
		State.CHARGE:
			_tick_charge(player, delta)
		State.REST:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_timer -= delta
			if _timer <= 0.0:
				_pick_next_move(player)
		State.NEIGH:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_timer -= delta
			if _timer <= 0.0:
				if player != null:
					_face_player(player)
				_enter_windup()
		State.QUAKE:
			_tick_quake(delta)
		State.HEAT_WAVE:
			_tick_heat_wave(delta)
	# 余烬雨：二阶段起的持续场地威胁（不在冲锋判定里，落点自带预警）。
	if _enraged:
		_tick_ember_rain(delta)


func _tick_charge(player: Player, delta: float) -> void:
	velocity.x = _dir * charge_speed
	_timer -= delta
	var next_x := global_position.x + velocity.x * delta
	if next_x - BODY_HALF_W <= arena_left or next_x + BODY_HALF_W >= arena_right:
		_wall_slam()
	elif _wall_ahead():
		_wall_slam()
	elif not _ground_ahead():
		velocity.x = 0.0
		_enter_rest()
	elif player != null and (global_position.x - player.global_position.x) * _dir > overshoot:
		_enter_rest()
	elif _timer <= 0.0:
		_enter_rest()


## 喘完气：没人就回去站着；二阶段起每第三次出手改成嘶鸣。
## 三阶段轮转：冲锋 → 地裂 → 热浪 → 冲锋……（嘶鸣仍按原节奏插入）。
func _pick_next_move(player: Player) -> void:
	if player == null:
		_state = State.IDLE
		return
	_face_player(player)
	if _enraged and _since_neigh >= NEIGH_EVERY - 1:
		_begin_neigh()
		return
	if _phase >= 3:
		_special_index += 1
		var choice := _special_index % 3
		if choice == 1:
			_begin_quake()
			return
		if choice == 2:
			_begin_heat_wave()
			return
	_enter_windup()


# ---------------------------------------------------------------------------
# 三阶段招式：地裂 / 热浪 / 余烬雨
# ---------------------------------------------------------------------------
## 地裂：沿骑士脚下左右各一段地面爆裂，预警框先亮，随后升起三根火柱判定。
func _begin_quake() -> void:
	_state = State.QUAKE
	_timer = QUAKE_WINDUP
	_quake_step = 0
	hitbox.disarm()
	_clear_tint()
	_dismiss_lane()
	hide_opening()
	_quake_count += 1
	var player := _player()
	var centre := player.global_position.x if player != null else global_position.x
	_quake_centre = clampf(centre, arena_left + QUAKE_ZONE.x, arena_right - QUAKE_ZONE.x)
	begin_telegraph(&"nightmare", QUAKE_WINDUP)
	for i in 3:
		var x := _quake_centre + (float(i) - 1.0) * QUAKE_SPAN
		CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
				Vector2(x - global_position.x, -QUAKE_ZONE.y * 0.5), QUAKE_WINDUP,
				Color(1.0, 0.5, 0.2, 0.95), {"rect": Rect2(-QUAKE_ZONE * 0.5, QUAKE_ZONE)})
	Sfx.play_at(CombatRules.sfx_key(&"boss_roar"), global_position, 0.12, -6.0)
	_notify_framework_attack(&"quake")


func _tick_quake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	_timer -= delta
	if _quake_step == 0 and _timer <= 0.0:
		_quake_step = 1
		_timer = QUAKE_ACTIVE
		_do_quake()
	elif _quake_step == 1 and _timer <= 0.0:
		_quake_step = 2
		_timer = QUAKE_RECOVERY
		_enter_rest()


var _quake_step := 0
var _quake_centre := 0.0


func _do_quake() -> void:
	for i in 3:
		var x := clampf(_quake_centre + (float(i) - 1.0) * QUAKE_SPAN,
				arena_left + QUAKE_ZONE.x * 0.5, arena_right - QUAKE_ZONE.x * 0.5)
		_spawn_zone_hitbox(Vector2(x, global_position.y - QUAKE_ZONE.y * 0.5), QUAKE_ZONE,
				2, Vector2(0.0, -150.0))
		Fx.dust_puff(Vector2(x, global_position.y), -PI * 0.5)
	Juice.shake(6.0, 320)
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_slam"), global_position, 0.1, -3.0)


## 热浪：左右各一道可弹反的热浪（Projectile 管线）。弹回来会让梦魇露出破绽。
func _begin_heat_wave() -> void:
	_state = State.HEAT_WAVE
	_timer = WAVE_WINDUP
	_heat_wave_step = 0
	hitbox.disarm()
	_clear_tint()
	_dismiss_lane()
	hide_opening()
	_heat_wave_count += 1
	begin_telegraph(&"nightmare", WAVE_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.RING, Vector2(0.0, -30.0), WAVE_WINDUP,
			Color(1.0, 0.62, 0.3, 0.95), {"radius_from": 20.0, "radius_to": 70.0})
	Sfx.play_at(CombatRules.sfx_key(&"boss_roar"), global_position, 0.12, -8.0)
	_notify_framework_attack(&"heat_wave")


func _tick_heat_wave(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	_timer -= delta
	if _heat_wave_step == 0 and _timer <= 0.0:
		_heat_wave_step = 1
		_timer = WAVE_ACTIVE
		_do_heat_wave()
	elif _heat_wave_step == 1 and _timer <= 0.0:
		_heat_wave_step = 2
		_timer = WAVE_RECOVERY
		_enter_rest()


var _heat_wave_step := 0


func _do_heat_wave() -> void:
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	var scene: PackedScene = null
	if ResourceLoader.exists(PROJECTILE_PATH):
		scene = load(PROJECTILE_PATH) as PackedScene
	if scene != null and host != null:
		for dir in [-1.0, 1.0]:
			var bolt := scene.instantiate() as Projectile
			host.add_child(bolt)
			bolt.global_position = global_position + Vector2(dir * 40.0, -14.0)
			bolt.setup(bolt.global_position, Vector2(dir, 0.0), HEAT_WAVE_SPEED, &"enemy", self)
			bolt.damage = 1
			_transient.append(bolt)
	Fx.burst(&"ring", global_position + Vector2(0.0, -20.0))
	Sfx.play_at(CombatRules.sfx_key(&"horse_charge"), global_position, 0.1, -6.0)


# ---------------------------------------------------------------------------
# 余烬雨（二阶段起的场地威胁）
# ---------------------------------------------------------------------------
func _tick_ember_rain(delta: float) -> void:
	_ember_timer -= delta
	if _ember_timer > 0.0:
		return
	_ember_timer = EMBER_RAIN_EVERY
	_spawn_ember_rain()


## 在骑士（或梦魇自己）附近落一柱余烬：0.5s 预警框 -> 0.25s 判定。
## 返回生成的柱数（测试 / 诊断用）。
func _spawn_ember_rain() -> int:
	if _ember_rain >= EMBER_RAIN_MAX or _dead:
		return 0
	var player := _player()
	var centre := player.global_position.x if player != null else global_position.x
	centre = clampf(centre, arena_left + 40.0, arena_right - 40.0)
	var column := EmberColumn.new()
	column.name = "EmberRain%d" % (_ember_rain + 1)
	column.warn = EMBER_RAIN_WARN
	column.active_time = 0.25
	column.size = EMBER_RAIN_ZONE
	column.damage = 1
	column.owner_boss = self
	add_child(column)
	column.position = Vector2(centre - global_position.x, 0.0)
	_transient.append(column)
	_ember_rain += 1
	return 1


## 余烬柱：地面残影预警 -> 判定火柱 -> 消散。全程画面在自身 _draw 里。
class EmberColumn extends Node2D:
	var warn := 0.5
	var active_time := 0.25
	var size := Vector2(44.0, 60.0)
	var damage := 1
	var owner_boss: Node2D
	var _t := 0.0
	var _armed := false
	var _done := false
	var _box: Hitbox

	func _process(delta: float) -> void:
		if _done:
			return
		_t += delta
		if not _armed and _t >= warn:
			_armed = true
			_box = Hitbox.new()
			_box.damage = damage
			_box.team = &"enemy"
			_box.blow = &"heavy"
			_box.knockback = Vector2(0.0, -120.0)
			_box.monitoring = true
			_box.collision_layer = 8
			_box.collision_mask = 32
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = size
			shape.shape = rect
			_box.add_child(shape)
			add_child(_box)
			_box.arm(Vector2(0.0, -120.0))
			Fx.burst(&"ring", global_position)
			Sfx.play_at(CombatRules.sfx_key(&"land"), global_position, 0.1, -6.0)
		if _armed and _t >= warn + active_time:
			if is_instance_valid(_box):
				_box.disarm()
				_box.queue_free()
			_done = true
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(-size * 0.5, size)
		if not _armed:
			var blink := 0.5 + 0.5 * sin(_t * 30.0)
			draw_rect(rect, Color(1.0, 0.4, 0.15, 0.16 * blink), true)
			draw_rect(rect, Color(1.0, 0.6, 0.25, 0.8 * blink), false, 1.0)
		else:
			draw_rect(rect, Color(1.0, 0.42, 0.12, 0.32), true)
			draw_rect(rect, Color(1.0, 0.75, 0.3, 0.95), false, 1.0)


## 敌人 Hitbox 生成 helper（灼热 / 地裂共用；几帧后自动收掉）。
func _spawn_zone_hitbox(at: Vector2, size: Vector2, dmg: int, knock: Vector2) -> Hitbox:
	var host := get_parent()
	if host == null:
		return null
	var box := Hitbox.new()
	box.damage = dmg
	box.team = &"enemy"
	box.blow = &"heavy"
	box.knockback = knock
	box.monitoring = true
	box.collision_layer = 8
	box.collision_mask = 32
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	box.add_child(shape)
	host.add_child(box)
	box.global_position = at
	box.arm(knock)
	_transient.append(box)
	return box


func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = windup_time
	_direction_locked = false
	hitbox.disarm()
	_apply_tint()
	hide_opening()
	# 读招：微红蓄势（机体）+ 地面路径线（跟随骑士，锁向后变白实线）。
	begin_telegraph(&"nightmare", windup_time)
	_spawn_lane()
	_notify_framework_attack(&"charge")


func _begin_charge() -> void:
	_state = State.CHARGE
	_timer = CHARGE_MAX_TIME
	_dir = _facing
	_charges += 1
	_since_neigh += 1
	_clear_tint()
	_dismiss_lane()
	hitbox.arm(Vector2(_dir * CHARGE_KNOCKBACK.x, CHARGE_KNOCKBACK.y))
	Fx.dust_puff(global_position, PI if _dir > 0.0 else 0.0)
	Sfx.play_at(CombatRules.sfx_key(&"horse_charge"), global_position, 0.1, -6.0)


func _spawn_lane() -> void:
	_dismiss_lane()
	_lane = CombatMarker.spawn(self, CombatMarker.Kind.LANE,
			Vector2(0.0, LANE_START.y), 0.0, LANE_COLOR,
			{"length": LANE_LENGTH, "facing": _facing})
	_sync_lane()


## 路径线贴着「现在的朝向」摆：起点在马头前方，朝 _facing 伸出。
func _sync_lane() -> void:
	if _lane == null or not is_instance_valid(_lane):
		return
	_lane.facing = _facing
	_lane.position.x = _facing * LANE_START.x


func _dismiss_lane() -> void:
	if _lane != null and is_instance_valid(_lane):
		_lane.dismiss()
	_lane = null


func _wall_slam() -> void:
	velocity.x = 0.0
	Juice.shake(3.0, 200)
	Fx.dust_puff(global_position, -PI * 0.5)
	Sfx.play(&"land", 0.1, -4.0)
	_flash_white()
	_enter_rest()


func _enter_rest() -> void:
	_state = State.REST
	_timer = rest_time
	hitbox.disarm()
	_clear_tint()
	_dismiss_lane()
	# 喘息就是破绽：头顶金箭头亮满整个窗口。
	show_opening(rest_time)


func _interrupt_for_poise() -> void:
	hitbox.disarm()
	_dismiss_lane()
	_disarm_poise_hitboxes(_transient)
	_state = State.REST
	_timer = 0.0
	_clear_tint()


## 嘶鸣：停 neigh_time，震屏，从鬃毛里落下火骷髅。
func _begin_neigh() -> void:
	_state = State.NEIGH
	_timer = neigh_time
	_since_neigh = 0
	velocity.x = 0.0
	hitbox.disarm()
	_clear_tint()
	Juice.shake(4.0, 300)
	GameEvents.announcement.emit("梦魇嘶鸣，火星从鬃毛里落下")
	Fx.hit_sparks(global_position + Vector2(0.0, -48.0))
	Fx.burst(&"ring", global_position + Vector2(0.0, -36.0))
	Sfx.play_at(CombatRules.sfx_key(&"boss_roar"), global_position, 0.15, -4.0)
	_spawn_skulls()
	_notify_framework_attack(&"neigh")


## 在自身上方两侧各生成一只火骷髅，挂到自己的父节点下；同时存在不超过 MAX_SKULLS。
func _spawn_skulls() -> void:
	if not ResourceLoader.exists(SKULL_SCENE_PATH):
		return
	var host := get_parent()
	if host == null:
		return
	var scene := load(SKULL_SCENE_PATH) as PackedScene
	if scene == null:
		return
	var room := MAX_SKULLS - _live_skulls()
	for i in mini(SKULLS_PER_NEIGH, room):
		var skull := scene.instantiate() as Node2D
		_skulls_spawned += 1
		skull.name = SKULL_PREFIX + str(_skulls_spawned)
		var side := -1.0 if i % 2 == 0 else 1.0
		var spawn := global_position + Vector2(side * SKULL_SPAWN_SPREAD, -SKULL_SPAWN_HEIGHT)
		spawn.x = clampf(spawn.x, arena_left + 24.0, arena_right - 24.0)
		skull.set("arena_left", arena_left)
		skull.set("arena_right", arena_right)
		# 先定位再入树：火骷髅在 _ready 里记出生点当巡飞锚点。
		skull.position = (host as Node2D).to_local(spawn) if host is Node2D else spawn
		host.add_child(skull)


func _live_skulls() -> int:
	var host := get_parent()
	if host == null:
		return 0
	var n := 0
	for child in host.get_children():
		if String(child.name).begins_with(SKULL_PREFIX) and not child.is_queued_for_deletion():
			n += 1
	return n


## 主人倒下，鬃毛里的火也跟着灭。
func _dismiss_skulls() -> void:
	var host := get_parent()
	if host == null:
		return
	for child in host.get_children():
		if child is Node2D and String(child.name).begins_with(SKULL_PREFIX) \
				and not child.is_queued_for_deletion():
			Fx.enemy_death_smoke((child as Node2D).global_position)
			child.queue_free()


## 只认冲锋方向上的墙。
func _wall_ahead() -> bool:
	return is_on_wall() and signf(get_wall_normal().x) == -_dir


func _ground_ahead() -> bool:
	if not is_on_floor():
		return true
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(_dir * PROBE_AHEAD, -PROBE_TOP)
	var to := global_position + Vector2(_dir * PROBE_AHEAD, PROBE_BOTTOM)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1, [get_rid()])
	return not space.intersect_ray(query).is_empty()


func _face_player(player: Player) -> void:
	var dx := player.global_position.x - global_position.x
	if absf(dx) > FACE_DEADZONE:
		_facing = signf(dx)


## 蓄势微红打在机体上；受击白闪落回时由 _flash_restore_color 保住这层色。
func _apply_tint() -> void:
	if _flash_target != null:
		_flash_target.modulate = WINDUP_TINT


func _clear_tint() -> void:
	if _flash_target == null:
		return
	if _flash_tween == null or not _flash_tween.is_valid():
		_flash_target.modulate = Color.WHITE


func _flash_restore_color() -> Color:
	return WINDUP_TINT if _state == State.WINDUP else Color.WHITE


## 原图面朝左；面朝右时水平镜像。
func _after_move() -> void:
	global_position.x = clampf(global_position.x, arena_left + BODY_HALF_W, arena_right - BODY_HALF_W)
	visual.scale.x = -1.0 if _facing > 0.0 else 1.0
	_update_anim()


func _update_anim() -> void:
	if _anim == null:
		return
	match _state:
		State.CHARGE:
			_anim.play("gallop")
		State.WINDUP:
			_anim.pin_frame("windup", clampi(int((1.0 - _timer / maxf(windup_time, 0.1)) * 5.0), 0, 4))
		State.REST:
			_anim.play("rest")
		State.NEIGH:
			_anim.play("neigh")
		State.QUAKE:
			_anim.play("quake")
		State.HEAT_WAVE:
			_anim.play("heat_wave")
		_:
			_anim.set_fps("idle", IDLE_FPS)
			_anim.play("idle")


## 同基类逻辑，只把挤开半宽放大到马身宽度。
func _separate_from_player() -> void:
	var player := knight()
	if player == null or player.is_invincible():
		return
	var to_p := player.global_position - global_position
	if absf(to_p.x) > BODY_HALF_W or absf(to_p.y) > BODY_SEPARATE_Y:
		return
	var push := signf(to_p.x)
	if push == 0.0:
		push = -_facing if _facing != 0.0 else 1.0
	if absf(player.velocity.x) < 90.0 or signf(player.velocity.x) != push:
		player.velocity.x = push * 88.0


func _player() -> Player:
	var p := knight()
	if p == null or p.health.current <= 0:
		return null
	return p


func _on_died() -> void:
	_dismiss_skulls()
	_dismiss_lane()
	_cleanup_transient()
	if _boss_director != null:
		_boss_director.notify_death()
	slain.emit()
	# 死亡演出钩子：慢动作 + 大震屏 + 双圈 + 碎屑 + 音效（受 Settings 缩放）。
	Juice.boss_death_beat(global_position + Vector2(0.0, -44.0))
	GameEvents.boss_defeated.emit()
	SaveData.mark_flag("nightmare_dead")
	SaveData.persist_story()
	_death_burst(CharFrames.anim(HORSE_CHAR, "death"), 12.0, _facing > 0.0, HORSE_POS.y, "梦魇跪进炉灰里")


func _cleanup_transient() -> void:
	for node in _transient:
		if is_instance_valid(node):
			node.queue_free()
	_transient.clear()


# --- boss framework (M3) -----------------------------------------------------
## 结构迁移（契约 §4.1）：冲锋 / 嘶鸣 / 阶段 / 场地事件收敛到一份 BossKit，由
## BossDirector 以协助模式挂载 —— 只观测，不接管现有状态机。三期重做只加数据与
## 新状态，不改冲锋 / 锁向 / 撞墙 / 召唤的原有时序。
##
## 演出（入场 / 死亡 / 相变）全部不锁输入：没有 Director 剧本时玩家能直接动，
## 由章节脚本调用 Director.play(kit.intro_steps(), true) 时也能被 skip_step 跳过。

## 这场 Boss 的 Kit（延迟构建）。
func boss_kit() -> BossKit:
	if _boss_kit == null:
		_boss_kit = BossKit.new(_boss_kit_config())
	return _boss_kit


## 挂在本 Boss 下的导演层（协助模式；无则返回 null）。
func boss_director() -> BossDirector:
	return _boss_director


## 竞技场边界（世界 x）：level10 由章节 layout 通过 arena_left/right 注入。
func boss_arena_bounds() -> Vector2:
	return Vector2(arena_left, arena_right)


func _build_boss_framework() -> void:
	if _boss_kit == null:
		_boss_kit = BossKit.new(_boss_kit_config())
	if _boss_director == null:
		_boss_director = BossDirector.attach(self, _boss_kit, false)
	if _boss_director != null:
		_boss_director.set_hp(health.current, health.max_hp)


## HP -> 框架同步；0 HP 只通知一次死亡（notify_death 幂等）。
func _sync_boss_framework(current: int, maximum: int) -> void:
	if _boss_director == null:
		return
	if current <= 0:
		_boss_director.notify_death()
	else:
		_boss_director.set_hp(current, maximum)


func _notify_framework_attack(id: StringName) -> void:
	if _boss_director != null:
		_boss_director.notify_attack_started(id)


## 攻击表数据源。数值引用本脚本既有的导出默认值 / 常量，和实现同源：
##   charge    —— 蓄势 0.7s（P2 0.58s，P3 0.5s；windup_by_phase 表达）+ 冲锋 + 喘息。
##   neigh     —— 二阶段起：每第三次出手改成嘶鸣（召唤火骷髅，不直接伤人）。
##   ember_rain—— 二阶段起的周期性场地威胁（0.5s 预警 + 0.25s 判定）。
##   quake     —— 三阶段：地裂三段（预警框 + 火柱判定）。
##   heat_wave —— 三阶段：左右两道可弹反热浪。
## 「每第三手嘶鸣」与三阶段轮转仍由本脚本状态机决定（保持原行为）。
func _boss_kit_config() -> Dictionary:
	return {
		"id": &"nightmare",
		"title": BOSS_TITLE,
		"subtitle": "无 主 之 马",
		"max_phases": PHASE_COUNT,
		"phase_thresholds": [1.0, PHASE2_RATIO, PHASE3_RATIO],
		"min_interval": 0.9,
		"attacks": [
			{
				"id": &"charge", "phase": 1, "weight": 2.0,
				"cooldown": 1.1, "cooldown_by_phase": [1.1, 0.9, 0.8],
				"min_range": 0.0, "max_range": aggro_range,
				"windup": 0.7,
				"windup_by_phase": [0.7, CombatRules.NIGHTMARE_P2_WINDUP, 0.5],
				"active": 0.4, "recovery": 1.1,
				"telegraph": &"nightmare",
				"hitbox": {"offset": Vector2(0.0, -14.0), "size": Vector2(48.0, 28.0)},
			},
			{
				"id": &"neigh", "phase": 2, "weight": 1.0,
				"cooldown": 2.4, "min_range": 0.0, "max_range": 0.0,
				"windup": neigh_time, "active": 0.2, "recovery": 0.4,
				"telegraph": &"nightmare", "damaging": false, "hitbox": {},
			},
			{
				"id": &"ember_rain", "phase": 2, "weight": 0.6,
				"cooldown": EMBER_RAIN_EVERY, "min_range": 0.0, "max_range": 0.0,
				"windup": EMBER_RAIN_WARN, "active": 0.25, "recovery": 0.0,
				"telegraph": &"nightmare", "damaging": false, "hitbox": {},
			},
			{
				"id": &"quake", "phase": 3, "weight": 1.4,
				"cooldown": 2.4, "min_range": 0.0, "max_range": 0.0,
				"windup": QUAKE_WINDUP, "active": QUAKE_ACTIVE, "recovery": QUAKE_RECOVERY,
				"telegraph": &"nightmare",
				"hitbox": {"offset": Vector2(0.0, -QUAKE_ZONE.y * 0.5), "size": QUAKE_ZONE},
			},
			{
				"id": &"heat_wave", "phase": 3, "weight": 1.2,
				"cooldown": 2.6, "min_range": 0.0, "max_range": 0.0,
				"windup": WAVE_WINDUP, "active": WAVE_ACTIVE, "recovery": WAVE_RECOVERY,
				"telegraph": &"nightmare", "hitbox": {},
			},
		],
		"arena_events": [
			{"id": &"arena_surge", "at_phase": 1, "once": true},
			{"id": &"arena_hot", "at_phase": 2, "once": true},
			{"id": &"arena_quake_floor", "at_phase": 3, "once": true},
			{"id": &"arena_dim", "at_phase": 0, "once": true},
		],
		"intro_steps": [
			{"kind": "step", "id": "player"},
			{"kind": "cam_focus", "target": "Boss", "zoom": 1.35, "duration": 0.9},
			{"kind": "letterbox", "on": true, "duration": 0.25},
			{"kind": "caption", "text": "梦魇 · 无主之马", "hold": 1.4},
			{"kind": "letterbox", "on": false, "duration": 0.35},
			{"kind": "cam_release", "duration": 0.5},
		],
		"death_steps": [
			{"kind": "slowmo", "ms": 700, "scale": 0.2, "seconds": 0.0},
			{"kind": "shake", "px": 6.0, "ms": 500, "seconds": 0.0},
			{"kind": "caption", "text": "梦魇跪进炉灰里", "hold": 1.6},
		],
	}

