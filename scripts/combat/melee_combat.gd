class_name MeleeCombat
extends Node2D
## Heavy slash with wind-up, active (parry) frames, and recovery.
## Parry is not a separate button — it is the active window of this swing.
## 帧数、冷却、取消窗口都在 CombatRules；规则全文见 docs/combat-rules.md。

enum State { IDLE, WINDUP, ACTIVE, RECOVERY }

@export var windup_time: float = CombatRules.SWING_WINDUP[0]
@export var active_time: float = CombatRules.SWING_ACTIVE[0]
@export var recovery_time: float = CombatRules.SWING_RECOVERY[0]
@export var cooldown: float = CombatRules.SWING_COOLDOWN
@export var damage: int = 1

## Three-hit chain: index 0..2. Finishing blow (2) hits harder and lingers.
const COMBO_WINDUP := CombatRules.SWING_WINDUP
const COMBO_ACTIVE := CombatRules.SWING_ACTIVE
const COMBO_RECOVERY := CombatRules.SWING_RECOVERY
const COMBO_DAMAGE := CombatRules.SWING_DAMAGE
const ATTACK_BUFFER_TIME := CombatRules.ATTACK_BUFFER
const LINK_EARLY_TIME := CombatRules.LINK_EARLY
## 事件线程里记下的按键只在这么多个物理帧内有效：越过过场 / 暂停的陈旧按键作废，
## 而顿帧里（物理帧很稀）按下的键仍能被下一帧收下。
const LATCH_TICKS := 6

var _state: State = State.IDLE
var _timer: float = 0.0
var _cooldown: float = 0.0
var _combo_index: int = 0
var _link_buffered: bool = false
var _attack_buffer: float = 0.0
var _ignore_attack_until_release := false
## 后摇刚结束的补接窗口：窗口内按下直接起下一刀，不再空等冷却。
var _late_link_left: float = 0.0
var _late_next: int = 0
## 收刀（冲刺 / 跳跃取消）之后、冷却走完之前按下的攻击：仍算接刀，被空闲冷却
## 吞掉就是纯粹的输入迟滞。收刀是「想继续打」的强信号，所以开一个补按窗口：
## 窗口从收刀起、到冷却走完为止；窗口里玩家的任意一按都记住，冷却一归零立刻起刀。
## 不记倒计时（会和冷却同速清零、正好错过那一帧），也不自动出刀——必须玩家真按。
## _cancel_window = 窗口是否开着；_cancel_link_next = 窗口内挂起的接刀（-1 表示没挂）。
var _cancel_window: bool = false
var _cancel_link_next: int = -1
## 本刀是否弹反成功（命中另由 Hitbox.connected 记录）。
var _parried_swing := false
## 这一刀的前摇 / 判定期里玩家已经按了跳：跳跃本身照常离地，但打实之后
## 后摇不该再把人锁在空中。后摇开始那一帧消费这个标记。
var _jump_during_swing := false
var _press_latched_tick: int = -1000

@onready var hitbox: Hitbox = $Hitbox
@onready var sword: Node2D = get_node_or_null("../Visual/Sword") as Node2D


func _ready() -> void:
	if sword == null and has_node("Sword"):
		sword = get_node("Sword")
	if hitbox == null and has_node("Hitbox"):
		hitbox = get_node("Hitbox")
	# Sole deflection path: the swing's active frames acknowledge incoming
	# projectiles through the hitbox signal plus the idle-frame sweep below.
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	if hitbox:
		hitbox.damage = damage
		hitbox.team = &"player"
		hitbox.riposte_eligible = true
		hitbox.monitoring = false
	var host := get_parent()
	var hp := host.get_node_or_null("Health") as Health
	if hp != null:
		hp.died.connect(cancel_attack)
	# 取消窗口：冲刺要过闸门才能打断后摇；起跳 / 冲刺成功后由这里收尾。
	# 只连宿主自己的控制器信号，不走全局总线，重生时不会重复连接。
	var ctrl := host.get_node_or_null("PlayerController") as PlayerController
	if ctrl != null:
		ctrl.dash_cancel_gate = can_dash_cancel
		ctrl.dashed.connect(_on_host_dashed)
		ctrl.jumped.connect(_on_host_jumped)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		clear_attack_buffer()


## 按键在事件线程先记一笔：物理帧很稀（顿帧 / 慢动作）时，按下又松开都落在两帧之间的
## 短按不会被 Input.is_action_just_pressed 看漏。触控走 Input.action_press（无事件），
## 仍由 tick() 里的轮询覆盖。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"attack"):
		_press_latched_tick = Engine.get_physics_frames()


func _take_press() -> bool:
	var fresh := Engine.get_physics_frames() - _press_latched_tick <= LATCH_TICKS
	_press_latched_tick = -1000
	return Input.is_action_just_pressed(&"attack") or fresh


## Pause/cutscene boundaries discard queued presses, including a held button.
func clear_attack_buffer() -> void:
	_attack_buffer = 0.0
	_link_buffered = false
	_late_link_left = 0.0
	_cancel_window = false
	_cancel_link_next = -1
	_press_latched_tick = -1000
	_ignore_attack_until_release = Input.is_action_pressed("attack")


func cancel_attack() -> void:
	clear_attack_buffer()
	_state = State.IDLE
	_combo_index = 0
	_timer = 0.0
	_jump_during_swing = false
	if hitbox != null:
		hitbox.monitoring = false
	_set_lock(false)


## One press queues at most one slash, without shortening any committed phase.
func request_attack() -> bool:
	if _host_locked() or get_tree().paused or _ignore_attack_until_release:
		return false
	if _state == State.IDLE:
		if _late_link_left > 0.0 and _late_next > 0:
			# 后摇刚结束的补按：算接刀（第二刀前摇更短），不让空闲冷却吃掉这一按。
			_combo_index = _late_next
			_late_link_left = 0.0
			_late_next = 0
			_cooldown = 0.0
			_attack_buffer = 0.0
			return start_swing()
		if _cancel_window and _cancel_link_next >= 0:
			# 收刀之后冷却尾巴上的补按：直接起刀。收刀已经证明玩家想继续打，
			# 这一按被冷却吞掉就是纯粹的输入迟滞。窗口里玩家真按了才挂起，不会自动出刀。
			_combo_index = _cancel_link_next
			_cancel_window = false
			_cancel_link_next = -1
			_cooldown = 0.0
			_attack_buffer = 0.0
			return start_swing()
		if start_swing():
			_attack_buffer = 0.0
		else:
			# 冷却期内普通挥砍：普通缓冲只够 0.16 s，而冷却有 0.40 s，最后一段会落空。
			# 只有身处「收刀补按窗口」才把这一按挂起、等冷却走完立刻起刀；
			# 普通挥砍的过期按键不挂起（保持 0.16 s 上限，不会自动出刀）。
			if _cancel_window:
				_cancel_link_next = _combo_index
			_attack_buffer = ATTACK_BUFFER_TIME
		return true
	if _combo_index < 2 and (_state == State.RECOVERY \
			or (_state == State.ACTIVE and _timer <= LINK_EARLY_TIME + 0.00001)):
		_link_buffered = true
		return true
	return false


func _on_hitbox_area_entered(area: Area2D) -> void:
	if area is Projectile:
		try_deflect(area as Projectile)


## 弹反唯一权威入口：窗口判定、反弹指令与成功反馈（parried 信号 / 播报 /
## 音效）都在这里。Projectile.deflect 只执行反弹本身；敌人（齿轮盾卫的
## 格挡硬直等）只作为响应方接信号或被 hurtbox 调用，不再自行判窗。
func try_deflect(bolt: Projectile) -> bool:
	if not is_parry_window() or not bolt.can_deflect():
		return false
	var host := get_parent()
	var actor: Node2D = (host as Node2D) if host is Node2D else self
	bolt.deflect(actor)
	_parried_swing = true
	if hitbox != null:
		hitbox.connected = true
	if host is Player:
		var knight := host as Player
		knight.toxin.purify(CombatRules.PARRY_PURIFY)
		knight.resonance.pulse()
		knight.controller.grant_air_jump()
	GameEvents.parried.emit(bolt, actor)
	GameEvents.announcement.emit("弹反！")
	Sfx.play(&"parry")
	Fx.burst(&"ring", bolt.global_position)
	return true


func is_busy() -> bool:
	return _state != State.IDLE


func is_parry_window() -> bool:
	return _state == State.ACTIVE and not _host_locked()


## 本刀是否已经「打实」：造成了伤害或弹反成功。盾面挡下不算。
func swing_connected() -> bool:
	return _parried_swing or (hitbox != null and hitbox.connected)


## 后摇已走过的比例（0 = 刚进后摇，1 = 后摇结束）；不在后摇里返回 0。
func recovery_progress() -> float:
	if _state != State.RECOVERY:
		return 0.0
	return phase_progress()


## 当前阶段走过的比例（0 = 刚进入，1 = 即将结束）。空闲返回 0。
func phase_progress() -> float:
	if _state == State.IDLE:
		return 0.0
	var total := 0.0
	match _state:
		State.WINDUP:
			total = float(COMBO_WINDUP[_combo_index])
		State.ACTIVE:
			total = float(COMBO_ACTIVE[_combo_index])
		State.RECOVERY:
			total = float(COMBO_RECOVERY[_combo_index])
	return clampf(1.0 - _timer / maxf(total, 0.001), 0.0, 1.0)


## 冲刺此刻能否开始：空闲随时可以；后摇里命中过从头开始，挥空要过 60%；
## 前摇与判定期任何动作都不能打断。
func can_dash_cancel() -> bool:
	if _state == State.IDLE:
		return true
	if _state != State.RECOVERY:
		return false
	var from := CombatRules.DASH_CANCEL_FROM_CONNECTED if swing_connected() \
			else CombatRules.DASH_CANCEL_FROM
	return recovery_progress() >= from


## 起跳此刻能否同时收掉后摇。挥空要过 60%；打实从后摇开头就能收。
## 前摇与判定期不能收刀，跳跃本身仍会离地。
func can_jump_cancel() -> bool:
	if _state != State.RECOVERY:
		return false
	var from := CombatRules.JUMP_CANCEL_FROM_CONNECTED if swing_connected() \
			else CombatRules.JUMP_CANCEL_FROM
	return recovery_progress() >= from


## 收掉后摇回到空闲（丢掉预输入的下一刀，连段归零；空闲冷却照常走完）。
## 前摇 / 判定期返回 false，什么也不改。
## 收刀（冲刺 / 跳跃取消）是「我想继续打」的强信号：随后冷却尾巴上的补按仍算
## 接刀，不让空闲冷却把玩家的下一刀吞掉。
func cancel_recovery() -> bool:
	if _state != State.RECOVERY:
		return false
	_link_buffered = false
	_late_link_left = 0.0
	# 收刀是「想继续打」的强信号：开一个补按窗口直到冷却走完；窗口里玩家真按了
	# 才挂起接刀、冷却归零立刻起刀。窗口不自动出刀、不放大普通挥砍的 0.16 s 缓冲。
	# 收刀本身把连段归零（escape 而非接刀），挂起的是重新起的第一刀（0）。
	_cancel_window = true
	_cancel_link_next = -1
	_combo_index = 0
	_timer = 0.0
	_state = State.IDLE
	_set_lock(false)
	return true


func _on_host_dashed() -> void:
	cancel_recovery()


func _on_host_jumped(_is_extra: bool) -> void:
	# 跳跃本身从不打断前摇 / 判定期；但这一跳已经离地，如果这刀随后打实，
	# 后摇一开始就该收掉，而不是把骑士锁在空中等完 0.26 / 0.46 秒。
	if _state == State.WINDUP or _state == State.ACTIVE:
		_jump_during_swing = true
	if can_jump_cancel():
		cancel_recovery()


func _physics_process(delta: float) -> void:
	tick(delta)


## Advance the swing state machine by one frame.
## Public so tests (and future AI/input shims) can drive it without Input.
func tick(delta: float) -> void:
	if _host_locked():
		cancel_attack()
		return
	_attack_buffer = maxf(0.0, _attack_buffer - delta)
	_late_link_left = maxf(0.0, _late_link_left - delta)
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if not Input.is_action_pressed("attack"):
		_ignore_attack_until_release = false
	if _take_press():
		request_attack()

	match _state:
		State.IDLE:
			_rest_sword(delta)
			if _attack_buffer > 0.0 and start_swing():
				_attack_buffer = 0.0
			elif _cancel_window and _cancel_link_next >= 0 and _cooldown <= 0.0:
				# 收刀补按窗口里玩家真按过：冷却一走完立刻起刀（挂起的补按不丢）。
				request_attack()
		State.WINDUP:
			_timer -= delta
			_tween_sword(-1.35 if _combo_index >= 2 else -0.9, delta, 14.0)
			if _timer <= 0.0:
				_begin_active()
		State.ACTIVE:
			_timer -= delta
			_tween_sword(1.5 if _combo_index >= 2 else 1.2, delta, 24.0)
			if _timer <= 0.0:
				_begin_recovery()
		State.RECOVERY:
			_timer -= delta
			_tween_sword(0.38, delta, 8.0)
			if _timer <= 0.0:
				if _link_buffered and _combo_index < 2:
					_link_buffered = false
					_combo_index += 1
					_begin_windup()
				else:
					# 补接窗口：下一按算接上一刀，而不是被空闲冷却吃掉。
					_late_next = _combo_index + 1 if _combo_index < 2 else 0
					_late_link_left = CombatRules.LATE_LINK_GRACE if _late_next > 0 else 0.0
					_jump_during_swing = false
					_combo_index = 0
					_state = State.IDLE
					_set_lock(false)
	# 冷却走完、窗口里没挂起补按：关窗（有挂起补按则上面已起刀、request_attack 已关）。
	# 放 match 之后，让「冷却归零那一帧挂着补按」也有机会在本帧出刀，而不是被先关窗吞掉。
	if _cancel_window and _cooldown <= 0.0:
		_cancel_window = false
		_cancel_link_next = -1


## Parry acknowledgement sampled during idle-phase processing: area-pair data
## and space queries are reliable outside the physics callback stack.
func _process(_delta: float) -> void:
	if hitbox == null or not is_parry_window():
		return
	for area in hitbox.get_overlapping_areas():
		_on_hitbox_area_entered(area)


## Attempt a slash bypassing the input layer. Returns false while busy/cooldown.
func start_swing() -> bool:
	if _state != State.IDLE or _cooldown > 0.0 or _host_locked():
		return false
	_begin_windup()
	return true


## Report which phase the swing is in ("idle"/"windup"/"active"/"recovery").
func phase_name() -> String:
	match _state:
		State.WINDUP:
			return "windup"
		State.ACTIVE:
			return "active"
		State.RECOVERY:
			return "recovery"
	return "idle"


func _begin_windup() -> void:
	_link_buffered = false
	_late_link_left = 0.0
	_jump_during_swing = false
	_state = State.WINDUP
	_timer = float(COMBO_WINDUP[_combo_index])
	_set_lock(true)
	GameEvents.swing_started.emit(_combo_index)
	Sfx.play(CombatRules.sfx_key(&"swing_heavy" if _combo_index >= 2 else &"swing"))


func _begin_active() -> void:
	_state = State.ACTIVE
	_timer = float(COMBO_ACTIVE[_combo_index])
	_parried_swing = false
	if hitbox:
		var face := 1.0
		var band: StringName = &"cold"
		var host := get_parent()
		var attack_bonus: int = 0
		if host is Player:
			var knight := host as Player
			face = float(knight.controller.facing)
			band = knight.toxin.band()
			if "stats" in knight and knight.stats != null and knight.stats.has_method(&"get_attack_bonus"):
				attack_bonus = knight.stats.get_attack_bonus()
		var tier := CombatRules.toxin_tier(band)
		hitbox.damage = maxi(1, int(COMBO_DAMAGE[_combo_index]) + int(tier["damage"]) + attack_bonus)
		hitbox.blow = _blow_for(_combo_index, tier)
		hitbox.already_hit.clear()
		hitbox.connected = false
		hitbox.monitoring = true
		var power := 150.0 if _combo_index >= 2 else 90.0
		if _combo_index >= 2:
			power *= float(tier["finisher_knock"])
		hitbox.knockback = Vector2(face * power, -40.0 if _combo_index >= 2 else -24.0)
		# 判定开始那一刻就结算已经压进剑刃的目标：贴身敌人不再晚一帧、弹反不再
		# 等到下一次物理 step；也保证剑先于火带 / 冲击波拿第一击（破绽翻倍归剑）。
		hitbox.sweep_now()
		if host is Player:
			(host as Player).on_melee_active(_combo_index)


## 出手分量：连段步给底（前两刀 light、终结击 finisher），毒素温档及以上把 light 抬成 heavy ——
## 毒素越高，命中的手感越重，这是读得出来的奖励。
func _blow_for(index: int, tier: Dictionary) -> StringName:
	var blow: StringName = CombatRules.SWING_BLOW[index]
	if blow == &"light" and bool(tier["weight_up"]):
		return &"heavy"
	return blow


func _host_locked() -> bool:
	var host := get_parent()
	if host is Player:
		var knight := host as Player
		return knight.cutscene_locked or knight.health.current <= 0
	return false


func _begin_recovery() -> void:
	_state = State.RECOVERY
	_timer = float(COMBO_RECOVERY[_combo_index])
	_cooldown = cooldown
	if hitbox:
		hitbox.monitoring = false
	# 打实的那一刀：如果玩家在判定期里已经按了跳，离地是既成事实，后摇从第一帧
	# 就收掉（与「打实从后摇开头可跳取消」同一规则，只是按键早了几帧）。
	# 挥空则保持承诺的完整后摇，沉重感不变。
	if _jump_during_swing and swing_connected():
		_jump_during_swing = false
		cancel_recovery()


func _set_lock(locked: bool) -> void:
	var host := get_parent()
	if host is Player:
		(host as Player).controller.set_commit_lock(locked)


func _tween_sword(target: float, delta: float, rate: float) -> void:
	if sword == null:
		return
	sword.rotation = lerp_angle(sword.rotation, target, 1.0 - exp(-rate * delta))


func _rest_sword(delta: float) -> void:
	_tween_sword(0.35, delta, 6.0)
