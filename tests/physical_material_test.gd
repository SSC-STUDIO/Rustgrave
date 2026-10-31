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


func test_baked_object_materials_bind_to_the_authored_surfaces() -> void:
	var expected := {
		Objects.Kind.BOARD: ["board.png", Vector2(1020.0, 640.0)],
		Objects.Kind.LEDGER: ["ledger.png", Vector2(960.0, 560.0)],
		Objects.Kind.PLATE: ["plate.png", Vector2(1120.0, 640.0)],
		Objects.Kind.JOURNAL: ["journal.png", Vector2(880.0, 580.0)],
		Objects.Kind.LETTER: ["letter.png", Vector2(640.0, 420.0)],
	}
	for kind in expected:
		var sb := Objects.style_box(kind, Vector2(420.0, 300.0))
		ok(sb is StyleBoxTexture, "kind %d returns a textured material shell" % kind)
		if sb is StyleBoxTexture:
			var tex := (sb as StyleBoxTexture).texture
			var name: String = expected[kind][0]
			var want_size: Vector2 = expected[kind][1]
			eq(String(tex.get_meta(&"source_path", tex.resource_path)), "res://assets/ui/objects/" + name,
					"kind %d consumes the authored %s surface" % [kind, name])
			eq(tex.get_size(), want_size, "kind %d preserves authored pixel dimensions" % kind)
			var image := tex.get_image()
			ok(image.get_used_rect().size.x > 0 and image.get_used_rect().size.y > 0,
					"kind %d material has non-empty authored pixels" % kind)


func test_paper_tag_and_notes_shell_use_baked_paper_and_wash_is_subtle() -> void:
	var tag := Objects.journey_tag_style_box()
	ok(tag.texture != null, "journey tag has a paper material")
	if tag.texture != null:
		eq(String(tag.texture.get_meta(&"source_path", tag.texture.resource_path)), "res://assets/ui/objects/paper.png")
		eq(tag.texture.get_size(), Vector2(460.0, 480.0))
	var notes := Objects.style_box(Objects.Kind.NOTES, Vector2(420.0, 300.0))
	ok(notes.texture != null, "notes shell consumes the shared paper material")
	if notes.texture != null:
		eq(String(notes.texture.get_meta(&"source_path", notes.texture.resource_path)),
				"res://assets/ui/objects/paper.png", "notes uses the shared paper background")
	var wash := Objects.light_wash(Objects.Kind.LEDGER, Vector2(320.0, 240.0))
	var wash_image := wash.texture.get_image()
	var max_alpha := 0.0
	for y in wash_image.get_height():
		for x in wash_image.get_width():
			max_alpha = maxf(max_alpha, wash_image.get_pixel(x, y).a)
	ok(max_alpha <= 0.14, "baked material light wash remains a restrained overlay (%.3f)" % max_alpha)
	wash.queue_free()
	await flush(1)
