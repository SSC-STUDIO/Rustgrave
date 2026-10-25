class_name Hurtbox
extends Area2D
## Receives melee and projectile hits. Team string prevents friendly fire.

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

signal hurt(amount: int, attacker: Node)

@export var team: StringName = &"player"
@export var damage_owner_path: NodePath = NodePath("..")

var _health: Health

## Optional veto: if set and returns true for (attacker, amount), the hit is
## fully consumed (no damage applied) and the owner — not this node — is
## responsible for any block/stagger feedback. Used by the Gear Shield's
## frontal defense so hits from the guarded side never chip its HP.
var block_check: Callable = Callable()


func _ready() -> void:
	monitorable = true
	monitoring = true
	collision_layer = 32 # hurtbox
	collision_mask = 8 | 16 # player_hitbox + projectile
	# Death can spawn loot and remove collision areas. Deliver contact damage
	# after the physics server has finished flushing its overlap queries.
	area_entered.connect(_on_area_entered, CONNECT_DEFERRED)
	var owner_node := get_node_or_null(damage_owner_path)
	if owner_node:
		_health = owner_node.get_node_or_null("Health") as Health


func receive_hit(amount: int, attacker: Node) -> void:
	hurt.emit(amount, attacker)
	# Blocking owners veto the damage before it reaches the health pool.
	if block_check.is_valid() and block_check.call(attacker, amount):
		return
	var body := get_parent()
	amount = _riposte_amount(body, attacker, amount)
	_apply_knockback(attacker)
	if _health == null:
		return
	if _health.take_damage(amount, attacker):
		# 打实了：挥砍取消窗口读这个标记（盾面挡下不会走到这里）。
		if attacker is Hitbox:
			(attacker as Hitbox).connected = true
		# 被弹回的弹丸打中：露出破绽（盾类走自己的格挡分支，见 GearShieldEnemy）。
		if attacker is Projectile and (attacker as Projectile).deflected \
				and _health.current > 0 and body != null and body.has_method(&"open_riposte"):
			body.call(&"open_riposte")


## 破绽窗口里玩家近战的第一击伤害翻倍（消耗标记）；其它来源 / 无标记原样返回。
func _riposte_amount(body: Node, attacker: Node, amount: int) -> int:
	if body == null or not (attacker is Hitbox) or not body.has_method(&"consume_riposte"):
		return amount
	var box := attacker as Hitbox
	if box.team != &"player" or not box.riposte_eligible:
		return amount
	return amount * maxi(1, int(body.call(&"consume_riposte")))


## Push the owning body away from the strike. Only moving bodies (enemies /
## the knight) respond; static props are unaffected. 击退再乘材质倍率
## （CombatRules.HIT_FEEL 的 knock：装甲减半，首领几乎不动）。
func _apply_knockback(attacker: Node) -> void:
	var body := get_parent()
	if body is not CharacterBody2D:
		return
	var kb := Vector2.ZERO
	if attacker is Hitbox:
		kb = (attacker as Hitbox).knockback
	elif attacker is Projectile:
		var bolt := attacker as Projectile
		var dir := bolt.velocity.normalized()
		kb = dir * 70.0
	if kb == Vector2.ZERO:
		return
	kb *= float(CombatRules.feel(CombatRules.material_of(body), &"light")["knock"])
	(body as CharacterBody2D).velocity += kb


func _on_area_entered(area: Area2D) -> void:
	if not is_instance_valid(area):
		return
	if area is Projectile:
		var projectile := area as Projectile
		if projectile.team == team:
			return
		if _is_owner_invincible():
			return
		if _arena_depth_blocked(projectile):
			return
		receive_hit(projectile.damage, projectile)
		projectile.queue_free()
		return
	if area is Hitbox:
		var box := area as Hitbox
		if box.team == team:
			return
		if not box.monitoring:
			return
		if box.already_hit.has(self):
			return
		if _is_owner_invincible():
			return
		if _arena_depth_blocked(box):
			return
		box.already_hit.append(self)
		receive_hit(box.damage, box)


func _is_owner_invincible() -> bool:
	if _health and _health.is_invincible():
		return true
	var body := get_parent()
	if body is Player:
		return (body as Player).is_invincible()
	return false


func _arena_depth_blocked(attacker: Node) -> bool:
	if not ArenaRun.active():
		return false
	var body := get_parent()
	if body == null or attacker == null:
		return false
	if not _arena_participant(body) and not _arena_participant(attacker):
		return false
	return not ArenaCatalog.depths_touch(attacker, body)


func _arena_participant(node: Node) -> bool:
	var cursor: Node = node
	while cursor != null:
		if cursor.is_in_group("arena_unit") or cursor.is_in_group("arena_plane") or cursor.is_in_group("arena_bolt"):
			return true
		cursor = cursor.get_parent()
	return false
