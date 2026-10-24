class_name ScrapperEnemy
extends EnemyBase
## Rust plate-brute: patrols its beat, then charges. Slamming into a wall —
## or skidding to a stop at a ledge / toxin pit — leaves it stunned, the
## punish window that teaches spacing.

enum State { PATROL, WINDUP, CHARGE, STUN }

@export var charge_speed: float = 235.0
@export var aggro_range: float = 215.0
@export var windup_time: float = 0.45
@export var charge_max_time: float = 0.95
@export var stun_time: float = 0.95
@export var re_aggro_cooldown: float = 1.15
@export var contact_damage: int = 1

## 冲锋探针：身前 20px 处、从膝盖(-16)扫到脚下(+10)的竖直射线。
const CHARGE_PROBE_AHEAD := 20.0
const CHARGE_PROBE_TOP := 16.0
const CHARGE_PROBE_BOTTOM := 10.0
## 危害区（毒池 ToxinPool）所在的物理层。
const HAZARD_LAYER := 128
## 像素前摇：贴图路径会藏掉 Eye 色块，改用整体染色 + 微蹲表达蓄势。
const WINDUP_TINT := Color(1.35, 0.85, 0.45)
const WINDUP_BODY_SCALE := Vector2(1.08, 0.92)
const CHARGE_KNOCKBACK_X := 120.0
const CHARGE_KNOCKBACK_Y := -32.0
## 冲满一程却没撞上东西时的喘息（撞墙 / 坑口走 stun_time）。
const MISS_STUN_TIME := 0.5

## Hell Hound 像素帧动画（ansimuz，原图面朝左）：idle 6 / walk 12 / run 5 / jump 5。
## 画布 64x32（run 67x32、jump 78x48），脚底均贴画布底边。
const HOUND_CHAR := "scrapper_hell_hound"
const HOUND_POS := Vector2(0.0, -16.0)        # 32 高画布 → 中心 -16
const HOUND_JUMP_POS := Vector2(0.0, -24.0)   # jump 画布 48 高

var _state: State = State.PATROL
var _timer: float = 0.0
var _cooldown: float = 0.0

@onready var charge_box: Hitbox = $ChargeBox
@onready var visual: Node2D = $Visual
@onready var eye: ColorRect = $Visual/Eye


func _enemy_ready() -> void:
	health.max_hp = 3
	health.heal_full()
	charge_box.team = &"enemy"
	charge_box.damage = contact_damage
	charge_box.monitoring = false
	_build_visual()


## 两级回退：Hell Hound 帧动画 → 场景内 ColorRect 占位（headless/缺素材）。
func _build_visual() -> void:
	_anim = _build_frame_anim(HOUND_CHAR, [
		["idle", "", 8.0, true, HOUND_POS],
		["walk", "", 10.0, true, HOUND_POS],
		["run", "", 14.0, true, HOUND_POS],
		["jump", "", 12.0, true, HOUND_JUMP_POS],
	])
	if _anim == null:
		return
	_anim.play("walk")
	visual.add_child(_anim)
	# 帧动画自带地狱犬造型：隐藏占位色块（含 Eye，状态改由动画/冲锋预告表达）。
	_hide_placeholder_rects(visual)


## 状态 → 动画：巡逻小跑 / 预备低吼(慢速待机) / 冲刺疾跑 / 硬直(定格待机)。
func _update_anim() -> void:
	if _anim == null:
		return
	match _state:
		State.PATROL:
			_anim.play("walk")
		State.WINDUP:
			_anim.set_fps("idle", 14.0)  # 蓄势：急促喘息
			_anim.play("idle")
		State.CHARGE:
			_anim.play("run")
		State.STUN:
			_anim.set_fps("idle", 4.0)   # 撞墙眩晕：拖慢到近乎定格
			_anim.play("idle")


func _tick_state(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	match _state:
		State.PATROL:
			_tick_patrol(delta)
		State.WINDUP:
			_tick_windup(delta)
		State.CHARGE:
			_tick_charge(delta)
		State.STUN:
			_tick_stun(delta)


func _after_move() -> void:
	_update_facing()
	_update_anim()
	# The charge box leads where we are driving toward.
	charge_box.position.x = absf(charge_box.position.x) * signf(_dir)


func _tick_patrol(_delta: float) -> void:
	charge_box.disarm()
	_patrol_step()
	var player := knight()
	if _cooldown <= 0.0 and player != null:
		var to_player := player.global_position - global_position
		if absf(to_player.x) < aggro_range * alert_scale() and absf(to_player.y) < 70.0:
			_dir = signf(to_player.x) if absf(to_player.x) > 4.0 else _dir
			_enter_windup()


func _tick_windup(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_timer -= delta
	if _timer <= 0.0:
		_arm_charge()


func _tick_charge(delta: float) -> void:
	velocity.x = _dir * charge_speed
	_timer -= delta
	if is_on_wall():
		_enter_stun()
		GameEvents.hit.emit(self, self, 0)  # Camera/hear feedback via bus.
	elif _charge_hazard_ahead():
		# （bug fix）冲锋不再扎进毒坑/冲出平台：前下方探不到地面或探到
		# 危害区就地刹车、回头，进入与撞墙同长的眩晕惩罚窗。
		velocity.x = 0.0
		_dir = -_dir
		_enter_stun()
	elif _timer <= 0.0:
		# 冲了一整程没撞上东西：喘一口气（短眩晕），比直接转回巡逻更读得出「现在能打」。
		charge_box.disarm()
		_enter_stun(MISS_STUN_TIME)


## 冲锋方向前下方两条射线：地面射线（layer 1）探不到 = 平台边缘/坑口；
## 危害射线（layer 128，Area）命中 = 毒池就在嘴边。
func _charge_hazard_ahead() -> bool:
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(_dir * CHARGE_PROBE_AHEAD, -CHARGE_PROBE_TOP)
	var to := global_position + Vector2(_dir * CHARGE_PROBE_AHEAD, CHARGE_PROBE_BOTTOM)
	var ground := PhysicsRayQueryParameters2D.create(from, to, 1, [get_rid()])
	if space.intersect_ray(ground).is_empty():
		return true
	var hazard := PhysicsRayQueryParameters2D.create(from, to, HAZARD_LAYER, [get_rid()])
	hazard.collide_with_areas = true
	hazard.collide_with_bodies = false
	return not space.intersect_ray(hazard).is_empty()


func _tick_stun(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	_timer -= delta
	if _timer <= 0.0:
		_cooldown = re_aggro_cooldown
		_state = State.PATROL
		_clear_windup_look()
		eye.color = Palette.TOXIC


func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = windup_time
	_apply_windup_look()
	begin_telegraph(&"scrapper", windup_time)


func _arm_charge() -> void:
	_state = State.CHARGE
	_timer = charge_max_time
	_clear_windup_look()
	charge_box.arm(Vector2(_dir * CHARGE_KNOCKBACK_X, CHARGE_KNOCKBACK_Y))


func _enter_stun(time: float = -1.0) -> void:
	_state = State.STUN
	_timer = stun_time if time < 0.0 else time
	charge_box.disarm()
	_clear_windup_look()
	# 眩晕就是破绽：头顶金箭头亮到眩晕结束。
	show_opening(_timer)


## Eye 色块在帧动画路径会被藏掉；用机体染色 + 微蹲让冲锋前摇可读。
func _apply_windup_look() -> void:
	eye.color = Palette.EMBER
	visual.modulate = WINDUP_TINT
	if _anim != null:
		_anim.scale = WINDUP_BODY_SCALE


func _clear_windup_look() -> void:
	if _anim != null:
		_anim.scale = Vector2.ONE
	eye.color = Palette.TOXIC
	# 受击白闪若还在播，交给 flash tween 落回；否则收掉蓄势染色。
	if _flash_tween == null or not _flash_tween.is_valid():
		visual.modulate = Color.WHITE


func _flash_restore_color() -> Color:
	return WINDUP_TINT if _state == State.WINDUP else Color.WHITE


func _update_facing() -> void:
	# Sprite faces travel; positive scale flips to the right.
	visual.scale.x = -_dir if _dir > 0.0 else 1.0


func _on_died() -> void:
	# 地狱犬无专用死亡帧 → 通用烟雾。
	_death_burst([] as Array[Texture2D], 12.0, false, 0.0, "碎甲者崩塌成一堆废铁")
