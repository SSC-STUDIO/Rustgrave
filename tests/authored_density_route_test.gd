extends TestCase


func test_authored_sprites_receive_detail_before_ready_without_moving_geometry() -> void:
	var world := Node2D.new()
	var nested := Node2D.new()
	world.add_child(nested)
	var sprite := Sprite2D.new()
	var original := load("res://assets/title/hammer_head.png") as Texture2D
	sprite.texture = original
	sprite.position = Vector2(31, -42)
	sprite.scale = Vector2(1.7, 1.7)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 12, 10)
	sprite.flip_h = true
	nested.add_child(sprite)
	DensityTextures.apply_to_scene(world)
	ok(not world.is_inside_tree(), "conversion is safe before ready hooks")
	ok(sprite.texture is ImageTexture, "authored sprite uses actual detail texels")
	eq(sprite.texture.get_size(), original.get_size(), "logical canvas stays authored")
	ok(sprite.texture.get_image().get_width() >= original.get_width() * 4)
	eq(sprite.position, Vector2(31, -42))
	eq(sprite.scale, Vector2(1.7, 1.7))
	eq(sprite.region_rect, Rect2(0, 0, 12, 10))
	ok(sprite.flip_h)
	world.free()


func test_soft_effects_and_unbacked_atlases_keep_their_texture_contract() -> void:
	var world := Node2D.new()
	var glow := Sprite2D.new()
	glow.texture = load("res://assets/title/glow.png")
	var original := glow.texture
	world.add_child(glow)
	var sprite := Sprite2D.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = original
	atlas.region = Rect2(0, 0, 8, 8)
	sprite.texture = atlas
	world.add_child(sprite)
	DensityTextures.apply_to_scene(world)
	eq(glow.texture, original, "soft glow keeps its authored texture")
	eq(sprite.texture, atlas, "region textures retain their atlas identity")
	world.free()
