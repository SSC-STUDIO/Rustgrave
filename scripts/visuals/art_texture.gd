class_name ArtTexture
extends RefCounted
## Physical QHD texels with the original logical dimensions. ImageTexture's
## size override keeps sprite frames, offsets, region crops and collision anchors
## in world units while the GPU still samples the detailed physical image.

static var _cache: Dictionary = {}
static var enabled := true


static func load_texture(path: String) -> Texture2D:
	if not enabled:
		return load(path) as Texture2D
	if _cache.has(path):
		var cached: Texture2D = (_cache[path] as WeakRef).get_ref() as Texture2D
		if cached != null:
			return cached
	var original := load(path) as Texture2D
	if original == null:
		return null
	var detailed_path := path.replace("res://assets/", "res://assets/qhd/")
	if detailed_path == path or not ResourceLoader.exists(detailed_path):
		return original
	var detail := load(detailed_path) as Texture2D
	if detail == null:
		return original
	var image := detail.get_image()
	if image == null:
		return original
	var texture := ImageTexture.create_from_image(image)
	texture.set_size_override(Vector2i(original.get_size()))
	texture.set_path_cache(path)
	texture.set_meta("physical_bytes", image.get_data_size())
	# Live sprites retain their own resources; this lookup must not retain every
	# boss and backdrop from all previously visited chapters.
	_cache[path] = weakref(texture)
	return texture
