extends CanvasLayer
## 回火试炼入口菜单：赛道 tab + 目标列表 + 记录 / 规则 / 固定装载 + 开始。
##
## 版式沿用现有弹窗语言（ui_modal / MenuList / PlateButton），不新增素材：
## 左侧一列目标（章节或"全部 Boss"），右侧战场档案（记录、固定装载、规则），
## 底部「开始试炼 / 返回标题」。开局后由 TrialRun 接管（pending 机制换场）。
##
## 输入：
##   ←→ / PageUp·PageDown / 肩键   切赛道
##   ↑↓                            选目标（列表行 ≥52 设计像素，鼠标/触控同行）
##   Enter                         开始当前目标
##   Esc                           回标题

signal closed

const Modal := preload("res://scripts/ui/ui_modal.gd")
const TrialRunScript := preload("res://scripts/autoload/trial_run.gd")
const Catalog := preload("res://scripts/data/trial_catalog.gd")
const Records := preload("res://scripts/data/trial_records.gd")
## 结算 overlay 运行时加载（它又依赖 TrialRun，preload 会成环）。
const RESULTS_PATH := "res://scripts/ui/trial_results.gd"
const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"
const TAB_WIDTH := 250.0
const ROW_MIN := 52.0

var _shell: Dictionary = {}
var _root: Control
var _tabs: Array[Button] = []
var _tab_group: ButtonGroup
var _track: int = Catalog.Track.BOSS_RUSH
var _target_menu: MenuList
var _scroll: ScrollContainer
var _targets: Array[Dictionary] = []
var _selected_target := ""
var _locked := false

var _title_label: Label
var _sub_label: Label
var _record_label: Label
var _loadout_label: Label
var _rule_label: Label
var _locked_label: Label
var _empty_label: Label
var _start_button: Button
var _back_button: Button


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	Music.set_state(&"calm")
	Music.set_theme(&"title")
	DisplayFit.apply()
	WorldClock.hold_for_menu()
	var peek := _peek_mode()
	if peek != "":
		# 渲染取证模式：--trial-peek=menu_rush|menu_time|menu_locked|results_s|
		# results_a|results_b|hud_time|hud_boss|hud_retry（见 tools/README 说明）。
		_peek_unlock(peek)
		_peek_window()
	_locked = not Catalog.unlocked()
	_build()
	PresentationMetrics.bind_layer(self)
	select_track(Catalog.Track.BOSS_RUSH)
	if _locked:
		for tab in _tabs:
			tab.disabled = true
	if peek != "":
		_run_peek(peek)


func _exit_tree() -> void:
	WorldClock.release_menu()


# --- 构建 ---------------------------------------------------------------------

func _build() -> void:
	_shell = Modal.build(self, {
		"title": "回 火 试 炼",
		"kicker": "锈 墓 · 试 炼 场",
		"size": Vector2(1120.0, 640.0),
		"hint": "←→ 赛道 · ↑↓ 目标 · Enter 开始",
		"back": "Esc 返回标题",
		"veil": 0.58,
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	var body := _shell["body"] as Control

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)

	_build_tabs(column)

	var main := HBoxContainer.new()
	main.name = "Main"
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 20)
	column.add_child(main)
	_build_target_side(main)
	_build_dossier_side(main)
	_build_footer(column)


func _build_tabs(parent: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	parent.add_child(tabs)
	_tab_group = ButtonGroup.new()
	for i in Catalog.TRACKS.size():
		var track: int = Catalog.TRACKS[i]
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = Catalog.track_name(track)
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.button_group = _tab_group
		tab.focus_mode = Control.FOCUS_ALL
		tab.custom_minimum_size = Vector2(TAB_WIDTH, UiKit.TOUCH_MIN)
		tab.set_meta(&"track", track)
		tab.pressed.connect(select_track.bind(track))
		tab.focus_entered.connect(select_track.bind(track))
		tabs.add_child(tab)
		_tabs.append(tab)


func _build_target_side(parent: HBoxContainer) -> void:
	var plaque := UiKit.panel()
	plaque.name = "Targets"
	plaque.custom_minimum_size = Vector2(520.0, 0.0)
	plaque.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaque.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(plaque)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	plaque.add_child(inner)
	var kicker := UiKit.label("目 标", &"TinyStrongLabel")
	inner.add_child(kicker)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_scroll)
	_empty_label = UiKit.label("", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_empty_label.name = "Empty"
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.add_child(_empty_label)


func _build_dossier_side(parent: HBoxContainer) -> void:
	var plaque := UiKit.panel()
	plaque.name = "Dossier"
	plaque.custom_minimum_size = Vector2(440.0, 0.0)
	plaque.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(plaque)
	# 档案内容可长可短：套一层滚动，卡片的最小高度就不会被文字撑爆
	# （否则底部「开始 / 返回」会被弹窗的提示带挤掉）。
	var scroll := ScrollContainer.new()
	scroll.name = "DossierScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plaque.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	scroll.add_child(inner)

	var kicker := HBoxContainer.new()
	inner.add_child(kicker)
	kicker.add_child(UiKit.label("战 场 档 案", &"TinyStrongLabel"))
	_title_label = _dossier_title()
	inner.add_child(_title_label)
	_sub_label = UiKit.label("", &"TinyLabel", HORIZONTAL_ALIGNMENT_LEFT)
	inner.add_child(_sub_label)
	inner.add_child(UiKit.divider())
	_record_label = UiKit.label("", &"BodyLabel")
	_record_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_record_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(spacer)
	inner.add_child(UiKit.label("固 定 装 载", &"TinyStrongLabel"))
	_loadout_label = _footnote("")
	inner.add_child(_loadout_label)
	inner.add_child(UiKit.label("规 则", &"TinyStrongLabel"))
	_rule_label = _footnote("")
	inner.add_child(_rule_label)
	_locked_label = _footnote("")
	_locked_label.modulate = Color(1.1, 0.85, 0.6)
	inner.add_child(_locked_label)


func _dossier_title() -> Label:
	var label := UiKit.label("", &"SubHeadLabel")
	label.name = "TargetTitle"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _footnote(text: String) -> Label:
	var label := UiKit.label(text, &"FootnoteLabel")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_footer(parent: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	parent.add_child(footer)
	_start_button = _plate_button("开 始 试 炼", &"Start")
	_start_button.pressed.connect(start_selected)
	footer.add_child(_start_button)
	_back_button = _plate_button("返 回 标 题", &"Back")
	_back_button.pressed.connect(_back_to_title)
	footer.add_child(_back_button)


func _plate_button(text: String, node_name: StringName) -> Button:
	var button := Button.new()
	button.name = String(node_name)
	button.text = text
	button.theme_type_variation = &"PlateButton"
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(230.0, UiKit.TOUCH_MIN)
	return button


# --- 赛道 / 目标 ----------------------------------------------------------------

## 切赛道并重排目标列表。键盘 ←→ / 肩键 / 鼠标点 tab 都走这里。
func select_track(track: int, focus_tab: bool = false) -> void:
	if not Catalog.is_valid_track(track):
		return
	_track = track
	for i in _tabs.size():
		var tab: Button = _tabs[i]
		tab.set_pressed_no_signal(int(tab.get_meta(&"track", -1)) == track)
		if int(tab.get_meta(&"track", -1)) == track and focus_tab and tab.is_inside_tree():
			tab.grab_focus()
	_rebuild_targets()


func _rebuild_targets() -> void:
	if _locked:
		_targets = []
	else:
		_targets = Catalog.targets_for(_track)
	if _target_menu != null and is_instance_valid(_target_menu):
		_target_menu.queue_free()
		_target_menu = null
	_target_menu = MenuList.new()
	_target_menu.name = "TargetList"
	_target_menu.add_theme_constant_override("separation", 6)
	_target_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_menu.chosen.connect(_on_target_chosen)
	_scroll.add_child(_target_menu)
	for entry in _targets:
		var row: Dictionary = entry
		var item := _target_menu.add_item(StringName(String(row.get("id", ""))),
				String(row.get("title", "")), false, MenuItem.Kind.DEFAULT)
		item.show_tick = false
		item.custom_minimum_size = Vector2(0.0, ROW_MIN)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_menu.active = not _locked and not _targets.is_empty()
	_empty_label.visible = _targets.is_empty()
	if _targets.is_empty():
		_empty_label.text = _empty_text()
		_selected_target = ""
	else:
		_selected_target = String((_targets[0] as Dictionary).get("id", ""))
		if _target_menu.get_child_count() > 0:
			_target_menu.select(0, false)
	_refresh_dossier()


func _empty_text() -> String:
	if _locked:
		return "试炼尚未解锁。\n通关第七章（钟楼）或走完任一结局后，这里会亮起来。"
	match _track:
		Catalog.Track.BOSS_RUSH:
			return "还没有可以连战的 Boss。\n先推进主线，让 Boss 倒下一次。"
		_:
			return "还没有已通关的章节。\n先在战役里打通一章，再回来计时。"


func _on_target_chosen(id: StringName) -> void:
	_selected_target = String(id)
	_refresh_dossier()
	start_selected()


## 「开始试炼」：交给 TrialRun（它负责 pending 载入与计时）。
func start_selected() -> bool:
	if _locked or _selected_target == "":
		return false
	if _start_button != null:
		_start_button.disabled = true
	return TrialRunScript.start(_track, _selected_target)


func _refresh_dossier() -> void:
	if _title_label == null:
		return
	if _locked:
		_title_label.text = "尚 未 解 锁"
		_sub_label.text = Catalog.unlock_requirement()
		_record_label.text = ""
		_loadout_label.text = "—"
		_rule_label.text = "—"
		_locked_label.text = Catalog.unlock_requirement()
		_start_button.disabled = true
		return
	_locked_label.text = ""
	var has_target := _selected_target != ""
	_title_label.text = Catalog.target_title(_track, _selected_target) if has_target else "—"
	_sub_label.text = Catalog.target_subtitle(_track, _selected_target)
	var summary := Records.summary_line(_track, _selected_target) if has_target else ""
	_record_label.text = ("记 录 · " + summary) if summary != "" else "记 录 · 尚 无"
	_loadout_label.text = Catalog.loadout_summary(_track)
	var rules := PackedStringArray()
	for line in Catalog.track_rules(_track):
		rules.append("· " + String(line))
	if _track == Catalog.Track.BOSS_RUSH:
		rules.append("· 已登记 %d 位 Boss" % Catalog.available_bosses().size())
	_rule_label.text = "\n".join(rules)
	_start_button.disabled = not has_target


func _step_track(step: int) -> void:
	var order := Catalog.TRACKS
	var index := order.find(_track)
	if index < 0:
		index = 0
	select_track(order[posmod(index + step, order.size())], true)


func _back_to_title() -> void:
	closed.emit()
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false
	# 走 TrialRun 的 show_scene（生产里 Director.fade_to，测试里可被 requester 劫持）。
	TrialRunScript.show_scene(TITLE_PATH)


# --- 输入 ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back_to_title()
		get_viewport().set_input_as_handled()
		return
	if _locked:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_page_up") \
			or _is_shoulder(event, JOY_BUTTON_LEFT_SHOULDER):
		_step_track(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_page_down") \
			or _is_shoulder(event, JOY_BUTTON_RIGHT_SHOULDER):
		_step_track(1)
		get_viewport().set_input_as_handled()


func _is_shoulder(event: InputEvent, button: JoyButton) -> bool:
	return event is InputEventJoypadButton and event.pressed \
			and (event as InputEventJoypadButton).button_index == button


# --- 测试 / 工具读数 ------------------------------------------------------------

func track() -> int:
	return _track


func locked() -> bool:
	return _locked


func track_tabs() -> Array[Button]:
	return _tabs


func target_menu() -> MenuList:
	return _target_menu


func target_count() -> int:
	return _targets.size()


func selected_target_id() -> String:
	return _selected_target


func start_button() -> Button:
	return _start_button


func back_button() -> Button:
	return _back_button


func record_text() -> String:
	return _record_label.text if _record_label != null else ""


func loadout_text() -> String:
	return _loadout_label.text if _loadout_label != null else ""


# --- 渲染取证模式（peek） -------------------------------------------------------
# 渲染图优先写 res://screenshots/trial/；沙箱 / 只读工作区写不进时退到 user://trial_peek/，
# 并在 stdout 打印绝对路径。窗口尺寸由命令行 --resolution 决定（任务要求 1280×720）。
# 例：
#   godot --path <repo> --windowed --resolution 1280x720 \
#     res://scenes/ui/TrialMenu.tscn -- --trial-peek=menu_rush

const PEEK_MODES: Array[String] = [
	"menu_rush", "menu_time", "menu_locked",
	"results_s", "results_a", "results_b",
	"hud_time", "hud_boss", "hud_retry",
]


func _peek_mode() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-peek="):
			var mode := arg.trim_prefix("--trial-peek=")
			if PEEK_MODES.has(mode):
				return mode
	return ""


## 固定 1280×720 窗口 + 移出屏幕，渲染取证与 UiPeek 同一口径。
func _peek_window() -> void:
	var win := get_window()
	if win == null:
		return
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(1280, 720)
	win.position = Vector2i(-12000, -12000)


## peek 模式下用内存旗标伪造"已解锁 + 已通关"，绝不写战役档（试炼规则）。
func _peek_unlock(mode: String) -> void:
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""
	if mode == "menu_locked":
		return
	SaveData.mark_flag("trial_unlocked")
	if mode in ["menu_rush", "hud_boss"]:
		SaveData.mark_flag("boss_dead")
		SaveData.mark_flag("nightmare_dead")
	else:
		SaveData.mark_flag("boss_dead")
		SaveData.mark_flag("level07_done")


func _run_peek(mode: String) -> void:
	# _ready 期间 add_child 到 root 会报"parent busy"，等一帧再搭取证场景。
	await get_tree().process_frame
	if mode.begins_with("menu_"):
		if mode == "menu_time":
			select_track(Catalog.Track.TIME_ATTACK)
		_peek_capture(0.9, mode, false)
	elif mode.begins_with("results_"):
		_peek_results(mode)
	elif mode.begins_with("hud_"):
		_peek_hud(mode)


func _peek_results(mode: String) -> void:
	Records.use_file("user://trial_peek_records.cfg")
	Records.delete_file()
	var result := {
		"track": Catalog.Track.TIME_ATTACK,
		"track_id": "time_attack",
		"track_name": "限时疾行",
		"target_id": "level07",
		"target_title": "锈墓・柒 — 钟楼",
		"elapsed_ms": 96000,
		"deaths": 0,
		"no_hit": true,
		"stage_count": 1,
		"rank": "S",
		"is_first": false,
		"is_best": true,
	}
	match mode:
		"results_s":
			result["rank"] = "S"
			result["is_first"] = true
			result["is_best"] = true
			result["elapsed_ms"] = 113000
		"results_a":
			# 先伪造一条更慢的旧记录，让结算读得出"新纪录 / 最佳"文案。
			Records.submit(Catalog.Track.TIME_ATTACK, "level07",
					{"elapsed_ms": 168000, "deaths": 1, "rank": "A"})
			result["rank"] = "A"
			result["elapsed_ms"] = 152000
			result["deaths"] = 1
			result["no_hit"] = false
		_:
			Records.submit(Catalog.Track.TIME_ATTACK, "level07",
					{"elapsed_ms": 120000, "deaths": 0, "rank": "A"})
			result["rank"] = "B"
			result["elapsed_ms"] = 260000
			result["deaths"] = 2
			result["no_hit"] = false
			result["is_best"] = false
	var results: GDScript = load(RESULTS_PATH) as GDScript
	if results != null:
		results.show_result(result)
	_peek_capture(1.1, mode, true)


func _peek_hud(mode: String) -> void:
	await get_tree().process_frame
	var level := "level01" if mode == "hud_boss" else "level07"
	GameContext.pending_world_path = String(GameContext.LEVELS.get(level, ""))
	var packed := load("res://scenes/ui/GamePresentation.tscn") as PackedScene
	var presentation: Node = packed.instantiate()
	get_tree().root.add_child(presentation)
	# 主树已注册 TrialRun autoload 时不要另建第二个实例（会双重推进计时/事件）。
	if get_tree().root.get_node_or_null("TrialRun") == null:
		var run := TrialRunScript.new()
		run.name = "TrialRunPeek"
		get_tree().root.add_child(run)
	# 场景已经手动装好，start() 只登记状态，不再请求换场。
	TrialRunScript.set_scene_requester(func(_path: String) -> void: pass)
	await get_tree().create_timer(0.6, true).timeout
	Director.abort()
	Director.set_letterbox(false, true)
	var started := TrialRunScript.start(Catalog.Track.BOSS_RUSH, Catalog.ALL_BOSSES_ID) \
			if mode == "hud_boss" else TrialRunScript.start(Catalog.Track.TIME_ATTACK, level)
	if not started:
		printerr("TRIAL_PEEK could not start trial ", mode)
		get_tree().quit(1)
		return
	await get_tree().create_timer(2.0, true).timeout
	Director.abort()
	Director.set_letterbox(false, true)
	if mode == "hud_retry":
		TrialRunScript.on_player_died()
		await get_tree().create_timer(0.25, true).timeout
	visible = false
	_peek_capture(0.2, mode, false)


func _peek_capture(delay: float, name: String, keep_paused: bool) -> void:
	await get_tree().create_timer(delay, true, false, true).timeout
	if not keep_paused:
		Director.abort()
		Director.set_letterbox(false, true)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	for dir in ["res://screenshots/trial", "user://trial_peek"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(String(dir)))
		var path: String = String(dir) + "/" + name + "_1280x720.png"
		if image.save_png(path) == OK:
			print("TRIAL_PEEK ", name, " saved=", ProjectSettings.globalize_path(path),
					" size=", image.get_size())
			get_tree().quit(0)
			return
	printerr("TRIAL_PEEK could not save ", name)
	get_tree().quit(1)


func title_text() -> String:
	return _title_label.text if _title_label != null else ""
