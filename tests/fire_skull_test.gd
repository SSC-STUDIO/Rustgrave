extends TestCase
## 火骷髅：飞行敌人声明 → 出生点附近正弦巡飞 → 骑士靠近后追过去 → 两刀灭。
## 脚本没有 class_name（等导入后类缓存才会更新），所以这里全用动态调用。

const FIRE_SKULL := preload("res://scenes/enemies/FireSkullEnemy.tscn")


func _spawn(arena: Node2D, pos: Vector2) -> Node2D:
	var skull := FIRE_SKULL.instantiate() as Node2D
	skull.position = pos
	arena.add_child(skull)
	return skull


func test_fire_skull_is_airborne_and_ignores_the_world() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var skull = _spawn(arena, Vector2(320, -120))
	await flush(2)
	ok(skull.is_airborne(), "level sanity treats it as a flyer")
	eq(skull.collision_mask, 0, "it never collides with platforms")
	eq(skull.health.max_hp, 2)
	eq(skull.state(), skull.State.PATROL, "with no knight around it just cruises")
	ok(skull.visual.has_node("SkullGlow"), "it carries its own ember glow")
	ok(not skull.hitbox.monitoring, "no bite while cruising")
	ok(skull.global_position.y < -60.0, "no gravity pulls it down (y=%.0f)" % skull.global_position.y)


func test_cruising_skull_weaves_around_its_spawn_point() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var origin := Vector2(900, -100)
	var skull = _spawn(arena, origin)
	await flush(2)
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for i in 150:
		await flush(1)
		min_x = minf(min_x, skull.global_position.x)
		max_x = maxf(max_x, skull.global_position.x)
		min_y = minf(min_y, skull.global_position.y)
		max_y = maxf(max_y, skull.global_position.y)
	ok(min_x >= origin.x - 110.0 and max_x <= origin.x + 110.0,
			"x stays within 110px of spawn (%.0f..%.0f)" % [min_x, max_x])
	ok(max_x - min_x > 60.0, "it actually travels along its beat (%.0f px)" % [max_x - min_x])
	ok(min_y >= origin.y - 30.0 and max_y <= origin.y + 30.0,
			"the bob stays shallow (%.0f..%.0f)" % [min_y, max_y])
	ok(max_y - min_y > 6.0, "it bobs up and down (%.0f px)" % [max_y - min_y])
	eq(skull.state(), skull.State.PATROL, "no knight, still patrolling")


func test_skull_hunts_a_nearby_knight() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var skull = _spawn(arena, player.global_position + Vector2(150, -60))
	await flush(3)
	eq(skull.state(), skull.State.HUNT, "a knight within 200px draws it in")
	var start_d: float = skull.global_position.distance_to(player.global_position)
	await flush(45)
	var now_d: float = skull.global_position.distance_to(player.global_position)
	ok(now_d < start_d - 30.0, "skull closed the distance (%.0f -> %.0f)" % [start_d, now_d])
	eq(skull.visual.scale.x, 1.0, "left-facing art flies unflipped toward a knight on its left")


func test_two_blows_snuff_the_skull() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var skull = _spawn(arena, player.global_position + Vector2(400, -60))
	await flush(2)
	skull.hurtbox.receive_hit(1, player)
	await flush(1)
	ok(is_instance_valid(skull) and not skull._dead, "one blow leaves it burning")
	eq(skull.health.current, 1)
	await flush(30)  # past Health's 0.45s i-frames
	skull.hurtbox.receive_hit(1, player)
	await flush(2)
	ok(not is_instance_valid(skull) or skull._dead, "second blow snuffs it")
