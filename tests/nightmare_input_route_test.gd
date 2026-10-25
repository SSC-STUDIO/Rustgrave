extends TestCase
## Geometry regression for the input driver's finale. Real combat/persistence
## runs in NightmareInputFixture; this case rejects embedded/obsolete waypoints.

const LAYOUT := preload("res://scripts/levels/chapters/level10_layout.gd")

class RouteProbe extends "res://tools/campaign_walkthrough.gd":
	var host: Node2D
	var knight: Player

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _world() -> Node:
		return host

	func _world_root() -> Node:
		return host

	func _player() -> Player:
		return knight


func setup() -> void:
	SaveData.delete_save()
	Director.abort()
	Director._set_lock(false)


func teardown() -> void:
	SaveData.delete_save()
	Director.abort()
	Director._set_lock(false)
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _build_probe() -> RouteProbe:
	var host := Node2D.new()
	host.name = "Level10_ForgeCore"
	host.scene_file_path = GameContext.LEVELS["level10"]
	host.add_to_group("game_world")
	add_child(host)
	var layout := LAYOUT.new() as ChapterLayout
	add_child(layout)
	layout.build(host)
	# This is a geometry-only test. The independent fixture keeps all AI live.
	host.process_mode = Node.PROCESS_MODE_DISABLED
	var knight := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Player
	knight.position = Vector2(2176, 320)
	host.add_child(knight)
	var probe := RouteProbe.new()
	probe.host = host
	probe.knight = knight
	add_child(probe)
	return probe


func test_ring_and_return_goals_fit_the_full_knight_between_pillars_and_dais() -> void:
	var probe := _build_probe()
	var solids := LevelSanity.solid_rects(probe.host)
	var initial_feet := probe.knight.position
	var initial_hp := probe.knight.health.current
	for name_ in ["RingGalleryWest", "RingGalleryInnerWest", "RingGalleryInnerEast", "RingGalleryEast", "RingStairEastMid", "RingStairEastLow", "RingStairWestMid", "RingStairWestLow", "ReturnE"]:
		var platform := probe.host.get_node("Platforms/" + name_) as SolidPlatform
		for rightmost in [true, false]:
			var feet := probe._nightmare_ring_feet(name_, rightmost)
			ok(feet.is_finite(), name_ + " has an authored target")
			ok(absf(feet.y - platform.position.y) < 0.1 and feet.x >= platform.position.x + 7.0 and feet.x <= platform.position.x + platform.size.x - 7.0, name_ + " supports the whole knight")
			var body := Rect2(feet - Vector2(7, 26), Vector2(14, 26)).grow(-0.1)
			var clear := true
			for solid in solids:
				if solid.intersects(body): clear = false
			ok(clear, name_ + " leaves headroom clear of pillars/dais")
	eq(probe.knight.position, initial_feet, "geometry observation does not move the knight")
	eq(probe.knight.health.current, initial_hp, "geometry observation does not heal the knight")
	ok(not SaveData.has_flag("nightmare_dead"), "geometry observation does not award progress")


func test_ring_target_follows_moved_authored_geometry_instead_of_old_finale_coordinates() -> void:
	var probe := _build_probe()
	var before := probe._nightmare_ring_feet("RingGalleryEast")
	var shift := Vector2(144, -16)
	for name_ in ["RingGalleryEast", "PillarSeat4"]:
		(probe.host.get_node("Platforms/" + name_) as Node2D).position += shift
	eq(probe._nightmare_ring_feet("RingGalleryEast"), before + shift, "route tracks the actual clear gallery span")
	ok(not probe._nightmare_ring_feet("missing_ring").is_finite(), "missing geometry is rejected before navigation")
