extends EnemyBase
## 炉风先驱（EmberwindHerald）· 最后的灰卫 —— 第拾叁章「炉风崖道」的 Boss。
##
## 一个不肯落地的灰卫。他悬在风口上：俯冲穿过竞技场、用风把骑士往崖边推、
## 甩出羽刃、在脚下点起上升气流。**钩锁的链条能把他从空中拉下来** —— 拉下的
## 那几秒是唯一能稳稳砍到他的窗口（破绽 + 硬直）。
## 二阶段炉风更热：俯冲更快、上升气流更强、羽刃更密。
##
## 框架（docs/integration-contracts.md §4.1）：BossKit + 驾驶模式 BossDirector。
## 可读性：前摇 >= 0.35s；同一时刻一条预警；hitbox 不出竞技场。
## 全部演出不锁输入，Director 层可随时跳过。

signal slain

enum State { IDLE, ATTACK, DOWNED }
enum AttackStep { WINDUP, ACTIVE, RECOVERY }

const BOSS_TITLE := "炉风先驱 · 最后的灰卫"
const BOSS_SUBTITLE := "最后的灰卫"
const MAX_HP := 19
const AGGRO_RANGE := 420.0
const FLAG_DEAD := "herald_dead"

const HOVER_HEIGHT := 150.0
const HOVER_BOB := 9.0
const HOVER_DRIFT := 34.0
const HOVER_SPEED := 90.0
const DIVE_SPEED := 520.0
const DIVE_SPEED_P2 := 620.0
const DIVE_LOW := 34.0

const DIVE_WINDUP := 0.58
const DIVE_ACTIVE := 0.42
const DIVE_RECOVERY := 0.82
const DIVE_LANE := 300.0
const DIVE_HITBOX := Vector2(58.0, 38.0)

const PUSH_WINDUP := 0.55
const PUSH_ACTIVE := 1.20
const PUSH_RECOVERY := 0.60
const PUSH_FLOW := 150.0
const PUSH_FLOW_P2 := 200.0
const PUSH_SIZE := Vector2(220.0, 180.0)

const BLADE_WINDUP := 0.55
const BLADE_ACTIVE := 0.20
const BLADE_RECOVERY := 0.70
const BLADE_COUNT := 5
const BLADE_SPEED := 230.0
const BLADE_SPREAD := 0.22

const UPDRAFT_WINDUP := 0.60
const UPDRAFT_ACTIVE := 0.20
const UPDRAFT_RECOVERY := 0.66
const UPDRAFT_LIFT := 420.0
const UPDRAFT_LIFT_P2 := 560.0
const UPDRAFT_LIFE := 3.4
const UPDRAFT_WIDTH := 96.0
const UPDRAFT_HEIGHT := 150.0

const DOWN_TIME := 2.6
const DOWN_RIPOSTE := 2.6
const PHASE_TRANSITION_TIME := 1.2

@export var arena_left: float = -INF
@export var arena_right: float = INF

var _state: State = State.IDLE
var _step: AttackStep = AttackStep.WINDUP
var _attack: StringName = &""
var _timer: float = 0.0
var _facing: float = -1.0
var _phase: int = 1
var _announced := false
var _enraged := false
var _transition_left := 0.0
var _downed_left := 0.0
var _hover_t := 0.0
var _anchor := Vector2.ZERO
var _floor_y := 0.0
var _dive_count := 0
var _push_count := 0
var _blade_volleys := 0
var _updraft_count := 0
var _yank_count := 0
var _transient: Array[Node] = []
var _boss_kit: BossKit
var _boss_director: BossDirector
var _shell: Node2D
var _glow: Sprite2D

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------
func _enemy_ready() -> void:
	_mobile = false                        # 飞行：不受重力、不走 move_and_slide
	hit_material = &"boss"
	health.max_hp = MAX_HP
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	_anchor = global_position
	_floor_y = global_position.y
	global_position.y = _floor_y - HOVER_HEIGHT
	_build_visual()
	_build_boss_framework()
	hitbox.team = &"enemy"
	hitbox.disarm()


func announce() -> void:
	if _announced:
		return
	_announced = true
	GameEvents.boss_intro_started.emit(BOSS_TITLE)
	GameEvents.boss_appeared.emit(BOSS_TITLE, health.current, health.max_hp)
	if _boss_director != null:
		_boss_director.notify_intro()
		_boss_director.start()
	GameEvents.announcement.emit("灰卫让开了风，让开了路，就是不肯落地")
	Fx.attach_ember(visual)
	Sfx.play_at(CombatRules.sfx_key(&"horse_charge"), global_position, 0.1, -8.0)


func is_announced() -> bool:
	return _announced


func is_enraged() -> bool:
	return _enraged


func state() -> State:
	return _state


func phase() -> int:
	return _phase


func hover_y() -> float:
	return _floor_y - HOVER_HEIGHT


func is_down() -> bool:
	return _downed_left > 0.0


func downed_left() -> float:
	return _downed_left


## 飞行 Boss：level_sanity 不该给「脚下没有平台」报警（悬停高度由 HOVER_HEIGHT 定）。
func is_airborne() -> bool:
	return true


func dive_count() -> int:
	return _dive_count


func push_count() -> int:
	return _push_count


func blade_volleys() -> int:
	return _blade_volleys


func updraft_count() -> int:
	return _updraft_count


func yank_count() -> int:
	return _yank_count


func _on_hp_changed(current: int, maximum: int) -> void:
	announce()
	GameEvents.boss_hp_changed.emit(current, maximum)
	_sync_boss_framework(current, maximum)


# ---------------------------------------------------------------------------
# 框架接线
# ---------------------------------------------------------------------------
func boss_kit() -> BossKit:
	if _boss_kit == null:
		_boss_kit = BossKit.new(_boss_kit_config())
	return _boss_kit


func boss_director() -> BossDirector:
	return _boss_director


func boss_arena_bounds() -> Vector2:
	return Vector2(arena_left, arena_right)


func _build_boss_framework() -> void:
	if _boss_kit == null:
		_boss_kit = BossKit.new(_boss_kit_config())
	if _boss_director == null:
		_boss_director = BossDirector.attach(self, _boss_kit, true)
	if _boss_director != null:
		_boss_director.attack_requested.connect(_on_attack_requested)
		_boss_director.phase_entered.connect(_on_phase_entered)
		_boss_director.set_hp(health.current, health.max_hp)


func _sync_boss_framework(current: int, maximum: int) -> void:
	if _boss_director == null:
		return
	if current <= 0:
		_boss_director.notify_death()
	else:
		_boss_director.set_hp(current, maximum)


func _on_phase_entered(next_phase: int) -> void:
	if next_phase <= _phase:
		return
	_phase = next_phase
	if next_phase == 2:
		_enraged = true
		_transition_left = PHASE_TRANSITION_TIME
		health.invincible = true
		_interrupt_attack()
		Juice.boss_phase_beat(global_position + Vector2(0.0, -20.0), Color(1.0, 0.7, 0.4))
		Fx.attach_heat_lick(visual)
		if _shell != null and _shell.has_method("set_hot"):
			_shell.call("set_hot", true)
		GameEvents.announcement.emit("风变热了。他还站在那里。")
		GameEvents.boss_phase_changed.emit(BOSS_TITLE, next_phase)


func _tick_transition(delta: float) -> bool:
	if _transition_left <= 0.0:
		return false
	_transition_left = maxf(0.0, _transition_left - delta)
	_tick_hover(delta)
	if _transition_left <= 0.0:
		health.invincible = false
	return true


# ---------------------------------------------------------------------------
# 攻击调度
# ---------------------------------------------------------------------------
func _on_attack_requested(id: StringName) -> void:
	if _dead or _state != State.IDLE or _transition_left > 0.0 or is_down():
		return
	_begin_attack(id)


func _begin_attack(id: StringName) -> void:
	match id:
		&"dive":
			_begin_dive()
		&"wind_push":
			_begin_push()
		&"feather_blades":
			_begin_blades()
		&"updraft":
			_begin_updraft()
		_:
			return


func _set_attack(id: StringName, step: AttackStep, time: float) -> void:
	_attack = id
	_state = State.ATTACK
	_step = step
	_timer = time
	if _boss_director != null:
		_boss_director.last_attack_id = id


func _begin_dive() -> void:
	_set_attack(&"dive", AttackStep.WINDUP, DIVE_WINDUP)
	_face_player()
	begin_telegraph(&"emberwind_herald", DIVE_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.LANE,
			Vector2(_facing * 30.0, _floor_y - HOVER_HEIGHT + 8.0),
			DIVE_WINDUP, Color(1.0, 0.7, 0.35, 0.95),
			{"length": DIVE_LANE, "facing": _facing})
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_swing"), global_position, 0.1, -8.0)


func _begin_push() -> void:
	_set_attack(&"wind_push", AttackStep.WINDUP, PUSH_WINDUP)
	_face_player()
	begin_telegraph(&"emberwind_herald", PUSH_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
			Vector2(_facing * PUSH_SIZE.x * 0.5, _floor_y - 70.0),
			PUSH_WINDUP, Color(0.55, 0.9, 1.0, 0.9),
			{"rect": Rect2(-PUSH_SIZE * 0.5, PUSH_SIZE)})
	Sfx.play_at(CombatRules.sfx_key(&"dash"), global_position, 0.1, -8.0)


func _begin_blades() -> void:
	_set_attack(&"feather_blades", AttackStep.WINDUP, BLADE_WINDUP)
	_face_player()
	begin_telegraph(&"emberwind_herald", BLADE_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.RING, Vector2(0.0, 0.0), BLADE_WINDUP,
			Color(1.0, 0.85, 0.5, 0.95), {"radius_from": 18.0, "radius_to": 54.0})
	Sfx.play_at(CombatRules.sfx_key(&"spit_charge"), global_position, 0.1, -8.0)


func _begin_updraft() -> void:
	_set_attack(&"updraft", AttackStep.WINDUP, UPDRAFT_WINDUP)
	var player := _player()
	var at_x := global_position.x if player == null else player.global_position.x
	set_meta("updraft_x", _clamp_x(at_x))
	begin_telegraph(&"emberwind_herald", UPDRAFT_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
			Vector2(float(get_meta("updraft_x")) - global_position.x, _floor_y - 80.0),
			UPDRAFT_WINDUP, Color(0.65, 0.95, 0.85, 0.9),
			{"rect": Rect2(-Vector2(UPDRAFT_WIDTH, UPDRAFT_HEIGHT) * 0.5,
					Vector2(UPDRAFT_WIDTH, UPDRAFT_HEIGHT))})
	Sfx.play_at(CombatRules.sfx_key(&"dash"), global_position, 0.1, -10.0)


func _tick_attack(delta: float) -> void:
	_timer -= delta
	var active := 0.0
	var recovery := 0.0
	match _attack:
		&"dive":
			active = DIVE_ACTIVE
			recovery = DIVE_RECOVERY
		&"wind_push":
			active = PUSH_ACTIVE
			recovery = PUSH_RECOVERY
		&"feather_blades":
			active = BLADE_ACTIVE
			recovery = BLADE_RECOVERY
		&"updraft":
			active = UPDRAFT_ACTIVE
			recovery = UPDRAFT_RECOVERY
		_:
			_finish_attack()
			return
	if _step == AttackStep.WINDUP:
		_tick_hover(delta)
		if _timer > 0.0:
			return
		_step = AttackStep.ACTIVE
		_timer = active
		_do_active()
	elif _step == AttackStep.ACTIVE:
		if _attack == &"dive":
			_tick_dive(delta)
		elif _attack == &"wind_push":
			_tick_hover(delta)
		else:
			_tick_hover(delta)
		if _timer > 0.0:
			return
		_step = AttackStep.RECOVERY
		_timer = recovery
		hitbox.disarm()
		show_opening(recovery)
	elif _step == AttackStep.RECOVERY:
		_tick_hover(delta)
		if _timer <= 0.0:
			_finish_attack()


func _do_active() -> void:
	match _attack:
		&"dive":
			_do_dive()
		&"wind_push":
			_do_push()
		&"feather_blades":
			_do_blades()
		&"updraft":
			_do_updraft()


# --- 俯冲 -------------------------------------------------------------------
func _do_dive() -> void:
	_dive_count += 1
	hitbox.disarm()
	hitbox.collision_layer = 8
	hitbox.collision_mask = 32
	hitbox.damage = 2
	hitbox.blow = &"heavy"
	hitbox.position = Vector2(0.0, 8.0)
	hitbox.arm(Vector2(_facing * 140.0, -40.0))
	Juice.shake(2.0, 120)
	Sfx.play_at(CombatRules.sfx_key(&"horse_charge"), global_position, 0.08, -4.0)
	Fx.burst(&"ring", global_position)


func _tick_dive(delta: float) -> void:
	var speed := DIVE_SPEED_P2 if _enraged else DIVE_SPEED
	global_position.x += _facing * speed * delta
	var target_y := _floor_y - DIVE_LOW
	global_position.y = move_toward(global_position.y, target_y, delta * 900.0)
	global_position.x = _clamp_x(global_position.x)
	if _timer <= 0.0:
		hitbox.disarm()


# --- 风推 -------------------------------------------------------------------
func _do_push() -> void:
	_push_count += 1
	var zone := WindZone.new()
	zone.name = "WindZone"
	zone.size = PUSH_SIZE
	zone.flow = _facing * (PUSH_FLOW_P2 if _enraged else PUSH_FLOW)
	zone.life = PUSH_ACTIVE + 0.05
	zone.position = Vector2(_facing * PUSH_SIZE.x * 0.5, _floor_y - zone.size.y * 0.5 - 10.0)
	add_child(zone)
	_transient.append(zone)
	Sfx.play_at(CombatRules.sfx_key(&"dash"), global_position, 0.1, -6.0)
	Juice.shake(1.5, 100)


# --- 羽刃弹幕 ---------------------------------------------------------------
func _do_blades() -> void:
	_blade_volleys += 1
	var player := _player()
	var aim := Vector2(_facing, 0.0)
	if player != null:
		aim = (player.global_position + Vector2(0.0, -18.0) - global_position).normalized()
	var count := BLADE_COUNT + (1 if _enraged else 0)
	for i in count:
		var spread := (float(i) - (count - 1) * 0.5) * BLADE_SPREAD
		var blade := _spawn_projectile(global_position + Vector2(0.0, -6.0), aim.rotated(spread),
				BLADE_SPEED, 1)
		if blade != null:
			blade.name = "FeatherBlade%d" % i
	Fx.burst(&"sparks", global_position)
	Sfx.play_at(CombatRules.sfx_key(&"spit"), global_position, 0.1, -8.0)


# --- 上升气流区 -------------------------------------------------------------
func _do_updraft() -> void:
	_updraft_count += 1
	var zone := UpdraftZone.new()
	zone.name = "UpdraftZone"
	zone.size = Vector2(UPDRAFT_WIDTH, UPDRAFT_HEIGHT)
	zone.lift = UPDRAFT_LIFT_P2 if _enraged else UPDRAFT_LIFT
	zone.life = UPDRAFT_LIFE if _enraged else UPDRAFT_LIFE * 0.75
	zone.position = Vector2(float(get_meta("updraft_x")) - global_position.x,
			_floor_y - zone.size.y * 0.5)
	add_child(zone)
	_transient.append(zone)
	Sfx.play_at(CombatRules.sfx_key(&"dash"), global_position, 0.12, -6.0)


# ---------------------------------------------------------------------------
# 钩锁拉下处决
# ---------------------------------------------------------------------------
## 飞行 Boss 可以被钩锁拽下来（重甲 / 普通首领不吃，这里放行）。
func is_yankable() -> bool:
	return not _dead and _state != State.DOWNED and _transition_left <= 0.0


## 钩锁命中：把灰卫从空中拽到骑士面前，硬直 + 破绽（唯一稳定的输出窗口）。
func yank_to(point: Vector2, _duration: float = 0.22) -> bool:
	if _dead or not is_yankable():
		return false
	_yank_count += 1
	_interrupt_attack()
	_state = State.DOWNED
	_downed_left = DOWN_TIME
	_timer = DOWN_TIME
	hitbox.disarm()
	global_position = Vector2(_clamp_x(point.x + signf(global_position.x - point.x) * 26.0),
			_floor_y)
	open_riposte(DOWN_RIPOSTE)
	Juice.shake(4.0, 240)
	Fx.dust_puff(global_position, -PI * 0.5)
	Sfx.play_at(CombatRules.sfx_key(&"land_heavy"), global_position, 0.08, -4.0)
	GameEvents.announcement.emit("铁链把他从风口上拽了下来")
	return true


func _tick_downed(delta: float) -> void:
	_downed_left = maxf(0.0, _downed_left - delta)
	global_position.y = move_toward(global_position.y, _floor_y, delta * 600.0)
	if _downed_left <= 0.0:
		_state = State.IDLE
		hide_opening()
		_anchor.x = global_position.x


# ---------------------------------------------------------------------------
# 悬停 / 状态机
# ---------------------------------------------------------------------------
func _tick_hover(delta: float) -> void:
	_hover_t += delta
	var target_y := _floor_y - HOVER_HEIGHT + sin(_hover_t * 1.6) * HOVER_BOB
	global_position.y = move_toward(global_position.y, target_y, delta * HOVER_SPEED)
	# 慢慢飘向玩家（保持距离），但不出竞技场。
	var player := _player()
	var target_x := _anchor.x
	if player != null and _announced:
		var side := signf(global_position.x - player.global_position.x)
		if side == 0.0:
			side = -1.0
		target_x = _clamp_x(player.global_position.x + side * 130.0)
	global_position.x = move_toward(global_position.x, target_x, delta * HOVER_DRIFT)
	global_position.x = _clamp_x(global_position.x)


func _tick_state(delta: float) -> void:
	if _dead:
		return
	if _tick_transition(delta):
		return
	match _state:
		State.IDLE:
			_tick_hover(delta)
			if not _announced:
				var player := _player()
				if player != null and global_position.distance_to(player.global_position) <= AGGRO_RANGE:
					announce()
			else:
				_face_player()
		State.ATTACK:
			_tick_attack(delta)
		State.DOWNED:
			_tick_downed(delta)
	_update_visuals(delta)


func _finish_attack() -> void:
	_state = State.IDLE
	_attack = &""
	hitbox.disarm()
	hide_opening()
	if _boss_director != null:
		_boss_director.notify_attack_finished()


func _interrupt_attack() -> void:
	if _state == State.ATTACK:
		_state = State.IDLE
		_attack = &""
		hitbox.disarm()
		hide_opening()
		if _boss_director != null:
			_boss_director.notify_attack_finished()


# ---------------------------------------------------------------------------
# 视觉（程序化像素：披灰的翼 + 羽刃轮廓）
# ---------------------------------------------------------------------------
func _build_visual() -> void:
	if visual == null:
		return
	for child in visual.get_children():
		if child is ColorRect:
			child.visible = false
	_glow = Sprite2D.new()
	_glow.name = "HeraldGlow"
	const GLOW := "res://assets/env/glow_soft.png"
	if ResourceLoader.exists(GLOW):
		_glow.texture = load(GLOW) as Texture2D
	_glow.position = Vector2(0.0, -16.0)
	_glow.scale = Vector2(2.4, 2.0)
	_glow.z_index = -1
	_glow.material = Fx.additive_mat()
	_glow.modulate = Color(0.7, 0.85, 1.0, 0.16)
	visual.add_child(_glow)
	_shell = HeraldShell.new()
	_shell.name = "HeraldShell"
	visual.add_child(_shell)
	_flash_target = _shell
	_anim = null


func _update_visuals(delta: float) -> void:
	if _shell != null and _shell.has_method("animate"):
		_shell.call("animate", delta, 1.0 if _facing >= 0.0 else -1.0, _enraged, is_down())
	if _glow != null:
		var pulse := 1.0 + 0.1 * sin(Time.get_ticks_msec() / 1000.0 * 2.6)
		_glow.modulate.a = (0.26 if _enraged else 0.14) * pulse


## 灰卫：灰披风、翼上的羽刃、头盔里一点炉火。翼按正弦扇动。
class HeraldShell extends Node2D:
	var _t := 0.0
	var _facing := 1.0
	var _hot := false
	var _down := false

	func set_hot(hot: bool) -> void:
		_hot = hot
		queue_redraw()

	func animate(delta: float, facing: float, hot: bool, down: bool) -> void:
		_t += delta
		_facing = facing
		_hot = hot
		_down = down
		queue_redraw()

	func _draw() -> void:
		var flap := sin(_t * 5.6) * 0.5 + 0.5
		var base := Color(0.42, 0.44, 0.48)
		var ash := Color(0.30, 0.31, 0.35)
		var ember := Color(1.0, 0.55, 0.2) if _hot else Color(0.9, 0.55, 0.25)
		# 披风 / 躯干（向下收窄的斗篷）。
		var cloak := PackedVector2Array([
			Vector2(-9.0, -30.0), Vector2(9.0, -30.0),
			Vector2(13.0, -6.0), Vector2(6.0, 8.0), Vector2(-6.0, 8.0), Vector2(-13.0, -6.0),
		])
		draw_colored_polygon(cloak, ash)
		draw_rect(Rect2(-3.0, -26.0, 6.0, 20.0), base)
		# 头盔：窄长的灰盔，面缝一点火。
		draw_rect(Rect2(-6.0, -46.0, 12.0, 14.0), base)
		draw_rect(Rect2(-8.0, -44.0, 16.0, 3.0), Color(0.24, 0.25, 0.28))
		draw_rect(Rect2(-2.0, -40.0, 4.0, 2.0), ember)
		# 翅膀：三层羽刃，扇动幅度随 flap。
		for side in [-1.0, 1.0]:
			var spread := 12.0 + 16.0 * flap
			var wing := PackedVector2Array([
				Vector2(side * 6.0, -26.0),
				Vector2(side * spread, -40.0 - 6.0 * flap),
				Vector2(side * (spread + 10.0), -28.0 - 10.0 * flap),
				Vector2(side * (spread + 4.0), -18.0 - 4.0 * flap),
				Vector2(side * 7.0, -20.0),
			])
			draw_colored_polygon(wing, Color(0.36, 0.38, 0.42))
			draw_line(wing[1], wing[4], Color(0.5, 0.52, 0.55), 1.0)
			draw_line(wing[2], wing[3], Color(0.5, 0.52, 0.55), 1.0)
		# 羽刃：悬在身侧的 3 片薄刃（二阶段刃口透热）。
		for i in 3:
			var bx := -10.0 + float(i) * 10.0
			var by := -12.0 + float(i % 2) * 4.0
			draw_line(Vector2(bx, by), Vector2(bx + 2.0, by + 12.0),
					Color(0.6, 0.62, 0.66), 1.0)
		# 坠落（被钩下来）时翅膀收拢成灰堆：画几条灰线。
		if _down:
			draw_line(Vector2(-16.0, 6.0), Vector2(16.0, 6.0), Color(0.35, 0.36, 0.4), 2.0)


## 风推区：把站进去的骑士沿 flow 方向推（真实速度，不改玩家公式）。
class WindZone extends Area2D:
	var size := Vector2(220.0, 180.0)
	var flow := 150.0
	var life := 1.25
	var _bodies: Array[Node2D] = []
	var _t := 0.0

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		add_child(shape)
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

	func _process(delta: float) -> void:
		_t += delta
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		for body in _bodies:
			if is_instance_valid(body) and body is CharacterBody2D:
				(body as CharacterBody2D).velocity.x += flow * delta
		queue_redraw()

	func _on_body_entered(body: Node2D) -> void:
		if body is Player and not _bodies.has(body):
			_bodies.append(body)

	func _on_body_exited(body: Node2D) -> void:
		_bodies.erase(body)

	func _draw() -> void:
		var alpha := clampf(life, 0.0, 1.0) * 0.5
		draw_rect(Rect2(-size * 0.5, size), Color(0.6, 0.9, 1.0, 0.05 * alpha), true)
		for i in 6:
			var y := -size.y * 0.5 + size.y * (float(i) + 0.5) / 6.0
			var x := -size.x * 0.5 + fmod(_t * 380.0 + float(i) * 71.0, size.x)
			draw_line(Vector2(x, y), Vector2(x + 26.0, y), Color(0.75, 0.95, 1.0, 0.35 * alpha), 1.0)


## 上升气流区：站进去会被持续托起（跳跃时更明显）。
class UpdraftZone extends Area2D:
	var size := Vector2(96.0, 150.0)
	var lift := 420.0
	var life := 3.4
	var _bodies: Array[Node2D] = []
	var _t := 0.0

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		add_child(shape)
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

	func _process(delta: float) -> void:
		_t += delta
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		for body in _bodies:
			if is_instance_valid(body) and body is CharacterBody2D:
				(body as CharacterBody2D).velocity.y -= lift * delta
		queue_redraw()

	func _on_body_entered(body: Node2D) -> void:
		if body is Player and not _bodies.has(body):
			_bodies.append(body)

	func _on_body_exited(body: Node2D) -> void:
		_bodies.erase(body)

	func _draw() -> void:
		var alpha := clampf(life / 1.5, 0.0, 1.0)
		draw_rect(Rect2(-size * 0.5, size), Color(0.6, 1.0, 0.85, 0.05 * alpha), true)
		for i in 4:
			var x := -size.x * 0.5 + size.x * (float(i) + 0.5) / 4.0
			var y := fmod(_t * 220.0 + float(i) * 41.0, size.y) - size.y * 0.5
			draw_line(Vector2(x, y), Vector2(x, y - 20.0), Color(0.7, 1.0, 0.9, 0.35 * alpha), 1.0)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------
func _player() -> Player:
	var p := knight()
	if p == null or p.health.current <= 0:
		return null
	return p


func _face_player() -> void:
	var p := _player()
	if p == null:
		return
	var dx := p.global_position.x - global_position.x
	if absf(dx) > 6.0:
		_facing = signf(dx)


func _clamp_x(x: float) -> float:
	if not is_finite(arena_left) or not is_finite(arena_right):
		return x
	return clampf(x, arena_left + 24.0, arena_right - 24.0)


func _effects_host() -> Node:
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	return host


func _spawn_projectile(origin: Vector2, dir: Vector2, speed: float, dmg: int) -> Projectile:
	const PATH := "res://scenes/combat/Projectile.tscn"
	if not ResourceLoader.exists(PATH):
		return null
	var scene := load(PATH) as PackedScene
	if scene == null:
		return null
	var host := _effects_host()
	var bolt := scene.instantiate() as Projectile
	host.add_child(bolt)
	bolt.global_position = origin
	bolt.setup(origin, dir.normalized(), speed, &"enemy", self)
	bolt.damage = dmg
	_transient.append(bolt)
	return bolt


func _on_died() -> void:
	_interrupt_attack()
	if _boss_director != null:
		_boss_director.notify_death()
	slain.emit()
	Juice.boss_death_beat(global_position + Vector2(0.0, -16.0))
	GameEvents.boss_defeated.emit()
	SaveData.mark_flag(FLAG_DEAD)
	SaveData.persist_story()
	_cleanup_transient()
	_death_burst([] as Array[Texture2D], 12.0, _facing > 0.0, 0.0, "最后一片灰落在风口上")


func _cleanup_transient() -> void:
	for node in _transient:
		if is_instance_valid(node):
			node.queue_free()
	_transient.clear()


# ---------------------------------------------------------------------------
# 攻击表（Kit 数据；数值与实现同源）
# ---------------------------------------------------------------------------
func _boss_kit_config() -> Dictionary:
	return {
		"id": &"emberwind_herald",
		"title": BOSS_TITLE,
		"subtitle": BOSS_SUBTITLE,
		"max_phases": 2,
		"phase_thresholds": [1.0, 0.5],
		"min_interval": 0.85,
		"attacks": [
			{
				"id": &"dive", "phase": 1, "weight": 2.0,
				"cooldown": 2.6, "cooldown_by_phase": [2.6, 1.8],
				"min_range": 0.0, "max_range": 0.0,
				"windup": DIVE_WINDUP, "active": DIVE_ACTIVE, "recovery": DIVE_RECOVERY,
				"telegraph": &"emberwind_herald",
				"hitbox": {"offset": Vector2(DIVE_LANE * 0.5, DIVE_LOW - HOVER_HEIGHT),
						"size": Vector2(DIVE_LANE, DIVE_HITBOX.y)},
			},
			{
				"id": &"wind_push", "phase": 1, "weight": 1.2,
				"cooldown": 3.4, "cooldown_by_phase": [3.4, 2.5],
				"min_range": 0.0, "max_range": 0.0,
				"windup": PUSH_WINDUP, "active": PUSH_ACTIVE, "recovery": PUSH_RECOVERY,
				"telegraph": &"emberwind_herald", "damaging": false, "hitbox": {},
			},
			{
				"id": &"feather_blades", "phase": 1, "weight": 1.6,
				"cooldown": 2.8, "cooldown_by_phase": [2.8, 2.0],
				"min_range": 60.0, "max_range": 0.0,
				"windup": BLADE_WINDUP, "active": BLADE_ACTIVE, "recovery": BLADE_RECOVERY,
				"telegraph": &"emberwind_herald", "hitbox": {},
			},
			{
				"id": &"updraft", "phase": 2, "weight": 1.4,
				"cooldown": 3.0, "cooldown_by_phase": [3.0, 2.2],
				"min_range": 0.0, "max_range": 0.0,
				"windup": UPDRAFT_WINDUP, "active": UPDRAFT_ACTIVE, "recovery": UPDRAFT_RECOVERY,
				"telegraph": &"emberwind_herald", "damaging": false, "hitbox": {},
			},
		],
		"arena_events": [
			{"id": &"herald_rockfall", "at_phase": 1, "once": true},
			{"id": &"herald_furnace", "at_phase": 2, "once": true},
			{"id": &"arena_dim", "at_phase": 0, "once": true},
		],
	}
