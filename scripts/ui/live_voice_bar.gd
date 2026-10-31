class_name LiveVoiceBar
extends CanvasLayer
## 非阻塞实时动态语音条（对标《ICEY》边走边打的动态旁白体验）。
##
## 核心契约：
##   1. 绝不调用 Director 锁输入、绝不拉起电影黑边，玩家移动、挥剑、弹反、打开菜单全程零阻断；
##   2. 摆放在顶部安全区偏下（y = 58..104 UI 设计像素），天然避开左上角血条/毒素槽与底部 Boss 血条；
##      当 Director 全屏分镜或暂停菜单打开时自动隐藏让位；
##   3. 四阶声线视觉反馈：
##        · guide    暖金余烬边框（「伊尔」）
##        · doubt    暗琥珀微颤边框（「伊尔？」）
##        · glitch   猩红裂纹故障抖动边框（「司炉回声」）
##        · true_yir 冷白魂光边框（「真伊尔」）
##        · boss     铁锈铜红边框（首领/残响）
##   4. 支持实时打断（Interrupt）：高优先级或违抗语音触发瞬间切掉未念完的引导词，立刻切入新词。

signal clip_started(clip_id: String, tone: StringName)
signal clip_interrupted(old_clip_id: String, new_clip_id: String)
signal clip_finished(clip_id: String)

const CHARS_PER_SEC := 28.0
const DEFAULT_HOLD := 2.5
const BAR_WIDTH := 580.0
const BAR_HEIGHT := 48.0
const BAR_TOP := 54.0

const STYLE_BY_TONE := {
	&"guide": {
		"bg": Color(0.07, 0.06, 0.09, 0.84),
		"border": Color("#FFB84D"),
		"speaker": Color("#FFD27D"),
		"text": Color("#F4EFE6"),
		"jitter": 0.0,
	},
	&"doubt": {
		"bg": Color(0.09, 0.06, 0.06, 0.88),
		"border": Color("#D97A2B"),
		"speaker": Color("#FF9E44"),
		"text": Color("#F2E2D0"),
		"jitter": 1.2,
	},
	&"glitch": {
		"bg": Color(0.13, 0.04, 0.06, 0.92),
		"border": Color("#E03B3B"),
		"speaker": Color("#FF5C5C"),
		"text": Color("#FFE3E3"),
		"jitter": 3.5,
	},
	&"true_yir": {
		"bg": Color(0.06, 0.09, 0.13, 0.88),
		"border": Color("#9BE4FF"),
		"speaker": Color("#C9F2FF"),
		"text": Color("#F2FBFF"),
		"jitter": 0.0,
	},
	&"boss": {
		"bg": Color(0.09, 0.05, 0.07, 0.86),
		"border": Color("#C2593F"),
		"speaker": Color("#E88A6E"),
		"text": Color("#EFE4DC"),
		"jitter": 0.6,
	},
}

var interrupt_count: int = 0

var _root: Control
var _card: Control
var _bg_rect: ColorRect
var _border_top: ColorRect
var _border_bot: ColorRect
var _border_left: ColorRect
var _tag_bg: ColorRect
var _speaker_label: Label
var _text_label: Label

var _queue: Array[Dictionary] = []
var _active_clip_id: String = ""
var _active_tone: StringName = &"guide"
var _active_priority: int = 0
var _full_text: String = ""
var _shown_chars: float = 0.0
var _hold_left: float = 0.0
var _typing: bool = false
var _holding: bool = false
var _jitter_px: float = 0.0
var _base_card_pos: Vector2 = Vector2.ZERO
var _clock: float = 0.0


func _ready() -> void:
	name = "LiveVoiceBar"
	layer = 12
	process_mode = Node.PROCESS_MODE_PAUSABLE
	WorldClock.isolate_ui_layer(self)
	_build_ui()
	PresentationMetrics.bind_layer(self)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "VoiceRoot"
	_root.anchor_left = 0.0
	_root.anchor_top = 0.0
	_root.anchor_right = 0.0
	_root.anchor_bottom = 0.0
	_root.offset_right = PresentationMetrics.UI_SIZE.x
	_root.offset_bottom = PresentationMetrics.UI_SIZE.y
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_card = Control.new()
	_card.name = "VoiceCard"
	_card.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_base_card_pos = Vector2(floorf((PresentationMetrics.UI_SIZE.x - BAR_WIDTH) * 0.5), BAR_TOP)
	_card.position = _base_card_pos
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_root.add_child(_card)

	_bg_rect = ColorRect.new()
	_bg_rect.name = "Bg"
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_bg_rect)

	_border_left = ColorRect.new()
	_border_left.name = "AccentLeft"
	_border_left.position = Vector2.ZERO
	_border_left.size = Vector2(4.0, BAR_HEIGHT)
	_border_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_border_left)

	_border_top = ColorRect.new()
	_border_top.name = "BorderTop"
	_border_top.position = Vector2.ZERO
	_border_top.size = Vector2(BAR_WIDTH, 1.0)
	_border_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_border_top)

	_border_bot = ColorRect.new()
	_border_bot.name = "BorderBottom"
	_border_bot.position = Vector2(0.0, BAR_HEIGHT - 1.0)
	_border_bot.size = Vector2(BAR_WIDTH, 1.0)
	_border_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_border_bot)

	_tag_bg = ColorRect.new()
	_tag_bg.name = "SpeakerPlate"
	_tag_bg.position = Vector2(4.0, -20.0)
	_tag_bg.size = Vector2(116.0, 20.0)
	_tag_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_tag_bg)

	_speaker_label = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_speaker_label.name = "SpeakerLabel"
	_speaker_label.position = Vector2(4.0, -20.0)
	_speaker_label.size = Vector2(116.0, 20.0)
	_speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_speaker_label)

	_text_label = UiKit.label("", &"BodyLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_text_label.name = "VoiceText"
	_text_label.position = Vector2(18.0, 6.0)
	_text_label.size = Vector2(BAR_WIDTH - 32.0, BAR_HEIGHT - 12.0)
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_text_label)


func is_speaking() -> bool:
	return _typing or _holding


func active_clip_id() -> String:
	return _active_clip_id


func active_tone() -> StringName:
	return _active_tone


func active_speaker() -> String:
	return _speaker_label.text if _speaker_label != null else ""


func current_text() -> String:
	return _full_text


func play_clip(clip_id: String, force_interrupt: bool = false) -> bool:
	var spec := NarrativeCatalog.clip_spec(clip_id)
	if spec.is_empty():
		return false
	var entry := {
		"id": clip_id,
		"tone": spec.get("tone", NarrativeCatalog.TONE_GUIDE),
		"speaker": NarrativeCatalog.speaker_of_clip(clip_id),
		"text": String(spec.get("text", "")),
		"hold": float(spec.get("hold", DEFAULT_HOLD)),
		"priority": int(spec.get("priority", 1)),
	}
	return play_entry(entry, force_interrupt)


func play_entry(entry: Dictionary, force_interrupt: bool = false) -> bool:
	var text := String(entry.get("text", "")).strip_edges()
	if text == "":
		return false
	var new_id := String(entry.get("id", "adhoc"))
	var new_prio := int(entry.get("priority", 1))
	if is_speaking():
		if force_interrupt or new_prio > _active_priority:
			var prev_id := _active_clip_id
			_queue.clear()
			interrupt_count += 1
			_start_entry(entry)
			clip_interrupted.emit(prev_id, new_id)
			return true
		if new_id == _active_clip_id:
			return false
		# 同优先级排队，最多保留 2 条避免过时语音堆积。
		if _queue.size() >= 2:
			_queue.pop_front()
		_queue.append(entry)
		return true
	_start_entry(entry)
	return true


func clear() -> void:
	_queue.clear()
	_typing = false
	_holding = false
	_active_clip_id = ""
	_full_text = ""
	if _card != null:
		_card.visible = false
		_card.position = _base_card_pos


func _start_entry(entry: Dictionary) -> void:
	_active_clip_id = String(entry.get("id", "adhoc"))
	_active_tone = entry.get("tone", NarrativeCatalog.TONE_GUIDE) as StringName
	_active_priority = int(entry.get("priority", 1))
	_full_text = String(entry.get("text", ""))
	_hold_left = maxf(0.4, float(entry.get("hold", DEFAULT_HOLD)))
	_shown_chars = 0.0
	_typing = true
	_holding = false

	var style: Dictionary = STYLE_BY_TONE.get(_active_tone, STYLE_BY_TONE[&"guide"])
	var border_col: Color = style["border"]
	_bg_rect.color = style["bg"]
	_border_left.color = border_col
	_border_top.color = Color(border_col.r, border_col.g, border_col.b, 0.55)
	_border_bot.color = Color(border_col.r, border_col.g, border_col.b, 0.35)
	_tag_bg.color = Color(style["bg"].r, style["bg"].g, style["bg"].b, 0.95)
	_speaker_label.text = String(entry.get("speaker", "伊尔"))
	_speaker_label.modulate = style["speaker"]
	_text_label.text = ""
	_text_label.modulate = style["text"]
	_jitter_px = float(style.get("jitter", 0.0))

	_card.position = _base_card_pos
	_card.visible = true
	if _active_tone == NarrativeCatalog.TONE_GLITCH:
		UiKit.sfx(&"ui_denied", &"ui_tick")
	elif _active_tone == NarrativeCatalog.TONE_DOUBT:
		UiKit.sfx(&"ui_tick", &"ui_move")
	clip_started.emit(_active_clip_id, _active_tone)


func _process(delta: float) -> void:
	if _root != null:
		var vp := get_viewport()
		if vp != null:
			_root.size = vp.get_visible_rect().size
			_base_card_pos.x = floorf((_root.size.x - BAR_WIDTH) * 0.5)
	# 全屏分镜或游戏暂停时暂时隐去，避免遮盖菜单/分镜。
	if _card != null and (_typing or _holding):
		var suppressed := get_tree().paused or Director.board_active()
		_card.visible = not suppressed
	if not _typing and not _holding:
		return

	_clock += delta
	if _jitter_px > 0.0 and _card != null:
		var decay := 1.0 if _typing else 0.35
		var dx := roundf(sin(_clock * 47.0) * _jitter_px * decay)
		var dy := roundf(cos(_clock * 31.0) * (_jitter_px * 0.35) * decay)
		_card.position = _base_card_pos + Vector2(dx, dy)
	elif _card != null:
		_card.position = _base_card_pos

	if _typing:
		_shown_chars += CHARS_PER_SEC * delta
		var count := int(_shown_chars)
		if count >= _full_text.length():
			_text_label.text = _full_text
			_typing = false
			_holding = true
		else:
			_text_label.text = _full_text.substr(0, count)
		return

	if _holding:
		_hold_left -= delta
		if _hold_left <= 0.0:
			var finished_id := _active_clip_id
			_holding = false
			if not _queue.is_empty():
				var next_entry: Dictionary = _queue.pop_front()
				clip_finished.emit(finished_id)
				_start_entry(next_entry)
			else:
				_active_clip_id = ""
				_card.visible = false
				_card.position = _base_card_pos
				clip_finished.emit(finished_id)
