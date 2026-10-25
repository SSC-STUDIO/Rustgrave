extends Sprite2D
## 8 帧炉火条（16×24）。只做整数倍缩放，过滤保持最近邻。

const FLAME := "res://assets/fx/shrine_flame.png"
const FRAME_W := 16
const FRAME_H := 24
const FRAMES := 8

var _acc := 0.0
var _frame := 0


func _ready() -> void:
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(FLAME):
		texture = load(FLAME) as Texture2D
	region_enabled = true
	region_rect = Rect2(0, 0, FRAME_W, FRAME_H)
	material = Fx.additive_mat()
	_frame = int(position.x) % FRAMES
	region_rect = Rect2(_frame * FRAME_W, 0, FRAME_W, FRAME_H)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.09:
		return
	_acc = 0.0
	_frame = (_frame + 1) % FRAMES
	region_rect = Rect2(_frame * FRAME_W, 0, FRAME_W, FRAME_H)
