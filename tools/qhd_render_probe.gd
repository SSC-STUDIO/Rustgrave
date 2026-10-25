extends Node
## Run with a real renderer (not --headless). Verifies single physical texels,
## source-region UVs, and logical camera coordinates at QHD.

class InputRecorder extends Node2D:
	var last_position := Vector2.INF
	var last_world := Vector2.INF
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			last_position = event.position
			last_world = get_canvas_transform().affine_inverse() * last_position

class InputPresentation extends GamePresentation:
	func _ready() -> void:
		pass # Exercise the inherited input path without loading a campaign level.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	PresentationMetrics.configure_world(viewport, PresentationMetrics.calculate(Vector2i(2560, 1440)))
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	get_tree().root.add_child(viewport)
	var camera := Camera2D.new()
	camera.position = Vector2(320, 180)
	viewport.add_child(camera)
	var image := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.set_pixel(8, 8, Color.WHITE)
	image.set_pixel(72, 8, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	texture.set_size_override(Vector2i(32, 16))
	for index in 2:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = texture
		sprite.position = Vector2(100 + index * 50, 100)
		if index == 1:
			sprite.region_enabled = true
			sprite.region_rect = Rect2(16, 0, 16, 16)
		viewport.add_child(sprite)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var captured := viewport.get_texture().get_image()
	var checks := {
		"raster_is_qhd": captured.get_size() == Vector2i(2560, 1440),
		"logical_view": viewport.get_visible_rect().size == Vector2(640, 360),
		"sprite_single_texel": captured.get_pixel(408, 408).r > 0.9 and captured.get_pixel(408, 408).g > 0.9,
		"next_texel_is_distinct": captured.get_pixel(409, 408).g < 0.1,
		"atlas_region_texel": captured.get_pixel(608, 408).g > 0.9,
		"atlas_next_texel": captured.get_pixel(609, 408).g < 0.1,
	}
	var presentation := InputPresentation.new()
	get_tree().root.add_child(presentation)
	presentation.world_viewport = viewport
	presentation.world_image = TextureRect.new()
	presentation.add_child(presentation.world_image)
	var recorder := InputRecorder.new()
	viewport.add_child(recorder)
	camera.position = Vector2(900, 500)
	camera.force_update_scroll()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	for size in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]:
		var metrics := PresentationMetrics.calculate(size)
		PresentationMetrics.configure_world(viewport, metrics)
		var rect: Rect2 = metrics["canvas_rect"]
		presentation.world_image.position = rect.position
		presentation.world_image.size = rect.size
		camera.force_update_scroll()
		await get_tree().process_frame
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = rect.position + Vector2(390, 200) / Vector2(640, 360) * rect.size
		presentation._unhandled_input(click)
		checks["input_logical_%dx%d" % [size.x, size.y]] = recorder.last_position.is_equal_approx(Vector2(390, 200))
		checks["input_world_%dx%d" % [size.x, size.y]] = recorder.last_world.is_equal_approx(Vector2(970, 520))
	var output := "res://screenshots/acceptance/qhd-materials-20261025"
	captured.save_png(output + "/native-texel-probe.png")
	var passed := not checks.values().has(false)
	checks["passed"] = passed
	var file := FileAccess.open(output + "/native-texel-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(checks, "  ") + "\n")
	print("QHD_RENDER_PROBE ", JSON.stringify(checks))
	viewport.queue_free()
	presentation.queue_free()
	get_tree().quit(0 if passed else 1)
