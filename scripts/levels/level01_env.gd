class_name Level01Env
extends Object
## Shared cemetery sprite planting for Level01 grave props and parallax silhouette.
## Hardness is the only sway rule: steel/stone never lean; trees lean; bushes lean more.

const DECOR_TREE_1 := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/tree-1.png"
const DECOR_TREE_2 := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/tree-2.png"
const DECOR_TREE_3 := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/tree-3.png"
const DECOR_BUSH_L := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/bush-large.png"
const DECOR_BUSH_S := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/bush-small.png"
const DECOR_STONE_1 := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/stone-1.png"
const DECOR_STONE_2 := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/stone-2.png"
const DECOR_STONE_3 := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/stone-3.png"
const DECOR_STONE_4 := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/stone-4.png"
const DECOR_STATUE := "res://assets/external/gothicvania_cemetery/PNG/Environment/sliced-objects/statue.png"
## 十字 + 草冢（objects.png 372,127 77×65 裁片）：一座有人埋过的坟。
const DECOR_GRAVE_CROSS := "res://assets/env/grave_cross.png"

enum Hardness { STEEL, STONE, TREE, BUSH }

const SWAY_AMPLITUDE := {
	Hardness.STEEL: 0.0,
	Hardness.STONE: 0.0,
	Hardness.TREE: 1.0,
	Hardness.BUSH: 1.45,
}
const SWAY_FREQ := {
	Hardness.STEEL: 0.0,
	Hardness.STONE: 0.0,
	Hardness.TREE: 0.82,
	Hardness.BUSH: 1.45,
}
const OPAQUE_ALPHA := 0.04


static func hardness_of(path: String) -> int:
	var name := path.get_file().get_basename().to_lower()
	if name.begins_with("tree-") or name.begins_with("tree_"):
		return Hardness.TREE
	if name.begins_with("bush-") or name.begins_with("bush_"):
		return Hardness.BUSH
	if name.begins_with("stone-") or name.begins_with("stone_") \
			or name.begins_with("statue"):
		return Hardness.STONE
	if name.contains("gate") or name.contains("door") or name.contains("gear") \
			or name.contains("iron") or name.contains("steel") or name.contains("fence"):
		return Hardness.STEEL
	return Hardness.STONE


static func sway_amplitude(path: String) -> float:
	return float(SWAY_AMPLITUDE[hardness_of(path)])


static func sway_freq(path: String) -> float:
	return float(SWAY_FREQ[hardness_of(path)])


static func is_foliage(path: String) -> bool:
	var h := hardness_of(path)
	return h == Hardness.TREE or h == Hardness.BUSH


static func opaque_bottom_px(tex: Texture2D) -> int:
	if tex == null:
		return 0
	var img := tex.get_image()
	if img == null:
		return maxi(tex.get_height() - 1, 0)
	if img.is_compressed():
		img.decompress()
	var h := img.get_height()
	var w := img.get_width()
	for y in range(h - 1, -1, -1):
		for x in w:
			if img.get_pixel(x, y).a > OPAQUE_ALPHA:
				return y
	return maxi(h - 1, 0)


static func sprite_opaque_bottom_y(spr: Sprite2D) -> float:
	if spr == null or spr.texture == null:
		return 0.0
	var bot := opaque_bottom_px(spr.texture)
	return spr.position.y + float(bot + 1) * spr.scale.y


static func find_sway(host: Node) -> WindSway:
	if host == null:
		return null
	for child in host.get_children():
		if child is WindSway:
			return child
	return null


## `shed_leaves`: play-layer trees drop the odd dead leaf (LeafShed sits beside
## the sway pivot so leaves fall straight while the crown leans).
static func plant(parent: Node2D, path: String, feet: Vector2, scale: float, tint: Color = Color.WHITE, shed_leaves: bool = false) -> Sprite2D:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	return plant_texture(parent, tex, path, feet, scale, tint, shed_leaves)


static func plant_texture(parent: Node2D, tex: Texture2D, path: String, feet: Vector2, scale: float, tint: Color = Color.WHITE, shed_leaves: bool = false) -> Sprite2D:
	if tex == null:
		return null
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(scale, scale)
	if tint != Color.WHITE:
		spr.modulate = tint
	var w := float(tex.get_width()) * scale
	var hardness := hardness_of(path)
	if hardness == Hardness.TREE or hardness == Hardness.BUSH:
		var h := float(tex.get_height()) * scale
		var pivot := Node2D.new()
		pivot.name = "Sway_%s" % path.get_file().get_basename()
		pivot.position = Vector2(feet.x + w * 0.5, feet.y)
		if in_world_space(parent):
			pivot.set_meta("feet", pivot.position)
			pivot.add_to_group("grounded")
		parent.add_child(pivot)
		spr.position = Vector2(-w * 0.5, -h)
		pivot.add_child(spr)
		var sway := WindSway.new()
		sway.amplitude = sway_amplitude(path)
		sway.freq = sway_freq(path)
		pivot.add_child(sway)
		if shed_leaves and hardness == Hardness.TREE:
			var shed := LeafShed.new()
			shed.name = "Leaves_%s" % path.get_file().get_basename()
			shed.position = pivot.position
			shed.canopy = Vector2(w, h)
			parent.add_child(shed)
		return spr
	var land := float(opaque_bottom_px(tex) + 1) * scale
	spr.position = Vector2(feet.x, feet.y - land)
	if in_world_space(parent):
		spr.set_meta("feet", Vector2(feet.x + w * 0.5, feet.y))
		spr.add_to_group("grounded")
	parent.add_child(spr)
	return spr


## Play-layer decor stands on platforms and is checked by LevelSanity; foliage
## planted into a Parallax2D / CanvasLayer silhouette strip lives in scroll
## space and is not.
static func in_world_space(node: Node) -> bool:
	var cursor := node
	while cursor != null:
		if cursor is Parallax2D or cursor is CanvasLayer:
			return false
		cursor = cursor.get_parent()
	return true
