class_name GearShieldEnemy
extends EnemyBase
## Rust gear-shield guard. A slow, armored sentinel that guards one facing:
## frontal strikes and deflected bolts are absorbed by its shield, but dodge
## around back and it is plain flesh. Skilled players can reflect its own bolt
## back into the shield to stagger it open - the teachable punish window.
##
## Mirror of GDD "齿轮盾卫": don't trade blows head-on; either flank it or
## feed it its own shot.

enum State { PATROL, BLOCK, CHARGE, STAGGER }

const PROJECTILE_SCENE := preload("res://scenes/combat/Projectile.tscn")

## Undead Executioner 像素帧动画（Kronovi，原图面朝左，画布 100x100、
## 脚底距底边 16~17px）：idle 4 / idle2(举斧格挡) 8 / summon(蓄力施法) 5 /
## death 18。身体中心在画布 x≈56.5，flip_h 后补偿 +6px。
const EXEC_CHAR := "gear_shield_executioner"
const EXEC_POS := Vector2(6.0, -34.0)
const EXEC_DEATH_BASELINE := -33.0

@export var aggro_range: float = 300.0
@export var shoot_interval: float = 2.4
@export var charge_time: float = 0.5
@export var stagger_time: float = 1.5
@export var projectile_speed: float = 145.0

var _state: State = State.PATROL
var _timer: float = 0.0
var _shoot_timer: float = 0.0
var _shield_facing: int = -1
var _blocking: bool = false
var _flicker_tween: Tween
## 格挡/蓄力指示的目标：有帧动画时是机体 Sprite（举斧姿态自带格挡语义），
## 否则回退为占位 Shield 多边形。
var _indicator: CanvasItem

@onready var visual: Node2D = $Visual
@onready var shield: CanvasItem = $Visual/Shield
@onready var eye: ColorRect = $Visual/Eye
@onready var hurtbox: Hurtbox = $Hurtbox


func _init() -> void:
	patrol_speed = 26.0  # 重甲哨兵拖着步子巡逻，慢于基类默认


func _enemy_ready() -> void:
	health.max_hp = 4
	health.heal_full()
	_shoot_timer = shoot_interval * 0.6
	hurtbox.block_check = _shield_block_check
	_build_visual()


## 两级回退：Executioner 帧动画 → 场景内 ColorRect/Polygon2D 占位（headless/缺素材）。
## 帧动画自带巨斧与重甲（举斧 idle2 就是格挡姿态），Shield 占位多边形随之隐藏；
## 格挡/蓄力指示改为整体染色。
func _build_visual() -> void:
	_indicator = shield
	_anim = _build_frame_anim(EXEC_CHAR, [
		["idle", "", 8.0, true, EXEC_POS],
		["block", "idle2", 8.0, true, EXEC_POS],
		# 蓄力施法 5 帧铺满整个 charge_time，最后一帧正好是释放。
		["charge", "summon", 5.0 / maxf(charge_time, 0.1), false, EXEC_POS],
	])
	if _anim == null:
		return
	_anim.play("idle")
	# 原图面朝左；Visual 的 scale.x=1 约定为面朝右（盾在 +x 侧），先水平翻转。
	_anim.flip_h = true
	visual.add_child(_anim)
	visual.move_child(_anim, 0)
	_hide_placeholder_rects(visual)
	shield.visible = false
	_indicator = _anim


## 状态 → 动画：巡逻待机 / 举斧格挡 / 蓄力施法 / 硬直（拖慢待机 + 白闪已由 hit 表达）。
func _update_anim() -> void:
	if _anim == null:
		return
	match _state:
		State.PATROL:
			_anim.set_fps("idle", 8.0)
			_anim.play("idle")
			# 巡逻期跟随行走方向转身（进入对峙后由 _update_visual 面向玩家）。
			visual.scale.x = 1.0 if _dir > 0.0 else -1.0
		State.BLOCK:
			_anim.play("block")
		State.CHARGE:
			_anim.play("charge")
		State.STAGGER:
			_anim.set_fps("idle", 3.0)
			_anim.play("idle")


func _tick_state(delta: float) -> void:
	if _dead:
		return
	match _state:
		State.PATROL:
			_tick_patrol(delta)
		State.BLOCK:
			_tick_block(delta)
		State.CHARGE:
			_tick_charge(delta)
		State.STAGGER:
			_tick_stagger(delta)


func _after_move() -> void:
	_update_anim()


func _tick_patrol(_delta: float) -> void:
	_set_blocking(false)
	_patrol_step()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null and global_position.distance_to(player.global_position) < aggro_range:
		_enter_block(player)


func _enter_block(player: Player) -> void:
	_state = State.BLOCK
	_shield_facing = 1 if player.global_position.x >= global_position.x else -1
	_timer = 0.0
	_shoot_timer = shoot_interval * 0.5
	_update_visual()


func _tick_block(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	_shoot_timer -= delta
	if _shoot_timer <= 0.0:
		_state = State.CHARGE
		_timer = charge_time
		_flicker_charge()
		return
	_set_blocking(true)


func _tick_charge(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	_set_blocking(true)
	_timer -= delta
	if _timer <= 0.0:
		_fire()
		_state = State.BLOCK
		_shoot_timer = shoot_interval


func _tick_stagger(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_timer -= delta
	if _timer <= 0.0:
		_state = State.BLOCK
		_set_blocking(true)
		_update_visual()


func _fire() -> void:
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_tree().current_scene
	host.add_child(proj)
	var player := get_tree().get_first_node_in_group("player") as Player
	# 帧动画机体更高大：弹体从抬手处出膛；占位机体沿用旧出膛点。
	var origin := global_position + (Vector2(_shield_facing * 18.0, -30.0)
			if _anim != null else Vector2(_shield_facing * 14.0, -14.0))
	var target := player.global_position + Vector2(0, -12) if player != null \
			else origin + Vector2(_shield_facing * 40.0, 0)
	proj.setup(origin, target - origin, projectile_speed, &"enemy", self)
	Sfx.play(&"spit")


func _shield_block_check(attacker: Node, _amount: int) -> bool:
	if not _blocking:
		return false
	if not _is_from_front(attacker):
		return false
	if attacker is Projectile and (attacker as Projectile).team == &"player":
		Sfx.play(&"parry")
		attacker.queue_free()
		_enter_stagger()
	else:
		Fx.hit_sparks(global_position + Vector2(_shield_facing * 9.0, -12.0))
		Sfx.play(&"parry")
	_flash_shield()
	return true


func _enter_stagger() -> void:
	_state = State.STAGGER
	_timer = stagger_time
	_set_blocking(false)
	GameEvents.announcement.emit("弹反击碎了齿轮盾！")
	GameEvents.hit.emit(self, self, 0)


func _is_from_front(attacker: Node) -> bool:
	var side: float
	if attacker is Projectile:
		# An incoming bolt travels *toward* us: its velocity is opposite
		# the side it arrived from. Position can already overlap our centre.
		side = -(attacker as Projectile).velocity.x
	elif attacker is Node2D:
		side = (attacker as Node2D).global_position.x - global_position.x
	else:
		return false
	return signf(side) == float(_shield_facing)


func _set_blocking(b: bool) -> void:
	if _blocking == b:
		return
	_blocking = b
	_refresh_indicator()


func _update_visual() -> void:
	visual.scale.x = -1.0 if _shield_facing == -1 else 1.0
	eye.color = Palette.EMBER


func _flash_shield() -> void:
	_kill_flicker()
	_flicker_tween = create_tween()
	_flicker_tween.tween_property(_indicator, "modulate", Color(0.9, 0.6, 0.3, 1.0), 0.04)
	_flicker_tween.tween_callback(_refresh_indicator)


func _flicker_charge() -> void:
	_kill_flicker()
	_flicker_tween = create_tween()
	_flicker_tween.tween_property(_indicator, "modulate", Palette.TOXIC, charge_time * 0.5)
	_flicker_tween.tween_property(_indicator, "modulate", Palette.EMBER, charge_time * 0.5)


func _kill_flicker() -> void:
	if _flicker_tween != null and _flicker_tween.is_valid():
		_flicker_tween.kill()


## 受击白闪走基类；先掐掉格挡/蓄力指示的染色 tween，避免两股 tween 抢色。
## 闪完落回当前姿态色，避免蓄力/举盾被洗成死白。
func _flash_white() -> void:
	_kill_flicker()
	super()
	_refresh_indicator()


## 格挡冷钢 / 蓄力余烬 / 收盾原色。白闪作用在 Visual 父节点，这里只钉指示器，避免叠乘。
func _refresh_indicator() -> void:
	if _indicator == null:
		return
	if _state == State.CHARGE:
		_indicator.modulate = Palette.EMBER
		return
	if _indicator == shield:
		_indicator.modulate = Color(1, 1, 1, 1.0 if _blocking else 0.35)
		return
	_indicator.modulate = Color(0.82, 0.95, 1.08) if _blocking else Color.WHITE


func _on_died() -> void:
	# 尸体演出：18 帧死亡（化作黑球消散），随当前朝向镜像。
	# 原图面朝左：面朝右（_shield_facing==1）时需要翻转。
	_death_burst(CharFrames.anim(EXEC_CHAR, "death"), 14.0,
			_shield_facing == 1, EXEC_DEATH_BASELINE, "齿轮盾卫崩塌成废铁")
