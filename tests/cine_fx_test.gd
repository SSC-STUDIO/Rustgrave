extends TestCase


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false


func teardown() -> void:
	WorldClock.reset()


func test_indoor_hides_mid_motes() -> void:
	var fx := CineFx.new()
	add_child(fx)
	eq(fx.z_index, -1, "depth dust stays behind the knight")
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)
	WorldClock._snap_wind_speed()
	ok(fx.mid_motes_allowed(), "outdoor breeze carries scrap")
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	WorldClock._snap_wind_speed()
	ok(not fx.mid_motes_allowed(), "indoor leaves the mid layer off")


func test_shaft_stronger_at_night() -> void:
	var fx := CineFx.new()
	add_child(fx)
	WorldClock.set_time(0.28)
	var day := fx.shaft_alpha()
	WorldClock.set_time(0.80)
	ok(fx.shaft_alpha() > day + 0.08, "night moon shaft is brighter")
	WorldClock.hold_for_menu()
	almost(fx.shaft_alpha(), 0.0, 0.001, "title holds the shaft")
