class_name FlyingDemonEnemy
extends EnemyBase
## Airborne gargoyle-demon that patrols the skies and perches above hazards.
## Keeps flapping while it winds up, swoops, then returns to its patrol height.

## 像素化变体（idle 72x65，身高约 55px = 骑士的 1.5 倍）：原 160x144 版本身高 124px
## （骑士 3.4 倍）、像素颗粒也比其它敌人细得多，和全场格格不入。内容在画布里基本居中，
## 悬停中心就是节点原点；attack 帧是青色火焰喷吐，与俯冲读招不是一回事，故不使用。
const DEMON_CHAR := "flying_demon_px"
const DEMON_POS := Vector2(0.0, 0.0)
## 俯冲前摇：猩红染色 + 翅膀加速扇动 + 身体略微膨胀。前摇时长取自 CombatRules.TELEGRAPH。
const ATTACK_WINDUP := 0.55
const ATTACK_TINT := Color(1.6, 0.5, 0.55)
const ATTACK_SWELL := 1.12
## 俯冲落空 / 撞墙后的喘息：悬停不动，头顶金箭头。
const RECOVERY_TIME := 1.0

enum State { PATROL, AGGRO, ATTACK, SWOOP, RECOVERY }

@export var fly_speed: float = 48.0
@export var aggro_range: float = 240.0
@export var attack_interval: float = 2.4
@export var swoop_speed: float = 120.0
## 追踪时人在正下方，dx 每帧变号，翅膀就左右乱翻。死区内只悬停不转向，
## 且两次转向至少隔 FLIP_COOLDOWN。
const FACE_DEADZONE := 16.0
const FLIP_COOLDOWN := 0.35

var _state: State = State.PATROL
var _state_timer: float = 0.0
var _shoot_timer: float = 0.0
var _origin_y: float = 0.0
var _hover_t: float = 0.0
var _target_player: Player = null
var _swoop_direction := Vector2.DOWN
var _flip_cooldown: float = 0.0

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox


## 飞行的小型敌人，钩锁能拽到面前。
func is_yankable() -> bool:
	return true


func _enemy_ready() -> void:
	health.max_hp = 3
	health.heal_full()
	_origin_y = global_position.y
	_shoot_timer = randf_range(1.0, attack_interval)
	if hitbox != null:
		hitbox.team = &"enemy"
		hitbox.damage = 1
		hitbox.monitoring = false
	_build_visual()


func _build_visual() -> void:
	_anim = _build_frame_anim(DEMON_CHAR, [
		["idle", "idle", 10.0, true, DEMON_POS],
	])
	if _anim != null:
		_anim.scale = Vector2.ONE
		visual.add_child(_anim)
		_flash_target = _anim
		_hide_placeholder_rects(visual)
		_anim.play("idle")
	elif visual.has_node("Placeholder"):
		_flash_target = visual.get_node("Placeholder") as CanvasItem


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if Director.is_input_locked():
		return
	if _hurt_lock > 0.0:
		_hurt_lock = maxf(0.0, _hurt_lock - delta)
		move_and_slide()
		_after_move()
		return
	_tick_state(delta)
	move_and_slide()
	_after_move()


func _tick_state(delta: float) -> void:
	_hover_t += delta * 2.5
	_flip_cooldown = maxf(0.0, _flip_cooldown - delta)
	var hover_offset := sin(_hover_t) * 14.0
	_poll_player()

	match _state:
		State.PATROL:
			_patrol_step()
			velocity.y = ((_origin_y + hover_offset) - global_position.y) * 4.0
			if _target_player != null:
				_state = State.AGGRO
				_state_timer = 0.5
		State.AGGRO:
			if _target_player == null or not is_instance_valid(_target_player):
				_state = State.PATROL
				velocity = Vector2.ZERO
				return
			var dx := _target_player.global_position.x - global_position.x
			if absf(dx) > FACE_DEADZONE:
				_face(signf(dx))
				velocity.x = move_toward(velocity.x, _dir * fly_speed * 0.8, 160.0 * delta)
			else:
				# Overhead: hold position instead of hunting the sign of dx.
				velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
			velocity.y = ((_origin_y + hover_offset - 20.0) - global_position.y) * 4.0
			_shoot_timer -= delta
			if _shoot_timer <= 0.0:
				_start_attack()
		State.ATTACK:
			if _target_player == null or not is_instance_valid(_target_player):
				_state = State.RECOVERY
				_state_timer = 0.2
				_clear_attack_look()
				return
			_state_timer -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)
			if _state_timer <= 0.0:
				_state = State.SWOOP
				_state_timer = 0.85
				_swoop_direction = (_target_player.global_position + Vector2(0, -14) - global_position).normalized()
				if absf(_swoop_direction.x) > 0.2:
					_face(signf(_swoop_direction.x), true)
				hitbox.arm(_swoop_direction * 75.0)
		State.SWOOP:
			velocity = _swoop_direction * swoop_speed
			_state_timer -= delta
			if _state_timer <= 0.0 or is_on_wall() or is_on_floor():
				hitbox.disarm()
				_state = State.RECOVERY
				_state_timer = RECOVERY_TIME
				show_opening(RECOVERY_TIME)
				_clear_attack_look()
		State.RECOVERY:
			_state_timer -= delta
			velocity.y = ((_origin_y + hover_offset) - global_position.y) * 3.0
			if _state_timer <= 0.0:
				_state = State.AGGRO if _target_player != null else State.PATROL
				_shoot_timer = attack_interval


func _after_move() -> void:
	if visual != null:
		visual.scale.x = -_dir if _dir != 0.0 else 1.0


## Turn only when the heading really changed and the last turn has settled.
## `force` is for the swoop commit, which must face where it dives.
func _face(dir: float, force: bool = false) -> void:
	if dir == 0.0 or dir == _dir:
		return
	if _flip_cooldown > 0.0 and not force:
		return
	_dir = dir
	_flip_cooldown = FLIP_COOLDOWN


func _poll_player() -> void:
	var p := knight()
	if p != null and not p.is_invincible() and p.health.current > 0:
		if global_position.distance_to(p.global_position) <= aggro_range:
			_target_player = p
			return
	_target_player = null


func _start_attack() -> void:
	_state = State.ATTACK
	_state_timer = ATTACK_WINDUP
	begin_telegraph(&"flying_demon", ATTACK_WINDUP)
	if _anim != null:
		_anim.play("idle")
		_anim.set_fps("idle", 15.0)
		_anim.modulate = ATTACK_TINT
		_anim.scale = Vector2(ATTACK_SWELL, ATTACK_SWELL)
	Sfx.play_at(&"swing", global_position, 0.12, -4.0)


func _clear_attack_look() -> void:
	if _anim == null:
		return
	_anim.modulate = Color.WHITE
	_anim.scale = Vector2.ONE
	_anim.set_fps("idle", 10.0)


## 受击白闪落回当前姿态色：前摇中不被洗成死白。
func _flash_restore_color() -> Color:
	return ATTACK_TINT if _state == State.ATTACK else Color.WHITE


func _on_died() -> void:
	GameEvents.announcement.emit("恶魔在锈风中坠解")
	_death_burst([] as Array[Texture2D], 12.0, false, 0.0, "")
