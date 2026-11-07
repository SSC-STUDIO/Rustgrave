extends TestCase
## The shared low-resolution 3D stage grew a supersampling factor for the 3D
## title screen. render_scale 1 must keep the arena's old 1:1 behaviour exactly
## (same render-target size, same subpixel shift rounding), and render_scale 2-3
## must only grow the render target while the output texel grid, the integer
## upscale and the physical-pixel shift math stay unchanged.

const STAGE := preload("res://scripts/moba/view/pixel_stage.gd")

var _stage


func setup() -> void:
	_stage = STAGE.new()
	_stage.fill_screen = false
	add_child(_stage)


func teardown() -> void:
	if is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null


func _output_target() -> Vector2i:
	return _stage.internal_size + Vector2i(_stage.MARGIN, _stage.MARGIN) * 2


func _physical(position: Vector2) -> Vector2:
	return position * _stage._root_scale


func test_default_is_unsupersampled() -> void:
	eq(_stage.render_scale, 1, "arena default render_scale")
	eq(_stage.internal_size, Vector2i(640, 360), "output grid stays 640x360")
	eq(_stage.viewport.size, _output_target(), "viewport is output grid + 2 texel margin")
	eq(_stage._post.get_shader_parameter("render_scale"), 1)
	eq(_stage._post.get_shader_parameter("output_size"), Vector2(_output_target()))


func test_supersampling_scales_only_the_render_target() -> void:
	_stage.set_render_scale(2)
	eq(_stage.render_scale, 2)
	eq(_stage.internal_size, Vector2i(640, 360), "output grid unchanged")
	eq(_stage.viewport.size, _output_target() * 2, "render target doubles")
	eq(_stage._post.get_shader_parameter("render_scale"), 2)
	eq(_stage._post.get_shader_parameter("source_size"), Vector2(_output_target() * 2))
	# One output texel must still cover `pixel_scale` physical pixels: the image
	# shows render pixels, so it is drawn 1/render_scale as large per texture pixel.
	almost(
		_stage.image.scale.x * _stage._root_scale.x * 2.0,
		float(_stage.pixel_scale),
		0.0001,
		"one output texel is pixel_scale physical pixels"
	)


func test_supersampling_three_matches_three_times_target() -> void:
	_stage.set_render_scale(3)
	eq(_stage.viewport.size, _output_target() * 3)
	eq(_stage._post.get_shader_parameter("render_scale"), 3)


func test_render_scale_is_clamped() -> void:
	_stage.set_render_scale(0)
	eq(_stage.render_scale, 1)
	_stage.set_render_scale(9)
	eq(_stage.render_scale, 3)
	eq(_stage.viewport.size, _output_target() * 3)


func test_post_params_are_forwarded() -> void:
	_stage.set_post_params({"vignette_strength": 0.42, "grain_strength": 0.1, "tint": Color(1, 0.9, 0.8)})
	almost(float(_stage._post.get_shader_parameter("vignette_strength")), 0.42)
	almost(float(_stage._post.get_shader_parameter("grain_strength")), 0.1)
	eq(_stage._post.get_shader_parameter("tint"), Color(1, 0.9, 0.8))


func test_subpixel_shift_lands_on_whole_physical_pixels() -> void:
	_stage.set_render_scale(2)
	_stage.set_camera_offset(Vector2.ZERO, Vector2i.ZERO)
	var base: Vector2 = _stage.image.position
	_stage.set_camera_offset(Vector2(0.5, -0.5), Vector2i.ZERO)
	var moved: Vector2 = _stage.image.position
	var expected := roundf(0.5 * float(_stage.pixel_scale))
	almost(absf(_physical(Vector2(moved.x - base.x, 0.0)).x), expected, 0.0001, "x shift is whole physical pixels")
	almost(absf(_physical(Vector2(0.0, moved.y - base.y)).y), expected, 0.0001, "y shift is whole physical pixels")
	eq(_stage._post.get_shader_parameter("texel_origin"), Vector2.ZERO, "texel origin pinned to world")


func test_fill_screen_keeps_output_rows_at_base_height() -> void:
	_stage.set_fill_screen(true)
	# Cover mode derives the row count from the real window and the integer scale,
	# plus an odd-row parity fix. Assert the documented formula, not a hard number
	# (the headless window size is whatever the host reports).
	var phys := Vector2(get_tree().root.size)
	var expected_scale := maxi(1, floori(phys.y / float(_stage.base_height)))
	var expected_height := ceili(phys.y / float(expected_scale))
	expected_height += expected_height & 1
	eq(_stage.internal_size.y, expected_height,
			"cover mode rows = ceil(window rows / scale) (+parity)")
	eq(_stage.render_scale, 1, "render scale survives relayout")
	eq(_stage.viewport.size, _output_target(), "viewport follows the new output grid")
