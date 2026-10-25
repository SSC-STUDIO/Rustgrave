extends Node2D
## Hitbox 飞弹。不是 Projectile，不占全局 8 发预算。

const SPEED := 156.0
const LIFE := 1.25
const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

var team: String = "enemy"
var owner_id: String = ""
var velocity := Vector2.ZERO
var _life := LIFE
var _hitbox: Hitbox = null
var _depth := 0.0


func arena_depth() -> float:
	return _depth


func setup(owner_node: Node2D, dir: float, dmg: int, aim: Node = null) -> void:
	add_to_group("arena_bolt")
	var face := 1.0 if dir >= 0.0 else -1.0
	_depth = ArenaCatalog.DEPTH_MID
	if owner_node != null:
		if "team" in owner_node:
			team = String(owner_node.get("team"))
		if "unit_id" in owner_node:
			owner_id = String(owner_node.get("unit_id"))
		_depth = ArenaCatalog.node_depth(owner_node)
	if aim != null:
		_depth = ArenaCatalog.node_depth(aim)
	if owner_node != null:
		global_position = owner_node.global_position + Vector2(face * 22.0, 0.0)
	global_position.y = _depth - 12.0
	velocity = Vector2(face * SPEED, 0.0)
	z_index = 0
	_build_visual()
	_build_hitbox(maxi(1, dmg))


func _build_visual() -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-5, -1), Vector2(5, -1), Vector2(5, 1), Vector2(-5, 1),
	])
	body.color = Color(1.4, 0.85, 0.45, 1)
	body.material = Fx.additive_mat()
	body.z_index = 0
	add_child(body)
	var tint: Color = Color.WHITE
	if ArenaCatalog.TEAM_TINT.has(team):
		tint = ArenaCatalog.TEAM_TINT[team]
	self_modulate = tint
	z_index = 0


func _build_hitbox(dmg: int) -> void:
	var box := Hitbox.new()
	box.name = "BoltHit"
	box.team = StringName(team)
	box.damage = dmg
	box.knockback = Vector2(signf(velocity.x) * 60.0, -16.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 36)
	shape.shape = rect
	box.add_child(shape)
	add_child(box)
	box.arm(box.knockback)
	box.area_entered.connect(_on_hit)
	_hitbox = box


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_hit(area: Area2D) -> void:
	if not (area is Hurtbox):
		return
	var box := area as Hurtbox
	if box.team == StringName(team):
		return
	var host := box.get_parent()
	if host != null and not ArenaCatalog.depths_touch(self, host, "bolt"):
		return
	queue_free()
