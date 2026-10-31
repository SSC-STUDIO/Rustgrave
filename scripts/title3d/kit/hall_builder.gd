class_name HallBuilder
extends RefCounted
## Builds the forge-hall shell of the 3D title: far wall with three tall
## windows, the side arcades, the side machine decks with pipes and the overhead
## crane rails, the roof trusses with the ragged skylight, and the far catwalk.
##
## Everything is merged into a handful of vertex-coloured meshes (one draw call
## per group) and hung under `host`, which is owned by the title world. Geometry
## is baked in world space, so every instance sits at the identity transform.
## The lava river and the light shafts are NOT built here (title-light owns
## them); the window openings are real holes so its volumetric shafts leak
## through.

const LAYOUT := preload("res://scripts/title3d/kit/layout.gd")
const KIT := preload("res://scripts/title3d/kit/title_kit.gd")
const SHAPES := preload("res://scripts/title3d/kit/shapes.gd")

const C_IRON := Color("#4a4642")
const C_IRON_DARK := Color("#332f2c")
const C_STONE := Color("#6e6258")
const C_STONE_DARK := Color("#463f39")
const C_RUST := Color("#8a4a22")
const C_RUST_DARK := Color("#5a2f14")
const C_BONE := Color("#b9a88f")
## Cold steel-blue window glass. Authored blue-dominant on purpose: a light
## desaturated blue reads as "paper white" once ACES tonemapping + Glow blow it
## out, while this ramp keeps a blue HDR peak (blue only) and a dark blue base.
const C_GLASS := Color(0.42, 0.58, 0.80)
## Deep blue glass behind the leaded grid and in the sooty bottom panes.
const C_GLASS_DEEP := Color(0.16, 0.26, 0.46)
## Cold moonlit highlight, only on the top panes and the middle lead column.
const C_GLASS_HOT := Color(0.62, 0.78, 0.98)

const OUTLINE_PX := 1.4

static var _window_material: ShaderMaterial


static func build(host: Node3D) -> void:
	if host == null:
		return
	_build_shell(host)
	_build_arcade(host)
	_build_windows(host)
	_build_machines(host)
	_build_roof(host)
	_build_catwalk(host)


# ---------------------------------------------------------------------------
# Shell: far wall (with window holes), side walls, machine decks, chasm walls
# ---------------------------------------------------------------------------

static func _build_shell(host: Node3D) -> void:
	var parts: Array = []
	var wall_z := LAYOUT.HALL_BACK_Z - LAYOUT.WALL_THICKNESS * 0.5
	var bottom := LAYOUT.PIT_Y
	var top := LAYOUT.ROOF_Y
	var window_bottom := LAYOUT.WINDOW_Y - LAYOUT.WINDOW_SIZE.y * 0.5
	var window_top := LAYOUT.WINDOW_Y + LAYOUT.WINDOW_SIZE.y * 0.5
	# Far wall: slabs below/above and between the three window holes.
	parts.append(KIT.part_box(
			Vector3(LAYOUT.HALL_W, window_bottom - bottom, LAYOUT.WALL_THICKNESS),
			KIT.xform(Vector3(0.0, (window_bottom + bottom) * 0.5, wall_z)), C_STONE_DARK))
	parts.append(KIT.part_box(
			Vector3(LAYOUT.HALL_W, top - window_top, LAYOUT.WALL_THICKNESS),
			KIT.xform(Vector3(0.0, (window_top + top) * 0.5, wall_z)), C_STONE))
	var edges := [-16.0, -9.5, -6.5, -1.5, 1.5, 6.5, 9.5, 16.0]
	for i in 4:
		parts.append(KIT.part_box(
				Vector3(edges[i * 2 + 1] - edges[i * 2], window_top - window_bottom, LAYOUT.WALL_THICKNESS),
				KIT.xform(Vector3((edges[i * 2] + edges[i * 2 + 1]) * 0.5, LAYOUT.WINDOW_Y, wall_z)),
				C_STONE))
	# Window frames and the shadow-casting mullion cross (breeds a cross-shaped
	# god ray through each hole).
	for wx in LAYOUT.WINDOW_XS:
		parts.append(KIT.part_box(
				Vector3(LAYOUT.WINDOW_SIZE.x + 0.5, 0.32, 0.7),
				KIT.xform(Vector3(wx, window_top, LAYOUT.WINDOW_Z + 0.3)), C_IRON_DARK))
		parts.append(KIT.part_box(
				Vector3(LAYOUT.WINDOW_SIZE.x + 0.7, 0.4, 0.9),
				KIT.xform(Vector3(wx, window_bottom, LAYOUT.WINDOW_Z + 0.3)), C_IRON))
		for side in [-1.0, 1.0]:
			parts.append(KIT.part_box(
					Vector3(0.32, LAYOUT.WINDOW_SIZE.y + 0.6, 0.7),
					KIT.xform(Vector3(wx + (LAYOUT.WINDOW_SIZE.x * 0.5 + 0.25) * side,
							LAYOUT.WINDOW_Y, LAYOUT.WINDOW_Z + 0.3)), C_IRON_DARK))
		parts.append(KIT.part_box(
				Vector3(0.14, LAYOUT.WINDOW_SIZE.y, 0.2),
				KIT.xform(Vector3(wx, LAYOUT.WINDOW_Y, LAYOUT.WINDOW_Z + 0.05)), C_IRON))
		parts.append(KIT.part_box(
				Vector3(LAYOUT.WINDOW_SIZE.x, 0.14, 0.2),
				KIT.xform(Vector3(wx, LAYOUT.WINDOW_Y, LAYOUT.WINDOW_Z + 0.05)), C_IRON))
		# Leaded grid over the glass: two vertical + three horizontal iron bars
		# (they also carve the cold window light into a believable cross-hatch).
		var bar_z := LAYOUT.WINDOW_Z + 0.12
		for bar in [-1.0, 1.0]:
			parts.append(KIT.part_box(
					Vector3(0.15, LAYOUT.WINDOW_SIZE.y + 0.2, 0.45),
					KIT.xform(Vector3(wx + bar * LAYOUT.WINDOW_SIZE.x / 6.0,
							LAYOUT.WINDOW_Y, bar_z)), C_IRON))
		for bar in 3:
			var bar_y := window_bottom + (window_top - window_bottom) * float(bar + 1) / 4.0
			parts.append(KIT.part_box(
					Vector3(LAYOUT.WINDOW_SIZE.x + 0.2, 0.15, 0.45),
					KIT.xform(Vector3(wx, bar_y, bar_z)), C_IRON))
		# A bone-coloured sill and a sooty shadow band under every window.
		parts.append(KIT.part_box(
				Vector3(LAYOUT.WINDOW_SIZE.x + 1.0, 0.18, 0.5),
				KIT.xform(Vector3(wx, window_bottom - 0.55, LAYOUT.WINDOW_Z + 0.35)), C_BONE))
		parts.append(KIT.part_box(
				Vector3(LAYOUT.WINDOW_SIZE.x + 1.6, 1.1, 0.12),
				KIT.xform(Vector3(wx, window_bottom - 1.3, LAYOUT.WINDOW_Z + 0.5)), C_STONE_DARK))
	# Far-wall pilasters between the windows.
	for px in [-12.5, -4.0, 4.0, 12.5]:
		parts.append(KIT.part_box(
				Vector3(1.0, top - bottom, 0.7),
				KIT.xform(Vector3(px, (top + bottom) * 0.5, LAYOUT.HALL_BACK_Z + 0.3)), C_STONE))
	# Side walls and the raised machine decks that form the chasm banks.
	var side_center_z := (LAYOUT.HALL_FRONT_Z + LAYOUT.HALL_BACK_Z) * 0.5
	var side_depth := LAYOUT.HALL_FRONT_Z - LAYOUT.HALL_BACK_Z
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(LAYOUT.WALL_THICKNESS, top - bottom, side_depth),
				KIT.xform(Vector3((LAYOUT.HALL_HALF_W + LAYOUT.WALL_THICKNESS * 0.5) * side,
						(top + bottom) * 0.5, side_center_z)), C_STONE_DARK))
		var deck_width := LAYOUT.SIDE_DECK_OUTER_X - LAYOUT.SIDE_DECK_INNER_X
		var deck_center_x: float = (LAYOUT.SIDE_DECK_OUTER_X + LAYOUT.SIDE_DECK_INNER_X) * 0.5 * side
		parts.append(KIT.part_box(
				Vector3(deck_width, 0.8, side_depth),
				KIT.xform(Vector3(deck_center_x, LAYOUT.SIDE_DECK_Y - 0.4, side_center_z)), C_STONE))
		# Deck edge trim and the pit retaining wall below it.
		parts.append(KIT.part_box(
				Vector3(0.45, 1.1, side_depth),
				KIT.xform(Vector3((LAYOUT.SIDE_DECK_INNER_X - 0.2) * side, -0.55, side_center_z)), C_IRON_DARK))
		parts.append(KIT.part_box(
				Vector3(0.4, absf(LAYOUT.PIT_Y), side_depth),
				KIT.xform(Vector3((LAYOUT.SIDE_DECK_INNER_X + 0.2) * side,
						LAYOUT.PIT_Y * 0.5, side_center_z)), C_STONE_DARK))
		# Rubble / rivet line along the deck edge (deterministic, every 2 m).
		var z := LAYOUT.HALL_FRONT_Z - 1.0
		while z > LAYOUT.HALL_BACK_Z + 1.0:
			parts.append(KIT.part_box(
					Vector3(0.5, 0.28, 0.5),
					KIT.xform(Vector3((LAYOUT.SIDE_DECK_INNER_X + 0.55) * side, 0.14, z)),
					C_RUST if fmod(z, 4.0) < 2.0 else C_IRON))
			z -= 2.0
	# Chasm: floor, near/far retaining walls and the far stone apron.
	parts.append(KIT.part_box(
			Vector3(LAYOUT.PIT_HALF_X * 2.0, 0.4, LAYOUT.LAVA_Z_FRONT - LAYOUT.LAVA_Z_BACK),
			KIT.xform(Vector3(0.0, LAYOUT.PIT_Y - 0.2, (LAYOUT.LAVA_Z_FRONT + LAYOUT.LAVA_Z_BACK) * 0.5)),
			C_RUST_DARK))
	for z in [LAYOUT.LAVA_Z_FRONT, LAYOUT.LAVA_Z_BACK]:
		parts.append(KIT.part_box(
				Vector3(LAYOUT.PIT_HALF_X * 2.0, absf(LAYOUT.PIT_Y), 0.5),
				KIT.xform(Vector3(0.0, LAYOUT.PIT_Y * 0.5, z)), C_STONE_DARK))
	parts.append(KIT.part_box(
			Vector3(LAYOUT.HALL_W, LAYOUT.FAR_FLOOR_Y - LAYOUT.PIT_Y,
					LAYOUT.LAVA_Z_BACK - LAYOUT.HALL_BACK_Z),
			KIT.xform(Vector3(0.0, (LAYOUT.FAR_FLOOR_Y + LAYOUT.PIT_Y) * 0.5,
					(LAYOUT.LAVA_Z_BACK + LAYOUT.HALL_BACK_Z) * 0.5)), C_STONE))
	parts.append(KIT.part_box(
			Vector3(LAYOUT.HALL_W, absf(LAYOUT.FAR_FLOOR_Y - LAYOUT.PIT_Y), 0.6),
			KIT.xform(Vector3(0.0, (LAYOUT.FAR_FLOOR_Y + LAYOUT.PIT_Y) * 0.5,
					LAYOUT.LAVA_Z_BACK + 0.3)), C_STONE_DARK))
	# Low soot band at the base of every wall; keeps the horizon dark.
	parts.append(KIT.part_box(
			Vector3(LAYOUT.HALL_W, 1.2, 0.2),
			KIT.xform(Vector3(0.0, LAYOUT.FAR_FLOOR_Y + 0.6, LAYOUT.HALL_BACK_Z + 0.1)), C_IRON_DARK))
	_add_group(host, "HallShell", parts, _stone_material(), OUTLINE_PX)


# ---------------------------------------------------------------------------
# Side arcades (columns + round arches)
# ---------------------------------------------------------------------------

static func _build_arcade(host: Node3D) -> void:
	var parts: Array = []
	var column_top := 5.4
	var arch_span := LAYOUT.PILLAR_SPACING - 0.7
	for side in [-1.0, 1.0]:
		var x: float = (LAYOUT.HALL_HALF_W - 1.6) * side
		for i in LAYOUT.PILLAR_COUNT:
			var z := LAYOUT.PILLAR_Z_START - i * LAYOUT.PILLAR_SPACING
			# Column shaft, base and capital.
			parts.append(KIT.part_box(
					Vector3(0.9, 0.35, 0.9), KIT.xform(Vector3(x, 0.175, z)), C_STONE_DARK))
			parts.append(KIT.part_box(
					Vector3(0.7, column_top, 0.7), KIT.xform(Vector3(x, column_top * 0.5, z)), C_STONE))
			parts.append(KIT.part_box(
					Vector3(1.0, 0.4, 1.0), KIT.xform(Vector3(x, column_top, z)), C_IRON_DARK))
			# A rust band around the shaft.
			parts.append(KIT.part_box(
					Vector3(0.74, 0.22, 0.74), KIT.xform(Vector3(x, column_top * 0.62, z)), C_RUST))
			if i < LAYOUT.PILLAR_COUNT - 1:
				var span_z := z - LAYOUT.PILLAR_SPACING * 0.5
				var arch_mesh := SHAPES.arch(arch_span, 5.2, 0.6, 10, C_STONE_DARK)
				parts.append(KIT.part_mesh(arch_mesh,
						KIT.xform(Vector3(x, 0.0, span_z), Vector3(0.0, 90.0, 0.0))))
	# Continuous cornice above the arcade on both sides.
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(0.9, 0.5, LAYOUT.HALL_FRONT_Z - LAYOUT.HALL_BACK_Z - 1.0),
				KIT.xform(Vector3((LAYOUT.HALL_HALF_W - 1.6) * side, 5.7,
						(LAYOUT.HALL_FRONT_Z + LAYOUT.HALL_BACK_Z) * 0.5)), C_IRON_DARK))
	_add_group(host, "HallArcade", parts, _stone_material(), OUTLINE_PX)


# ---------------------------------------------------------------------------
# Tall windows: cold blue leaded glass behind the holes (no shadow casting, so
# the sun/volumetric shafts still pass through)
# ---------------------------------------------------------------------------

## Shared emissive material of the far-wall windows. A duplicated kit material
## with a controlled gain: bright enough that the blue channel only goes HDR
## (so Glow picks up blue, not a white seam), dim enough that ACES keeps the
## panes steel blue instead of desaturating them to warm white.
static func window_material() -> ShaderMaterial:
	if _window_material == null:
		var base := KIT.mat(KIT.EMISSIVE)
		_window_material = base.duplicate() as ShaderMaterial
		_window_material.set_shader_parameter("emission_gain", 2.1)
		_window_material.set_shader_parameter("flicker", 0.0)
	return _window_material


## Pane colour ramp from the cold moonlit top row down to the sooty bottom row.
static func _pane_color(row: int, rows: int) -> Color:
	if rows <= 1:
		return C_GLASS
	var t := float(row) / float(rows - 1)
	var color := C_GLASS_HOT.lerp(C_GLASS, clampf(t * 2.4, 0.0, 1.0))
	return color.lerp(C_GLASS_DEEP, clampf((t - 0.45) / 0.55, 0.0, 1.0))


static func _build_windows(host: Node3D) -> void:
	var parts: Array = []
	var glass_w := LAYOUT.WINDOW_SIZE.x - 0.5
	var glass_h := LAYOUT.WINDOW_SIZE.y - 0.5
	var cols := 3
	var rows := 4
	var gap := 0.11
	var pane_w := (glass_w - gap * float(cols - 1)) / float(cols)
	var pane_h := (glass_h - gap * float(rows - 1)) / float(rows)
	var backing_z := LAYOUT.HALL_BACK_Z - 0.30
	var pane_z := LAYOUT.HALL_BACK_Z - 0.18
	var left_x := -glass_w * 0.5 + pane_w * 0.5
	var top_y := glass_h * 0.5 - pane_h * 0.5
	for i in LAYOUT.WINDOW_XS.size():
		var wx: float = LAYOUT.WINDOW_XS[i]
		# Deep blue backing so the leaded gaps never read as black holes.
		parts.append(KIT.part_box(
				Vector3(glass_w + 0.24, glass_h + 0.24, 0.08),
				KIT.xform(Vector3(wx, LAYOUT.WINDOW_Y, backing_z)), C_GLASS_DEEP, 0.72))
		# 3x4 leaded panes: cold at the top, sooty at the bottom, the middle
		# column catching a moon streak.
		for row in rows:
			var row_color := _pane_color(row, rows)
			var row_emissive := lerpf(1.0, 0.80, float(row) / float(rows - 1))
			for col in cols:
				var color: Color = row_color
				if col == 1:
					color = color.lerp(C_GLASS_HOT, 0.28)
				parts.append(KIT.part_box(
						Vector3(pane_w, pane_h, 0.12),
						KIT.xform(Vector3(wx + left_x + float(col) * (pane_w + gap),
								LAYOUT.WINDOW_Y + top_y - float(row) * (pane_h + gap), pane_z)),
						color, row_emissive))
	var mi := _add_group(host, "HallWindows", parts, window_material(), 0.0)
	if mi != null:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------
# Side machines: gear housing, pipes, overhead crane rails
# ---------------------------------------------------------------------------

static func _build_machines(host: Node3D) -> void:
	var parts: Array = []
	# Left gear housing behind the big/small gear pair.
	parts.append(KIT.part_box(
			Vector3(5.6, 8.0, 5.6), KIT.xform(Vector3(-13.0, 4.0, -6.4)), C_IRON_DARK))
	parts.append(KIT.part_box(
			Vector3(4.8, 1.0, 5.0), KIT.xform(Vector3(-13.0, 8.5, -6.4)), C_IRON))
	parts.append(KIT.part_box(
			Vector3(0.8, 8.2, 0.8), KIT.xform(Vector3(-10.5, 4.1, -8.9)), C_RUST_DARK))
	for i in 3:
		parts.append(KIT.part_box(
				Vector3(5.0, 0.22, 0.22),
				KIT.xform(Vector3(-13.0, 1.6 + i * 2.1, -3.55)), C_RUST))
	# Right machine wall behind the forge: flues and a back-pressure tank.
	parts.append(KIT.part_box(
			Vector3(0.8, 9.0, 8.0), KIT.xform(Vector3(15.0, 4.5, -17.0)), C_IRON_DARK))
	parts.append(KIT.part_cyl(1.5, 4.0, 10,
			KIT.xform(Vector3(13.6, 2.0, -20.0), Vector3(0.0, 0.0, 90.0)), C_IRON))
	# Long wall pipes on both sides (cylinders run along Z).
	for side in [-1.0, 1.0]:
		for i in 3:
			parts.append(KIT.part_cyl(0.24, 21.0, 8,
					KIT.xform(Vector3(15.1 * side, 7.0 + i * 0.85, -8.0), Vector3(90.0, 0.0, 0.0)),
					C_RUST if i == 1 else C_IRON))
		# Pipe clamps every 4 m.
		var cz := 2.0
		while cz > -19.0:
			parts.append(KIT.part_box(
					Vector3(0.5, 3.4, 0.35),
					KIT.xform(Vector3(15.05 * side, 7.85, cz)), C_IRON_DARK))
			cz -= 4.0
	# Overhead crane rails plus one travelling hoist in the middle.
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(0.35, 0.4, LAYOUT.CRANE_Z_FROM - LAYOUT.CRANE_Z_TO),
				KIT.xform(Vector3(LAYOUT.CRANE_HALF_X * side, LAYOUT.CRANE_Y,
						(LAYOUT.CRANE_Z_FROM + LAYOUT.CRANE_Z_TO) * 0.5)), C_IRON))
		parts.append(KIT.part_box(
				Vector3(0.25, 0.25, LAYOUT.CRANE_Z_FROM - LAYOUT.CRANE_Z_TO),
				KIT.xform(Vector3(LAYOUT.CRANE_HALF_X * side, LAYOUT.CRANE_Y - 0.32,
						(LAYOUT.CRANE_Z_FROM + LAYOUT.CRANE_Z_TO) * 0.5)), C_RUST))
	for z in [LAYOUT.CRANE_Z_FROM, LAYOUT.CRANE_Z_TO]:
		parts.append(KIT.part_box(
				Vector3(LAYOUT.CRANE_HALF_X * 2.0, 0.4, 0.4),
				KIT.xform(Vector3(0.0, LAYOUT.CRANE_Y, z)), C_IRON_DARK))
	parts.append(KIT.part_box(
			Vector3(1.6, 0.9, 1.4), KIT.xform(Vector3(0.0, LAYOUT.CRANE_Y - 0.65, -9.0)), C_IRON_DARK))
	parts.append(KIT.part_box(
			Vector3(0.18, 1.6, 0.18), KIT.xform(Vector3(0.0, LAYOUT.CRANE_Y - 1.9, -9.0)), C_IRON))
	_add_group(host, "HallMachines", parts, _plate_material(), OUTLINE_PX)


# ---------------------------------------------------------------------------
# Roof: trusses, purlins, ragged skylight, broken flaps
# ---------------------------------------------------------------------------

static func _build_roof(host: Node3D) -> void:
	var parts: Array = []
	var roof_low := LAYOUT.ROOF_Y
	var thickness := LAYOUT.ROOF_THICKNESS
	var x0 := -LAYOUT.HALL_HALF_W - 0.4
	var x1 := LAYOUT.HALL_HALF_W + 0.4
	var z0 := LAYOUT.HALL_FRONT_Z + 0.4
	var z1 := LAYOUT.HALL_BACK_Z - 0.4
	var center_y := roof_low + thickness * 0.5
	var hole_x0 := LAYOUT.SKYLIGHT_CENTER.x - LAYOUT.SKYLIGHT_SIZE.x * 0.5
	var hole_x1 := LAYOUT.SKYLIGHT_CENTER.x + LAYOUT.SKYLIGHT_SIZE.x * 0.5
	var hole_z0 := LAYOUT.SKYLIGHT_CENTER.z - LAYOUT.SKYLIGHT_SIZE.y * 0.5
	var hole_z1 := LAYOUT.SKYLIGHT_CENTER.z + LAYOUT.SKYLIGHT_SIZE.y * 0.5
	# Four slabs that leave the skylight hole open.
	parts.append(KIT.part_box(
			Vector3(hole_x0 - x0, thickness, z0 - z1),
			KIT.xform(Vector3((x0 + hole_x0) * 0.5, center_y, (z0 + z1) * 0.5)), C_STONE_DARK))
	parts.append(KIT.part_box(
			Vector3(x1 - hole_x1, thickness, z0 - z1),
			KIT.xform(Vector3((hole_x1 + x1) * 0.5, center_y, (z0 + z1) * 0.5)), C_STONE_DARK))
	parts.append(KIT.part_box(
			Vector3(hole_x1 - hole_x0, thickness, z0 - hole_z1),
			KIT.xform(Vector3((hole_x0 + hole_x1) * 0.5, center_y, (z0 + hole_z1) * 0.5)), C_STONE))
	parts.append(KIT.part_box(
			Vector3(hole_x1 - hole_x0, thickness, hole_z0 - z1),
			KIT.xform(Vector3((hole_x0 + hole_x1) * 0.5, center_y, (hole_z0 + z1) * 0.5)), C_STONE))
	# Torn flaps around the hole: tilted plates that break the straight edges.
	parts.append(KIT.part_box(
			Vector3(2.6, 0.12, 1.1),
			KIT.xform(Vector3(hole_x0 + 1.0, roof_low - 0.35, hole_z1 + 0.4), Vector3(18.0, 12.0, -8.0)),
			C_IRON_DARK))
	parts.append(KIT.part_box(
			Vector3(1.4, 0.12, 2.2),
			KIT.xform(Vector3(hole_x1 - 0.5, roof_low - 0.5, hole_z0 + 1.2), Vector3(-22.0, -6.0, 14.0)),
			C_STONE_DARK))
	parts.append(KIT.part_box(
			Vector3(1.9, 0.1, 0.9),
			KIT.xform(Vector3(hole_x0 + 2.3, roof_low + 0.25, hole_z1 - 0.3), Vector3(12.0, 4.0, 20.0)),
			C_STONE))
	# Skylight frame: four beams around the opening.
	parts.append(KIT.part_box(
			Vector3(LAYOUT.SKYLIGHT_SIZE.x + 0.6, 0.35, 0.35),
			KIT.xform(Vector3(LAYOUT.SKYLIGHT_CENTER.x, roof_low + 0.1, hole_z0 - 0.15)), C_IRON))
	parts.append(KIT.part_box(
			Vector3(LAYOUT.SKYLIGHT_SIZE.x + 0.6, 0.35, 0.35),
			KIT.xform(Vector3(LAYOUT.SKYLIGHT_CENTER.x, roof_low + 0.1, hole_z1 + 0.15)), C_IRON))
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(0.35, 0.35, LAYOUT.SKYLIGHT_SIZE.y + 0.6),
				KIT.xform(Vector3(LAYOUT.SKYLIGHT_CENTER.x + side * (LAYOUT.SKYLIGHT_SIZE.x * 0.5 + 0.15),
						roof_low + 0.1, LAYOUT.SKYLIGHT_CENTER.z)), C_IRON))
	# Purlins running along Z under the roof deck.
	for side in [-1.0, 1.0]:
		for i in 3:
			parts.append(KIT.part_box(
					Vector3(0.3, 0.3, z0 - z1),
					KIT.xform(Vector3((3.0 + i * 4.0) * side, roof_low - 0.5, (z0 + z1) * 0.5)), C_IRON_DARK))
	# Trusses: the generator's triangular truss, squashed to fit the roof space.
	var truss_mesh := SHAPES.truss(LAYOUT.HALL_W - 1.2, 0.55, C_IRON_DARK)
	for i in LAYOUT.ROOF_TRUSS_COUNT:
		var z := LAYOUT.ROOF_TRUSS_Z_START - i * LAYOUT.ROOF_TRUSS_SPACING
		parts.append(KIT.part_mesh(truss_mesh,
				KIT.xform(Vector3(0.0, LAYOUT.ROOF_TRUSS_Y, z), Vector3.ZERO, Vector3(1.0, 0.15, 1.0))))
	# Cross ties between trusses at the tie-beam level.
	for i in LAYOUT.ROOF_TRUSS_COUNT - 1:
		var z := LAYOUT.ROOF_TRUSS_Z_START - i * LAYOUT.ROOF_TRUSS_SPACING - LAYOUT.ROOF_TRUSS_SPACING * 0.5
		for side in [-1.0, 1.0]:
			parts.append(KIT.part_box(
					Vector3(9.0, 0.18, 0.18),
					KIT.xform(Vector3(side * 9.0, LAYOUT.ROOF_TRUSS_Y + 0.9, z)), C_IRON_DARK))
	_add_group(host, "HallRoof", parts, _stone_material(), OUTLINE_PX)


# ---------------------------------------------------------------------------
# Far catwalk (the ghosts' patrol walkway)
# ---------------------------------------------------------------------------

static func _build_catwalk(host: Node3D) -> void:
	var parts: Array = []
	var y := LAYOUT.FAR_CATWALK_Y
	var z := LAYOUT.FAR_CATWALK_Z
	var half := LAYOUT.FAR_CATWALK_HALF_X
	parts.append(KIT.part_box(
			Vector3(half * 2.0, 0.35, 2.4), KIT.xform(Vector3(0.0, y, z)), C_IRON_DARK))
	parts.append(KIT.part_box(
			Vector3(half * 2.0, 0.12, 0.3), KIT.xform(Vector3(0.0, y + 0.24, z - 1.05)), C_RUST))
	var x := -half + 1.0
	while x < half:
		parts.append(KIT.part_box(
				Vector3(0.35, y - LAYOUT.FAR_FLOOR_Y, 0.35),
				KIT.xform(Vector3(x, (y + LAYOUT.FAR_FLOOR_Y) * 0.5, z)), C_IRON))
		x += 4.0
	for side in [-1.0, 1.0]:
		parts.append(KIT.part_box(
				Vector3(0.12, 1.0, 0.12), KIT.xform(Vector3(side * (half - 0.2), y + 0.85, z)), C_IRON))
		parts.append(KIT.part_box(
				Vector3(half * 2.0, 0.1, 0.1), KIT.xform(Vector3(0.0, y + 1.35, z)), C_RUST))
	# A couple of hanging chain links off the catwalk edge for scale.
	for side in [-1.0, 1.0]:
		for i in 4:
			parts.append(KIT.part_mesh(SHAPES.chain_link(0.5, 0.3, C_IRON_DARK),
					KIT.xform(Vector3(side * (half - 0.2), y - 0.35 - i * 0.42, z + 1.2),
							Vector3(0.0, 90.0 if i % 2 == 0 else 0.0, 0.0))))
	_add_group(host, "HallCatwalk", parts, _plate_material(), OUTLINE_PX)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _stone_material() -> ShaderMaterial:
	return KIT.textured(KIT.luminance_texture("stone"), 9.0)


static func _plate_material() -> ShaderMaterial:
	return KIT.textured(KIT.luminance_texture("plate"), 12.0)


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
