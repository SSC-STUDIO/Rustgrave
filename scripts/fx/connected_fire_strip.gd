extends Node2D
## 连根火舌用普通混合与自发光；光晕/飞火仍由父节点单独加色。
## 两口火共享一个绘制节点，不新建逐帧精灵，也不增加PointLight2D。

static var STRIP: Texture2D = DensityTextures.load_texture("res://assets/fx/connected_flame.png")
const CELL := Vector2(32.0, 40.0)
const ROOT := Vector2(16.0, 36.0)
const FRAMES := 16
const FPS := 12.0

var origins := PackedVector2Array([Vector2.ZERO])
var levels := PackedFloat32Array([0.0])
var offsets := PackedFloat32Array([0.0])
var size_scale := 0.8
var time := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var flame_material := CanvasItemMaterial.new()
	flame_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	flame_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = flame_material


func frame_at(seconds: float, offset: float = 0.0) -> int:
	return posmod(int(floor((seconds + offset) * FPS)), FRAMES)


func _draw() -> void:
	for i in origins.size():
		var level := clampf(levels[i], 0.0, 1.4)
		if level <= 0.04:
			continue
		var factor := size_scale * (0.72 + 0.28 * minf(level, 1.2))
		var size := (CELL * factor).round()
		var root := (ROOT * size / CELL).round()
		var frame := frame_at(time, offsets[i])
		draw_texture_rect_region(STRIP, Rect2((origins[i] - root).round(), size),
				Rect2(Vector2(float(frame) * CELL.x, 0.0), CELL),
				Color(1.0, 1.0, 1.0, clampf(level * 2.8, 0.0, 1.0)))
