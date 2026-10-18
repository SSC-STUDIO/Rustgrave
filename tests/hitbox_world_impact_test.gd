extends TestCase
## 剑刃扫环境：只出表现、不产生伤害；同一个碰撞体每刀只触发一次。

const HitboxScript := preload("res://scripts/combat/hitbox.gd")


func _make_hitbox() -> Hitbox:
	var box: Hitbox = HitboxScript.new()
	box.name = "Hitbox"
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18.0, 26.0)
	shape.shape = rect
	box.add_child(shape)
	add_child(box)
	box.arm(Vector2.ZERO)
	return box


func _make_wall(pos: Vector2, size: Vector2, material: StringName) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Wall"
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	body.set_meta(&"impact_material", material)
	add_child(body)
	return body


func test_world_probe_hits_each_surface_once_per_swing() -> void:
	_make_wall(Vector2(18.0, 0.0), Vector2(12.0, 60.0), &"metal")
	Fx.reset_impact_counters()
	var box := _make_hitbox()
	ok(not box.world_probe, "默认不扫环境（敌人命中走原有矩阵）")
	box.begin_world_probe()
	await flush(4)
	eq(Fx.impact_count(), 1, "开始判定的第一帧扫到墙")
	eq(StringName(Fx.last_impact().get("material", &"")), &"metal")
	await flush(24)
	eq(Fx.impact_count(), 1, "同一刀对同一面不重复出特效")
	# 下一刀再来一次
	box.begin_world_probe()
	await flush(3)
	eq(Fx.impact_count(), 2, "新一刀重新允许同一面出特效")
	# 收刀后不再扫
	box.disarm()
	await flush(10)
	eq(Fx.impact_count(), 2, "收刀后停止环境扫描")
	box.queue_free()


func test_world_probe_does_nothing_without_a_target() -> void:
	Fx.reset_impact_counters()
	var box := _make_hitbox()
	box.begin_world_probe()
	await flush(20)
	eq(Fx.impact_count(), 0, "前方没有环境就没有打击")
	box.queue_free()


func test_disarm_never_damages_anything() -> void:
	# 剑扫环境不能碰 hurtbox：放一个带 Health 的 hurtbox 在墙前面，确认血量不变。
	_make_wall(Vector2(26.0, 0.0), Vector2(12.0, 60.0), &"stone")
	var target := CharacterBody2D.new()
	target.name = "Target"
	target.position = Vector2(30.0, -10.0)
	var health := Health.new()
	health.name = "Health"
	health.max_hp = 5
	health.current = 5
	target.add_child(health)
	var hurt := Hurtbox.new()
	hurt.name = "Hurtbox"
	hurt.team = &"enemy"
	hurt.damage_owner_path = NodePath("..")
	var hurt_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12.0, 20.0)
	hurt_shape.shape = rect
	hurt.add_child(hurt_shape)
	target.add_child(hurt)
	add_child(target)
	Fx.reset_impact_counters()
	var box := _make_hitbox()
	box.begin_world_probe()
	await flush(10)
	eq(health.current, 5, "环境扫描不造成伤害")
	box.queue_free()
	target.queue_free()
	await flush(2)
