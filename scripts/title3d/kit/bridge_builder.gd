class_name BridgeBuilder
extends RefCounted
## Builds the iron bridge that carries the knight over the lava chasm: planked
## deck, edge girders, railings on both sides, the under-deck chain drops and the
## stone abutments that meet the side machine decks.
##
## One merged mesh per group, all baked in world space under `host`. The lava
## river itself is title-light's surface, never this file.

const LAYOUT := preload("res://scripts/title3d/kit/layout.gd")
const KIT := preload("res://scripts/title3d/kit/title_kit.gd")
const SHAPES := preload("res://scripts/title3d/kit/shapes.gd")

const C_IRON := Color("#4f4a44")
const C_IRON_DARK := Color("#332e2a")
const C_RUST := Color("#8a4a22")
const C_RUST_DARK := Color("#5a2f14")
const C_STONE := Color("#6a5f55")
const C_STONE_DARK := Color("#443d37")
const C_BONE := Color("#b9a88f")

const OUTLINE_PX := 1.2


static func build(host: Node3D) -> void:
	if host == null:
		return
	_build_deck(host)
	_build_rails(host)
	_build_supports(host)


static func _build_deck(host: Node3D) -> void:
	var parts: Array = []
	var half_x := LAYOUT.BRIDGE_HALF_X
	var half_z := LAYOUT.BRIDGE_SIZE.z * 0.5
	# Support slab (slightly below the walking surface).
	parts.append(KIT.part_box(
			Vector3(LAYOUT.BRIDGE_SIZE.x, 0.62, LAYOUT.BRIDGE_SIZE.z - 0.06),
			KIT.xform(Vector3(0.0, -0.37, 0.0)), C_IRON_DARK))
	# Walking planks with dark seams between them; the top face stays exactly at
	# DECK_Y so props and the knight stand on it without clipping.
	var plank_count := 12
	var gap := 0.04
	var plank_depth := (half_z * 2.0 - gap * float(plank_count - 1)) / float(plank_count)
	var z := -half_z + gap * 0.5
	for i in plank_count:
		var color := C_IRON if i % 3 != 1 else C_RUST_DARK
		parts.append(KIT.part_box(
				Vector3(LAYOUT.BRIDGE_SIZE.x, 0.56, plank_depth),
				KIT.xform(Vector3(0.0, -0.28, z + plank_depth * 0.5)), color))
		z += plank_depth + gap
	# Edge girders and the riveted side plates.
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(LAYOUT.BRIDGE_SIZE.x, 0.55, 0.4),
				KIT.xform(Vector3(0.0, -0.42, (half_z - 0.2) * side)), C_IRON))
		var x := -half_x + 0.6
		while x < half_x:
			parts.append(KIT.part_box(
					Vector3(0.22, 0.22, 0.18),
					KIT.xform(Vector3(x, -0.2, (half_z - 0.02) * side)), C_BONE))
			x += 1.1
	# Under-deck cross girders, one per chain drop.
	for x in LAYOUT.BRIDGE_CHAIN_XS:
		parts.append(KIT.part_box(
				Vector3(0.4, 0.45, LAYOUT.BRIDGE_SIZE.z),
				KIT.xform(Vector3(x, -0.86, 0.0)), C_IRON_DARK))
	# Diagonal braces between the cross girders (dark X pattern in the shadow).
	for i in range(LAYOUT.BRIDGE_CHAIN_XS.size() - 1):
		var x0: float = LAYOUT.BRIDGE_CHAIN_XS[i]
		var x1: float = LAYOUT.BRIDGE_CHAIN_XS[i + 1]
		for side in [-1.0, 1.0]:
			var center := Vector3((x0 + x1) * 0.5, -0.95, (half_z - 0.5) * side)
			var length := Vector2(x1 - x0, 0.4).length()
			var angle := atan2(0.4, x1 - x0)
			parts.append(KIT.part_box(
					Vector3(length, 0.16, 0.16),
					Transform3D(Basis(Vector3(0.0, 0.0, 1.0), angle if side > 0.0 else -angle), center),
					C_RUST_DARK))
	# Stone abutments where the deck meets the two machine decks.
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(1.3, 1.4, LAYOUT.BRIDGE_SIZE.z + 0.3),
				KIT.xform(Vector3((half_x + 0.45) * side, -0.9, 0.0)), C_STONE))
		parts.append(KIT.part_box(
				Vector3(1.6, 0.22, LAYOUT.BRIDGE_SIZE.z + 0.5),
				KIT.xform(Vector3((half_x + 0.45) * side, -0.18, 0.0)), C_STONE_DARK))
	_add_group(host, "BridgeDeck", parts, _plate_material(), OUTLINE_PX)


static func _build_rails(host: Node3D) -> void:
	var parts: Array = []
	var half_x := LAYOUT.BRIDGE_HALF_X
	var rail_z := LAYOUT.BRIDGE_SIZE.z * 0.5 - 0.22
	var post_spacing := 1.7
	for side in [-1.0, 1.0]:
		var z: float = rail_z * side
		var x := -half_x
		while x <= half_x + 0.01:
			parts.append(KIT.part_box(
					Vector3(0.15, LAYOUT.RAIL_HEIGHT, 0.15),
					KIT.xform(Vector3(x, LAYOUT.RAIL_HEIGHT * 0.5, z)), C_IRON))
			parts.append(KIT.part_box(
					Vector3(0.3, 0.1, 0.3), KIT.xform(Vector3(x, 0.1, z)), C_RUST_DARK))
			x += post_spacing
		# Top, mid and kick rails.
		parts.append(KIT.part_box(
				Vector3(LAYOUT.BRIDGE_SIZE.x, 0.14, 0.18),
				KIT.xform(Vector3(0.0, LAYOUT.RAIL_HEIGHT, z)), C_IRON))
		parts.append(KIT.part_box(
				Vector3(LAYOUT.BRIDGE_SIZE.x, 0.09, 0.12),
				KIT.xform(Vector3(0.0, LAYOUT.RAIL_HEIGHT * 0.56, z)), C_RUST))
		parts.append(KIT.part_box(
				Vector3(LAYOUT.BRIDGE_SIZE.x, 0.12, 0.14),
				KIT.xform(Vector3(0.0, 0.16, z)), C_IRON_DARK))
		# Rusted chain swags between the end posts (short decorative links).
		for i in 4:
			var cx := -half_x + 2.2 + i * 3.4
			parts.append(KIT.part_mesh(SHAPES.chain_link(0.42, 0.26, C_RUST_DARK),
					KIT.xform(Vector3(cx, LAYOUT.RAIL_HEIGHT - 0.42 - (i % 2) * 0.16, z),
							Vector3(0.0, 90.0 if i % 2 == 0 else 0.0, 0.0))))
	_add_group(host, "BridgeRails", parts, _plate_material(), OUTLINE_PX)


static func _build_supports(host: Node3D) -> void:
	var parts: Array = []
	var link_length := 0.5
	var link_width := 0.3
	var link_step := 0.42
	for x in LAYOUT.BRIDGE_CHAIN_XS:
		# Anchor block bolted under the deck.
		parts.append(KIT.part_box(
				Vector3(0.7, 0.45, 0.7), KIT.xform(Vector3(x, -1.15, 0.0)), C_IRON_DARK))
		parts.append(KIT.part_box(
				Vector3(0.9, 0.16, 0.9), KIT.xform(Vector3(x, -0.98, 0.0)), C_RUST))
		for i in 10:
			var y := -1.55 - float(i) * link_step
			parts.append(KIT.part_mesh(
					SHAPES.chain_link(link_length, link_width, C_IRON_DARK),
					KIT.xform(Vector3(x, y, 0.0), Vector3(0.0, 90.0 if i % 2 == 0 else 0.0, 0.0))))
		# Counterweight at the bottom of the drop, just above the lava.
		parts.append(KIT.part_box(
				Vector3(0.55, 0.4, 0.55), KIT.xform(Vector3(x, -5.05, 0.0)), C_RUST_DARK))
	# Hanging lantern cross-beams under the deck edges (unlit iron bars).
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(0.25, 0.25, LAYOUT.BRIDGE_SIZE.z - 0.4),
				KIT.xform(Vector3(side * (LAYOUT.BRIDGE_HALF_X - 0.4), -0.7, 0.0)), C_IRON))
	_add_group(host, "BridgeSupports", parts, KIT.mat(0), 0.0)


static func _plate_material() -> ShaderMaterial:
	return KIT.textured(KIT.luminance_texture("plate"), 14.0)


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
