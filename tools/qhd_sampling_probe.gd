extends Node
## Run in a real GPU window. Verify one physical texel survives logical size
## overrides, sprite frames, AtlasTexture and terrain-style region drawing.

const OUT := "res://screenshots/acceptance/qhd/sampling"


class RegionDraw extends Node2D:
	var texture: Texture2D
	var tiled := false
	func _draw() -> void:
		if tiled:
			draw_texture_rect(texture, Rect2(0, 0, 8, 4), true)
		else:
			ArtTexture.draw_region(self, texture, Rect2(0, 0, 4, 4), Rect2(4, 0, 4, 4))


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 32:
			image.set_pixel(x, y, Color.BLUE if x < 16 else (Color.RED if (x + y) % 2 else Color.GREEN))
	var texture := ImageTexture.create_from_image(image)
	texture.set_size_override(Vector2i(8, 4))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 32)
	viewport.size_2d_override = Vector2i(16, 8)
	viewport.size_2d_override_stretch = true
	viewport.disable_3d = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.hframes = 2
	sprite.frame = 1
	viewport.add_child(sprite)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(4, 0, 4, 4)
	var atlas_sprite := Sprite2D.new()
	atlas_sprite.texture = atlas
	atlas_sprite.centered = false
	atlas_sprite.position.x = 4
	viewport.add_child(atlas_sprite)
	var regions := RegionDraw.new()
	regions.texture = texture
	regions.position.y = 4
	viewport.add_child(regions)
	var cropped_sprite := Sprite2D.new()
	cropped_sprite.texture = texture
	cropped_sprite.centered = false
	cropped_sprite.region_enabled = true
	cropped_sprite.region_rect = Rect2(4, 0, 4, 4)
	cropped_sprite.position = Vector2(4, 4)
	viewport.add_child(cropped_sprite)
	var tiled := RegionDraw.new()
	tiled.texture = texture
	tiled.tiled = true
	tiled.position.x = 8
	viewport.add_child(tiled)
	for i in 4:
		await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	result.save_png(OUT + "/physical-texel-sampling.png")
	var checks := {}
	for item in [["sprite_frame", Vector2i(0, 0)], ["atlas_region", Vector2i(16, 0)], ["draw_region", Vector2i(0, 16)], ["sprite_region", Vector2i(16, 16)]]:
		var correct := true
		var origin: Vector2i = item[1]
		for y in 16:
			for x in 16:
				if not result.get_pixelv(origin + Vector2i(x, y)).is_equal_approx(image.get_pixel(x + 16, y)):
					correct = false
		checks[item[0]] = correct
	var tiled_correct := true
	for y in 16:
		for x in 32:
			if not result.get_pixel(x + 32, y).is_equal_approx(image.get_pixel(x, y)):
				tiled_correct = false
	checks["tiled_draw"] = tiled_correct
	var passed := not checks.values().has(false)
	var report := {"passed": passed, "checks": checks, "renderer": RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open(OUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("QHD_SAMPLING ", JSON.stringify(report))
	get_tree().quit(0 if passed else 1)
