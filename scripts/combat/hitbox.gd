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


func _physics_process(_delta: float) -> void:
	if not monitoring:
		return
	# A hurtbox can overlap the sword before the active window begins.
	# Toggling monitoring does not re-emit its area_entered signal. Sweep the
	# current pairs as well; already_hit still limits damage to once per swing.
	for area in get_overlapping_areas():
		if area is Hurtbox:
			area._on_area_entered(self)
