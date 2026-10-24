extends TestCase
## 塌陷台：抖 → 塌 → 回的时间线、碰撞随状态开关、骑士站上去会触发、
## 骑士还压在原位时先不长回来。

func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	return host


func _platform(host: Node2D, pos: Vector2 = Vector2(200, -48), width: float = 96.0,
		props: Dictionary = {}) -> CollapsingPlatform:
	var layout := ChapterLayout.new()
	add_child(layout)
	return layout.collapsing(host, "RustBeam", pos, width, "moss_float", props)


func _shapes(plat: CollapsingPlatform) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	for child in plat.get_children():
		if child is CollisionShape2D:
			out.append(child as CollisionShape2D)
	return out


func test_timeline_shake_fall_return() -> void:
	var plat := _platform(_host())
	plat.set_physics_process(false)
	await flush(1)
	eq(plat.state(), CollapsingPlatform.State.IDLE)
	ok(plat.is_solid())
	ok(plat.trigger(), "first trigger starts the shake")
	ok(not plat.trigger(), "a second trigger while shaking is ignored")
	eq(plat.state(), CollapsingPlatform.State.SHAKING)
	plat.tick(plat.shake_time * 0.5)
	eq(plat.state(), CollapsingPlatform.State.SHAKING)
	plat.tick(plat.shake_time * 0.6)
	eq(plat.state(), CollapsingPlatform.State.FALLEN)
	ok(plat.is_collapsed() and not plat.is_solid())
	await flush(2)
	var shapes := _shapes(plat)
	ok(not shapes.is_empty(), "the platform has collision")
	for shape in shapes:
		ok(shape.disabled, "fallen: collision off")
	plat.tick(plat.fall_time + 0.1)
	var skin := plat.get_node("Skin") as Node2D
	ok(not skin.visible, "the fallen slab has faded out")
	plat.tick(plat.respawn_time + 0.1)
	eq(plat.state(), CollapsingPlatform.State.RETURNING)
	await flush(2)
	for shape in shapes:
		ok(not shape.disabled, "returning: collision back on")
	plat.tick(0.5)
	eq(plat.state(), CollapsingPlatform.State.IDLE)
	ok(skin.visible)
	almost(skin.modulate.a, 1.0, 0.001)
	almost(skin.position.length(), 0.0, 0.001)


func test_visuals_live_in_a_single_skin_container() -> void:
	var plat := _platform(_host())
	await flush(1)
	var skin := plat.get_node_or_null("Skin") as Node2D
	ok(skin != null, "Skin container exists")
	var loose := 0
	for child in plat.get_children():
		if child is Sprite2D or child is ColorRect:
			loose += 1
	eq(loose, 0, "no sprite is left outside the container (so shaking moves them all)")
	ok(skin.get_child_count() > 0, "the tiles are inside")
	plat.apply_tone(Color(0.8, 0.8, 0.8))
	loose = 0
	for child in plat.get_children():
		if child is Sprite2D or child is ColorRect:
			loose += 1
	eq(loose, 0, "re-toning keeps the container")


func test_a_knight_standing_on_it_makes_it_shake_then_drop() -> void:
	var host := _host()
	build_floor(host)
	var plat := _platform(host, Vector2(280, -48), 96.0, {"shake_time": 0.5, "respawn_time": 60.0})
	var player := await spawn_player(host, Vector2(328, -90))
	var shook := await wait_until(func() -> bool:
		return plat.state() != CollapsingPlatform.State.IDLE, 120)
	ok(shook, "standing on the beam starts the shake")
	var fell := await wait_until(func() -> bool:
		return plat.state() == CollapsingPlatform.State.FALLEN, 120)
	ok(fell, "and the shake ends in a collapse")
	await flush(50)
	ok(player.global_position.y > -12.0, "the knight dropped to the floor (y=%.0f)" % player.global_position.y)


func test_it_waits_while_the_knight_is_inside_its_footprint() -> void:
	var host := _host()
	build_floor(host)
	var plat := _platform(host, Vector2(280, -48), 96.0, {"respawn_time": 0.2})
	plat.set_physics_process(false)
	var player := await spawn_player(host, Vector2(328, -20))
	player.position = Vector2(328, -40)
	player.velocity = Vector2.ZERO
	plat.trigger()
	plat.tick(plat.shake_time + 0.01)
	eq(plat.state(), CollapsingPlatform.State.FALLEN)
	await flush(2)
	player.global_position = Vector2(328, -40)
	player.set_physics_process(false)
	# 物理服务器的空间查询要等下一个物理帧才看得到被直接挪过去的刚体。
	await flush(1)
	plat.tick(plat.fall_time + plat.respawn_time + 0.5)
	eq(plat.state(), CollapsingPlatform.State.FALLEN, "a knight inside the footprint keeps it from growing back")
	player.global_position = Vector2(328, 100)
	await flush(2)
	plat.tick(0.1)
	await flush(1)
	eq(plat.state(), CollapsingPlatform.State.RETURNING, "once clear it returns")


func test_sanity_refuses_a_nest_on_a_collapsing_beam() -> void:
	var host := _host()
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.floor_strip(host, "Floor", 0.0, 800.0, "moss")
	layout.collapsing(host, "Beam", Vector2(300, 240), 96.0)
	layout.nest(host, "NestOnBeam", 340.0, 240.0)
	var problems := LevelSanity.check(host)
	var found := false
	for p in problems:
		if p.contains("collapsing") and p.contains("NestOnBeam"):
			found = true
	ok(found, "a nest on a collapsing beam is reported: %s" % [problems])
