class_name TutorialRecall
extends CanvasLayer
## 教程回看：暂停菜单里重读已经出现过的情境提示（键名按当前键位）。
## 数据来自 HintService.seen_entries()（本存档旗标 + 内置表 + 关卡作者提示的文案缓存），
## 没看过的不列——这里不是剧透清单。挂法与 ControlsPanel 相同。

signal closed

const SCROLL_STEP := 56.0

var _root: Control
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_root)
	_root.add_child(UiKit.scrim(0.90, 0.90, 0.90))

	var frame := UiKit.panel(&"OrnatePanel")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 140.0
	frame.offset_right = -140.0
	frame.offset_top = 32.0
	frame.offset_bottom = -32.0
	_root.add_child(frame)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	frame.add_child(column)
	column.add_child(UiKit.label("教 程 回 看", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)

	_empty = UiKit.label("还没有可回看的提示。\n新的机制第一次用得上时，提示会在画面上出现一次，并留在这里。",
			&"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_empty.name = "Empty"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(700.0, 0.0)
	_empty.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_empty)

	column.add_child(UiKit.label("↑↓ 滚动 · Esc / 回车 返回", &"SubHeadLabel",
			HORIZONTAL_ALIGNMENT_CENTER))


## 重新读取已看过的提示并重排。
func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var entries := HintService.seen_entries()
	_empty.visible = entries.is_empty()
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
	visible = true
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


func close() -> void:
	if not visible:
		return
	visible = false
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	closed.emit()


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
