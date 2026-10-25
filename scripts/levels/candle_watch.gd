extends Area2D
## 烛光桥的感应圈：骑士站进来，旁边的台阶才现形、才有碰撞。
## 离开就收回。主路不靠这块台阶，所以它灭着的时候关卡照样走得通。

var step: Node2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	if get_child_count() == 0:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(96.0, 72.0)
		shape.shape = rect
		add_child(shape)
	body_entered.connect(_set_lit.bind(true))
	body_exited.connect(_set_lit.bind(false))
	_set_lit(false)
	call_deferred("_set_lit", false)


func _set_lit(on: bool) -> void:
	if step == null or not is_instance_valid(step):
		return
	step.visible = on
	if step is CollisionObject2D:
		(step as CollisionObject2D).set_collision_layer_value(1, on)
