extends TestCase
## WindSway follows WorldClock heading; hardness decides who leans.


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock._snap_wind_speed()


func teardown() -> void:
	WorldClock.reset()


func test_sway_flips_with_heading() -> void:
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	WorldClock._snap_wind_speed()
	var host := Node2D.new()
	add_child(host)
	var sway := WindSway.new()
	sway.amplitude = 1.0
	sway.phase = 0.0
	host.add_child(sway)
	sway._apply()
	ok(host.rotation > 0.0, "right wind leans positive")
	WorldClock.wind_heading = -1.0
	WorldClock._heading_target = -1.0
	sway._apply()
	ok(host.rotation < 0.0, "left wind leans negative")
	ok(absf(WorldClock.sway_radians()) >= 0.08, "outdoor sway is at least ~4.5 degrees")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	WorldClock._snap_wind_speed()
	almost(WorldClock.sway_radians(), 0.0, 0.01, "indoor trees do not lean")


func test_hardness_rules() -> void:
	eq(Level01Env.hardness_of(Level01Env.DECOR_TREE_1), Level01Env.Hardness.TREE)
	eq(Level01Env.hardness_of(Level01Env.DECOR_BUSH_L), Level01Env.Hardness.BUSH)
	eq(Level01Env.hardness_of(Level01Env.DECOR_STONE_1), Level01Env.Hardness.STONE)
	eq(Level01Env.hardness_of(Level01Env.DECOR_STATUE), Level01Env.Hardness.STONE)
	eq(Level01Env.hardness_of("res://props/rusty_gate.png"), Level01Env.Hardness.STEEL)
	eq(Level01Env.hardness_of("res://props/arena_door.png"), Level01Env.Hardness.STEEL)
	eq(Level01Env.hardness_of("res://world/gear_platform.png"), Level01Env.Hardness.STEEL)
	almost(Level01Env.sway_amplitude(Level01Env.DECOR_STONE_1), 0.0, 0.001)
	almost(Level01Env.sway_amplitude(Level01Env.DECOR_STATUE), 0.0, 0.001)
	almost(Level01Env.sway_amplitude("res://props/iron_fence.png"), 0.0, 0.001)
	ok(Level01Env.sway_amplitude(Level01Env.DECOR_TREE_1) > 0.0, "trees lean")
	ok(Level01Env.sway_amplitude(Level01Env.DECOR_BUSH_L) \
			> Level01Env.sway_amplitude(Level01Env.DECOR_TREE_1),
			"bushes lean more than trees")


func test_plant_sways_trees_not_stones() -> void:
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	WorldClock._snap_wind_speed()
	var layer := Node2D.new()
	add_child(layer)
	var tree := Level01Env.plant(layer, Level01Env.DECOR_TREE_1, Vector2(0, 80), 0.5)
	var bush := Level01Env.plant(layer, Level01Env.DECOR_BUSH_L, Vector2(40, 80), 0.65)
	var stone := Level01Env.plant(layer, Level01Env.DECOR_STONE_1, Vector2(80, 80), 1.0)
	var statue := Level01Env.plant(layer, Level01Env.DECOR_STATUE, Vector2(120, 80), 0.82)
	if tree == null or stone == null:
		ok(true, "gothic assets missing in this checkout — skip plant assert")
		return
	ok(tree.get_parent() != layer, "foliage sits on a foot pivot")
	var tree_sway := Level01Env.find_sway(tree.get_parent())
	ok(tree_sway != null, "tree pivot has WindSway")
	ok(bush != null, "bush planted")
	var bush_sway := Level01Env.find_sway(bush.get_parent()) if bush != null else null
	ok(bush_sway != null, "bush pivot has WindSway")
	if tree_sway != null and bush_sway != null:
		ok(bush_sway.amplitude > tree_sway.amplitude, "bush amplitude > tree")
		tree_sway.phase = 0.0
		bush_sway.phase = 0.0
		tree_sway._apply()
		bush_sway._apply()
		ok(absf(bush.get_parent().rotation) > absf(tree.get_parent().rotation),
				"bush leans farther than the tree")
	ok(stone.get_parent() == layer, "stone stays a raw sprite")
	ok(Level01Env.find_sway(stone) == null, "stone has no sway child")
	almost(stone.rotation, 0.0, 0.0001, "stone rotation stays 0")
	if statue != null:
		ok(statue.get_parent() == layer, "statue stays a raw sprite")
		ok(Level01Env.find_sway(statue) == null, "statue has no WindSway")
		almost(statue.rotation, 0.0, 0.0001, "statue rotation stays 0")


func test_play_trees_shed_leaves_beside_the_sway_pivot() -> void:
	var layer := Node2D.new()
	add_child(layer)
	var quiet := Level01Env.plant(layer, Level01Env.DECOR_TREE_2, Vector2(0, 80), 0.5)
	var tree := Level01Env.plant(layer, Level01Env.DECOR_TREE_1, Vector2(200, 80), 0.5, Color.WHITE, true)
	var bush := Level01Env.plant(layer, Level01Env.DECOR_BUSH_L, Vector2(400, 80), 0.65, Color.WHITE, true)
	if quiet == null or tree == null or bush == null:
		ok(true, "gothic assets missing — skip leaf assert")
		return
	var sheds: Array[LeafShed] = []
	for child in layer.get_children():
		if child is LeafShed:
			sheds.append(child)
	eq(sheds.size(), 1, "only trees asked to shed get a LeafShed; bushes and silhouettes never do")
	if sheds.is_empty():
		return
	var shed := sheds[0]
	var pivot := tree.get_parent() as Node2D
	ok(shed.get_parent() == layer, "shed is a sibling of the pivot, so leaves fall straight while the crown leans")
	eq(shed.position, pivot.position, "shed stands on the tree's feet")
	almost(shed.canopy.x, float(tree.texture.get_width()) * 0.5, 0.01, "canopy width follows the planted scale")
	almost(shed.canopy.y, float(tree.texture.get_height()) * 0.5, 0.01)
	ok(layer.get_children().find(shed) > layer.get_children().find(pivot), "leaves draw in front of their trunk")


func test_leaf_falls_with_the_wind_and_dies_on_the_ground() -> void:
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	WorldClock._snap_wind_speed()
	var shed := LeafShed.new()
	shed.canopy = Vector2(80, 60)
	add_child(shed)
	var leaf := shed.spawn_leaf()
	ok(leaf != null, "spawn_leaf hands back the leaf")
	if leaf == null:
		return
	ok(leaf.position.y <= -30.0 and leaf.position.y >= -54.0, "leaves start in the upper crown")
	ok(absf(leaf.position.x) <= 28.0, "leaves start inside the canopy width")
	eq(leaf.position, leaf.position.round(), "leaf sits on the pixel grid")
	var start := leaf.position
	leaf._process(0.5)
	ok(leaf.position.y > start.y, "leaf falls")
	ok(not leaf.landed())
	ok(absf(leaf.position.x - start.x) <= 12.0, "a leaf glides; it is not dragged sideways")
	var min_x := leaf.position.x
	var max_x := leaf.position.x
	for i in 60:
		leaf._process(0.1)
		min_x = minf(min_x, leaf.position.x)
		max_x = maxf(max_x, leaf.position.x)
	ok(leaf.landed(), "leaf reaches the foot line")
	almost(leaf.position.y, 0.0, 0.01, "landed leaves rest exactly on the feet line")
	ok(max_x - min_x >= 4.0, "the leaf swings back and forth on the way down")
	ok(absf(leaf.position.x - start.x) <= 30.0, "leaves land near their own tree, not down the corridor")
	leaf._process(LeafShed.Leaf.FADE + 0.05)
	ok(leaf.is_queued_for_deletion(), "landed leaves dissolve into the soil")
	for i in 5:
		shed.spawn_leaf()
	ok(shed.leaf_count() <= LeafShed.MAX_LEAVES, "a tree never rains more than %d leaves" % LeafShed.MAX_LEAVES)


func test_hard_plant_lands_on_opaque_bottom() -> void:
	var layer := Node2D.new()
	add_child(layer)
	var feet := Vector2(16, 80)
	var img := Image.create(12, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 12:
		for x in 12:
			img.set_pixel(x, y, Color(0.5, 0.45, 0.4, 1))
	var pad := ImageTexture.create_from_image(img)
	var spr := Level01Env.plant_texture(layer, pad, "stone-pad.png", feet, 2.0)
	ok(spr != null, "padded stone planted")
	almost(spr.position.y, feet.y - 24.0, 0.01, "sprite top uses opaque height, not pad")
	almost(Level01Env.sprite_opaque_bottom_y(spr), feet.y, 0.01,
			"opaque pixel bottom sits on feet.y")
	var stone := Level01Env.plant(layer, Level01Env.DECOR_STONE_1, Vector2(40, 80), 1.0)
	var statue := Level01Env.plant(layer, Level01Env.DECOR_STATUE, Vector2(80, 80), 0.82)
	if stone == null or statue == null:
		ok(true, "gothic assets missing — skip real-asset land assert")
		return
	almost(Level01Env.sprite_opaque_bottom_y(stone), 80.0, 0.01, "stone opaque bottom on feet")
	almost(Level01Env.sprite_opaque_bottom_y(statue), 80.0, 0.01, "statue opaque bottom on feet")


## 特效不遮挡（docs/art-spec.md「特效不遮挡原则」）：风尘是 1–3px 的氛围粒，
## 不是亮斑。它可以在角色前（读风），但必须远低于剑光（z=10），且尺寸封顶，
## 不形成遮挡面。真正会盖住轮廓的浮尘层（ThemeMotes/CineFx）已放到 z<0。
func test_wind_fx_stays_below_the_play_layer() -> void:
	var wind := WindFx.new()
	add_child(wind)
	eq(wind.z_index, 1, "wind dust stays a thin near-air layer")
	ok(wind.z_index > -10, "wind dust still draws in front of the backdrop")
	ok(wind.z_index < 10, "wind dust never reaches the SlashArc layer")
	var mote := wind.spawn_mote(Rect2(Vector2.ZERO, Vector2(640, 360)))
	ok(mote != null, "a wind mote can be inspected")
	if mote != null:
		var poly := mote.get_child(0) as Polygon2D
		ok(poly != null, "wind mote is a polygon")
		if poly != null:
			var area := 0.0
			var pts := poly.polygon
			for i in pts.size():
				var a := pts[i]
				var b := pts[(i + 1) % pts.size()]
				area += a.x * b.y - b.x * a.y
			area = absf(area) * 0.5
			ok(area <= 6.0, "wind dust is 1–3px (area %.1f), not an occluding shape" % area)
	var pivot := Node2D.new()
	add_child(pivot)
	var sway := WindSway.new()
	pivot.add_child(sway)
	ok(sway.get_parent() is Node2D, "sway pivot is a plain Node2D — z stays at the planted sprite")
	eq(pivot.z_index, 0, "the sway pivot never lifts decor above the play layer")


func test_play_decor_feet_sit_on_ground() -> void:
	eq(Level01Static.GROUND_TOP, 320.0)
	ok(Level01Static.PLAY_DECOR.size() >= 8, "grave props are listed")
	for item in Level01Static.PLAY_DECOR:
		var path := String(item[0])
		var feet: Vector2 = item[1]
		almost(feet.y, Level01Static.GROUND_TOP, 0.01,
				"%s feet.y is the ground top" % path.get_file())
		ok(_on_standable_ground(feet), "%s x=%.0f sits on a standable span" % [path.get_file(), feet.x])


func test_play_decor_stays_at_integer_scale_and_off_the_signs() -> void:
	var spans: Array[Rect2] = []
	for item in Level01Static.PLAY_DECOR:
		var path := String(item[0])
		almost(float(item[2]), 1.0, 0.001, "%s is drawn at 1x" % path.get_file())
		var tex := load(path) as Texture2D
		ok(tex != null, path)
		if tex == null:
			continue
		var feet: Vector2 = item[1]
		spans.append(Rect2(feet.x, feet.y - float(tex.get_height()), float(tex.get_width()), float(tex.get_height())))
	for i in spans.size():
		for j in range(i + 1, spans.size()):
			var overlap: Rect2 = spans[i].intersection(spans[j])
			ok(overlap.get_area() <= 1.0,
					"decor %d and %d overlap by %s" % [i, j, str(overlap.size)])
	for mark in Level01Static.WAYMARKS:
		var feet: Vector2 = mark[0]
		var board := Rect2(feet.x - 17.0, feet.y - 35.0, 35.0, 35.0)
		for i in spans.size():
			var overlap: Rect2 = spans[i].intersection(board)
			ok(overlap.get_area() <= 1.0,
					"%s covers %s" % [String(Level01Static.PLAY_DECOR[i][0]).get_file(), String(mark[1])])


func test_play_decor_hard_props_do_not_sway() -> void:
	var layer := Node2D.new()
	add_child(layer)
	var hard_n := 0
	for item in Level01Static.PLAY_DECOR:
		var path := String(item[0])
		if Level01Env.is_foliage(path):
			continue
		hard_n += 1
		almost(float(item[2]), 1.0, 0.001, "%s scale is 1" % path.get_file())
		almost(Level01Env.sway_amplitude(path), 0.0, 0.001,
				"%s sway amplitude is 0" % path.get_file())
		var spr := Level01Env.plant(layer, path, item[1] as Vector2, float(item[2]))
		if spr == null:
			continue
		ok(spr.get_parent() == layer, "%s stays a raw sprite" % path.get_file())
		ok(Level01Env.find_sway(spr) == null, "%s has no WindSway" % path.get_file())
		almost(spr.scale.x, 1.0, 0.001, "%s planted scale.x is 1" % path.get_file())
		almost(spr.rotation, 0.0, 0.0001, "%s rotation stays 0" % path.get_file())
	ok(hard_n >= 4, "play layer still nails stones / the statue")


func test_silhouette_is_background_foliage() -> void:
	ok(Level01Parallax.SIL_PATTERN.size() >= 3, "near strip still has silhouettes")
	for item in Level01Parallax.SIL_PATTERN:
		var path := String(item[0])
		var feet_y := float(item[2])
		ok(Level01Env.is_foliage(path), "%s is foliage, not a climbable stone" % path.get_file())
		ok(Level01Env.hardness_of(path) != Level01Env.Hardness.STONE)
		ok(feet_y >= Level01Parallax.SIL_FEET_MIN and feet_y <= Level01Parallax.SIL_FEET_MAX,
				"%s feet_y=%.1f sits on the hill/ground band" % [path.get_file(), feet_y])


func test_near_silhouette_plants_only_foliage() -> void:
	var host := Node2D.new()
	add_child(host)
	var backdrop := CanvasLayer.new()
	backdrop.name = "ParallaxBackdrop"
	host.add_child(backdrop)
	var far := Parallax2D.new()
	far.name = "Far"
	backdrop.add_child(far)
	var extras := Level01Parallax.new()
	add_child(extras)
	extras.build(host)
	var sil := backdrop.get_node_or_null("NearSilhouette") as Parallax2D
	if sil == null:
		ok(true, "gothic assets missing — silhouette layer skipped")
		return
	var hard := 0
	for child in sil.get_children():
		var spr := child as Sprite2D
		if spr == null and child.get_child_count() > 0:
			spr = child.get_child(0) as Sprite2D
		if spr == null or spr.texture == null:
			continue
		var path := String(spr.texture.resource_path)
		if path != "" and not Level01Env.is_foliage(path):
			hard += 1
		ok(Level01Env.find_sway(child) == null or Level01Env.is_foliage(path),
				"hard silhouette props do not sway")
	eq(hard, 0, "NearSilhouette planted no stone/statue")


func _on_standable_ground(feet: Vector2) -> bool:
	# GroundLeft 0–400, GroundRight 512–1600, east floor 1600–2240. Pit 400–512 is void.
	if not is_equal_approx(feet.y, Level01Static.GROUND_TOP):
		return false
	if feet.x >= 0.0 and feet.x <= 400.0:
		return true
	if feet.x >= 512.0 and feet.x <= 2240.0:
		return true
	return false
