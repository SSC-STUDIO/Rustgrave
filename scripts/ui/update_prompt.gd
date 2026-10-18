class_name UpdatePrompt
extends CanvasLayer
## 更新提示：发现新版本时弹出的模态卡。列出更新日志与当前/远端版本号，
## 给两个出口——去下载页（桌面版唤起浏览器）和跳过此版本。
## exe/zip 包不做内置自更新：Godot 的热更新要么换 pck 要么走应用商店，
## 都不适合一个绿色版小游戏；把玩家带到下载页是最诚实也最省事的一条路。

signal closed
signal download_requested
signal skip_requested

const Modal := preload("res://scripts/ui/ui_modal.gd")

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _current_version: Label
var _remote_version: Label
var _notes: VBoxContainer
var _download_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_shell = Modal.build(self, {
		"kicker": "RELEASE",
		"title": "有新版本",
		"size": Vector2(760.0, 520.0),
		"hint": "Enter 前往下载 · Esc 稍后再说",
		"back": "Esc 稍后再说",
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	var body := _shell["body"] as Control

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)

	# 版本行：当前 → 远端。数字用等宽余烬色，箭头用暗铁，一眼看清"我在哪、要去哪"。
	var versions := HBoxContainer.new()
	versions.name = "Versions"
	versions.alignment = BoxContainer.ALIGNMENT_CENTER
	versions.add_theme_constant_override("separation", 12)
	versions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(versions)
	var current := UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	current.name = "CurrentVersion"
	current.custom_minimum_size = Vector2(150.0, 0.0)
	current.modulate = UiKit.ASH
	_current_version = current
	versions.add_child(current)
	var arrow := UiKit.label("→", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	arrow.name = "VersionArrow"
	arrow.modulate = Color("#B8703E")
	versions.add_child(arrow)
	var remote := UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_LEFT)
	remote.name = "RemoteVersion"
	remote.custom_minimum_size = Vector2(150.0, 0.0)
	remote.modulate = UiKit.EMBER
	_remote_version = remote
	versions.add_child(remote)

	# 更新日志：远端给的是多行文本，按行拆成小条目，行距比正文松一档，
	# 扫读时一条一条落下来，而不是挤成一团。
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

	# 按钮行：主行动（去下载）做成铆钉板按钮，次行动（跳过）退成幽灵键。
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
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
	skip.theme_type_variation = &"PlateButton"
	skip.custom_minimum_size = Vector2(200.0, UiKit.TOUCH_MIN)
	skip.focus_mode = Control.FOCUS_ALL
	skip.mouse_entered.connect(skip.grab_focus)
	skip.pressed.connect(_on_skip)
	buttons.add_child(skip)


## 打开提示：entry 是 UpdateService 交出的 manifest 字典。
func open(entry: Dictionary) -> void:
	if visible:
		return
	_closing = false
	if _current_version != null:
		_current_version.text = "当前 " + UpdateService.current_version()
	if _remote_version != null:
		_remote_version.text = "新版 " + String(entry.get("version", ""))
	if _notes != null:
		for child in _notes.get_children():
			_notes.remove_child(child)
			child.queue_free()
		for line in String(entry.get("notes_zh", "")).split("\n"):
			var text := line.strip_edges()
			if text == "":
				continue
			# 远端日志按行给，行首的项目符号（·、-）自己剥掉：
			# Modal 里已经有板面分隔，再挂一排符号就是两层装饰打架。
			while text.length() > 1 and (text[0] == "·" or text[0] == "-"):
				text = text.substr(1).strip_edges()
			var item := UiKit.label(text, &"BodyLabel")
			item.name = "Note"
			item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_notes.add_child(item)
	visible = true
	(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	UiKit.sfx(&"ui_select")
	if _download_button != null:
		_download_button.grab_focus.call_deferred()


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
