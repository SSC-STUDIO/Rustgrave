extends CanvasLayer
## 回火试炼结算 overlay：用时 / 死亡 / 评级 / 记录，三个出口（再来一次 / 换赛道 / 回标题）。
##
## 只被 TrialRun.finish() 创建；不读战役存档，记录文本全部来自 TrialRecords。
## 打开期间暂停 SceneTree（结算不是"还要继续打"的场景），关闭时恢复。

signal dismissed

const Modal := preload("res://scripts/ui/ui_modal.gd")
const TrialRunScript := preload("res://scripts/autoload/trial_run.gd")
const Catalog := preload("res://scripts/data/trial_catalog.gd")
const Records := preload("res://scripts/data/trial_records.gd")

const ID_RETRY := &"retry"
const ID_TRACKS := &"tracks"
const ID_TITLE := &"title"

static var _open: CanvasLayer = null

var _result: Dictionary = {}
var _shell: Dictionary = {}
var _menu: MenuList
var _time_label: Label
var _rank_label: Label
var _badge_label: Label
var _track_label: Label
var _stats_label: Label
var _record_label: Label


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if _open == self:
		_open = null


static func show_result(result: Dictionary) -> CanvasLayer:
	close_all()
	# 本文件没有 class_name（多 agent 类缓存不可靠），实例化走脚本资源自己。
	var script := load("res://scripts/ui/trial_results.gd") as GDScript
	if script == null:
		return null
	var node: CanvasLayer = script.new()
	node.name = "TrialResults"
	node.set("_result", result.duplicate(true))
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	tree.root.add_child(node)
	_open = node
	node.call_deferred("_begin")
	return node


static func close_all() -> void:
	if _open != null and is_instance_valid(_open):
		var layer := _open
		_open = null
		layer.call("_release")
		layer.queue_free()


static func is_open() -> bool:
	return _open != null and is_instance_valid(_open)


static func open_instance() -> CanvasLayer:
	return _open if is_instance_valid(_open) else null


func result_data() -> Dictionary:
	return _result.duplicate(true)


# --- 构建 ---------------------------------------------------------------------

func _begin() -> void:
	_build()
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree != null:
		tree.paused = true
	if _menu != null:
		_menu.select(0, false)


func _build() -> void:
	_shell = Modal.build(self, {
		"title": "回 火 试 炼 · 结 算",
		"size": Vector2(900.0, 600.0),
		"hint": "↑↓ 选择 · Enter 确认",
		"back": "Esc 回标题",
		"veil": 0.66,
	})
	var root := _shell["root"] as Control
	root.theme = UiKit.extras_theme()
	var body := _shell["body"] as Control

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)

	_track_label = UiKit.label(String(_result.get("track_name", "试炼")), &"SubHeadLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	_track_label.name = "TrackLine"
	column.add_child(_track_label)
	column.add_child(UiKit.divider())

	# 大数字行：用时 + 评级徽记。
	var numbers := HBoxContainer.new()
	numbers.name = "Numbers"
	numbers.alignment = BoxContainer.ALIGNMENT_CENTER
	numbers.add_theme_constant_override("separation", 26)
	column.add_child(numbers)
	_time_label = UiKit.label(Records.format_ms(int(_result.get("elapsed_ms", 0))),
			&"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_time_label.name = "Time"
	numbers.add_child(_time_label)
	_rank_label = UiKit.label(String(_result.get("rank", "B")), &"HeadLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	_rank_label.name = "Rank"
	_rank_label.add_theme_color_override("font_color",
			Catalog.rank_color(StringName(String(_result.get("rank", "B")))))
	numbers.add_child(_rank_label)
	_badge_label = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_badge_label.name = "Badge"
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	numbers.add_child(_badge_label)

	_stats_label = UiKit.label(_stats_line(), &"BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_stats_label.name = "Stats"
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stats_label)

	_record_label = UiKit.label(_record_line(), &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_record_label.name = "Record"
	_record_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_record_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_menu = MenuList.new()
	_menu.name = "Menu"
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu.add_theme_constant_override("separation", 8)
	column.add_child(_menu)
	_menu.compact(_menu.add_item(ID_RETRY, "再 来 一 次", false, MenuItem.Kind.PRIMARY))
	_menu.compact(_menu.add_item(ID_TRACKS, "换 条 赛 道", false, MenuItem.Kind.SECONDARY))
	_menu.compact(_menu.add_item(ID_TITLE, "回 标 题", false, MenuItem.Kind.GHOST))
	_menu.chosen.connect(_on_chosen)

	_refresh_badge()


func _stats_line() -> String:
	var parts := PackedStringArray()
	parts.append("死亡 %d" % int(_result.get("deaths", 0)))
	if int(_result.get("stage_count", 1)) > 1:
		parts.append("第 %d/%d 场" % [int(_result.get("stage_count", 1)),
				int(_result.get("stage_count", 1))])
	if bool(_result.get("no_hit", false)):
		parts.append("无 伤")
	parts.append(Catalog.track_tagline(int(_result.get("track", 0))))
	return " · ".join(parts)


func _record_line() -> String:
	var track := int(_result.get("track", -1))
	var target := String(_result.get("target_id", ""))
	if bool(_result.get("is_first", false)):
		return "首 次 通 过"
	var summary := Records.summary_line(track, target)
	if summary == "":
		return "首 次 通 过"
	if bool(_result.get("is_best", false)):
		return "新 纪 录 ！  之 前 最 佳 · " + summary
	return "最 佳 记 录 · " + summary


func _refresh_badge() -> void:
	if _badge_label == null:
		return
	if bool(_result.get("is_first", false)):
		_badge_label.text = "首 通"
	elif bool(_result.get("is_best", false)):
		_badge_label.text = "新 纪 录"
	else:
		_badge_label.text = ""


# --- 出口 ---------------------------------------------------------------------

func _on_chosen(id: StringName) -> void:
	match id:
		ID_RETRY:
			_leave(func() -> void:
				TrialRunScript.start(int(_result.get("track", 0)),
						String(_result.get("target_id", ""))))
		ID_TRACKS:
			_leave(func() -> void: TrialRunScript.exit_to_menu())
		ID_TITLE:
			_leave(func() -> void: TrialRunScript.exit_to_title())


func _leave(action: Callable) -> void:
	_release()
	dismissed.emit()
	queue_free()
	if action.is_valid():
		action.call()


## 解除"结算中"的暂停（关闭 / 被 TrialRun 清屏时都会走这里）。
func _release() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree != null and tree.paused:
		tree.paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_chosen(ID_TITLE)
		get_viewport().set_input_as_handled()


# --- 测试 / 工具读数 ------------------------------------------------------------

func time_text() -> String:
	return _time_label.text if _time_label != null else ""


func rank_text() -> String:
	return _rank_label.text if _rank_label != null else ""


func badge_text() -> String:
	return _badge_label.text if _badge_label != null else ""


func stats_text() -> String:
	return _stats_label.text if _stats_label != null else ""


func record_text() -> String:
	return _record_label.text if _record_label != null else ""


func track_text() -> String:
	return _track_label.text if _track_label != null else ""


func menu() -> MenuList:
	return _menu
