class_name FrameAnimSprite
extends Sprite2D
## 逐帧动画 Sprite（不依赖 SpriteFrames 资源，方便按状态机手动驱动）。
## register() 登记动作（帧列表 + fps + 循环 + 每动作基线位置），play() 切换。
## 非循环动作播完停在末帧并发一次 finished；像素素材统一 NEAREST 过滤。
##
## 基线约定：pos 由调用方按"脚底贴父节点原点"算好传入
## （centered=true 时 pos.y = -(画布高/2 - 底部透明边距)）。

signal finished(anim: StringName)

var _anims: Dictionary = {}
var _current: String = ""
var _t: float = 0.0
var _done: bool = false
var _pinned: bool = false


func _init() -> void:
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func register(anim: String, frames: Array[Texture2D], fps: float, loop: bool, pos: Vector2 = Vector2.ZERO) -> void:
	if frames.is_empty():
		return
	_anims[anim] = {"frames": frames, "fps": maxf(fps, 0.001), "loop": loop, "pos": pos}


func has_anim(anim: String) -> bool:
	return _anims.has(anim)


func current() -> String:
	return _current


## 切换动作；相同动作默认不重开（restart=true 强制从第 0 帧重播）。
func play(anim: String, restart: bool = false) -> void:
	if not _anims.has(anim):
		return
	if anim == _current and not restart:
		return
	_pinned = false
	_current = anim
	_t = 0.0
	_done = false
	var cfg: Dictionary = _anims[anim]
	position = cfg["pos"]
	texture = (cfg["frames"] as Array[Texture2D])[0]


## 动态调节 fps（攻击动画按挥砍总时长同步用）。
func set_fps(anim: String, fps: float) -> void:
	if _anims.has(anim):
		_anims[anim]["fps"] = maxf(fps, 0.001)


## 停在某一帧上，不再按 fps 往前走。挥砍用它把前摇 / 判定 / 后摇钉在对应姿势。
func pin_frame(anim: String, index: int) -> void:
	if not _anims.has(anim):
		return
	var cfg: Dictionary = _anims[anim]
	var frames: Array[Texture2D] = cfg["frames"]
	var idx := clampi(index, 0, frames.size() - 1)
	if _current != anim:
		_current = anim
		_t = 0.0
	_pinned = true
	_done = false
	position = cfg["pos"]
	var frame := frames[idx]
	if texture != frame:
		texture = frame


func _process(delta: float) -> void:
	if _current == "" or _done or _pinned:
		return
	var cfg: Dictionary = _anims[_current]
	var frames: Array[Texture2D] = cfg["frames"]
	_t += delta
	var idx := int(_t * float(cfg["fps"]))
	if cfg["loop"]:
		idx %= frames.size()
	elif idx >= frames.size():
		idx = frames.size() - 1
		_done = true
		finished.emit(StringName(_current))
	if texture != frames[idx]:
		texture = frames[idx]
