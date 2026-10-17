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
	# The hall strip's base is the bottom of the art. A vertical copy would
	# stand that base in the shaft, which is the floating-wall bug.
	_assert_single_grounded_strip(host.get_node("ParallaxBackdrop/Layer0"), 320.0, "hall")
	_assert_single_grounded_strip(host.get_node("ParallaxBackdrop/Layer1"), 336.0, "column")


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


func _assert_single_grounded_strip(layer: Node, base_y: float, label: String) -> void:
	var sprites := 0
	for child in layer.get_children():
		if child is Sprite2D:
			sprites += 1
			var spr := child as Sprite2D
			var bottom := spr.position.y + spr.get_rect().size.y * absf(spr.scale.y)
			almost(bottom, base_y, 1.0, "%s strip base stays on the ground line" % label)
	eq(sprites, 1, "%s strip is not copied up the shaft" % label)
