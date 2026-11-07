class_name TitleKit
extends RefCounted
## Shared look of the 3D pixel title screen: cached vertex-colour materials, the
## greyscale projection textures, the palette texture for the post-process, the
## primitive recorder / vertex-coloured mesh merger, and the inverted-hull
## outline.
##
## The API is static and state only ever caches resources, so every builder and
## prop script can share the same ShaderMaterial instances (one material per
## look = few draw-call state changes). Vertex colours are written exactly as
## the Palette sRGB values and vertex alpha is an emission mask (1 = fully
## emissive). The Forward+ renderer linearises mesh colours itself, so nothing
## is converted here (same convention as scripts/moba/view/toon_kit.gd).
##
## This file is pure data/tooling: it never touches the scene tree except for
## `mesh_instance()` which returns a detached node and `outline()` which adds the
## hull as a child of the instance it is given.

const LAYOUT := preload("res://scripts/title3d/kit/layout.gd")
const PALETTE := preload("res://scripts/data/palette.gd")
const SURFACE_SHADER := preload("res://assets/shaders/title3d/surface.gdshader")
const HULL_SHADER := preload("res://assets/shaders/moba/outline_hull.gdshader")

## Shape flags. Emission is carried in vertex alpha, so these cost no material;
## they only pick the cached material variant (emission gain).
const EMISSIVE := 1
const HALF_EMISSIVE := 2
const NO_OUTLINE := 4

const TEX_SIZE := 32
const OUTLINE_COLOR := Color("#120d0f")

## Colours appended to the project's 16 for the optional palette lock: soot and
## bone for the hall, forge ramp for the mouth/lava, cold ramp for the windows.
const EXTRA_PALETTE := [
	Color("#0d0a10"), Color("#1b1417"), Color("#2a2224"), Color("#3d3236"),
	Color("#6b5c52"), Color("#9a8877"), Color("#c9b8a2"), Color("#efe3cc"),
	Color("#5c2a12"), Color("#8f3d16"), Color("#c9561c"), Color("#f07a24"),
	Color("#ffb04a"), Color("#ffe08a"),
	Color("#16303a"), Color("#244a56"), Color("#3d7280"), Color("#79a8b0"),
	Color("#1d2b3a"), Color("#2d4257"), Color("#47688a"),
]

## Ambient light of every title surface material (sRGB colour + energy). The
## shader adds it once from the directional branch; the Environment's own
## ambient must stay at zero (see surface.gdshader).
static var ambient_color := PALETTE.TEAL
static var ambient_energy := 1.2

## Set to false to hide every outline hull (perf / test toggles).
static var outlines_enabled := true

static var _materials: Dictionary = {}
static var _textured: Dictionary = {}
static var _unshaded: Dictionary = {}
static var _hull: ShaderMaterial
static var _unshaded_shaders: Dictionary = {}
static var _textures: Dictionary = {}
static var _palette: ImageTexture

const UNSHADED_CODE := """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D albedo_tex : filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a * tint.a;
}
"""

const UNSHADED_ADD_CODE := """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D albedo_tex : filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * tint.rgb * tint.a * tex.a;
}
"""


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

## Shared vertex-colour material. Flags only pick the emission-gain variant:
## EMISSIVE is the hot (forge/window) look, HALF_EMISSIVE the warm accents.
static func mat(flags := 0) -> ShaderMaterial:
	var key := flags & (EMISSIVE | HALF_EMISSIVE)
	if not _materials.has(key):
		var material := _new_surface()
		var gain := 1.0
		if key & EMISSIVE:
			gain = 1.6
		elif key & HALF_EMISSIVE:
			gain = 1.25
		material.set_shader_parameter("emission_gain", gain)
		_materials[key] = material
	return _materials[key]


## Surface material with the optional world-axis-projected greyscale texture.
static func textured(tex: Texture2D, texels_per_unit := 16.0) -> ShaderMaterial:
	if tex == null:
		return mat(0)
	var key := "%d@%.2f" % [tex.get_instance_id(), texels_per_unit]
	if not _textured.has(key):
		var material := _new_surface()
		material.set_shader_parameter("use_texture", true)
		material.set_shader_parameter("albedo_tex", tex)
		material.set_shader_parameter("texels_per_unit", texels_per_unit)
		material.set_shader_parameter("tex_size", float(TEX_SIZE))
		_textured[key] = material
	return _textured[key]


static func _new_surface() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("tex_size", float(TEX_SIZE))
	material.set_shader_parameter("use_texture", false)
	_apply_ambient(material)
	return material


## Unshaded textured material for glow cards / decals. `additive` switches to
## additive blending (the blend mode is part of the shader, so both variants
## have their own cached Shader).
static func unshaded(tex: Texture2D, additive := false) -> ShaderMaterial:
	if tex == null:
		return null
	var key := "%d@%d" % [tex.get_instance_id(), 1 if additive else 0]
	if not _unshaded.has(key):
		var material := ShaderMaterial.new()
		material.shader = _unshaded_shader(additive)
		material.set_shader_parameter("albedo_tex", tex)
		_unshaded[key] = material
	return _unshaded[key]


static func _unshaded_shader(additive: bool) -> Shader:
	var key := 1 if additive else 0
	if not _unshaded_shaders.has(key):
		var shader := Shader.new()
		shader.code = UNSHADED_ADD_CODE if additive else UNSHADED_CODE
		_unshaded_shaders[key] = shader
	return _unshaded_shaders[key]


## Re-tint the ambient term on every cached surface material. `color` is sRGB;
## the shader takes linear values, so it is converted here.
static func set_ambient(color: Color, energy: float) -> void:
	ambient_color = color
	ambient_energy = energy
	for material: ShaderMaterial in _materials.values():
		_apply_ambient(material)
	for material: ShaderMaterial in _textured.values():
		_apply_ambient(material)


static func _apply_ambient(material: ShaderMaterial) -> void:
	var linear := ambient_color.srgb_to_linear()
	material.set_shader_parameter("ambient_light", Vector3(linear.r, linear.g, linear.b) * ambient_energy)


## ShaderMaterial for the inverted hull used by `outline()`.
static func hull_material(color: Color = OUTLINE_COLOR) -> ShaderMaterial:
	if _hull == null:
		_hull = ShaderMaterial.new()
		_hull.shader = HULL_SHADER
		_hull.set_shader_parameter("outline_color", color)
	return _hull


# ---------------------------------------------------------------------------
# Textures
# ---------------------------------------------------------------------------

## Grey multipliers (0.55..1.0) for the projection look. Fixed seeds, so every
## run on every machine paints identical pixels. Presets: "stone", "brick",
## "plate", "grate".
static func luminance_texture(preset: String) -> ImageTexture:
	if _textures.has(preset):
		return _textures[preset]
	var img := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(preset)
	match preset:
		"brick":
			_paint_brick(img, rng)
		"plate":
			_paint_plate(img, rng)
		"grate":
			_paint_grate(img, rng)
		_:
			_paint_stone(img, rng)
	var tex := ImageTexture.create_from_image(img)
	_textures[preset] = tex
	return tex


static func palette_colors() -> PackedColorArray:
	var colors := PackedColorArray([
		PALETTE.VOID, PALETTE.SHADOW, PALETTE.IRON, PALETTE.CONCRETE,
		PALETTE.PALE, PALETTE.RUST_SHADOW, PALETTE.RUST_DARK, PALETTE.RUST_MID,
		PALETTE.RUST_LIGHT, PALETTE.EMBER_ASH, PALETTE.TOXIC_DARK, PALETTE.TOXIC,
		PALETTE.EMBER, PALETTE.TEAL_DEEP, PALETTE.TEAL, PALETTE.FOG,
	])
	for color in EXTRA_PALETTE:
		colors.append(color)
	return colors


## One-row palette texture for the post-process palette lock.
static func palette_texture() -> ImageTexture:
	if _palette == null:
		var colors := palette_colors()
		var img := Image.create_empty(colors.size(), 1, false, Image.FORMAT_RGBA8)
		for i in colors.size():
			img.set_pixel(i, 0, colors[i])
		_palette = ImageTexture.create_from_image(img)
	return _palette


static func _paint_stone(img: Image, rng: RandomNumberGenerator) -> void:
	for row in 4:
		var offset := (row * 5) & 7
		var shades := PackedFloat32Array()
		for i in 4:
			shades.append(rng.randf_range(0.80, 1.0))
		for yy in 8:
			for x in TEX_SIZE:
				var lx := posmod(x - offset, TEX_SIZE)
				var v := shades[lx >> 3]
				var cx := lx & 7
				if yy == 7 or cx == 7:
					v = 0.58
				elif yy == 0 or cx == 0:
					v = minf(1.0, v + 0.07)
				v = clampf(v + rng.randf_range(-0.03, 0.03), 0.0, 1.0)
				img.set_pixel(x, row * 8 + yy, Color(v, v, v))


static func _paint_brick(img: Image, rng: RandomNumberGenerator) -> void:
	for row in 8:
		var offset := 0 if row % 2 == 0 else 4
		var shades := PackedFloat32Array()
		for i in 4:
			shades.append(rng.randf_range(0.76, 1.0))
		for yy in 4:
			for x in TEX_SIZE:
				var lx := posmod(x + offset, TEX_SIZE)
				var v := shades[lx >> 3]
				if yy == 3 or (lx & 7) == 7:
					v = 0.55
				elif yy == 0:
					v = minf(1.0, v + 0.06)
				v = clampf(v + rng.randf_range(-0.025, 0.025), 0.0, 1.0)
				img.set_pixel(x, row * 4 + yy, Color(v, v, v))


static func _paint_plate(img: Image, rng: RandomNumberGenerator) -> void:
	var shades := PackedFloat32Array()
	for i in 4:
		shades.append(rng.randf_range(0.86, 0.96))
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := shades[((x >> 3) + (y >> 3) * 3) & 3]
			var rx := x & 7
			var ry := y & 7
			if rx == 0 or ry == 0:
				v = 0.62
			elif rx == 3 and ry == 3:
				v = 0.74
			elif (rx == 4 and ry == 3) or (rx == 2 and ry == 4):
				v = 1.0
			img.set_pixel(x, y, Color(v, v, v))


static func _paint_grate(img: Image, rng: RandomNumberGenerator) -> void:
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := 0.78 + rng.randf_range(-0.03, 0.03)
			if (x & 3) == 0 or (y & 7) == 0:
				v = 0.52
			elif (x & 3) == 1:
				v = 0.92
			img.set_pixel(x, y, Color(v, v, v))


# ---------------------------------------------------------------------------
# Primitive parts and merging
# ---------------------------------------------------------------------------

## One box part. `emissive` is 0..1 (1 = fully emissive).
static func part_box(size: Vector3, xform: Transform3D, color: Color, emissive := 0.0) -> Dictionary:
	return {
		"kind": "box",
		"size": size,
		"xform": xform,
		"color": color,
		"emissive": clampf(emissive, 0.0, 1.0),
	}


## One cylinder part (flat-shaded facets, `sides` from 3 up).
static func part_cyl(radius: float, height: float, sides: int, xform: Transform3D, color: Color, emissive := 0.0) -> Dictionary:
	return {
		"kind": "cyl",
		"radius": radius,
		"height": height,
		"sides": maxi(3, sides),
		"xform": xform,
		"color": color,
		"emissive": clampf(emissive, 0.0, 1.0),
	}


## One pre-built ArrayMesh part (e.g. a TitleShapes gear). Its baked vertex
## colours are preserved; only the alpha channel is overwritten with the
## emission mask.
static func part_mesh(mesh: ArrayMesh, xform: Transform3D, emissive := 0.0) -> Dictionary:
	return {
		"kind": "mesh",
		"mesh": mesh,
		"xform": xform,
		"emissive": clampf(emissive, 0.0, 1.0),
	}


## Merge recorded parts into one vertex-coloured ArrayMesh (one draw call).
## UVs are dropped on purpose: the surface shader projects the greyscale texture
## from world space. Parts with no colour fall back to white.
static func merge(parts: Array) -> ArrayMesh:
	var builder := MeshBuilder.new()
	for part in parts:
		if not part is Dictionary:
			continue
		var xform: Transform3D = part.get("xform", Transform3D.IDENTITY)
		var emissive: float = part.get("emissive", 0.0)
		match String(part.get("kind", "")):
			"box":
				var box := BoxMesh.new()
				box.size = part.get("size", Vector3.ONE)
				builder.add(box.get_mesh_arrays(), xform, _part_color(part, emissive), false)
			"cyl":
				var cyl := CylinderMesh.new()
				var radius: float = absf(part.get("radius", 0.5))
				cyl.top_radius = radius
				cyl.bottom_radius = radius
				cyl.height = maxf(absf(part.get("height", 1.0)), 0.001)
				cyl.radial_segments = maxi(3, int(part.get("sides", 8)))
				cyl.rings = 0
				builder.add(cyl.get_mesh_arrays(), xform, _part_color(part, emissive), true)
			"mesh":
				var mesh: ArrayMesh = part.get("mesh", null)
				if mesh != null:
					builder.add_mesh(mesh, xform, 1.0 - emissive)
	return builder.commit()


static func _part_color(part: Dictionary, emissive: float) -> Color:
	var color: Color = part.get("color", Color.WHITE)
	return Color(color.r, color.g, color.b, 1.0 - emissive)


## Convenience transform: euler rotation in degrees plus an optional scale.
static func xform(pos: Vector3, rot_deg := Vector3.ZERO, scale_v := Vector3.ONE) -> Transform3D:
	var basis := Basis.from_euler(Vector3(
			deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	if scale_v != Vector3.ONE:
		basis = basis.scaled(scale_v)
	return Transform3D(basis, pos)


## Detached MeshInstance3D; `node_name` is applied only when non-empty.
static func mesh_instance(mesh: ArrayMesh, material: Material, at: Transform3D, node_name := "") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if node_name != "":
		instance.name = node_name
	instance.mesh = mesh
	if material != null:
		instance.material_override = material
	instance.transform = at
	return instance


# ---------------------------------------------------------------------------
# Outlines
# ---------------------------------------------------------------------------

## Add (or rebuild) the inverted-hull outline of `instance`. `width_px` is in
## render texels of the 640x360 title target: the hull is pushed outward along
## the welded vertex normals by `width_px * WORLD_PER_TEXEL`, so vertices that
## share a position always move together and the shell stays watertight (no
## corner cracks even on hard-edged merged meshes). Uses the arena hull shader
## (unshaded, cull_front); it is plain Forward+ and needs no flip tricks.
static func outline(instance: MeshInstance3D, width_px: float) -> void:
	if instance == null or instance.mesh == null or width_px <= 0.0 or not outlines_enabled:
		return
	if instance.get_meta("title_outline_width", -1.0) == width_px:
		return
	var hull_mesh := hull_mesh_for(instance.mesh, width_px * LAYOUT.WORLD_PER_TEXEL)
	if hull_mesh == null or hull_mesh.get_surface_count() == 0:
		return
	var hull: MeshInstance3D = instance.get_node_or_null("Outline")
	if hull == null:
		hull = MeshInstance3D.new()
		hull.name = "Outline"
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hull.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.add_child(hull)
	hull.mesh = hull_mesh
	hull.material_override = hull_material()
	instance.set_meta("title_outline_width", width_px)


## Welded normal-displaced copy of `mesh`, grown by `delta` metres.
static func hull_mesh_for(mesh: ArrayMesh, delta: float) -> ArrayMesh:
	if mesh == null or delta <= 0.0:
		return null
	var builder := MeshBuilder.new()
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
		# Weld by position so shared corners move as one: watertight shell.
		var sums: Dictionary = {}
		var keys: Array = []
		keys.resize(verts.size())
		for i in verts.size():
			var key := _weld_key(verts[i])
			keys[i] = key
			var normal := normals[i] if normals.size() == verts.size() else Vector3.UP
			if sums.has(key):
				sums[key] = sums[key] + normal
			else:
				sums[key] = normal
		var hull_verts := PackedVector3Array()
		var hull_normals := PackedVector3Array()
		hull_verts.resize(verts.size())
		hull_normals.resize(verts.size())
		for i in verts.size():
			var normal: Vector3 = sums[keys[i]]
			if normal.length_squared() < 1e-10:
				normal = normals[i] if normals.size() == verts.size() else Vector3.UP
			normal = normal.normalized()
			hull_verts[i] = verts[i] + normal * delta
			hull_normals[i] = normal
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in hull_verts.size():
				indices.append(i)
		var start := builder.verts.size()
		builder.verts.append_array(hull_verts)
		builder.normals.append_array(hull_normals)
		for i in indices.size():
			builder.indices.append(start + indices[i])
		if builder.colors.size() < builder.verts.size():
			builder.colors.resize(builder.verts.size())
	return builder.commit()


static func _weld_key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0))


# ---------------------------------------------------------------------------
# Array accumulation
# ---------------------------------------------------------------------------

## Accumulates transformed primitive arrays into one flat-shaded surface.
## Non-uniform transforms get proper inverse-transpose normals.
class MeshBuilder extends RefCounted:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()


	func is_empty() -> bool:
		return verts.is_empty()


	func add(arrays: Array, xform: Transform3D, color: Color, flat: bool) -> void:
		if arrays.is_empty():
			return
		var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if src_v.is_empty():
			return
		var src_n := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			src_n = arrays[Mesh.ARRAY_NORMAL]
		var src_i := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			src_i = arrays[Mesh.ARRAY_INDEX]
		if src_i.is_empty():
			for k in src_v.size():
				src_i.append(k)
		var normal_matrix := xform.basis.inverse().transposed()
		if not flat:
			var start := verts.size()
			for k in src_v.size():
				verts.append(xform * src_v[k])
				normals.append((normal_matrix * src_n[k]).normalized())
				colors.append(color)
			for k in src_i.size():
				indices.append(start + src_i[k])
			return
		for t in range(0, src_i.size() - 2, 3):
			var a := xform * src_v[src_i[t]]
			var b := xform * src_v[src_i[t + 1]]
			var c := xform * src_v[src_i[t + 2]]
			var cross := (b - a).cross(c - a)
			if cross.length_squared() < 1e-12:
				continue
			var normal := cross.normalized()
			if src_n.size() == src_v.size():
				var hint := normal_matrix * (src_n[src_i[t]] + src_n[src_i[t + 1]] + src_n[src_i[t + 2]])
				if normal.dot(hint) < 0.0:
					normal = -normal
			var start := verts.size()
			verts.append(a)
			verts.append(b)
			verts.append(c)
			for j in 3:
				normals.append(normal)
				colors.append(color)
				indices.append(start + j)


	## Append an ArrayMesh preserving its baked vertex colours; `alpha` is forced
	## on every vertex (emission mask) while RGB is kept.
	func add_mesh(mesh: ArrayMesh, xform: Transform3D, alpha: float) -> void:
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if src_v.is_empty():
				continue
			var src_n := PackedVector3Array()
			if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
				src_n = arrays[Mesh.ARRAY_NORMAL]
			var src_c := PackedColorArray()
			if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
				src_c = arrays[Mesh.ARRAY_COLOR]
			var src_i := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				src_i = arrays[Mesh.ARRAY_INDEX]
			var normal_matrix := xform.basis.inverse().transposed()
			var start := verts.size()
			for k in src_v.size():
				verts.append(xform * src_v[k])
				if src_n.size() == src_v.size():
					normals.append((normal_matrix * src_n[k]).normalized())
				else:
					normals.append(Vector3.UP)
				var color := src_c[k] if src_c.size() == src_v.size() else Color.WHITE
				colors.append(Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0)))
			if src_i.is_empty():
				for k in src_v.size():
					indices.append(start + k)
			else:
				for k in src_i.size():
					indices.append(start + src_i[k])


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
