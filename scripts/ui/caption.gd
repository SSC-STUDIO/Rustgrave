class_name Caption
extends Control
## 底部打字机字幕。可排队；skip 会立刻写完当前句并进入停留，
## 再 skip 一次就切下一句或结束。
##
## 外观：一块玻璃铁框（与 HUD 同一套 TAG 板、同一透明度），左上角外侧挂一块说话人名牌，
## 名牌字是 12px 的小标（字距拉开，和弹窗题头同一写法）：伊尔用余烬金，其余说话人用淡余烬。

signal finished
signal line_advanced

const CHARS_PER_SEC := 22.0
const DEFAULT_HOLD := 1.6
## 面板默认贴底（-48..-4）。Boss 血条也在屏幕底部，打 Boss 时 HUD 把字幕抬到血条上方。
const BASE_TOP := -48.0
const BASE_BOTTOM := -4.0
## 名牌：左缘对齐字幕条内侧，宽 160、高 34（TAG 板两端各占 16 的切角与环）；下沿压在字幕条上沿 2px。
const WHO_LEFT := -272.0
const WHO_WIDTH := 160.0
const WHO_HEIGHT := 34.0

static var _glass: Theme

var _queue: Array[Dictionary] = []
var _full: String = ""
var _shown: float = 0.0
var _hold_left: float = 0.0
var _typing: bool = false
var _holding: bool = false
var _label: Label
var _panel: PanelContainer
var _who_panel: PanelContainer
var _who_label: Label
var _lift := 0.0
var _who: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_viewport_size()
	get_viewport().size_changed.connect(_sync_viewport_size)

	_panel = PanelContainer.new()
	_panel.name = "CaptionPanel"
	_panel.theme = glass_theme()
	_panel.theme_type_variation = &"CaptionGlass"
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

	# 说话人名牌：贴在字幕条左上角外侧。台词写成「伊尔：……」，名牌显示「伊尔」，条里只放内容。
	_who_panel = PanelContainer.new()
	_who_panel.name = "CaptionWho"
	_who_panel.theme = glass_theme()
	_who_panel.theme_type_variation = &"CaptionWhoCold"
	_who_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_who_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_who_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_who_panel.offset_left = WHO_LEFT
	_who_panel.offset_right = WHO_LEFT + WHO_WIDTH
	_who_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_who_panel.visible = false
	add_child(_who_panel)
	_who_label = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_who_label.name = "Speaker"
	_who_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_who_panel.add_child(_who_label)
	_place_who()


## 字幕与名牌共用的玻璃铁框：menu_plate 的 TAG 板只改着色透明度（GlassKit.CARD_ALPHA）。
## 字幕条是冷铁环；名牌在「伊尔」（你背上的声音）时是余烬环，其余说话人是冷铁环。
static func glass_theme() -> Theme:
	if _glass == null:
		_glass = Theme.new()
		_glass.set_type_variation(&"CaptionGlass", &"PanelContainer")
		_glass.set_stylebox("panel", &"CaptionGlass", _glass_box(UiKit.Plate.State.NORMAL, 20.0, 0.0))
		_glass.set_type_variation(&"CaptionWhoLit", &"PanelContainer")
		_glass.set_stylebox("panel", &"CaptionWhoLit", _glass_box(UiKit.Plate.State.SELECTED, 8.0, 0.0))
		_glass.set_type_variation(&"CaptionWhoCold", &"PanelContainer")
		_glass.set_stylebox("panel", &"CaptionWhoCold", _glass_box(UiKit.Plate.State.NORMAL, 8.0, 0.0))
		# 伊尔（你背上的声音）的名字用余烬金；其余说话人用淡余烬，名牌环也收成冷铁。
		_glass.set_type_variation(&"CaptionSpeakerGold", &"Label")
		_glass.set_color("font_color", &"CaptionSpeakerGold", UiKit.EMBER)
		_glass.set_color("font_outline_color", &"CaptionSpeakerGold", Color(0.04, 0.03, 0.06, 0.92))
		_glass.set_constant("outline_size", &"CaptionSpeakerGold", 1)
		_glass.set_font_size("font_size", &"CaptionSpeakerGold", 12)
	return _glass


static func _glass_box(state: int, pad_x: float, pad_y: float) -> StyleBoxTexture:
	var box := UiKit.Plate.style_box(UiKit.Plate.Shape.TAG, state)
	box.modulate_color = Color(1.0, 1.0, 1.0, GlassKit.CARD_ALPHA)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


func _sync_viewport_size() -> void:
	var vp := get_viewport()
	if vp != null:
		set_deferred("size", vp.get_visible_rect().size)


## 把字幕条整体上移 `px`（UI 设计像素）；0 = 回到贴底。Director 是常驻的，
## 所以抬起的一方（HUD）离场时必须放回去。
func lift(px: float) -> void:
	_lift = maxf(0.0, px)
	if _panel != null:
		_panel.offset_top = BASE_TOP - _lift
		_panel.offset_bottom = BASE_BOTTOM - _lift
	_place_who()


func lifted() -> float:
	return _lift


## 名牌的下沿压在字幕条上沿 2 个像素（两块牌子拼成一块）。
func _place_who() -> void:
	if _who_panel == null:
		return
	var foot := BASE_TOP - _lift + 2.0
	_who_panel.offset_top = foot - WHO_HEIGHT
	_who_panel.offset_bottom = foot


func is_busy() -> bool:
	return _typing or _holding or not _queue.is_empty()


## 当前这句的说话人（没有则空串）。测试与 Director 读。
func speaker() -> String:
	return _who


## who 为空时按「说话人：内容」自动拆（只认 ChapterText.SPEAKERS）。
func enqueue(text: String, hold: float = DEFAULT_HOLD, who: String = "") -> void:
	if text == "":
		return
	var body := text
	var speaker_name := who
	if speaker_name == "":
		var parts := ChapterText.split_speaker(text)
		speaker_name = parts[0]
		body = parts[1]
	if body == "":
		return
	_queue.append({"text": body, "hold": hold, "who": speaker_name})
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
	_set_who("")


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if _typing:
		var subtitle := clampf(float(Settings.value(&"subtitle_speed", 1.0)), 0.6, 1.5)
		_shown += CHARS_PER_SEC * subtitle * delta
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


func _set_who(who: String) -> void:
	_who = who
	if _who_panel == null:
		return
	_who_panel.visible = who != ""
	_who_label.text = _spaced(who)
	var is_ember := who == "伊尔"
	_who_panel.theme_type_variation = &"CaptionWhoLit" if is_ember else &"CaptionWhoCold"
	_who_label.theme_type_variation = &"CaptionSpeakerGold" if is_ember else &"TinyStrongLabel"


## 名牌字距拉开（"伊 尔"），与弹窗题头、章节小标同一写法。
static func _spaced(text: String) -> String:
	var parts := PackedStringArray()
	for i in text.length():
		parts.append(text.substr(i, 1))
	return " ".join(parts)


func _start_next() -> void:
	if _queue.is_empty():
		_panel.visible = false
		_set_who("")
		_label.text = ""
		_full = ""
		finished.emit()
		return
	var item: Dictionary = _queue.pop_front()
	_full = String(item.get("text", ""))
	_set_who(String(item.get("who", "")))
	_hold_left = float(item.get("hold", DEFAULT_HOLD))
	# 第一格字和面板同一帧出现：以前面板先空着亮 2–3 帧，截图和录像里是一条空框。
	_shown = 1.0
	_label.text = _full.substr(0, 1)
	_typing = _full.length() > 1
	_holding = not _typing
	if _holding:
		line_advanced.emit()
	_panel.visible = true
