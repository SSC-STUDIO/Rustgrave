extends Area2D
## 章节入场边界：巢前不启动唱诗班，跨进场地才交回原 Boss/Director。

var boss_ref: EnemyBase
var arena_left := 0.0
var arena_right := 0.0
var floor_y := 320.0
var triggered := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(arena_right - arena_left, 240)
	shape.shape = rect
	shape.position = Vector2((arena_left + arena_right) * 0.5, floor_y - 80)
	add_child(shape)
	body_entered.connect(_on_entered)


func _on_entered(body: Node2D) -> void:
	if triggered or not body.is_in_group(&"player") or not is_instance_valid(boss_ref):
		return
	triggered = true
	boss_ref.set_physics_process(true)
	if boss_ref.has_method("announce"):
		boss_ref.call("announce")
