class_name Projectile
extends Area2D
## Hostile slag bolt. During a slash active-frame overlap it is deflected home.

var velocity: Vector2 = Vector2.ZERO
var team: StringName = &"enemy"
var source: Node2D
var damage: int = 1
var deflected: bool = false
var lifetime: float = 4.5
## 撞到环境时用它读材质（木箱/裂石板可覆盖）；留空则从碰撞体的 skin/hit_material 推。
var hit_material: StringName = &""

const BOLT_PATH := "res://assets/env/fireball_1.png"
## Hell Beast 火球 3 帧（19x16，火头朝右 → rotation=velocity.angle() 直接可用）。
const BOLT_CHAR := "spitter_hell_beast"
## 火球与"地面/墙/可破坏物"的碰撞层：世界静态体 + 可破坏/可交互物。
const TERRAIN_MASK := 1 | 64
const ImpactCatalog := preload("res://scripts/data/impact_catalog.gd")

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
	_sprite.texture = DensityTextures.load_texture(BOLT_PATH)
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
	if is_queued_for_deletion():
		return
	# 先做一次"本帧位移"的射线：拿到精确的命中点/法线，才能把焦痕、火花和
	# 辉光落在表面上，而不是落在弹丸消失时的空中坐标。
	var step := velocity * delta
	if step.length_squared() > 0.0001 and _sweep_terrain(step):
		return
	global_position += step
	if velocity.length_squared() > 4.0:
		rotation = velocity.angle()
	if deflected and randf() < 0.28:
		Fx.dust_puff(global_position, rotation + PI)
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


## 本帧撞到地形就结算环境打击并返回 true（调用方不再移动弹丸）。
func _sweep_terrain(step: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position,
			global_position + step, TERRAIN_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider") as Object
	# 可破坏道具是"有血量的地形"：射线放行，让它的 Hurtbox 结算伤害；
	# 否则火球会在表面炸掉、永远打不碎箱子。
	if collider is Node and (collider as Node).is_in_group(&"destructible_body"):
		return false
	_impact_terrain(hit.get("position", global_position), hit.get("normal", Vector2.UP), collider)
	return true


func _impact_terrain(point: Vector2, normal: Vector2, collider: Object) -> void:
	if is_queued_for_deletion():
		return
	var material: StringName = hit_material
	if material == &"" or not ImpactCatalog.has_material(material):
		material = ImpactCatalog.material_for_collider(collider)
	# 被弹回的冷色弹丸打在地上也要有反馈，但分量轻一档（它不是敌方威胁）。
	var weight: StringName = &"light"
	Fx.impact(material, point, normal, weight)
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if Director.is_input_locked():
		return
	if body is Player:
		return
	# 物理信号没有命中点：用弹丸当前位置 + 反方向法线近似一次，保证即使射线
	# 先没扫到（极端帧、形状重叠）也一定有落地反馈。
	_impact_terrain(global_position, -velocity.normalized(), body)


func _update_visual() -> void:
	if _sprite is FrameAnimSprite:
		# 帧火球本身就是橙红：敌方保持原色，弹反后压成冷青色标记归属反转。
		_sprite.modulate = Color(0.55, 1.35, 1.6) if deflected else Color.WHITE
	elif _sprite:
		_sprite.modulate = Color(0.72, 0.42, 0.28) if deflected else Color(0.78, 0.38, 0.22)
	elif _fill:
		_fill.color = Palette.TEAL if deflected else Palette.TOXIC
