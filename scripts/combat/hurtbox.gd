class_name Hurtbox
extends Area2D
## Receives melee and projectile hits. Team string prevents friendly fire.

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
	_apply_knockback(attacker)
	if _health:
		_health.take_damage(amount, attacker)


## Push the owning body away from the strike. Only moving bodies (enemies /
## the knight) respond; static props are unaffected.
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
		box.already_hit.append(self)
		receive_hit(box.damage, box)


func _is_owner_invincible() -> bool:
	if _health and _health.is_invincible():
		return true
	var body := get_parent()
	if body is Player:
		return (body as Player).is_invincible()
	return false
