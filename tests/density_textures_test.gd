extends TestCase


func test_density_changes_texel_count_without_changing_geometry() -> void:
	for path in ["res://assets/env/ember_nest.png", "res://assets/title/forge_mouth.png", "res://assets/title/gear_big.png", "res://assets/ui/title_logo.png"]:
		if not ResourceLoader.exists(path):
			continue
		var source := load(path) as Texture2D
		var detail := DensityTextures.load_texture(path)
		ok(detail is ImageTexture, "companion is active: " + path)
		eq(detail.get_size(), source.get_size(), "sprite size / atlas geometry is unchanged")
		eq(detail.get_image().get_size(), Vector2i(source.get_size()) * 4, "four actual texels per world unit")
		eq(DensityTextures.source_path(detail), path, "audits retain original asset identity")
		eq(DensityTextures.load_texture(path), detail, "live assets share the same texture")
		eq(DensityTextures.logical_image(detail).get_size(), source.get_image().get_size())


func test_missing_companion_preserves_original_and_missing_asset_returns_null() -> void:
	var path := "res://assets/title/glow.png"
	eq(DensityTextures.load_texture(path), load(path), "soft light stays on the original texture")
	eq(DensityTextures.load_texture("res://assets/does_not_exist.png"), null)


func test_transparent_bottom_margin_keeps_props_on_the_same_ground_line() -> void:
	var path := "res://assets/env/grave_cross.png"
	var original := load(path) as Texture2D
	var detail := DensityTextures.load_texture(path)
	Level01Env._opaque_bottom_cache.clear()
	var original_bottom := Level01Env.opaque_bottom_px(original)
	Level01Env._opaque_bottom_cache.clear()
	eq(Level01Env.opaque_bottom_px(detail), original_bottom, "QHD texels cannot move the authored foot anchor")
	var host := Node2D.new()
	add_child(host)
	var feet := Vector2(140, 260)
	var prop := Level01Env.plant_texture(host, detail, path, feet, 1.0)
	eq(Level01Env.sprite_opaque_bottom_y(prop), feet.y, "the visible bottom rests on the requested world ground")
	host.queue_free()


func test_animation_frames_and_atlas_regions_keep_their_authored_size() -> void:
	var frames := CharFrames.anim("player_fantasy_knight", "idle")
	ok(not frames.is_empty())
	for frame in frames:
		var original := load(DensityTextures.source_path(frame)) as Texture2D
		eq(frame.get_size(), original.get_size(), "combat / foot anchors unchanged")
		eq(frame.get_image().get_size(), Vector2i(original.get_size()) * 4)
	var atlas := AtlasTexture.new()
	atlas.atlas = DensityTextures.load_texture("res://assets/title/forge_mouth.png")
	atlas.region = Rect2(60, 0, 60, 66)
	eq(atlas.get_size(), Vector2(60, 66), "frame 1 remains a logical 60x66 region")


func test_high_density_images_contain_subpixel_material_information() -> void:
	var texture := DensityTextures.load_texture("res://assets/title/bridge.png")
	var detail := texture.get_image()
	var expanded := DensityTextures.logical_image(texture)
	expanded.resize(detail.get_width(), detail.get_height(), Image.INTERPOLATE_NEAREST)
	var different := 0
	for y in detail.get_height():
		for x in detail.get_width():
			if detail.get_pixel(x, y) != expanded.get_pixel(x, y):
				different += 1
	ok(different > 100, "companion contains detail beyond a nearest-expanded original")


func test_companion_art_has_no_white_rim_on_transparent_edges() -> void:
	# Decode the PNG bytes directly: the editor's import cache may still hold older pixels.
	var paths := [
		"res://assets/qhd/characters/flying_demon/idle/idle_1.png",
		"res://assets/qhd/env/props/rampart/balustrade.png",
		"res://assets/qhd/env/column_big.png",
	]
	for path in paths:
		var image := Image.new()
		var err := image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		ok(err == OK, "companion PNG decodes: " + path)
		if err != OK:
			continue
		var rim := _white_rim_count(image)
		ok(rim == 0, "%d white outline texels in %s" % [rim, path])


## Opaque texels with all channels >= 215 that touch a fully transparent texel.
## Transparent texels often store white RGB, so upscaling that copies them
## leaves a bright outline along the silhouette.
static func _white_rim_count(image: Image) -> int:
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	var w := image.get_width()
	var h := image.get_height()
	var rim := 0
	for y in h:
		for x in w:
			var i := (y * w + x) * 4
			var near_white := mini(data[i], mini(data[i + 1], data[i + 2])) >= 215
			if data[i + 3] == 0 or not near_white:
				continue
			for n in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
				if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and data[(n.y * w + n.x) * 4 + 3] == 0:
					rim += 1
					break
	return rim
