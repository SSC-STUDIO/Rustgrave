class_name WeatherRegion
extends Area2D
## 一片局部天气：这条街、这个天井、这段垛口此刻是另一副天。
##
## 和 AtmosphereZone 同一套路子，但它不改"室内外"，只往 WorldClock 的区域栈里压一格：
##   · weather    这一片强制显示哪种天气（-1 = 沿用基础天气）
##   · intensity  这一片的强度 0..1（0 = 有云无雨）
##   · wind_scale 风力倍率（避风的矮墙下 0.3，垛口上 1.4）
##
## 栈是后进先出的，重叠区域由后进的那片说了算。用位置轮询而不是 body_entered：
## 读档/重生会传送玩家，传送那帧不产生信号，区域就漏触发。

## -1 = 沿用基础天气（这一片只改强度/风力）。
@export var weather: int = -1
@export_range(0.0, 1.0, 0.05) var intensity: float = 1.0
@export_range(0.0, 2.0, 0.05) var wind_scale: float = 1.0
## 区域矩形（以本节点为左上角）。
@export var rect: Vector2 = Vector2(320, 200)

var _inside: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = false
	monitorable = false
	_ensure_shape()


func _physics_process(_delta: float) -> void:
	var player := _find_player()
	if player == null:
		return
	var now := contains_point(player.global_position)
	if now == _inside:
		return
	_inside = now
	if now:
		WorldClock.enter_weather_region(StringName(name), spec())
	else:
		WorldClock.leave_weather_region(StringName(name))


## 位置是区域左上角，形状从节点原点铺到 +rect。
func _ensure_shape() -> void:
	var shape := get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		shape = CollisionShape2D.new()
		shape.name = "Shape"
		add_child(shape)
	if rect.x > 0.0 and rect.y > 0.0:
		var box := RectangleShape2D.new()
		box.size = rect
		shape.shape = box
		shape.position = rect * 0.5


func spec() -> Dictionary:
	return {"weather": weather, "intensity": intensity, "wind_scale": wind_scale}


func world_rect() -> Rect2:
	return Rect2(global_position, rect)


func contains_point(world: Vector2) -> bool:
	return world_rect().has_area() and world_rect().has_point(world)


func _find_player() -> Node2D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Node2D
