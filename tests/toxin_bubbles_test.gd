extends TestCase
## 毒池气泡：用户报告「明明没下雨，水面还有雨滴/扩散特效」。
## 真相是毒池每 0.4s 冒的"气泡"用了彩色魔法粒子表并缩到 0.06–0.1 倍，
## 缩小后是乱码白点、还会被误读成雨滴涟漪。现在改成整数像素的上浮泡。
## 断言：不再缩放贴图、只朝上、坐标取整、寿命有限。

func test_bubble_is_a_pixel_drawn_node_not_a_scaled_sheet() -> void:
	var bubble: Node2D = Fx.ToxinBubble.new(Color(0.55, 0.95, 0.62))
	ok(not (bubble is Sprite2D), "bubbles are drawn with _draw, not a downscaled spritesheet")
	eq(bubble.scale, Vector2.ONE, "no fractional scaling")
	eq(bubble.z_index, 3, "bubble sits above the pool film")
	bubble.position = Vector2(100, 300)
	add_child(bubble)
	await flush(3)
	ok(is_instance_valid(bubble), "bubble survives its first frames")
	bubble.queue_free()


func test_bubble_rises_straight_up_at_integer_pixels_and_expires() -> void:
	var bubble: Node2D = Fx.ToxinBubble.new(Color(0.55, 0.95, 0.62))
	bubble.position = Vector2(100.0, 300.0)
	add_child(bubble)
	var y0 := bubble.position.y
	var life := float(bubble.get("_lifetime"))
	ok(life > 0.5 and life < 2.0, "bubble lifetime stays short (%.2fs)" % life)
	# headless 里物理帧间隔极小、_process 的 delta 不稳定；直接按固定步长驱动。
	for _i in 10:
		bubble.call(&"_process", 0.05)
	var up := y0 - bubble.position.y
	ok(up > 0.0, "bubble rises (moved %.1f px up)" % up)
	ok(bubble.position.x >= 98.0 and bubble.position.x <= 102.0,
			"lateral wobble stays within 2px (%.1f)" % bubble.position.x)
	ok(bubble.position.x == roundf(bubble.position.x)
			and bubble.position.y == roundf(bubble.position.y), "positions stay on the pixel grid")
	# 寿命结束后自毁。
	var guard := 0
	while is_instance_valid(bubble) and guard < 60:
		bubble.call(&"_process", 0.1)
		guard += 1
	ok(not is_instance_valid(bubble) or bubble.is_queued_for_deletion(), "bubble frees itself")
