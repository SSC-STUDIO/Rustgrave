class_name TutorialRecall
extends CanvasLayer
## 教程回看：暂停菜单里重读已经出现过的情境提示（键名按当前键位）。
## 数据来自 HintService.seen_entries()（本存档旗标 + 内置表 + 关卡作者提示的文案缓存），
## 没看过的不列——这里不是剧透清单。挂法与 ControlsPanel 相同。
##
## 版式：随身手札左页是墨写目录（一 二 三 …，↑↓ 或悬停选中），
## 右页是课名、正文，以及正文里提到的铅字按键。
## 键名只从正文里认：整词出现才亮成键帽，不凭空补键。

signal closed

const Modal := preload("res://scripts/ui/ui_modal.gd")
const INK := Color("#30251D")
const FADED_INK := Color("#65513E")
const ObjectKit := preload("res://scripts/ui/ui_object.gd")

## 压暗到 0.76：盖在暂停菜单上，底下的左列铁条要压到看不出字来，玻璃课卡才干净。
const VEIL := 0.76
const LIST_WIDTH := 304.0
const CARD_GAP := 24.0
const ITEM_PREFIX := "lesson_"
## 正文里会写到、但不在 Settings 绑定表里的固定键名。
const FIXED_KEYS: Array[String] = ["Tab", "Esc"]
const NUMERALS: Array[String] = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _split: HBoxContainer
var _scroll: ScrollContainer
var _menu: MenuList
var _lesson_title: Label
var _lesson_body: Label
var _keys_caption: Label
var _keys_box: HBoxContainer
var _empty_box: Control
var _entries: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_shell = Modal.build(self, {
		"object": ObjectKit.Kind.JOURNAL,
		"title": "教 程 回 看",
		"size": Vector2(880.0, 580.0),
		"hint": "↑↓ 选择",
		"back": "Esc / 回车 返回",
		"veil": VEIL,
	})
	_root = _shell["root"] as Control
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close())

	var body := _shell["body"] as Control
	_split = HBoxContainer.new()
	_split.name = "Split"
	_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	_split.add_theme_constant_override("separation", int(CARD_GAP))
	body.add_child(_split)
	body.resized.connect(_layout_pages)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.custom_minimum_size = Vector2(LIST_WIDTH + 8.0, 0.0)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_split.add_child(_scroll)

	var card := PanelContainer.new()
	card.name = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var page := StyleBoxEmpty.new()
	page.content_margin_left = 12.0
	page.content_margin_right = 8.0
	card.add_theme_stylebox_override("panel", page)
	_split.add_child(card)
	var lesson := VBoxContainer.new()
	lesson.name = "Lesson"
	lesson.add_theme_constant_override("separation", 10)
	card.add_child(lesson)
	var caption := UiKit.label("随 身 手 札", &"TinyStrongLabel")
	caption.add_theme_color_override("font_color", FADED_INK)
	lesson.add_child(caption)
	_lesson_title = UiKit.label("", &"HeadLabel")
	_lesson_title.name = "LessonTitle"
	_lesson_title.add_theme_color_override("font_color", INK)
	_lesson_title.add_theme_constant_override("outline_size", 0)
	lesson.add_child(_lesson_title)
	lesson.add_child(GlassKit.rule(160.0))
	_lesson_body = UiKit.label("", &"BodyLabel")
	_lesson_body.name = "LessonBody"
	_lesson_body.add_theme_color_override("font_color", INK)
	_lesson_body.add_theme_constant_override("outline_size", 0)
	_lesson_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lesson_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lesson_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lesson.add_child(_lesson_body)
	_keys_caption = UiKit.label("涉 及 按 键", &"TinyStrongLabel")
	_keys_caption.name = "KeysCaption"
	_keys_caption.add_theme_color_override("font_color", FADED_INK)
	lesson.add_child(_keys_caption)
	_keys_box = HBoxContainer.new()
	_keys_box.name = "Keys"
	_keys_box.add_theme_constant_override("separation", 8)
	lesson.add_child(_keys_box)

	# 空态分两层：一句暖白的"还没有可回看的提示"是主答案，下面一行暗脚注
	# 解释机制何时会出现。整段同字同色时玩家只会扫到"一大片灰"。
	_empty_box = VBoxContainer.new()
	_empty_box.name = "EmptyBox"
	_empty_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_box.add_theme_constant_override("separation", 6)
	_empty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_box.visible = false
	body.add_child(_empty_box)
	var empty_head := UiKit.label("还没有可回看的提示", &"SubHeadLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	empty_head.name = "EmptyHead"
	empty_head.add_theme_color_override("font_color", INK)
	_empty_box.add_child(empty_head)
	var empty := UiKit.label("新的机制第一次用得上时，提示会在画面上出现一次，并留在这里。",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	empty.name = "Empty"
	empty.add_theme_color_override("font_color", FADED_INK)
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.custom_minimum_size = Vector2(560.0, 0.0)
	empty.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_box.add_child(empty)
	refresh()
	_layout_pages.call_deferred()


## 两列在真正的书脊两侧落位；视口适配后重新测量，不让目录越过中缝。
func _layout_pages() -> void:
	if _scroll == null or _split == null:
		return
	_scroll.custom_minimum_size.x = floorf((_split.size.x - CARD_GAP) * 0.5)


## 重新读取已看过的提示并重排墨写目录（MenuList 没有删行接口，所以每次重建）。
func refresh() -> void:
	_entries = HintService.seen_entries()
	if _menu != null:
		_scroll.remove_child(_menu)
		_menu.queue_free()
	_menu = MenuList.new()
	_menu.name = "List"
	_menu.ink_style = true
	_menu.add_theme_constant_override("separation", 6)
	_menu.focus_changed.connect(_on_focus_changed)
	_scroll.add_child(_menu)
	for i in _entries.size():
		var item := _menu.add_item(StringName(ITEM_PREFIX + str(i)),
				"%s  %s" % [_numeral(i + 1), String(_entries[i]["title"])], false,
				MenuItem.Kind.SECONDARY)
		item.show_tick = false
	var has := not _entries.is_empty()
	_split.visible = has
	if _empty_box != null:
		_empty_box.visible = not has
	_scroll.scroll_vertical = 0
	if has:
		_show_lesson(0)


func entry_count() -> int:
	return _menu.items().size() if _menu != null else 0


## 课卡：课名、正文、正文里提到的键。
func _show_lesson(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry := _entries[index]
	_lesson_title.text = String(entry["title"])
	_lesson_body.text = String(entry["text"])
	_render_keys(String(entry["text"]))


func _on_focus_changed(id: StringName) -> void:
	var index := String(id).trim_prefix(ITEM_PREFIX).to_int()
	_show_lesson(index)
	var items := _menu.items()
	if index >= 0 and index < items.size():
		_scroll.ensure_control_visible.call_deferred(items[index] as Control)


func _render_keys(text: String) -> void:
	for old in _keys_box.get_children():
		_keys_box.remove_child(old)
		old.queue_free()
	var tokens := keys_in(text)
	for token in tokens:
		_keys_box.add_child(_chip(token))
	_keys_caption.visible = not tokens.is_empty()
	_keys_box.visible = not tokens.is_empty()


func _chip(text: String) -> Control:
	var plate := UiKit.panel(&"KeyCapPanel")
	plate.name = "Chip"
	var stamp := StyleBoxFlat.new()
	stamp.bg_color = Color("#B9A785")
	stamp.border_color = Color("#79664A")
	stamp.set_border_width_all(1)
	stamp.content_margin_left = 8.0
	stamp.content_margin_right = 8.0
	stamp.content_margin_top = 2.0
	stamp.content_margin_bottom = 2.0
	plate.add_theme_stylebox_override("panel", stamp)
	var key := UiKit.label(text, &"KeyCapLabel", HORIZONTAL_ALIGNMENT_CENTER)
	key.add_theme_color_override("font_color", INK)
	key.add_theme_constant_override("outline_size", 0)
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(key)
	return plate


## 正文里出现过的键名（按出现顺序去重）。只认整词：E 不会误中 Esc，1 不会误中 12。
static func keys_in(text: String) -> Array[String]:
	var hits: Array = []
	for token in _key_tokens():
		var at := text.find(token)
		while at >= 0:
			if _whole_word(text, at, token.length()):
				hits.append([at, token])
				break
			at = text.find(token, at + 1)
	hits.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var out: Array[String] = []
	for hit in hits:
		var token := String(hit[1])
		if not out.has(token):
			out.append(token)
	return out


## 当前键位表里所有可能出现在正文里的键名：Settings 的绑定 + 备用键 + 固定键。
static func _key_tokens() -> Array[String]:
	var out: Array[String] = []
	for action in Settings.REBINDABLE:
		_add_token(out, KeyLabels.label(StringName(action)))
		for extra in KeyLabels.extra_keys(StringName(action)):
			_add_token(out, extra)
	for fixed in FIXED_KEYS:
		_add_token(out, fixed)
	return out


static func _add_token(out: Array[String], token: String) -> void:
	if token != "" and not out.has(token):
		out.append(token)


static func _whole_word(text: String, at: int, n: int) -> bool:
	var before := text.unicode_at(at - 1) if at > 0 else 32
	var after := text.unicode_at(at + n) if at + n < text.length() else 32
	return not _is_ascii_word(before) and not _is_ascii_word(after)


static func _is_ascii_word(c: int) -> bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)


## 一 二 三 …：1..9 用单字，十以上写成「十一」「二十」「二十一」。
static func _numeral(n: int) -> String:
	if n < 10:
		return NUMERALS[n]
	if n < 100:
		var tens := n / 10
		var ones := n % 10
		var head := "" if tens == 1 else NUMERALS[tens]
		return head + "十" + ("" if ones == 0 else NUMERALS[ones])
	return str(n)


func open() -> void:
	refresh()
	_closing = false
	_menu.active = true
	visible = true
	(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_menu.active = false
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	# 退场动画播完才隐藏：卡片沉回去、纱幕收掉，然后才 emit closed。
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		closed.emit()
	)


## 回车 / Esc 在任何焦点下都是「返回」：放在 _input 里先接，免得列表把回车当成选中。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()
