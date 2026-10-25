class_name GearPlatform
extends StaticBody2D
## Small hovering stone foothold (octagon collision, church slab block).
## 悬空物件走"石造台子"皮肤家族，与接地的草顶土地明确区分。

@export var radius: float = 16.0
@export var fill: Color = Color("#2a1e32")
## Material family of the chapter (iron, basalt, rampart, brick, castle ...). When
## assets/env/<family>_float_small.png exists the block is drawn from it, so a
## workshop's stepping stones are rust iron instead of lavender church slab.
@export var family: String = ""

const BLOCK_PATH := "res://assets/env/float_small.png"
const FLOAT_TONE := Color(0.82, 0.8, 0.95)
const WORLD := 16.0


func setup(pos: Vector2, r: float) -> void:
	position = pos
	radius = r


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var pts := PackedVector2Array()
	for i in 8:
		var a := deg_to_rad(22.5 + float(i) * 45.0)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	_build_visual()
	var col := CollisionPolygon2D.new()
	col.polygon = pts
	add_child(col)
	var occluder := LightOccluder2D.new()
	occluder.name = "LightOccluder"
	var occ := OccluderPolygon2D.new()
	occ.polygon = pts
	occluder.occluder = occ
	add_child(occluder)


## Themed block path + tone for this chapter family; the church block is the fallback.
func _block_choice() -> Array:
	if family != "":
		var themed := "res://assets/env/%s_float_small.png" % family
		if ResourceLoader.exists(themed):
			return [themed, Color.WHITE]
	return [BLOCK_PATH, FLOAT_TONE]


func _build_visual() -> void:
	var choice := _block_choice()
	var block_path: String = choice[0]
	if ResourceLoader.exists(block_path):
		var tex := DensityTextures.load_texture(block_path)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 八边形碰撞顶边在 y≈-0.92*radius；石台顶面与其对齐。
		var s := (radius * 2.0) / float(tex.get_width())
		spr.scale = Vector2(s, s)
		spr.position = Vector2(-radius, -0.92 * radius)
		spr.modulate = choice[1]
		add_child(spr)
		return
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 8:
		var a := deg_to_rad(22.5 + float(i) * 45.0)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	poly.color = fill
	add_child(poly)
