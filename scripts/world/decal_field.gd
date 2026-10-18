extends Node2D
## 一个世界一份的打击痕迹容器：环形复用，超过上限收最老的。
##
## 上限与 CombatRules.BUDGET[&"decals"] 对齐（24）。痕迹只是表现，不参与碰撞、
## 不写存档；关卡重载时它随 WorldEffects 一起消失。headless 下也能建（画不出来
## 也无所谓），测试直接数格子/复用次数。

const ImpactDecal := preload("res://scripts/world/impact_decal.gd")

const MAX_DECALS := 24
const DECAL_Z := 1

var _entries: Array = []
var _cursor := 0
var _total := 0
var _recycled := 0


func _ready() -> void:
	name = "ImpactDecals"
	z_index = DECAL_Z


## 留一块痕迹；返回被复用的节点，便于测试。
func add(kind: StringName, material: StringName, pos: Vector2, normal: Vector2,
		weight_scale: float = 1.0) -> Node2D:
	_total += 1
	var decal: Node2D = null
	if _entries.size() < MAX_DECALS:
		decal = ImpactDecal.new()
		add_child(decal)
		_entries.append(decal)
	else:
		_recycled += 1
		decal = _entries[_cursor] if is_instance_valid(_entries[_cursor]) else null
		if decal == null:
			decal = ImpactDecal.new()
			add_child(decal)
		_entries[_cursor] = decal
		_cursor = (_cursor + 1) % MAX_DECALS
	decal.call(&"setup", kind, pos, normal, weight_scale)
	return decal


func count() -> int:
	var n := 0
	for entry in _entries:
		if is_instance_valid(entry) and not (entry as Node).is_queued_for_deletion():
			n += 1
	return n


func total_added() -> int:
	return _total


func recycled() -> int:
	return _recycled


func clear_all() -> void:
	for entry in _entries:
		if is_instance_valid(entry):
			(entry as Node).queue_free()
	_entries.clear()
	_cursor = 0
	_total = 0
	_recycled = 0
