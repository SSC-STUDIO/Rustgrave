class_name PauseMenu
extends CanvasLayer
## 暂停菜单：Esc 开合；左列是"铁架"式动作栏，右列是本次行程的档案卡。
##
## 版式沿用标题屏那套语言：主行动（回到锈墓）是一整块箭头板，系统类动作是燕尾小板，
## 回标题是只有四只角标的第三层，中间用铆钉横线分组；右列的石头档案板放章节、当前目标、
## 剑核、余烬巢和视口—— HUD 只报"此刻"，暂停屏回答"我在哪、还剩什么"。
##
## 整棵子树 PROCESS_MODE_ALWAYS，所以 get_tree().paused 之后自己还能动。
## 全屏、像素平滑、音量、键位等选项都搬进了设置界面（SettingsScreen）；
## 从这里打开设置 / 教程回看 / 操作说明 / 地图都只是在它们上面再盖一层，
## 不碰暂停状态，关闭后菜单光标回到原来那一行。

const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"
const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Modal := preload("res://scripts/ui/ui_modal.gd")

const ID_RESUME := &"resume"
const ID_SETTINGS := &"settings"
const ID_TUTORIAL := &"tutorial"
const ID_CONTROLS := &"controls"
const ID_MAP := &"map"
const ID_TITLE := &"title"

## 左列铁架：竖脊贴左缘，板面从 RAIL_X 挂出去；行距由空白节点控，主/次/第三层分开。
const RAIL_X := 24.0
const RAIL_W := 482.0
const DIVIDER_W := 440.0
const MENU_TOP := 8.0
const GAP_GROUP := 18.0
const GAP_DIVIDER := 14.0
const GAP_SECONDARY := 6.0
const RAIL_H := 424.0
## 右列档案卡的固定键列宽（12px 小字，和 HUD 的紧凑小字同档）。
const KEY_COLUMN := 92.0

var _root: Control
var _shell: Dictionary = {}
var _layout: Control
var _menu: MenuList
var _controls: ControlsPanel
var _settings: SettingsScreen
var _tutorial: TutorialRecall
var _map: MapScreen
## Esc during a scene fade (respawn fade-in, chapter arrival, Continue) used to be
## dropped without a sound; the request is now kept and honoured once the fade ends.
var _open_requested := false

var _dossier_chapter: Label
var _dossier_objective: Label
var _dossier_cores: Label
var _dossier_nests: Label
var _dossier_viewport: Label
var _tracker: ObjectiveTracker


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	WorldClock.isolate_ui_layer(self)
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	# 暂停菜单也是"弹出来的卡片"：卡片四周还看得见被压暗的战场，而不是一整页紫板。
	_shell = Modal.build(self, {
		"title": "暂 停",
		"size": Vector2(1020.0, 640.0),
		"hint": "↑↓ 选择 · Enter 确认",
		"back": "Esc 继续",
		"veil": 0.62,
	})
	_root = _shell["root"] as Control
	var body := _shell["body"] as Control

	var layout := HBoxContainer.new()
	layout.name = "PauseLayout"
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 28)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout = layout
	body.add_child(layout)
	_build_rail(layout)
	_build_dossier(layout)

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
	_refresh_dossier()


## 左列：标题 + 铆钉横线 + 挂在竖脊上的六格动作。
func _build_rail(parent: Control) -> void:
	var rail := Control.new()
	rail.name = "Rail"
	rail.custom_minimum_size = Vector2(RAIL_W, RAIL_H)
	rail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rail)

	_menu = MenuList.new()
	_menu.name = "Menu"
	# 行距交给下面的空白节点：主行动 / 系统动作 / 回标题三档之间要不同的呼吸。
	_menu.add_theme_constant_override("separation", 0)
	_menu.position = Vector2(RAIL_X, MENU_TOP)
	rail.add_child(_menu)

	_menu.add_item(ID_RESUME, "回 到 锈 墓", false, MenuItem.Kind.PRIMARY)
	_gap(GAP_GROUP)
	_menu.add_child(_rail_divider())
	_gap(GAP_DIVIDER)
	var systems := [[ID_SETTINGS, "设 置"], [ID_MAP, "地 图"],
			[ID_TUTORIAL, "教 程 回 看"], [ID_CONTROLS, "操 作 说 明"]]
	for i in systems.size():
		_menu.add_item(StringName(systems[i][0]), String(systems[i][1]), false,
				MenuItem.Kind.SECONDARY)
		if i + 1 < systems.size():
			_gap(GAP_SECONDARY)
	_menu.add_item(ID_TITLE, "返 回 标 题", false, MenuItem.Kind.GHOST)
	_menu.reset_size()
	_menu.chosen.connect(_on_chosen)

	# 竖脊串起六格；两端铆钉+中段菱形和标题屏是同一只铁件。
	var spine := Ornaments.spine(_menu.size.y - 16.0)
	spine.name = "Spine"
	spine.position = Vector2(0.0, MENU_TOP + 6.0)
	rail.add_child(spine)
	rail.move_child(spine, 0)


## 右列：石头档案板（章节 / 目标 / 剑核 / 余烬巢 / 视口）+ 底部两行提示。
func _build_dossier(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.name = "DossierColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	parent.add_child(column)

	var plaque := UiKit.panel()
	plaque.name = "Dossier"
	plaque.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(plaque)

	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 8)
	plaque.add_child(inner)

	var kicker := HBoxContainer.new()
	kicker.add_theme_constant_override("separation", 10)
	inner.add_child(kicker)
	var tag := UiKit.label("行 程 档 案", &"TinyStrongLabel")
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kicker.add_child(tag)
	var stub := Ornaments.stub_rule(false)
	stub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kicker.add_child(stub)

	_dossier_chapter = _dossier_row(inner, "章 节")
	_dossier_objective = _dossier_row(inner, "目 标")
	_dossier_cores = _dossier_row(inner, "锈 核")
	_dossier_nests = _dossier_row(inner, "余 烬 巢")
	_dossier_viewport = _dossier_row(inner, "视 口")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(spacer)

	var rule := Ornaments.stub_rule(true)
	rule.name = "DossierRule"
	inner.add_child(rule)
	inner.add_child(UiKit.label("剑核随时可在插座台换装 · 进度在余烬巢刻录",
			&"FootnoteLabel"))


## 一行档案：左边 12px 的键，右边 24px 的值（值可换行，章节名/目标句可能很长）。
func _dossier_row(parent: VBoxContainer, key: String) -> Label:
	var row := HBoxContainer.new()
	row.name = "Row_" + key.replace(" ", "")
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var key_label := UiKit.label(key, &"TinyStrongLabel")
	key_label.custom_minimum_size = Vector2(KEY_COLUMN, 0.0)
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(key_label)
	var value := UiKit.label("—", &"BodyLabel")
	value.name = "Value"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value)
	return value


func _rail_divider() -> Control:
	var rule := Ornaments.rivet_rule(DIVIDER_W)
	rule.name = "RailDivider"
	return rule


func _gap(height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(spacer)


## 每次打开都重算一遍：章节、当前目标、剑核、余烬巢、视口都可能变过。
func _refresh_dossier() -> void:
	_dossier_chapter.text = _chapter_title()
	_dossier_objective.text = _objective_line()
	_dossier_cores.text = _cores_summary()
	_dossier_nests.text = "已刻录 %d 处" % SaveData.lit_nests.size()
	_dossier_viewport.text = DisplayFit.get_resolution_string()


## 当前章节名：与地图共用 MapScreen.chapter_title() 这一份口径，避免档案卡和
## 地图对同一关写出两个名字（第一章的名字只在开场分镜里写一次）。
func _chapter_title() -> String:
	var title := MapScreen.chapter_title(GameContext.world_root(self))
	return title if title != "" else "—"


func _objective_line() -> String:
	var world := GameContext.world_root(self)
	var player := get_tree().get_first_node_in_group("player") as Player
	if world == null or player == null:
		return "—"
	if _tracker == null:
		_tracker = ObjectiveTracker.new()
	_tracker.scan(world)
	var line := _tracker.line(player)
	return line.trim_prefix("目标 · ") if line != "" else "—"


func _cores_summary() -> String:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.inventory == null:
		return "—"
	var sockets := player.inventory.sockets
	var filled := 0
	for core in sockets:
		if core != null:
			filled += 1
	return "剑 %d/%d · 囊 %d" % [filled, sockets.size(), player.inventory.pouch.size()]


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
	_refresh_dossier()
	(_shell.get("play_intro") as Callable).call()
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


func dossier_label(key: String) -> Label:
	match key:
		"chapter":
			return _dossier_chapter
		"objective":
			return _dossier_objective
		"cores":
			return _dossier_cores
		"nests":
			return _dossier_nests
		"viewport":
			return _dossier_viewport
	return null
