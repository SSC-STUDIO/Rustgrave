class_name AtmosphereZone
extends Area2D
## Reusable indoor / outdoor trigger. Clock keeps running; WorldClock.zone
## only swaps lighting + weather particles. Future rooms call the same API.
##
## 用轮询而不是 body_entered：读档、重生、Boss 特写都会把玩家**传送**进场景，
## 传送那一帧不产生 body_entered，区域就漏触发（露天天井不进雨、室内区不压暗）。
## 这里以玩家位置为准，每物理帧对一次，进出都稳，也不依赖物理层配置。

@export var zone: int = 1
## 出这片区域且没有别的区域接着时回到哪一层。-1 = 回到本关基础层（推荐）；
## 0/1 = 强制室外/室内。室内关整关的 IndoorZone 用默认值即可：出栈后仍是室内。
@export var restore_zone: int = -1

var _inside: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = false
	monitorable = false


func _physics_process(_delta: float) -> void:
	var player := _find_player()
	if player == null:
		return
	var now := contains_point(player.global_position)
	if now == _inside:
		return
	_inside = now
	if now:
		WorldClock.enter_zone(zone)
	else:
		WorldClock.leave_zone(restore_zone, zone)


## 世界坐标点是否落在本区域的第一个矩形碰撞盒里。
func contains_point(world: Vector2) -> bool:
	var rect := world_rect()
	if not rect.has_area():
		return false
	return rect.has_point(world)


## 第一个 CollisionShape2D + RectangleShape2D 换算成世界矩形。
func world_rect() -> Rect2:
	for child in get_children():
		var col := child as CollisionShape2D
		if col == null:
			continue
		var box := col.shape as RectangleShape2D
		if box == null:
			continue
		var center := col.global_position
		return Rect2(center - box.size * 0.5, box.size)
	return Rect2()


func _find_player() -> Node2D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Node2D
