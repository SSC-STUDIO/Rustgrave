class_name TutorialRecall
extends CanvasLayer
## 教程回看：暂停菜单里重读已经出现过的情境提示（键名按当前键位）。
## 数据来自 HintService.seen_entries()（本存档旗标 + 内置表 + 关卡作者提示的文案缓存），
## 没看过的不列——这里不是剧透清单。挂法与 ControlsPanel 相同。

signal closed

const Modal := preload("res://scripts/ui/ui_modal.gd")

const SCROLL_STEP := 56.0

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty_box: Control
var _empty: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_shell = Modal.build(self, {
		"title": "教 程 回 看",
		"size": Vector2(880.0, 580.0),
		"hint": "↑↓ 滚动",
		"back": "Esc / 回车 返回",
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close())

	var body := _shell["body"] as Control
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)

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
	empty_head.modulate = Color("#E4DCCC")
	_empty_box.add_child(empty_head)
	_empty = UiKit.label("新的机制第一次用得上时，提示会在画面上出现一次，并留在这里。",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_empty.name = "Empty"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(560.0, 0.0)
	_empty.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_box.add_child(_empty)

## 重新读取已看过的提示并重排。
func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var entries := HintService.seen_entries()
	if _empty_box != null:
		_empty_box.visible = entries.is_empty()
	_scroll.visible = not entries.is_empty()
	for entry in entries:
		_list.add_child(_make_entry(String(entry["title"]), String(entry["text"])))
	_scroll.scroll_vertical = 0


func entry_count() -> int:
	return _list.get_child_count()


func _make_entry(title: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.custom_minimum_size = Vector2(0.0, UiKit.TOUCH_MIN * 0.62)
	var name_label := UiKit.label(title, &"KeyCapLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	name_label.name = "Title"
	name_label.custom_minimum_size = Vector2(130.0, 0.0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# "场景提示"是关卡作者写的临时提示，排在内置键位表之后 —— 键名染成
	# 暗铁而不是琥珀，内置条目与作者条目在颜色上就分出了主次两档。
	name_label.modulate = Color("#B8703E") if title == "场景提示" else UiKit.EMBER
	row.add_child(name_label)
	var body := UiKit.label(text, &"BodyLabel")
	body.name = "Text"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(body)
	return row


func open() -> void:
	refresh()
	_closing = false
	visible = true
	(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
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


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_scroll.scroll_vertical += int(SCROLL_STEP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical - int(SCROLL_STEP))
		get_viewport().set_input_as_handled()
