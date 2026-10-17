extends TestCase
## WorldLight pools carve a darker night; moon fill and indoor warmth stay secondary.


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false
	SaveData.flags.clear()
	Director.abort()
	Director.choice_hold = false


func teardown() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false
	SaveData.flags.clear()
	Director.abort()
	Director.choice_hold = false


func test_outdoor_night_luminance_is_a_corridor() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock.set_time(0.80)
	var lum := WorldClock.mood_luminance()
	ok(lum >= 0.30 and lum <= 0.40, "haze night sits in the carve band")
	WorldClock.set_weather(WorldClock.Weather.FOG, true)
	ok(WorldClock.mood_luminance() >= 0.28, "fog night is darker but not black")
	var c := WorldClock.mood_tint()
	ok(c.r >= 0.28 and c.g >= 0.28 and c.b >= 0.28)


func test_moon_fill_is_weaker_than_nest() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_time(0.28)
	almost(WorldClock.moon_fill_energy(), 0.0, 0.001, "day moon fill is off")
	WorldClock.set_time(0.80)
	ok(WorldClock.moon_fill_energy() > 0.05, "night moon fill is a silhouette")
	ok(WorldClock.moon_fill_energy() < WorldClock.nest_light_energy() * 0.20,
			"moon fill never covers the nest")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	almost(WorldClock.moon_fill_energy(), 0.0, 0.001, "indoor drops moonlight")


func test_unlit_nest_emits_nothing() -> void:
	var nest := EmberNest.new()
	add_child(nest)
	await flush(1)
	var light := nest.get_node_or_null("NestLight") as WorldLight
	ok(light != null, "nest hosts a WorldLight")
	if light == null:
		return
	ok(not light.lit)
	ok(not light.enabled)
	almost(light.energy, 0.0, 0.001)
	var halo := nest.get_node_or_null("Halo") as Sprite2D
	ok(halo != null)
	if halo != null:
		ok(not halo.visible)


func test_lit_nest_night_is_stronger_than_day() -> void:
	var nest := EmberNest.new()
	add_child(nest)
	await flush(1)
	var light := nest.get_node_or_null("NestLight") as WorldLight
	ok(light != null)
	if light == null:
		return
	WorldClock.set_time(0.80)
	nest.apply_persistent_state({"lit": true})
	ok(light.lit)
	ok(light.enabled)
	ok(light.shadow_enabled)
	var night_e := light.energy
	WorldClock.set_time(0.28)
	nest.apply_persistent_state({"lit": true})
	ok(night_e > light.energy + 0.40)
	ok(light.energy >= 1.0, "day pool is visible")
	var halo := nest.get_node_or_null("Halo") as Sprite2D
	ok(halo != null and halo.visible, "lit nest shows an additive halo")


func test_forge_shelter_has_warm_pool() -> void:
	var host := Node2D.new()
	add_child(host)
	var shelter := Level01EastWing.place_forge_shelter(host)
	ok(shelter != null)
	var pool := shelter.get_node_or_null("WarmPool") as WorldLight
	ok(pool != null, "shelter carries an indoor WorldLight")
	if pool == null:
		return
	eq(pool.follow, &"indoor")
	ok(pool.lit)
	await flush(1)
	ok(pool.enabled)
	almost(pool.energy, WorldClock.indoor_fill_energy(), 0.02)


func test_heart_light_follows_lock() -> void:
	var heart := ForgeHeart.new()
	add_child(heart)
	await flush(1)
	var glow := heart.get_node_or_null("HeartLight") as WorldLight
	ok(glow != null, "heart hosts a WorldLight")
	if glow == null:
		return
	ok(not glow.lit, "locked heart is dark")
	ok(not glow.enabled)
	almost(glow.energy, 0.0, 0.001)
	heart.unlock()
	ok(glow.lit)
	ok(glow.enabled)
	almost(glow.energy, WorldClock.heart_light_energy(), 0.02)
	heart.lock()
	ok(not glow.lit)
	almost(glow.energy, 0.0, 0.001)


func test_parallax_plants_moon_fill() -> void:
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
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
	var moon := host.get_node_or_null("MoonFill") as DirectionalLight2D
	ok(moon != null, "parallax plants MoonFill")
	if moon != null:
		ok(moon.energy > 0.05)
		ok(moon.energy < 0.25)
	var hud_scene := load("res://scenes/ui/HUD.tscn") as PackedScene
	ok(hud_scene != null)
	var hud: CanvasLayer = hud_scene.instantiate()
	host.add_child(hud)
	await flush(1)
	WorldClock.isolate_ui_layer(hud)
	var root := hud.get_node_or_null("Root") as CanvasItem
	ok(root != null)
	if root != null:
		eq(root.modulate, Color.WHITE, "HUD stays off the dark corridor")


func test_shrine_does_not_emit_fire() -> void:
	var shrine := PurificationShrine.new()
	add_child(shrine)
	await flush(1)
	ok(shrine.get_node_or_null("WorldLight") == null)
	ok(shrine.find_child("HeartLight", true, false) == null)
	ok(shrine.find_child("NestLight", true, false) == null)
	for child in shrine.get_children():
		ok(not (child is PointLight2D), "purification shrine has no point light")


## Regression: a free-running light (torch, fire skull, ghost) used to read its own
## flickered `energy` back as the target, compounding every frame until it was black.
func test_free_running_flicker_never_decays() -> void:
	var host := Node2D.new()
	add_child(host)
	var light := WorldLight.new()
	light.follow = &"torch"
	light.lit = true
	light.flicker = true
	light.energy = 0.6
	host.add_child(light)
	for frame in 4000:
		light.set_flame_frame(frame % 8)
		light.apply(false)
	ok(light.energy >= 0.6 * 0.91 and light.energy <= 0.6 * 1.09,
			"after 4000 frames the torch is still ~0.6 (got %f)" % light.energy)
	ok(light.enabled, "still lit")
	light.set_base_energy(0.3)
	light.set_flame_frame(7)
	light.apply(false)
	ok(absf(light.energy - 0.3 * 1.08) < 0.002, "retuned base is honoured")
	host.queue_free()
