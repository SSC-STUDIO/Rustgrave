extends TestCase


func test_standard_desktops_fill_with_world_texels() -> void:
	for item in [Vector3i(1280, 720, 2), Vector3i(1920, 1080, 3), Vector3i(2560, 1440, 4), Vector3i(3840, 2160, 6)]:
		var metrics := PresentationMetrics.calculate(Vector2i(item.x, item.y))
		eq(metrics["scale"], item.z)
		eq(metrics["physical_rect"], Rect2(0, 0, item.x, item.y))


func test_unusual_windows_have_integer_centered_content() -> void:
	var laptop := PresentationMetrics.calculate(Vector2i(1366, 768))
	eq(laptop["physical_rect"], Rect2(43, 24, 1280, 720))
	var deck := PresentationMetrics.calculate(Vector2i(1280, 800))
	eq(deck["physical_rect"], Rect2(0, 40, 1280, 720))
	var ultra := PresentationMetrics.calculate(Vector2i(3440, 1440))
	eq(ultra["physical_rect"], Rect2(440, 0, 2560, 1440))
	var small := PresentationMetrics.calculate(Vector2i(640, 360))
	eq(small["scale"], 1)


## 根窗口里的普通 Control（标题屏）也必须吃同一条 ui_transform，而不是铺满带黑边的窗口。
func test_control_ui_uses_the_selected_content_rect() -> void:
	var previous := DisplayFit.get_fit_mode()
	var control := Control.new()
	add_child(control)
	var fake := Window.new()
	fake.size = Vector2i(1366, 768)
	for mode in [DisplayFit.FitMode.INTEGER, DisplayFit.FitMode.ADAPTIVE, DisplayFit.FitMode.EXPAND]:
		DisplayFit.apply_fit_mode(mode)
		PresentationMetrics.apply_control(control, fake)
		var expected: Transform2D = PresentationMetrics.calculate(Vector2i(1366, 768), mode)["ui_transform"]
		ok(control.position.is_equal_approx(expected.origin),
				"control origin equals the selected UI layer origin at 1366x768")
		ok(control.scale.is_equal_approx(expected.get_scale()),
				"control scale equals the selected UI layer scale at 1366x768")
		almost(control.rotation, expected.get_rotation(), 0.0001, "control has no extra rotation")
	DisplayFit.apply_fit_mode(previous)
	fake.free()
	control.queue_free()
	await flush(1)


func test_ui_and_world_share_the_same_final_physical_rect() -> void:
	for size in [Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(1280, 800), Vector2i(3440, 1440), Vector2i(3841, 2161)]:
		var metrics := PresentationMetrics.calculate(size)
		var ui: Transform2D = metrics["ui_transform"]
		var canvas_rect: Rect2 = metrics["canvas_rect"]
		ok(ui.origin.is_equal_approx(canvas_rect.position), "UI starts at the world image")
		ok((ui * Vector2(PresentationMetrics.UI_SIZE)).is_equal_approx(canvas_rect.end), "UI covers the exact world image")
		var physical_scale := Vector2(size) / Vector2(PresentationMetrics.UI_SIZE)
		var physical: Rect2 = metrics["physical_rect"]
		ok((canvas_rect.position * physical_scale).is_equal_approx(physical.position))
		ok((canvas_rect.size * physical_scale).is_equal_approx(physical.size))


func test_world_image_runs_the_pixel_smoothing_shader() -> void:
	var shader := load("res://assets/shaders/pixel_smooth.gdshader") as Shader
	ok(shader != null, "pixel_smooth shader compiles and loads")
	if shader == null:
		return
	var code := shader.code
	ok(code.contains("uniform bool smoothing"), "shader exposes the smoothing toggle")
	ok(code.contains("uniform int scale_hint"), "shader is told the integer content scale")
	ok(code.contains("scale_hint == 3"), "3x (1080p) uses the Scale3x rule set")
	var was := GamePresentation.pixel_smoothing
	GamePresentation.pixel_smoothing = true
	var presentation := GamePresentation.new()
	add_child(presentation)
	await flush(2)
	var image := presentation.world_image
	ok(image != null and image.material is ShaderMaterial, "world image carries the smoothing material")
	if image != null and image.material is ShaderMaterial:
		var mat := image.material as ShaderMaterial
		eq(mat.shader, shader)
		eq(mat.get_shader_parameter("smoothing"), true, "on by default")
		eq(int(mat.get_shader_parameter("scale_hint")), int(PresentationMetrics.for_window(get_tree().root)["scale"]),
				"scale hint follows the window's integer scale")
		eq(image.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "neighbour samples stay exact texels")
		GamePresentation.set_pixel_smoothing(false)
		eq(mat.get_shader_parameter("smoothing"), false, "pause-menu toggle reaches the live material")
		eq(GamePresentation.pixel_smoothing_label(), "像 素 平 滑: 关")
		GamePresentation.set_pixel_smoothing(true)
		eq(GamePresentation.pixel_smoothing_label(), "像 素 平 滑: 开")
	GamePresentation.pixel_smoothing = was
	presentation.queue_free()


func test_scene_routing_keeps_the_authored_save_identifier() -> void:
	eq(GameContext.route_scene(GameContext.WORLD_PATH), "res://scenes/ui/GamePresentation.tscn")
	eq(GameContext.route_scene("res://scenes/ui/TitleScreen.tscn"), "res://scenes/ui/TitleScreen.tscn")
	eq(GameContext.route_scene("res://scenes/levels/Level01_Static.tscn"),
			"res://scenes/ui/GamePresentation.tscn")


func test_level_registers_as_the_game_world() -> void:
	var presentation := Node.new()
	presentation.name = "GamePresentation"
	add_child(presentation)
	var viewport := Node.new()
	viewport.name = "WorldViewport"
	presentation.add_child(viewport)
	var level := Level01Static.new()
	level.name = "Level01_Static"
	viewport.add_child(level)
	ok(level.is_in_group("game_world"), "Level01 joins game_world before children ready")
	eq(GameContext.world_root(level), level)
	eq(GameContext.world_scene_path(level), GameContext.WORLD_PATH)
	eq(GameContext.route_scene(GameContext.world_scene_path(level)),
			"res://scenes/ui/GamePresentation.tscn")
	var props := Node2D.new()
	props.name = "Props"
	level.add_child(props)
	var nest := Node2D.new()
	nest.name = "EmberNest"
	props.add_child(nest)
	eq(SaveData.persist_path(nest), "Props/EmberNest",
			"save keys stay scene-relative, not WorldViewport-prefixed")


func test_native_ui_uses_pixel_filter_and_automatic_font_raster_size() -> void:
	ok(get_tree().root.canvas_item_default_texture_filter in [
		CanvasItem.TEXTURE_FILTER_NEAREST,
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
		3,
	], "root canvas keeps nearest pixel filtering")
	var font := load("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf") as FontFile
	ok(font != null)
	if font != null:
		almost(font.oversampling, 0.0, 0.001, "font uses automatic oversampling for native UI")
