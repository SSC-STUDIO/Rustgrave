extends TestCase

const Objects := preload("res://scripts/ui/ui_object.gd")


func test_paper_theme_has_ink_without_scene_font_outline_and_reuses_cache() -> void:
	for kind in [Objects.Kind.LEDGER, Objects.Kind.JOURNAL, Objects.Kind.LETTER]:
		var theme := Objects.surface_theme(kind)
		eq(theme, Objects.surface_theme(kind))
		for type in [&"HeadLabel", &"BodyLabel", &"FootnoteLabel", &"MenuItemLabel"]:
			eq(theme.get_constant("outline_size", type), 0)
			var paper: Color = Objects.PAL["parchment_base"]
			var ink := theme.get_color("font_color", type)
			var contrast := (paper.srgb_to_linear().get_luminance() + 0.05) / (ink.srgb_to_linear().get_luminance() + 0.05)
			ok(contrast >= 4.5, "%s ink contrast on paper is %.2f" % [type, contrast])
			almost(theme.get_color("font_shadow_color", type).a, 0.0, 0.001)


func test_setting_ink_and_controls_stay_on_their_respective_pages() -> void:
	var settings := SettingsScreen.new()
	add_child(settings)
	settings.open()
	await flush(3)
	var card := settings.get_node("ModalRoot/Card") as Control
	var slider := settings.slider_for(&"Master")
	var name_label := slider.get_parent().get_node("Name") as Label
	var spine := card.global_position.x + card.size.x * 0.5
	ok(name_label.get_global_rect().end.x < spine - 12.0)
	ok(slider.get_global_rect().position.x > spine + 12.0)
	ok(name_label.get_theme_color("font_color").get_luminance() < 0.22)
	ok(settings.get_node("ModalRoot/SceneCopy") is BackBufferCopy)
	ok(settings.get_node("ModalRoot/SceneBlur").material is ShaderMaterial)
	settings.close()
	settings.queue_free()
	await flush(1)
