extends TestCase

const PEEK := preload("res://tools/peek_live.gd")


func test_parked_knight_uses_real_raised_and_sunken_support() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Raised", Vector2(0, 288), 128.0)
	layout.step(host, "Sunken", Vector2(128, 352), 128.0)
	eq(PEEK.park_feet(host, Vector2(64, 320)), Vector2(64, 288))
	eq(PEEK.park_feet(host, Vector2(192, 320)), Vector2(192, 352))


func test_parked_knight_never_embeds_in_a_cover_plinth() -> void:
	var host := Node2D.new()
	add_child(host)
	var layout := ChapterLayout.new()
	add_child(layout)
	layout.step(host, "Floor", Vector2(0, 320), 256.0)
	layout.platform(host, "Cover", Vector2(96, 288), Vector2(64, 32))
	var feet := PEEK.park_feet(host, Vector2(120, 320))
	eq(feet, Vector2(120, 288))
	var body := Rect2(feet - Vector2(7, 26), Vector2(14, 26))
	for solid in LevelSanity.solid_rects(host):
		ok(not body.intersects(solid.grow(-0.1)))


func test_no_support_is_reported_instead_of_a_floating_actor() -> void:
	var host := Node2D.new()
	add_child(host)
	ok(not PEEK.park_feet(host, Vector2(64, 320)).is_finite())
