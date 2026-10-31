extends RefCounted
## Shared hit feedback for the procedural arena units.
##
## A unit is built from several TOON_PART meshes that share cached materials
## between every unit on screen, so per-unit feedback cannot recolour a
## material. Instead this helper walks the unit once, keeps the mesh list, fades
## the whole group through GeometryInstance3D.transparency (death fade) and
## flashes it with an additive white `material_overlay` (hit flash). Neither
## touches the shared toon/outline materials, so the look of the rest of the
## arena is unchanged.

const FLASH_COLOR := Color(1.0, 0.9, 0.78, 0.5)

static var _flash: StandardMaterial3D
static var _tints: Dictionary = {}


## Every solid mesh below `root` (parts and their inverted-hull outlines), in
## tree order. Ground decals (blob shadows, light pools, lava) are skipped: they
## are additive/alpha planes, and flashing or fading one paints a bright quad
## over the floor instead of lighting up the unit.
static func collect_parts(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_into(root, out)
	return out


static func _collect_into(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and not _is_decal(child as MeshInstance3D):
			out.append(child as MeshInstance3D)
		_collect_into(child, out)


static func _is_decal(mesh: MeshInstance3D) -> bool:
	var material := mesh.material_override
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader != null:
			var path := shader.resource_path
			return path.ends_with("blob_shadow.gdshader") \
					or path.ends_with("light_pool.gdshader") \
					or path.ends_with("lava.gdshader")
	return false


## `fade` 1.0 keeps the unit opaque, 0.0 makes it fully transparent.
static func set_fade(parts: Array[MeshInstance3D], fade: float) -> void:
	var transparency := clampf(1.0 - fade, 0.0, 1.0)
	for part in parts:
		if is_instance_valid(part):
			part.transparency = transparency


static func flash_material() -> StandardMaterial3D:
	if _flash == null:
		_flash = StandardMaterial3D.new()
		_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash.albedo_color = FLASH_COLOR
		_flash.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _flash


static func set_flash(parts: Array[MeshInstance3D], on: bool) -> void:
	var material: Material = flash_material() if on else null
	for part in parts:
		if is_instance_valid(part):
			part.material_overlay = material


## A permanent additive team tint used to tell the enemy heroes apart from the
## player knight without touching the shared toon materials.
static func tint_material(color: Color, strength: float = 0.22) -> StandardMaterial3D:
	var key := "%s@%.2f" % [color.to_html(), strength]
	if _tints.has(key):
		return _tints[key]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, strength)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tints[key] = material
	return material


static func set_overlay(parts: Array[MeshInstance3D], material: Material) -> void:
	for part in parts:
		if is_instance_valid(part):
			part.material_overlay = material
