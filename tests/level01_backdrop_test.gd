extends TestCase
## 1B — Level01 rust identity (docs/art-spec.md「每章身份色」「环境层次」「轮廓对比度」).
##
## The authored cemetery plate is candy magenta on purpose; the chapter ships a
## derived rust pair (tools/gen_theme_tiles.py) that keeps the plate geometry and
## the value separation. These tests pin the contract:
##   * derived plates exist, are warm (not magenta) and stay darker than the knight
##   * the graveyard theme swaps to them; the swap is theme-gated and falls back
##   * the horizon ember haze sits behind the mountains
##   * moonbeams are backdrop light (never the play canvas) and blend smoothly
##   * SIL_PATTERN / foreground gained variation without gaining gameplay geometry

const LEVEL := "res://scenes/levels/Level01_Static.tscn"
const SKY := "res://assets/env/parallax_sky.png"
const SKY_RUST := "res://assets/env/parallax_sky_rust.png"
const MOUNTAINS := "res://assets/env/parallax_mountains.png"
const MOUNTAINS_RUST := "res://assets/env/parallax_mountains_rust.png"
const CLOUD_HIGH := "res://assets/env/parallax_clouds_px.png"
const CLOUD_LOW := "res://assets/env/parallax_clouds_low_px.png"
const CLOUD_HIGH_RUST := "res://assets/env/parallax_clouds_rust.png"
const CLOUD_LOW_RUST := "res://assets/env/parallax_clouds_low_rust.png"
const MISSING := "res://assets/env/__no_such_plate__.png"
## 玩家躯干 #CD5C5C 的 sRGB 明度（docs/art-spec.md「轮廓对比度」）。
const PLAYER_BODY_LUMA := 0.455


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false


func teardown() -> void:
	WorldClock.reset()


## 派生夜板：同一张画、另一套色阶。品红被拉成锈橙，但平均明度仍留在背景带里，
## 月亮最亮处也压在玩家躯干明度之下——背景永远抢不过角色。
func test_rust_sky_is_derived_and_stays_in_the_backdrop_band() -> void:
	ok(ResourceLoader.exists(SKY), "the authored magenta plate is kept on disk")
	ok(ResourceLoader.exists(SKY_RUST), "the derived rust sky ships")
	ok(ResourceLoader.exists(MOUNTAINS_RUST), "the far mountains ship a rust variant")
	if not (ResourceLoader.exists(SKY_RUST) and ResourceLoader.exists(MOUNTAINS_RUST)):
		return
	var src := _plate_stats((load(SKY) as Texture2D).get_image())
	var rust := _plate_stats((load(SKY_RUST) as Texture2D).get_image())
	var plain := _plate_stats((load(MOUNTAINS) as Texture2D).get_image())
	var mounts := _plate_stats((load(MOUNTAINS_RUST) as Texture2D).get_image())
	eq(rust["size"], src["size"], "the derived sky keeps the authored plate geometry")
	eq(mounts["size"], plain["size"], "the derived range keeps the authored plate geometry")
	# 品红签名：绿通道极低、蓝接近红。锈签名：R > G > B。
	ok(src["rgb"].y < 0.10, "the authored plate is candy magenta (green %.3f)" % src["rgb"].y)
	ok(rust["rgb"].x > rust["rgb"].y and rust["rgb"].y > rust["rgb"].z,
			"the derived sky is rust: R>G>B (%s)" % str(rust["rgb"]))
	ok(rust["rgb"].z < src["rgb"].z * 0.85, "magenta blue is pulled out of the sky")
	ok(rust["luma"] >= 0.10 and rust["luma"] <= 0.22,
			"derived sky stays in the backdrop band (mean %.3f)" % rust["luma"])
	ok(rust["max"] < PLAYER_BODY_LUMA,
			"blood-moon core %.3f stays under the knight's %.3f" % [rust["max"], PLAYER_BODY_LUMA])
	# 远山从紫罗兰变成"暗色剪影 + 余烬山脊"：90% 的像素仍是暗色，但峰尖留一点暖光。
	ok(mounts["luma"] < 0.14, "the rust range still reads as a silhouette (mean %.3f)" % mounts["luma"])
	ok(mounts["max"] >= 0.30, "the range keeps a moonlit ember rim (max %.3f)" % mounts["max"])
	ok(mounts["max"] < PLAYER_BODY_LUMA, "the rim never outranks the knight")
	ok(mounts["rgb"].x > mounts["rgb"].z, "the range is no longer lavender")


## 云板同样是紫罗兰原板派生的灰烬/暖尘板：同一张厚涂轮廓，颜色不再和锈月天打架。
## 云量 / 漂移 / 透明度仍由 WorldClock 控制——只换色，不换「一朵风」的运动。
func test_cloud_plates_are_derived_ash_not_magenta() -> void:
	ok(ResourceLoader.exists(CLOUD_HIGH), "the authored violet cloud strip is kept on disk")
	ok(ResourceLoader.exists(CLOUD_LOW), "the authored low cloud strip is kept on disk")
	ok(ResourceLoader.exists(CLOUD_HIGH_RUST), "the derived ash cloud strip ships")
	ok(ResourceLoader.exists(CLOUD_LOW_RUST), "the derived ash low strip ships")
	if not (ResourceLoader.exists(CLOUD_HIGH_RUST) and ResourceLoader.exists(CLOUD_LOW_RUST)):
		return
	var src := _plate_stats((load(CLOUD_HIGH) as Texture2D).get_image())
	var ash := _plate_stats((load(CLOUD_HIGH_RUST) as Texture2D).get_image())
	var src_low := _plate_stats((load(CLOUD_LOW) as Texture2D).get_image())
	var ash_low := _plate_stats((load(CLOUD_LOW_RUST) as Texture2D).get_image())
	eq(ash["size"], src["size"], "the ash clouds keep the authored strip geometry")
	eq(ash_low["size"], src_low["size"], "the ash low strip keeps its geometry")
	# 紫云签名：蓝高于绿。灰烬签名：暖色 R>G>B。
	ok(src["rgb"].z > src["rgb"].y, "the authored cloud strip is violet (blue above green)")
	ok(ash["rgb"].x > ash["rgb"].y and ash["rgb"].y > ash["rgb"].z,
			"the ash clouds are warm dust (R>G>B, %s)" % str(ash["rgb"]))
	ok(ash_low["rgb"].x > ash_low["rgb"].y and ash_low["rgb"].y > ash_low["rgb"].z,
			"the ash low strip is warm dust too")
	ok(ash["rgb"].z < src["rgb"].z * 0.80, "the violet blue is pulled out of the cloud strip")
	ok(ash_low["rgb"].z < src_low["rgb"].z * 0.80, "the violet blue is pulled out of the low strip")
	ok(ash["luma"] <= src["luma"] + 0.02,
			"the ash clouds do not brighten the sky (%.3f vs %.3f)" % [ash["luma"], src["luma"]])
	ok(ash_low["luma"] <= src_low["luma"] + 0.02, "the ash low strip does not brighten the sky either")


## level01 的作者场景把天空/远山换成派生锈板；作者写的 scroll/scale 原样保留。
func test_level01_backdrop_uses_the_rust_plates() -> void:
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
	ok(fspr != null and fspr.texture != null, "the sky plate still has art")
	ok(mspr != null and mspr.texture != null, "the mountain plate still has art")
	if fspr == null or mspr == null:
		return
	eq(String(fspr.texture.resource_path), SKY_RUST, "the sky is the rust derivation")
	eq(String(mspr.texture.resource_path), MOUNTAINS_RUST, "the far range is the rust derivation")
	almost(fspr.scale.x, 1.9, 0.001, "authored sky scale untouched")
	almost(mspr.scale.x, 1.7, 0.001, "authored mountain scale untouched")
	# 飘云也换成灰烬/暖尘派生板，但作者写的运动（scroll）与云量控制点不变。
	var high := level.get_node_or_null("ParallaxBackdrop/SkyCloudsHigh") as Parallax2D
	var low := level.get_node_or_null("ParallaxBackdrop/SkyCloudsLow") as Parallax2D
	ok(high != null and low != null, "both drifting cloud strips are planted")
	if high == null or low == null:
		return
	eq(high.scroll_scale, Vector2(0.10, 0.03), "high clouds keep their authored drift")
	eq(low.scroll_scale, Vector2(0.14, 0.05), "low clouds keep their authored drift")
	var hspr := high.get_node_or_null("Sprite") as Sprite2D
	var lspr := low.get_node_or_null("Sprite") as Sprite2D
	ok(hspr != null and lspr != null)
	if hspr != null and lspr != null:
		eq(String(hspr.texture.resource_path), CLOUD_HIGH_RUST, "the high cloud strip is the ash derivation")
		eq(String(lspr.texture.resource_path), CLOUD_LOW_RUST, "the low cloud strip is the ash derivation")


## 换板只在墓园身份开启；派生资产被删时安全回落原板（启动不依赖派生素材）。
func test_plate_swap_is_theme_gated_and_falls_back() -> void:
	eq(Level01Parallax.sky_plate_path("graveyard"), SKY_RUST, "the graveyard theme swaps the sky")
	eq(Level01Parallax.mountains_plate_path("graveyard"), MOUNTAINS_RUST)
	eq(Level01Parallax.sky_plate_path("undercroft"), SKY,
			"a non-graveyard theme in the same stack keeps the authored plate")
	eq(Level01Parallax.mountains_plate_path("town"), MOUNTAINS)
	eq(Level01Parallax.plate_path(MISSING, SKY), SKY,
			"a missing derived asset resolves to the authored plate")
	eq(Level01Parallax.plate_path(MISSING, CLOUD_HIGH), CLOUD_HIGH,
			"a missing ash cloud strip also resolves to the authored plate")
	# 派生板在手：云是暖白校正；回落原紫板：仍旧用提亮紫的乘数。
	var ash_tint := Level01Parallax.cloud_tint(true)
	var magenta_tint := Level01Parallax.cloud_tint(false)
	ok(ash_tint.r > ash_tint.b and ash_tint.g > ash_tint.b, "the ash-cloud tint is a warm white")
	ok(magenta_tint.r > ash_tint.r and magenta_tint.b > ash_tint.b,
			"the authored-plate fallback keeps the old violet boost")
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	var authored := ImageTexture.create_from_image(img)
	var layer := Parallax2D.new()
	add_child(layer)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = authored
	layer.add_child(spr)
	eq(Level01Parallax.swap_plate_texture(layer, MISSING), false,
			"a missing plate is a no-op, not a cleared texture")
	ok(spr.texture == authored, "the authored texture survives the failed swap")
	eq(Level01Parallax.swap_plate_texture(null, SKY_RUST), false, "null layer is a no-op")
	eq(Level01Parallax.swap_plate_texture(layer, SKY_RUST), true)
	eq(String(spr.texture.resource_path), SKY_RUST, "a present derived plate is swapped in")
	eq(Level01Parallax.swap_plate_texture(layer, SKY_RUST), false, "re-applying the same plate is a no-op")


## 地平线暖雾：加法暖光夹在云板与远山之间，山把下半截挡住，只漏出一圈锈橙光。
func test_horizon_haze_sits_behind_the_mountains() -> void:
	var level := _load_level()
	if level == null:
		return
	var backdrop := level.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null)
	if backdrop == null:
		return
	var haze := backdrop.get_node_or_null(Level01Parallax.HORIZON_NODE) as Parallax2D
	var clouds := backdrop.get_node_or_null("SkyCloudsLow") as Parallax2D
	var mid := backdrop.get_node_or_null("Mid") as Parallax2D
	ok(haze != null, "the horizon ember haze layer is planted")
	ok(clouds != null and mid != null)
	if haze == null or clouds == null or mid == null:
		return
	ok(haze.get_index() > clouds.get_index() and haze.get_index() < mid.get_index(),
			"haze sits in front of the clouds but behind the mountains")
	ok(haze.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES, "haze loops like every other plate")
	ok(haze.repeat_size.x >= 640.0, "haze tile covers the view")
	ok(haze.modulate.a > 0.0 and haze.modulate.a <= 0.20,
			"haze is a low-alpha wash (%.2f), not a grey card" % haze.modulate.a)
	var spr := haze.get_node_or_null("Sprite") as Sprite2D
	ok(spr != null and spr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	if spr == null:
		return
	var mat := spr.material as CanvasItemMaterial
	ok(mat != null and mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
			"the haze adds warm light instead of washing the sky grey")
	var warm := Level01Parallax.horizon_tint()
	ok(warm.r > warm.g and warm.g > warm.b, "the haze tint is rust/ember (R>G>B)")
	ok(backdrop.layer < 0, "and it is still on the backdrop canvas, behind gameplay")


## 月光束是 backdrop 里的加法光，2–3 条，永远不越到玩法层/前景层。
func test_moonbeams_are_backdrop_light_not_occlusion() -> void:
	var level := _load_level()
	if level == null:
		return
	var backdrop := level.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	var beams := level.get_node_or_null("ParallaxBackdrop/Moonbeams") as Parallax2D
	var hills := level.get_node_or_null("ParallaxBackdrop/Hills") as Parallax2D
	ok(backdrop != null and beams != null and hills != null, "the moonbeam layer is planted")
	if backdrop == null or beams == null or hills == null:
		return
	ok(backdrop.layer < 0, "moonbeams live in the backdrop CanvasLayer, never over the knight")
	ok(beams.get_parent() == backdrop)
	ok(beams.get_index() > hills.get_index(), "shafts fall in front of the far plates for depth")
	ok(beams.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES, "shafts loop with the camera travel")
	ok(beams.repeat_size.x >= 640.0, "shaft pattern covers the view")
	ok(beams.modulate.a > 0.0 and beams.modulate.a <= 0.20,
			"moonbeams stay low alpha (%.2f)" % beams.modulate.a)
	var shafts := 0
	for child in beams.get_children():
		var spr := child as Sprite2D
		ok(spr != null and spr.texture != null, "each shaft carries art")
		if spr == null or spr.texture == null:
			continue
		eq(spr.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
		var mat := spr.material as CanvasItemMaterial
		ok(mat != null and mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
				"the shaft is additive light, not a dark decal")
		shafts += 1
	ok(shafts >= 2 and shafts <= 3, "2–3 volumetric shafts (%d)" % shafts)
	ok(level.get_node_or_null("ParallaxForeground/Moonbeams") == null,
			"no beam is planted on the foreground layer")
	ok(backdrop.get_node_or_null("Moonbeams") != null)


## 昼夜/天气交叉：光柱与暖雾只改 modulate，目标值随连续量走，单帧无跳变。
func test_haze_and_beams_blend_with_the_clock_without_popping() -> void:
	var host := _new_host()
	var extras := Level01Parallax.new()
	add_child(extras)
	WorldClock.set_time(0.30)
	WorldClock.set_weather(WorldClock.Weather.CLEAR, true)
	extras.build(host)
	var backdrop := host.get_node("ParallaxBackdrop") as CanvasLayer
	var beams := backdrop.get_node_or_null(Level01Parallax.MOONBEAM_NODE) as Parallax2D
	var haze := backdrop.get_node_or_null(Level01Parallax.HORIZON_NODE) as Parallax2D
	ok(beams != null and haze != null, "the atmosphere layers build on a bare host too")
	if beams == null or haze == null:
		return
	var day := beams.modulate.a
	WorldClock.set_time(0.85)
	extras._snap_atmosphere()
	var night := beams.modulate.a
	ok(night > day + 0.01, "the moon lights the shafts at night (%.3f > %.3f)" % [night, day])
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	extras._snap_atmosphere()
	ok(beams.modulate.a < night, "thick fog eats the shafts")
	# 换天用混合过渡而不是瞬间换：逐帧推进，单帧 alpha 变化要远小于雨天/雾天的总量。
	WorldClock.set_time(0.85)
	WorldClock.set_weather(WorldClock.Weather.CLEAR, true)
	extras._snap_atmosphere()
	var start_beams := beams.modulate.a
	var start_haze := haze.modulate.a
	WorldClock.set_weather(WorldClock.Weather.RAIN, false)
	var worst_beams := 0.0
	var worst_haze := 0.0
	var prev_beams := start_beams
	var prev_haze := start_haze
	for i in 120:
		# 逐帧推进仿真时钟 + 表现层，和真实帧循环同序：换天混合由 WorldClock 推进，
		# 本层只读生效值——这样测到的是实际交叉淡入，而不是一次 snap。
		WorldClock.tick(1.0 / 60.0)
		extras._process(1.0 / 60.0)
		worst_beams = maxf(worst_beams, absf(beams.modulate.a - prev_beams))
		worst_haze = maxf(worst_haze, absf(haze.modulate.a - prev_haze))
		prev_beams = beams.modulate.a
		prev_haze = haze.modulate.a
	ok(worst_beams < 0.02, "no per-frame moonbeam pop (worst step %.4f)" % worst_beams)
	ok(worst_haze < 0.02, "no per-frame haze pop (worst step %.4f)" % worst_haze)
	ok(absf(beams.modulate.a - start_beams) > 0.0, "the blend actually moves toward the new weather")
	ok(night_weight_is_continuous(), "night weight wraps continuously through dawn")


func night_weight_is_continuous() -> bool:
	var max_jump := 0.0
	var prev := Level01Parallax.night_weight(0.0)
	for i in 2000:
		var t := float(i) / 2000.0
		var w := Level01Parallax.night_weight(t)
		max_jump = maxf(max_jump, absf(w - prev))
		prev = w
	return max_jump < 0.01


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
	var front := level.get_node_or_null("ParallaxForeground") as CanvasLayer
	var author_fore := level.get_node_or_null("ParallaxForeground/Foreground") as Parallax2D
	var fringe := level.get_node_or_null("ParallaxForeground/ForegroundFringe") as Parallax2D
	ok(front != null and author_fore != null and fringe != null,
			"the foreground gains a second grass phase")
	if fringe == null or author_fore == null:
		return
	ok(fringe.scroll_scale.x > author_fore.scroll_scale.x,
			"the fringe moves faster, so the two grass strips never march in lockstep")
	ok(fringe.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES, "fringe loops enough copies")
	var fspr := fringe.get_node_or_null("Sprite") as Sprite2D
	ok(fspr != null and fspr.texture != null and fspr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	if fspr != null:
		ok(fspr.modulate.a < 0.6, "fringe stays a silhouette (alpha %.2f)" % fspr.modulate.a)
	for layer in [sil, fringe]:
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


## ThemeBackdrop 的 graveyard 分支（level06 也走这条）同样换成锈板，
## 并且 BackdropTint 仍然把整层压在玩法画布之下。
func test_graveyard_theme_reuses_the_rust_plates_for_later_chapters() -> void:
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
	eq(String(far.texture.resource_path), SKY_RUST, "chapter 6's rainy night shares the rust moon")
	eq(String(mid.texture.resource_path), MOUNTAINS_RUST, "and the rust range")
	ok(backdrop.get_node_or_null("BackdropTint") is CanvasModulate,
			"the backdrop is still subordinate to the play canvas")
	ok(host.get_node_or_null("ParallaxForeground/ForegroundFringe") != null,
			"the foreground variation rides along with the shared stack")


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
