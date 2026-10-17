extends TestCase
## 场景级天气：每章配方、关卡内局部区域、强度、顶板遮挡。
##
## 这几条断言同时钉住两件事：
##   1. 新功能真的生效（配方能收敛、区域能覆盖、强度能缩降雨量、顶板下面不漏雨）
##   2. 不设配方/区域时行为和从前一模一样（默认值必须是恒等变换）


func setup() -> void:
	SaveData.delete_save()
	Director.abort()
	WorldClock.reset()


func teardown() -> void:
	WorldClock.reset()
	Director.abort()
	SaveData.delete_save()


## ------------------------------------------------------------- 配方 --

func test_profile_pins_the_weather_to_the_allowed_set() -> void:
	WorldClock.set_time(0.30)
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.set_weather_profile({
		"allowed": [WorldClock.Weather.FOG],
		"hold": 0.0,
	})
	ok(WorldClock.has_weather_profile(), "profile is installed")
	for i in 6:
		WorldClock.set_weather_hold(0.0)
		WorldClock.tick(0.20)
		eq(WorldClock.effective_weather(), WorldClock.Weather.FOG,
				"a one-weather profile can only produce that weather (step %d)" % i)
	eq(WorldClock.weather_id(), "fog", "weather_id reports the profile result")


func test_profile_weights_pick_by_phase() -> void:
	WorldClock.set_weather_profile({
		"weights": {
			"night": {"rust_rain": 1.0},
			"day": {"clear": 1.0},
		},
	})
	WorldClock.set_time(0.80) # night
	WorldClock.set_weather_hold(0.0)
	WorldClock.tick(0.20)
	eq(WorldClock.effective_weather(), WorldClock.Weather.RUST_RAIN, "night row wins at night")
	WorldClock.set_time(0.30) # day
	WorldClock.set_weather_hold(0.0)
	WorldClock.tick(0.20)
	eq(WorldClock.effective_weather(), WorldClock.Weather.CLEAR, "day row wins by day")


func test_profile_intensity_stays_inside_its_range() -> void:
	WorldClock.set_weather_profile({
		"allowed": [WorldClock.Weather.RAIN],
		"intensity": Vector2(0.4, 0.6),
		"hold": 0.0,
	})
	for i in 8:
		WorldClock.set_weather_hold(0.0)
		WorldClock.tick(3.0)
		var got := WorldClock.weather_intensity()
		ok(got >= 0.4 - 0.001 and got <= 0.6 + 0.001,
				"intensity %f stays in [0.4, 0.6] (step %d)" % [got, i])


func test_no_profile_keeps_the_global_behaviour() -> void:
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.tick(2.0)
	almost(WorldClock.weather_intensity(), 1.0, 0.05, "no profile means full strength")
	almost(WorldClock.rain_opacity(), 1.0, 0.05, "no profile means unthinned rain")


## ------------------------------------------------------------- 区域 --

func test_region_overrides_and_restores() -> void:
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.tick(2.0)
	almost(WorldClock.rain_opacity(), 1.0, 0.05, "outdoor rain first")
	WorldClock.enter_weather_region(&"Courtyard", {"weather": WorldClock.Weather.FOG})
	eq(WorldClock.effective_weather(), WorldClock.Weather.FOG, "region takes over immediately")
	eq(WorldClock.active_weather_region(), &"Courtyard", "region id is queryable")
	WorldClock.tick(2.0)
	almost(WorldClock.rain_opacity(), 0.0, 0.05, "fog courtyard stops the rain")
	WorldClock.leave_weather_region(&"Courtyard")
	eq(WorldClock.effective_weather(), WorldClock.Weather.RAIN, "leaving restores the base weather")
	WorldClock.tick(2.0)
	ok(WorldClock.rain_opacity() > 0.9, "rain comes back after leaving the courtyard")


func test_region_stack_is_lifo_and_deduped() -> void:
	WorldClock.set_weather(WorldClock.Weather.CLEAR, true)
	WorldClock.enter_weather_region(&"A", {"weather": WorldClock.Weather.FOG})
	WorldClock.enter_weather_region(&"B", {"weather": WorldClock.Weather.EMBER_WIND})
	eq(WorldClock.effective_weather(), WorldClock.Weather.EMBER_WIND, "later region wins")
	# 重进同一个 id 不叠层：里面那份被换掉，外面那份仍然只剩一层。
	WorldClock.enter_weather_region(&"A", {"weather": WorldClock.Weather.FOG})
	WorldClock.leave_weather_region(&"A")
	eq(WorldClock.effective_weather(), WorldClock.Weather.EMBER_WIND, "re-entering A did not stack")
	WorldClock.leave_weather_region(&"B")
	eq(WorldClock.effective_weather(), WorldClock.Weather.CLEAR, "stack empties back to base")
	eq(WorldClock.active_weather_region(), &"", "no active region left")


func test_leaving_an_unknown_region_is_harmless() -> void:
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock.leave_weather_region(&"NeverEntered")
	eq(WorldClock.effective_weather(), WorldClock.Weather.HAZE, "stray exit leaves the sky alone")


func test_region_intensity_thins_the_rain() -> void:
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.tick(2.0)
	WorldClock.enter_weather_region(&"Drizzle", {
		"weather": WorldClock.Weather.RAIN,
		"intensity": 0.25,
	})
	WorldClock.tick(4.0)
	almost(WorldClock.weather_intensity(), 0.25, 0.02, "region intensity is applied")
	almost(WorldClock.rain_opacity(), 0.25, 0.03, "thin rain follows intensity")
	WorldClock.clear_weather_regions()
	WorldClock.tick(4.0)
	almost(WorldClock.rain_opacity(), 1.0, 0.05, "clearing regions restores full rain")


func test_region_wind_scale_bends_the_wind() -> void:
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.tick(2.0)
	var open_wind := WorldClock.weather_wind_speed()
	WorldClock.enter_weather_region(&"Shelter", {
		"weather": WorldClock.Weather.RAIN,
		"wind_scale": 0.3,
	})
	almost(WorldClock.weather_wind_speed(), open_wind * 0.3, 0.01, "a sheltered column calms the wind")
	WorldClock.clear_weather_regions()
	almost(WorldClock.weather_wind_speed(), open_wind, 0.01, "open air restores it")


## 存档只认基础态：站在雾天井里存档，读出来不能把整关变成雾。
func test_snapshot_saves_the_base_weather_only() -> void:
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.enter_weather_region(&"Courtyard", {"weather": WorldClock.Weather.FOG})
	eq(String(WorldClock.snapshot().get("weather", "")), "rain", "snapshot keeps the base weather")
	eq(WorldClock.weather_id(), "fog", "while the screen still shows the region weather")


## --------------------------------------------------------- 顶板遮挡 --

func test_roof_columns_know_their_ceiling() -> void:
	var host := Node2D.new()
	add_child(host)
	var roof := SolidPlatform.new()
	roof.name = "Roof"
	roof.position = Vector2(400.0, 120.0)
	roof.size = Vector2(96.0, 32.0)
	host.add_child(roof)
	var fx := WeatherFx.new()
	host.add_child(fx)
	await flush(2)
	almost(fx.roof_y_at(440.0), 152.0, 0.5, "under the roof the column sees its underside")
	var open := fx.roof_y_at(600.0)
	ok(is_inf(open) and open < 0.0, "a column with open sky has no roof")
	fx.queue_free()
	host.queue_free()
	await flush(1)


func test_roof_follows_new_terrain() -> void:
	var host := Node2D.new()
	add_child(host)
	var fx := WeatherFx.new()
	host.add_child(fx)
	await flush(2)
	# 没有地块时用夹具兜底：地面 y=320 的板厚 80，所以这一列"顶板底面"是 400。
	almost(fx.roof_y_at(320.0), WeatherFx.DEFAULT_GROUND_Y + 80.0, 0.5,
			"empty host falls back to the fixture floor")
	var ledge := SolidPlatform.new()
	ledge.name = "Ledge"
	ledge.position = Vector2(280.0, 200.0)
	ledge.size = Vector2(120.0, 16.0)
	host.add_child(ledge)
	await flush(2)
	fx.call("_rebuild_spans")
	almost(fx.roof_y_at(320.0), 216.0, 0.5, "a new ledge becomes the roof of that column")
	ok(is_inf(fx.roof_y_at(960.0)) or fx.roof_y_at(960.0) > 216.0,
			"a column outside the ledge keeps the taller roof")
	fx.queue_free()
	host.queue_free()
	await flush(1)
