class_name PauseMenu
extends CanvasLayer
## 暂停菜单：Esc 开合，继续 / 设置 / 教程回看 / 操作说明 / 地图 / 返回标题。
##
## 整棵子树 PROCESS_MODE_ALWAYS，所以 get_tree().paused 之后自己还能动。
## 全屏、像素平滑、音量、键位等选项都搬进了设置界面（SettingsScreen）；
## 从这里打开设置 / 教程回看 / 操作说明 / 地图都只是在它们上面再盖一层，
## 不碰暂停状态，关闭后菜单光标回到原来那一行。

const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"

const ID_RESUME := &"resume"
const ID_SETTINGS := &"settings"
const ID_TUTORIAL := &"tutorial"
const ID_CONTROLS := &"controls"
const ID_MAP := &"map"
const ID_TITLE := &"title"

var _root: Control
var _menu: MenuList
var _res_label: Label
var _controls: ControlsPanel
var _settings: SettingsScreen
var _tutorial: TutorialRecall
var _map: MapScreen
## Esc during a scene fade (respawn fade-in, chapter arrival, Continue) used to be
## dropped without a sound; the request is now kept and honoured once the fade ends.
var _open_requested := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	WorldClock.isolate_ui_layer(self)
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# 整屏遮罩：2.5K 上半透明卡片会把左上角心槽透出来，先铺实底再压一层渐变。
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(UiKit.SCRIM.r, UiKit.SCRIM.g, UiKit.SCRIM.b, 0.90)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(veil)
	_root.add_child(UiKit.scrim(0.46, 0.22, 0.58))

	var frame := UiKit.panel(&"OrnatePanel")
	frame.name = "PauseFrame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 120.0
	frame.offset_right = -120.0
	frame.offset_top = 36.0
	frame.offset_bottom = -36.0
	_root.add_child(frame)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(column)
	column.add_child(UiKit.label("暂 停", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())

	_menu = MenuList.new()
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_menu)
	_menu.add_item(ID_RESUME, "回 到 锈 墓")
	_menu.add_item(ID_SETTINGS, "设 置")
	_menu.add_item(ID_TUTORIAL, "教 程 回 看")
	_menu.add_item(ID_CONTROLS, "操 作 说 明")
	_menu.add_item(ID_MAP, "地 图")
	_menu.add_item(ID_TITLE, "返 回 标 题")
	_menu.chosen.connect(_on_chosen)

	_res_label = UiKit.label("视口: %s" % DisplayFit.get_resolution_string(),
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_res_label)
	column.add_child(UiKit.label("进度在余烬巢刻录 · 回标题不会丢档",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER))

	_controls = ControlsPanel.new()
	_controls.layer = 21
	_controls.closed.connect(_resume_menu)
	add_child(_controls)
	_settings = SettingsScreen.new()
	_settings.layer = 22
	_settings.closed.connect(_resume_menu)
	add_child(_settings)
	_tutorial = TutorialRecall.new()
	_tutorial.layer = 21
	_tutorial.closed.connect(_resume_menu)
	add_child(_tutorial)
	_map = MapScreen.new()
	_map.layer = 21
	_map.closed.connect(_resume_menu)
	add_child(_map)


func is_open() -> bool:
	return visible


## 是否有子界面（设置 / 回看 / 说明 / 地图）盖在菜单上。
func sub_screen_open() -> bool:
	return _controls.visible or _settings.visible or _tutorial.visible or _map.visible


func _resume_menu() -> void:
	_menu.active = true


func open() -> void:
	# 淡入淡出换关的 0.45 秒里暂停，下一关会带着 paused / suspended 加载出来。
	# 所以淡变期间只记下请求，淡变结束再开（见 _process），而不是吞掉这次 Esc。
	if visible or Director.choice_hold:
		return
	if Director.is_fading():
		_open_requested = true
		return
	_open_requested = false
	visible = true
	_menu.active = true
	_set_play_hud_visible(false)
	if _res_label != null:
		_res_label.text = "视口: %s" % DisplayFit.get_resolution_string()
	get_tree().paused = true
	Director.suspend()
	UiKit.sfx(&"ui_pause", &"ui_select")


## 淡变期间按下、还没兑现的暂停请求。
func open_pending() -> bool:
	return _open_requested


func _process(_delta: float) -> void:
	if not _open_requested:
		return
	if Director.choice_hold or not is_inside_tree():
		_open_requested = false
		return
	if not Director.is_fading():
		open()


func close() -> void:
	_open_requested = false
	if not visible:
		return
	_controls.visible = false
	_tutorial.visible = false
	_map.visible = false
	if _settings.visible:
		_settings.close()
	visible = false
	_set_play_hud_visible(true)
	Sfx.play(&"ui_back")
	if Director.choice_hold:
		return
	get_tree().paused = false
	Director.resume()


func _set_play_hud_visible(show: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var chrome := parent.get_node_or_null("Root") as CanvasItem
	if chrome != null:
		chrome.visible = show


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if Director.choice_hold and not visible:
		return
	# 子界面自己会吃掉 ui_cancel，走到这里说明它们没开着。
	# 淡变中再按一次 = 收回刚才的暂停请求。
	if _open_requested and not visible:
		_open_requested = false
	elif visible:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func _on_chosen(id: StringName) -> void:
	match id:
		ID_RESUME:
			close()
		ID_SETTINGS:
			_menu.active = false
			_settings.open()
		ID_TUTORIAL:
			_menu.active = false
			_tutorial.open()
		ID_CONTROLS:
			_menu.active = false
			_controls.open()
		ID_MAP:
			_menu.active = false
			_map.open()
		ID_TITLE:
			get_tree().paused = false
			Director.resume()
			Director.fade_to(TITLE_PATH)


# --- 测试用 -------------------------------------------------------------------

func menu() -> MenuList:
	return _menu


func settings_screen() -> SettingsScreen:
	return _settings


func tutorial_recall() -> TutorialRecall:
	return _tutorial


func map_screen() -> MapScreen:
	return _map


func controls_panel() -> ControlsPanel:
	return _controls
