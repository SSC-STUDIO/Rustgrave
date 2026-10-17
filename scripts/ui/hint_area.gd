class_name HintArea
extends Area2D
## 关卡作者放置的"走到这里给一行提示"区域。
##
## 在关卡里摆一个 HintArea（或把它挂进 Props），填 hint_id 与 text，走进去即触发；
## 提示统一经 HUD 的 HintService 排队（同一时刻只一条、不叠放、每个存档一次）。
## text 可含 {attack} {jump} {dash} {interact} {socket_1} {socket_2} {hookshot}
## {move_left} {move_right} 占位，显示时换成玩家当前键位。
## hint_id 与 HintService.CATALOG 同名时 text 可留空（沿用内置文案）。
##
## 没有碰撞形状子节点时按 `size` 自动生成一个矩形（原点在矩形中心）。

@export var hint_id: StringName = &""
@export_multiline var text: String = ""
## true：每个存档只触发一次；false：可重复，但同一条间隔 HintService.REPEAT_COOLDOWN 秒。
@export var once: bool = true
@export var size: Vector2 = Vector2(48.0, 96.0)

var _fired := false


func _ready() -> void:
	# 只探测骑士本体（碰撞层 2）。区域自己不被任何东西探测。
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	if not _has_shape():
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		add_child(shape)
	body_entered.connect(_on_body_entered)


func _has_shape() -> bool:
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			return true
	return false


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	trigger()


## 测试与脚本也可以直接调用。返回 true 表示提示已交给 HintService。
func trigger() -> bool:
	if hint_id == &"":
		return false
	if once and _fired:
		return false
	var service := get_tree().get_first_node_in_group(HintService.GROUP) as HintService
	if service == null:
		return false
	var accepted := service.offer(hint_id, text, once)
	if accepted and once:
		_fired = true
	return accepted
