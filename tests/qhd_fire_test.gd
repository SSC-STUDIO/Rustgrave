extends TestCase


func test_shrine_fire_has_physical_detail_and_a_fixed_fuel_root() -> void:
	var tex := ArtTexture.load_texture(EmberNest.FLAME_PATH)
	eq(tex.get_size(), Vector2(128, 24))
	var image := tex.get_image()
	eq(image.get_size(), Vector2i(512, 96))
	var poses := {}
	for frame in 8:
		var cell := image.get_region(Rect2i(frame * 64, 0, 64, 96))
		poses[hash(cell.get_data())] = true
		ok(cell.get_pixel(32, 95).a > 0.9, "flame grows from fixed bottom root")
		almost(cell.get_pixel(0, 0).a, 0.0)
		almost(cell.get_pixel(63, 0).a, 0.0)
		var rect := cell.get_used_rect()
		ok(rect.end.y == 96 and rect.position.y > 0, "root never floats; tip has transparent headroom")
	eq(poses.size(), 8)


func test_live_title_forge_selects_and_advances_the_new_hearth_strip() -> void:
	var world := TitleWorld.new()
	add_child(world)
	world.set_process(false)
	var mouth := world.get_node("MassRight/ForgeMouth") as Sprite2D
	eq(mouth.hframes, 8)
	eq(mouth.texture.resource_path, "res://assets/title/forge_fire.png")
	eq(mouth.get_rect().size, Vector2(60, 66), "same aperture placement")
	eq(mouth.texture.get_image().get_size(), Vector2i(1920, 264))
	world.set("_t", 0.0)
	world.call("_animate_actors", 0.0)
	var before := mouth.frame
	world.set("_t", 0.12)
	world.call("_animate_actors", 0.0)
	ok(mouth.frame != before, "actual title animates the furnace")
	world.queue_free()
	await flush(2)
