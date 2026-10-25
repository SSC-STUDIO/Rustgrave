class_name Caption
extends Control
## 底部打字机字幕。可排队；skip 会立刻写完当前句并进入停留，
## 再 skip 一次就切下一句或结束。

signal finished
signal line_advanced

const CHARS_PER_SEC := 22.0
const DEFAULT_HOLD := 1.6
## 面板默认贴底（-48..-4）。Boss 血条也在屏幕底部，打 Boss 时 HUD 把字幕抬到血条上方。
const BASE_TOP := -48.0
const BASE_BOTTOM := -4.0

var _queue: Array[Dictionary] = []
var _full: String = ""
var _shown: float = 0.0
var _hold_left: float = 0.0
var _typing: bool = false
var _holding: bool = false
var _label: Label
var _panel: PanelContainer
var _lift := 0.0


## 字幕层被 PresentationMetrics.bind_layer 包进内容矩形里（layer.transform），
## 引擎在视口/层变换时会重排子树 Control 的 size。全矩形预设的左右（上下）
## 锚点不相等，引擎每次重排都打印一条 "non-equal opposite anchors" 警告。
## 这里改用相等的对角锚点 + 偏移量铺满内容矩形：布局结果一致，警告消失。
const LAYER_SIZE := Vector2(PresentationMetrics.UI_SIZE)


func _ready() -> void:
	# Equal opposite anchors (0,0,0,0) + offsets to the full layer: no size
	# assignment, so the engine's resize pass never trips the anchor warning.
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = LAYER_SIZE.x
	offset_bottom = LAYER_SIZE.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_viewport_size()
	get_viewport().size_changed.connect(_sync_viewport_size)

	_panel = UiKit.panel(&"HudPanel")
	_panel.name = "CaptionPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -280.0
	_panel.offset_right = 280.0
	# Hug the 32px letterbox / screen foot so the strip does not cover the player.
	_panel.offset_top = BASE_TOP - _lift
	_panel.offset_bottom = BASE_BOTTOM - _lift
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_label = UiKit.label("", &"AnnounceLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_panel.add_child(_label)


func _sync_viewport_size() -> void:
	# A caption inside a presentation-bound layer is already a fixed UI_SIZE
	# rectangle in layer units, so following the physical window would fight the
	# layer transform. Only an unbound caption (tests, probes) on a raw viewport
	# needs to match that viewport.
	var vp := get_viewport()
	if vp == null:
		return
	var host := get_parent()
	if host is CanvasLayer and host.has_meta("presentation_bound"):
		return
	set_deferred("size", vp.get_visible_rect().size)


## 把字幕条整体上移 `px`（UI 设计像素）；0 = 回到贴底。Director 是常驻的，
## 所以抬起的一方（HUD）离场时必须放回去。
func lift(px: float) -> void:
	_lift = maxf(0.0, px)
	if _panel != null:
		_panel.offset_top = BASE_TOP - _lift
		_panel.offset_bottom = BASE_BOTTOM - _lift


func lifted() -> float:
	return _lift


func is_busy() -> bool:
	return _typing or _holding or not _queue.is_empty()


func enqueue(text: String, hold: float = DEFAULT_HOLD, who: String = "") -> void:
	if text == "":
		return
	# who 由导演传入（「说话人：内容」以外的显式名牌）。字幕条只画正文，名字留在字典里。
	_queue.append({"text": text, "hold": hold, "who": who})
	if not _typing and not _holding:
		_start_next()


func skip() -> void:
	if _typing:
		_shown = _full.length()
		_label.text = _full
		_typing = false
		_holding = true
		line_advanced.emit()
		return
	if _holding:
		_holding = false
		_hold_left = 0.0
		_start_next()


func clear() -> void:
	_queue.clear()
	_typing = false
	_holding = false
	_full = ""
	_shown = 0
	_hold_left = 0.0
	_label.text = ""
	_panel.visible = false


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if _typing:
		_shown += CHARS_PER_SEC * Settings.assist(&"subtitle_speed") * delta
		var n := mini(_full.length(), int(_shown))
		_label.text = _full.substr(0, n)
		if n >= _full.length():
			_typing = false
			_holding = true
			line_advanced.emit()
		return
	if _holding:
		_hold_left -= delta
		if _hold_left <= 0.0:
			_holding = false
			_start_next()


func _start_next() -> void:
	if _queue.is_empty():
		_panel.visible = false
		_label.text = ""
		_full = ""
		finished.emit()
		return
	var item: Dictionary = _queue.pop_front()
	_full = String(item.get("text", ""))
	_hold_left = float(item.get("hold", DEFAULT_HOLD))
	# 第一格字和面板同一帧出现：以前面板先空着亮 2–3 帧，截图和录像里是一条空框。
	_shown = 1.0
	_label.text = _full.substr(0, 1)
	_typing = _full.length() > 1
	_holding = not _typing
	if _holding:
		line_advanced.emit()
	_panel.visible = true
