extends TestCase
## 每一章的天气配方和局部天气区域都必须"可装、可验、不越界"。
## 这些断言不测画面，只测数据：配方里的天气 id、权重、区间，区域矩形是否还落在关卡里。

const LAYOUT_IDS := ["level03", "level04", "level05", "level06", "level07",
		"level08", "level09", "level10"]
const WEATHER_IDS := ["haze", "rain", "fog", "ember_wind", "rust_rain", "clear"]
const PHASE_IDS := ["dawn", "day", "dusk", "night"]


func teardown() -> void:
	WorldClock.reset()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _layout(id: String) -> ChapterLayout:
	var script := load(GameContext.LAYOUTS[id]) as GDScript
	ok(script != null, "%s has a layout script" % id)
	if script == null:
		return null
	return script.new() as ChapterLayout


func _range_min(value) -> float:
	if value is Vector2:
		return minf((value as Vector2).x, (value as Vector2).y)
	return float(value)


func _range_max(value) -> float:
	if value is Vector2:
		return maxf((value as Vector2).x, (value as Vector2).y)
	return float(value)


func test_every_chapter_recipe_is_well_formed() -> void:
	for id in LAYOUT_IDS:
		var layout := _layout(id)
		if layout == null:
			continue
		var recipe := layout.weather_recipe()
		ok(recipe is Dictionary, "%s returns a recipe dictionary" % id)
		if recipe.is_empty():
			# 没配方的关卡（比如钟楼）合法：它沿用全局阶段权重表。
			layout.free()
			continue
		if recipe.has("allowed"):
			var allowed: Array = recipe["allowed"]
			ok(not allowed.is_empty(), "%s: allowed is not empty" % id)
			for kind in allowed:
				var w := int(kind)
				ok(w >= WorldClock.Weather.HAZE and w <= WorldClock.Weather.CLEAR,
						"%s: allowed entry %s is a real Weather" % [id, str(kind)])
		if recipe.has("weights"):
			var table: Dictionary = recipe["weights"]
			ok(not table.is_empty(), "%s: weights is not empty" % id)
			for phase_key in table:
				ok(String(phase_key) == "*" or PHASE_IDS.has(String(phase_key)),
						"%s: weight row '%s' is a phase id or '*'" % [id, str(phase_key)])
				var row: Dictionary = table[phase_key]
				ok(not row.is_empty(), "%s: weight row '%s' is not empty" % [id, str(phase_key)])
				for weather_key in row:
					ok(WEATHER_IDS.has(String(weather_key)),
							"%s: weight key '%s' is a weather id" % [id, str(weather_key)])
					ok(float(row[weather_key]) > 0.0,
							"%s: weight for '%s' is positive" % [id, str(weather_key)])
		if recipe.has("hold"):
			var hold = recipe["hold"]
			ok(_range_min(hold) >= 0.0, "%s: hold is not negative" % id)
			ok(_range_max(hold) >= _range_min(hold), "%s: hold range is ordered" % id)
		if recipe.has("intensity"):
			var inten = recipe["intensity"]
			ok(_range_min(inten) >= 0.0 and _range_max(inten) <= 1.0,
					"%s: intensity range stays inside 0..1" % id)
		# ChapterLayout 是 Node，不 free 会在退出时报 "resources still in use"。
		layout.free()


func test_every_chapter_region_is_inside_the_level() -> void:
	for id in LAYOUT_IDS:
		var layout := _layout(id)
		if layout == null:
			continue
		var limit := float(layout.east_limit())
		var top := float(layout.camera_top()) - 64.0
		for spec in layout.weather_regions():
			var s: Dictionary = spec
			var who := "%s/%s" % [id, String(s.get("name", "?"))]
			var rect: Rect2 = s.get("rect", Rect2())
			ok(rect.size.x > 0.0 and rect.size.y > 0.0, "%s has a positive rect" % who)
			ok(rect.position.x >= 0.0 and rect.end.x <= limit + 0.5,
					"%s sits inside east_limit (%.0f..%.0f of %.0f)" % [who, rect.position.x, rect.end.x, limit])
			ok(rect.position.y >= top - 0.5 and rect.end.y <= 400.5,
					"%s sits between camera_top and the floor (%.0f..%.0f)" % [who, rect.position.y, rect.end.y])
			var intensity := float(s.get("intensity", 1.0))
			ok(intensity >= 0.0 and intensity <= 1.0, "%s intensity stays in 0..1" % who)
			var wind := float(s.get("wind_scale", 1.0))
			ok(wind >= 0.0 and wind <= 2.0, "%s wind_scale stays in 0..2" % who)
			if s.has("weather"):
				var w := int(s["weather"])
				ok(w >= WorldClock.Weather.HAZE and w <= WorldClock.Weather.CLEAR,
						"%s weather is a real Weather" % who)
		layout.free()


## 圣殿是室内关，但廊桥那一段拱顶塌了：站上去就是真的在下雨，走回走廊就停了。
## 只装配那一片区域，不搭整关——这个测试要验的是"装配 + 效果"，不是关卡几何。
func test_cathedral_broken_vault_rains_inside_an_indoor_level() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := _layout("level04")
	if layout == null:
		host.free()
		return
	var built := 0
	for spec in layout.weather_regions():
		if layout.call("_add_weather_region", host, spec) != null:
			built += 1
	var region := host.get_node_or_null("Props/BrokenVault") as WeatherRegion
	ok(region != null, "the broken vault exists as a weather region")
	ok(built >= 1, "at least one region was assembled")
	if region == null:
		host.free()
		layout.free()
		return
	eq(region.weather, WorldClock.Weather.RAIN, "the vault forces rain")
	ok(host.get_node_or_null("Props/BrokenVaultOpen") is AtmosphereZone,
			"the vault also opens a sky zone so the rain can actually render")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.tick(1.0)
	eq(WorldClock.rain_opacity(), 0.0, "indoors has no rain to begin with")
	# 模拟玩家踏上廊桥：先压一层"露天"，再压一层"这一片下雨"。
	WorldClock.enter_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.enter_weather_region(StringName(region.name), region.spec())
	WorldClock.tick(2.0)
	ok(WorldClock.rain_opacity() > 0.5, "the vault lets the rain in")
	WorldClock.leave_weather_region(StringName(region.name))
	WorldClock.leave_zone(WorldClock.Zone.INDOORS)
	eq(WorldClock.rain_opacity(), 0.0, "stepping back inside dries it up again")
	host.free()
	layout.free()
	await flush(2)


## 风口那一段的雨比别处大、风比别处猛：区域自己带天气与风力。
func test_rampart_gale_is_local_to_the_gap() -> void:
	var layout := _layout("level09")
	if layout == null:
		return
	var found := false
	for spec in layout.weather_regions():
		var s: Dictionary = spec
		if String(s.get("name", "")) != "GaleGap":
			continue
		found = true
		eq(int(s.get("weather", -1)), WorldClock.Weather.RAIN, "the gap brings its own rain")
		ok(float(s.get("wind_scale", 1.0)) > 1.0, "and it is windier than the rest of the wall")
	ok(found, "level09 declares the gale gap")
	layout.free()


## 真场景验证：走 ChapterLevel → 真实玩家 → 区域轮询这条完整链路。
## （peek 工具会把玩家物理关掉再摆位置，和真实游玩不是一条路。）
func test_real_level_scene_activates_the_region_for_the_real_player() -> void:
	var packed := load(GameContext.LEGACY_LEVELS["level09"]) as PackedScene
	ok(packed != null, "level09 scene loads")
	if packed == null:
		return
	var level := packed.instantiate()
	add_child(level)
	await flush(3)
	Director.abort()
	var region := level.get_node_or_null("Props/GaleGap") as WeatherRegion
	ok(region != null, "the real scene carries the gale gap")
	if region == null:
		level.free()
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	ok(player != null, "the real scene spawns a knight")
	if player == null:
		level.free()
		return
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	player.global_position = region.global_position + Vector2(region.rect.x * 0.5, 128)
	await flush(8)
	eq(WorldClock.active_weather_region(), &"GaleGap", "the real player activates the gap")
	eq(WorldClock.weather_id(), "rain", "and the sky above the gap turns to rain")
	player.global_position = Vector2(1600, 240)
	await flush(8)
	eq(WorldClock.active_weather_region(), &"", "walking out clears it")
	level.free()
	await flush(2)

## 这条用一个真玩家站进风口，确认整条链走通：节点 → 时钟 → 能下雨。
func test_player_standing_in_the_gap_switches_the_weather() -> void:
	var host := Node2D.new()
	host.scene_file_path = GameContext.LEGACY_LEVELS["level09"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := _layout("level09")
	if layout == null:
		host.free()
		return
	add_child(layout)
	layout.build(host)
	var region := host.get_node_or_null("Props/GaleGap") as WeatherRegion
	ok(region != null, "the gale gap node is assembled")
	if region == null:
		host.free()
		layout.free()
		return
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock.tick(1.0)
	eq(WorldClock.weather_id(), "haze", "base weather before entering")
	var player := await spawn_player(host, region.global_position + Vector2(region.rect.x * 0.5, 128))
	ok(player != null, "a knight exists")
	await flush(6)
	eq(WorldClock.active_weather_region(), &"GaleGap", "standing in the gap activates the region")
	eq(WorldClock.weather_id(), "rain", "and the gap switches the sky to rain")
	WorldClock.tick(2.0)
	ok(WorldClock.rain_opacity() > 0.5, "the gap really rains")
	# 走出风口：天气回到基础态。
	player.global_position = Vector2(1600, 240)
	await flush(6)
	eq(WorldClock.active_weather_region(), &"", "leaving the gap clears the region")
	eq(WorldClock.weather_id(), "haze", "and the sky returns to the base weather")
	player.queue_free()
	host.free()
	layout.free()
	await flush(2)
