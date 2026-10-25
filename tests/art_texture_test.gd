extends TestCase


func test_physical_detail_keeps_logical_frames_and_original_resource_paths() -> void:
	var path := "res://assets/characters/original_executioner/idle/idle_0.png"
	var texture := ArtTexture.load_texture(path)
	eq(texture.get_size(), Vector2(100, 100))
	eq(texture.get_image().get_size(), Vector2i(400, 400))
	eq(texture.resource_path, path)
	eq(ArtTexture.load_texture(path), texture, "live texture reused")
	var nearest := (load(path) as Texture2D).get_image()
	nearest.resize(400, 400, Image.INTERPOLATE_NEAREST)
	ok(texture.get_image().get_data() != nearest.get_data(), "new contours and material edges, not enlarged PNG")
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = 2
	eq(sprite.get_rect().size, Vector2(50, 100), "atlas frame geometry stays logical")
	sprite.free()


func test_unavailable_detail_falls_back_and_cache_does_not_own_texture() -> void:
	var path := "res://assets/characters/original_capstan_warden/idle/idle_0.png"
	var texture := ArtTexture.load_texture(path)
	var reference: WeakRef = weakref(texture)
	texture = null
	ok(reference.get_ref() == null, "weak lookup releases unused QHD image")
	var fallback := "res://assets/title/glow.png"
	# This file deliberately keeps the original texture until a detailed sibling exists.
	var loaded := ArtTexture.load_texture(fallback)
	ok(loaded != null)
	eq(loaded.get_size(), (load(fallback) as Texture2D).get_size())


func test_animation_cache_has_a_bounded_memory_budget() -> void:
	for action in ["idle", "pendulum", "chain_pull", "bell_drop", "toll_wave", "stagger"]:
		ok(not CharFrames.anim("original_hollow_bell", action).is_empty())
	ok(CharFrames._cache_bytes <= CharFrames.MAX_CACHE_BYTES)
	var held := CharFrames.anim("original_executioner", "idle")
	for action in ["hot_pendulum", "hot_chain_pull", "hot_bell_drop", "hot_toll_wave"]:
		CharFrames.anim("original_hollow_bell", action)
	ok(held[0] != null, "eviction preserves resources referenced by live animations")
	ok(CharFrames._cache_bytes <= CharFrames.MAX_CACHE_BYTES)
