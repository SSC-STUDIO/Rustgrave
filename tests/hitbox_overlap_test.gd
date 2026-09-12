extends TestCase


func test_active_swing_hits_existing_overlap_once_each_swing() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var victim := Node2D.new()
	arena.add_child(victim)
	var hp := Health.new()
	hp.name = "Health"
	hp.max_hp = 5
	hp.hit_iframe_time = 0.0
	victim.add_child(hp)
	var hurt := Hurtbox.new()
	hurt.team = &"enemy"
	_shape(hurt)
	victim.add_child(hurt)
	var box := Hitbox.new()
	_shape(box)
	arena.add_child(box)
	await flush(5)
	eq(hp.current, 5, "overlap before swing does not deal damage")
	box.arm()
	await flush(8)
	eq(hp.current, 4, "active window hits the already overlapping hurtbox once")
	box.disarm()
	await flush(4)
	box.arm()
	await flush(8)
	eq(hp.current, 3, "next swing hits again without requiring enemy movement")


func _shape(area: Area2D) -> void:
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(24, 24)
	collision.shape = rectangle
	area.add_child(collision)


func test_lethal_contact_can_spawn_loot_after_overlap_queries() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var victim := (load("res://scenes/enemies/SpitterEnemy.tscn") as PackedScene).instantiate() as SpitterEnemy
	victim.name = "LootVictim"
	victim.position = Vector2(320, 0)
	arena.add_child(victim)
	var box := Hitbox.new()
	box.damage = 99
	_shape(box)
	box.position = Vector2(200, -20)
	arena.add_child(box)
	await flush(3)
	box.arm()
	box.position = Vector2(320, -20)
	await flush(12)
	ok(not is_instance_valid(victim), "real lethal overlap removes the enemy")
	ok(arena.get_node_or_null("TetherDrop_LootVictim") is CorePickup, "death safely creates a pickup collision area")
