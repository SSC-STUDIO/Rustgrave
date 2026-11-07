extends RefCounted
## Shared procedural geometry / material helpers for the 3D title props
## (`scripts/title3d/props/*.gd`).
##
## The public surface mirrors the agreed `scripts/title3d/kit/title_kit.gd` contract:
##   mat(flags) / textured(tex, texels_per_unit) / unshaded(tex, additive) /
##   palette_texture() / part_box(size, xform, color, emissive) /
##   part_cyl(radius, height, sides, xform, color, emissive) / merge(parts) /
##   mesh_instance(mesh, material, at, name) / outline(mi, width_px)
## with the same flag bits (EMISSIVE / HALF_EMISSIVE / NO_OUTLINE).
##
## title-kit owns the "real" implementation. This file keeps a self-contained fallback
## so every prop is testable (and the title screen keeps working) before/without the
## kit, and so the kit can be adopted without touching the props:
## `kit_script()` returns the kit GDScript when it exists; props keep calling the
## neutral helpers below, which prefer the kit and fall back to SurfaceTool meshes and
## StandardMaterial3D materials.
##
## Everything here runs at build time only. Per-frame code in the props changes node
## transforms / visibility / Sprite tint, never meshes or materials.

const KIT_PATH := "res://scripts/title3d/kit/title_kit.gd"
const SHAPES_PATH := "res://scripts/title3d/kit/shapes.gd"

const EMISSIVE := 1
const HALF_EMISSIVE := 2
const NO_OUTLINE := 4

## 2D title palette (scripts/ui/title_prop.gd) shared by every prop.
const OUTLINE := Color("#0B0910")
const IRON_DARK := Color("#241C22")
const IRON := Color("#3C343C")
const IRON_LIGHT := Color("#6A5A5E")
const HOT_CORE := Color(1.0, 0.93, 0.70)
const HOT := Color(1.0, 0.62, 0.20)
const HOT_DEEP := Color(0.86, 0.30, 0.10)
const EMBER_COOL := Color(0.42, 0.08, 0.04)
const GLOW_WARM := Color(1.0, 0.55, 0.20)
const STEEL := Color("#8A8F9A")
const STEEL_LIGHT := Color("#B9BEC8")
const STEEL_DARK := Color("#555B68")
const CLOTH := Color("#5C2A26")
const CLOTH_LIGHT := Color("#7C3A30")
const CLOTH_DARK := Color("#3A1A1C")
const EMBLEM := Color("#B08A4A")
const CLOAK := Color("#1B2230")
const CLOAK_RIM := Color("#3A4660")
const EYES := Color(0.62, 0.84, 1.0)
const LAMP := Color(1.0, 0.72, 0.35)
const SOUL_CORE := Color(0.92, 0.97, 1.0)
const SOUL_HALO := Color(0.55, 0.78, 1.0)

static var _kit = null
static var _kit_checked := false
static var _shapes = null
static var _shapes_checked := false
static var _mats := {}
static var _tex_cache := {}
static var _quad_meshes := {}


# ------------------------------------------------------------------ kit seam ----

## The kit script when it has landed, else null (the fallback below is used). Kept
## lazy so a missing/partial kit can never stop the title screen from loading.
static func kit_script():
	if not _kit_checked:
		_kit_checked = true
		if ResourceLoader.exists(KIT_PATH):
			_kit = load(KIT_PATH)
	return _kit


static func has_kit() -> bool:
	return kit_script() != null


## The kit's shape generators (`gear` / `cloth` / ...) when they have landed.
static func shapes_script():
	if not _shapes_checked:
		_shapes_checked = true
		if ResourceLoader.exists(SHAPES_PATH):
			_shapes = load(SHAPES_PATH)
	return _shapes


## Deterministic spur gear in the XY plane (thickness along Z), from title-kit shapes
## when available, else the local box/cylinder stand-in.
static func shape_gear(radius: float, teeth: int, depth: float, hub_radius: float,
		color: Color) -> ArrayMesh:
	var shapes = shapes_script()
	if shapes != null and _has_static(shapes, "gear"):
		return shapes.gear(radius, teeth, depth, hub_radius, color)
	var parts: Array = []
	parts.append(cyl(hub_radius, depth * 1.5, 12, Vector3.ZERO, color.darkened(0.34),
			Vector3(90.0, 0.0, 0.0)))
	parts.append(cyl(radius * 0.80, depth * 0.55, 20, Vector3.ZERO, color.darkened(0.20),
			Vector3(90.0, 0.0, 0.0)))
	var tooth_w := TAU * radius / float(maxi(teeth, 4))
	for k in maxi(teeth, 4):
		var a := TAU * float(k) / float(maxi(teeth, 4))
		parts.append(box(Vector3(radius * 0.20, tooth_w * 0.72, depth),
				Vector3(cos(a) * radius, sin(a) * radius, 0.0), color,
				Vector3(0.0, 0.0, rad_to_deg(a))))
	return merge(parts)


## A hanging cloth sheet with UVs (top-centre origin, hanging down, double sided),
## from title-kit shapes when available, else the local torn-grid fallback.
static func shape_cloth(width: float, height: float, segments_x: int, segments_y: int,
		color: Color, top_color: Color) -> ArrayMesh:
	var shapes = shapes_script()
	if shapes != null and _has_static(shapes, "cloth"):
		return shapes.cloth(width, height, segments_x, segments_y, color, top_color)
	return cloth_mesh(segments_x, segments_y, width, height, true)


# --------------------------------------------------------------- materials ------

static func mat(flags: int = 0) -> Material:
	var kit = kit_script()
	if kit != null and _has_static(kit, "mat"):
		return kit.mat(flags)
	var key := "m%d" % flags
	var cached: Material = _mats.get(key)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.metallic = 0.05
	m.specular = 0.25
	# The fallback mesh builder writes fixed triangle winding for clarity; the title
	# budget makes double-sided benches harmless. The kit shader keeps its own culling.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if flags & EMISSIVE:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif flags & HALF_EMISSIVE:
		m.emission_enabled = true
		m.emission = Color(1.0, 1.0, 1.0)
		m.emission_energy_multiplier = 0.32
	_mats[key] = m
	return m


static func textured(tex: Texture2D, texels_per_unit: float = 16.0) -> Material:
	var kit = kit_script()
	if kit != null and _has_static(kit, "textured"):
		return kit.textured(tex, texels_per_unit)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.9
	m.metallic = 0.1
	return m


static func unshaded(tex: Texture2D, additive: bool = false) -> Material:
	var kit = kit_script()
	if kit != null and _has_static(kit, "unshaded"):
		return kit.unshaded(tex, additive)
	return additive_material(tex, additive)


static func palette_texture() -> Texture2D:
	var kit = kit_script()
	if kit != null and _has_static(kit, "palette_texture"):
		return kit.palette_texture()
	return solid_texture(Color(0.35, 0.3, 0.3), 8)


## Stand-in for the kit's shared palette texture: a tiny strip of the 2D title palette.
static func solid_texture(color: Color, size: int = 8) -> Texture2D:
	var key := "solid:%s:%d" % [color.to_html(), size]
	var cached: Texture2D = _tex_cache.get(key)
	if cached != null:
		return cached
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func additive_material(tex: Texture2D, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	if tex != null:
		m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color.WHITE
	return m


# ------------------------------------------------------------------- parts -----

static func xform_at(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Transform3D:
	if rot_deg == Vector3.ZERO:
		return Transform3D(Basis.IDENTITY, pos)
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)


static func part_box(size: Vector3, xform: Transform3D, color: Color, emissive: float = 0.0) -> Dictionary:
	var kit = kit_script()
	if kit != null and _has_static(kit, "part_box"):
		return kit.part_box(size, xform, color, emissive)
	return {"kind": "box", "size": size, "xform": xform, "color": color, "emissive": emissive}


static func part_cyl(radius: float, height: float, sides: int, xform: Transform3D,
		color: Color, emissive: float = 0.0) -> Dictionary:
	var kit = kit_script()
	if kit != null and _has_static(kit, "part_cyl"):
		return kit.part_cyl(radius, height, sides, xform, color, emissive)
	return {"kind": "cyl", "radius": radius, "height": height, "sides": maxi(sides, 3),
			"xform": xform, "color": color, "emissive": emissive}


## One prebuilt ArrayMesh part (baked vertex colours kept, alpha becomes the emission
## mask). Used to splice title-kit shapes (`gear`, `cloth`, ...) into a merged mesh.
static func part_mesh(mesh: ArrayMesh, xform: Transform3D, emissive: float = 0.0) -> Dictionary:
	var kit = kit_script()
	if kit != null and _has_static(kit, "part_mesh") and mesh != null:
		return kit.part_mesh(mesh, xform, emissive)
	return {"kind": "mesh", "mesh": mesh, "xform": xform, "emissive": emissive}


## Convenience wrappers: `box(size, center, color)` is the common case.
static func box(size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO,
		emissive: float = 0.0) -> Dictionary:
	return part_box(size, xform_at(pos, rot_deg), color, emissive)


static func cyl(radius: float, height: float, sides: int, pos: Vector3, color: Color,
		rot_deg: Vector3 = Vector3.ZERO, emissive: float = 0.0) -> Dictionary:
	return part_cyl(radius, height, sides, xform_at(pos, rot_deg), color, emissive)


static func merge(parts: Array) -> ArrayMesh:
	var kit = kit_script()
	if kit != null and _has_static(kit, "merge"):
		return kit.merge(parts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		match String(part.get("kind", "box")):
			"box":
				_append_box(st, part)
			"cyl":
				_append_cyl(st, part)
			"mesh":
				_append_mesh_part(st, part)
	st.index()
	return st.commit()


static func mesh_instance(mesh: Mesh, material: Material, at: Variant, node_name: String) -> MeshInstance3D:
	var xform := Transform3D.IDENTITY
	if at is Transform3D:
		xform = at
	elif at is Vector3:
		xform = Transform3D(Basis.IDENTITY, at)
	var array_mesh := mesh as ArrayMesh
	var kit = kit_script()
	if kit != null and array_mesh != null and _has_static(kit, "mesh_instance"):
		var mi_kit = kit.mesh_instance(array_mesh, material, xform, node_name)
		if mi_kit != null:
			return mi_kit
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	if material != null:
		mi.material_override = material
	mi.transform = xform
	return mi


static func outline(_mi: MeshInstance3D, _width_px: float) -> void:
	var kit = kit_script()
	if kit != null and _has_static(kit, "outline"):
		kit.outline(_mi, _width_px)


# -------------------------------------------------------------- mesh build -----

static func _append_box(st: SurfaceTool, part: Dictionary) -> void:
	var size: Vector3 = part["size"]
	var xf: Transform3D = part["xform"]
	var col: Color = part["color"]
	var e := float(part.get("emissive", 0.0))
	var c := _glow_tint(col, e)
	var h := size * 0.5
	var n := xf.basis
	# 6 faces: normal, 4 corners (CCW when seen from outside).
	_quad(st, xf, n * Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
			Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), c)
	_quad(st, xf, n * Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
			Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), c)
	_quad(st, xf, n * Vector3.FORWARD, Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z),
			Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), c)
	_quad(st, xf, n * Vector3.BACK, Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), c)
	_quad(st, xf, n * Vector3.LEFT, Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z),
			Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), c)
	_quad(st, xf, n * Vector3.RIGHT, Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z),
			Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), c)


static func _append_cyl(st: SurfaceTool, part: Dictionary) -> void:
	var r := float(part["radius"])
	var h := float(part["height"])
	var sides := int(part["sides"])
	var xf: Transform3D = part["xform"]
	var c := _glow_tint(part["color"], float(part.get("emissive", 0.0)))
	var basis := xf.basis
	var up := basis * Vector3.UP
	var top := r if h > 0.0 else 0.0
	var half := h * 0.5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(cos(a0) * r, -half, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, -half, sin(a1) * r)
		var q0 := Vector3(cos(a0) * top, half, sin(a0) * top)
		var q1 := Vector3(cos(a1) * top, half, sin(a1) * top)
		var n0 := (basis * Vector3(cos(a0), 0.0, sin(a0))).normalized()
		var n1 := (basis * Vector3(cos(a1), 0.0, sin(a1))).normalized()
		# side quad (two triangles, smooth-ish normals)
		st.set_color(c)
		st.set_normal(n0)
		st.add_vertex(xf * p0)
		st.set_color(c)
		st.set_normal(n1)
		st.add_vertex(xf * p1)
		st.set_color(c)
		st.set_normal(n1)
		st.add_vertex(xf * q1)
		st.set_color(c)
		st.set_normal(n0)
		st.add_vertex(xf * p0)
		st.set_color(c)
		st.set_normal(n1)
		st.add_vertex(xf * q1)
		st.set_color(c)
		st.set_normal(n0)
		st.add_vertex(xf * q0)
	# caps
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		_cap_tri(st, xf, up, half, r, a0, a1, c, false)
		_cap_tri(st, xf, -up, -half, r, a0, a1, c, true)


static func _cap_tri(st: SurfaceTool, xf: Transform3D, normal: Vector3, y: float, r: float,
		a0: float, a1: float, color: Color, flip: bool) -> void:
	var p0 := Vector3(cos(a0) * r, y, sin(a0) * r)
	var p1 := Vector3(cos(a1) * r, y, sin(a1) * r)
	var c := Vector3(0.0, y, 0.0)
	var tri := [p0, c, p1] if not flip else [p0, p1, c]
	for p in tri:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(xf * p)


## Append a prebuilt ArrayMesh part, keeping its baked vertex colours and forcing the
## part's emission mask into the alpha channel (same convention as title-kit).
static func _append_mesh_part(st: SurfaceTool, part: Dictionary) -> void:
	var mesh: ArrayMesh = part.get("mesh", null)
	if mesh == null:
		return
	var xf: Transform3D = part.get("xform", Transform3D.IDENTITY)
	var alpha := 1.0 - clampf(float(part.get("emissive", 0.0)), 0.0, 1.0)
	var normal_matrix := xf.basis.inverse().transposed()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var normals := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			normals = arrays[Mesh.ARRAY_NORMAL]
		var colors := PackedColorArray()
		if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
			colors = arrays[Mesh.ARRAY_COLOR]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in verts.size():
				indices.append(i)
		for idx in indices:
			if idx < 0 or idx >= verts.size():
				continue
			var c := Color(1.0, 1.0, 1.0, alpha)
			if idx < colors.size():
				c = Color(colors[idx].r, colors[idx].g, colors[idx].b, alpha)
			st.set_color(c)
			if idx < normals.size():
				st.set_normal((normal_matrix * normals[idx]).normalized())
			else:
				st.set_normal(Vector3.UP)
			st.add_vertex(xf * verts[idx])


static func _quad(st: SurfaceTool, xf: Transform3D, normal: Vector3,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var tri := [a, b, c, a, c, d]
	for p in tri:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(xf * p)


## Slight whitening for emissive parts when the fallback material is lit: the real
## look comes from the kit shader's vertex-alpha emissive mask.
static func _glow_tint(color: Color, emissive: float) -> Color:
	if emissive <= 0.0:
		return color
	return color.lerp(Color(1.0, 1.0, 1.0), clampf(emissive, 0.0, 1.0) * 0.35)


# ------------------------------------------------------------------ cloth ------

## A torn banner cloth mesh: `cols` x `rows` grid in the XY plane (top edge at y=0,
## hanging down), vertex colours baked (folds + warm bottom hem), optional half
## sword emblem. UV.y runs 0..1 top to bottom so a vertex shader can wave it.
static func cloth_mesh(cols: int, rows: int, width: float, height: float,
		with_emblem: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cw := width / float(cols)
	var ch := height / float(rows)
	for row in rows:
		for col in cols:
			var x0 := -width * 0.5 + cw * float(col)
			var y0 := -ch * float(row)
			var x1 := x0 + cw
			var y1 := y0 - ch
			var v := float(row) / float(maxi(rows - 1, 1))
			var base := CLOTH.lerp(CLOTH_DARK, v * 0.35)
			# vertical fold: every third column catches a little light
			if col % 3 == 1:
				base = base.lerp(CLOTH_LIGHT, 0.55)
			elif col % 3 == 2:
				base = base.lerp(CLOTH_DARK, 0.35)
			# torn hem: the outer columns of the last row are missing
			var edge := col == 0 or col == cols - 1
			if edge and row == rows - 1:
				continue
			if row == rows - 1:
				base = base.lerp(Color(0.95, 0.42, 0.16), 0.30)
			var uv := Rect2(float(col) / float(cols), float(row) / float(rows),
					1.0 / float(cols), 1.0 / float(rows))
			_cloth_quad(st, x0, y0, x1, y1, base, uv)
	if with_emblem:
		# half a sword: a vertical bar and a crossguard, centred mid-cloth
		var cy := -height * 0.42
		_cloth_quad(st, -0.09, cy + 0.55, 0.09, cy - 0.75, EMBLEM,
				Rect2(0.45, 0.36, 0.1, 0.3))
		_cloth_quad(st, -0.34, cy + 0.1, 0.34, cy - 0.1, EMBLEM,
				Rect2(0.3, 0.54, 0.4, 0.08))
	st.index()
	return st.commit()


static func _cloth_quad(st: SurfaceTool, x0: float, y0: float, x1: float, y1: float,
		color: Color, uv: Rect2) -> void:
	var n := Vector3.BACK
	var pts := [Vector3(x0, y0, 0.0), Vector3(x1, y0, 0.0), Vector3(x1, y1, 0.0),
			Vector3(x0, y0, 0.0), Vector3(x1, y1, 0.0), Vector3(x0, y1, 0.0)]
	var uvs := [Vector2(uv.position.x, uv.position.y),
			Vector2(uv.position.x + uv.size.x, uv.position.y),
			Vector2(uv.position.x + uv.size.x, uv.position.y + uv.size.y),
			Vector2(uv.position.x, uv.position.y),
			Vector2(uv.position.x + uv.size.x, uv.position.y + uv.size.y),
			Vector2(uv.position.x, uv.position.y + uv.size.y)]
	for i in 6:
		st.set_color(color)
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


# ------------------------------------------------------------------ glows -----

## Radial additive glow texture (32x32, nearest sampled -> chunky pixel halo).
static func glow_texture() -> Texture2D:
	var cached: Texture2D = _tex_cache.get("glow")
	if cached != null:
		return cached
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.9
			# quantise to 5 steps so the halo reads as pixel art
			a = floorf(a * 5.0) / 5.0
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["glow"] = tex
	return tex


## Kind: 0 = round ember (8x8), 1 = smoke puff (16x16), 2 = hard spark (8x8).
static func pixel_texture(kind: int = 0) -> Texture2D:
	var key := "px:%d" % kind
	var cached: Texture2D = _tex_cache.get(key)
	if cached != null:
		return cached
	var tex: Texture2D
	if kind == 1:
		tex = _make_smoke_texture()
	elif kind == 2:
		tex = _make_spark_texture()
	else:
		tex = _make_ember_texture()
	_tex_cache[key] = tex
	return tex


static func _make_ember_texture() -> Texture2D:
	var size := 8
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var dx := absf(float(x) - 3.5) / 4.0
			var dy := absf(float(y) - 3.5) / 4.0
			var d := maxf(dx, dy)
			var a := 0.0
			if d < 0.55:
				a = 1.0
			elif d < 0.85:
				a = 0.55
			var c := Color(1.0, 0.72, 0.3, a)
			if d < 0.3:
				c = Color(1.0, 0.95, 0.8, a)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _make_smoke_texture() -> Texture2D:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var dx := (float(x) + 0.5 - 8.0) / 8.0
			var dy := (float(y) + 0.5 - 8.0) / 8.0
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = floorf(a * 4.0) / 4.0 * 0.7
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


static func _make_spark_texture() -> Texture2D:
	var size := 8
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := maxf(absf(float(x) - 3.5), absf(float(y) - 3.5))
			var a := 1.0 if d < 1.0 else (0.45 if d < 2.5 else 0.0)
			img.set_pixel(x, y, Color(1.0, 0.9, 0.6, a))
	return ImageTexture.create_from_image(img)


## Camera-facing additive halo quad (unique material per node so the prop can tint it
## per frame through `tint_glow`).
static func glow_quad(size_m: float, additive: bool = true) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size_m, size_m)
	var m := additive_material(glow_texture(), additive)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	q.material = m
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


static func tint_glow(mi: MeshInstance3D, color: Color) -> void:
	if mi == null:
		return
	var prim := mi.mesh as PrimitiveMesh
	if prim == null:
		return
	var m := prim.material as StandardMaterial3D
	if m != null:
		m.albedo_color = color


## A flat camera-facing billboard quad with a pixel texture (sparks, souls, flames).
static func sprite_quad(width_m: float, height_m: float, tex: Texture2D,
		additive: bool = true) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(width_m, height_m)
	var m := additive_material(tex, additive)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	q.material = m
	var mi := MeshInstance3D.new()
	mi.name = "Sprite"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


static func tint_sprite(mi: MeshInstance3D, color: Color) -> void:
	tint_glow(mi, color)


# -------------------------------------------------------------- particles -----

## A pixel-art particle draw pass: 8x8 ember / 16x16 smoke texture, nearest sampled,
## additive or alpha blended, depth-tested but not depth-writing (the hall occludes it).
static func particle_draw_pass(tex: Texture2D, size_m: float, additive: bool = true) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size_m, size_m)
	var m := additive_material(tex, additive)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = false
	q.material = m
	return q


## Allocate a GPUParticles3D node ready for upward drifting embers/smoke; the caller
## sets the process material tuning and `emitting`/`amount_ratio` afterwards.
static func particles_node(node_name: String, amount: int, lifetime: float,
		tex: Texture2D, size_m: float, additive: bool = true) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = maxi(amount, 1)
	p.lifetime = maxf(lifetime, 0.1)
	p.local_coords = false
	p.draw_pass_1 = particle_draw_pass(tex, size_m, additive)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.visible = true
	return p


static func upward_process_material(spread: float = 12.0) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.4, 0.08, 0.25)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = spread
	pm.initial_velocity_min = 0.22
	pm.initial_velocity_max = 0.62
	pm.gravity = Vector3(0.0, 0.35, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color = Color(1.0, 1.0, 1.0, 1.0)
	return pm


# ------------------------------------------------------------------ helpers ----

static func _has_static(script: Script, method_name: String) -> bool:
	for info in script.get_script_method_list():
		if String(info.get("name", "")) == method_name and int(info.get("flags", 0)) & METHOD_FLAG_STATIC:
			return true
	return false
