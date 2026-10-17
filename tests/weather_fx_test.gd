extends TestCase
## Rain hits standable ground (wet + splash) and water film (ripple, no wet).


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)


func teardown() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false


func test_ground_fx_nodes_exist() -> void:
	var host := Node2D.new()
	add_child(host)
	var fx := WeatherFx.new()
	fx.name = "WeatherFx"
	host.add_child(fx)
	var ground := fx.ground_fx()
	ok(ground != null, "RainGroundFx is planted")
	if ground != null:
		eq(ground.name, "RainGroundFx")
		ok(ground.get_node_or_null("Splashes") != null, "splash bucket exists")
		ok(ground.get_node_or_null("WetMarks") != null, "wet-mark bucket exists")
		ok(ground.get_node_or_null("Ripples") != null, "water-ripple bucket exists")


func test_hit_spawns_splash_and_wet() -> void:
	var host := Node2D.new()
	add_child(host)
	var fx := WeatherFx.new()
	host.add_child(fx)
	fx.simulate_hit(Vector2(120.0, 320.0))
	ok(fx.wet_mark_count() >= 1, "standable ground keeps a wet patch")
	ok(fx.splash_count() >= 2, "landing spatters 2–5 specks")
	var wets := host.get_node_or_null("RainGroundFx/WetMarks")
	ok(wets != null)
	if wets != null:
		ok(wets.get_child_count() >= 1, "wet sprite sits on the ground host")
		var spr := wets.get_child(0) as Sprite2D
		ok(spr != null)
		if spr != null:
			almost(spr.position.y, 321.0, 1.5, "wet mark hugs the ground top")
			eq(spr.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_water_hit_splashes_without_wet() -> void:
	var host := Node2D.new()
	add_child(host)
	var pool := ToxinPool.new()
	pool.position = Vector2(400.0, 336.0)
	host.add_child(pool)
	pool.configure(Vector2(112.0, 32.0))
	var fx := WeatherFx.new()
	host.add_child(fx)
	fx.simulate_hit(Vector2(120.0, 320.0))
	var wet := fx.wet_mark_count()
	var splash := fx.splash_count()
	fx.simulate_hit(Vector2(456.0, 368.0))
	eq(fx.wet_mark_count(), wet, "water already wet — no dirt plates")
	ok(fx.splash_count() > splash, "water film throws 2–4 specks")
	ok(fx.ripple_count() >= 1, "water film grows a pixel ripple")
	almost(fx.water_y_at(456.0), 336.0, 0.51, "hit plane is the scum top, not y=320 dirt")
	ok(fx.water_y_at(120.0) < 0.0, "dirt span is not a pool")


func test_water_stops_rain_above_the_pit_floor() -> void:
	var host := Node2D.new()
	add_child(host)
	var pool := ToxinPool.new()
	pool.position = Vector2(400.0, 336.0)
	host.add_child(pool)
	pool.configure(Vector2(112.0, 32.0))
	var fx := WeatherFx.new()
	host.add_child(fx)
	var hit := fx._hit_surface(Vector2(456.0, 350.0))
	eq(String(hit.get("kind", "")), "water", "a drop at the pit hits water")
	almost(float(hit.get("y", -1.0)), 336.0, 0.51, "collision is the film, not the floor")
	var dirt := fx._hit_surface(Vector2(120.0, 321.0))
	eq(String(dirt.get("kind", "")), "ground", "dirt still hits standable top")
	almost(float(dirt.get("y", -1.0)), 320.0, 0.51)


func test_screen_to_world_uses_world_viewport_transform() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	add_child(viewport)
	var host := Node2D.new()
	viewport.add_child(host)
	var fx := WeatherFx.new()
	host.add_child(fx)
	viewport.canvas_transform = Transform2D(0.0, Vector2(-240, -90))
	fx._cache_view()
	eq(fx._view_size, Vector2(640, 360), "weather uses the world viewport, not native UI dimensions")
	eq(fx._screen_to_world(Vector2(120, 180)), Vector2(360, 270), "rain hit testing uses the full canvas inverse")


func test_surfaces_rebuild_when_terrain_changes() -> void:
	var host := Node2D.new()
	add_child(host)
	var fx := WeatherFx.new()
	host.add_child(fx)
	ok(not fx._surfaces_dirty, "initial terrain cache is ready")
	var terrain := SolidPlatform.new()
	terrain.position = Vector2(100, 200)
	terrain.size = Vector2(80, 16)
	host.add_child(terrain)
	ok(fx._surfaces_dirty, "adding terrain invalidates the cache")
	fx._rebuild_spans()
	almost(fx._ground_y_at(120), 200, 0.01, "new ledge becomes the rain hit plane")
	ok(not fx._surfaces_dirty, "cached geometry remains clean between changes")


## 特效不遮挡（docs/art-spec.md「特效不遮挡原则」）：雨是全屏氛围层，画在
## backdrop（-10）与玩法画布（0）之间；角色 / 前摇 / 台缘都在雨滴前面。
## 地面水痕 / 涟漪属于地面，也在角色脚下，不遮轮廓。
func test_weather_fx_stay_below_the_play_layer() -> void:
	var host := Node2D.new()
	add_child(host)
	var fx := WeatherFx.new()
	fx.name = "WeatherFx"
	host.add_child(fx)
	eq(fx.layer, WeatherFx.WEATHER_LAYER)
	ok(fx.layer > -10, "weather draws in front of the backdrop")
	ok(fx.layer < 0, "weather draws behind the play canvas — never over silhouettes")
	ok(WeatherFx.RAIN_ALPHA_CAP <= 0.45, "the full-screen rain veil stays thin")
	ok(WeatherFx.EMBER_ALPHA_CAP <= 0.25, "ember-wind specks never read as fire over an actor")
	eq(fx.follow_viewport_enabled, false, "weather does its own camera math")
	fx.simulate_hit(Vector2(120.0, 320.0))
	var ground := fx.ground_fx()
	ok(ground != null, "RainGroundFx is planted")
	if ground != null:
		eq(ground.z_index, 2, "RainGroundFx is a floor effect, not a screen wash")
	var wets := ground.get_node_or_null("WetMarks") if ground != null else null
	if wets != null and wets.get_child_count() > 0:
		var mark := wets.get_child(0) as Node2D
		ok(mark.z_index == 1, "wet marks hug the ground, never over characters (%d)" % mark.z_index)
