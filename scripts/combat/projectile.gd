class_name Projectile
extends Area2D
## Hostile slag bolt. During a slash active-frame overlap it is deflected home.

var velocity: Vector2 = Vector2.ZERO
var team: StringName = &"enemy"
var source: Node2D
var damage: int = 1
var deflected: bool = false
var lifetime: float = 4.5

const BOLT_PATH := "res://assets/env/fireball_1.png"
## Hell Beast 火球 3 帧（19x16，火头朝右 → rotation=velocity.angle() 直接可用）。
const BOLT_CHAR := "spitter_hell_beast"

@onready var _fill: ColorRect = $Fill
var _sprite: Sprite2D

## 同屏弹丸预算（CombatRules.BUDGET[projectiles]）：超出时收掉最老的敌方弹，
## 被弹回的弹丸（玩家归属）永不被收。静态登记表只放弱引用，场景重载自动失效。
static var _live: Array = []


func _enter_tree() -> void:
	_live.append(weakref(self))
	_enforce_budget()


func _exit_tree() -> void:
	for i in range(_live.size() - 1, -1, -1):
		var ref: WeakRef = _live[i]
		if ref.get_ref() == null or ref.get_ref() == self:
			_live.remove_at(i)


static func live_count() -> int:
	var n := 0
	for ref in _live:
		if (ref as WeakRef).get_ref() != null:
			n += 1
	return n


static func _enforce_budget() -> void:
	var cap := int(CombatRules.BUDGET[&"projectiles"])
	var alive: Array = []
	for ref in _live:
		var bolt := (ref as WeakRef).get_ref() as Projectile
		if bolt != null and not bolt.is_queued_for_deletion():
			alive.append(bolt)
	var excess := alive.size() - cap
	for bolt in alive:
		if excess <= 0:
			break
		if not (bolt as Projectile).deflected:
			(bolt as Projectile).queue_free()
			excess -= 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	collision_layer = 16
	collision_mask = 1 | 8 | 32
	_setup_sprite()
	_update_visual()


## 三级回退：帧动画火球 → 静态 fireball 贴图 → ColorRect 占位。
## 只换外观，弹反（deflect/parry）判定路径不碰。
func _setup_sprite() -> void:
	var frames := CharFrames.anim(BOLT_CHAR, "projectile")
	if not frames.is_empty():
		if _fill:
			_fill.visible = false
		var anim := FrameAnimSprite.new()
		anim.name = "BoltSprite"
		anim.register("fly", frames, 12.0, true)
		anim.play("fly")
		add_child(anim)
		_sprite = anim
		return
	if not ResourceLoader.exists(BOLT_PATH):
		return
	if _fill:
		_fill.visible = false
	_sprite = Sprite2D.new()
	_sprite.name = "BoltSprite"
	_sprite.texture = load(BOLT_PATH) as Texture2D
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	_sprite.scale = Vector2(0.28, 0.28)
	add_child(_sprite)


func setup(origin: Vector2, direction: Vector2, speed: float, p_team: StringName, p_source: Node2D) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	team = p_team
	source = p_source
	_update_visual()


func can_deflect() -> bool:
	return not deflected and team != &"player"


## 反弹执行（响应方）：翻转归属、瞄准射源加速回敬、换弹反配色。
## 窗口判定与成功反馈（parried 信号/播报/音效）由 MeleeCombat.try_deflect
## 统一负责，这里不再自行判窗。
func deflect(_by: Node2D) -> void:
	if not can_deflect():
		return
	deflected = true
	team = &"player"
	damage = 2
	var aim := -velocity.normalized()
	if source != null and is_instance_valid(source):
		# Character origins sit at their feet. Aiming there sends reflected
		# bolts into the floor before reaching a grounded enemy's hurtbox.
		var target := source.get_node_or_null("Hurtbox") as Node2D
		var target_position := target.global_position if target != null else source.global_position
		aim = (target_position - global_position).normalized()
	velocity = aim * maxf(velocity.length() * 1.55, 210.0)
	_update_visual()


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	if velocity.length_squared() > 4.0:
		rotation = velocity.angle()
	if deflected and randf() < 0.28:
		Fx.dust_puff(global_position, rotation + PI)
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		return
	queue_free()


func _update_visual() -> void:
	if _sprite is FrameAnimSprite:
		# 帧火球本身就是橙红：敌方保持原色，弹反后压成冷青色标记归属反转。
		_sprite.modulate = Color(0.55, 1.35, 1.6) if deflected else Color.WHITE
	elif _sprite:
		_sprite.modulate = Color(0.72, 0.42, 0.28) if deflected else Color(0.78, 0.38, 0.22)
	elif _fill:
		_fill.color = Palette.TEAL if deflected else Palette.TOXIC
