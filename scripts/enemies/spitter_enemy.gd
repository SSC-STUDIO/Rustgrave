class_name SpitterEnemy
extends EnemyBase
## Stationary rust-spitter. Teaches parry: its slag bolts can be sent home.

const PROJECTILE_SCENE := preload("res://scenes/combat/Projectile.tscn")
const PICKUP_SCENE := preload("res://scenes/interactables/CorePickup.tscn")

@export var shoot_interval: float = 1.85
@export var projectile_speed: float = 150.0
@export var aggro_range: float = 380.0

## Telegraph: the nozzle glows toxic-orange and the body puffs up before the
## bolt actually flies, then snaps back on release. Pure presentation — the
## firing cadence (shoot_interval) and hit logic are untouched.
const CHARGE_TIME := 0.45
const CHARGE_TINT_WEIGHT := 0.65
const CHARGE_SCALE := Vector2(1.1, 1.1)

@onready var muzzle: Marker2D = $Muzzle

var _body: CanvasItem
var _base_modulate := Color.WHITE
var _charging := false
var _charge_timer: Timer
var _visual_tween: Tween


const FLY_TEX_PATH := "res://assets/kenney_clean/enemies/flyFly1.png"
## Hell Beast 像素帧动画（ansimuz，原图面朝左）：idle 5帧 / attack(吐息) 4帧 /
## death(烈焰焚毁) 6帧。画布 66x67 / 64x64 / 74x160，脚底均贴画布底边。
const BEAST_CHAR := "spitter_hell_beast"
const BEAST_IDLE_POS := Vector2(-4.0, -33.0)   # 身体中心在画布 x≈37 → 补偿 -4
const BEAST_ATTACK_POS := Vector2(0.0, -32.0)
const BEAST_DEATH_BASELINE := -80.0            # 死亡帧画布 160 高（火柱向上）


func _enemy_ready() -> void:
	_mobile = false  # 定点炮台：不施重力、不 move_and_slide
	health.max_hp = 2
	health.heal_full()
	var timer := Timer.new()
	timer.wait_time = shoot_interval
	timer.autostart = true
	timer.timeout.connect(_on_shoot_tick)
	add_child(timer)
	_charge_timer = Timer.new()
	_charge_timer.wait_time = CHARGE_TIME
	_charge_timer.one_shot = true
	_charge_timer.timeout.connect(_on_charged)
	add_child(_charge_timer)
	_build_visual()


## 三级回退：Hell Beast 帧动画 → Kenney 单帧 → ColorRect 占位（headless/缺素材）。
func _build_visual() -> void:
	var existing := get_node_or_null("Body") as CanvasItem
	if existing != null:
		_body = existing
		_base_modulate = existing.modulate
		return
	_anim = _build_frame_anim(BEAST_CHAR, [
		["idle", "", 8.0, true, BEAST_IDLE_POS],
		["attack", "", 10.0, false, BEAST_ATTACK_POS],
	])
	if _anim != null:
		_anim.play("idle")
		_anim.finished.connect(_on_anim_finished)
		add_child(_anim)
		_body = _anim
		_base_modulate = _anim.modulate
		return
	if ResourceLoader.exists(FLY_TEX_PATH):
		var spr := Sprite2D.new()
		spr.name = "Body"
		spr.texture = load(FLY_TEX_PATH) as Texture2D
		spr.position = Vector2(0, -10)
		spr.modulate = Palette.RUST_MID.lerp(Color.WHITE, 0.25)
		add_child(spr)
		_body = spr
		_base_modulate = spr.modulate
		_add_nozzle()
		return
	var body := ColorRect.new()
	body.name = "Body"
	body.size = Vector2(16, 20)
	body.position = Vector2(-8, -20)
	body.color = Palette.RUST_MID
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	_body = body
	_base_modulate = Color.WHITE
	_add_nozzle()


func _add_nozzle() -> void:
	var nozzle := ColorRect.new()
	nozzle.size = Vector2(10, 4)
	nozzle.position = Vector2(-14, -14)
	nozzle.color = Palette.TOXIC
	nozzle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(nozzle)


func _on_shoot_tick() -> void:
	if Director.is_input_locked() or is_hurt_locked():
		return
	if health.current <= 0 or _charging:
		return
	var player := knight()
	if player == null:
		return
	if global_position.distance_to(player.global_position) > aggro_range:
		return
	# Do not fire through a full platform-height gap. The player must first
	# reach the ledge so the telegraph is readable and the fight is answerable.
	if absf(global_position.y - player.global_position.y) > 96.0:
		return
	_begin_charge()


## 吐完一口的喘息：炮口冒烟的这一小会儿是破绽（头顶金箭头），之后才重新蓄力。
const EXHALE_TIME := 0.35


func _begin_charge() -> void:
	_charging = true
	_face_player()
	begin_telegraph(&"spitter", CHARGE_TIME)
	Sfx.play_at(CombatRules.sfx_key(&"spit_charge"), global_position, 0.06, -8.0)
	# 吐息动画横跨整个蓄力窗：4 帧在 CHARGE_TIME 内播完，释放帧正好落在发射瞬间。
	if _anim != null:
		_anim.set_fps("attack", 4.0 / maxf(CHARGE_TIME, 0.1))
		_anim.play("attack", true)
	_kill_visual_tween()
	_visual_tween = create_tween()
	_visual_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_visual_tween.tween_property(_body, "modulate", _charge_modulate(), CHARGE_TIME)
	_visual_tween.parallel().tween_property(
		_body, "scale", Vector2(signf(_body.scale.x) * CHARGE_SCALE.x, CHARGE_SCALE.y), CHARGE_TIME
	)
	_charge_timer.start()


func _on_charged() -> void:
	_charging = false
	_kill_visual_tween()
	_visual_tween = create_tween()
	_visual_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_visual_tween.tween_property(_body, "modulate", _base_modulate, 0.08)
	_visual_tween.parallel().tween_property(
		_body, "scale", Vector2(signf(_body.scale.x), 1.0), 0.08
	)
	if health.current <= 0 or _dead:
		return
	var player := knight()
	if player == null:
		return
	_fire(player)
	show_opening(EXHALE_TIME)


## 吐息动画播完（非循环停在末帧）后回到待机循环。
func _on_anim_finished(anim: StringName) -> void:
	if anim == &"attack" and not _charging:
		_anim.play("idle")


func _fire(player: Player) -> void:
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	var effects := GameContext.world_effects(self)
	if effects == null:
		effects = get_parent()
	effects.add_child(proj)
	# 喷口跟随身体朝向镜像（原图面朝左，scale.x=-1 时面朝右）。
	var mpos := muzzle.position
	if _body != null and _body.scale.x < 0.0:
		mpos.x = -mpos.x
	var origin := global_position + mpos
	var dir := player.global_position + Vector2(0, -12) - origin
	proj.setup(origin, dir, projectile_speed, &"enemy", self)


## 受击白闪覆写：蓄力/回弹与白闪共用 _visual_tween 互相顶替（保持原手感），
## 且蓄力中闪完要落回蓄力色而非纯白。
func _flash_white() -> void:
	_kill_visual_tween()
	var restore_to := _charge_modulate() if _charging else _base_modulate
	_visual_tween = create_tween()
	_visual_tween.tween_property(_body, "modulate", FLASH_MODULATE, 0.03)
	_visual_tween.tween_interval(0.05)
	_visual_tween.tween_property(_body, "modulate", restore_to, 0.12)


func _charge_modulate() -> Color:
	return _base_modulate.lerp(Palette.TOXIC, CHARGE_TINT_WEIGHT)


## AI 贴图面朝左：玩家在右侧时水平翻转，蓄力朝向更可读。
func _face_player() -> void:
	if _body == null:
		return
	var player := knight()
	if player == null:
		return
	_body.scale.x = 1.0 if player.global_position.x < global_position.x else -1.0


func _kill_visual_tween() -> void:
	if _visual_tween != null and _visual_tween.is_valid():
		_visual_tween.kill()


func _on_died() -> void:
	var pickup := PICKUP_SCENE.instantiate() as CorePickup
	pickup.name = "TetherDrop_%s" % name
	pickup.core = AbilityCatalog.tether_core()
	# Set the position before _ready captures the bobbing baseline.
	pickup.position = position + Vector2(0, -8)
	var saved_path := SaveData.persist_path(self).get_base_dir() + "/" + String(pickup.name)
	if SaveData.is_consumed(saved_path):
		pickup.free()
	else:
		get_parent().add_child(pickup)
	# 尸体演出：烈焰焚毁 6 帧（火柱画布 160 高，脚底对齐原地），随朝向镜像。
	var facing_right: bool = _body != null and _body.scale.x < 0.0
	_death_burst(CharFrames.anim(BEAST_CHAR, "death"), 12.0,
			facing_right, BEAST_DEATH_BASELINE, "喷吐者崩解，掉落钩锁核")
