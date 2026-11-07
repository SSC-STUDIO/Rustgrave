extends TestCase
## Title 3D kit contract tests.
##
## Covers the shared coordinate layout (layout.gd), the deterministic shape
## generators (shapes.gd), the vertex-colour merger / cached materials / outline
## (title_kit.gd) and the headless build budget of the three geometry builders.
## Everything runs headless: no rendering, no window, no screenshots.

const LAYOUT := preload("res://scripts/title3d/kit/layout.gd")
const KIT := preload("res://scripts/title3d/kit/title_kit.gd")
const SHAPES := preload("res://scripts/title3d/kit/shapes.gd")
const HALL := preload("res://scripts/title3d/kit/hall_builder.gd")
const BRIDGE := preload("res://scripts/title3d/kit/bridge_builder.gd")
const FURNACE := preload("res://scripts/title3d/kit/furnace_builder.gd")
const PALETTE := preload("res://scripts/data/palette.gd")

const MAX_MESH_INSTANCES := 120

var _reported_scale := false


# ---------------------------------------------------------------------------
# layout.gd: the shared coordinate contract stays self-consistent
# ---------------------------------------------------------------------------

func test_layout_contract() -> void:
	# Axes: bridge top is the deck plane the knight stands on, at the origin.
	almost(LAYOUT.bridge_top(), LAYOUT.DECK_Y, 0.0001, "bridge top face sits on DECK_Y")
	eq(LAYOUT.BRIDGE_TOP_Y, LAYOUT.DECK_Y, "bridge slab top / deck contract")
	eq(LAYOUT.KNIGHT_POS, Vector3.ZERO, "knight feet are the hero origin")
	ok(LAYOUT.KNIGHT_HEIGHT > 1.0 and LAYOUT.KNIGHT_HEIGHT < 3.0, "knight height is human scale")
	# Pixel / camera contract.
	almost(LAYOUT.world_per_texel(), LAYOUT.VIEW_HEIGHT / float(LAYOUT.RENDER_TEXEL_HEIGHT), 1e-6,
			"one texel is VIEW_HEIGHT / 360 m on the focus plane")
	almost(LAYOUT.camera_distance(),
			(LAYOUT.VIEW_HEIGHT * 0.5) / tan(deg_to_rad(LAYOUT.CAMERA_FOV * 0.5)), 0.01,
			"camera distance frames VIEW_HEIGHT at CAMERA_FOV")
	ok(LAYOUT.world_per_texel() > 0.0)
	# Hall box.
	almost(LAYOUT.HALL_W, LAYOUT.HALL_HALF_W * 2.0, 0.0001)
	almost(LAYOUT.HALL_D, LAYOUT.HALL_FRONT_Z - LAYOUT.HALL_BACK_Z, 0.0001)
	almost(LAYOUT.SKYLIGHT_CENTER.y, LAYOUT.ROOF_Y, 0.0001)
	ok(LAYOUT.ROOF_Y <= LAYOUT.HALL_H)
	# The forge mouth is inside the hall volume (and on the forge's +Z face).
	ok(LAYOUT.in_hall(LAYOUT.FORGE_MOUTH), "forge mouth is inside the hall")
	ok(LAYOUT.in_hall(LAYOUT.SKYLIGHT_CENTER), "skylight is inside the hall")
	ok(LAYOUT.in_hall(LAYOUT.KNIGHT_POS), "knight is inside the hall")
	ok(LAYOUT.in_hall(LAYOUT.GEAR_BIG), "big gear is inside the hall")
	ok(LAYOUT.in_hall(LAYOUT.GEAR_SMALL), "small gear is inside the hall")
	ok(not LAYOUT.in_hall(Vector3(0.0, 0.0, 100.0)), "far outside the hall is rejected")
	almost(LAYOUT.FORGE_MOUTH.z, LAYOUT.FORGE_CENTER.z + LAYOUT.FORGE_SIZE.z * 0.5, 0.15,
			"forge mouth sits on the camera-facing forge face")
	# The mouth opening has to fit in the forge face.
	ok(LAYOUT.FORGE_MOUTH_SIZE.x < LAYOUT.FORGE_SIZE.x)
	ok(LAYOUT.FORGE_MOUTH_SIZE.y < LAYOUT.FORGE_SIZE.y)
	# The light shaft has two different endpoints and travels downward.
	ok(LAYOUT.BEAM_FROM != LAYOUT.BEAM_TO, "light shaft endpoints differ")
	ok(LAYOUT.BEAM_FROM.distance_to(LAYOUT.BEAM_TO) > 8.0, "light shaft has real length")
	ok(LAYOUT.BEAM_TO.y < LAYOUT.BEAM_FROM.y, "light shaft travels down")
	ok(LAYOUT.in_hall(LAYOUT.BEAM_FROM) and LAYOUT.in_hall(LAYOUT.BEAM_TO),
			"light shaft endpoints are inside the hall")
	# Sun direction and its euler rotation describe the same light.
	var sun_basis := Basis.from_euler(Vector3(
			deg_to_rad(LAYOUT.SUN_ROTATION_DEG.x),
			deg_to_rad(LAYOUT.SUN_ROTATION_DEG.y),
			deg_to_rad(LAYOUT.SUN_ROTATION_DEG.z)))
	var sun_forward := sun_basis * Vector3(0.0, 0.0, -1.0)
	ok(sun_forward.distance_to(LAYOUT.SUN_DIRECTION) < 0.02,
			"SUN_ROTATION_DEG forward axis matches SUN_DIRECTION (got %s)" % str(sun_forward))
	ok(LAYOUT.SUN_DIRECTION.z > 0.0, "sun travels toward the camera (backlit windows)")
	# 14 lanterns in two rows of 7: unique, ordered, above the knight, clear rows.
	var positions := LAYOUT.lantern_positions()
	var anchors := LAYOUT.lantern_anchors()
	eq(positions.size(), LAYOUT.LANTERN_COUNT, "lantern_positions() returns 14")
	eq(anchors.size(), LAYOUT.LANTERN_COUNT, "lantern_anchors() returns 14")
	var unique := {}
	for p in positions:
		unique[p] = true
	eq(unique.size(), LAYOUT.LANTERN_COUNT, "no two lanterns share a position")
	ok(positions[0].z > positions[LAYOUT.LANTERN_PER_ROW].z,
			"front row is closer to the camera than the back row")
	for i in LAYOUT.LANTERN_COUNT:
		ok(LAYOUT.in_hall(positions[i]), "lantern %d hangs inside the hall" % i)
		ok(anchors[i].y > positions[i].y, "lantern %d hangs below its anchor" % i)
		ok(positions[i].y > LAYOUT.KNIGHT_HEIGHT * 2.0, "lantern %d clears the knight" % i)
	almost(LAYOUT.LANTERN_TOP_Y, LAYOUT.lantern_anchors()[0].y, 0.0001)
	almost(LAYOUT.LANTERN_HANG_Y, positions[0].y, 0.0001)
	# Gears: inside the hall and meshing (centre distance about the radius sum).
	ok(LAYOUT.GEAR_BIG_RADIUS * 2.0 < LAYOUT.HALL_W, "big gear fits the hall width")
	ok(LAYOUT.GEAR_SMALL_RADIUS < LAYOUT.GEAR_BIG_RADIUS)
	var gear_gap := LAYOUT.GEAR_BIG.distance_to(LAYOUT.GEAR_SMALL)
	almost(gear_gap, LAYOUT.GEAR_BIG_RADIUS + LAYOUT.GEAR_SMALL_RADIUS, 0.30,
			"gear pair centre distance matches the radius sum")
	# Bridge: spans the chasm exactly at deck height.
	almost(LAYOUT.BRIDGE_HALF_X, LAYOUT.PIT_HALF_X, 0.0001, "bridge spans the chasm exactly")
	ok(LAYOUT.BRIDGE_SIZE.z > 4.0, "bridge deck is deep enough for the stage")
	ok(LAYOUT.RAIL_HEIGHT > 0.5)
	var brazier_positions := LAYOUT.braziers()
	eq(brazier_positions.size(), 2)
	for b in brazier_positions:
		almost(b.y, LAYOUT.DECK_Y, 0.0001, "braziers stand on the deck")
		ok(absf(b.x) < LAYOUT.BRIDGE_HALF_X and absf(b.z) < LAYOUT.BRIDGE_SIZE.z * 0.5,
				"braziers stand on the bridge")
	# Lava is below the deck and above the pit floor.
	ok(LAYOUT.LAVA_Y < LAYOUT.DECK_Y, "lava is below the deck")
	ok(LAYOUT.PIT_Y < LAYOUT.LAVA_Y, "lava surface is above the pit floor")
	ok(LAYOUT.LAVA_Z_BACK < LAYOUT.LAVA_Z_FRONT)
	# Ghosts patrol the far catwalk line.
	almost(LAYOUT.GHOST_A.y, LAYOUT.GHOST_B.y, 0.0001)
	eq(LAYOUT.GHOST_A.z, LAYOUT.GHOST_B.z, "ghosts share the catwalk line")
	eq(LAYOUT.GHOST_A.z, LAYOUT.FAR_CATWALK_Z, "ghosts walk on the catwalk")
	ok(LAYOUT.GHOST_A.y > LAYOUT.FAR_CATWALK_Y, "ghosts stand on the catwalk")
	# Windows are inside the far wall span.
	for wx in LAYOUT.WINDOW_XS:
		ok(absf(wx) < LAYOUT.HALL_HALF_W, "window is inside the hall width")
	ok(LAYOUT.WINDOW_Z <= LAYOUT.HALL_BACK_Z + LAYOUT.WALL_THICKNESS,
			"window glass sits in the far wall")


# ---------------------------------------------------------------------------
# shapes.gd: non-empty and deterministic
# ---------------------------------------------------------------------------

func test_shapes_non_empty_and_deterministic() -> void:
	var cases := [
		["gear", SHAPES.gear(2.6, 16, 0.7, 0.72, Color("#4a4642")),
				SHAPES.gear(2.6, 16, 0.7, 0.72, Color("#4a4642"))],
		["arch", SHAPES.arch(5.0, 5.2, 0.6, 10, Color("#6e6258")),
				SHAPES.arch(5.0, 5.2, 0.6, 10, Color("#6e6258"))],
		["truss", SHAPES.truss(30.8, 0.55, Color("#332f2c")),
				SHAPES.truss(30.8, 0.55, Color("#332f2c"))],
		["chain_link", SHAPES.chain_link(0.5, 0.3, Color("#4f4a44")),
				SHAPES.chain_link(0.5, 0.3, Color("#4f4a44"))],
		["cloth", SHAPES.cloth(2.4, 6.2, 6, 10, Color("#6b2a1c"), Color("#8a4a22")),
				SHAPES.cloth(2.4, 6.2, 6, 10, Color("#6b2a1c"), Color("#8a4a22"))],
	]
	for entry in cases:
		var label: String = entry[0]
		var first: ArrayMesh = entry[1]
		var second: ArrayMesh = entry[2]
		var first_stats := _mesh_stats(first)
		var second_stats := _mesh_stats(second)
		eq(first_stats.surfaces, 1, "%s builds one surface" % label)
		ok(first_stats.vertices > 0, "%s has vertices" % label)
		ok(first_stats.triangles > 0, "%s has triangles" % label)
		ok(first_stats.has_color, "%s bakes vertex colours" % label)
		eq(second_stats.vertices, first_stats.vertices, "%s vertex count is deterministic" % label)
		eq(second_stats.triangles, first_stats.triangles, "%s triangle count is deterministic" % label)
		ok(_arrays_equal(first, second), "%s mesh arrays are identical between runs" % label)
	# Cloth carries UVs for a cloth shader.
	var cloth := SHAPES.cloth(2.4, 6.2, 6, 10, Color("#6b2a1c"), Color("#8a4a22"))
	ok(_has_uv(cloth), "cloth has UVs")
	var cloth_stats := _mesh_stats(cloth)
	eq(cloth_stats.vertices, 2 * 7 * 11, "cloth is double sided over a 7x11 grid")
	# Different parameters change the mesh (sanity: generator actually reads them).
	ok(_mesh_stats(SHAPES.gear(2.6, 8, 0.7, 0.72, Color.WHITE)).vertices
			< _mesh_stats(SHAPES.gear(2.6, 16, 0.7, 0.72, Color.WHITE)).vertices,
			"more gear teeth means more geometry")


# ---------------------------------------------------------------------------
# title_kit.gd: vertex colours, cached materials, textures, outline
# ---------------------------------------------------------------------------

func test_merge_preserves_vertex_colors() -> void:
	var box := BoxMesh.new()
	var box_vertices: int = _mesh_stats(box).vertices
	var red := Color(0.8, 0.3, 0.1, 1.0)
	var green := Color(0.2, 0.7, 0.4, 1.0)
	var parts: Array = [
		KIT.part_box(Vector3.ONE, KIT.xform(Vector3.ZERO), red),
		KIT.part_box(Vector3.ONE, KIT.xform(Vector3(2.0, 0.0, 0.0)), green, 1.0),
	]
	var mesh := KIT.merge(parts)
	var stats := _mesh_stats(mesh)
	eq(stats.surfaces, 1, "merge returns one surface")
	eq(stats.vertices, box_vertices * 2, "merge keeps every box vertex")
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	eq(colors.size(), box_vertices * 2)
	almost(colors[0].r, red.r, 0.01, "first part keeps its red channel (got %s)" % str(colors[0]))
	almost(colors[0].g, red.g, 0.01, "first part keeps its green channel (got %s)" % str(colors[0]))
	almost(colors[0].a, 1.0, 0.01, "opaque part has alpha 1 (got %s)" % str(colors[0]))
	almost(colors[box_vertices].r, green.r, 0.01, "second part keeps its red channel")
	almost(colors[box_vertices].a, 0.0, 0.01, "fully emissive part has alpha 0")
	# Transforms are applied (the second box is translated along +X).
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	ok(verts[box_vertices].x > 1.0, "merge bakes the part transform")
	# A prebuilt shape keeps its baked colours when merged through part_mesh.
	var gear_mesh := SHAPES.gear(1.0, 8, 0.3, 0.3, Color(0.5, 0.5, 0.5))
	var gear_merged := KIT.merge([KIT.part_mesh(gear_mesh, KIT.xform(Vector3(10.0, 0.0, 0.0)))])
	var gear_arrays := gear_merged.surface_get_arrays(0)
	var gear_colors: PackedColorArray = gear_arrays[Mesh.ARRAY_COLOR]
	eq(gear_colors.size(), _mesh_stats(gear_mesh).vertices)
	almost(gear_colors[0].a, 1.0, 0.01, "prebuilt shape stays opaque")
	var gear_verts: PackedVector3Array = gear_arrays[Mesh.ARRAY_VERTEX]
	ok(gear_verts[0].x >= 9.0, "prebuilt shape transform is baked")
	# Half-emissive part keeps its RGB and gets alpha 0.5.
	var half := KIT.merge([KIT.part_box(Vector3.ONE, Transform3D.IDENTITY, Color(0.4, 0.6, 0.8), 0.5)])
	var half_colors: PackedColorArray = half.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	almost(half_colors[0].a, 0.5, 0.01, "half emissive alpha is 0.5 (got %s)" % str(half_colors[0]))


func test_materials_and_textures() -> void:
	var plain := KIT.mat(0)
	ok(plain is ShaderMaterial, "mat(0) is a ShaderMaterial")
	ok(KIT.mat(0) == plain, "mat(0) is cached")
	ok(KIT.mat(KIT.EMISSIVE) != plain, "EMISSIVE picks another cached material")
	ok(KIT.mat(KIT.EMISSIVE) == KIT.mat(KIT.EMISSIVE), "EMISSIVE material is cached")
	ok(KIT.mat(KIT.NO_OUTLINE) == plain, "NO_OUTLINE does not change the material")
	ok(plain.get_shader_parameter("ambient_light") is Vector3, "ambient uniform is set")
	var stone := KIT.luminance_texture("stone")
	eq(stone.get_width(), KIT.TEX_SIZE)
	eq(stone.get_height(), KIT.TEX_SIZE)
	ok(KIT.luminance_texture("stone") == stone, "luminance texture is cached")
	var textured := KIT.textured(stone, 8.0)
	ok(textured is ShaderMaterial, "textured() returns a material")
	ok(KIT.textured(stone, 8.0) == textured, "textured() is cached")
	var additive := KIT.unshaded(stone, true)
	var mixed := KIT.unshaded(stone, false)
	ok(additive != null and mixed != null, "unshaded() returns materials")
	ok(additive != mixed, "additive unshaded is a different material")
	ok(KIT.unshaded(stone, true) == additive, "unshaded() is cached")
	var palette := KIT.palette_texture()
	eq(palette.get_height(), 1)
	ok(palette.get_width() >= 16, "palette texture holds the project colours")
	ok(KIT.palette_texture() == palette, "palette texture is cached")
	# Ambient knob writes linear values into every cached surface material.
	KIT.set_ambient(Color("#4a6b6b"), 1.0)
	var ambient: Vector3 = plain.get_shader_parameter("ambient_light")
	ok(ambient.length() > 0.0, "set_ambient writes the ambient uniform")
	KIT.set_ambient(PALETTE.TEAL, 1.2)
	var reset: Vector3 = plain.get_shader_parameter("ambient_light")
	ok(reset.length() > 0.0)


func test_outline_hull() -> void:
	var mesh := KIT.merge([KIT.part_box(Vector3(2.0, 1.0, 3.0), Transform3D.IDENTITY, Color(0.5, 0.4, 0.3))])
	var instance := KIT.mesh_instance(mesh, KIT.mat(0), Transform3D.IDENTITY, "OutlinedBox")
	add_child(instance)
	KIT.outline(instance, 1.0)
	eq(instance.get_child_count(), 1, "outline() adds exactly one child")
	var hull := instance.get_child(0) as MeshInstance3D
	ok(hull != null, "outline child is a MeshInstance3D")
	ok(hull.mesh != null and hull.mesh.get_surface_count() == 1, "outline hull has geometry")
	ok(hull.material_override is ShaderMaterial, "outline hull uses the hull shader")
	eq(hull.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var base_verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var hull_verts: PackedVector3Array = hull.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	eq(hull_verts.size(), base_verts.size(), "hull keeps the mesh topology")
	var max_shift := 0.0
	for i in base_verts.size():
		max_shift = maxf(max_shift, base_verts[i].distance_to(hull_verts[i]))
	ok(max_shift >= LAYOUT.WORLD_PER_TEXEL * 0.9,
			"hull grows about one render texel (got %f)" % max_shift)
	ok(max_shift <= LAYOUT.WORLD_PER_TEXEL * 1.1, "hull does not over-grow")
	# Calling it twice must not stack another hull.
	KIT.outline(instance, 1.0)
	eq(instance.get_child_count(), 1, "outline() is idempotent")
	instance.queue_free()
	await flush(1)


# ---------------------------------------------------------------------------
# Builders: headless build budget and cleanup
# ---------------------------------------------------------------------------

func test_builders_headless_budget() -> void:
	var host := Node3D.new()
	host.name = "TitleKitTestHost"
	add_child(host)
	HALL.build(host)
	BRIDGE.build(host)
	FURNACE.build(host)
	await flush(1)
	var instances := _mesh_instances(host)
	ok(instances.size() > 0, "builders produced mesh instances")
	ok(instances.size() <= MAX_MESH_INSTANCES,
			"builders stay inside the %d MeshInstance3D budget (got %d)" % [MAX_MESH_INSTANCES, instances.size()])
	var total_vertices := 0
	var total_triangles := 0
	for instance in instances:
		ok(instance.mesh != null, "%s has a mesh" % instance.name)
		if instance.mesh == null:
			continue
		eq(instance.mesh.get_surface_count(), 1, "%s is a merged single surface" % instance.name)
		ok(instance.material_override != null, "%s has a shared material" % instance.name)
		var stats := _mesh_stats(instance.mesh)
		total_vertices += stats.vertices
		total_triangles += stats.triangles
	ok(total_vertices > 1000, "builders bake real geometry (got %d vertices)" % total_vertices)
	# Expected group names come from the builders themselves.
	for group_name in ["HallShell", "HallWindows", "HallRoof", "HallMachines", "HallCatwalk",
			"BridgeDeck", "BridgeRails", "BridgeSupports", "ForgeBody", "ForgeStack", "ForgeMouth"]:
		ok(host.has_node(group_name), "builder group %s exists" % group_name)
	# The glowing groups must not cast shadows (they would block the sun shafts).
	var windows := host.get_node_or_null("HallWindows") as MeshInstance3D
	ok(windows != null and windows.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"window glass does not cast shadows")
	var mouth := host.get_node_or_null("ForgeMouth") as MeshInstance3D
	ok(mouth != null and mouth.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"forge mouth glow does not cast shadows")
	# Outlines are hull children of the solid groups (not of the glow meshes).
	var shell := host.get_node_or_null("HallShell") as MeshInstance3D
	ok(shell != null and shell.get_node_or_null("Outline") != null, "hall shell has an outline hull")
	if shell != null:
		var hull := shell.get_node("Outline") as MeshInstance3D
		ok(hull.mesh != null and hull.mesh.get_surface_count() == 1)
		ok(hull.material_override != null)
	if not _reported_scale:
		_reported_scale = true
		print("[title3d_kit] mesh instances=%d vertices=%d triangles=%d" % [
				instances.size(), total_vertices, total_triangles])
	# Cleanup must not leak nodes or print errors.
	host.queue_free()
	await flush(2)
	ok(not is_instance_valid(host) or host.is_queued_for_deletion(), "test host is freed")
	var remaining := _mesh_instances(self)
	# The outline test instance may already be gone; no builder nodes may survive.
	for instance in remaining:
		ok(not instance.name.begins_with("Hall") and not instance.name.begins_with("Bridge")
				and not instance.name.begins_with("Forge"),
				"no builder mesh survives teardown (%s)" % instance.name)


# ---------------------------------------------------------------------------
# Dynamic entry points: TitleWorld3D loads the scripts by path and calls the
# static entry points through has_method()/call() (same idiom as title_state.gd).
# ---------------------------------------------------------------------------

func test_dynamic_entry_points_match_world3d() -> void:
	var surface: Shader = load("res://assets/shaders/title3d/surface.gdshader")
	ok(surface != null, "surface.gdshader loads")
	if surface != null:
		var uniforms: Array = surface.get_shader_uniform_list()
		if not uniforms.is_empty():
			var names := {}
			for entry in uniforms:
				names[String(entry["name"])] = true
			for required in ["tint", "roughness", "metallic", "texels_per_unit", "emission_gain",
					"flicker", "band_high", "band_low", "mid_level", "shadow_level", "ambient_light"]:
				ok(names.has(required), "surface.gdshader exposes the %s uniform" % required)
	var hull: Shader = load("res://assets/shaders/moba/outline_hull.gdshader")
	ok(hull != null, "arena outline hull shader is reusable")
	var host := Node3D.new()
	host.name = "DynamicEntryHost"
	add_child(host)
	for entry in [["hall_builder", "Hall"], ["bridge_builder", "Bridge"], ["furnace_builder", "Furnace"]]:
		var path := "res://scripts/title3d/kit/" + String(entry[0]) + ".gd"
		var script: GDScript = load(path)
		ok(script != null, "%s loads as a GDScript" % entry[0])
		if script == null:
			continue
		ok(script.has_method("build"), "%s exposes static build() through has_method()" % entry[0])
		var child := Node3D.new()
		child.name = String(entry[1])
		host.add_child(child)
		if script.has_method("build"):
			script.call("build", child)
		ok(child.get_child_count() > 0, "%s.build(host) populates its host" % entry[0])
	var kit_script: GDScript = load("res://scripts/title3d/kit/title_kit.gd")
	ok(kit_script != null, "title_kit.gd loads as a GDScript")
	if kit_script != null:
		ok(kit_script.has_method("set_ambient"),
				"title_kit exposes static set_ambient() through has_method()")
		if kit_script.has_method("set_ambient"):
			kit_script.call("set_ambient", Color(0.5, 0.46, 0.54), 0.16)
			ok(true, "set_ambient() accepts the lighting rig's colour + energy")
	host.queue_free()
	await flush(1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_mesh_instances(child))
	return out


func _mesh_stats(mesh) -> Dictionary:
	var vertices := 0
	var triangles := 0
	var has_color := false
	var surfaces := 0
	if mesh == null:
		return {"surfaces": 0, "vertices": 0, "triangles": 0, "has_color": false}
	var surface_arrays: Array = []
	if mesh is ArrayMesh:
		for surface in mesh.get_surface_count():
			surface_arrays.append(mesh.surface_get_arrays(surface))
	elif mesh is PrimitiveMesh:
		surface_arrays.append(mesh.get_mesh_arrays())
	for arrays: Array in surface_arrays:
		surfaces += 1
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		vertices += verts.size()
		if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
			has_color = true
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += floori(float(indices.size()) / 3.0)
		else:
			triangles += floori(float(verts.size()) / 3.0)
	return {"surfaces": surfaces, "vertices": vertices, "triangles": triangles, "has_color": has_color}


func _arrays_equal(a: ArrayMesh, b: ArrayMesh) -> bool:
	if a.get_surface_count() != b.get_surface_count():
		return false
	for surface in a.get_surface_count():
		var left := a.surface_get_arrays(surface)
		var right := b.surface_get_arrays(surface)
		for index in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
			if left[index] != right[index]:
				return false
	return true


func _has_uv(mesh: ArrayMesh) -> bool:
	if mesh.get_surface_count() == 0:
		return false
	var arrays := mesh.surface_get_arrays(0)
	if not (arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array):
		return false
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return uvs.size() == verts.size() and uvs.size() > 0
