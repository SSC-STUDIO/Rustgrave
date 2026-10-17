class_name Caption
extends Control
## 底部打字机字幕。可排队；skip 会立刻写完当前句并进入停留，
## 再 skip 一次就切下一句或结束。

signal finished
signal line_advanced

const CHARS_PER_SEC := 22.0
const DEFAULT_HOLD := 1.6

var _queue: Array[Dictionary] = []
var _full: String = ""
var _shown: float = 0.0
var _hold_left: float = 0.0
var _typing: bool = false
var _holding: bool = false
var _label: Label
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_panel.offset_top = -48.0
	_panel.offset_bottom = -4.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_label = UiKit.label("", &"AnnounceLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_panel.add_child(_label)


func _sync_viewport_size() -> void:
	var vp := get_viewport()
	if vp != null:
		set_deferred("size", vp.get_visible_rect().size)


func is_busy() -> bool:
	return _typing or _holding or not _queue.is_empty()


func enqueue(text: String, hold: float = DEFAULT_HOLD) -> void:
	if text == "":
		return
	_queue.append({"text": text, "hold": hold})
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
		_shown += CHARS_PER_SEC * delta
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
