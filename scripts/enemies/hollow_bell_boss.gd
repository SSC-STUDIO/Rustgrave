extends EnemyBase
## 空钟（HollowBell）· 沉钟之灵 —— 第贰章「沉钟地窟」的 Boss。
##
## 一座悬在地窟里的巨钟。它不追人：用摆锤横扫、用钟索把骑士拽向钟心、把落钟
## 砸在骑士脚下、用钟鸣波沿地面扩散。**钟锤（弱点头）是它唯一的软处**：打中
## 垂在钟口的钟锤会打断当前招式并打开破绽（下一刀翻倍），二阶段的钟面裂纹里
## 透出炉火光。
##
## 框架（docs/integration-contracts.md §4.1）：BossKit + 驾驶模式 BossDirector
## （attach(self, kit, true) + start()）。导演层选招后发 attack_requested(id)，
## 本脚本执行招式，收招调 notify_attack_finished()；HP 变化 set_hp()，死亡
## notify_death()。竞技场由 ChapterLayout.boss() 装配，本脚本只读 arena_left/right。
##
## 可读性：每招前摇 >= 0.35s，统一 begin_telegraph + CombatMarker；同一时刻只有
## 一条预警（导演层串行出招）。全部演出不锁输入，Director 层可随时跳过。

signal slain

enum State { IDLE, ATTACK, STAGGER }
enum AttackStep { WINDUP, ACTIVE, RECOVERY }

const BOSS_TITLE := "空钟 · 沉钟之灵"
const BOSS_SUBTITLE := "沉钟之灵"
const MAX_HP := 18
const AGGRO_RANGE := 320.0
const FLAG_DEAD := "hollow_bell_dead"

## 招式数值（前摇 / 判定 / 后摇；导演层 Kit 与实现共用同一组常量）。
const PENDULUM_WINDUP := 0.60
const PENDULUM_ACTIVE := 0.34
const PENDULUM_RECOVERY := 0.70
const PENDULUM_SWEEP := 260.0
const PENDULUM_BOX := Vector2(60.0, 44.0)
const PENDULUM_Y := Vector2(0.0, -18.0)

const PULL_WINDUP := 0.55
const PULL_ACTIVE := 0.55
const PULL_RECOVERY := 0.80
const PULL_ACCEL := 1500.0
## 玩家跳起（速度向上）或出钩时甩开拉拽：这就是「跳/钩反制」。
const PULL_JUMP_ESCAPE := -60.0
const PULL_RANGE := 420.0

const DROP_WINDUP := 0.70
const DROP_ACTIVE := 0.25
const DROP_RECOVERY := 0.60
const DROP_ZONE := Vector2(72.0, 56.0)

const WAVE_WINDUP := 0.50
const WAVE_ACTIVE := 0.20
const WAVE_RECOVERY := 0.70
const WAVE_SPEED := 150.0
const WAVE_DAMAGE := 1

## 相变 1.2s 无敌演出（契约 §4.1）。
const PHASE_TRANSITION_TIME := 1.2
## 打中钟锤后的破绽 / 硬直。
const WEAK_STAGGER := 1.6
const WEAK_RIPOSTE := 2.4

## 视觉参数。
const BELL_TOP := -318.0
const BELL_BODY_TOP := -196.0
const BELL_BODY_BOTTOM := -78.0
const BELL_WIDTH := 96.0
const HAMMER_HOME := Vector2(0.0, -46.0)

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
var _weak_marks := 0
var _parried_waves := 0
var _fling: Node2D = null
var _drop_box: Hitbox = null
var _swing := 0.0
var _swing_target := 0.0
var _pull_left := 0.0
var _pulling := false
var _pull_target: Player = null
var _transient: Array[Node] = []
var _boss_kit: BossKit
var _boss_director: BossDirector
var _shell: Node2D
var _glow: Sprite2D
var _hammer: Node2D

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox
@onready var weak_hurtbox: Hurtbox = $WeakHurtbox


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------
func _enemy_ready() -> void:
	_mobile = false                       # 悬空的钟不走路、不受重力
	hit_material = &"boss"
	health.max_hp = MAX_HP
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	_build_visual()
	_build_boss_framework()
	if weak_hurtbox != null:
		weak_hurtbox.hurt.connect(_on_weak_hurt)
	GameEvents.parried.connect(_on_parried)
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
	GameEvents.announcement.emit("钟里有东西在数人")
	Fx.attach_ember(visual)
	Sfx.play_at(CombatRules.sfx_key(&"bell_toll"), global_position, 0.05, -8.0)


func is_announced() -> bool:
	return _announced


## 悬在地窟里的钟：level_sanity 不该给「脚下没有平台」报警。
func is_airborne() -> bool:
	return true


func phase() -> int:
	return _phase


func is_enraged() -> bool:
	return _enraged


func state() -> State:
	return _state


func attack_name() -> StringName:
	return _attack


func weak_marks() -> int:
	return _weak_marks


func parried_waves() -> int:
	return _parried_waves


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


## 竞技场边界（世界 x）：BossArena / boss_fixture 读取。
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


func _on_phase_entered(phase: int) -> void:
	if phase <= _phase:
		return
	_phase = phase
	if phase == 2:
		_enraged = true
		_transition_left = PHASE_TRANSITION_TIME
		health.invincible = true
		_interrupt_attack()
		Juice.boss_phase_beat(global_position + Vector2(0.0, -120.0), Color(1.0, 0.55, 0.3))
		Fx.attach_heat_lick(visual)
		if _shell != null and _shell.has_method("set_hot"):
			_shell.call("set_hot", true)
		GameEvents.announcement.emit("钟面的裂缝里烧出了炉火")
		GameEvents.boss_phase_changed.emit(BOSS_TITLE, phase)


## 相变无敌窗口结束（_tick_state 里推进，headless 测试也能手动 tick）。
func _tick_transition(delta: float) -> bool:
	if _transition_left <= 0.0:
		return false
	_transition_left = maxf(0.0, _transition_left - delta)
	if _transition_left <= 0.0:
		health.invincible = false
	return true


# ---------------------------------------------------------------------------
# 攻击调度
# ---------------------------------------------------------------------------
func _on_attack_requested(id: StringName) -> void:
	if _dead or _state != State.IDLE:
		return
	if _transition_left > 0.0:
		return
	_begin_attack(id)


## 开始一招（测试也可直接调用）。未知 id 安全忽略。
func _begin_attack(id: StringName) -> void:
	match id:
		&"pendulum":
			_begin_pendulum()
		&"chain_pull":
			_begin_chain_pull()
		&"bell_drop":
			_begin_bell_drop()
		&"toll_wave":
			_begin_toll_wave()
		_:
			return


func _begin_pendulum() -> void:
	_set_attack(&"pendulum", State.ATTACK, AttackStep.WINDUP, PENDULUM_WINDUP)
	var player := _player()
	_facing = signf(player.global_position.x - global_position.x) if player != null else _facing
	if _facing == 0.0:
		_facing = 1.0
	begin_telegraph(&"hollow_bell", PENDULUM_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.LANE, Vector2(_facing * 26.0, PENDULUM_Y.y),
			PENDULUM_WINDUP, Color(1.0, 0.62, 0.3, 0.95),
			{"length": PENDULUM_SWEEP, "facing": _facing})
	_swing_target = -_facing
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_swing"), global_position, 0.06, -8.0)


func _begin_chain_pull() -> void:
	_set_attack(&"chain_pull", State.ATTACK, AttackStep.WINDUP, PULL_WINDUP)
	var player := _player()
	_facing = signf(player.global_position.x - global_position.x) if player != null else _facing
	begin_telegraph(&"hollow_bell", PULL_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.RING, Vector2(0.0, -60.0), PULL_WINDUP,
			Color(0.55, 0.85, 0.95, 0.95), {"radius_from": 30.0, "radius_to": 8.0})
	Sfx.play_at(CombatRules.sfx_key(&"dash"), global_position, 0.08, -10.0)


func _begin_bell_drop() -> void:
	_set_attack(&"bell_drop", State.ATTACK, AttackStep.WINDUP, DROP_WINDUP)
	var player := _player()
	var drop_x := global_position.x
	if player != null:
		drop_x = player.global_position.x
	drop_x = _clamp_x(drop_x)
	_facing = signf(drop_x - global_position.x) if absf(drop_x - global_position.x) > 4.0 else _facing
	begin_telegraph(&"hollow_bell", DROP_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.ZONE, Vector2(drop_x - global_position.x, -DROP_ZONE.y * 0.5),
			DROP_WINDUP, Color(1.0, 0.45, 0.25, 0.95),
			{"rect": Rect2(-DROP_ZONE * 0.5, DROP_ZONE)})
	var data := {"x": drop_x}
	set_meta("drop_x", drop_x)
	Sfx.play_at(CombatRules.sfx_key(&"bell_toll"), Vector2(drop_x, global_position.y - 40.0), 0.04, -14.0)


func _begin_toll_wave() -> void:
	_set_attack(&"toll_wave", State.ATTACK, AttackStep.WINDUP, WAVE_WINDUP)
	var player := _player()
	if player != null:
		_facing = signf(player.global_position.x - global_position.x)
	begin_telegraph(&"hollow_bell", WAVE_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.RING, Vector2(0.0, -40.0), WAVE_WINDUP,
			Color(1.0, 0.8, 0.45, 0.95), {"radius_from": 18.0, "radius_to": 64.0})
	Sfx.play_at(CombatRules.sfx_key(&"bell_toll"), global_position, 0.03, -10.0)


func _set_attack(id: StringName, p_state: State, step: AttackStep, windup: float) -> void:
	_attack = id
	_state = p_state
	_step = step
	_timer = windup
	if _boss_director != null:
		_boss_director.last_attack_id = id


## 当前招式推进；返回 true 表示本帧还在出招。
func _tick_attack(delta: float) -> void:
	_timer -= delta
	match _attack:
		&"pendulum":
			_tick_pendulum(delta)
		&"chain_pull":
			_tick_chain_pull(delta)
		&"bell_drop":
			_tick_bell_drop(delta)
		&"toll_wave":
			_tick_toll_wave(delta)
		_:
			_finish_attack()


# --- 摆锤 -------------------------------------------------------------------
func _tick_pendulum(delta: float) -> void:
	if _step == AttackStep.WINDUP and _timer <= 0.0:
		_step = AttackStep.ACTIVE
		_timer = PENDULUM_ACTIVE
		_swing_target = _facing
		_spawn_pendulum_box()
	elif _step == AttackStep.ACTIVE:
		_swing = lerpf(_swing, _swing_target, minf(1.0, delta * 18.0))
		if _fling != null and is_instance_valid(_fling):
			var box := _fling as Hitbox
			box.position.x += _facing * PENDULUM_SWEEP / PENDULUM_ACTIVE * delta
		if _timer <= 0.0:
			_step = AttackStep.RECOVERY
			_timer = PENDULUM_RECOVERY
			_clear_fling()
			_swing_target = 0.0
			# 收锤是破绽：头顶金箭头亮满后摇。
			show_opening(PENDULUM_RECOVERY)
	elif _step == AttackStep.RECOVERY and _timer <= 0.0:
		_finish_attack()


func _spawn_pendulum_box() -> void:
	_clear_fling()
	var box := Hitbox.new()
	box.damage = 2
	box.team = &"enemy"
	box.blow = &"heavy"
	box.knockback = Vector2(_facing * 130.0, -60.0)
	box.monitoring = true
	box.collision_layer = 8
	box.collision_mask = 32
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = PENDULUM_BOX
	shape.shape = rect
	box.add_child(shape)
	var host := _effects_host()
	host.add_child(box)
	box.global_position = global_position + Vector2(_facing * 40.0, PENDULUM_Y.y)
	box.arm(Vector2(_facing * 130.0, -60.0))
	_fling = box
	_transient.append(box)
	Juice.shake(2.0, 90)
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_slam"), box.global_position, 0.05, -6.0)


func _clear_fling() -> void:
	if _fling != null and is_instance_valid(_fling):
		var box := _fling as Hitbox
		box.disarm()
		box.queue_free()
	_fling = null


# --- 钟索拉拽 ---------------------------------------------------------------
func _tick_chain_pull(delta: float) -> void:
	var player := _player()
	if _step == AttackStep.WINDUP and _timer <= 0.0:
		_step = AttackStep.ACTIVE
		_timer = PULL_ACTIVE
		_pulling = true
		_pull_target = player
		Sfx.play_at(CombatRules.sfx_key(&"boss_axe_swing"), global_position, 0.08, -8.0)
	elif _step == AttackStep.ACTIVE:
		if not _advance_pull(delta):
			# 被跳/钩反制：拉拽立即结束。
			_pulling = false
			_step = AttackStep.RECOVERY
			_timer = 0.25
		elif _timer <= 0.0:
			_pulling = false
			_pull_target = null
			_step = AttackStep.RECOVERY
			_timer = PULL_RECOVERY
			show_opening(PULL_RECOVERY)
	elif _step == AttackStep.RECOVERY and _timer <= 0.0:
		_finish_attack()


## 把骑士往钟心拉。返回 false = 玩家用跳跃或钩锁甩开了拉拽。
func _advance_pull(delta: float) -> bool:
	var player := _pull_target
	if player == null or not is_instance_valid(player) or player.health.current <= 0:
		return false
	if player.velocity.y <= PULL_JUMP_ESCAPE:
		GameEvents.announcement.emit("钟索被跳跃甩开")
		return false
	var hook := player.get_node_or_null("HookshotTether")
	if hook != null and hook.has_method("is_active") and bool(hook.call("is_active")):
		GameEvents.announcement.emit("钩锁把钟索扯断了")
		return false
	var dx := global_position.x - player.global_position.x
	if absf(dx) <= 24.0:
		return true
	player.velocity.x += signf(dx) * PULL_ACCEL * delta
	return true


# --- 落钟 -------------------------------------------------------------------
func _tick_bell_drop(delta: float) -> void:
	if _step == AttackStep.WINDUP and _timer <= 0.0:
		_step = AttackStep.ACTIVE
		_timer = DROP_ACTIVE
		_do_bell_drop()
	elif _step == AttackStep.ACTIVE and _timer <= 0.0:
		_step = AttackStep.RECOVERY
		_timer = DROP_RECOVERY
		_clear_drop_box()
		show_opening(DROP_RECOVERY)
	elif _step == AttackStep.RECOVERY and _timer <= 0.0:
		_finish_attack()


func _do_bell_drop() -> void:
	var drop_x: float = float(get_meta("drop_x", global_position.x))
	var box := Hitbox.new()
	box.damage = 2
	box.team = &"enemy"
	box.blow = &"heavy"
	box.knockback = Vector2(0.0, -120.0)
	box.monitoring = true
	box.collision_layer = 8
	box.collision_mask = 32
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = DROP_ZONE
	shape.shape = rect
	box.add_child(shape)
	var host := _effects_host()
	host.add_child(box)
	box.global_position = Vector2(drop_x, global_position.y - DROP_ZONE.y * 0.5)
	box.arm(Vector2(0.0, -120.0))
	_transient.append(box)
	_drop_box = box
	Juice.shake(4.0, 240)
	Fx.dust_puff(Vector2(drop_x, global_position.y), -PI * 0.5)
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_slam"), Vector2(drop_x, global_position.y - 20.0), 0.04, -3.0)


## 落钟判定只活 DROP_ACTIVE 那么久；收判定免得留一根永久火柱。
func _clear_drop_box() -> void:
	if _drop_box != null and is_instance_valid(_drop_box):
		_drop_box.disarm()
		_drop_box.queue_free()
	_drop_box = null


# --- 钟鸣波 -----------------------------------------------------------------
func _tick_toll_wave(delta: float) -> void:
	if _step == AttackStep.WINDUP and _timer <= 0.0:
		_step = AttackStep.ACTIVE
		_timer = WAVE_ACTIVE
		_fire_wave()
	elif _step == AttackStep.ACTIVE and _timer <= 0.0:
		_step = AttackStep.RECOVERY
		_timer = WAVE_RECOVERY
	elif _step == AttackStep.RECOVERY and _timer <= 0.0:
		_finish_attack()


## 沿地面左右各一道可弹反的钟鸣波（Projectile 走现有弹反管线）。
func _fire_wave() -> void:
	const PATH := "res://scenes/combat/Projectile.tscn"
	if not ResourceLoader.exists(PATH):
		return
	var scene := load(PATH) as PackedScene
	if scene == null:
		return
	var host := _effects_host()
	for dir in [-1.0, 1.0]:
		var bolt := scene.instantiate() as Projectile
		host.add_child(bolt)
		bolt.global_position = global_position + Vector2(dir * 30.0, -14.0)
		bolt.setup(bolt.global_position, Vector2(dir, 0.0), WAVE_SPEED, &"enemy", self)
		bolt.damage = WAVE_DAMAGE
		_transient.append(bolt)
	Fx.burst(&"ring", global_position + Vector2(0.0, -24.0))
	Sfx.play_at(CombatRules.sfx_key(&"bell_toll"), global_position, 0.03, -6.0)


## 玩家弹反钟鸣波：空钟短暂破防（破绽 + 硬直）。
func _on_parried(projectile: Node, _by_actor: Node) -> void:
	if _dead:
		return
	if projectile is Projectile and (projectile as Projectile).source == self:
		_parried_waves += 1
		_stagger(WEAK_STAGGER, "钟鸣被弹回来，空钟晃了一下")


# ---------------------------------------------------------------------------
# 钟锤弱点
# ---------------------------------------------------------------------------
func _on_weak_hurt(_amount: int, _attacker: Node) -> void:
	if _dead or _state == State.STAGGER or _transition_left > 0.0:
		return
	_weak_marks += 1
	_stagger(WEAK_STAGGER, "钟锤被劈中，钟声散了")


## 打断当前招 + 破绽窗口（下一刀翻倍）。
func _stagger(duration: float, message: String) -> void:
	_interrupt_attack()
	_state = State.STAGGER
	_timer = duration
	open_riposte(WEAK_RIPOSTE)
	Juice.shake(3.0, 160)
	Fx.hit_sparks(global_position + Vector2(0.0, HAMMER_HOME.y))
	Sfx.play_at(CombatRules.sfx_key(&"hit_heavy"), global_position, 0.08, -6.0)
	if message != "":
		GameEvents.announcement.emit(message)
	_swing_target = 0.6


func _tick_stagger(delta: float) -> void:
	_timer -= delta
	_swing = lerpf(_swing, 0.0, minf(1.0, delta * 6.0))
	if _timer <= 0.0:
		_state = State.IDLE
		hide_opening()


# ---------------------------------------------------------------------------
# 状态机
# ---------------------------------------------------------------------------
func _tick_state(delta: float) -> void:
	if _dead:
		return
	if _tick_transition(delta):
		return
	match _state:
		State.IDLE:
			_swing = lerpf(_swing, 0.0, minf(1.0, delta * 4.0))
			var player := _player()
			if not _announced and player != null \
					and global_position.distance_to(player.global_position) <= AGGRO_RANGE:
				announce()
				return
			if player != null and absf(player.global_position.x - global_position.x) > 6.0:
				_facing = signf(player.global_position.x - global_position.x)
		State.ATTACK:
			_tick_attack(delta)
		State.STAGGER:
			_tick_stagger(delta)
	_update_visuals(delta)


## 打断当前招式并同步框架（死亡 / 相变 / 破防用）。
func _interrupt_attack() -> void:
	if _state == State.ATTACK:
		_clear_fling()
		_clear_drop_box()
		_pulling = false
		_pull_target = null
		hide_opening()
		_state = State.IDLE
		_attack = &""
		if _boss_director != null:
			_boss_director.notify_attack_finished()


func _finish_attack() -> void:
	_state = State.IDLE
	_attack = &""
	_clear_fling()
	_clear_drop_box()
	_pulling = false
	_pull_target = null
	hide_opening()
	if _boss_director != null:
		_boss_director.notify_attack_finished()


func _interrupt_for_poise() -> void:
	_interrupt_attack()
	_clear_drop_box()
	_state = State.IDLE
	_timer = 0.0


# ---------------------------------------------------------------------------
# 视觉（程序化像素：没有空钟的帧素材，用色板形状画一座锈钟）
# ---------------------------------------------------------------------------
func _build_visual() -> void:
	if visual == null:
		return
	for child in visual.get_children():
		if child is ColorRect:
			child.visible = false
	_glow = _build_glow()
	_hammer = BellHammer.new()
	_hammer.name = "Hammer"
	visual.add_child(_hammer)
	_shell = BellShell.new()
	_shell.name = "BellShell"
	visual.add_child(_shell)
	_flash_target = _shell
	_anim = null


func _build_glow() -> Sprite2D:
	var glow := Sprite2D.new()
	glow.name = "BellGlow"
	const PATH := "res://assets/env/glow_soft.png"
	if ResourceLoader.exists(PATH):
		glow.texture = load(PATH) as Texture2D
	glow.position = Vector2(0.0, -140.0)
	glow.scale = Vector2(2.6, 3.0)
	glow.z_index = -1
	glow.material = Fx.additive_mat()
	glow.modulate = Color(1.0, 0.55, 0.25, 0.20)
	visual.add_child(glow)
	return glow


func _update_visuals(delta: float) -> void:
	if _shell != null and _shell.has_method("animate"):
		_shell.call("animate", delta, _swing, _enraged, _pulling)
	if _hammer != null and _hammer.has_method("animate"):
		var swing := sin(Time.get_ticks_msec() / 1000.0 * 1.2) * 0.06 if _state == State.IDLE else _swing
		(_hammer as Node2D).position = HAMMER_HOME + Vector2(swing * 70.0, 0.0)
		(_hammer as Node2D).rotation = swing * 0.8
	if _glow != null:
		var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() / 1000.0 * 2.4)
		_glow.modulate.a = (0.30 if _enraged else 0.18) * pulse


## 钟体：锈铜梯形钟身 + 钟口 + 钟面裂纹（二阶段裂缝透炉火）+ 顶部吊索。
class BellShell extends Node2D:
	const HANG_TOP := -318.0
	const BELL_TOP := -196.0
	const BELL_BOTTOM := -78.0
	const BELL_W := 96.0

	var _hot := false
	var _t := 0.0
	var _shake := 0.0
	var _pulling := false

	func set_hot(hot: bool) -> void:
		_hot = hot
		queue_redraw()

	func animate(delta: float, swing: float, hot: bool, pulling: bool) -> void:
		_t += delta
		_hot = hot
		_pulling = pulling
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 8.0))
		if absf(swing) > 0.05:
			_shake = maxf(_shake, absf(swing) * 3.0)
		queue_redraw()

	func shake_by(amount: float) -> void:
		_shake = maxf(_shake, amount)

	func _draw() -> void:
		var ox := sin(_t * 34.0) * _shake
		# 吊索 / 梁：从洞顶垂到钟顶。
		draw_rect(Rect2(roundf(ox) - 2.0, HANG_TOP, 4.0, BELL_TOP - HANG_TOP), Color(0.22, 0.18, 0.16))
		draw_rect(Rect2(roundf(ox) - 5.0, HANG_TOP - 6.0, 10.0, 6.0), Color(0.30, 0.24, 0.2))
		# 钟身：上窄下宽的梯形（整数像素折线）。
		var top := BELL_TOP
		var bottom := BELL_BOTTOM
		var half_top := BELL_W * 0.34
		var half_bottom := BELL_W * 0.5
		var shell := PackedVector2Array([
			Vector2(roundf(ox - half_top), top),
			Vector2(roundf(ox + half_top), top),
			Vector2(roundf(ox + half_bottom), bottom - 14.0),
			Vector2(roundf(ox + half_bottom + 4.0), bottom),
			Vector2(roundf(ox - half_bottom - 4.0), bottom),
			Vector2(roundf(ox - half_bottom), bottom - 14.0),
		])
		draw_colored_polygon(shell, Color(0.26, 0.21, 0.17))
		# 高光面（右半）：锈铜的暖高光。
		var highlight := PackedVector2Array([
			Vector2(roundf(ox + half_top * 0.25), top + 6.0),
			Vector2(roundf(ox + half_top), top),
			Vector2(roundf(ox + half_bottom), bottom - 14.0),
			Vector2(roundf(ox + half_bottom * 0.35), bottom - 6.0),
		])
		draw_colored_polygon(highlight, Color(0.42, 0.30, 0.20))
		# 钟口厚沿 + 两条装饰箍。
		draw_rect(Rect2(roundf(ox - half_bottom - 6.0), bottom, BELL_W + 12.0, 8.0),
				Color(0.34, 0.26, 0.19))
		draw_rect(Rect2(roundf(ox - half_bottom - 2.0), bottom - 30.0, BELL_W + 4.0, 3.0),
				Color(0.18, 0.14, 0.12))
		# 钟面裂纹：二阶段透出炉火（亮橙点线）。
		var crack := Color(1.0, 0.55, 0.2, 0.9) if _hot else Color(0.16, 0.13, 0.12)
		var cx := roundf(ox)
		draw_line(Vector2(cx - 6.0, top + 26.0), Vector2(cx + 2.0, top + 52.0), crack, 2.0)
		draw_line(Vector2(cx + 2.0, top + 52.0), Vector2(cx - 4.0, top + 74.0), crack, 2.0)
		draw_line(Vector2(cx - 4.0, top + 74.0), Vector2(cx + 8.0, top + 94.0), crack, 2.0)
		if _hot:
			draw_rect(Rect2(cx - 10.0, top + 24.0, 3.0, 3.0), Color(1.0, 0.4, 0.12, 0.8))
			draw_rect(Rect2(cx + 6.0, top + 90.0, 3.0, 3.0), Color(1.0, 0.4, 0.12, 0.8))
		# 钟舌：垂在钟口中央，拉拽时绷直。
		var tongue_len := 40.0 if _pulling else 26.0
		draw_rect(Rect2(cx - 3.0, bottom + 2.0, 6.0, 6.0), Color(0.20, 0.16, 0.13))
		draw_line(Vector2(cx, bottom + 6.0), Vector2(cx, bottom + tongue_len), Color(0.20, 0.16, 0.13), 2.0)


## 钟锤（弱点）：吊在钟口下方、可摆动的铁锤头。
class BellHammer extends Node2D:
	var _t := 0.0

	func _draw() -> void:
		# 锤柄从上垂下（本地原点 = 锤头中心）。
		draw_rect(Rect2(-1.0, -34.0, 2.0, 26.0), Color(0.20, 0.16, 0.13))
		draw_rect(Rect2(-6.0, -26.0, 12.0, 4.0), Color(0.28, 0.23, 0.19))
		# 锤头：铁块 + 高光 + 侧面。
		draw_rect(Rect2(-11.0, -10.0, 22.0, 16.0), Color(0.30, 0.26, 0.23))
		draw_rect(Rect2(-11.0, -10.0, 22.0, 4.0), Color(0.44, 0.38, 0.32))
		draw_rect(Rect2(6.0, -10.0, 5.0, 16.0), Color(0.22, 0.18, 0.15))
		# 弱点记号：暗金点（只有一像素点，不抢戏）。
		draw_rect(Rect2(-2.0, -4.0, 4.0, 4.0), Color(1.0, 0.78, 0.35, 0.85))


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------
func _player() -> Player:
	var p := knight()
	if p == null or p.health.current <= 0:
		return null
	return p


func _effects_host() -> Node:
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	return host


func _clamp_x(x: float) -> float:
	if not is_finite(arena_left) or not is_finite(arena_right):
		return x
	return clampf(x, arena_left + 24.0, arena_right - 24.0)


func _append_transient_marker_meta(_data: Dictionary) -> void:
	pass


func _on_died() -> void:
	_interrupt_attack()
	if _boss_director != null:
		_boss_director.notify_death()
	slain.emit()
	Juice.boss_death_beat(global_position + Vector2(0.0, -120.0))
	GameEvents.boss_defeated.emit()
	SaveData.mark_flag(FLAG_DEAD)
	SaveData.persist_story()
	_cleanup_transient()
	_death_burst([] as Array[Texture2D], 12.0, _facing > 0.0, 0.0, "空钟停了，钟声散进地窟")


func _cleanup_transient() -> void:
	for node in _transient:
		if is_instance_valid(node):
			node.queue_free()
	_transient.clear()
	_clear_fling()
	if _pull_target != null and is_instance_valid(_pull_target) and _pull_target is Node2D:
		pass


# ---------------------------------------------------------------------------
# 攻击表（Kit 数据；数值与实现同源）
# ---------------------------------------------------------------------------
func _boss_kit_config() -> Dictionary:
	return {
		"id": &"hollow_bell",
		"title": BOSS_TITLE,
		"subtitle": BOSS_SUBTITLE,
		"max_phases": 2,
		"phase_thresholds": [1.0, 0.5],
		"min_interval": 0.9,
		"attacks": [
			{
				"id": &"pendulum", "phase": 1, "weight": 2.0,
				"cooldown": 2.2, "cooldown_by_phase": [2.2, 1.5],
				"min_range": 0.0, "max_range": 420.0,
				"windup": PENDULUM_WINDUP, "active": PENDULUM_ACTIVE, "recovery": PENDULUM_RECOVERY,
				"telegraph": &"hollow_bell",
				"hitbox": {"offset": Vector2(PENDULUM_SWEEP * 0.5, PENDULUM_Y.y),
						"size": Vector2(PENDULUM_SWEEP, PENDULUM_BOX.y)},
			},
			{
				"id": &"chain_pull", "phase": 1, "weight": 1.2,
				"cooldown": 3.2, "cooldown_by_phase": [3.2, 2.4],
				"min_range": 60.0, "max_range": PULL_RANGE,
				"windup": PULL_WINDUP, "active": PULL_ACTIVE, "recovery": PULL_RECOVERY,
				"telegraph": &"hollow_bell", "damaging": false, "hitbox": {},
			},
			{
				"id": &"bell_drop", "phase": 2, "weight": 1.8,
				"cooldown": 2.2, "cooldown_by_phase": [2.2, 1.6],
				"min_range": 0.0, "max_range": 460.0,
				"windup": DROP_WINDUP, "active": DROP_ACTIVE, "recovery": DROP_RECOVERY,
				"telegraph": &"hollow_bell",
				"hitbox": {"offset": Vector2(0.0, -DROP_ZONE.y * 0.5), "size": DROP_ZONE},
			},
			{
				"id": &"toll_wave", "phase": 1, "weight": 1.0,
				"cooldown": 3.0, "cooldown_by_phase": [3.0, 2.1],
				"min_range": 0.0, "max_range": 0.0,
				"windup": WAVE_WINDUP, "active": WAVE_ACTIVE, "recovery": WAVE_RECOVERY,
				"telegraph": &"hollow_bell", "hitbox": {},
			},
		],
		"arena_events": [
			{"id": &"bell_fall_west", "at_phase": 1, "once": true},
			{"id": &"bell_fall_east", "at_phase": 2, "once": true},
			{"id": &"arena_dim", "at_phase": 0, "once": true},
		],
	}
