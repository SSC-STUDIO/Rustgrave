extends RefCounted
## Shared look of the 3D pixel mode: cached materials, procedural luminance
## textures, the quantisation palette, and the merger that turns primitive
## shapes into one vertex-coloured mesh (one draw call per rigid part).

const TOON_SHADER := preload("res://assets/shaders/moba/toon.gdshader")
const HULL_SHADER := preload("res://assets/shaders/moba/outline_hull.gdshader")
const BLOB_SHADER := preload("res://assets/shaders/moba/blob_shadow.gdshader")
const LAVA_SHADER := preload("res://assets/shaders/moba/lava.gdshader")
const POOL_SHADER := preload("res://assets/shaders/moba/light_pool.gdshader")

## Shape flags. Emission is carried in vertex alpha, so these cost no material.
const EMISSIVE := 1
const HALF_EMISSIVE := 2
const NO_OUTLINE := 4

const TEX_SIZE := 32
const OUTLINE_COLOR := Color("#120d0f")

const TEAM_BLUE := Color("#4f7db8")
const TEAM_BLUE_DARK := Color("#2f4c7a")
const TEAM_BLUE_LIGHT := Color("#8db6e8")
const TEAM_RED := Color("#b23a2e")
const TEAM_RED_DARK := Color("#6e1f1f")
const TEAM_RED_LIGHT := Color("#e8735a")

## Added to the project's 16 colours for the optional palette lock: team ramps,
## verdigris foliage, warm stone, earth (lit and shaded ground), highlights.
const EXTRA_PALETTE: Array[Color] = [
	Color("#1c2a44"), Color("#2f4c7a"), Color("#4f7db8"), Color("#8db6e8"),
	Color("#3a1214"), Color("#6e1f1f"), Color("#b23a2e"), Color("#e8735a"),
	Color("#1f3328"), Color("#2f5241"), Color("#4c7a5e"), Color("#7fa88a"),
	Color("#2a2420"), Color("#4a3e36"), Color("#6e6258"), Color("#a89a8a"),
	Color("#3f3426"), Color("#61583a"), Color("#6f5a3e"), Color("#937f63"),
	Color("#f2e8da"), Color("#ffe08a"),
]

## Ambient light of every toon material. The shader adds it with the sun, so
## the Environment's own ambient must stay at zero (see toon.gdshader).
static var ambient_color := Palette.TEAL
static var ambient_energy := 1.4

static var _toon: ShaderMaterial
static var _flame: ShaderMaterial
static var _lava: ShaderMaterial
static var _blob: ShaderMaterial
static var _blob_mesh: PlaneMesh
static var _pools: Dictionary = {}
static var _textured: Dictionary = {}
static var _hulls: Dictionary = {}
static var _textures: Dictionary = {}


static func team_color(team: int) -> Color:
	return TEAM_BLUE if team == 0 else TEAM_RED


static func team_dark(team: int) -> Color:
	return TEAM_BLUE_DARK if team == 0 else TEAM_RED_DARK


static func team_light(team: int) -> Color:
	return TEAM_BLUE_LIGHT if team == 0 else TEAM_RED_LIGHT


static func set_ambient(color: Color, energy: float) -> void:
	ambient_color = color
	ambient_energy = energy
	var materials: Array = _textured.values()
	materials.append_array([_toon, _flame])
	for mat: ShaderMaterial in materials:
		if mat != null:
			_apply_ambient(mat)


static func toon_material() -> ShaderMaterial:
	if _toon == null:
		_toon = _new_toon()
	return _toon


static func flame_material() -> ShaderMaterial:
	if _flame == null:
		_flame = _new_toon()
		_flame.set_shader_parameter("flicker", 0.55)
		_flame.set_shader_parameter("emission_gain", 1.2)
	return _flame


static func lava_material() -> ShaderMaterial:
	if _lava == null:
		_lava = ShaderMaterial.new()
		_lava.shader = LAVA_SHADER
	return _lava


static func textured_material(texture_name: String, texels_per_unit: float = 16.0) -> ShaderMaterial:
	var key := "%s@%.2f" % [texture_name, texels_per_unit]
	if not _textured.has(key):
		var mat := _new_toon()
		mat.set_shader_parameter("use_texture", true)
		mat.set_shader_parameter("albedo_tex", luminance_texture(texture_name))
		mat.set_shader_parameter("texels_per_unit", texels_per_unit)
		mat.set_shader_parameter("tex_size", float(TEX_SIZE))
		_textured[key] = mat
	return _textured[key]


static func _new_toon() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	_apply_ambient(mat)
	return mat


static func _apply_ambient(mat: ShaderMaterial) -> void:
	var linear := ambient_color.srgb_to_linear()
	mat.set_shader_parameter("ambient_light", Vector3(linear.r, linear.g, linear.b) * ambient_energy)


static func hull_material(color: Color = OUTLINE_COLOR) -> ShaderMaterial:
	var key := color.to_html()
	if not _hulls.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = HULL_SHADER
		mat.set_shader_parameter("outline_color", color)
		_hulls[key] = mat
	return _hulls[key]


static func blob_shadow(radius: float) -> MeshInstance3D:
	if _blob == null:
		_blob = ShaderMaterial.new()
		_blob.shader = BLOB_SHADER
	return _ground_decal("BlobShadow", radius, _blob)


## Stepped additive glow on the ground; stands in for an omni light (see
## light_pool.gdshader). The inner ring adds `color * strength` on screen.
static func light_pool(radius: float, color: Color, strength: float, flicker: float = 0.0) -> MeshInstance3D:
	var key := "%s@%.3f@%.2f" % [color.to_html(), strength, flicker]
	if not _pools.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = POOL_SHADER
		mat.set_shader_parameter("glow", Vector3(color.r, color.g, color.b) * strength)
		mat.set_shader_parameter("flicker", flicker)
		_pools[key] = mat
	return _ground_decal("LightPool", radius, _pools[key])


static func _ground_decal(decal_name: String, radius: float, material: Material) -> MeshInstance3D:
	if _blob_mesh == null:
		_blob_mesh = PlaneMesh.new()
		_blob_mesh.size = Vector2.ONE
	var decal := MeshInstance3D.new()
	decal.name = decal_name
	decal.mesh = _blob_mesh
	decal.material_override = material
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	decal.position = Vector3(0.0, 0.05, 0.0)
	return decal


## Grey multipliers (0.55..1.0) tinted by vertex colour; fixed seeds so every run
## and every machine paints the same pixels.
static func luminance_texture(texture_name: String) -> ImageTexture:
	if _textures.has(texture_name):
		return _textures[texture_name]
	var img := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(texture_name)
	match texture_name:
		"flagstone":
			_paint_flagstone(img, rng)
		"brick":
			_paint_brick(img, rng)
		_:
			_paint_dirt(img, rng)
	var tex := ImageTexture.create_from_image(img)
	_textures[texture_name] = tex
	return tex


static func palette_colors() -> PackedColorArray:
	var colors := PackedColorArray([
		Palette.VOID, Palette.SHADOW, Palette.IRON, Palette.CONCRETE,
		Palette.PALE, Palette.RUST_SHADOW, Palette.RUST_DARK, Palette.RUST_MID,
		Palette.RUST_LIGHT, Palette.EMBER_ASH, Palette.TOXIC_DARK, Palette.TOXIC,
		Palette.EMBER, Palette.TEAL_DEEP, Palette.TEAL, Palette.FOG,
	])
	for color in EXTRA_PALETTE:
		colors.append(color)
	return colors


static func palette_texture() -> ImageTexture:
	var colors := palette_colors()
	var img := Image.create_empty(colors.size(), 1, false, Image.FORMAT_RGBA8)
	for i in colors.size():
		img.set_pixel(i, 0, colors[i])
	return ImageTexture.create_from_image(img)


## Vertex colours stay sRGB: the renderer linearises mesh colours itself, so
## converting here would darken and oversaturate everything a second time.
static func vertex_color(color: Color, flags: int) -> Color:
	var out := color
	if flags & EMISSIVE:
		out.a = 0.0
	elif flags & HALF_EMISSIVE:
		out.a = 0.5
	else:
		out.a = 1.0
	return out


## Mesh arrays for one recorded shape, grown by `grow` metres on every side
## (the inverted hull uses the grown twin). Built from Godot primitives so the
## winding is always the engine's own.
static func shape_arrays(shape: Dictionary, grow: float) -> Array:
	var kind: String = shape["kind"]
	match kind:
		"box":
			var box := BoxMesh.new()
			var box_size: Vector3 = shape["size"]
			box.size = box_size + Vector3.ONE * (grow * 2.0)
			return box.get_mesh_arrays()
		"cylinder":
			var sides: int = shape["sides"]
			var radial_grow := grow / cos(PI / float(sides))
			var top: float = shape["top"]
			var bottom: float = shape["bottom"]
			var height: float = shape["height"]
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = top + radial_grow if top > 0.0 else 0.0
			cylinder.bottom_radius = bottom + radial_grow if bottom > 0.0 else 0.0
			cylinder.height = height + grow * 2.0
			cylinder.radial_segments = sides
			cylinder.rings = 0
			return cylinder.get_mesh_arrays()
		"sphere":
			var segments: int = shape["segments"]
			var rings: int = shape["rings"]
			var radius: float = shape["radius"]
			var sphere_height: float = shape["height"]
			var sphere := SphereMesh.new()
			sphere.radius = radius + grow / cos(PI / float(segments))
			sphere.height = sphere_height + grow * 2.0
			sphere.radial_segments = segments
			sphere.rings = rings
			return sphere.get_mesh_arrays()
		"prism":
			var prism := PrismMesh.new()
			var prism_size: Vector3 = shape["size"]
			prism.size = prism_size + Vector3(grow * 2.0, grow * 3.0, grow * 2.0)
			return prism.get_mesh_arrays()
	return []


static func _paint_flagstone(img: Image, rng: RandomNumberGenerator) -> void:
	for row in 4:
		var offset := (row * 5) & 7
		var shades := PackedFloat32Array()
		for i in 4:
			shades.append(rng.randf_range(0.8, 1.0))
		for yy in 8:
			for x in TEX_SIZE:
				var lx := posmod(x - offset, TEX_SIZE)
				var v := shades[lx >> 3]
				var cx := lx & 7
				if yy == 7 or cx == 7:
					v = 0.58
				elif yy == 0 or cx == 0:
					v = minf(1.0, v + 0.07)
				v = clampf(v + rng.randf_range(-0.025, 0.025), 0.0, 1.0)
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
				v = clampf(v + rng.randf_range(-0.02, 0.02), 0.0, 1.0)
				img.set_pixel(x, row * 4 + yy, Color(v, v, v))


static func _paint_dirt(img: Image, rng: RandomNumberGenerator) -> void:
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := 0.88 + rng.randf_range(-0.04, 0.04)
			var roll := rng.randf()
			if roll < 0.06:
				v = 0.72
			elif roll < 0.09:
				v = 1.0
			img.set_pixel(x, y, Color(v, v, v))


## Accumulates transformed primitive arrays into one surface. `flat` re-splits
## triangles with face normals so round primitives shade as facets.
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
		var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var src_i := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			src_i = arrays[Mesh.ARRAY_INDEX]
		if src_i.is_empty():
			for k in src_v.size():
				src_i.append(k)
		var rot := xform.basis
		if not flat:
			var start := verts.size()
			for k in src_v.size():
				verts.append(xform * src_v[k])
				normals.append((rot * src_n[k]).normalized())
				colors.append(color)
			for k in src_i.size():
				indices.append(start + src_i[k])
			return
		for t in range(0, src_i.size() - 2, 3):
			var a := xform * src_v[src_i[t]]
			var b := xform * src_v[src_i[t + 1]]
			var c := xform * src_v[src_i[t + 2]]
			var n := (b - a).cross(c - a)
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			var hint := rot * (src_n[src_i[t]] + src_n[src_i[t + 1]] + src_n[src_i[t + 2]])
			if n.dot(hint) < 0.0:
				n = -n
			var start := verts.size()
			verts.append(a)
			verts.append(b)
			verts.append(c)
			for j in 3:
				normals.append(n)
				colors.append(color)
				indices.append(start + j)


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
