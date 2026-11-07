class_name TitleShapes
extends RefCounted
## Deterministic low-poly ArrayMesh generators for the forge-hall title.
##
## Every generator is a pure function of its arguments: no nodes, no RNG, no
## time. Calling one twice returns meshes with identical vertex counts (the
## title's pixel look must not shimmer between runs). Meshes are flat-shaded
## triangles with baked vertex colours, in metres, local to the shape:
##   - gear:   disc in the XY plane, thickness along Z (faces a -Z camera);
##   - arch:   ring/portal in the XY plane (local origin at the base centre),
##             thickness along Z; build upward from y = 0;
##   - truss:  triangular roof truss, bottom chord on y = 0, length along X,
##             thickness along Z, apex on +Y;
##   - chain_link: one oval chain link in the XY plane (long axis Y), tube
##             thickness along Z, closed swept loop;
##   - cloth:  hanging sheet, local origin at the TOP-CENTRE edge, hanging down
##             to y = -height, width centred on X, with UVs (u across, v down)
##             for a cloth shader. Double sided.
##
## Front-face winding is auto-detected once from a BoxMesh, so the triangles are
## oriented exactly like the engine's own primitives (Godot's winding order has
## changed between renderers; never hard-code it).

const KIT := preload("res://scripts/title3d/kit/title_kit.gd")

static var _winding := 0


# ---------------------------------------------------------------------------
# Gear
# ---------------------------------------------------------------------------

## Spur gear with `teeth` teeth, tip radius `radius` in metres, extruded `depth`
## along Z and a raised hub of `hub_radius`. `color` is the base vertex colour;
## darker shades are derived for the rim and hub so the gear reads in one tone.
static func gear(radius: float, teeth: int, depth: float, hub_radius: float, color: Color) -> ArrayMesh:
	var builder := _Builder.new(winding_sign())
	var r := maxf(radius, 0.05)
	var tooth_count := maxi(4, teeth)
	var d := maxf(depth, 0.02)
	var hub := clampf(hub_radius, 0.0, r * 0.85)
	var half := d * 0.5
	var root_r := r * 0.82
	var pitch := TAU / float(tooth_count)
	var profile := PackedVector2Array()
	for i in tooth_count:
		var base := pitch * float(i)
		profile.append(_polar(root_r, base))
		profile.append(_polar(r, base + pitch * 0.18))
		profile.append(_polar(r, base + pitch * 0.52))
		profile.append(_polar(root_r, base + pitch * 0.70))
	var n := profile.size()
	var body_color := color
	var rim_color := color.darkened(0.20)
	var hub_color := color.darkened(0.34)
	var hub_top_color := color.darkened(0.12)
	# Front (+Z) and back (-Z) discs, then the toothed rim wall.
	var bag := Vector3(0.0, 0.0, half)
	var bak := Vector3(0.0, 0.0, -half)
	for i in n:
		var p0 := profile[i]
		var p1 := profile[(i + 1) % n]
		builder.tri(bag, _flat(p0, half), _flat(p1, half), Vector3.BACK, body_color)
		builder.tri(bak, _flat(p1, -half), _flat(p0, -half), Vector3.FORWARD, body_color)
	for i in n:
		var p0 := profile[i]
		var p1 := profile[(i + 1) % n]
		var edge := p1 - p0
		var outward2 := Vector2(-edge.y, edge.x).normalized()
		if outward2.dot((p0 + p1) * 0.5) < 0.0:
			outward2 = -outward2
		var outward := Vector3(outward2.x, outward2.y, 0.0)
		builder.quad(
				Vector3(p0.x, p0.y, half), Vector3(p1.x, p1.y, half),
				Vector3(p1.x, p1.y, -half), Vector3(p0.x, p0.y, -half),
				outward, rim_color)
	# Raised hub and axle stub on both faces.
	if hub > 0.0:
		var hub_h := d * 0.42
		var sides := clampi(tooth_count, 8, 16)
		for side in [1.0, -1.0]:
			builder.cylinder(hub, half * side, (half + hub_h) * side, sides, hub_color, hub_top_color)
			builder.cylinder(hub * 0.30, (half + hub_h) * side, (half + hub_h * 1.55) * side,
					sides, hub_top_color, hub_top_color.darkened(0.1))
	return builder.commit()


# ---------------------------------------------------------------------------
# Arch
# ---------------------------------------------------------------------------

## Round-arched portal (拱券) of outer span `width` and total height `height`,
## extruded `depth` along Z. Local origin is the base centre; the ring is about
## `min(width, height) * 0.16` thick and the opening is open at the bottom.
static func arch(width: float, height: float, depth: float, segments: int, color: Color) -> ArrayMesh:
	var builder := _Builder.new(winding_sign())
	var w := maxf(width, 0.2)
	var h := maxf(height, 0.2)
	var d := maxf(depth, 0.02)
	var outer := w * 0.5
	var thickness := clampf(minf(w, h) * 0.16, 0.10, outer * 0.6)
	var inner := maxf(outer - thickness, outer * 0.25)
	var leg := maxf(h - outer, 0.0)
	var seg := clampi(segments, 4, 64)
	var half := d * 0.5
	var face_color := color
	var wall_color := color.darkened(0.16)
	var inner_color := color.darkened(0.30)
	# Vertical legs: front, back, outer wall, inner wall, bottom cap.
	if leg > 0.0:
		for side in [-1.0, 1.0]:
			var ox: float = outer * side
			var ix: float = inner * side
			builder.quad(
					Vector3(ox, 0.0, half), Vector3(ix, 0.0, half),
					Vector3(ix, leg, half), Vector3(ox, leg, half),
					Vector3.BACK, face_color)
			builder.quad(
					Vector3(ox, 0.0, -half), Vector3(ox, leg, -half),
					Vector3(ix, leg, -half), Vector3(ix, 0.0, -half),
					Vector3.FORWARD, face_color)
			builder.quad(
					Vector3(ox, 0.0, -half), Vector3(ox, 0.0, half),
					Vector3(ox, leg, half), Vector3(ox, leg, -half),
					Vector3(side, 0.0, 0.0), wall_color)
			builder.quad(
					Vector3(ix, 0.0, half), Vector3(ix, 0.0, -half),
					Vector3(ix, leg, -half), Vector3(ix, leg, half),
					Vector3(-side, 0.0, 0.0), inner_color)
			builder.quad(
					Vector3(ox, 0.0, -half), Vector3(ix, 0.0, -half),
					Vector3(ix, 0.0, half), Vector3(ox, 0.0, half),
					Vector3.DOWN, wall_color)
	# Semicircular ring from the left springing to the right springing.
	for k in seg:
		var a0 := PI * (1.0 - float(k) / float(seg))
		var a1 := PI * (1.0 - float(k + 1) / float(seg))
		var am := (a0 + a1) * 0.5
		var o0 := Vector2(cos(a0), sin(a0)) * outer + Vector2(0.0, leg)
		var o1 := Vector2(cos(a1), sin(a1)) * outer + Vector2(0.0, leg)
		var i0 := Vector2(cos(a0), sin(a0)) * inner + Vector2(0.0, leg)
		var i1 := Vector2(cos(a1), sin(a1)) * inner + Vector2(0.0, leg)
		var radial := Vector3(cos(am), sin(am), 0.0)
		builder.quad(
				Vector3(o0.x, o0.y, half), Vector3(i0.x, i0.y, half),
				Vector3(i1.x, i1.y, half), Vector3(o1.x, o1.y, half),
				Vector3.BACK, face_color)
		builder.quad(
				Vector3(o0.x, o0.y, -half), Vector3(o1.x, o1.y, -half),
				Vector3(i1.x, i1.y, -half), Vector3(i0.x, i0.y, -half),
				Vector3.FORWARD, face_color)
		builder.quad(
				Vector3(o0.x, o0.y, -half), Vector3(o0.x, o0.y, half),
				Vector3(o1.x, o1.y, half), Vector3(o1.x, o1.y, -half),
				radial, wall_color)
		builder.quad(
				Vector3(i0.x, i0.y, half), Vector3(i0.x, i0.y, -half),
				Vector3(i1.x, i1.y, -half), Vector3(i1.x, i1.y, half),
				-radial, inner_color)
	# When there is no straight leg the ring starts on the floor: close its ends.
	if leg <= 0.0:
		for side in [-1.0, 1.0]:
			builder.quad(
					Vector3(outer * side, 0.0, -half), Vector3(inner * side, 0.0, -half),
					Vector3(inner * side, 0.0, half), Vector3(outer * side, 0.0, half),
					Vector3.DOWN, wall_color)
	return builder.commit()


# ---------------------------------------------------------------------------
# Truss
# ---------------------------------------------------------------------------

## Triangular roof truss: bottom chord on y = 0 spanning `length` along X, apex
## on +Y at `length * 0.28`, beams `depth` thick along Z. Callers usually scale
## Y down to fit the roof space (the title hall does).
static func truss(length: float, depth: float, color: Color) -> ArrayMesh:
	var span := maxf(length, 1.0)
	var d := maxf(depth, 0.05)
	var beam := clampf(span * 0.032, 0.12, 0.5)
	var rise := span * 0.28
	var chord_color := color
	var web_color := color.darkened(0.12)
	var parts: Array = []
	parts.append(KIT.part_box(
			Vector3(span, beam, d), Transform3D(Basis(), Vector3(0.0, beam * 0.5, 0.0)), chord_color))
	# Two top chords from the ends to the apex.
	var apex := Vector3(0.0, rise, 0.0)
	for side in [-1.0, 1.0]:
		var start := Vector3(span * 0.5 * side, beam * 0.5, 0.0)
		var delta := apex - start
		var top_length := delta.length()
		var angle := atan2(delta.y, delta.x)
		var basis := Basis(Vector3(0.0, 0.0, 1.0), angle)
		parts.append(KIT.part_box(
				Vector3(top_length, beam * 0.8, d * 0.9),
				Transform3D(basis, (start + apex) * 0.5), web_color))
	# King post and two verticals under the top chords.
	var king_length := rise - beam
	if king_length > 0.05:
		parts.append(KIT.part_box(
				Vector3(beam * 0.8, king_length, d * 0.8),
				Transform3D(Basis(), Vector3(0.0, beam + king_length * 0.5, 0.0)), web_color))
	for side in [-1.0, 1.0]:
		var x: float = span * 0.25 * side
		var top := beam + (rise - beam) * 0.5
		parts.append(KIT.part_box(
				Vector3(beam * 0.6, top - beam, d * 0.7),
				Transform3D(Basis(), Vector3(x, (top + beam) * 0.5, 0.0)), web_color))
	return KIT.merge(parts)


# ---------------------------------------------------------------------------
# Chain link
# ---------------------------------------------------------------------------

## One oval chain link lying in the XY plane (long axis Y, so it hangs), `length`
## along Y and `width` across X, swept from a square wire section whose size is
## derived from `width`. Closed watertight loop; alternate links by rotating 90
## degrees around Y in the builder.
static func chain_link(length: float, width: float, color: Color) -> ArrayMesh:
	var builder := _Builder.new(winding_sign())
	var total_length := maxf(length, 0.12)
	var w := clampf(width, 0.06, total_length * 0.8)
	var wire := maxf(w * 0.26, 0.02)
	var half_wire := wire * 0.5
	var arc_center := total_length * 0.5 - w * 0.5
	var arc_radius := maxf(w * 0.5 - half_wire, half_wire * 0.5)
	# Centreline samples around the stadium: right straight, top arc, left
	# straight, bottom arc (the last arc closes back onto the first sample).
	var points: Array[Vector3] = []
	var straight_x := w * 0.5 - half_wire
	points.append(Vector3(straight_x, -arc_center, 0.0))
	points.append(Vector3(straight_x, arc_center, 0.0))
	var arc_segments := 6
	for k in range(1, arc_segments):
		var angle := PI * float(k) / float(arc_segments)
		points.append(Vector3(arc_radius * cos(angle), arc_center + arc_radius * sin(angle), 0.0))
	points.append(Vector3(-straight_x, arc_center, 0.0))
	points.append(Vector3(-straight_x, -arc_center, 0.0))
	for k in range(1, arc_segments):
		var angle := PI + PI * float(k) / float(arc_segments)
		points.append(Vector3(arc_radius * cos(angle), -arc_center + arc_radius * sin(angle), 0.0))
	var count := points.size()
	var ring: Array = []
	for i in count:
		var prev := points[(i + count - 1) % count]
		var next := points[(i + 1) % count]
		var tangent := (next - prev).normalized()
		var in_plane := Vector3(-tangent.y, tangent.x, 0.0)
		var binormal := Vector3(0.0, 0.0, 1.0)
		var p := points[i]
		ring.append([
			p + in_plane * half_wire + binormal * half_wire,
			p - in_plane * half_wire + binormal * half_wire,
			p - in_plane * half_wire - binormal * half_wire,
			p + in_plane * half_wire - binormal * half_wire,
		])
	var face_color := color
	var side_color := color.darkened(0.18)
	for i in count:
		var current: Array = ring[i]
		var following: Array = ring[(i + 1) % count]
		var spine0 := points[i]
		var spine1 := points[(i + 1) % count]
		for side in 4:
			var other := (side + 1) % 4
			var a: Vector3 = current[side]
			var b: Vector3 = current[other]
			var c: Vector3 = following[other]
			var d2: Vector3 = following[side]
			var outward := (a + b + c + d2) * 0.25 - (spine0 + spine1) * 0.5
			if outward.length_squared() < 1e-10:
				continue
			var shade := face_color if side == 0 or side == 2 else side_color
			builder.quad(a, b, c, d2, outward, shade)
	return builder.commit()


# ---------------------------------------------------------------------------
# Cloth
# ---------------------------------------------------------------------------

## Hanging sheet with UVs for a cloth shader. Origin is the top-centre edge; the
## sheet hangs down to y = -height, x is centred, +Z is the visible face.
## `top_color` paints the first band (rod pocket / top hem), `color` the rest.
## Double sided (both faces are baked so the banner reads from either side).
static func cloth(width: float, height: float, segments_x: int, segments_y: int,
		color: Color, top_color: Color) -> ArrayMesh:
	var w := maxf(width, 0.1)
	var h := maxf(height, 0.1)
	var sx := clampi(segments_x, 1, 64)
	var sy := clampi(segments_y, 1, 64)
	var grid: Array[Vector3] = []
	for j in sy + 1:
		var v := float(j) / float(sy)
		for i in sx + 1:
			var u := float(i) / float(sx)
			var x := (u - 0.5) * w
			var y := -h * v
			var flutter := sin(u * PI * 2.0 + v * 1.3) * w * 0.035 * v
			grid.append(Vector3(x, y, flutter))
	var front_count := (sx + 1) * (sy + 1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for j in sy + 1:
		for i in sx + 1:
			var v := float(j) / float(sy)
			var u := float(i) / float(sx)
			var index := _grid_index(i, j, sx)
			var left := _grid_index(maxi(i - 1, 0), j, sx)
			var right := _grid_index(mini(i + 1, sx), j, sx)
			var up := _grid_index(i, maxi(j - 1, 0), sx)
			var down := _grid_index(i, mini(j + 1, sy), sx)
			var normal := (grid[right] - grid[left]).cross(grid[down] - grid[up])
			if normal.length_squared() < 1e-12:
				normal = Vector3.BACK
			else:
				normal = normal.normalized()
				if normal.z < 0.0:
					normal = -normal
			verts.append(grid[index])
			normals.append(normal)
			uvs.append(Vector2(u, v))
			var c := top_color.lerp(color, clampf((v - 0.06) / 0.30, 0.0, 1.0))
			if (i + j) % 3 == 0:
				c = c.darkened(0.05)
			colors.append(c)
	var indices := PackedInt32Array()
	var winding := winding_sign()
	for j in sy:
		for i in sx:
			var a := _grid_index(i, j, sx)
			var b := _grid_index(i + 1, j, sx)
			var c := _grid_index(i + 1, j + 1, sx)
			var d := _grid_index(i, j + 1, sx)
			# The quad's geometric normal points down -Z for this vertex order;
			# orientate it toward the front (+Z) following the engine winding.
			var triples := [[a, b, c], [a, c, d]]
			for triple in triples:
				var ia: int = triple[0]
				var ib: int = triple[1]
				var ic: int = triple[2]
				var cross := (grid[ib] - grid[ia]).cross(grid[ic] - grid[ia])
				var orientation := 1 if cross.dot(Vector3.BACK) >= 0.0 else -1
				if orientation == winding:
					indices.append(ia)
					indices.append(ib)
					indices.append(ic)
				else:
					indices.append(ia)
					indices.append(ic)
					indices.append(ib)
	# Back layer: same sheet, normals flipped and winding reversed.
	for k in front_count:
		verts.append(verts[k])
		normals.append(-normals[k])
		colors.append(colors[k])
		uvs.append(uvs[k])
	for k in range(0, indices.size(), 3):
		var a := indices[k]
		var b := indices[k + 1]
		var c := indices[k + 2]
		indices.append(front_count + a)
		indices.append(front_count + c)
		indices.append(front_count + b)
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Sign convention of Godot's front faces, measured once from a BoxMesh:
## cross(b - a, c - a) . outward_normal is +1 or -1 for a correctly oriented
## triangle. Detecting instead of hard-coding keeps this file correct across
## renderers (Godot's winding order has changed between versions).
static func winding_sign() -> int:
	if _winding == 0:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		var arrays := box.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var i0 := 0
		var i1 := 1
		var i2 := 2
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.size() >= 3:
				i0 = indices[0]
				i1 = indices[1]
				i2 = indices[2]
		var cross := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		_winding = 1 if cross.dot(normals[i0]) >= 0.0 else -1
	return _winding


static func _polar(radius: float, angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * radius


static func _flat(point: Vector2, z: float) -> Vector3:
	return Vector3(point.x, point.y, z)


static func _grid_index(i: int, j: int, segments_x: int) -> int:
	return j * (segments_x + 1) + i


# ---------------------------------------------------------------------------
# Flat-shaded triangle accumulator
# ---------------------------------------------------------------------------

class _Builder extends RefCounted:
	var winding := 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()


	func _init(sign: int) -> void:
		winding = 1 if sign >= 0 else -1


	func tri(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
		var cross := (b - a).cross(c - a)
		if cross.length_squared() < 1e-12:
			return
		var orientation := 1 if cross.dot(outward) >= 0.0 else -1
		if orientation != winding:
			var swap := b
			b = c
			c = swap
		var start := verts.size()
		verts.append(a)
		verts.append(b)
		verts.append(c)
		var normal := outward.normalized()
		for j in 3:
			normals.append(normal)
			colors.append(color)
			indices.append(start + j)


	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color) -> void:
		tri(a, b, c, outward, color)
		tri(a, c, d, outward, color)


	## Capped cylinder between two Z planes; `near_z`/`far_z` may be in any order.
	func cylinder(radius: float, near_z: float, far_z: float, sides: int,
			wall_color: Color, cap_color: Color) -> void:
		var step := TAU / float(maxi(sides, 3))
		var cap_outward := Vector3(0.0, 0.0, 1.0 if far_z > near_z else -1.0)
		for k in sides:
			var a0 := step * float(k)
			var a1 := step * float(k + 1)
			var p0 := Vector2(cos(a0), sin(a0)) * radius
			var p1 := Vector2(cos(a1), sin(a1)) * radius
			var mid := (a0 + a1) * 0.5
			var outward := Vector3(cos(mid), sin(mid), 0.0)
			quad(
					Vector3(p0.x, p0.y, near_z), Vector3(p1.x, p1.y, near_z),
					Vector3(p1.x, p1.y, far_z), Vector3(p0.x, p0.y, far_z),
					outward, wall_color)
			tri(Vector3(0.0, 0.0, far_z), Vector3(p0.x, p0.y, far_z),
					Vector3(p1.x, p1.y, far_z), cap_outward, cap_color)


	func is_empty() -> bool:
		return verts.is_empty()


	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if verts.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
