extends EnemyBase
## 骸骨：埋在墓土里的锈骨架。骑士走近才从土里爬起来（起身期间不可攻击也不可受伤），
## 之后拖着步子追骑士，贴身即咬；碰到台缘或墙就折返几步再追。两刀散成一把锈钉。

enum State { BURIED, RISE, WALK, TURN }

@export var wake_range: float = 150.0
@export var walk_speed: float = 36.0
@export var contact_damage: int = 1

const SKEL_CHAR := "skeleton"
## 44×52 画布，脚底贴画布底边：centered Sprite 中心抬 26px 让脚落在节点原点。
const SKEL_POS := Vector2(0.0, -26.0)
const RISE_FPS := 9.0
const WALK_FPS := 10.0
## 贴身咬：水平距离进这个范围就开一次判定，隔 CONTACT_COOLDOWN 再开一次。
const CONTACT_RANGE := 22.0
const CONTACT_REACH_Y := 30.0
const CONTACT_COOLDOWN := 0.7
const CONTACT_KNOCKBACK := Vector2(90.0, -60.0)
## 撞墙/到台缘后反向走这么久再回头追。
const BACKSTEP_TIME := 0.55
## 骑士就在头顶/脚下时不左右抖。
const CHASE_DEADZONE := 6.0
const LEDGE_PROBE_AHEAD := 10.0
const LEDGE_PROBE_TOP := 6.0
const LEDGE_PROBE_BOTTOM := 10.0

var _state: State = State.BURIED
var _timer: float = 0.0
var _contact_cd: float = 0.0

@onready var visual: Node2D = $Visual
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox


func _enemy_ready() -> void:
	health.max_hp = 2
	health.heal_full()
	hitbox.team = &"enemy"
	hitbox.damage = contact_damage
	hitbox.disarm()
	_build_visual()
	_set_tangible(false)
	visual.visible = false


func _build_visual() -> void:
	_anim = _build_actions(SKEL_CHAR, "walk", [
		["rise", "rise", RISE_FPS, false, SKEL_POS],
		["walk", "walk", WALK_FPS, true, SKEL_POS],
	])
	if _anim != null:
		visual.add_child(_anim)
		_flash_target = _anim
		_hide_placeholder_rects(visual)
	elif visual.has_node("Placeholder"):
		_flash_target = visual.get_node("Placeholder") as CanvasItem


## 基类 _build_frame_anim 只用 "idle" 目录探测素材是否存在；骸骨没有 idle，
## 这里按指定动作探测后照同样的规格表装配。
func _build_actions(char_name: String, probe: String, specs: Array) -> FrameAnimSprite:
	if not CharFrames.available(char_name, probe):
		return null
	var anim := FrameAnimSprite.new()
	anim.name = "BodySprite"
	for spec in specs:
		anim.register(String(spec[0]), CharFrames.anim(char_name, String(spec[1])),
				float(spec[2]), bool(spec[3]), spec[4])
	return anim


func state() -> State:
	return _state


func is_risen() -> bool:
	return _state == State.WALK or _state == State.TURN


## 埋着/起身时没有身体、不可受伤；站起来才是实体。
func _set_tangible(on: bool) -> void:
	hurtbox.monitoring = on
	hurtbox.monitorable = on
	collision_layer = 4 if on else 0


func _tick_state(delta: float) -> void:
	var player := _player()
	match _state:
		State.BURIED:
			velocity.x = 0.0
			if player != null and global_position.distance_to(player.global_position) <= wake_range:
				_rise()
		State.RISE:
			velocity.x = 0.0
			_timer -= delta
			if _timer <= 0.0:
				_state = State.WALK
				_set_tangible(true)
				if _anim != null:
					_anim.play("walk")
		State.WALK:
			_tick_walk(player)
			_tick_contact(player, delta)
		State.TURN:
			_tick_turn(delta)
			_tick_contact(player, delta)


func _tick_walk(player: Player) -> void:
	if player == null:
		velocity.x = 0.0
		return
	var dx := player.global_position.x - global_position.x
	if absf(dx) <= CHASE_DEADZONE:
		velocity.x = 0.0
		return
	_dir = signf(dx)
	if _wall_ahead() or not _ground_ahead():
		_dir = -_dir
		_state = State.TURN
		_timer = BACKSTEP_TIME
	velocity.x = _dir * walk_speed


## 折返：背对骑士走几步；背后也没路就原地站到时间结束。
func _tick_turn(delta: float) -> void:
	_timer -= delta
	if _wall_ahead() or not _ground_ahead():
		velocity.x = 0.0
	else:
		velocity.x = _dir * walk_speed
	if _timer <= 0.0:
		_state = State.WALK


## 贴身时开一次判定；Hurtbox 的 already_hit 只放一次伤害，所以隔一口气重新 arm。
func _tick_contact(player: Player, delta: float) -> void:
	_contact_cd = maxf(0.0, _contact_cd - delta)
	if player == null:
		hitbox.disarm()
		return
	var to := player.global_position - global_position
	if absf(to.x) <= CONTACT_RANGE and absf(to.y) <= CONTACT_REACH_Y:
		if _contact_cd <= 0.0:
			var side := signf(to.x) if to.x != 0.0 else _dir
			hitbox.arm(Vector2(side * CONTACT_KNOCKBACK.x, CONTACT_KNOCKBACK.y))
			_contact_cd = CONTACT_COOLDOWN
	elif hitbox.monitoring:
		hitbox.disarm()


## 只认前进方向上的墙：刚背着墙转身那帧 is_on_wall 仍为 true，不能当成前面有墙。
func _wall_ahead() -> bool:
	return is_on_wall() and signf(get_wall_normal().x) == -_dir


## 前脚下方探地面（layer 1）；探不到就是台缘。空中不判，免得被击飞时乱转。
func _ground_ahead() -> bool:
	if not is_on_floor():
		return true
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(_dir * LEDGE_PROBE_AHEAD, -LEDGE_PROBE_TOP)
	var to := global_position + Vector2(_dir * LEDGE_PROBE_AHEAD, LEDGE_PROBE_BOTTOM)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1, [get_rid()])
	return not space.intersect_ray(query).is_empty()


func _rise() -> void:
	_state = State.RISE
	visual.visible = true
	var frames := CharFrames.anim(SKEL_CHAR, "rise").size()
	_timer = float(frames) / RISE_FPS if frames > 0 else 0.6
	if _anim != null:
		_anim.play("rise", true)
	Fx.dust_puff(global_position, -PI * 0.5)
	Sfx.play(&"gate", 0.12, -10.0)


func _player() -> Player:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or p.health.current <= 0:
		return null
	return p


## 原图面朝左；朝右走时水平镜像。
func _after_move() -> void:
	if is_risen():
		visual.scale.x = -1.0 if _dir > 0.0 else 1.0


## 埋在土里的骨头不该把踩过去的骑士挤开。
func _separate_from_player() -> void:
	if is_risen():
		super()


func _on_died() -> void:
	_death_burst([] as Array[Texture2D], 12.0, false, 0.0, "骸骨散成一把锈钉")
