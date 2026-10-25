class_name MovingPlatform
extends AnimatableBody2D
## 地窟吊台：一块苔石板吊在两根锈链上，在 `start`（自身初始位置）和 start+travel
## 之间往返；两端用余弦缓入缓出，骑士站上去不会被甩。sync_to_physics 让引擎把
## 平台速度传给站在上面的 CharacterBody2D。

const WORLD := 16.0
const CHAIN_COLOR := Color(0.16, 0.2, 0.18)
const CHAIN_HIGHLIGHT := Color(0.34, 0.4, 0.34)

## 位移向量（像素），从初始位置出发。
@export var travel: Vector2 = Vector2(128, 0)
## 一个完整往返的秒数。
@export var period: float = 5.0
## 起始相位（0..1），让相邻吊台错开。
@export var phase: float = 0.0
@export var width: float = 64.0
## 链条挂到的高度（世界 y）；<= start.y 才画链。
@export var chain_top_y: float = -32.0

var _start: Vector2
var _t: float = 0.0
var _last_pos: Vector2


func _ready() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0
	_start = position
	_t = phase * period
	_last_pos = position
	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, WORLD)
	col.shape = shape
	col.position = Vector2(width * 0.5, WORLD * 0.5)
	add_child(col)
	_build_visual()
	position = position_at(_t)


## 位置随时间：余弦往返，t 以秒计。
func position_at(t: float) -> Vector2:
	if period <= 0.001:
		return _start
	var k := 0.5 - 0.5 * cos(TAU * t / period)
	return _start + travel * k


func start_position() -> Vector2:
	return _start


func end_position() -> Vector2:
	return _start + travel


func _physics_process(delta: float) -> void:
	_t += delta
	_last_pos = position
	position = position_at(_t)
	_update_chains()


func _build_visual() -> void:
	var left := _tex(SolidPlatform.MOSS_FLOAT_LEFT)
	var mid := _tex(SolidPlatform.MOSS_FLOAT_MID)
	var right := _tex(SolidPlatform.MOSS_FLOAT_RIGHT)
	if left == null or mid == null or right == null:
		var rect := ColorRect.new()
		rect.name = "VisualRect"
		rect.size = Vector2(width, WORLD)
		rect.color = Color("#2f4a3a")
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
	else:
		var x := 0.0
		while x < width - 0.01:
			var tex := mid
			if x < 0.01:
				tex = left
			elif x + WORLD >= width - 0.01:
				tex = right
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(x, 0.0)
			spr.z_index = -1
			spr.modulate = SolidPlatform.MOSS_TONE
			add_child(spr)
			x += WORLD
	for i in 2:
		var chain := Line2D.new()
		chain.name = "Chain%d" % i
		chain.width = 2.0
		chain.default_color = CHAIN_COLOR
		chain.z_index = -2
		add_child(chain)
		var glint := Line2D.new()
		glint.name = "Glint%d" % i
		glint.width = 1.0
		glint.default_color = CHAIN_HIGHLIGHT
		glint.z_index = -2
		add_child(glint)
	_update_chains()


func _update_chains() -> void:
	for i in 2:
		var chain := get_node_or_null("Chain%d" % i) as Line2D
		var glint := get_node_or_null("Glint%d" % i) as Line2D
		if chain == null:
			continue
		var x := 6.0 if i == 0 else width - 6.0
		var top := chain_top_y - position.y
		if top >= 0.0:
			chain.visible = false
			if glint != null:
				glint.visible = false
			continue
		chain.visible = true
		chain.points = PackedVector2Array([Vector2(x, 2.0), Vector2(x, top)])
		if glint != null:
			glint.visible = true
			glint.points = PackedVector2Array([Vector2(x - 0.5, 2.0), Vector2(x - 0.5, top)])


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return ArtTexture.load_texture(path)
	return null
