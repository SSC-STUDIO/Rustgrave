extends CanvasLayer
## 回火试炼结算 overlay：试炼判决。用时 / 统计两格夹着一枚大号评级印记（菱形章，字在章心），
## 印记底下挂「新纪录 / 首通」的小牌；底下一行记录文字；最底下三个出口（再来一次为主行动）。
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

## 判决行的尺寸：两格读数等高，与中间的印记 + 小牌同高。
const CELL_W := 264.0
const CELL_H := 148.0
const SEAL_SIZE := 116.0
## 评级字母的字号：12px 像素字的整数倍（6 倍），不做小数缩放。
const LETTER_SIZE := 72

static var _open: CanvasLayer = null

var _result: Dictionary = {}
var _shell: Dictionary = {}
var _menu: MenuList
var _track_label: Label
var _time_label: Label
var _seal: RankSeal
var _badge_panel: PanelContainer
var _badge_label: Label
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
		"kicker": "试 炼 判 决",
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
	column.add_theme_constant_override("separation", 6)
	body.add_child(column)

	# 题头：赛道 · 目标，一行写完。
	_track_label = UiKit.label(_track_line(), &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_track_label.name = "TrackLine"
	column.add_child(_track_label)

	# 判决：左格读用时，中间是评级印记（下挂新纪录 / 首通的小牌），右格读统计。
	var verdict := HBoxContainer.new()
	verdict.name = "Verdict"
	verdict.alignment = BoxContainer.ALIGNMENT_CENTER
	verdict.add_theme_constant_override("separation", 20)
	column.add_child(verdict)

	_time_label = UiKit.label(Records.format_ms(int(_result.get("elapsed_ms", 0))),
			&"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_time_label.name = "Time"
	verdict.add_child(_readout("用 时", "TimeCell", _time_label))

	var center := VBoxContainer.new()
	center.name = "Seal"
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 6)
	verdict.add_child(center)
	_seal = RankSeal.new()
	_seal.name = "Rank"
	_seal.custom_minimum_size = Vector2(SEAL_SIZE, SEAL_SIZE)
	var rank := StringName(String(_result.get("rank", "B")))
	_seal.letter = String(rank)
	_seal.tint = Catalog.rank_color(rank)
	center.add_child(_seal)
	_badge_panel = UiKit.panel(&"KeyCapPanel")
	_badge_panel.name = "Badge"
	_badge_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_badge_label = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_badge_label.name = "BadgeText"
	_badge_panel.add_child(_badge_label)
	center.add_child(_badge_panel)

	_stats_label = UiKit.label(_stats_line(), &"BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_stats_label.name = "Stats"
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.add_child(_readout("统 计", "StatsCell", _stats_label))

	_record_label = UiKit.label(_record_line(), &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
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
	_menu.add_theme_constant_override("separation", 6)
	column.add_child(_menu)
	_menu.compact(_menu.add_item(ID_RETRY, "再 来 一 次", false, MenuItem.Kind.PRIMARY))
	_menu.compact(_menu.add_item(ID_TRACKS, "换 条 赛 道", false, MenuItem.Kind.SECONDARY))
	_menu.compact(_menu.add_item(ID_TITLE, "回 标 题", false, MenuItem.Kind.GHOST))
	_menu.chosen.connect(_on_chosen)

	_refresh_badge()


## 一格读数：小题头 + 大值，半透明的切角小格（与判决的印记同一个视觉重心）。
func _readout(kicker_text: String, cell_name: String, value: Label) -> Control:
	var cell := ReadoutCell.new()
	cell.name = cell_name
	cell.custom_minimum_size = Vector2(CELL_W, CELL_H)
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18.0
	box.offset_top = 12.0
	box.offset_right = -18.0
	box.offset_bottom = -12.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	cell.add_child(box)
	box.add_child(GlassKit.kicker(kicker_text, HORIZONTAL_ALIGNMENT_CENTER))
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(value)
	return cell


func _track_line() -> String:
	var track := String(_result.get("track_name", "试炼"))
	var target := String(_result.get("target_title", ""))
	return track if target == "" else track + " · " + target


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
	if _badge_panel != null:
		_badge_panel.visible = _badge_label.text != ""


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
	return _seal.letter if _seal != null else ""


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


## 评级印记：菱形章（与标题的结局印记同一套菱形语汇放大），中心一个评级字母，两侧各一道细线。
## 颜色随评级（S 余烬金 / A 锈橙 / B 灰烬）；字母用 12px 像素字的 6 倍绘制。
class RankSeal extends Control:
	var letter := "":
		set(value):
			letter = value
			queue_redraw()
	var tint: Color = GlassKit.EMBER:
		set(value):
			tint = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5))
		var line := Color(tint.r, tint.g, tint.b, 0.4)
		draw_rect(Rect2(c.x - 90.0, c.y, 50.0, 2.0), line)
		draw_rect(Rect2(c.x + 40.0, c.y, 50.0, 2.0), line)
		GlassKit.diamond(self, c, 56.0, Color(tint.r, tint.g, tint.b, 0.14))
		GlassKit.diamond(self, c, 52.0, tint)
		GlassKit.diamond(self, c, 45.0, GlassKit.INK)
		GlassKit.diamond(self, c, 41.0, Color(tint.r, tint.g, tint.b, 0.35))
		GlassKit.diamond(self, c, 37.0, GlassKit.INK)
		var font := get_theme_default_font()
		if font != null and letter != "":
			var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_SIZE).x
			draw_string(font, Vector2(floorf(c.x - width * 0.5), floorf(c.y + float(LETTER_SIZE) * 0.36)),
					letter, HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_SIZE, tint)


## 判决行里的读数格：半透明的 2px 阶梯切角小格，不做落影（比标题档案卡轻一级）。
class ReadoutCell extends Control:
	const FILL := Color(0.05, 0.035, 0.07, 0.62)
	const BORDER := Color("#4A2A18")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(4.0, 0.0, w - 8.0, h), FILL)
		draw_rect(Rect2(2.0, 2.0, w - 4.0, h - 4.0), FILL)
		draw_rect(Rect2(0.0, 4.0, w, h - 8.0), FILL)
		draw_rect(Rect2(4.0, 0.0, w - 8.0, 1.0), BORDER)
		draw_rect(Rect2(4.0, h - 1.0, w - 8.0, 1.0), BORDER)
		draw_rect(Rect2(0.0, 4.0, 1.0, h - 8.0), BORDER)
		draw_rect(Rect2(w - 1.0, 4.0, 1.0, h - 8.0), BORDER)
