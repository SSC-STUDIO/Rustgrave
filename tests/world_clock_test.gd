extends TestCase
## WorldClock: slow cemetery cycle, weather blends, freeze rules, save restore.


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false
	WorldClock.time_scale = 1.0
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	SaveData.save_path = "user://rustgrave_test_clock_save.cfg"
	SaveData.delete_save()


func teardown() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"


func test_advance_changes_phase() -> void:
	WorldClock.set_time(0.48)
	eq(WorldClock.phase, WorldClock.Phase.DAY, "just before dusk")
	WorldClock.advance(CYCLE_CROSS)
	eq(WorldClock.phase, WorldClock.Phase.DUSK, "crossing 0.50 becomes dusk")
	WorldClock.set_time(0.61)
	WorldClock.advance(CYCLE_CROSS)
	eq(WorldClock.phase, WorldClock.Phase.NIGHT, "crossing 0.62 becomes night")


func test_pause_freezes_clock() -> void:
	WorldClock.set_time(0.30)
	var t0 := WorldClock.time_of_day
	get_tree().paused = true
	ok(WorldClock.is_frozen(), "paused tree freezes the clock")
	WorldClock._process(8.0)
	almost(WorldClock.time_of_day, t0, 0.0001, "paused clock does not advance")
	get_tree().paused = false
	ok(not WorldClock.is_frozen())


func test_cutscene_freezes_clock() -> void:
	WorldClock.set_time(0.30)
	var t0 := WorldClock.time_of_day
	Director.play([
		{"kind": "lock"},
		{"kind": "wait", "seconds": 30.0},
		{"kind": "unlock"},
	])
	ok(Director.playing)
	ok(WorldClock.is_frozen(), "Director.playing freezes the clock")
	WorldClock._process(8.0)
	almost(WorldClock.time_of_day, t0, 0.0001, "cutscene clock does not jump")
	Director.abort()
	ok(not WorldClock.is_frozen())


func test_choice_hold_freezes_clock() -> void:
	WorldClock.set_time(0.40)
	var t0 := WorldClock.time_of_day
	Director.choice_hold = true
	ok(WorldClock.is_frozen())
	WorldClock._process(5.0)
	almost(WorldClock.time_of_day, t0, 0.0001)
	Director.choice_hold = false


func test_menu_hold_freezes_clock() -> void:
	WorldClock.hold_for_menu()
	ok(WorldClock.is_frozen(), "title pins the clock")
	almost(WorldClock.time_of_day, WorldClock.TITLE_TIME, 0.0001)
	eq(WorldClock.phase, WorldClock.Phase.DUSK, "title stays at dusk")
	var t0 := WorldClock.time_of_day
	WorldClock._process(10.0)
	almost(WorldClock.time_of_day, t0, 0.0001, "menu does not roll the sky")
	WorldClock.release_menu()
	ok(not WorldClock.is_frozen())


func test_weather_blend_stays_legal() -> void:
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock.set_weather(WorldClock.Weather.RAIN, false)
	eq(WorldClock.weather, WorldClock.Weather.RAIN)
	eq(WorldClock.previous_weather, WorldClock.Weather.HAZE)
	ok(WorldClock.weather_blend >= 0.0 and WorldClock.weather_blend < 1.0, "blend starts open")
	WorldClock._process(1.0)
	ok(WorldClock.weather_blend > 0.0 and WorldClock.weather_blend <= 1.0)
	ok(WorldClock.weather >= WorldClock.Weather.HAZE)
	ok(WorldClock.weather <= WorldClock.Weather.RUST_RAIN)
	ok(WorldClock.rain_opacity() > 0.0, "rain opacity rises during blend-in")
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	almost(WorldClock.weather_blend, 1.0, 0.001)
	eq(WorldClock.weather, WorldClock.Weather.FOG)


func test_weather_does_not_swap_during_cutscene() -> void:
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock.set_weather_hold(0.01)
	Director.play([{"kind": "wait", "seconds": 20.0}])
	WorldClock._process(2.0)
	eq(WorldClock.weather, WorldClock.Weather.HAZE, "cutscene blocks a weather roll")
	Director.abort()


func test_save_roundtrip_time_and_weather() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	WorldClock.set_time(0.73)
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	ok(SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player))
	WorldClock.reset()
	almost(WorldClock.time_of_day, WorldClock.DEFAULT_TIME, 0.0001)
	eq(WorldClock.weather, WorldClock.Weather.HAZE)
	ok(SaveData.load_game())
	almost(WorldClock.time_of_day, 0.73, 0.0001, "load restores the hour")
	eq(WorldClock.weather, WorldClock.Weather.FOG, "load restores fog")
	eq(WorldClock.phase, WorldClock.Phase.NIGHT)
	eq(String(SaveData.data["atmosphere"]["weather"]), "fog")


func test_night_tint_stays_playable() -> void:
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	var night := WorldClock.mood_tint()
	ok(night.r >= 0.28 and night.g >= 0.28 and night.b >= 0.28, "night is not a black frame")
	ok(WorldClock.mood_luminance() >= 0.30, "fog night stays above a black frame")
	ok(night != Color.BLACK)
	WorldClock.set_time(0.30)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	var day := WorldClock.mood_tint()
	ok(day.b >= day.r * 0.95, "day stays cool, not a sunny yellow")
	ok(WorldClock.mood_luminance() > WorldClock.NIGHT_TINT.r * 0.9)
	ok(WorldClock.nest_light_energy() >= 1.0, "day nest glow is a visible pool")
	WorldClock.set_time(0.80)
	ok(WorldClock.nest_light_energy() >= 2.0, "night nest glow is the bright setting")
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	ok(WorldClock.nest_light_energy() < 1.0, "outdoor rain soaks the shrine fire")
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	ok(WorldClock.nest_light_energy() >= 2.0, "rain stop restores night nest glow")


func test_parallax_follows_clock_tint() -> void:
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	var host := Node2D.new()
	add_child(host)
	var backdrop := CanvasLayer.new()
	backdrop.name = "ParallaxBackdrop"
	host.add_child(backdrop)
	var far := Parallax2D.new()
	far.name = "Far"
	far.follow_viewport = false
	backdrop.add_child(far)
	var extras := Level01Parallax.new()
	add_child(extras)
	extras.build(host)
	var tint := host.get_node_or_null("MoodTint") as CanvasModulate
	ok(tint != null)
	if tint != null:
		ok(tint.color.r >= 0.28 and tint.color.g >= 0.28 and tint.color.b >= 0.28,
				"MoodTint night is a dark corridor, not a black frame")
		ok(tint.color.a >= 0.99)
	ok(host.get_node_or_null("WeatherFx") != null, "rain layer is attached")


func test_indoor_zone_locks_warm_light_and_hides_rain() -> void:
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	var outdoor := WorldClock.mood_tint()
	var outdoor_lum := WorldClock.mood_luminance()
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	var indoor := WorldClock.mood_tint()
	ok(indoor.r > outdoor.r + 0.08, "indoor night stays warmer than outdoor night")
	ok(WorldClock.mood_luminance() > outdoor_lum, "indoor lock is brighter than outdoor night")
	eq(WorldClock.zone_id(), "indoors")
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	almost(WorldClock.rain_opacity(), 0.0, 0.001, "rain particles stop at the door")
	ok(WorldClock.rain_audio_gain() <= 0.05, "indoor rain is muffled")
	ok(WorldClock.rust_rain_audio_gain() < 0.20)
	ok(not WorldClock.weather_fx_allowed())


func test_zone_api_simulates_second_scene() -> void:
	WorldClock.set_time(0.30)
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	ok(WorldClock.rain_opacity() > 0.9, "outdoor scene can rain")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	almost(WorldClock.rain_opacity(), 0.0, 0.001, "second scene indoor suppresses rain")
	eq(WorldClock.zone_id(), "indoors")
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	eq(WorldClock.zone_id(), "outdoors")
	ok(WorldClock.rain_opacity() > 0.9, "leaving the room restores outdoor rain")


func test_atmosphere_zone_switches_on_overlap() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	var shelter := AtmosphereZone.new()
	shelter.zone = WorldClock.Zone.INDOORS
	shelter.position = player.global_position
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(96, 96)
	shape.shape = rect
	shelter.add_child(shape)
	arena.add_child(shelter)
	await flush(6)
	eq(WorldClock.zone, WorldClock.Zone.INDOORS, "entering the room sets indoor")
	player.position.x += 420.0
	await flush(6)
	eq(WorldClock.zone, WorldClock.Zone.OUTDOORS, "leaving the room restores outdoor")


func test_rust_rain_exposes_outdoors_only() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	player.toxin.toxin = 0.0
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.RUST_RAIN, true)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	ok(WorldClock.is_rust_raining())
	ok(WorldClock.apply_rust_rain_expose(player), "outdoor rust rain soaks")
	almost(player.toxin.toxin, WorldClock.RUST_RAIN_EXPOSE, 0.05)
	ok(player.toxin.toxin < 36.0, "weaker than a toxin-pool second")
	player.toxin.toxin = 0.0
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	ok(not WorldClock.apply_rust_rain_expose(player), "indoor rust rain does not soak")
	almost(player.toxin.toxin, 0.0, 0.01)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	get_tree().paused = true
	ok(not WorldClock.apply_rust_rain_expose(player), "pause blocks rust rain")
	get_tree().paused = false
	Director.play([{"kind": "lock"}, {"kind": "wait", "seconds": 2.0}, {"kind": "unlock"}])
	ok(not WorldClock.apply_rust_rain_expose(player), "cutscene blocks rust rain")
	Director.abort()
	player.health.current = 0
	ok(not WorldClock.apply_rust_rain_expose(player), "dead player is not soaked")
	eq(WorldClock.weather_label(), "锈雨")


func test_clear_weather_is_a_real_state() -> void:
	WorldClock.set_time(0.30)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.CLEAR, true)
	eq(WorldClock.weather, WorldClock.Weather.CLEAR, "CLEAR survives the clamp")
	eq(WorldClock.weather_label(), "晴")
	eq(WorldClock.weather_id(), "clear")
	eq(WorldClock.weather_from_id("clear"), WorldClock.Weather.CLEAR)
	eq(WorldClock.hud_line(), "晴 · 白昼")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	eq(WorldClock.hud_line(), "地下 · 白昼", "underground the HUD stops reporting sky weather")
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	almost(WorldClock.rain_opacity(), 0.0, 0.001, "clear sky has no rain")
	ok(WorldClock.cloud_alpha() < 0.25, "clear sky is nearly cloudless")
	almost(WorldClock.ground_fog_alpha(), 0.0, 0.001, "clear sky has no ground fog")
	ok(WorldClock.fog_near_alpha() < 0.15, "clear sky thins the far fog bands")
	ok(WorldClock.mood_luminance() > 0.78, "clear day is the brightest outdoor mood")
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	ok(WorldClock.cloud_alpha() > 0.6, "rain is overcast")
	ok(WorldClock.ground_fog_alpha() > 0.05)
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	ok(WorldClock.ground_fog_alpha() >= 0.3, "thick fog rolls on the ground")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	almost(WorldClock.ground_fog_alpha(), 0.0, 0.001, "no ground fog indoors")
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	# The picker rotates through every state without ever repeating the current one.
	var seen := {}
	for i in 200:
		WorldClock.set_time(float(i % 4) * 0.25 + 0.05)
		var next: int = WorldClock._pick_weather()
		ok(next != WorldClock.weather, "picker never re-picks the current weather")
		ok(next >= 0 and next <= WorldClock.Weather.CLEAR, "picked weather is a legal state")
		seen[next] = true
	ok(seen.has(WorldClock.Weather.CLEAR), "clear days do come around")
	ok(seen.size() >= 5, "the picker visits most weathers over 200 rolls")


func test_wind_mote_density_follows_wind_and_zone() -> void:
	WorldClock.set_time(0.30)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock._snap_wind_speed()
	var calm := WorldClock.wind_mote_density()
	ok(calm > 0.0 and calm < 0.6, "a breeze sheds a little dust")
	WorldClock.set_weather(WorldClock.Weather.EMBER_WIND, true)
	WorldClock._snap_wind_speed()
	ok(WorldClock.wind_mote_density() > calm + 0.3, "ember wind fills the air")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	WorldClock._snap_wind_speed()
	almost(WorldClock.wind_mote_density(), 0.0, 0.001, "no wind dust indoors")
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.menu_hold = true
	almost(WorldClock.wind_mote_density(), 0.0, 0.001, "title menu has no wind dust")
	WorldClock.menu_hold = false


func test_night_rain_upgrades_to_rust_rain() -> void:
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	ok(WorldClock.is_rust_raining(), "night rain is rust rain")
	ok(WorldClock.rust_rain_mix() > 0.8)
	WorldClock.set_time(0.30)
	ok(not WorldClock.is_rust_raining(), "day rain stays ordinary rain")


func test_ember_wind_has_particle_weight() -> void:
	WorldClock.set_weather(WorldClock.Weather.EMBER_WIND, true)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	almost(WorldClock.ember_wind_opacity(), 1.0, 0.001)
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	almost(WorldClock.ember_wind_opacity(), 0.0, 0.001, "embers stay outside")


func test_isolate_does_not_unhide_flash_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "JuiceFlash"
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "Flash"
	rect.color = Color(1, 1, 1, 1)
	rect.modulate.a = 0.0
	layer.add_child(rect)
	WorldClock.isolate_ui_layer(layer)
	almost(rect.modulate.a, 0.0, 0.001, "isolate must not un-hide Juice flash")
	almost(rect.modulate.r, 1.0, 0.001)
	almost(rect.modulate.g, 1.0, 0.001)
	almost(rect.modulate.b, 1.0, 0.001)


func test_hud_stays_readable_at_night() -> void:
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	var host := Node2D.new()
	add_child(host)
	var backdrop := CanvasLayer.new()
	backdrop.name = "ParallaxBackdrop"
	host.add_child(backdrop)
	var extras := Level01Parallax.new()
	add_child(extras)
	extras.build(host)
	const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	host.add_child(hud)
	await flush(2)
	WorldClock.isolate_ui_layer(hud)
	ok(hud.layer >= 10)
	ok(not hud.follow_viewport_enabled, "HUD is its own canvas")
	var root := hud.get_node_or_null("Root") as CanvasItem
	ok(root != null, "HUD draws on a CanvasItem child")
	if root != null:
		eq(root.modulate, Color.WHITE, "HUD root does not inherit night")
	var tint := host.get_node_or_null("MoodTint") as CanvasModulate
	ok(tint != null)
	if tint != null:
		ok(absf(tint.color.r - 1.0) > 0.15, "world MoodTint is actually night")
		if root != null:
			ok(absf(tint.color.r - root.modulate.r) > 0.15, "HUD does not follow night MoodTint")
	var pause := hud.get_node_or_null("PauseMenu") as CanvasLayer
	ok(pause != null)
	if pause != null:
		ok(pause.layer >= 10, "pause sits above the world canvas")
		ok(not pause.follow_viewport_enabled)
	var cap := Director.caption()
	var cap_layer := cap.get_parent() as CanvasLayer
	ok(cap_layer != null, "caption lives on a CanvasLayer")
	if cap_layer != null:
		ok(cap_layer.layer >= 10)
		eq(cap.modulate, Color.WHITE, "caption stays off MoodTint")


func test_outdoor_breeze_is_alive() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock._snap_wind_speed()
	ok(WorldClock.wind_speed > 0.12, "haze still has a standing breeze")
	ok(WorldClock.is_breeze_active())
	ok(absf(WorldClock.sway_radians()) > 0.001)


func test_indoor_wind_dies() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock._snap_wind_speed()
	ok(WorldClock.wind_speed > 0.3)
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	WorldClock.advance(2.0)
	almost(WorldClock.wind_speed, 0.0, 0.03, "indoor wind fades out")
	almost(WorldClock.sway_radians(), 0.0, 0.01)


func test_rain_wind_stronger_than_fog() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	WorldClock._snap_wind_speed()
	var fog := WorldClock.wind_speed
	WorldClock.set_weather(WorldClock.Weather.RAIN, true)
	WorldClock._snap_wind_speed()
	ok(WorldClock.wind_speed > fog + 0.12, "rain lifts the breeze")


func test_frozen_clock_holds_gust() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.advance(1.5)
	var g0 := WorldClock.gust
	var h0 := WorldClock.wind_heading
	get_tree().paused = true
	WorldClock._process(4.0)
	almost(WorldClock.gust, g0, 0.0001, "paused gust does not walk")
	almost(WorldClock.wind_heading, h0, 0.0001)
	get_tree().paused = false


func test_sky_seed_rolls_per_visit() -> void:
	var a := WorldClock.roll_sky_seed()
	ok(a != 0, "sky seed is usable")
	eq(WorldClock.sky_seed(), a, "sky_seed() matches the last roll")
	var b := WorldClock.roll_sky_seed()
	if b == a:
		b = WorldClock.roll_sky_seed()
	ok(b != 0)
	eq(WorldClock.sky_seed(), b)


func test_save_roundtrip_zone_and_heading() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena)
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	WorldClock.wind_heading = 1.0
	WorldClock._heading_target = 1.0
	ok(SaveData.save_game("res://scenes/levels/Level01_Static.tscn", player))
	WorldClock.reset()
	eq(WorldClock.zone, WorldClock.Zone.OUTDOORS)
	ok(SaveData.load_game())
	eq(WorldClock.zone, WorldClock.Zone.INDOORS, "load restores indoor")
	almost(WorldClock.wind_heading, 1.0, 0.01, "load restores heading")


const CYCLE_CROSS := 30.0
