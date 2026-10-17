extends TestCase
## 多分辨率与多屏幕比例适配单元测试。
## 验证 16:9 (1080p/2K/4K)、16:10 (Steam Deck)、21:9 (带鱼屏)、4:3 (复古屏) 的
## 视口比例判定、缩放模式及 HUD/标题 UI 控件锚点完整性。

const HUD_SCENE := "res://scenes/ui/HUD.tscn"
const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"


func test_common_resolutions_defined() -> void:
	var presets := DisplayFit.PRESET_RESOLUTIONS
	ok(presets.size() >= 8, "has at least 8 standard resolution presets")
	ok(Vector2i(1280, 720) in presets, "contains 720p base")
	ok(Vector2i(1920, 1080) in presets, "contains 1080p standard")
	ok(Vector2i(2560, 1440) in presets, "contains 1440p 2K")
	ok(Vector2i(3840, 2160) in presets, "contains 4K UHD")
	ok(Vector2i(1280, 800) in presets, "contains Steam Deck 1280x800")
	ok(Vector2i(1920, 1200) in presets, "contains 16:10 laptop 1920x1200")
	ok(Vector2i(2560, 1080) in presets, "contains 21:9 ultrawide")
	ok(Vector2i(1024, 768) in presets, "contains 4:3 legacy")


func test_aspect_ratio_detection_math() -> void:
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(1280, 720)), "16:9")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(1920, 1080)), "16:9")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(2560, 1440)), "16:9")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(3840, 2160)), "16:9")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(1280, 800)), "16:10 (Deck/掌机)")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(1920, 1200)), "16:10 (Deck/掌机)")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(2560, 1080)), "21:9 (超宽带鱼屏)")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(3440, 1440)), "21:9 (超宽带鱼屏)")
	eq(DisplayFit.get_aspect_ratio_name(Vector2i(1024, 768)), "4:3 (复古方屏)")


func test_fit_modes_behavior() -> void:
	DisplayFit.apply_fit_mode(DisplayFit.FitMode.ADAPTIVE)
	eq(int(DisplayFit.get_fit_mode()), int(DisplayFit.FitMode.INTEGER))
	ok("整数" in DisplayFit.fit_mode_label(), "legacy adaptive request uses pixel presentation")

	DisplayFit.apply_fit_mode(DisplayFit.FitMode.EXPAND)
	eq(int(DisplayFit.get_fit_mode()), int(DisplayFit.FitMode.INTEGER))
	ok("整数" in DisplayFit.fit_mode_label(), "legacy expand request keeps authored framing")

	DisplayFit.apply_fit_mode(DisplayFit.FitMode.INTEGER)
	eq(int(DisplayFit.get_fit_mode()), int(DisplayFit.FitMode.INTEGER))
	ok("整数" in DisplayFit.fit_mode_label(), "label matches integer")

	DisplayFit.apply_fit_mode(DisplayFit.FitMode.ADAPTIVE)


func test_hud_anchors_and_bounds() -> void:
	var hud_packed := load(HUD_SCENE) as PackedScene
	ok(hud_packed != null, "HUD scene loads")
	var hud := hud_packed.instantiate() as CanvasLayer
	add_child(hud)
	await get_tree().process_frame

	var root := hud.get_node_or_null("Root") as Control
	ok(root != null, "HUD Root control exists")
	ok(root.anchor_right == 1.0 and root.anchor_bottom == 1.0, "root is full rect")

	var stat_panel := root.get_node_or_null("StatPanel") as Control
	ok(stat_panel != null, "StatPanel exists")
	ok(stat_panel.anchor_left == 0.0 and stat_panel.anchor_top == 0.0, "StatPanel is left-anchored")

	var banner := root.get_node_or_null("Banner") as Control
	ok(banner != null, "Banner exists")
	ok(banner.anchor_left == 0.5 and banner.anchor_right == 0.5 and banner.anchor_top == 0.0, "Banner is center-top anchored")

	var boss_bar := root.get_node_or_null("BossBar") as Control
	ok(boss_bar != null, "BossBar exists")
	ok(boss_bar.anchor_left == 0.5 and boss_bar.anchor_right == 0.5 and boss_bar.anchor_bottom == 1.0, "BossBar is center-bottom anchored")

	var prompt := root.get_node_or_null("Prompt") as Control
	ok(prompt != null, "Prompt exists")
	ok(prompt.anchor_left == 0.5 and prompt.anchor_right == 0.5 and prompt.anchor_bottom == 1.0, "Prompt is center-bottom anchored")

	hud.queue_free()
	await get_tree().process_frame


func test_title_screen_anchors() -> void:
	var title_packed := load(TITLE_SCENE) as PackedScene
	ok(title_packed != null, "TitleScreen scene loads")
	var title := title_packed.instantiate() as Control
	add_child(title)
	await get_tree().process_frame

	eq(title.size, Vector2(1280, 720), "TitleScreen keeps the native UI design size")
	ok(title.has_meta("presentation_control_bound"),
			"TitleScreen binds its transform to the presentation content rect")
	ok(title.get_node_or_null("WindowBackdrop/Black") != null,
			"TitleScreen keeps the letterbox bars black, like GamePresentation")
	var presentation: Transform2D = PresentationMetrics.for_window(get_tree().root)["ui_transform"]
	ok(title.position.is_equal_approx(presentation.origin), "TitleScreen shares the physical content origin")
	ok(title.scale.is_equal_approx(presentation.get_scale()), "TitleScreen compensates for per-axis root scaling")
	var keyart := title.get_node_or_null("Keyart") as TextureRect
	ok(keyart != null, "Keyart exists")
	eq(int(keyart.stretch_mode), int(TextureRect.STRETCH_KEEP_ASPECT_COVERED),
			"Keyart keeps aspect covered across any ratio")

	title.queue_free()
	await get_tree().process_frame
