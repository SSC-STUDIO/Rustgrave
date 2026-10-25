class_name UpdatePrompt
extends CanvasLayer
## 更新提示：发现新版本时弹出的模态卡。一张紧凑的玻璃卡：版本芯片（当前 → 最新）、更新日志、
## 两个出口——去下载页（桌面版唤起浏览器）和跳过此版本。
## exe/zip 包不做内置自更新：Godot 的热更新要么换 pck 要么走应用商店，
## 都不适合一个绿色版小游戏；把玩家带到下载页是最诚实也最省事的一条路。

signal closed
signal download_requested
signal skip_requested

const Modal := preload("res://scripts/ui/ui_modal.gd")
## 紧凑卡：四条单行日志不用滚动，更长的内容进日志滚动区。
const CARD_SIZE := Vector2(680.0, 530.0)
const CHIP_W := 232.0
const CHIP_H := 44.0

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _current_version: Label
var _remote_version: Label
var _notes_kicker: Label
var _notes: VBoxContainer
var _download_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_shell = Modal.build(self, {
		"kicker": "版 本 更 新",
		"title": "有 新 版 本",
		"size": CARD_SIZE,
		"hint": "Enter 前往下载 · Esc 稍后再说",
		"back": "Esc 稍后再说",
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	var body := _shell["body"] as Control

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	body.add_child(column)

	column.add_child(_build_versions())

	var notes_head := GlassKit.kicker("更 新 日 志")
	notes_head.name = "NotesKicker"
	_notes_kicker = notes_head
	column.add_child(notes_head)
	var scroll := ScrollContainer.new()
	scroll.name = "NotesScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var notes := VBoxContainer.new()
	notes.name = "Notes"
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation", 8)
	_notes = notes
	scroll.add_child(notes)

	column.add_child(_build_buttons())


## 版本芯片：当前（暗铁）→ 最新（余烬）。芯片是一块小铁牌，里面一个小题头 + 一个版本号。
func _build_versions() -> HBoxContainer:
	var versions := HBoxContainer.new()
	versions.name = "Versions"
	versions.alignment = BoxContainer.ALIGNMENT_CENTER
	versions.add_theme_constant_override("separation", 14)
	versions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_current_version = _chip(versions, "CurrentChip", "当 前", "CurrentVersion",
			UiKit.ASH, UiKit.ASH)
	var arrow := UiKit.label("→", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	arrow.name = "VersionArrow"
	arrow.modulate = Color("#B8703E")
	versions.add_child(arrow)
	_remote_version = _chip(versions, "RemoteChip", "最 新", "RemoteVersion",
			UiKit.EMBER_ASH, UiKit.EMBER)
	return versions


## 一枚芯片：小题头 + 版本号。当前是暗铁（小字与数字都压暗），最新是余烬（一眼能找到）。
func _chip(parent: HBoxContainer, chip_name: String, tag: String, value_name: String,
		tag_tint: Color, value_tint: Color) -> Label:
	var chip := UiKit.panel(&"KeyCapPanel")
	chip.name = chip_name
	chip.custom_minimum_size = Vector2(CHIP_W, CHIP_H)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var tag_label := UiKit.label(tag, &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_LEFT)
	tag_label.name = chip_name + "Tag"
	tag_label.modulate = tag_tint
	row.add_child(tag_label)
	var value := UiKit.label("", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_LEFT)
	value.name = value_name
	value.modulate = value_tint
	row.add_child(value)
	parent.add_child(chip)
	return value


func _build_buttons() -> HBoxContainer:
	# 主行动（去下载）用铆钉板；跳过退成次行动的铁按钮，两者一眼分出轻重。
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var go := Button.new()
	go.name = "DownloadButton"
	go.text = "前 往 下 载 页"
	go.theme_type_variation = &"PlateButton"
	go.custom_minimum_size = Vector2(240.0, UiKit.TOUCH_MIN)
	go.focus_mode = Control.FOCUS_ALL
	go.mouse_entered.connect(go.grab_focus)
	go.pressed.connect(_on_download)
	_download_button = go
	buttons.add_child(go)
	var skip := Button.new()
	skip.name = "SkipButton"
	skip.text = "跳 过 此 版 本"
	skip.theme_type_variation = &"SettingsButton"
	skip.custom_minimum_size = Vector2(200.0, UiKit.TOUCH_MIN)
	skip.focus_mode = Control.FOCUS_ALL
	skip.mouse_entered.connect(skip.grab_focus)
	skip.pressed.connect(_on_skip)
	buttons.add_child(skip)
	return buttons


## 打开提示：entry 是 UpdateService 交出的 manifest 字典。
func open(entry: Dictionary) -> void:
	if visible:
		return
	_closing = false
	if _current_version != null:
		_current_version.text = UpdateService.current_version()
	if _remote_version != null:
		_remote_version.text = String(entry.get("version", ""))
	_fill_notes(String(entry.get("notes_zh", "")))
	visible = true
	(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	UiKit.sfx(&"ui_select")
	if _download_button != null:
		_download_button.grab_focus.call_deferred()


## 远端日志按行给：每行一条，行首的项目符号（·、-）自己剥掉，前面换成一根余烬短线。
func _fill_notes(raw: String) -> void:
	if _notes == null:
		return
	for child in _notes.get_children():
		_notes.remove_child(child)
		child.queue_free()
	var lines: Array[String] = []
	for line in raw.split("\n"):
		var text := line.strip_edges()
		if text == "":
			continue
		while text.length() > 1 and (text[0] == "·" or text[0] == "-"):
			text = text.substr(1).strip_edges()
		lines.append(text)
	if _notes_kicker != null:
		_notes_kicker.visible = not lines.is_empty()
	for text in lines:
		var row := HBoxContainer.new()
		row.name = "Note"
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tick := ColorRect.new()
		tick.name = "Tick"
		tick.color = Color(UiKit.EMBER.r, UiKit.EMBER.g, UiKit.EMBER.b, 0.6)
		tick.custom_minimum_size = Vector2(2.0, 14.0)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tick)
		var item := UiKit.label(text, &"BodyLabel")
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item)
		_notes.add_child(row)


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	GameContext.suppress_gameplay_input()
	UiKit.sfx(&"ui_back")
	# 退场动画播完才隐藏：卡片沉回去、纱幕收掉，然后才 emit closed。
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		closed.emit()
	)


func is_open() -> bool:
	return visible


func _on_download() -> void:
	var page := UpdateService.download_page()
	if page != "":
		OS.shell_open(page)
	UiKit.sfx(&"ui_select")
	download_requested.emit()


func _on_skip() -> void:
	UpdateService.skip_version()
	UiKit.sfx(&"ui_back")
	skip_requested.emit()
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		_on_download()
		get_viewport().set_input_as_handled()
