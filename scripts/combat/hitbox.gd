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


func _physics_process(_delta: float) -> void:
	if not monitoring:
		return
	# A hurtbox can overlap the sword before the active window begins.
	# Toggling monitoring does not re-emit its area_entered signal. Sweep the
	# current pairs as well; already_hit still limits damage to once per swing.
	for area in get_overlapping_areas():
		if area is Hurtbox:
			area._on_area_entered(self)
