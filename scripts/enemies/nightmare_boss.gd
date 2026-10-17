extends EnemyBase
## 梦魇（终关 Boss）：一匹无主的战马。站在竞技场一侧等骑士靠近，之后循环
## 「蓄势 → 直线冲锋 → 撞墙/冲过头后喘息」；身体低矮，起跳能越过。
## 半血后每第三次冲锋改成嘶鸣，从鬃毛里落下两只火骷髅（同屏最多四只）。

signal slain

enum State { IDLE, WINDUP, CHARGE, REST, NEIGH }

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

const HORSE_CHAR := "boss_nightmare"
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
	_build_visual()


func _build_visual() -> void:
	_anim = _build_frame_anim(HORSE_CHAR, [
		["idle", "", IDLE_FPS, true, HORSE_POS],
		["gallop", "", GALLOP_FPS, true, HORSE_POS],
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
		return
	if _state == State.IDLE and current < maximum:
		# 远程先手也算开战。
		var player := _player()
		if player != null:
			_face_player(player)
		_enter_windup()
	if not _enraged and current <= maximum / 2:
		_enter_phase_two()


## 二阶段：相变演出 + 节奏收紧（前摇 0.7→0.58、喘息 1.1→0.9、冲速 x1.12，锁向仍留最后 0.2 秒，
## 召唤上限不变）；相变后的第一手固定是嘶鸣召火骷髅，让「变强了」先被看见再被打到。
func _enter_phase_two() -> void:
	_enraged = true
	windup_time = CombatRules.NIGHTMARE_P2_WINDUP
	rest_time = CombatRules.NIGHTMARE_P2_REST
	charge_speed *= CombatRules.NIGHTMARE_P2_SPEED_K
	_since_neigh = NEIGH_EVERY - 1
	Juice.boss_phase_beat(global_position + Vector2(0.0, -40.0), Color(1.0, 0.82, 0.7))
	Fx.attach_heat_lick(visual)
	GameEvents.announcement.emit("梦魇的鬃毛烧成了白焰")
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, 2)


func _tick_state(delta: float) -> void:
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


## 喘完气：没人就回去站着；半血后每第三次出手改成嘶鸣。
func _pick_next_move(player: Player) -> void:
	if player == null:
		_state = State.IDLE
		return
	_face_player(player)
	if _enraged and _since_neigh >= NEIGH_EVERY - 1:
		_begin_neigh()
	else:
		_enter_windup()


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
			_anim.set_fps("idle", WINDUP_IDLE_FPS)
			_anim.play("idle")
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
	slain.emit()
	# 死亡演出钩子：慢动作 + 大震屏 + 双圈 + 碎屑 + 音效（受 Settings 缩放）。
	Juice.boss_death_beat(global_position + Vector2(0.0, -44.0))
	GameEvents.boss_defeated.emit()
	SaveData.mark_flag("nightmare_dead")
	SaveData.persist_story()
	_death_burst([] as Array[Texture2D], 12.0, _facing > 0.0, 0.0, "梦魇跪进炉灰里")
