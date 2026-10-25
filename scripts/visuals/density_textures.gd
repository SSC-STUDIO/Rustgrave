class_name DensityTextures
extends RefCounted
## Companion art has more texels, but the original logical size. Sprite anchors,
## atlas regions and platform geometry therefore do not depend on screen density.
## Weak caching shares live textures without retaining every visited chapter.

static var _cache: Dictionary = {}
const REDRAWS := preload("res://scripts/visuals/redrawn_texture_catalog.gd")


## Authored scene sprites are instantiated before their _ready hooks. Replacing
## their backing texels here keeps logical sizes, atlas regions and all physics.
static func apply_to_scene(node: Node) -> void:
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			var path := source_path(sprite.texture)
			if path.begins_with("res://assets/") and path.ends_with(".png"):
				var detailed := load_texture(path)
				if detailed != null:
					sprite.texture = detailed
	for child in node.get_children():
		apply_to_scene(child)


static func load_texture(path: String) -> Texture2D:
	if _cache.has(path):
		var existing := (_cache[path] as WeakRef).get_ref() as Texture2D
		if existing != null:
			return existing
	if not ResourceLoader.exists(path):
		return null
	var original := load(path) as Texture2D
	if original == null:
		return null
	var companion: String = REDRAWS.REPLACEMENTS.get(path, path.replace("res://assets/", "res://assets/qhd/"))
	if companion == path or not ResourceLoader.exists(companion):
		return original
	var detail := load(companion) as Texture2D
	if detail == null:
		return original
	var image := detail.get_image()
	if image == null:
		return original
	var texture := ImageTexture.create_from_image(image)
	texture.set_size_override(Vector2i(original.get_size()))
	texture.set_meta("source_path", path)
	texture.set_meta("physical_bytes", image.get_data_size())
	texture.resource_name = original.resource_name
	# A separate identity avoids replacing the ResourceLoader cache of source art.
	texture.resource_path = "res://qhd-runtime/" + path.trim_prefix("res://assets/")
	_cache[path] = weakref(texture)
	return texture


static func source_path(texture: Texture2D) -> String:
	return str(texture.get_meta("source_path", texture.resource_path)) if texture != null else ""


static func logical_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	if not texture.has_meta("source_path"):
		return texture.get_image()
	var source := load(source_path(texture)) as Texture2D
	return source.get_image() if source != null else texture.get_image()
