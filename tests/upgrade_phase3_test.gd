extends TestCase
## Phase-3 regressions: chapter-1 grade brightened with clear value separation (phase-2
## feedback: too dark / muddy), lit platform tops, light pools around fires, horizon glow.

const LEVEL := "res://scenes/levels/Level01_Static.tscn"


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_chapter_one_ramps_are_ember_not_magenta() -> void:
	for ramp in [Level01Parallax.RUST_RAMP, Level01Parallax.PLAY_RAMP]:
		for c in ramp:
			var col := c as Color
			ok(col.r >= col.g and col.g >= col.b, "r >= g >= b at every stop (no plum / magenta): %s" % col)
	var g := Level01Parallax.HORIZON_GLOW
	ok(g.r > g.g and g.g > g.b and g.a > 0.2, "horizon glow is a visible warm ember")


func test_value_structure_backdrop_dark_midground_mid_play_brightest() -> void:
	var v := Level01Parallax.PLATE_VALUE
	ok(float(v["Mid"]) < float(v["Hills"]), "mountains darker than the graveyard slope")
	ok(float(v["Hills"]) < Level01Parallax.PLAY_VALUE, "play layer lifted above the midground")
	ok(Level01Parallax.PLAY_VALUE > 1.0, "terrain is pushed up, not down")
	ok(_lum(Level01Parallax.PLAY_RAMP[4]) >= _lum(Level01Parallax.RUST_RAMP[4]), "brightest values belong to the play layer")
	ok(_lum(Level01Parallax.PLAY_RAMP[0]) < 0.05, "deep shadows stay dark (contrast, not a lifted haze)")


func test_partial_grade_keeps_the_authored_colour() -> void:
	# User steer: keep more of the original crimson / violet, a bit darker; no full recolour.
	for layer_name in ["Far", "Mid", "Hills"]:
		ok(float(Level01Parallax.GRADE[layer_name]) <= 0.5, "%s keeps at least half its authored hue" % layer_name)
		ok(float(Level01Parallax.PLATE_VALUE[layer_name]) < 1.0, "%s sits a little darker than authored" % layer_name)
	ok(Level01Parallax.PLAY_GRADE_AMOUNT <= 0.4, "play layer keeps its authored colours")
	var day := WorldClock.DAY_TINT
	var warm := Level01Parallax.chapter_tint(day)
	ok(absf(_lum(warm) - _lum(day)) < 0.06, "the day tint is nudged, not washed")


func test_play_material_lifts_value() -> void:
	var mat := Level01Parallax.play_grade_material()
	almost(float(mat.get_shader_parameter("value_scale")), Level01Parallax.PLAY_VALUE)


func test_platform_tops_get_a_lit_lip_once() -> void:
	var host := Node2D.new()
	add_child(host)
	var plats := Node2D.new()
	plats.name = "Platforms"
	host.add_child(plats)
	var ledge := SolidPlatform.new()
	ledge.size = Vector2(96, 16)
	plats.add_child(ledge)
	var wall := SolidPlatform.new()
	wall.size = Vector2(16, 96)
	plats.add_child(wall)
	await flush(1)
	Level01Parallax.grade_play_layer(host)
	Level01Parallax.grade_play_layer(host)
	var lip := ledge.get_node_or_null("TopLight") as Sprite2D
	ok(lip != null, "ledge top is lit")
	if lip != null:
		ok(lip.material is CanvasItemMaterial and (lip.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "additive light")
		almost(lip.scale.x, 96.0, 0.01, "spans the whole top")
	var lips := 0
	for c in ledge.get_children():
		if String(c.name).begins_with("TopLight"):
			lips += 1
	eq(lips, 1, "regrading adds no second lip")
	ok(wall.get_node_or_null("TopLight") == null, "walls are not lit like ledges")
	host.queue_free()


func test_light_pools_follow_their_fire() -> void:
	var host := Node2D.new()
	add_child(host)
	var nest_light := WorldLight.new()
	nest_light.follow = &"nest"
	host.add_child(nest_light)
	var ghost := WorldLight.new()
	ghost.follow = &"ghost"
	host.add_child(ghost)
	await flush(1)
	eq(Level01Parallax.add_light_pools(host), 1, "fires only; enemy glows keep their own look")
	eq(Level01Parallax.add_light_pools(host), 0, "idempotent")
	var pool := nest_light.get_node_or_null("LightPool") as LightPool
	ok(pool != null)
	if pool != null:
		nest_light.lit = false
		nest_light.apply(true)
		await flush(1)
		ok(not pool.visible, "unlit nest has no pool")
		nest_light.lit = true
		nest_light.apply(true)
		await flush(1)
		ok(pool.visible, "lit nest glows")
	host.queue_free()


func test_horizon_glow_sits_between_sky_and_mountains_and_fog_is_graded() -> void:
	# Minimal backdrop host (a full Level01 instance would start the opening cinematic and
	# leave clock / director state behind for later suites).
	var host := Node2D.new()
	add_child(host)
	var backdrop := CanvasLayer.new()
	backdrop.name = "ParallaxBackdrop"
	host.add_child(backdrop)
	for layer_name in ["Far", "Mid", "Hills"]:
		var layer := Parallax2D.new()
		layer.name = layer_name
		var spr := Sprite2D.new()
		spr.texture = PlaceholderTexture2D.new()
		layer.add_child(spr)
		backdrop.add_child(layer)
	var extras := Level01Parallax.new()
	host.add_child(extras)
	extras.build(host)
	var glow := backdrop.get_node_or_null("HorizonGlow") as Sprite2D
	ok(glow != null, "horizon glow is planted")
	if glow != null:
		ok(glow.get_index() > backdrop.get_node("Far").get_index(), "over the sky")
		ok(glow.get_index() < backdrop.get_node("Mid").get_index(), "under the mountains")
		ok(glow.modulate.a > 0.1, "visible")
	var fog := backdrop.get_node_or_null("FogNear")
	ok(fog != null and (fog.get_child(0) as CanvasItem).material is ShaderMaterial, "fog bands are graded warm, not lavender")
	host.queue_free()
