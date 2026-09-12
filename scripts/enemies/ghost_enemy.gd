class_name GhostEnemy
extends EnemyBase
## 地窟幽魂：不受墙与重力约束，从苔墙里凝出，慢慢飘向骑士，贴近时抬手一击。
## 追得太久会散成雾，隔一口气再从骑士背后凝出来——逼玩家转身，而不是一直后退。
## 只在实体阶段可被打（2 刀）；凝出/散去期间无判定。

const GHOST_CHAR := "ghost"
## 64×80 帧：身体占 y 19–61，中心恰在画布中心，基线零偏移即可。
const GHOST_POS := Vector2(0.0, 0.0)

enum State { DORMANT, APPEAR, HAUNT, ATTACK, VANISH, GONE }

@export var wake_range: float = 210.0
@export var drift_speed: float = 34.0
@export var lunge_speed: float = 96.0
@export var attack_range: float = 30.0
## 一次实体追猎的时长；到点就散雾重定位。
@export var haunt_time: float = 6.5
@export var gone_time: float = 1.2
## Optional encounter bounds; defaults preserve unrestricted haunt routes.
@export var arena_left: float = -INF
@export var arena_right: float = INF
## 重新凝出时落在骑士背后这么远。
const REPHASE_OFFSET := 88.0
const REPHASE_HEIGHT := 26.0
const APPEAR_FPS := 10.0
const IDLE_FPS := 8.0
const ATTACK_FPS := 10.0
const VANISH_FPS := 12.0
const ATTACK_WINDUP := 0.28
const ATTACK_ACTIVE := 0.22
const ATTACK_COOLDOWN := 1.1
const FACE_DEADZONE := 10.0
const BOB_AMP := 5.0
const BOB_RATE := 2.2
const GLOW_COLOR := Color(0.45, 0.95, 1.0)

var _state: State = State.DORMANT
var _timer: float = 0.0
var _bob_t: float = 0.0
var _attack_cd: float = 0.0
var _facing: float = -1.0
var _rephases: int = 0

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
var _glow: WorldLight


func _enemy_ready() -> void:
	_mobile = false
	collision_mask = 0
	health.max_hp = 2
	health.heal_full()
	if hitbox != null:
		hitbox.team = &"enemy"
		hitbox.damage = 1
		hitbox.disarm()
	_build_visual()
	_setup_glow()
	_set_tangible(false)
	visual.visible = false


func _build_visual() -> void:
	_anim = _build_frame_anim(GHOST_CHAR, [
		["appear", "appear", APPEAR_FPS, false, GHOST_POS],
		["idle", "idle", IDLE_FPS, true, GHOST_POS],
		["attack", "attack", ATTACK_FPS, false, GHOST_POS],
		["vanish", "vanish", VANISH_FPS, false, GHOST_POS],
	])
	if _anim != null:
		visual.add_child(_anim)
		_flash_target = _anim
		_hide_placeholder_rects(visual)
	elif visual.has_node("Placeholder"):
		_flash_target = visual.get_node("Placeholder") as CanvasItem


func _setup_glow() -> void:
	_glow = WorldLight.new()
	_glow.name = "SpiritGlow"
	_glow.follow = &"ghost"
	_glow.lit = true
	_glow.color = GLOW_COLOR
	_glow.energy = 0.55
	_glow.texture_scale = 44.0 / 32.0
	_glow.shadow_enabled = false
	visual.add_child(_glow)


func state() -> State:
	return _state


func is_tangible() -> bool:
	return _state == State.HAUNT or _state == State.ATTACK


func rephase_count() -> int:
	return _rephases


func _set_tangible(on: bool) -> void:
	if hurtbox != null:
		hurtbox.monitoring = on
		hurtbox.monitorable = on
	collision_layer = 4 if on else 0


func _tick_state(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_bob_t += delta * BOB_RATE
	var player := _player()
	match _state:
		State.DORMANT:
			if player != null and global_position.distance_to(player.global_position) <= wake_range:
				_appear()
		State.APPEAR:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.HAUNT
				_timer = haunt_time
				_set_tangible(true)
				if _anim != null:
					_anim.play("idle")
		State.HAUNT:
			_timer -= delta
			if player == null:
				velocity = velocity.move_toward(Vector2.ZERO, 60.0 * delta)
			else:
				var target := player.global_position + Vector2(0.0, -12.0 + sin(_bob_t) * BOB_AMP)
				var to := target - global_position
				# 三分之一秒加到全速：够飘，又不至于追不上一个后退的人。
				var want := to.normalized() * drift_speed if to.length() > 2.0 else Vector2.ZERO
				velocity = velocity.move_toward(want, drift_speed * 3.0 * delta)
				_face_toward(player)
				if to.length() <= attack_range and _attack_cd <= 0.0:
					_begin_attack(to)
			global_position += velocity * delta
			if _timer <= 0.0:
				_vanish()
		State.ATTACK:
			_timer -= delta
			global_position += velocity * delta
			velocity = velocity.move_toward(Vector2.ZERO, 240.0 * delta)
			if _timer <= ATTACK_ACTIVE and not hitbox.monitoring and _timer > 0.0:
				hitbox.arm(Vector2(_facing * 60.0, -40.0))
			if _timer <= 0.0:
				hitbox.disarm()
				_attack_cd = ATTACK_COOLDOWN
				_state = State.HAUNT
				if _anim != null:
					_anim.play("idle")
		State.VANISH:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.GONE
				_timer = gone_time
				visual.visible = false
		State.GONE:
			_timer -= delta
			if _timer <= 0.0:
				_rephase(player)
	global_position.x = clampf(global_position.x, arena_left + 12.0, arena_right - 12.0)


func _player() -> Player:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or p.health.current <= 0 or p.global_position.x < arena_left or p.global_position.x > arena_right:
		return null
	return p


func _appear() -> void:
	_state = State.APPEAR
	visual.visible = true
	velocity = Vector2.ZERO
	var frames := CharFrames.anim(GHOST_CHAR, "appear").size()
	_timer = float(maxi(frames, 1)) / APPEAR_FPS if frames > 0 else 0.4
	if _anim != null:
		_anim.play("appear", true)
	Sfx.play(&"gate", 0.1, -8.0)


func _begin_attack(to: Vector2) -> void:
	_state = State.ATTACK
	_timer = ATTACK_WINDUP + ATTACK_ACTIVE
	velocity = to.normalized() * lunge_speed
	if _anim != null:
		_anim.play("attack", true)
	Sfx.play(&"swing", 0.1, -6.0)


func _vanish() -> void:
	_state = State.VANISH
	_set_tangible(false)
	hitbox.disarm()
	velocity = Vector2.ZERO
	var frames := CharFrames.anim(GHOST_CHAR, "vanish").size()
	_timer = float(maxi(frames, 1)) / VANISH_FPS if frames > 0 else 0.4
	if _anim != null:
		_anim.play("vanish", true)


## 从骑士背后凝出：骑士面朝哪边，就落在相反的一侧。
func _rephase(player: Player) -> void:
	_rephases += 1
	if player != null:
		var behind := -signf(player.visual.scale.x)
		if behind == 0.0:
			behind = -1.0
		global_position = player.global_position + Vector2(behind * REPHASE_OFFSET, -REPHASE_HEIGHT)
		_facing = -behind
	_appear()


func _face_toward(player: Player) -> void:
	var dx := player.global_position.x - global_position.x
	if absf(dx) > FACE_DEADZONE:
		_facing = signf(dx)


func _after_move() -> void:
	pass


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if visual != null:
		visual.scale.x = -_facing if _facing != 0.0 else 1.0


func _on_died() -> void:
	var frames := CharFrames.anim(GHOST_CHAR, "vanish")
	_death_burst(frames, VANISH_FPS, _facing > 0.0, 0.0, "幽魂散进苔雾里")
