class_name Hitbox
extends Area2D
## Player (or enemy) melee volume. Monitoring is toggled by MeleeCombat.

@export var damage: int = 1
@export var knockback: Vector2 = Vector2.ZERO
var team: StringName = &"player"
var already_hit: Array = []
## 出手分量（CombatRules.WEIGHTS）：命中反馈矩阵按它挑行。MeleeCombat 每次判定期
## 开头按连段步与毒素档位重写；其它判定体（敌人、火带、冲击波）自己标注。
var blow: StringName = &"light"
## 本次判定是否已造成伤害（挥砍取消窗口读它，arm / disarm 会清零）。
var connected: bool = false
## 只有剑本身的判定能吃掉破绽窗口的翻倍（火带 / 冲击波不行，免得它们抢走第一击）。
var riposte_eligible: bool = false
## 剑刃扫环境：判定期内向前打三条短射线，命中地面/墙/可破坏物时出材质打击。
## 只走 Fx，不造成伤害、不进 already_hit（hurtbox 路径完全不受影响）。
var world_probe: bool = false
const PROBE_INTERVAL := 0.05
const TERRAIN_MASK := 1 | 64
const ImpactCatalog := preload("res://scripts/data/impact_catalog.gd")
var _probe_cool := 0.0
var _world_hits: Dictionary = {}


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = 8 # player_hitbox
	collision_mask = 16 | 32 # projectile + hurtbox


## 打开判定并清 already_hit。冲锋/挥砍每次出手都要调用，否则第一下命中后永远打不中。
func arm(p_knockback: Vector2 = Vector2.ZERO) -> void:
	already_hit.clear()
	connected = false
	knockback = p_knockback
	monitoring = true


func disarm() -> void:
	monitoring = false
	already_hit.clear()
	world_probe = false
	_world_hits.clear()
	_probe_cool = 0.0


## 一次挥砍的环境扫描初始化：清上一刀扫过的碰撞体，避免同面重复出特效。
func begin_world_probe() -> void:
	_world_hits.clear()
	_probe_cool = 0.0
	world_probe = true


## 刺出那一帧的立即结算：Area2D 的 overlapping_areas 在 monitoring 刚打开时
## 还是空的（物理服务器要到下一次 step 才刷新），贴身敌人 / 已经压进剑里的弹丸
## 会晚一帧才命中或弹反。这里用空间查询把「判定开始的这一刻已经重叠」的目标
## 直接交给对应入口；already_hit / can_deflect 保证不会与随后的物理信号重复。
func sweep_now() -> void:
	if not monitoring or not is_inside_tree():
		return
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null or shape_node.disabled:
		return
	var space := get_world_2d().direct_space_state
	if space == null:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = 16 | 32  # projectile + hurtbox
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [get_rid()]
	for hit in space.intersect_shape(query, 16):
		var area := hit.get("collider") as Area2D
		if area == null or not is_instance_valid(area):
			continue
		if area is Hurtbox:
			(area as Hurtbox)._on_area_entered(self)
		elif area is Projectile:
			area_entered.emit(area)


func _physics_process(delta: float) -> void:
	if not monitoring:
		return
	# A hurtbox can overlap the sword before the active window begins.
	# Toggling monitoring does not re-emit its area_entered signal. Sweep the
	# current pairs as well; already_hit still limits damage to once per swing.
	for area in get_overlapping_areas():
		if area is Hurtbox:
			area._on_area_entered(self)
	if world_probe:
		_probe_cool -= delta
		if _probe_cool <= 0.0:
			_probe_cool = PROBE_INTERVAL
			_sweep_world()


## 三条短射线（上/中/下）找前方环境；每个碰撞体每刀只触发一次。
func _sweep_world() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null or shape_node.disabled:
		return
	var rect := shape_node.shape as RectangleShape2D
	if rect == null:
		return
	var space := get_world_2d().direct_space_state
	if space == null:
		return
	var facing := global_transform.x.normalized()
	if facing.length_squared() < 0.5:
		return
	var center := shape_node.global_position
	var reach := rect.size.x * 0.5 + 6.0
	for row in [-0.32, 0.0, 0.32]:
		var from := center + Vector2(0.0, rect.size.y * float(row))
		var query := PhysicsRayQueryParameters2D.create(from, from + facing * reach,
				TERRAIN_MASK)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider := hit.get("collider") as Object
		var id := collider.get_instance_id() if collider != null else 0
		if id == 0 or _world_hits.has(id):
			continue
		_world_hits[id] = true
		var material := ImpactCatalog.material_for_collider(collider)
		Fx.impact(material, hit.get("position", from), hit.get("normal", -facing), blow)
