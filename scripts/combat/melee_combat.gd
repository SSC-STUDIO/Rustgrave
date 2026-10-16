class_name MeleeCombat
extends Node2D
## Heavy slash with wind-up, active (parry) frames, and recovery.
## Parry is not a separate button — it is the active window of this swing.

enum State { IDLE, WINDUP, ACTIVE, RECOVERY }

@export var windup_time: float = 0.18
@export var active_time: float = 0.12
@export var recovery_time: float = 0.26
@export var cooldown: float = 0.40
@export var damage: int = 1

## Three-hit chain: index 0..2. Finishing blow (2) hits harder and lingers.
const COMBO_WINDUP := [0.18, 0.14, 0.30]
const COMBO_ACTIVE := [0.12, 0.12, 0.17]
const COMBO_RECOVERY := [0.26, 0.20, 0.46]
const COMBO_DAMAGE := [1, 1, 2]
const ATTACK_BUFFER_TIME := 0.16
const LINK_EARLY_TIME := 0.12

var _state: State = State.IDLE
var _timer: float = 0.0
var _cooldown: float = 0.0
var _combo_index: int = 0
var _link_buffered: bool = false
var _attack_buffer: float = 0.0
var _ignore_attack_until_release := false

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
		hitbox.monitoring = false
	var hp := get_parent().get_node_or_null("Health") as Health
	if hp != null:
		hp.died.connect(cancel_attack)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		clear_attack_buffer()


## Pause/cutscene boundaries discard queued presses, including a held button.
func clear_attack_buffer() -> void:
	_attack_buffer = 0.0
	_link_buffered = false
	_ignore_attack_until_release = Input.is_action_pressed("attack")


func cancel_attack() -> void:
	clear_attack_buffer()
	_state = State.IDLE
	_combo_index = 0
	_timer = 0.0
	if hitbox != null:
		hitbox.monitoring = false
	_set_lock(false)


## One press queues at most one slash, without shortening any committed phase.
func request_attack() -> bool:
	if _host_locked() or get_tree().paused or _ignore_attack_until_release:
		return false
	if _state == State.IDLE:
		if start_swing():
			_attack_buffer = 0.0
		else:
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
	if host is Player:
		var knight := host as Player
		knight.toxin.purify(0.12)
		knight.resonance.pulse()
		knight.controller.grant_air_jump()
	GameEvents.parried.emit(bolt, actor)
	GameEvents.announcement.emit("弹反！")
	Sfx.play(&"parry")
	return true


func is_busy() -> bool:
	return _state != State.IDLE


func is_parry_window() -> bool:
	return _state == State.ACTIVE and not _host_locked()


func _physics_process(delta: float) -> void:
	tick(delta)


## Advance the swing state machine by one frame.
## Public so tests (and future AI/input shims) can drive it without Input.
func tick(delta: float) -> void:
	if _host_locked():
		cancel_attack()
		return
	_attack_buffer = maxf(0.0, _attack_buffer - delta)
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if not Input.is_action_pressed("attack"):
		_ignore_attack_until_release = false
	if Input.is_action_just_pressed("attack"):
		request_attack()

	match _state:
		State.IDLE:
			_rest_sword(delta)
			if _attack_buffer > 0.0 and start_swing():
				_attack_buffer = 0.0
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
					_combo_index = 0
					_state = State.IDLE
					_set_lock(false)


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
	_state = State.WINDUP
	_timer = float(COMBO_WINDUP[_combo_index])
	_set_lock(true)
	GameEvents.swing_started.emit(_combo_index)
	Sfx.play(&"swing")


func _begin_active() -> void:
	_state = State.ACTIVE
	_timer = float(COMBO_ACTIVE[_combo_index])
	if hitbox:
		var bonus := 0
		var face := 1.0
		var host := get_parent()
		var pot := 0.0
		if host is Player:
			var knight := host as Player
			face = float(knight.controller.facing)
			pot = knight.toxin.potency()
			if pot >= 0.5:
				bonus = 1
		hitbox.damage = int(COMBO_DAMAGE[_combo_index]) + bonus
		hitbox.already_hit.clear()
		hitbox.monitoring = true
		var power := 150.0 if _combo_index >= 2 else 90.0
		if pot >= 0.85 and _combo_index >= 2:
			power *= 1.35
		hitbox.knockback = Vector2(face * power, -40.0 if _combo_index >= 2 else -24.0)
		if host is Player:
			(host as Player).on_melee_active(_combo_index)


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
