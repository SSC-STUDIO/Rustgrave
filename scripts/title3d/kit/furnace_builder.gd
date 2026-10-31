class_name FurnaceBuilder
extends RefCounted
## Builds the right-bank forge: the riveted furnace body, its glowing mouth on
## the +Z face (facing the title camera), the chimney stack that punches through
## the roof, the flue pipes, and the small bellows rig. The lava river and the
## forge light are not built here (title-light owns both).

const LAYOUT := preload("res://scripts/title3d/kit/layout.gd")
const KIT := preload("res://scripts/title3d/kit/title_kit.gd")

const C_IRON := Color("#4f4a44")
const C_IRON_DARK := Color("#302b28")
const C_RUST := Color("#8a4a22")
const C_RUST_DARK := Color("#5a2f14")
const C_BRICK := Color("#6b4a3a")
const C_BRICK_DARK := Color("#473027")
const C_BONE := Color("#b9a88f")
const C_EMBER := Color("#ff8c2a")
const C_EMBER_HOT := Color("#ffd27a")
const C_SOOT := Color("#1e1917")

const OUTLINE_PX := 1.3

static var _mouth_material: ShaderMaterial


## Shared emissive material of the forge mouth. The lighting module may animate
## `flicker` / `emission_gain` on it (it is the only user of this instance).
static func mouth_material() -> ShaderMaterial:
	if _mouth_material == null:
		var base := KIT.mat(KIT.EMISSIVE)
		_mouth_material = base.duplicate() as ShaderMaterial
		_mouth_material.set_shader_parameter("flicker", 0.28)
		_mouth_material.set_shader_parameter("emission_gain", 2.0)
	return _mouth_material


static func build(host: Node3D) -> void:
	if host == null:
		return
	_build_body(host)
	_build_stack(host)
	_build_mouth(host)


static func _build_body(host: Node3D) -> void:
	var parts: Array = []
	var center := LAYOUT.FORGE_CENTER
	var size := LAYOUT.FORGE_SIZE
	var front_z := center.z + size.z * 0.5
	# Body and a stepped foot.
	parts.append(KIT.part_box(size, KIT.xform(center), C_IRON_DARK))
	parts.append(KIT.part_box(
			Vector3(size.x + 0.8, 0.55, size.z + 0.8),
			KIT.xform(Vector3(center.x, 0.275, center.z)), C_IRON))
	# Horizontal rivet bands around the chamber.
	for i in 3:
		parts.append(KIT.part_box(
				Vector3(size.x + 0.18, 0.24, size.z + 0.18),
				KIT.xform(Vector3(center.x, 1.3 + i * 2.2, center.z)), C_RUST))
	# Corner straps.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append(KIT.part_box(
					Vector3(0.35, size.y, 0.35),
					KIT.xform(Vector3(center.x + sx * (size.x * 0.5 - 0.15),
							0.0 + size.y * 0.5, center.z + sz * (size.z * 0.5 - 0.15))), C_RUST_DARK))
	# Mouth frame on the +Z face: heavy lintel, jambs, sill and a sooty hood.
	var mouth := LAYOUT.FORGE_MOUTH
	var mouth_half_w := LAYOUT.FORGE_MOUTH_SIZE.x * 0.5
	var mouth_half_h := LAYOUT.FORGE_MOUTH_SIZE.y * 0.5
	parts.append(KIT.part_box(
			Vector3(LAYOUT.FORGE_MOUTH_SIZE.x + 1.1, 0.5, 0.85),
			KIT.xform(Vector3(mouth.x, mouth.y + mouth_half_h + 0.25, front_z + 0.3)), C_IRON))
	parts.append(KIT.part_box(
			Vector3(LAYOUT.FORGE_MOUTH_SIZE.x + 1.4, 0.6, 1.0),
			KIT.xform(Vector3(mouth.x, mouth.y + mouth_half_h + 0.75, front_z + 0.35)), C_RUST_DARK))
	parts.append(KIT.part_box(
			Vector3(LAYOUT.FORGE_MOUTH_SIZE.x + 1.1, 0.45, 1.0),
			KIT.xform(Vector3(mouth.x, mouth.y - mouth_half_h - 0.22, front_z + 0.35)), C_IRON))
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(0.55, LAYOUT.FORGE_MOUTH_SIZE.y + 1.0, 0.85),
				KIT.xform(Vector3(mouth.x + (mouth_half_w + 0.27) * side, mouth.y, front_z + 0.3)),
				C_IRON))
		# Chain hooks flanking the mouth.
		parts.append(KIT.part_box(
				Vector3(0.2, 0.55, 0.2),
				KIT.xform(Vector3(mouth.x + (mouth_half_w + 1.0) * side, mouth.y + 0.9, front_z + 0.2)),
				C_RUST))
	# Soot fan above the mouth.
	parts.append(KIT.part_box(
			Vector3(LAYOUT.FORGE_MOUTH_SIZE.x + 2.4, 2.6, 0.12),
			KIT.xform(Vector3(mouth.x, mouth.y + mouth_half_h + 2.2, front_z + 0.05)), C_SOOT))
	# Grate bars in front of the glowing mouth (non-emissive, they silhouette).
	for i in 4:
		parts.append(KIT.part_box(
				Vector3(0.14, LAYOUT.FORGE_MOUTH_SIZE.y - 0.3, 0.22),
				KIT.xform(Vector3(mouth.x - 0.9 + i * 0.6, mouth.y - 0.1, front_z + 0.62)), C_IRON_DARK))
	# Flues and pipes around the body.
	parts.append(KIT.part_cyl(0.42, 3.2, 8,
			KIT.xform(Vector3(center.x - 2.0, size.y - 1.4, center.z + 1.2)), C_IRON))
	parts.append(KIT.part_cyl(0.5, 2.2, 8,
			KIT.xform(Vector3(center.x - 2.0, size.y - 0.1, center.z + 1.2), Vector3(90.0, 0.0, 0.0)),
			C_RUST))
	for i in 2:
		parts.append(KIT.part_cyl(0.2, 3.6, 6,
				KIT.xform(Vector3(center.x + size.x * 0.5 + 0.15, 4.6 + i * 0.7, center.z + 0.6),
						Vector3(90.0, 0.0, 0.0)), C_RUST if i == 0 else C_IRON))
	# Small bellows rig bolted to the left face of the furnace.
	parts.append(KIT.part_box(
			Vector3(1.9, 1.3, 1.5), KIT.xform(Vector3(center.x - size.x * 0.5 - 0.8, 1.4, center.z + 1.4)),
			C_RUST_DARK))
	parts.append(KIT.part_box(
			Vector3(2.6, 0.22, 0.22),
			KIT.xform(Vector3(center.x - size.x * 0.5 - 1.6, 2.2, center.z + 1.4), Vector3(0.0, 0.0, 18.0)),
			C_IRON))
	_add_group(host, "ForgeBody", parts, KIT.textured(KIT.luminance_texture("plate"), 11.0), OUTLINE_PX)


static func _build_stack(host: Node3D) -> void:
	var parts: Array = []
	var base := LAYOUT.FORGE_STACK_BASE
	var height := LAYOUT.FORGE_STACK_TOP_Y - base.y
	var radius := LAYOUT.FORGE_STACK_RADIUS
	parts.append(KIT.part_cyl(radius, height, 12, KIT.xform(Vector3(base.x, base.y + height * 0.5, base.z)),
			C_BRICK))
	# Flared skirt at the bottom and a crown at the top.
	parts.append(KIT.part_cyl(radius * 1.45, 1.4, 12,
			KIT.xform(Vector3(base.x, base.y + 0.7, base.z)), C_BRICK_DARK))
	parts.append(KIT.part_cyl(radius * 1.18, 0.9, 12,
			KIT.xform(Vector3(base.x, LAYOUT.FORGE_STACK_TOP_Y - 0.45, base.z)), C_IRON_DARK))
	parts.append(KIT.part_cyl(radius * 1.08, 0.25, 12,
			KIT.xform(Vector3(base.x, LAYOUT.FORGE_STACK_TOP_Y + 0.1, base.z)), C_EMBER, 1.0))
	# Iron hoops up the stack.
	for i in 4:
		var y := base.y + 1.8 + i * (height - 2.4) / 4.0
		parts.append(KIT.part_cyl(radius + 0.08, 0.28, 12, KIT.xform(Vector3(base.x, y, base.z)), C_IRON))
	# Soot streaks down the camera-facing side.
	for i in 2:
		parts.append(KIT.part_box(
				Vector3(0.5, height * 0.75, 0.16),
				KIT.xform(Vector3(base.x - 0.45 + i * 0.9, base.y + height * 0.45, base.z + radius - 0.02)),
				C_SOOT))
	_add_group(host, "ForgeStack", parts, KIT.textured(KIT.luminance_texture("brick"), 10.0), 1.1)


static func _build_mouth(host: Node3D) -> void:
	var parts: Array = []
	var mouth := LAYOUT.FORGE_MOUTH
	var front_z := LAYOUT.FORGE_CENTER.z + LAYOUT.FORGE_SIZE.z * 0.5
	# Recessed glowing panel plus a hotter inner heart and an ember bed.
	parts.append(KIT.part_box(
			Vector3(LAYOUT.FORGE_MOUTH_SIZE.x - 0.4, LAYOUT.FORGE_MOUTH_SIZE.y - 0.35, 0.14),
			KIT.xform(Vector3(mouth.x, mouth.y, front_z + 0.02)), C_EMBER, 1.0))
	parts.append(KIT.part_box(
			Vector3(LAYOUT.FORGE_MOUTH_SIZE.x - 1.6, LAYOUT.FORGE_MOUTH_SIZE.y - 1.25, 0.1),
			KIT.xform(Vector3(mouth.x, mouth.y + 0.16, front_z + 0.1)), C_EMBER_HOT, 1.0))
	parts.append(KIT.part_box(
			Vector3(LAYOUT.FORGE_MOUTH_SIZE.x - 0.8, 0.24, 0.5),
			KIT.xform(Vector3(mouth.x, mouth.y - LAYOUT.FORGE_MOUTH_SIZE.y * 0.5 + 0.2, front_z + 0.2)),
			C_RUST, 0.55))
	# Two ember specks spilling out of the mouth.
	for i in 3:
		parts.append(KIT.part_box(
				Vector3(0.16, 0.1, 0.1),
				KIT.xform(Vector3(mouth.x - 0.7 + i * 0.7, mouth.y - 0.9 - i * 0.16, front_z + 0.55)),
				C_EMBER_HOT, 1.0))
	var instance := _add_group(host, "ForgeMouth", parts, mouth_material(), 0.0)
	if instance != null:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _add_group(host: Node3D, group_name: String, parts: Array,
		material: Material, outline_px: float) -> MeshInstance3D:
	var mesh := KIT.merge(parts)
	if mesh.get_surface_count() == 0:
		return null
	var instance := KIT.mesh_instance(mesh, material, Transform3D.IDENTITY, group_name)
	host.add_child(instance)
	if outline_px > 0.0:
		KIT.outline(instance, outline_px)
	return instance
