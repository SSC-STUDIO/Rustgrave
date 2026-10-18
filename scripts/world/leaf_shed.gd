class_name LeafShed
extends Node2D
## 树冠落叶：每隔几秒从冠层掉一片 2px 枯叶，随风侧漂、忽扁忽竖地翻，
## 落到脚线后化进土里。纯表现；坐标取整；headless 不生成。
## 挂在种树的图层上（不是摇摆枢轴下），叶子才不会跟着树一起摆。

const MAX_LEAVES := 3
## 枯叶 / 锈叶：要比紫黑的墓园底亮一档，2px 的叶子才读得出来。
const LEAF_TINTS: Array[Color] = [
	Color(0.66, 0.44, 0.22),
	Color(0.58, 0.36, 0.18),
	Color(0.70, 0.34, 0.20),
	Color(0.52, 0.48, 0.22),
]

## 冠层宽 / 冠层顶到脚线的高度（像素，按种植缩放后）。
var canopy: Vector2 = Vector2(80.0, 60.0)

var _accum := 0.0
var _next := 2.0
var _headless := false
## Parked while the clock is frozen (pause / cinematic / fade): a shed with no
## leaves in flight has nothing to spawn, and `_process` on every tree in the
## level is dispatch cost for nothing.
var _parked := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_next = randf_range(1.5, 4.0)


func _process(delta: float) -> void:
	if _headless:
		return
	var frozen := WorldClock.is_frozen()
	if frozen:
		# Leaves in flight keep falling while frozen? No — the clock is what
		# drives wind and drift, so a frozen world holds them too.
		if not _parked:
			_parked = true
			for child in get_children():
				if child is Leaf:
					(child as Leaf).park()
		return
	if _parked:
		_parked = false
		for child in get_children():
			if child is Leaf:
				(child as Leaf).resume()
	_accum += delta
	if _accum < _next:
		return
	_accum = 0.0
	# 风大掉得勤：静风 1.8–4.2s 一片，满风约快一倍。一棵树同时最多 3 片。
	var gust := clampf(0.6 + absf(WorldClock.wind_vector().x) * 1.4, 0.6, 1.4)
	_next = randf_range(1.8, 4.2) / gust
	spawn_leaf()


func spawn_leaf() -> Leaf:
	if leaf_count() >= MAX_LEAVES:
		return null
	var leaf := Leaf.new()
	leaf.position = Vector2(
		randf_range(-canopy.x * 0.35, canopy.x * 0.35),
		-canopy.y * randf_range(0.5, 0.9))
	add_child(leaf)
	return leaf


func leaf_count() -> int:
	var n := 0
	for child in get_children():
		if child is Leaf and not child.is_queued_for_deletion():
			n += 1
	return n


## 一片叶：两块多边形交替显示模拟翻转（3×1 扁 / 1×2 竖），不旋转 2px 方块。
## 运动以下落为主，横向是钟摆式来回滑翔（±SWING_AMP），风只加很小的侧漂——
## 之前风给到 26px/s，叶子像被拖着一路横着走。
class Leaf extends Node2D:
	const FADE := 0.5
	const SWING_AMP_MIN := 4.0
	const SWING_AMP_MAX := 7.0
	const SWING_RATE := 2.4
	const WIND_DRIFT := 6.0
	const WIND_DRIFT_MAX := 4.0

	var _pos := Vector2.ZERO
	var _anchor_x := 0.0
	var _vy := 16.0
	var _amp := 5.0
	var _phase := 0.0
	var _t := 0.0
	var _landed := -1.0
	var _flat: Polygon2D
	var _tall: Polygon2D
	var _parked := false


	func _init() -> void:
		_vy = randf_range(14.0, 22.0)
		_amp = randf_range(SWING_AMP_MIN, SWING_AMP_MAX)
		_phase = randf() * TAU
		var tint := LeafShed.LEAF_TINTS[randi_range(0, LeafShed.LEAF_TINTS.size() - 1)]
		_flat = Polygon2D.new()
		_flat.polygon = PackedVector2Array([
			Vector2(-1.5, -0.5), Vector2(1.5, -0.5), Vector2(1.5, 0.5), Vector2(-1.5, 0.5),
		])
		_flat.color = tint
		add_child(_flat)
		_tall = Polygon2D.new()
		_tall.polygon = PackedVector2Array([
			Vector2(-0.5, -1.0), Vector2(0.5, -1.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0),
		])
		_tall.color = tint.darkened(0.15)
		_tall.visible = false
		add_child(_tall)


	func _ready() -> void:
		_pos = position
		# Start the pendulum exactly where the leaf was spawned (no first-frame jump).
		_anchor_x = position.x - sin(_phase) * _amp
		position = _pos.round()


	func landed() -> bool:
		return _landed >= 0.0


	## Held mid-fall while the clock is frozen (pause / cinematic / fade).
	## Position and age stay as they are, so resuming continues the fall
	## without a jump.
	func park() -> void:
		_parked = true


	func resume() -> void:
		_parked = false


	func _process(delta: float) -> void:
		if _parked:
			return
		_t += delta
		if _landed >= 0.0:
			var k := (_t - _landed) / FADE
			if k >= 1.0:
				queue_free()
				return
			modulate.a = 1.0 - k
			return
		var wind := clampf(WorldClock.wind_vector().x * WIND_DRIFT, -WIND_DRIFT_MAX, WIND_DRIFT_MAX)
		_anchor_x += wind * delta
		var swing := _t * SWING_RATE + _phase
		_pos.x = _anchor_x + sin(swing) * _amp
		_pos.y += _vy * delta
		if _pos.y >= 0.0:
			_pos.y = 0.0
			_landed = _t
			_flat.visible = true
			_tall.visible = false
		else:
			# Gliding sideways shows the flat face; at the turnarounds it tips edge-on.
			var flat := absf(cos(swing)) > 0.45
			_flat.visible = flat
			_tall.visible = not flat
		position = _pos.round()
