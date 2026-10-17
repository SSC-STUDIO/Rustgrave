extends TestCase
## 1B — Level01 backdrop contract after merging cursor/upgrade-phase1 (phase-3 grade).
##
## The user rejected the derived rust plates ("background colour completely distorted")
## and approved the phase-3 grade: the authored crimson-moon / violet plates stay and are
## graded ~40% toward the rust ramp by Level01Parallax (partial, darker, separated).
## These tests pin that contract:
##   * the authored plates are what chapter 1 (and the graveyard theme) shows; the
##     derived *_rust.png files may stay on disk but are not wired in
##   * no rust-plate horizon haze / moonbeam layers are added on top of the grade
##     (phase-3 owns the horizon glow: HorizonGlow)
##   * SIL_PATTERN gained variation without gaining gameplay geometry
##   * presentation never creates nodes per frame or writes the clock

const LEVEL := "res://scenes/levels/Level01_Static.tscn"
const SKY := "res://assets/env/parallax_sky.png"
const MOUNTAINS := "res://assets/env/parallax_mountains.png"
const CLOUD_HIGH := "res://assets/env/parallax_clouds_px.png"
const CLOUD_LOW := "res://assets/env/parallax_clouds_low_px.png"


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false


func teardown() -> void:
	WorldClock.reset()


## level01 keeps the authored plates (crimson moon, violet range, violet clouds); the
## phase-3 grade material does the colour work, so authored scroll/scale stay as written.
func test_level01_backdrop_keeps_the_authored_plates_under_the_grade() -> void:
	var level := _load_level()
	if level == null:
		return
	var far := level.get_node_or_null("ParallaxBackdrop/Far") as Parallax2D
	var mid := level.get_node_or_null("ParallaxBackdrop/Mid") as Parallax2D
	ok(far != null and mid != null, "the authored plate stack is intact")
	if far == null or mid == null:
		return
	eq(far.scroll_scale, Vector2(0.08, 0.04), "the authored sky scroll is preserved")
	eq(mid.scroll_scale, Vector2(0.22, 0.06), "the authored mountain scroll is preserved")
	var fspr := far.get_node_or_null("Sprite") as Sprite2D
	var mspr := mid.get_node_or_null("Sprite") as Sprite2D
	ok(fspr != null and fspr.texture != null and mspr != null and mspr.texture != null)
	if fspr == null or mspr == null:
		return
	eq(String(fspr.texture.resource_path), SKY, "the sky is the authored crimson-moon plate")
	eq(String(mspr.texture.resource_path), MOUNTAINS, "the far range is the authored plate")
	almost(fspr.scale.x, 1.9, 0.001, "authored sky scale untouched")
	almost(mspr.scale.x, 1.7, 0.001, "authored mountain scale untouched")
	ok(fspr.material is ShaderMaterial, "the sky carries the phase-3 grade material")
	var high := level.get_node_or_null("ParallaxBackdrop/SkyCloudsHigh") as Parallax2D
	var low := level.get_node_or_null("ParallaxBackdrop/SkyCloudsLow") as Parallax2D
	ok(high != null and low != null, "both drifting cloud strips are planted")
	if high == null or low == null:
		return
	var hspr := high.get_node_or_null("Sprite") as Sprite2D
	var lspr := low.get_node_or_null("Sprite") as Sprite2D
	if hspr != null and lspr != null:
		eq(String(hspr.texture.resource_path), CLOUD_HIGH, "the high cloud strip is the authored one")
		eq(String(lspr.texture.resource_path), CLOUD_LOW, "the low cloud strip is the authored one")


## The rust-plate atmosphere (HorizonHaze / Moonbeams) is not layered over the grade:
## phase-3's HorizonGlow is the one horizon light.
func test_no_rust_haze_or_moonbeams_over_the_grade() -> void:
	var level := _load_level()
	if level == null:
		return
	var backdrop := level.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null)
	if backdrop == null:
		return
	ok(backdrop.get_node_or_null("HorizonHaze") == null, "no rust horizon haze")
	ok(backdrop.get_node_or_null("Moonbeams") == null, "no additive moonbeam shafts")
	ok(level.get_node_or_null("ParallaxForeground/ForegroundFringe") == null,
			"no extra rust-shadow grass fringe over the graded foreground")
	ok(backdrop.find_child("HorizonGlow", true, false) != null, "the phase-3 horizon glow is there")

## 中景剪影与前景获得变化，但只是画面：不引入碰撞体、不进玩法层。
func test_silhouette_and_foreground_gain_variation() -> void:
	var shapes := {}
	for item in Level01Parallax.SIL_PATTERN:
		shapes[String(item[0])] = true
	ok(Level01Parallax.SIL_PATTERN.size() >= 8,
			"the near strip repeats more than the old five stamps")
	ok(shapes.size() >= 5, "the mid-ground has %d distinct tree/bush shapes" % shapes.size())
	var level := _load_level()
	if level == null:
		return
	var sil := level.get_node_or_null("ParallaxBackdrop/NearSilhouette") as Parallax2D
	ok(sil != null, "the silhouette strip is still one Parallax2D")
	var author_fore := level.get_node_or_null("ParallaxForeground/Foreground") as Parallax2D
	for layer in [sil]:
		if layer == null:
			continue
		for child in layer.get_children():
			ok(not (child is CollisionObject2D), "backdrop variation adds no collision")
	# 玩法层不变：作者前景板仍是原来的图，前景层之外没有多余的玩法节点。
	if author_fore != null:
		var aspr := author_fore.get_node_or_null("Sprite") as Sprite2D
		ok(aspr != null and String(aspr.texture.resource_path).ends_with("parallax_foreground_px.png"),
				"the authored foreground plate is untouched")


## 表现层契约：漂移/调色只改已有节点，不建节点、不写时钟/存档/物理。
func test_presentation_only_creates_no_nodes_and_never_writes_the_clock() -> void:
	var level := _load_level()
	if level == null:
		return
	var extras := level.get_node_or_null("ParallaxExtras")
	var backdrop := level.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(extras != null and backdrop != null)
	if extras == null or backdrop == null:
		return
	var before_backdrop := _count_nodes(backdrop)
	var before_extras := _count_nodes(extras)
	WorldClock.set_time(0.85)
	WorldClock.set_weather(WorldClock.Weather.FOG, false)
	var weather := WorldClock.weather
	var time_scale := WorldClock.time_scale
	for i in 60:
		extras._process(1.0 / 60.0)
	eq(_count_nodes(backdrop), before_backdrop, "per-frame drift never creates backdrop nodes")
	eq(_count_nodes(extras), before_extras, "per-frame tinting never creates extras nodes")
	eq(WorldClock.weather, weather, "presentation never rolls the weather")
	almost(WorldClock.time_scale, time_scale, 0.0001, "presentation never writes Engine time scale")
	ok(not WorldClock.menu_hold, "presentation never holds the clock for a menu")


## ThemeBackdrop 的 graveyard 分支（level06 也走这条）同样用作者原板 + phase-3 调色。
func test_graveyard_theme_keeps_the_authored_plates_for_later_chapters() -> void:
	var host := Node2D.new()
	add_child(host)
	var director := ThemeBackdrop.new()
	host.add_child(director)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	director.build(host, "graveyard")
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null, "the graveyard theme rebuilds the sky stack")
	if backdrop == null:
		return
	var far := backdrop.get_node_or_null("Far/Sprite") as Sprite2D
	var mid := backdrop.get_node_or_null("Mid/Sprite") as Sprite2D
	ok(far != null and mid != null)
	if far == null or mid == null:
		return
	eq(String(far.texture.resource_path), SKY, "chapter 6's rainy night keeps the authored moon")
	eq(String(mid.texture.resource_path), MOUNTAINS, "and the authored range")
	ok(backdrop.layer < 0, "the backdrop stays behind the play canvas")


func _load_level() -> Node:
	var packed := load(LEVEL) as PackedScene
	ok(packed != null, "Level01_Static packs")
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	return level


func _new_host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	var backdrop := CanvasLayer.new()
	backdrop.name = "ParallaxBackdrop"
	host.add_child(backdrop)
	for plate_name in ["Far", "Mid", "Hills"]:
		var layer := Parallax2D.new()
		layer.name = plate_name
		backdrop.add_child(layer)
	var front := CanvasLayer.new()
	front.name = "ParallaxForeground"
	host.add_child(front)
	return host


func _count_nodes(root: Node) -> int:
	var n := 1
	for child in root.get_children():
		if child is Node:
			n += _count_nodes(child as Node)
	return n


## One pass over an image: mean luma, max luma, mean rgb of opaque pixels, size.
func _plate_stats(img: Image) -> Dictionary:
	if img == null:
		return {"size": Vector2i.ZERO, "luma": 0.0, "max": 0.0, "rgb": Vector3.ZERO}
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var peak := 0.0
	var rs := 0.0
	var gs := 0.0
	var bs := 0.0
	var n := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.04:
				continue
			rs += c.r
			gs += c.g
			bs += c.b
			var luma := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			total += luma
			peak = maxf(peak, luma)
			n += 1
	return {
		"size": img.get_size(),
		"luma": total / float(n) if n > 0 else 0.0,
		"max": peak,
		"rgb": Vector3(rs / float(n), gs / float(n), bs / float(n)) if n > 0 else Vector3.ZERO,
	}
