extends RefCounted
## Blender-authored hero set for the 3D title (assets/title3d/forge_hall.glb).
##
## The kit builders generated a clean but sparse hall; the 2D reference frame is a
## dense industrial set. This module loads the Blender model and swaps every mesh
## onto the kit's vertex-colour surface shader, so the geometry keeps the pixel
## title's palette/lighting rules while the shape/detail comes from Blender.
##
## The GLB is modelled in Godot world coordinates (bridge deck y=0, knight feet at
## the origin, hall x +-16), so the returned root is added at the identity.
##
## Rebuild the GLB with tools/blender/build_forge_hall.py.

const KIT_PATH := "res://scripts/title3d/kit/title_kit.gd"
const GLB_PATH := "res://assets/title3d/forge_hall.glb"


## Returns true when the Blender set was added; the caller then skips the kit
## builders (they would z-fight with the modelled hall).
static func build(host: Node3D) -> bool:
	if host == null or not ResourceLoader.exists(GLB_PATH):
		return false
	var packed := load(GLB_PATH) as PackedScene
	if packed == null:
		return false
	var kit: GDScript = null
	if ResourceLoader.exists(KIT_PATH):
		kit = load(KIT_PATH) as GDScript
	var root := packed.instantiate()
	if root == null:
		return false
	root.name = "BlenderHall"
	var material: Material = null
	if kit != null and kit.has_method("mat"):
		material = kit.call("mat", 0)
	var mesh_count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		if material != null:
			mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_count += 1
	host.add_child(root)
	push_warning("title: Blender hero set loaded (%d meshes)" % mesh_count)
	return mesh_count > 0


## Glow/haze fixtures inside the GLB are plain emissive vertices; the lighting rig
## owns the real lights. Nothing else to do for now, kept as a seam for tuning.
static func apply(host: Node3D, grade: Dictionary) -> void:
	pass
