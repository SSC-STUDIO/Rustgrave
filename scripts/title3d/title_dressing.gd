extends RefCounted
## Extra set dressing that thickens the 3D title hall without touching the frozen
## kit builders: foreground framing masses, a far arcade behind the bridge, roof
## bracing, wall pipes/ducts, hanging chains and deck clutter.
##
## The point is composition, not simulation: the 2D reference had heavy machinery
## framing the hero on both sides and a layered hall behind him, and the bare
## generated hall reads too empty from the hero camera. Everything here is merged
## into a handful of MeshInstance3D so the draw-call budget stays flat.
##
## Coordinates are the TitleLayout contract written out so this file has no load
## order dependency: 1 unit = 1 m, +Y up, camera looks -Z, bridge deck y = 0 (top
## face), knight feet at (0,0,0), hall x +-16, z -30..+6, roof y 15, side decks
## x +-8.5..16 at y 0, lava at y -5.55.

const KIT_PATH := "res://scripts/title3d/kit/title_kit.gd"

const IRON_DARK := Color("#241C22")
const IRON := Color("#3C343C")
const IRON_LIGHT := Color("#6A5A5E")
const STONE_DARK := Color("#2A2420")
const STONE := Color("#4A3E36")
const RUST := Color("#6F3A22")
const EMBER_DIM := Color("#8A3A1C")


static func build(host: Node3D) -> void:
	if host == null:
		return
	var kit: GDScript = null
	if ResourceLoader.exists(KIT_PATH):
		kit = load(KIT_PATH) as GDScript
	if kit == null:
		return
	_foreground_frame(host, kit)
	_far_arcade(host, kit)
	_roof_bracing(host, kit)
	_wall_pipes(host, kit)
	_hanging_chains(host, kit)
	_deck_clutter(host, kit)


static func _mesh(kit: GDScript, parts: Array, host: Node3D, node_name: String) -> void:
	if parts.is_empty():
		return
	var merged: ArrayMesh = kit.merge(parts)
	var mi: MeshInstance3D = kit.mesh_instance(merged, kit.mat(0), Transform3D.IDENTITY, node_name)
	host.add_child(mi)


## Two thick machinery shoulders at the extreme left/right edges, closer to the
## camera than the bridge, so the frame closes like the 2D layout did.
static func _foreground_frame(host: Node3D, kit: GDScript) -> void:
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		var x := 15.0 * side
		parts.append(kit.part_box(Vector3(4.4, 9.0, 6.0),
				kit.xform(Vector3(x, 2.2, 6.4), Vector3(0, 9.0 * side, 0)),
				STONE_DARK))
		parts.append(kit.part_box(Vector3(2.6, 3.2, 4.2),
				kit.xform(Vector3(x - 2.2 * side, 5.6, 4.6), Vector3(0, 0, 4.0 * side)),
				IRON_DARK))
		# riveted plate band
		parts.append(kit.part_box(Vector3(3.6, 0.55, 5.2),
				kit.xform(Vector3(x, 6.6, 6.2), Vector3.ZERO), IRON))
		for i in 4:
			parts.append(kit.part_cyl(0.16, 0.5, 6,
					kit.xform(Vector3(x - 1.7 * side, 1.2 + 1.6 * float(i), 6.2)),
					RUST))
		# hanging chain stub under the shoulder
		for k in 6:
			parts.append(kit.part_box(Vector3(0.16, 0.5, 0.16),
					kit.xform(Vector3(x - 1.2 * side, -1.0 - 0.55 * float(k), 5.6)),
					IRON_LIGHT))
	_mesh(kit, parts, host, "DressForeground")


## A run of arches behind the bridge at z -20: gives the hall depth behind the
## hero without touching the far wall windows.
static func _far_arcade(host: Node3D, kit: GDScript) -> void:
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var x := float(i) * 5.6 * side + 1.6 * side
			parts.append(kit.part_box(Vector3(1.5, 7.4, 1.5),
					kit.xform(Vector3(x, 3.7, -20.5)), STONE_DARK))
			parts.append(kit.part_box(Vector3(1.4, 1.0, 1.4),
					kit.xform(Vector3(x, 7.6, -20.5)), STONE))
		# the arch band tying the pillars together
		parts.append(kit.part_box(Vector3(16.0, 1.1, 1.2),
				kit.xform(Vector3(9.0 * side, 8.2, -20.5)), STONE_DARK))
		# catwalk deck behind the arch
		parts.append(kit.part_box(Vector3(16.5, 0.4, 2.4),
				kit.xform(Vector3(9.0 * side, 5.6, -19.0)), IRON_DARK))
		for j in 5:
			parts.append(kit.part_box(Vector3(0.12, 1.1, 0.12),
					kit.xform(Vector3(2.0 + 3.4 * float(j), 6.35, -18.1)), IRON_LIGHT))
	_mesh(kit, parts, host, "DressFarArcade")


## Roof cross bracing: diagonal truss members under the roof deck.
static func _roof_bracing(host: Node3D, kit: GDScript) -> void:
	var parts: Array = []
	for i in 6:
		var z := 3.0 - 5.2 * float(i)
		var len := 30.0
		parts.append(kit.part_box(Vector3(len, 0.42, 0.42),
				kit.xform(Vector3(0.0, 13.2, z)), IRON_DARK))
		# diagonal pair each bay
	var bays := 6
	for i in bays:
		var z := 2.0 - 5.0 * float(i)
		for side: float in [-1.0, 1.0]:
			var beam: Dictionary = kit.part_box(Vector3(0.34, 0.34, 8.4),
					kit.xform(Vector3(8.0 * side, 13.9, z), Vector3(24.0 * side, 0, 0)),
					IRON)
			parts.append(beam)
	_mesh(kit, parts, host, "DressRoofBrace")


## Wall pipes and ducts running up both side walls.
static func _wall_pipes(host: Node3D, kit: GDScript) -> void:
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		for i in 5:
			var z := 2.0 - 5.5 * float(i)
			parts.append(kit.part_cyl(0.26, 9.6, 6,
					kit.xform(Vector3(15.1 * side, 5.2, z)), IRON))
			parts.append(kit.part_box(Vector3(1.1, 0.32, 0.32),
					kit.xform(Vector3(15.3 * side, 9.6, z)), RUST))
		# horizontal duct at mid height
		parts.append(kit.part_cyl(0.34, 22.0, 6,
				kit.xform(Vector3(14.4 * side, 7.4, -9.0), Vector3(0, 0, 90.0)), IRON_DARK))
		# brackets
		for k in 4:
			parts.append(kit.part_box(Vector3(0.5, 0.5, 0.5),
					kit.xform(Vector3(15.4 * side, 7.4, 1.0 - 5.0 * float(k))), IRON_LIGHT))
	_mesh(kit, parts, host, "DressWallPipes")


## Old hanging chains between roof and mid-air, behind the hero plane.
static func _hanging_chains(host: Node3D, kit: GDScript) -> void:
	var parts: Array = []
	var xs := [-11.5, -6.0, 5.4, 10.8, 12.6]
	var zs := [-6.0, -12.5, -3.5, -9.0, -15.0]
	for i in xs.size():
		var x: float = xs[i]
		var z: float = zs[i]
		var length := 5.0 + 1.5 * float(i % 3)
		var links := int(length / 0.46)
		for k in links:
			var y := 14.4 - 0.46 * float(k)
			if k % 2 == 0:
				parts.append(kit.part_box(Vector3(0.16, 0.4, 0.07),
						kit.xform(Vector3(x, y, z)), IRON_LIGHT))
			else:
				parts.append(kit.part_box(Vector3(0.07, 0.4, 0.16),
						kit.xform(Vector3(x, y, z)), IRON))
		# weight at the end
		parts.append(kit.part_box(Vector3(0.34, 0.32, 0.3),
				kit.xform(Vector3(x, 14.4 - length - 0.3, z)), RUST))
	_mesh(kit, parts, host, "DressHangingChains")


## Deck clutter on the two side banks (crates, anvils, barrels, rails).
static func _deck_clutter(host: Node3D, kit: GDScript) -> void:
	var parts: Array = []
	var spots := [
		[-12.6, 0.35, -2.0], [-11.4, 0.35, 1.6], [-13.8, 0.35, -6.4],
		[12.9, 0.35, -2.4], [11.6, 0.35, 1.2], [13.6, 0.35, -7.0],
	]
	for i in spots.size():
		var s: Array = spots[i]
		var x: float = s[0]
		var y: float = s[1]
		var z: float = s[2]
		var size := 0.9 + 0.25 * float(i % 3)
		parts.append(kit.part_box(Vector3(size, size, size),
				kit.xform(Vector3(x, y, z), Vector3(0, 12.0 * float(i), 0)), RUST))
		parts.append(kit.part_box(Vector3(size + 0.1, 0.12, size + 0.1),
				kit.xform(Vector3(x, y + size * 0.5, z)), IRON_DARK))
	# anvils
	for side: float in [-1.0, 1.0]:
		parts.append(kit.part_box(Vector3(0.8, 1.1, 0.5),
				kit.xform(Vector3(10.4 * side, 0.55, -5.2)), IRON_DARK))
		parts.append(kit.part_box(Vector3(1.5, 0.28, 0.62),
				kit.xform(Vector3(10.4 * side, 1.22, -5.2)), IRON))
		# barrels
		for i in 2:
			parts.append(kit.part_cyl(0.48, 1.1, 8,
					kit.xform(Vector3(9.9 * side + 1.6 * float(i) * side, 0.55, 2.6)),
					IRON_DARK))
	_mesh(kit, parts, host, "DressDeckClutter")
