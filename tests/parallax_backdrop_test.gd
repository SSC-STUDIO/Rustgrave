extends TestCase
## The backdrop is the authored Gothicvania plates on Parallax2D with enough
## repeat copies that a zoomed / shaken 640px view never sees a seam. The sky and
## far-mountain plates are the derived rust pair for the graveyard identity; the
## original magenta plates stay on disk as the fallback (see level01_backdrop_test).

const LEVEL := "res://scenes/levels/Level01_Static.tscn"
const PLATES := {
	"Far": ["res://assets/env/parallax_sky.png", Vector2(0.08, 0.04), 1.9],
	"Mid": ["res://assets/env/parallax_mountains.png", Vector2(0.22, 0.06), 1.7],
	"Hills": ["res://assets/env/parallax_graveyard.png", Vector2(0.48, 0.1), 1.85],
}


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false


func teardown() -> void:
	WorldClock.reset()


func test_backdrop_is_a_canvas_layer_of_parallax2d_plates() -> void:
	var level := _load_level()
	if level == null:
		return
	var backdrop := level.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	ok(backdrop != null, "backdrop is a CanvasLayer, not the deprecated ParallaxBackground")
	if backdrop == null:
		return
	ok(backdrop.layer < 0, "backdrop draws behind the play canvas")
	ok(not backdrop.follow_viewport_enabled, "Parallax2D does its own camera math")
	for name in PLATES:
		var layer := backdrop.get_node_or_null(name) as Parallax2D
		ok(layer != null, "%s is a Parallax2D" % name)
		if layer == null:
			continue
		var spec: Array = PLATES[name]
		eq(layer.scroll_scale, spec[1], "%s keeps the authored scroll" % name)
		ok(not layer.follow_viewport)
		var spr := layer.get_node_or_null("Sprite") as Sprite2D
		ok(spr != null and spr.texture != null, "%s carries the authored plate" % name)
		if spr == null or spr.texture == null:
			continue
		eq(String(spr.texture.resource_path), spec[0], "%s keeps the authored plate (phase-3 grade does the colour)" % name)
		almost(spr.scale.x, float(spec[2]), 0.001, "%s plate scale" % name)
		eq(spr.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	for name in ["CloudFar", "CloudLow", "FarMountains", "MidGrove", "NearGround"]:
		ok(backdrop.get_node_or_null(name) == null, "%s stacked wash is gone" % name)
	ok(level.get_node_or_null("ParallaxBackdrop/Far/Sprite") != null)
	var order := []
	for child in backdrop.get_children():
		if child is Parallax2D:
			order.append(String(child.name))
	eq(order.slice(0, 5), ["Far", "SkyCloudsHigh", "SkyCloudsLow", "Mid", "Hills"],
			"sky, drifting clouds, mountains, graveyard (HorizonGlow is a sprite under Mid)")


func test_plates_repeat_enough_copies_to_cover_the_view() -> void:
	var level := _load_level()
	if level == null:
		return
	var backdrop := level.get_node("ParallaxBackdrop")
	for name in PLATES:
		var layer := backdrop.get_node(name) as Parallax2D
		var spr := layer.get_node("Sprite") as Sprite2D
		var tile := Level01Parallax.tile_width(spr)
		ok(tile >= 300.0, "%s tile is a full plate, not a strip" % name)
		ok(layer.repeat_size.x >= 1.0, "%s repeats along x" % name)
		ok(layer.repeat_size.x <= tile + 0.01, "%s repeat never exceeds the plate width (no gap)" % name)
		ok(layer.repeat_size.x >= tile - 1.01, "%s repeat is at most 1px under the plate (pixel snap overlap)" % name)
		ok(layer.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES,
				"%s draws %d copies; ParallaxLayer's single mirror showed seams" % [name, layer.repeat_times])
		ok(float(layer.repeat_times) * layer.repeat_size.x >= 640.0 + Level01Parallax.COVER_PAD,
				"%s copies cover the 640 view plus pad" % name)
	eq(Level01Parallax.copies_for_view(326.0), 4, "mountains: ceil(768/326)=3 → floor of 4")
	eq(Level01Parallax.copies_for_view(120.0), 7, "narrow tiles need more copies")
	eq(Level01Parallax.copies_for_view(0.0), Level01Parallax.MIN_REPEAT_TIMES)


func test_cover_layer_keeps_one_sprite_and_floors_the_step() -> void:
	var layer := Parallax2D.new()
	add_child(layer)
	var img := Image.create(192, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.2, 0.4, 1))
	var tex := ImageTexture.create_from_image(img)
	for i in 3:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2(1.7, 1.7)
		spr.position = Vector2(i * 326.4, 0)
		layer.add_child(spr)
	Level01Parallax.cover_layer(layer, 640.0)
	var sprites := 0
	for child in layer.get_children():
		if child is Sprite2D:
			sprites += 1
	eq(sprites, 1, "hand-tiled duplicates collapse to one sprite; Parallax2D repeats it")
	almost(layer.repeat_size.x, 326.0, 0.01, "326.4 floors to 326 so snapped copies overlap instead of gapping")
	eq(layer.repeat_times, 4)
	ok(not layer.follow_viewport)


func test_extras_add_fog_silhouette_and_foreground_cover() -> void:
	var level := _load_level()
	if level == null:
		return
	var backdrop := level.get_node("ParallaxBackdrop")
	var fog_far := backdrop.get_node_or_null("FogFar") as Parallax2D
	var fog_near := backdrop.get_node_or_null("FogNear") as Parallax2D
	var sil := backdrop.get_node_or_null("NearSilhouette") as Parallax2D
	ok(fog_far != null and fog_near != null, "two fog bands drift between the plates")
	ok(sil != null, "near silhouette strip is planted")
	if fog_far != null and fog_near != null and sil != null:
		ok(fog_far.get_index() > backdrop.get_node("Hills").get_index(), "fog hangs in front of the graveyard plate")
		ok(sil.get_index() > fog_far.get_index() and fog_near.get_index() > sil.get_index(),
				"far fog, silhouettes, near fog")
		ok(fog_far.scroll_scale.x < sil.scroll_scale.x and sil.scroll_scale.x < fog_near.scroll_scale.x,
				"nearer strips scroll faster")
		ok(fog_far.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES)
		ok(sil.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES)
		almost(sil.repeat_size.x, Level01Parallax.SIL_SPAN, 0.01)
	var front := level.get_node_or_null("ParallaxForeground") as CanvasLayer
	ok(front != null and front.layer > 0, "the fog/veil foreground layer draws over the play canvas")
	# 幕前草（Foreground / ForegroundFringe）已删除：它压在土壤剖面上，
	# 被玩家读成"土里长出来的移动植物"（2026 用户复查）。
	ok(level.get_node_or_null("ParallaxForeground/Foreground") == null,
			"no soil-sliding grass plate remains on the foreground layer")
	ok(level.get_node_or_null("ParallaxForeground/ForegroundFringe") == null,
			"no grass fringe remains either")
	ok(level.get_node_or_null("MoodTint") is CanvasModulate)
	ok(level.get_node_or_null("MoonFill") is DirectionalLight2D)
	ok(level.get_node_or_null("WeatherFx") is WeatherFx)
	ok(level.get_node_or_null("CineFx") is CineFx)
	ok(level.get_node_or_null("WindFx") is WindFx, "wind-borne dust emitter is attached")
	var ground_fog := level.get_node_or_null("ParallaxForeground/GroundFog") as Parallax2D
	ok(ground_fog != null, "ground fog rolls in front of the play canvas")
	if ground_fog != null:
		eq(ground_fog.scroll_scale, Vector2(1.0, 1.0), "ground fog is pinned to the world, not the screen")
		ok(ground_fog.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES)


func test_clouds_and_ground_fog_follow_the_weather() -> void:
	var host := Node2D.new()
	add_child(host)
	var backdrop := CanvasLayer.new()
	backdrop.name = "ParallaxBackdrop"
	host.add_child(backdrop)
	var far := Parallax2D.new()
	far.name = "Far"
	backdrop.add_child(far)
	var mid := Parallax2D.new()
	mid.name = "Mid"
	backdrop.add_child(mid)
	var front := CanvasLayer.new()
	front.name = "ParallaxForeground"
	host.add_child(front)
	var extras := Level01Parallax.new()
	add_child(extras)
	WorldClock.set_time(0.35)
	WorldClock.set_weather(WorldClock.Weather.CLEAR, true)
	extras.build(host)
	var high := backdrop.get_node_or_null("SkyCloudsHigh") as Parallax2D
	var low := backdrop.get_node_or_null("SkyCloudsLow") as Parallax2D
	ok(high != null and low != null, "two cloud plates are planted")
	if high == null or low == null:
		return
	ok(high.get_index() > far.get_index() and low.get_index() < mid.get_index(), "clouds sit between sky and mountains")
	ok(high.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES, "clouds loop like every other plate")
	var clear_a := high.modulate.a
	ok(clear_a < 0.25, "a clear sky is nearly cloudless")
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	extras._snap_atmosphere()
	ok(high.modulate.a > 0.6, "rain brings an overcast sky")
	ok(low.modulate.a < high.modulate.a, "the low plate stays thinner than the high one")
	var fog := front.get_node_or_null("GroundFog") as Parallax2D
	ok(fog != null)
	if fog == null:
		return
	WorldClock.set_weather(WorldClock.Weather.CLEAR, true)
	extras._snap_atmosphere()
	almost(fog.modulate.a, 0.0, 0.001, "no ground fog under a clear sky")
	var veil := front.get_node_or_null("FogVeil") as ColorRect
	ok(veil != null, "a screen-space veil sits on the foreground layer")
	if veil != null:
		almost(veil.color.a, 0.0, 0.001, "no veil under a clear sky")
		eq(veil.size, Vector2(640, 360), "veil covers the whole world view")
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	extras._snap_atmosphere()
	ok(fog.modulate.a >= 0.3, "thick fog rolls over the graveyard floor")
	if veil != null:
		ok(veil.color.a >= 0.15 and veil.color.a <= 0.35, "thick fog washes the view without hiding it")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	extras._snap_atmosphere()
	almost(fog.modulate.a, 0.0, 0.001, "fog stops at the door")
	if veil != null:
		almost(veil.color.a, 0.0, 0.001, "veil stops at the door too")
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	WorldClock._snap_wind_speed()
	var x0 := high.scroll_offset.x
	extras._process(0.5)
	ok(high.scroll_offset.x > x0, "clouds drift with the wind")


func test_sky_and_fog_follow_the_clock() -> void:
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
	WorldClock.set_time(0.35)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	extras.build(host)
	var day := far.modulate
	var fog_near := backdrop.get_node_or_null("FogNear") as Parallax2D
	var fog_day := fog_near.modulate.a if fog_near != null else 0.0
	WorldClock.set_time(0.85)
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	extras._snap_atmosphere()
	ok(far.modulate.v < day.v, "night darkens the sky plate through the layer modulate")
	if fog_near != null:
		ok(fog_near.modulate.a > fog_day, "fog weather thickens the near band")
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	WorldClock._snap_wind_speed()
	var x0 := far.scroll_offset.x
	extras._process(0.5)
	ok(far.scroll_offset.x != x0, "wind drifts the sky through scroll_offset")


## 每章一个视觉身份：不能只换底色（docs/art-spec.md「环境层次」）。
## SIGNATURE_LAYERS 是 theme_backdrop.gd 里登记的独有层名；build() 之后这些层
## 必须真的存在、贴最近邻采样、并以足够副本覆盖 640 视口。
func test_every_theme_has_its_signature_layers() -> void:
	var seen := {}
	var ids: Array = ["level03", "level04", "level05", "level06", "level07", "level08", "level09", "level10"]
	# level01/level02 走各自的场景脚本（ThemeBackdrop 同样经 ChapterLayout.finish 落地），
	# 这里只覆盖 GameContext.LAYOUTS 里的 ChapterLayout 子类。
	for layout_id in ids:
		var script: GDScript = load(String(GameContext.LAYOUTS[layout_id]))
		ok(script != null, "%s layout script loads" % layout_id)
		if script == null:
			continue
		var layout := script.new() as ChapterLayout
		if layout == null:
			ok(true, "%s is not a ChapterLayout — skip" % layout_id)
			continue
		var theme_id: String = layout.theme()
		seen[theme_id] = true
		var host := Node2D.new()
		add_child(host)
		# build() 在 host 下创建 / 复用名为 "ParallaxBackdrop" 的 CanvasLayer 并挂层。
		var director := ThemeBackdrop.new()
		# Parented so it is freed with the host (an orphan ThemeBackdrop leaked per layout).
		host.add_child(director)
		director.build(host, theme_id)
		var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
		if theme_id == "graveyard":
			ok(backdrop != null, "%s reuses the Level01 stack" % layout_id)
			layout.free()
			continue
		ok(backdrop != null, "%s builds a ParallaxBackdrop CanvasLayer" % layout_id)
		ok(ThemeBackdrop.has_theme(theme_id), "%s names a known theme (%s)" % [layout_id, theme_id])
		# Every authored LayerN plate of the theme (phase-3 THEMES table).
		var want: Array = []
		for child in backdrop.get_children():
			if child is Parallax2D and String(child.name).begins_with("Layer"):
				want.append(String(child.name))
		ok(not want.is_empty(), "%s plants authored plates for '%s'" % [layout_id, theme_id])
		for layer_name in want:
			var layer := backdrop.get_node_or_null(String(layer_name)) as Parallax2D
			ok(layer != null, "%s signature layer %s exists" % [theme_id, layer_name])
			if layer == null:
				continue
			var spr := layer.get_node_or_null("Sprite") as Sprite2D
			ok(spr != null and spr.texture != null, "%s/%s carries a plate" % [theme_id, layer_name])
			if spr == null:
				continue
			ok(spr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
					"%s/%s stays nearest-neighbour" % [theme_id, layer_name])
			# 平铺竖井墙（belltower tower_wall 的 tile 模式）用 texture_repeat 的
			# 大 region 覆盖整座塔，不靠 repeat_times；其余层靠 repeat_times 平铺。
			if layer.repeat_size == Vector2.ZERO and spr.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED:
				ok(true, "%s/%s tiles via texture_repeat (no seam in a tall shaft)" % [theme_id, layer_name])
			else:
				ok(layer.repeat_times >= Level01Parallax.MIN_REPEAT_TIMES,
						"%s/%s repeats enough copies (%d)" % [theme_id, layer_name, layer.repeat_times])
		# 注：「层 tint 明度 ≤ 0.62」是运行期 WorldAtmosphere 把 backdrop 压暗一档后
		# 的约束（见 world_atmosphere_test.test_backdrop_stays_subordinate_at_every_phase），
		# 作者写的 tint 允许为白（1.0）——夜幕由 WorldAtmosphere 统一压暗，不在此断言。
		layout.free()
	# 每章身份色必须至少登记一次；登记表本身要覆盖 build() 用得到的主题。
	ok(seen.size() >= 8, "chapters cover at least 8 distinct themes (got %d)" % seen.size())
	# 登记表覆盖 THEMES 全部键：新增主题忘了登记 SIGNATURE_LAYERS 就过不了。


## 环境层次（merge contract: phase-3 ChapterLook）：every theme carries its own look —
## a haze glow and lit platform lips in the chapter's colour, plates pushed back by depth —
## and the glow stays additive air on the backdrop canvas, never a screen wash.
## (The parallel line's Signature / FogNear / BackdropTint identity layers were not kept:
## the user approved the phase-3 grade for every chapter.)
func test_every_theme_has_a_phase3_look_on_the_backdrop() -> void:
	var seen := {}
	for theme_id in ThemeBackdrop.THEMES:
		var look: Dictionary = (ThemeBackdrop.THEMES[theme_id] as Dictionary).get("look", {})
		ok(not look.is_empty(), "%s registers a ChapterLook" % theme_id)
		WorldClock.set_zone(WorldClock.Zone.INDOORS if ThemeBackdrop.is_indoor_theme(theme_id) \
				else WorldClock.Zone.OUTDOORS)
		var host := Node2D.new()
		add_child(host)
		var director := ThemeBackdrop.new()
		host.add_child(director)
		director.build(host, theme_id)
		var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
		ok(backdrop != null and backdrop.layer < 0, "%s builds a backdrop behind the play canvas" % theme_id)
		if backdrop != null:
			var glow := backdrop.get_node_or_null("HorizonGlow") as Sprite2D
			ok(glow != null, "%s has its chapter haze glow" % theme_id)
			if glow != null:
				ok(glow.modulate.a <= 0.45, "%s glow is air, not a screen wash" % theme_id)
				var mat := glow.material as CanvasItemMaterial
				ok(mat != null and mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
						"%s glow is additive light" % theme_id)
		var key := str(look.get("glow", Color.BLACK)) + str(look.get("top_light", Color.BLACK))
		ok(not seen.has(key), "%s keeps a distinct look" % theme_id)
		seen[key] = true
		host.free()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _load_level() -> Node:
	var packed := load(LEVEL) as PackedScene
	ok(packed != null, "Level01_Static packs")
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	return level
