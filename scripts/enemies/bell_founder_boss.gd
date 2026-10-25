extends EnemyBase
## 铸钟人（BellFounder）· 名字的炉 —— 第拾章「铸钟厅」的 Boss。
##
## 一个把自己浇进钟里的铸工。他围着浇铸坑走位：用锤头敲地（锤势可以弹反，
## 弹回会敲裂他的钟壳、露出破绽），把熔金泼成一片持续燃烧的浇铸区，
## 召唤还在模子里的钟壳，并把钟片像飞刀一样甩出去。
## 二阶段炉温不再下降：熔池更大、更久，钟壳更多，浇铸区把安全台挤窄。
##
## 框架（docs/integration-contracts.md §4.1）：BossKit + 驾驶模式 BossDirector。
## 可读性：前摇 >= 0.35s；同一时刻一条预警；hitbox 不出竞技场。
## 全部演出不锁输入，Director 层可随时跳过。

signal slain

enum State { IDLE, ATTACK, STAGGER }
enum AttackStep { WINDUP, ACTIVE, RECOVERY }

const BOSS_TITLE := "铸钟人 · 名字的炉"
const BOSS_SUBTITLE := "名字的炉"
const MAX_HP := 20
const AGGRO_RANGE := 340.0
const FLAG_DEAD := "founder_dead"

const APPROACH_SPEED := 42.0
const APPROACH_KEEP := 120.0
const CHASE_SPEED_P2 := 64.0

const HAMMER_WINDUP := 0.62
const HAMMER_ACTIVE := 0.26
const HAMMER_RECOVERY := 0.72
const HAMMER_ZONE := Vector2(76.0, 40.0)
const HAMMER_ZONE_Y := -22.0
const HAMMER_WAVE_SPEED := 190.0

const MOLD_WINDUP := 0.58
const MOLD_ACTIVE := 0.22
const MOLD_RECOVERY := 0.60
const MOLD_HUSKS := 2
const MOLD_HUSKS_P2 := 3
const HUSK_SPEED := 120.0

const POOL_WINDUP := 0.70
const POOL_ACTIVE := 0.20
const POOL_RECOVERY := 0.70
const POOL_RADIUS := 58.0
const POOL_RADIUS_P2 := 82.0
const POOL_LIFE := 5.0
const POOL_LIFE_P2 := 6.5
const POOL_TICK := 0.9

const SHARD_WINDUP := 0.52
const SHARD_ACTIVE := 0.20
const SHARD_RECOVERY := 0.66
const SHARD_COUNT := 3
const SHARD_SPEED := 250.0
const SHARD_SPREAD := 0.30

const PHASE_TRANSITION_TIME := 1.2
const BREAK_STAGGER := 2.2
const BREAK_RIPOSTE := 2.6

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
var _broken_left := 0.0
var _break_count := 0
var _husks_spawned := 0
var _shard_volleys := 0
var _swing := 0.0
var _swing_target := 0.0
var _transient: Array[Node] = []
var _pools: Array[Node] = []
var _boss_kit: BossKit
var _boss_director: BossDirector
var _shell: Node2D
var _hammer: Node2D
var _glow: Sprite2D

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------
func _enemy_ready() -> void:
	hit_material = &"boss"
	health.max_hp = MAX_HP
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	_build_visual()
	_build_boss_framework()
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
	GameEvents.announcement.emit("炉温不降。名字在锅里。")
	Fx.attach_ember(visual)
	Sfx.play_at(CombatRules.sfx_key(&"boss_roar"), global_position, 0.1, -10.0)


func is_announced() -> bool:
	return _announced


func is_enraged() -> bool:
	return _enraged


func state() -> State:
	return _state


func phase() -> int:
	return _phase


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
		Juice.boss_phase_beat(global_position + Vector2(0.0, -40.0), Color(1.0, 0.62, 0.3))
		Fx.attach_heat_lick(visual)
		if _shell != null and _shell.has_method("set_hot"):
			_shell.call("set_hot", true)
		GameEvents.announcement.emit("炉温不再下降，熔池漫过铸台")
		GameEvents.boss_phase_changed.emit(BOSS_TITLE, next_phase)


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
	if _dead or _state != State.IDLE or _transition_left > 0.0:
		return
	_begin_attack(id)


func _begin_attack(id: StringName) -> void:
	match id:
		&"hammer_slam":
			_begin_hammer()
		&"mold_cast":
			_begin_mold()
		&"molten_pool":
			_begin_pool()
		&"bell_shard":
			_begin_shards()
		_:
			return


func _set_attack(id: StringName, step: AttackStep, time: float) -> void:
	_attack = id
	_state = State.ATTACK
	_step = step
	_timer = time
	if _boss_director != null:
		_boss_director.last_attack_id = id


func _begin_hammer() -> void:
	_set_attack(&"hammer_slam", AttackStep.WINDUP, HAMMER_WINDUP)
	_face_player()
	begin_telegraph(&"bell_founder", HAMMER_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
			Vector2(_facing * HAMMER_ZONE.x * 0.5, HAMMER_ZONE_Y),
			HAMMER_WINDUP, Color(1.0, 0.5, 0.22, 0.95),
			{"rect": Rect2(-HAMMER_ZONE * 0.5, HAMMER_ZONE)})
	_swing_target = _facing
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_swing"), global_position, 0.08, -6.0)


func _begin_mold() -> void:
	_set_attack(&"mold_cast", AttackStep.WINDUP, MOLD_WINDUP)
	_face_player()
	begin_telegraph(&"bell_founder", MOLD_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.RING, Vector2(0.0, -30.0), MOLD_WINDUP,
			Color(0.7, 0.9, 1.0, 0.95), {"radius_from": 20.0, "radius_to": 52.0})
	Sfx.play_at(CombatRules.sfx_key(&"insert"), global_position, 0.08, -8.0)


func _begin_pool() -> void:
	_set_attack(&"molten_pool", AttackStep.WINDUP, POOL_WINDUP)
	var drop_x := _player_x_or(global_position.x)
	drop_x = _clamp_x(drop_x)
	_facing = signf(drop_x - global_position.x) if absf(drop_x - global_position.x) > 4.0 else _facing
	set_meta("pool_x", drop_x)
	begin_telegraph(&"bell_founder", POOL_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
			Vector2(drop_x - global_position.x, -24.0), POOL_WINDUP,
			Color(1.0, 0.72, 0.2, 0.95),
			{"rect": Rect2(-Vector2(POOL_RADIUS * 1.4, 48.0) * 0.5, Vector2(POOL_RADIUS * 1.4, 48.0))})
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_slam"), global_position, 0.1, -12.0)


func _begin_shards() -> void:
	_set_attack(&"bell_shard", AttackStep.WINDUP, SHARD_WINDUP)
	_face_player()
	begin_telegraph(&"bell_founder", SHARD_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.RING, Vector2(0.0, -36.0), SHARD_WINDUP,
			Color(0.9, 0.82, 0.55, 0.95), {"radius_from": 26.0, "radius_to": 10.0})
	Sfx.play_at(CombatRules.sfx_key(&"spit_charge"), global_position, 0.1, -8.0)


func _tick_attack(delta: float) -> void:
	_timer -= delta
	var active_time := 0.0
	var recovery := 0.0
	match _attack:
		&"hammer_slam":
			active_time = HAMMER_ACTIVE
			recovery = HAMMER_RECOVERY
		&"mold_cast":
			active_time = MOLD_ACTIVE
			recovery = MOLD_RECOVERY
		&"molten_pool":
			active_time = POOL_ACTIVE
			recovery = POOL_RECOVERY
		&"bell_shard":
			active_time = SHARD_ACTIVE
			recovery = SHARD_RECOVERY
		_:
			_finish_attack()
			return
	if _step == AttackStep.WINDUP:
		if _timer > 0.0:
			return
		_step = AttackStep.ACTIVE
		_timer = active_time
		_do_active()
	elif _step == AttackStep.ACTIVE:
		if _timer > 0.0:
			return
		_step = AttackStep.RECOVERY
		_timer = recovery
		_swing_target = 0.0
		show_opening(recovery)
	elif _step == AttackStep.RECOVERY and _timer <= 0.0:
		_finish_attack()


func _do_active() -> void:
	match _attack:
		&"hammer_slam":
			_do_hammer()
		&"mold_cast":
			_do_mold()
		&"molten_pool":
			_do_pool()
		&"bell_shard":
			_do_shards()


# --- 锤击（锤势可弹反 -> 破防） ---------------------------------------------
func _do_hammer() -> void:
	var host := _effects_host()
	var origin := global_position + Vector2(_facing * 44.0, -14.0)
	# 直击判定（近身） + 一道可弹反的锤势（Projectile）。
	var box := Hitbox.new()
	box.damage = 2
	box.team = &"enemy"
	box.blow = &"heavy"
	box.knockback = Vector2(_facing * 120.0, -50.0)
	box.monitoring = true
	box.collision_layer = 8
	box.collision_mask = 32
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = HAMMER_ZONE
	shape.shape = rect
	box.add_child(shape)
	host.add_child(box)
	box.global_position = global_position + Vector2(_facing * HAMMER_ZONE.x * 0.5, HAMMER_ZONE_Y)
	box.arm(Vector2(_facing * 120.0, -50.0))
	_transient.append(box)
	var wave := _spawn_projectile(origin, Vector2(_facing, 0.0), HAMMER_WAVE_SPEED, 1)
	if wave != null:
		wave.name = "FounderHammerWave"
	Juice.shake(4.0, 220)
	Fx.dust_puff(origin, PI if _facing > 0.0 else 0.0)
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_slam"), origin, 0.05, -3.0)
	_swing_target = 0.0


## 玩家把锤势弹回来：钟壳裂开，进入破防（破绽 + 硬直）。
func _on_parried(projectile: Node, _by_actor: Node) -> void:
	if _dead or not (projectile is Projectile):
		return
	if (projectile as Projectile).source != self:
		return
	_break_guard()


func _break_guard() -> void:
	if _dead or _transition_left > 0.0:
		return
	_break_count += 1
	_interrupt_attack()
	_state = State.STAGGER
	_broken_left = BREAK_STAGGER
	_timer = BREAK_STAGGER
	open_riposte(BREAK_RIPOSTE)
	Juice.shake(4.0, 200)
	Fx.hit_sparks(global_position + Vector2(0.0, -36.0))
	Sfx.play_at(CombatRules.sfx_key(&"shield_break"), global_position, 0.06, -4.0)
	GameEvents.announcement.emit("锤势被弹回，钟壳裂了")
	if _shell != null and _shell.has_method("crack"):
		_shell.call("crack")


func is_broken() -> bool:
	return _broken_left > 0.0


func break_count() -> int:
	return _break_count


# --- 铸模召唤 ---------------------------------------------------------------
func _do_mold() -> void:
	var count := MOLD_HUSKS_P2 if _enraged else MOLD_HUSKS
	var host := _effects_host()
	var player := _player()
	var aim := Vector2(_facing, -0.2)
	if player != null:
		aim = (player.global_position + Vector2(0.0, -16.0) - global_position).normalized()
	for i in count:
		var spread := (float(i) - (count - 1) * 0.5) * 0.26
		var dir := aim.rotated(spread)
		var husk := _spawn_projectile(global_position + Vector2(0.0, -46.0), dir, HUSK_SPEED, 1)
		if husk == null:
			continue
		_husks_spawned += 1
		husk.name = "MoldHusk%d" % _husks_spawned
		husk.scale = Vector2(1.6, 1.6)
	Sfx.play_at(CombatRules.sfx_key(&"gear_creak"), global_position, 0.1, -8.0)


# --- 浇铸区（熔金池） -------------------------------------------------------
func _do_pool() -> void:
	var center_x := _clamp_x(float(get_meta("pool_x", global_position.x)))
	var radius := POOL_RADIUS_P2 if _enraged else POOL_RADIUS
	var life := POOL_LIFE_P2 if _enraged else POOL_LIFE
	var centers: Array[float] = [center_x]
	if _enraged:
		# 二阶段：再泼一勺，两片熔池把中间的安全台挤窄（左/右各一片）。
		centers = [center_x - radius * 1.1, center_x + radius * 1.1]
	for i in centers.size():
		var x: float = centers[i]
		var pool := MoltenPool.new()
		pool.name = "MoltenPool%d" % (i + 1)
		pool.radius = radius
		pool.life = life
		pool.tick = POOL_TICK
		pool.damage = 1
		pool.owner_boss = self
		pool.position = Vector2(_clamp_x(x) - global_position.x, 0.0)
		add_child(pool)
		_pools.append(pool)
	Sfx.play_at(CombatRules.sfx_key(&"rustgate_melt"), global_position, 0.08, -6.0)
	Juice.shake(2.5, 160)


func pool_count() -> int:
	var n := 0
	for pool in _pools:
		if is_instance_valid(pool) and not (pool as Node).is_queued_for_deletion():
			n += 1
	return n


func pool_radius() -> float:
	return POOL_RADIUS_P2 if _enraged else POOL_RADIUS


# --- 钟片投射 ---------------------------------------------------------------
func _do_shards() -> void:
	_shard_volleys += 1
	var player := _player()
	var aim := Vector2(_facing, -0.08)
	if player != null:
		aim = (player.global_position + Vector2(0.0, -16.0) - global_position).normalized()
	for i in SHARD_COUNT:
		var spread := (float(i) - (SHARD_COUNT - 1) * 0.5) * SHARD_SPREAD
		var shard := _spawn_projectile(global_position + Vector2(_facing * 30.0, -42.0),
				aim.rotated(spread), SHARD_SPEED, 1)
		if shard != null:
			shard.name = "BellShard%d" % i
	Sfx.play_at(CombatRules.sfx_key(&"boss_axe_swing"), global_position, 0.1, -8.0)


func shard_volleys() -> int:
	return _shard_volleys


func husks_spawned() -> int:
	return _husks_spawned


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
			_tick_idle(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.STAGGER:
			_broken_left = maxf(0.0, _broken_left - delta)
			if _broken_left <= 0.0:
				_state = State.IDLE
				hide_opening()
	_update_visuals(delta)


func _tick_idle(delta: float) -> void:
	var player := _player()
	if not _announced:
		if player != null and global_position.distance_to(player.global_position) <= AGGRO_RANGE:
			announce()
		return
	if player == null:
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		return
	_face_player()
	var dist := absf(player.global_position.x - global_position.x)
	if dist > APPROACH_KEEP:
		var speed := CHASE_SPEED_P2 if _enraged else APPROACH_SPEED
		velocity.x = signf(player.global_position.x - global_position.x) * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)


func _after_move() -> void:
	global_position.x = _clamp_x(global_position.x)
	if visual != null:
		visual.scale.x = 1.0 if _facing >= 0.0 else -1.0


func _finish_attack() -> void:
	_state = State.IDLE
	_attack = &""
	hide_opening()
	_swing_target = 0.0
	if _boss_director != null:
		_boss_director.notify_attack_finished()


func _interrupt_attack() -> void:
	if _state == State.ATTACK:
		_state = State.IDLE
		_attack = &""
		hide_opening()
		if _boss_director != null:
			_boss_director.notify_attack_finished()


func _interrupt_for_poise() -> void:
	_interrupt_attack()
	_disarm_poise_hitboxes(_transient)
	_state = State.IDLE
	_timer = 0.0


# ---------------------------------------------------------------------------
# 视觉（原创四层炉甲铸工 / 钟模背炉 / 独立分节锤）
# ---------------------------------------------------------------------------
func _build_visual() -> void:
	if visual == null:
		return
	for child in visual.get_children():
		if child is ColorRect:
			child.visible = false
	_glow = Sprite2D.new()
	_glow.name = "FounderGlow"
	const GLOW := "res://assets/env/glow_soft.png"
	if ResourceLoader.exists(GLOW):
		_glow.texture = ArtTexture.load_texture(GLOW)
	_glow.position = Vector2(0.0, -40.0)
	_glow.scale = Vector2(2.2, 2.6)
	_glow.z_index = -1
	_glow.material = Fx.additive_mat()
	_glow.modulate = Color(1.0, 0.55, 0.22, 0.18)
	visual.add_child(_glow)
	_hammer = FounderHammer.new()
	_hammer.name = "FounderHammer"
	visual.add_child(_hammer)
	_shell = FounderShell.new()
	_shell.name = "FounderShell"
	visual.add_child(_shell)
	_flash_target = _shell
	_anim = null


func _update_visuals(delta: float) -> void:
	if _shell != null and _shell.has_method("animate"):
		_shell.call("animate", delta, _swing, _enraged, _broken_left > 0.0, String(_attack), int(_step))
	if _hammer != null and _hammer.has_method("set_swing"):
		(_hammer as Node2D).call("set_swing", _swing)
		_hammer.call("animate_state", delta, _enraged, _broken_left > 0.0, String(_attack), int(_step))
	if _glow != null:
		var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() / 1000.0 * 2.2)
		_glow.modulate.a = (0.30 if _enraged else 0.16) * pulse


## 自绘四层炉甲：各层护甲、背炉开口和钳手均烘焙为透明整数像素帧。
class FounderShell extends Node2D:
	var _hot := false
	var _t := 0.0
	var _frames: FrameAnimSprite

	func _ready() -> void:
		_frames = FrameAnimSprite.new()
		_frames.name = "OriginalFounderFrames"
		for prefix in ["", "hot_"]:
			for action in ["idle", "hammer_slam", "mold_cast", "molten_pool", "bell_shard", "stagger"]:
				var key: String = prefix + action
				_frames.register(key, CharFrames.anim("original_bell_founder", key), 6.0, true, Vector2(0.0, -56.0))
		add_child(_frames)
		_frames.pin_frame("idle", 0)

	func set_hot(hot: bool) -> void:
		_hot = hot
		if _frames != null:
			_frames.pin_frame(("hot_" if _hot else "") + "idle", 0)

	func crack() -> void:
		if _frames != null:
			_frames.pin_frame(("hot_" if _hot else "") + "stagger", 0)

	func animate(delta: float, _swing: float, hot: bool, broken: bool, attack: String, step: int) -> void:
		_t += delta
		_hot = hot
		var action := "stagger" if broken else (attack if not attack.is_empty() else "idle")
		var index := int(_t * 6.0) % 4 if action in ["idle", "stagger"] else clampi(step, 0, 2) * 2 + int(_t * 8.0) % 2
		_frames.pin_frame(("hot_" if hot else "") + action, index)


## 独立分节锤仍接收真实 swing；举锤/落锤/收锤另按真实 AttackStep 钉帧。
class FounderHammer extends Node2D:
	var _t := 0.0
	var _frames: FrameAnimSprite

	func _ready() -> void:
		_frames = FrameAnimSprite.new()
		_frames.name = "OriginalFounderToolFrames"
		for prefix in ["", "hot_"]:
			for action in ["idle", "hammer_slam", "mold_cast", "molten_pool", "bell_shard", "stagger"]:
				var key: String = prefix + "tool_" + action
				_frames.register(key, CharFrames.anim("original_bell_founder", key), 6.0, true, Vector2(0.0, -56.0))
		add_child(_frames)
		_frames.pin_frame("tool_idle", 0)

	func set_swing(swing: float) -> void:
		rotation = -swing * 0.5

	func animate_state(delta: float, hot: bool, broken: bool, attack: String, step: int) -> void:
		_t += delta
		var action := "stagger" if broken else (attack if not attack.is_empty() else "idle")
		var index := int(_t * 6.0) % 4 if action in ["idle", "stagger"] else clampi(step, 0, 2) * 2 + int(_t * 8.0) % 2
		_frames.pin_frame(("hot_" if hot else "") + "tool_" + action, index)


## 熔金池：持续存在的浇铸区（站进去每 0.9s 掉 1 血）。视觉是发光的熔金面。
class MoltenPool extends Area2D:
	var radius := 58.0
	var life := 5.0
	var tick := 0.9
	var damage := 1
	var owner_boss: Node2D
	var _t := 0.0
	var _tick_left := 0.0

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = radius
		shape.shape = circle
		add_child(shape)
		body_entered.connect(_on_body_entered)

	func _process(delta: float) -> void:
		_t += delta
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		_tick_left = maxf(0.0, _tick_left - delta)
		queue_redraw()

	func _on_body_entered(body: Node2D) -> void:
		if not (body is Player) or body.is_invincible():
			return
		if _tick_left > 0.0:
			return
		_tick_left = tick
		(body as Player).health.take_damage(damage, owner_boss)
		if owner_boss != null and is_instance_valid(owner_boss):
			ForegroundFx()

	func ForegroundFx() -> void:
		pass

	func _draw() -> void:
		var pulse := 0.85 + 0.15 * sin(_t * 6.0)
		draw_circle(Vector2.ZERO, radius, Color(0.9, 0.32, 0.06, 0.22 * pulse))
		draw_circle(Vector2.ZERO, radius * 0.72, Color(1.0, 0.48, 0.10, 0.30 * pulse))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, Color(1.0, 0.7, 0.25, 0.8), 1.5)
		# 熔金气泡：4 个不同相位的亮点，只在视觉上跳动。
		for i in 4:
			var ang := TAU * float(i) / 4.0 + _t * 0.7
			var r := radius * (0.25 + 0.12 * float(i % 2))
			var p := Vector2(cos(ang), sin(ang) * 0.45) * r
			draw_rect(Rect2(p.round() - Vector2(1.0, 1.0), Vector2(3, 3)),
					Color(1.0, 0.78, 0.35, 0.9 * pulse))


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------
func _player() -> Player:
	var p := knight()
	if p == null or p.health.current <= 0:
		return null
	return p


func _player_x_or(fallback: float) -> float:
	var p := _player()
	return p.global_position.x if p != null else fallback


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


## 生成一颗敌方弹丸（走现有 Projectile 管线：可被 slash 弹反）。
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
	Juice.boss_death_beat(global_position + Vector2(0.0, -40.0))
	GameEvents.boss_defeated.emit()
	SaveData.mark_flag(FLAG_DEAD)
	SaveData.persist_story()
	_cleanup_transient()
	_death_burst([] as Array[Texture2D], 12.0, _facing > 0.0, 0.0, "铸钟人把自己浇进了最后一口钟")


func _cleanup_transient() -> void:
	for node in _transient:
		if is_instance_valid(node):
			node.queue_free()
	_transient.clear()
	for pool in _pools:
		if is_instance_valid(pool):
			(pool as Node).queue_free()
	_pools.clear()


func _exit_tree() -> void:
	if GameEvents.parried.is_connected(_on_parried):
		GameEvents.parried.disconnect(_on_parried)


# ---------------------------------------------------------------------------
# 攻击表（Kit 数据；数值与实现同源）
# ---------------------------------------------------------------------------
func _boss_kit_config() -> Dictionary:
	return {
		"id": &"bell_founder",
		"title": BOSS_TITLE,
		"subtitle": BOSS_SUBTITLE,
		"max_phases": 2,
		"phase_thresholds": [1.0, 0.5],
		"min_interval": 0.85,
		"attacks": [
			{
				"id": &"hammer_slam", "phase": 1, "weight": 2.0,
				"cooldown": 2.4, "cooldown_by_phase": [2.4, 1.7],
				"min_range": 0.0, "max_range": 150.0,
				"windup": HAMMER_WINDUP, "active": HAMMER_ACTIVE, "recovery": HAMMER_RECOVERY,
				"telegraph": &"bell_founder",
				"hitbox": {"offset": Vector2(HAMMER_ZONE.x * 0.5, HAMMER_ZONE_Y),
						"size": HAMMER_ZONE},
			},
			{
				"id": &"mold_cast", "phase": 1, "weight": 1.2,
				"cooldown": 3.2, "cooldown_by_phase": [3.2, 2.4],
				"min_range": 80.0, "max_range": 0.0,
				"windup": MOLD_WINDUP, "active": MOLD_ACTIVE, "recovery": MOLD_RECOVERY,
				"telegraph": &"bell_founder", "hitbox": {},
			},
			{
				"id": &"molten_pool", "phase": 2, "weight": 1.8,
				"cooldown": 2.6, "cooldown_by_phase": [2.6, 1.9],
				"min_range": 0.0, "max_range": 0.0,
				"windup": POOL_WINDUP, "active": POOL_ACTIVE, "recovery": POOL_RECOVERY,
				"telegraph": &"bell_founder", "damaging": false, "hitbox": {},
			},
			{
				"id": &"bell_shard", "phase": 1, "weight": 1.4,
				"cooldown": 2.8, "cooldown_by_phase": [2.8, 2.0],
				"min_range": 60.0, "max_range": 0.0,
				"windup": SHARD_WINDUP, "active": SHARD_ACTIVE, "recovery": SHARD_RECOVERY,
				"telegraph": &"bell_founder", "hitbox": {},
			},
		],
		"arena_events": [
			{"id": &"cast_pillar_west", "at_phase": 1, "once": true},
			{"id": &"cast_pillar_east", "at_phase": 2, "once": true},
			{"id": &"arena_dim", "at_phase": 0, "once": true},
		],
	}
