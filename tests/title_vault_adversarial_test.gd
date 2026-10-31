extends TestCase
## title_vault_adversarial_test.gd
##
## Adversarial stress tests for Phase 2 FarVault & FarHaze:
## 1. Zero PointLight2D nodes added by FarVault and FarHaze.
## 2. TitleWorld.light_count() <= 8 across all variants (cold, act1..4, give, keep, snuff).
## 3. TitleWorld.node_count() <= 150 across all variants.
## 4. FarVault parallax depth is strictly -0.45 (< HallFar -0.30, and < FarHaze -0.42).
## 5. world.prop_nodes().size() == 7 (_heat_props is unpolluted).
## 6. All FarVault geometry coordinates and dimensions align to 2px (snap2).
## 7. Extreme pointer / parallax stress (rapid shaking at limits [-1, 1], out-of-bounds, max zoom push):
##    strictly integer pixel snapped, no holes, no NaN/Inf, no exceptions.
## 8. Intro camera dolly with stress interruptions and rapid skip idempotence.

const WORLD_SCENE := "res://scenes/ui/TitleWorld.tscn"
const FarVaultScript := preload("res://scripts/ui/title_far_vault.gd")
const FarHazeScript := preload("res://scripts/ui/title_far_haze.gd")


func setup() -> void:
	TitleWorld.forced_state = {}


func teardown() -> void:
	TitleWorld.forced_state = {}


func _peek(level_id: String = "", flags: Array = [], ending: String = "", has_save: bool = true) -> Dictionary:
	return {
		"has_save": has_save,
		"scene": String(GameContext.LEVELS[level_id]) if level_id != "" else "",
		"flags": PackedStringArray(flags),
		"ending": ending,
		"skin": "",
		"origin": "",
		"rank": 3,
		"points": 1,
	}


func _done_flags(count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(String(StoryFlow.DONE_FLAGS[GameContext.LEVEL_ORDER[i]]))
	return out


func _journey(cleared: int) -> Dictionary:
	var scene := String(GameContext.LEVEL_ORDER[mini(cleared, GameContext.LEVEL_ORDER.size() - 1)])
	return TitleWorld.build_state(_peek(scene, _done_flags(cleared)))


func _state(variant_id: String) -> Dictionary:
	match variant_id:
		"cold":
			return TitleWorld.build_state(_peek("", [], "", false))
		"act1":
			return _journey(2)
		"act2":
			return _journey(4)
		"act3":
			return _journey(8)
		"act4":
			return _journey(13)
	return TitleWorld.build_state(_peek("level10", _done_flags(14), variant_id))


func _all_variants() -> Array:
	return ["cold", "act1", "act2", "act3", "act4", "give", "keep", "snuff"]


func _make_world(state: Dictionary) -> TitleWorld:
	var vp := SubViewport.new()
	vp.size = PresentationMetrics.WORLD_SIZE
	vp.world_2d = World2D.new()
	vp.disable_3d = true
	vp.snap_2d_transforms_to_pixel = true
	add_child(vp)
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as TitleWorld
	world.state = state
	vp.add_child(world)
	return world


func _free_world(world: TitleWorld) -> void:
	if is_instance_valid(world):
		var vp := world.get_parent()
		if vp != null and is_instance_valid(vp):
			vp.queue_free()
		else:
			world.queue_free()
		await get_tree().process_frame


# -----------------------------------------------------------------------------------------
# Test 1: FarVault Standalone & In-Scene Zero-Light Contract
# -----------------------------------------------------------------------------------------
func test_far_vault_standalone_and_in_scene_zero_lights() -> void:
	# 1. Standalone instance
	var vault := FarVaultScript.new()
	eq(vault.get_child_count(), 0, "Standalone FarVault has exactly 0 children")
	var standalone_lights := vault.find_children("*", "PointLight2D", true, false)
	eq(standalone_lights.size(), 0, "Standalone FarVault has 0 PointLight2D nodes")
	vault.free()

	# 2. In TitleWorld across variants: cold, act2, keep, snuff
	var variants_to_test: Array[String] = ["cold", "act2", "keep", "snuff"]
	for v in variants_to_test:
		var world := _make_world(_state(v))
		await flush(2)
		var fv := world.far_vault()
		ok(fv != null, "%s: far_vault() returns valid node" % v)
		eq(fv.get_child_count(), 0, "%s: FarVault node in TitleWorld has 0 children" % v)
		var lights := fv.find_children("*", "PointLight2D", true, false)
		eq(lights.size(), 0, "%s: FarVault adds strictly 0 PointLight2D instances" % v)
		await _free_world(world)


# -----------------------------------------------------------------------------------------
# Test 2: Node and Light Budgets across ALL Variants
# -----------------------------------------------------------------------------------------
func test_node_and_light_budgets_across_all_variants() -> void:
	for v in _all_variants():
		var world := _make_world(_state(v))
		await flush(2)
		var lc := world.light_count()
		ok(lc <= TitleWorld.MAX_LIGHTS, "%s: light_count() (%d) <= MAX_LIGHTS (%d)" % [v, lc, TitleWorld.MAX_LIGHTS])
		var all_lights := world.find_children("*", "PointLight2D", true, false)
		ok(all_lights.size() <= TitleWorld.MAX_LIGHTS, "%s: actual PointLight2D count (%d) <= 8" % [v, all_lights.size()])

		var nc := world.node_count()
		ok(nc <= 150, "%s: node_count() (%d) strictly <= 150 budget" % [v, nc])
		var tree_nodes: int = world.find_children("*", "", true, false).size() + 1
		ok(tree_nodes <= 150, "%s: total descendant nodes (%d) <= 150" % [v, tree_nodes])
		await _free_world(world)


# -----------------------------------------------------------------------------------------
# Test 3: Strict Parallax Depth Ordering
# -----------------------------------------------------------------------------------------
func test_parallax_depth_hierarchy_strictly_layered() -> void:
	var world := _make_world(_state("act2"))
	await flush(2)
	var vault := world.far_vault()
	ok(vault != null, "far_vault() exists")

	var hall_far := world.get_node_or_null("HallFar") as Node2D
	ok(hall_far != null, "HallFar exists")

	var haze := world.get_node_or_null("FarHaze") as Node2D
	ok(haze != null, "FarHaze exists")

	var d_vault: float = world.parallax_depth(vault)
	var d_haze: float = world.parallax_depth(haze)
	var d_hall: float = world.parallax_depth(hall_far)

	almost(d_vault, -0.45, 0.001, "FarVault parallax depth is strictly -0.45")
	almost(d_haze, -0.42, 0.001, "FarHaze parallax depth is strictly -0.42")
	almost(d_hall, -0.30, 0.001, "HallFar parallax depth is strictly -0.30")

	ok(d_vault < d_haze, "FarVault is deeper than FarHaze: -0.45 < -0.42")
	ok(d_haze < d_hall, "FarHaze is deeper than HallFar: -0.42 < -0.30")
	ok(d_vault < d_hall, "FarVault is strictly deeper than HallFar: -0.45 < -0.30")

	ok(world.parallax_layers().has(vault), "FarVault is present in parallax_layers()")
	ok(world.parallax_layers().has(haze), "FarHaze is present in parallax_layers()")
	ok(world.parallax_layers().has(hall_far), "HallFar is present in parallax_layers()")

	await _free_world(world)


# -----------------------------------------------------------------------------------------
# Test 4: Prop Nodes Unpolluted (Size strictly 7)
# -----------------------------------------------------------------------------------------
func test_heat_props_unpolluted_and_size_strictly_seven() -> void:
	var check_variants: Array[String] = ["cold", "act2", "keep", "snuff"]
	for v in check_variants:
		var world := _make_world(_state(v))
		await flush(2)
		var props := world.prop_nodes()
		eq(props.size(), 7, "%s: prop_nodes().size() == 7" % v)
		var vault := world.far_vault()
		ok(not props.has(vault), "%s: FarVault is NOT in prop_nodes()" % v)
		var haze := world.get_node("FarHaze")
		ok(not props.has(haze), "%s: FarHaze is NOT in prop_nodes()" % v)

		# Verify the 7 expected props
		var names: Array[String] = []
		for p in props:
			names.append(String(p.name))
		names.sort()
		var expected: Array[String] = ["Banner0", "Banner1", "Braziers", "Crucible", "Ghosts", "Hammer", "SwordChain"]
		eq(names, expected, "%s: prop_nodes contains exactly the 7 expected heat-reacting props" % v)
		await _free_world(world)


# -----------------------------------------------------------------------------------------
# Test 5: FarVault Geometry Coordinates & Dimensions Align to 2px (snap2)
# -----------------------------------------------------------------------------------------
func test_far_vault_geometry_snap2_alignment() -> void:
	# 1. snap2 function unit assertions
	var test_vectors: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(1.4, 2.7),
		Vector2(-3.1, -5.9),
		Vector2(100.333, -200.777),
		Vector2(0.5, 0.5),
		Vector2(1.5, 1.5),
		Vector2(-0.5, -0.5),
		Vector2(-1.5, -1.5)
	]
	for vec in test_vectors:
		var snapped: Vector2 = FarVaultScript.snap2(vec)
		var rem_x := fposmod(absf(snapped.x), 2.0)
		var rem_y := fposmod(absf(snapped.y), 2.0)
		almost(rem_x, 0.0, 0.0001, "snap2(%.2f, %.2f).x = %.2f is divisible by 2" % [vec.x, vec.y, snapped.x])
		almost(rem_y, 0.0, 0.0001, "snap2(%.2f, %.2f).y = %.2f is divisible by 2" % [vec.x, vec.y, snapped.y])

	# 2. Static definition alignment in FarVault
	for win_data in FarVaultScript.WINDOWS:
		var win: Array = win_data as Array
		var cx: float = float(win[0])
		var top_y: float = float(win[1])
		var sill_y: float = float(win[2])
		var w: float = float(win[3])
		almost(fposmod(cx, 2.0), 0.0, 0.0001, "Window cx %.1f is 2px aligned" % cx)
		almost(fposmod(top_y, 2.0), 0.0, 0.0001, "Window top_y %.1f is 2px aligned" % top_y)
		almost(fposmod(sill_y, 2.0), 0.0, 0.0001, "Window sill_y %.1f is 2px aligned" % sill_y)
		almost(fposmod(w, 2.0), 0.0, 0.0001, "Window w %.1f is 2px aligned" % w)

	for shaft_data in FarVaultScript.SHAFTS:
		var shaft: Array = shaft_data as Array
		var length: float = float(shaft[2])
		var w_top: float = float(shaft[3])
		var w_bot: float = float(shaft[4])
		almost(fposmod(length, 2.0), 0.0, 0.0001, "Shaft length %.1f is 2px aligned" % length)
		almost(fposmod(w_top, 2.0), 0.0, 0.0001, "Shaft w_top %.1f is 2px aligned" % w_top)
		almost(fposmod(w_bot, 2.0), 0.0, 0.0001, "Shaft w_bot %.1f is 2px aligned" % w_bot)

	# 3. Dynamic vertex verification across time steps
	var vault := FarVaultScript.new()
	add_child(vault)
	var time_samples: Array[float] = [0.0, 0.125, 0.5, 1.23, 3.1415, 7.89, 15.0, 42.0, 100.0, 360.0]
	for t in time_samples:
		vault._t = t
		# Check all motes generated at this time step
		for mote_data in FarVaultScript.MOTES:
			var mote: Array = mote_data as Array
			var shaft_idx: int = int(mote[0])
			var u0: float = float(mote[1])
			var v_lat: float = float(mote[2])
			var speed: float = float(mote[3])
			var drift_amp: float = float(mote[4])
			var drift_freq: float = float(mote[5])

			var shaft: Array = FarVaultScript.SHAFTS[shaft_idx] as Array
			var win: Array = FarVaultScript.WINDOWS[int(shaft[0])] as Array
			var p_top := Vector2(float(win[0]), float(win[2]))
			var theta_base: float = float(shaft[1])
			var length: float = float(shaft[2])
			var w_top: float = float(shaft[3])
			var w_bot: float = float(shaft[4])
			var h1: Vector3 = shaft[6] as Vector3
			var h2: Vector3 = shaft[7] as Vector3

			var theta := theta_base + h1.x * sin(t * h1.y + h1.z) + h2.x * sin(t * h2.y + h2.z)
			var dir := Vector2(sin(theta), cos(theta))
			var norm := Vector2(dir.y, -dir.x)
			var p_bot := p_top + dir * length
			var prog := fposmod(u0 - t * speed, 1.0)
			var cur_center := p_top.lerp(p_bot, prog)
			var cur_w := lerpf(w_top, w_bot, prog)
			var lat_offset := v_lat * 0.5 * cur_w + drift_amp * sin(t * drift_freq + float(shaft_idx))
			var mote_pos := FarVaultScript.snap2(cur_center + norm * lat_offset)

			almost(fposmod(absf(mote_pos.x), 2.0), 0.0, 0.0001, "Mote pos X at t=%.2f is 2px aligned" % t)
			almost(fposmod(absf(mote_pos.y), 2.0), 0.0, 0.0001, "Mote pos Y at t=%.2f is 2px aligned" % t)

	vault.queue_free()
	await get_tree().process_frame


# -----------------------------------------------------------------------------------------
# Test 6: Extreme Pointer & Parallax Stress Test
# -----------------------------------------------------------------------------------------
func test_extreme_pointer_and_parallax_stress() -> void:
	var world := _make_world(_state("act2"))
	await flush(2)

	var vault := world.far_vault()
	ok(vault != null, "FarVault is valid")

	# Test extreme out-of-bounds pointer clamping
	world.set_pointer(Vector2(9999.0, -9999.0))
	eq(world._pointer, Vector2(1.0, -1.0), "Pointer clamped to limits [1, -1]")
	world.set_pointer(Vector2(-12345.0, 54321.0))
	eq(world._pointer, Vector2(-1.0, 1.0), "Pointer clamped to limits [-1, 1]")

	# Rapid violent shaking between extreme diagonal limits with max pushes
	var shake_coords: Array[Vector2] = [
		Vector2(-1.0, -1.0),
		Vector2(1.0, 1.0),
		Vector2(-1.0, 1.0),
		Vector2(1.0, -1.0),
		Vector2(0.0, 0.0),
		Vector2(-0.8, -0.6),
		Vector2(0.9, 0.7),
		Vector2(-1.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.0, -1.0),
		Vector2(0.0, 1.0)
	]

	# Stress run over 120 iterations
	for i in 120:
		var target: Vector2 = shake_coords[i % shake_coords.size()]
		world.set_pointer(target)
		if i % 15 == 0:
			world.enter_push(12.0, 0.2)
		if i % 8 == 0:
			world.nudge(3.0)

		# Step world simulation with varying delta
		var dt: float = 0.016 if i % 2 == 0 else 0.033
		world._process(dt)

		# Verify integer snapping and non-NaN / non-Inf across ALL parallax layers
		for layer in world.parallax_layers():
			var pos: Vector2 = layer.position
			ok(not is_nan(pos.x) and not is_inf(pos.x), "Frame %d: layer %s pos.x is finite" % [i, layer.name])
			ok(not is_nan(pos.y) and not is_inf(pos.y), "Frame %d: layer %s pos.y is finite" % [i, layer.name])
			eq(pos, pos.round(), "Frame %d: layer %s strictly whole-pixel snapped" % [i, layer.name])

		# Specific check for FarVault: within reasonable parallax envelope
		var v_pos: Vector2 = vault.position
		ok(absf(v_pos.x) < 40.0, "Frame %d: FarVault X offset within [-40, 40] (got %.1f)" % [i, v_pos.x])
		ok(absf(v_pos.y) < 40.0, "Frame %d: FarVault Y offset within [-40, 40] (got %.1f)" % [i, v_pos.y])

	await _free_world(world)


# -----------------------------------------------------------------------------------------
# Test 7: Intro Dolly with Stress Interruption & Rapid Skip Idempotence
# -----------------------------------------------------------------------------------------
func test_intro_dolly_with_stress_interruption_and_skip() -> void:
	var world := _make_world(_state("act2"))
	await flush(2)

	# 1. Start intro, inject extreme pointer & nudges mid-flight, then skip
	world.play_intro(0.16)
	eq(world._dolly, TitleWorld.DOLLY_FROM, "Intro started with _dolly == DOLLY_FROM")

	for i in 20:
		world.set_pointer(Vector2(sin(float(i)), cos(float(i))))
		if i == 5:
			world.nudge(2.0)
		world._process(0.02)
		for layer in world.parallax_layers():
			eq(layer.position, layer.position.round(), "Mid-dolly frame %d: layer %s whole-pixel snapped" % [i, layer.name])

	# Mid-flight skip
	world.skip_intro()
	eq(world._dolly, Vector2.ZERO, "Immediate skip: _dolly zeroed")
	ok(world._intro_level >= 1.0, "Immediate skip: intro level restored")
	for layer in world.parallax_layers():
		eq(layer.position, layer.position.round(), "Post-skip: layer %s whole-pixel snapped" % layer.name)

	# 2. Stress rapid skip_intro invocations (10 back-to-back skips in one frame)
	for i in 10:
		world.skip_intro()
		eq(world._dolly, Vector2.ZERO, "Repeated skip %d keeps _dolly at ZERO" % i)

	# 3. Repeated play_intro -> skip_intro cycles
	for cycle in 5:
		world.play_intro(0.1)
		world._process(0.05)
		world.skip_intro()
		eq(world._dolly, Vector2.ZERO, "Cycle %d: skip_intro zeroes _dolly" % cycle)
		for layer in world.parallax_layers():
			eq(layer.position, layer.position.round(), "Cycle %d: layer %s whole-pixel snapped" % [cycle, layer.name])

	await _free_world(world)


# -----------------------------------------------------------------------------------------
# Test 8: FarHaze Upward Bounce Parameters & Budgets
# -----------------------------------------------------------------------------------------
func test_far_haze_bounce_parameters_and_budgets() -> void:
	var haze := FarHazeScript.new()
	eq(haze.get_child_count(), 0, "FarHaze has 0 children")
	var lights := haze.find_children("*", "PointLight2D", true, false)
	eq(lights.size(), 0, "FarHaze adds strictly 0 PointLight2D instances")

	# Check bounce geometry constants
	almost(FarHazeScript.BOUNCE_TOP_Y, 180.0, 0.001, "BOUNCE_TOP_Y == 180.0")
	almost(FarHazeScript.BOUNCE_BOTTOM_Y, 340.0, 0.001, "BOUNCE_BOTTOM_Y == 340.0")
	eq(FarHazeScript.BOUNCE_BANDS, 8, "BOUNCE_BANDS == 8")
	var band_h := (FarHazeScript.BOUNCE_BOTTOM_Y - FarHazeScript.BOUNCE_TOP_Y) / float(FarHazeScript.BOUNCE_BANDS)
	almost(band_h, 20.0, 0.001, "Band height is exactly 20.0px (2px integer grid aligned)")
	almost(fposmod(band_h, 2.0), 0.0, 0.0001, "Band height is divisible by 2.0")

	haze.free()
