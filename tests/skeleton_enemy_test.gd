extends TestCase
## 骸骨：远处埋着不可见不可伤 → 骑士靠近爬起 → 起身后追着骑士走、撞墙折返 → 两刀散架。
## 脚本没有 class_name（等导入后类缓存才会更新），所以这里全用动态调用。

const SKELETON := preload("res://scenes/enemies/SkeletonEnemy.tscn")


func _spawn(arena: Node2D, pos: Vector2) -> Node2D:
	var skel := SKELETON.instantiate() as Node2D
	skel.position = pos
	arena.add_child(skel)
	return skel


func test_buried_skeleton_is_invisible_and_untouchable_until_the_knight_is_near() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var skel = _spawn(arena, player.global_position + Vector2(400, 0))
	await flush(3)
	eq(skel.state(), skel.State.BURIED, "far away it stays in the dirt")
	ok(not skel.is_risen())
	ok(not skel.visual.visible, "buried bones are not drawn")
	ok(not skel.hurtbox.monitorable, "hurtbox stays off underground")
	ok(not skel.hitbox.monitoring, "no contact damage underground")
	eq(skel.collision_layer, 0, "no body while buried")
	skel.global_position = player.global_position + Vector2(100, 0)
	await flush(2)
	eq(skel.state(), skel.State.RISE, "within wake range it claws out of the dirt")
	ok(skel.visual.visible, "rising bones are drawn")
	ok(not skel.hurtbox.monitorable, "still untouchable while rising")
	ok(not skel.is_risen())


func test_risen_skeleton_walks_toward_the_knight() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var skel = _spawn(arena, player.global_position + Vector2(110, 0))
	var risen: bool = await wait_until(func() -> bool: return skel.is_risen(), 90)
	ok(risen, "the rise animation ends with it on its feet")
	eq(skel.state(), skel.State.WALK)
	ok(skel.hurtbox.monitorable, "standing bones can be struck")
	eq(skel.collision_layer, 4, "standing bones have a body")
	var start_dx: float = absf(skel.global_position.x - player.global_position.x)
	await flush(60)
	var now_dx: float = absf(skel.global_position.x - player.global_position.x)
	ok(now_dx < start_dx - 20.0, "skeleton closed in (%.0f -> %.0f)" % [start_dx, now_dx])
	eq(skel.visual.scale.x, 1.0, "left-facing art walks unflipped toward a knight on its left")


func test_skeleton_backsteps_off_a_wall_then_resumes_the_chase() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var wall := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 64)
	col.shape = shape
	wall.add_child(col)
	wall.position = player.global_position + Vector2(40, -32)
	wall.collision_layer = 1
	arena.add_child(wall)
	var skel = _spawn(arena, player.global_position + Vector2(80, 0))
	var turned: bool = await wait_until(func() -> bool: return skel.state() == skel.State.TURN, 200)
	ok(turned, "bumping the wall makes it turn away")
	ok(skel.velocity.x > 0.0, "during the backstep it walks away from the wall")
	var chasing: bool = await wait_until(func() -> bool: return skel.state() == skel.State.WALK, 60)
	ok(chasing, "a few steps later it comes back for the knight")
	ok(skel.global_position.x > wall.position.x, "it never phased through the wall")


func test_two_blows_scatter_the_bones() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var skel = _spawn(arena, player.global_position + Vector2(90, 0))
	skel.walk_speed = 0.0
	var risen: bool = await wait_until(func() -> bool: return skel.is_risen(), 90)
	ok(risen)
	eq(skel.health.max_hp, 2)
	skel.hurtbox.receive_hit(1, player)
	await flush(1)
	ok(is_instance_valid(skel) and not skel._dead, "one blow leaves it standing")
	eq(skel.health.current, 1)
	await flush(30)  # past Health's 0.45s i-frames
	skel.hurtbox.receive_hit(1, player)
	await flush(2)
	ok(not is_instance_valid(skel) or skel._dead, "second blow scatters it")
