extends TestCase

const CATALOG := preload("res://scripts/visuals/redrawn_texture_catalog.gd")


func test_redraws_keep_source_canvas_and_alpha_on_the_native_texture_route() -> void:
	ok(CATALOG.REPLACEMENTS.size() >= 30, "the redraw batch is registered")
	for path in CATALOG.REPLACEMENTS:
		var source := load(path) as Texture2D
		var detail := DensityTextures.load_texture(path)
		ok(detail is ImageTexture, "actual detailed pixels are active: " + path)
		eq(detail.get_size(), source.get_size(), "the source logical canvas remains authoritative")
		var old_image := source.get_image()
		var image := detail.get_image()
		var density := image.get_width() / old_image.get_width()
		ok(density >= 4, "native QHD texel density: " + path)
		eq(image.get_size(), old_image.get_size() * density, "uniform density preserves proportions")
		var mask_preserved := true
		for y in range(0, old_image.get_height(), 3):
			for x in range(0, old_image.get_width(), 3):
				if absf(image.get_pixel(x * density, y * density).a - old_image.get_pixel(x, y).a) > 0.005:
					mask_preserved = false
		ok(mask_preserved, "source silhouettes and transparent gaps stay intact: " + path)
