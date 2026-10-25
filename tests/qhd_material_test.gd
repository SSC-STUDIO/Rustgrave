extends TestCase


func test_terrain_themes_keep_logical_tiles_with_four_times_physical_detail() -> void:
	for name in ["slab_a", "iron_slab_a", "basalt_slab_a", "moss_slab_a", "brick_slab_a", "castle_slab_a", "rampart_slab_a"]:
		var path := "res://assets/env/%s.png" % name
		if not ResourceLoader.exists(path):
			continue
		var base := load(path) as Texture2D
		var detailed := ArtTexture.load_texture(path)
		eq(detailed.get_size(), base.get_size(), name + " logical canvas")
		eq(detailed.get_image().get_size(), Vector2i(base.get_size()) * 4, name + " physical detail")
		eq(Level01Env.opaque_bottom_px(detailed), Level01Env.opaque_bottom_px(base), name + " ground contact")


func test_title_geometry_and_ui_panels_keep_their_original_layout_contract() -> void:
	for path in ["res://assets/title/bridge.png", "res://assets/title/gear_big.png", "res://assets/ui/title_logo.png", "res://assets/ui/panel_stone.png"]:
		var base := load(path) as Texture2D
		var detailed := ArtTexture.load_texture(path)
		eq(detailed.get_size(), base.get_size())
		eq(detailed.get_image().get_size(), Vector2i(base.get_size()) * 4)
		ok(detailed.get_image().get_data() != base.get_image().get_data())


func test_packed_scene_sprites_receive_detail_before_world_ready() -> void:
	var world := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/env/ember_nest.png") as Texture2D
	sprite.position = Vector2(120, 80)
	sprite.scale = Vector2(2, 2)
	world.add_child(sprite)
	ArtTexture.adapt_scene(world)
	eq(sprite.texture.get_size(), Vector2(48, 36))
	eq(sprite.texture.get_image().get_size(), Vector2i(192, 144))
	eq(sprite.position, Vector2(120, 80))
	eq(sprite.scale, Vector2(2, 2))
	world.free()
