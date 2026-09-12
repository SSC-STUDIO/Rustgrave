extends TestCase

class TallLayout extends ChapterLayout:
	func camera_top() -> int: return -832
	func theme() -> String: return "cathedral"


func teardown() -> void:
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func test_tall_room_covers_top_landing_with_indoor_zone_and_backdrop() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := TallLayout.new()
	add_child(layout)
	layout.finish(host)
	var col := host.get_node("IndoorZone").get_child(0) as CollisionShape2D
	var rect := Rect2(col.position - col.shape.size * 0.5, col.shape.size)
	ok(rect.has_point(Vector2(640, -680)), "tower summit stays indoors")
	ok(rect.has_point(Vector2(96, 320)), "entry stays indoors")
	var wall := host.get_node("ParallaxBackdrop/Layer0")
	ok(wall.get_child_count() > 3, "wall panels also cover the upper floors")


func test_hook_is_optional_and_ceiling_is_not_a_walkable_shortcut() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Start", Vector2(64, 320), 96)
	layout.step(host, "Goal", Vector2(96, 160), 96)
	layout.step(host, "Ceiling", Vector2(0, -32), 1280)
	layout.hook(host, "Anchor", Vector2(144, 96))
	ok(LevelSanity.is_reachable(host, Vector2(96, 300), Vector2(160, 160)), "legacy check allows a hook")
	ok(not LevelSanity.is_reachable(host, Vector2(96, 300), Vector2(160, 160), false), "single jump cannot gain 160px")
	for top in LevelSanity.top_segments(host):
		ok(top.owner_name != "Ceiling", "roof is not a landing")
