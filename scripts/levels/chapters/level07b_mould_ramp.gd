extends StaticBody2D
## 钟模台两侧的32/64缓坡。铸钟人不具备跳跃，坡面保留其原始地面追击。

var rises_right := true


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([Vector2(0, 32), Vector2(64, 0), Vector2(64, 32)]) if rises_right else PackedVector2Array([Vector2(0, 0), Vector2(64, 32), Vector2(0, 32)])
	add_child(shape)
	z_index = -1


func _draw() -> void:
	# 整像素水平切片与现有玄武岩钟模台衔接；碰撞仍是连续26.6°坡面。
	for y in range(32):
		var width := float(y + 1) * 2.0
		var x := 64.0 - width if rises_right else 0.0
		draw_rect(Rect2(x, y, width, 1), Color("#403630") if y % 8 != 0 else Color("#645348"))
