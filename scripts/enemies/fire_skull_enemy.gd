extends EnemyBase
## 火骷髅：燃着的飞头。在出生点附近沿正弦路径巡飞；骑士靠近就扑向头顶咬一口，
## 咬完拉开一口气再扑。不受墙与重力约束，自己积分位置。两刀灭。

enum State { PATROL, HUNT, LUNGE, RETREAT }

@export var bob_amp: float = 18.0
@export var aggro_range: float = 200.0
@export var hunt_speed: float = 70.0
@export var contact_range: float = 26.0
@export var retreat_time: float = 0.9
@export var arena_left: float = -INF
@export var arena_right: float = INF

const SKULL_CHAR := "fire_skull"
## 96×112 画布里骷髅实体偏左下（中心约在 (44, 68)）；0.7 缩放后把实体中心补回节点原点。
const SKULL_SCALE := Vector2(0.7, 0.7)
const SKULL_POS := Vector2(2.0, -8.0)
const FLY_FPS := 10.0
## 追的是骑士头顶上方一点，而不是脚点。
const HEAD_OFFSET := Vector2(0.0, -16.0)
const LUNGE_TIME := 0.18
const LUNGE_SPEED_K := 1.6
const LUNGE_KNOCKBACK := Vector2(70.0, -40.0)
## 追出这么多倍 aggro_range 才放弃。
const LOSE_RANGE_K := 1.4
## 水平速度死区（px/s）：头顶悬停时不左右乱翻。
const FACE_DEADZONE := 12.0
const BOB_RATE := 2.4
const SPARK_INTERVAL := 0.35
const GLOW_COLOR := Color(1.0, 0.55, 0.2)

var _state: State = State.PATROL
var _timer: float = 0.0
var _bob_t: float = 0.0
var _spark_t: float = 0.0
var _origin := Vector2.ZERO
var _facing: float = -1.0
var _glow: WorldLight

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox


func _init() -> void:
	patrol_range = 96.0
	patrol_speed = 44.0


func _enemy_ready() -> void:
	_mobile = false
	collision_mask = 0
	health.max_hp = 2
	health.heal_full()
	_origin = global_position
	hitbox.team = &"enemy"
	hitbox.damage = 1
	hitbox.disarm()
	_build_visual()
	_setup_glow()


func _build_visual() -> void:
	# 基类 _build_frame_anim 只探 "idle" 目录；火骷髅只有 fly，自己装配。
	if CharFrames.available(SKULL_CHAR, "fly"):
		_anim = FrameAnimSprite.new()
		_anim.name = "BodySprite"
		_anim.register("fly", CharFrames.anim(SKULL_CHAR, "fly"), FLY_FPS, true, SKULL_POS)
		_anim.scale = SKULL_SCALE
		_anim.play("fly")
		visual.add_child(_anim)
		_flash_target = _anim
		_hide_placeholder_rects(visual)
	elif visual.has_node("Placeholder"):
		_flash_target = visual.get_node("Placeholder") as CanvasItem


func _setup_glow() -> void:
	_glow = WorldLight.new()
	_glow.name = "SkullGlow"
	_glow.follow = &"skull"
	_glow.lit = true
	_glow.color = GLOW_COLOR
	_glow.energy = 0.5
	_glow.texture_scale = 40.0 / 32.0
	visual.add_child(_glow)
	# WorldLight._ready() 会把 shadow_enabled 重置为 true，只能入树后再关。
	_glow.shadow_enabled = false


## LevelSanity：飞行敌人不查脚下台面，只查没嵌进实体。
func is_airborne() -> bool:
	return true


func state() -> State:
	return _state


func _tick_state(delta: float) -> void:
	_bob_t += delta * BOB_RATE
	_tick_sparks(delta)
	var player := _player()
	match _state:
		State.PATROL:
			_tick_patrol(delta)
			if player != null and _dist(player) <= aggro_range:
				_state = State.HUNT
		State.HUNT:
			if player == null or _dist(player) > aggro_range * LOSE_RANGE_K:
				_state = State.PATROL
			else:
				_tick_hunt(player, delta)
		State.LUNGE:
			_timer -= delta
			global_position += velocity * delta
			if _timer <= 0.0:
				_begin_retreat(player)
		State.RETREAT:
			_timer -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 40.0 * delta)
			global_position += velocity * delta
			if _timer <= 0.0:
				_state = State.HUNT if player != null and _dist(player) <= aggro_range else State.PATROL
	_update_facing()


## 出生点两侧 patrol_range 内往返，y 跟着正弦摆。
func _tick_patrol(delta: float) -> void:
	if global_position.x < _origin.x - patrol_range:
		_dir = 1.0
	elif global_position.x > _origin.x + patrol_range:
		_dir = -1.0
	velocity.x = move_toward(velocity.x, _dir * patrol_speed, patrol_speed * 6.0 * delta)
	var want_y := _origin.y + sin(_bob_t) * bob_amp
	velocity.y = (want_y - global_position.y) * 4.0
	global_position += velocity * delta


func _tick_hunt(player: Player, delta: float) -> void:
	var to := player.global_position + HEAD_OFFSET - global_position
	if to.length() <= contact_range:
		_begin_lunge(to)
		return
	velocity = velocity.move_toward(to.normalized() * hunt_speed, hunt_speed * 4.0 * delta)
	global_position += velocity * delta


## 贴近后再往前顶一小段并开判定，保证咬得到；判定只开这一小段。
func _begin_lunge(to: Vector2) -> void:
	_state = State.LUNGE
	_timer = LUNGE_TIME
	var heading := to.normalized() if to.length() > 0.5 else Vector2(_facing, 0.0)
	velocity = heading * hunt_speed * LUNGE_SPEED_K
	var side := signf(heading.x) if absf(heading.x) > 0.05 else _facing
	hitbox.arm(Vector2(side * LUNGE_KNOCKBACK.x, LUNGE_KNOCKBACK.y))
	Sfx.play(&"swing", 0.12, -8.0)


func _begin_retreat(player: Player) -> void:
	hitbox.disarm()
	_state = State.RETREAT
	_timer = retreat_time
	var away := Vector2(-_facing, -0.6)
	if player != null:
		away = (global_position - player.global_position).normalized() + Vector2(0.0, -0.6)
	velocity = away.normalized() * hunt_speed * 0.9


func _update_facing() -> void:
	global_position.x = clampf(global_position.x, arena_left + 12.0, arena_right - 12.0)
	if velocity.x > FACE_DEADZONE:
		_facing = 1.0
	elif velocity.x < -FACE_DEADZONE:
		_facing = -1.0
	# 原图面朝左；朝右飞时水平镜像。
	visual.scale.x = -1.0 if _facing > 0.0 else 1.0


## 每 SPARK_INTERVAL 从骷髅下缘撒两粒火星。纯表现，headless 不生成。
func _tick_sparks(delta: float) -> void:
	_spark_t -= delta
	if _spark_t > 0.0:
		return
	_spark_t = SPARK_INTERVAL
	if DisplayServer.get_name() == "headless":
		return
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	if host == null:
		return
	for i in 2:
		var mote := FireMote.new()
		mote.position = global_position + Vector2(randf_range(-8.0, 8.0), randf_range(0.0, 8.0))
		mote.z_index = Fx.FX_Z
		host.add_child(mote)


func _dist(player: Player) -> float:
	return global_position.distance_to(player.global_position)


func _player() -> Player:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or p.health.current <= 0:
		return null
	return p


func _on_died() -> void:
	_death_burst([] as Array[Texture2D], 12.0, false, 0.0, "火骷髅灭了")


## 一粒从火骷髅身上落下的火星：加法混合的小方块，往下飘一点就熄。
class FireMote extends Node2D:
	var _vel := Vector2.ZERO
	var _age := 0.0
	var _life := 0.45


	func _init() -> void:
		_life = randf_range(0.3, 0.55)
		_vel = Vector2(randf_range(-14.0, 14.0), randf_range(18.0, 40.0))


	func _ready() -> void:
		var half := randf_range(0.8, 1.4)
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half),
		])
		poly.color = Palette.EMBER.lerp(Palette.TOXIC, randf() * 0.6)
		poly.material = Fx.additive_mat()
		add_child(poly)


	func _process(delta: float) -> void:
		_age += delta
		if _age >= _life:
			queue_free()
			return
		_vel.y += 60.0 * delta
		position += _vel * delta
		modulate.a = 1.0 - _age / _life
