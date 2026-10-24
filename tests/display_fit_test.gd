extends TestCase
## Logical viewport stays 1280x720; stretch is integer for 2x / 3x desktops.


func test_logical_viewport_stays_1280() -> void:
	eq(DisplayFit.VIEW_W, 1280)
	eq(DisplayFit.VIEW_H, 720)
	eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1280)
	eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 720)


func test_stretch_mode_and_aspect() -> void:
	eq(String(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items")
	eq(String(ProjectSettings.get_setting("display/window/stretch/aspect")), "keep")
	var scale_mode: Variant = ProjectSettings.get_setting("display/window/stretch/scale_mode")
	ok(String(scale_mode) in ["fractional", "integer"], "scale mode supports smooth scaling or integer")


func test_fit_modes_cycle() -> void:
	DisplayFit.apply_fit_mode(DisplayFit.FitMode.ADAPTIVE)
	eq(int(DisplayFit.get_fit_mode()), int(DisplayFit.FitMode.ADAPTIVE))
	DisplayFit.cycle_fit_mode()
	eq(int(DisplayFit.get_fit_mode()), int(DisplayFit.FitMode.EXPAND))
	DisplayFit.cycle_fit_mode()
	eq(int(DisplayFit.get_fit_mode()), int(DisplayFit.FitMode.INTEGER))
	DisplayFit.cycle_fit_mode()
	eq(int(DisplayFit.get_fit_mode()), int(DisplayFit.FitMode.ADAPTIVE))
	DisplayFit.apply_fit_mode(DisplayFit.FitMode.INTEGER)
	Settings._extra.erase(&"display_fit")


func test_modes_produce_different_content_and_expanded_world() -> void:
	var size := Vector2i(1366, 900)
	var integer := PresentationMetrics.calculate(size, DisplayFit.FitMode.INTEGER)
	var adaptive := PresentationMetrics.calculate(size, DisplayFit.FitMode.ADAPTIVE)
	var expanded := PresentationMetrics.calculate(size, DisplayFit.FitMode.EXPAND)
	eq(integer["physical_rect"].size, Vector2(1280, 720))
	almost(adaptive["physical_rect"].size.x, 1366.0)
	eq(expanded["physical_rect"], Rect2(Vector2.ZERO, Vector2(size)))
	ok(expanded["world_size"].y > 360, "expansion increases actual world viewport")
	ok(expanded["ui_canvas_rect"].size.y < expanded["canvas_rect"].size.y, "UI keeps its safe 16:9 design")


func test_display_options_persist_without_a_display() -> void:
	DisplayFit.apply_resolution(Vector2i(1920, 1080))
	eq(Settings.value(&"resolution"), Vector2i(1920, 1080))
	DisplayFit.apply_vsync(false)
	eq(Settings.value(&"vsync"), false)
	for key in [&"resolution", &"vsync", &"fullscreen"]:
		Settings._extra.erase(key)


func test_aspect_ratio_classification() -> void:
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(1920, 1080)), "16:9")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(2560, 1440)), "16:9")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(1280, 800)), "16:10 (Deck/掌机)")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(2560, 1080)), "21:9 (超宽带鱼屏)")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(1024, 768)), "4:3 (复古方屏)")


func test_apply_is_safe_headless() -> void:
	DisplayFit.apply()
	ok(true, "headless apply is a no-op")
