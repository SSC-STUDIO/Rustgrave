extends CanvasLayer
## 标题「回看余烬」总结页：通关后（或随时从旅程列的「回看余烬」进来）看一眼这趟旅程——
## 结局、已过的章数、前情一句，以及从这里出发的所有入口：
##   继 续 旅 程     直接读档接着走（总结页不吞掉「继续」）
##   重 温 序 章 / 重 温 结 局   把看过的分镜再看一遍（回放时本页先藏起来，播完回来）
##   余 烬 竞 技 场 / 回 火 试 炼   两个模式入口（试炼未解锁时置灰）
##   返 回
##   再 入 某 章      已通关的每一章各一行，从该章入口重新出发
##
## 外壳与其他弹窗一致（ui_modal.gd 的 OrnatePanel 卡片）。左列是铁条菜单（内容多，包在 ScrollContainer
## 里，↑↓ / 手柄方向键换行，光标会带着滚动条走）；右侧是半透明的旅程档案板（结局印记、前情、章节刻度、
## 结局三格），不随列表滚动。Esc 或点卡片外返回。
##
## 本页只发信号，不碰存档 / 场景：TitleScreen 接 continue_requested / arena_requested /
## trial_requested / chapter_requested 去做真正的事。flags 一律由调用方传进来
## （标题刚启动时 SaveData.flags 还没读档，要用 TitleWorld.peek_save() 合并过磁盘的那份）。
##
## 本文件不写 class_name：TitleScreen 按 preload 取用（避开 .godot 类缓存）。

signal closed
## dismiss()（不走退场动画的关闭）时发出：标题要接着做别的事，菜单也要跟着回来。
signal dismissed
signal continue_requested
signal arena_requested
signal trial_requested
signal chapter_requested(chapter_id: String)
signal replay_started(board_id: String)
signal replay_finished(board_id: String)

const Modal := preload("res://scripts/ui/ui_modal.gd")
const Boards := preload("res://scripts/data/storyboards.gd")
const ReplayScript := preload("res://scripts/ui/board_replay.gd")

const ID_CONTINUE := &"continue"
const ID_ARENA := &"arena"
const ID_TRIAL := &"trial"
const ID_BACK := &"back"
const ID_PROLOGUE := &"replay_prologue"
const ROW_ENDING := "replay_ending_"
const ROW_CHAPTER := "chapter_"
const NO_ENDING_HEADING := "尚无结局"
const UNKNOWN_ENDING_NAME := "旅程已终"
const CARD_SIZE := Vector2(900.0, 672.0)
## 左侧菜单列的最小宽度：要小于正文宽的 DOSSIER_SPLIT 部分，否则会把滚动区撑出卡片左半边。
const MENU_WIDTH := 400.0
## 菜单列占正文宽度的比例；剩下的右侧是旅程档案板。
const DOSSIER_SPLIT := 0.52
const DOSSIER_GAP := 16.0
## 两列题头距卡片正文顶边的距离：左列「行程入口」与右侧「旅程档案」落在同一行。
const HEAD_TOP := 36.0
const ENDING_KINDS := ["give", "keep", "snuff"]
## 结局印记与结局三格的颜色：还火金、守炉橙、熄火灰紫；没有结局用冷铁。
const ENDING_COLORS := {
	"give": Color("#FFC14A"),
	"keep": Color("#D9743A"),
	"snuff": Color("#8C8290"),
}

var _root: Control
var _shell: Dictionary = {}
var _scroll: ScrollContainer
var _content: VBoxContainer
var _column: VBoxContainer
var _snap_pad: Control
var _menu: MenuList
var _more: Label
var _pinned: Control
var _follow_pin := false
var _refreshing_scroll := false
var _fitting := false
var _layout_retries := 0
var _heading: Label
var _summary: Label
var _count: Label
var _dossier_box: VBoxContainer
var _info: Dictionary = {}
var _closing := false
var _replayer = ReplayScript.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	_replayer.finished.connect(_on_replay_finished)
	PresentationMetrics.bind_layer(self)


func _exit_tree() -> void:
	# 页面被连根拔起（换场 / 退出）时别把分镜播放器留在半空。
	if _replayer != null and _replayer.playing:
		_replayer.abort()


func _build() -> void:
	_shell = Modal.build(self, {
		"title": "回 看 余 烬",
		"size": CARD_SIZE,
		"hint": "↑↓ 选择 · Enter 确认",
		"back": "Esc 返回",
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close())
	var body := _shell["body"] as Control
	# 左侧是菜单列（可滚动），右侧是固定的旅程档案板：两者并排，互不挤压。两列顶上各一行题头。
	_column = VBoxContainer.new()
	_column.name = "BodyColumn"
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.anchor_right = DOSSIER_SPLIT
	_column.offset_top = HEAD_TOP
	_column.add_theme_constant_override("separation", 0)
	body.add_child(_column)
	var entries := GlassKit.kicker("行 程 入 口", HORIZONTAL_ALIGNMENT_LEFT)
	entries.name = "EntriesKicker"
	_column.add_child(entries)
	_build_dossier(body)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = true
	_column.add_child(_scroll)
	_scroll.resized.connect(_on_scroll_resized)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_value)
	# 行高取整后多出来的像素落在这里，不拿半行去填。
	_snap_pad = Control.new()
	_snap_pad.name = "SnapPad"
	_snap_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap_pad.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_snap_pad.custom_minimum_size = Vector2(0.0, 0.0)
	_column.add_child(_snap_pad)
	# 提示是滚动区下面的一行，不盖在章节行上。
	_more = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_more.name = "MoreHint"
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_more.modulate = UiKit.EMBER
	_more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_more.custom_minimum_size = Vector2(0.0, 0.0)
	_more.visible = false
	_column.add_child(_more)


# --- 内容 ---------------------------------------------------------------------

## info:
##   ending     String   存档里的结局 id（give / keep / snuff；没有 = ""）
##   flags      Variant  存档旗标（Array / PackedStringArray，要有 has()）
##   has_save   bool     有存档才给「继续旅程」
##   trial_ready bool    回火试炼是否已解锁（没解锁就置灰）
func open(info: Dictionary) -> void:
	_info = info.duplicate()
	_closing = false
	_rebuild()
	visible = true
	_root.visible = true
	(_shell.get("play_intro") as Callable).call()
	_sync_menu_active()
	Sfx.play(&"ui_select")


func _rebuild() -> void:
	if _content != null:
		_scroll.remove_child(_content)
		_content.queue_free()
		_content = null
	_menu = null
	_pinned = null
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content)

	var ending := String(_info.get("ending", ""))
	var flags: Variant = _info.get("flags", PackedStringArray())
	_fill_dossier(ending, flags)

	_menu = MenuList.new()
	_menu.name = "Menu"
	# 菜单贴左：与上方「行程入口」题头同一条左缘。
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_menu.custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	_menu.add_theme_constant_override("separation", 6)
	# 铁条列：与标题屏的菜单架同一套版式（削角、左缘灯口、余烬光标）。
	_menu.strip_style = true
	_content.add_child(_menu)
	for row in rows_for(_info):
		var item := _menu.add_item(StringName(String(row["id"])), String(row["text"]),
				bool(row.get("disabled", false)), MenuItem.Kind.PRIMARY)
		item.dark_plate = true
	# 「再入某章」分组标题：插在菜单项之间的普通子节点，不参与上下键顺序。
	var chapter_rows := chapter_ids_for(flags)
	if not chapter_rows.is_empty():
		var section := UiKit.label("再 入 某 章 · 从 该 章 入 口 出 发", &"TinyStrongLabel")
		section.name = "ChapterSection"
		section.modulate = UiKit.EMBER
		section.custom_minimum_size = Vector2(0.0, 28.0)
		section.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_menu.add_child(section)
		for id in chapter_rows:
			var chapter_item := _menu.add_item(StringName(ROW_CHAPTER + id), chapter_text(id), false,
					MenuItem.Kind.PRIMARY)
			chapter_item.dark_plate = true
	var tail := Control.new()
	tail.name = "ScrollTail"
	tail.custom_minimum_size = Vector2(0.0, 20.0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(tail)
	_menu.chosen.connect(_on_chosen)
	_menu.focus_changed.connect(_on_focus_changed)
	# 有存档时光标默认停在「继续旅程」，没有就停在第一个可用行（add_item 已经选了）。
	_scroll.scroll_vertical = 0
	_layout_retries = 2
	_layout_scroll_window.call_deferred()


## 右侧的旅程档案板：与标题屏档案卡同一种深色切角卡片，半透明，固定不随菜单滚动。
## 内容每次打开由 _fill_dossier 重排。
func _build_dossier(body: Control) -> void:
	var card := TitleCard.new()
	card.name = "DossierCard"
	# 与外壳同一透明度：TitleCard 的填充自带 FILL.a，倍率除回去，填充正好落在 GlassKit.CARD_ALPHA。
	card.body_alpha = GlassKit.CARD_ALPHA / TitleCard.FILL.a
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.anchor_left = DOSSIER_SPLIT
	card.offset_left = DOSSIER_GAP
	card.offset_right = -6.0
	card.offset_top = 10.0
	card.offset_bottom = -10.0
	body.add_child(card)
	_dossier_box = VBoxContainer.new()
	_dossier_box.name = "DossierBox"
	_dossier_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dossier_box.offset_left = 22.0
	_dossier_box.offset_right = -22.0
	_dossier_box.offset_top = HEAD_TOP - card.offset_top
	_dossier_box.offset_bottom = -22.0
	_dossier_box.add_theme_constant_override("separation", 12)
	card.add_child(_dossier_box)


## 档案板内容（自上而下）：题头「旅程档案」、结局印记、结局标题、前情、章节刻度、已过章数、结局三格。
## 上下各一段弹性空白，把内容压在卡片中部。前情放在这里而不是滚动区里：列表滚动时它不跟着走，
## 章节行也不会被它顶到折叠线以下。
func _fill_dossier(ending: String, flags: Variant) -> void:
	for old in _dossier_box.get_children():
		_dossier_box.remove_child(old)
		old.queue_free()
	_dossier_box.add_child(GlassKit.kicker("旅 程 档 案", HORIZONTAL_ALIGNMENT_CENTER))
	_dossier_box.add_child(GlassKit.spacer())
	var seal := GlassKit.SealMark.new()
	seal.name = "Seal"
	seal.tint = ENDING_COLORS.get(ending, GlassKit.COLD_IRON)
	_dossier_box.add_child(seal)
	_heading = UiKit.label(heading_for(ending), &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_heading.name = "Heading"
	_heading.modulate = UiKit.EMBER if ending != "" else UiKit.ASH
	_dossier_box.add_child(_heading)
	_dossier_box.add_child(GlassKit.rule())
	_summary = UiKit.label(summary_for(ending, flags), &"BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_summary.name = "Summary"
	# 不要 max_lines_visible / clip_text：排版前宽度可能还是 0，省略号会把每一行裁成空串，
	# 标签却占着高度。高度由 _fit_summary 按档案板的内宽量出来。
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.clip_text = false
	_summary.max_lines_visible = -1
	_summary.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_dossier_box.add_child(_summary)
	var rail := GlassKit.ChapterRail.new()
	rail.name = "ChapterRail"
	rail.set_journey(GlassKit.done_from_flags(flags))
	_dossier_box.add_child(rail)
	_count = UiKit.label(count_line(StoryFlow.cleared_count(flags)), &"BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_count.name = "Count"
	_count.modulate = UiKit.EMBER_ASH
	_dossier_box.add_child(_count)
	_dossier_box.add_child(GlassKit.spacer())
	_dossier_box.add_child(_endings_row(seen_endings_for(_info)))


func _endings_row(seen: Array[String]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Endings"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind in ENDING_KINDS:
		var known := seen.has(kind)
		# 没见过的结局只写「？？」：三格的数量是摆在明面上的，名字留到看过再说。
		var text := _spaced(ending_short_name(kind)) if known else "？？"
		var cell := UiKit.label(text, &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
		cell.name = "Ending_" + kind
		cell.modulate = ENDING_COLORS[kind] if known else Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.7)
		row.add_child(cell)
	return row


## 看过（或存档记着）的结局种类：与重温列表同一口径，三格里只有这些亮出名字。
static func seen_endings_for(info: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var listed := replay_ids_for(info)
	for kind in ENDING_KINDS:
		if listed.has(Boards.ending_id(kind)):
			out.append(kind)
	return out


## 页面标题：「结局 · 还火」/「尚无结局」。不认识的结局 id 写「旅程已终」（旧存档兜底）。
static func heading_for(ending: String) -> String:
	if ending == "":
		return NO_ENDING_HEADING
	return "结局 · %s" % ending_short_name(ending)


## 结局短名：取自结局概述冒号前的几个字（还火 / 守炉 / 熄火），不认识的给 UNKNOWN_ENDING_NAME。
static func ending_short_name(kind: String) -> String:
	var summary := ChapterText.ending_summary_of(kind)
	var cut := summary.find("：")
	return summary.substr(0, cut) if cut > 0 else UNKNOWN_ENDING_NAME


## 总结段：有结局 = 结局概述；没有 = 最近一两章的前情（没通关任何一章就是兜底句）。
static func summary_for(ending: String, flags: Variant) -> String:
	if ending != "":
		var summary := ChapterText.ending_summary_of(ending)
		if summary != "":
			return summary
	var cleared: Array = []
	for id in ChapterText.order():
		var flag := StoryFlow.done_flag(id)
		if flag != "" and flags.has(flag):
			cleared.append(id)
	var recent: Array = cleared.slice(maxi(cleared.size() - 2, 0))
	var lines := ChapterText.recap_lines_for(recent)
	return "  ".join(lines) if not lines.is_empty() else StoryFlow.RECAP_FALLBACK


static func count_line(cleared: int) -> String:
	return "已过 %d / %d 章" % [cleared, ChapterText.order().size()]


## 已通关章节 id（战役顺序，口径 = StoryFlow.DONE_FLAGS）。
static func chapter_ids_for(flags: Variant) -> Array[String]:
	var out: Array[String] = []
	for id in ChapterText.order():
		var flag := StoryFlow.done_flag(id)
		if flag != "" and flags.has(flag):
			out.append(id)
	return out


static func chapter_text(id: String) -> String:
	return "再入 %s · %s" % [ChapterText.number_of(id), ChapterText.name_of(id)]


## 行定义（顺序 = 显示顺序），不含「再入某章」那一组。每行 {id, text, disabled?, note?}。
static func rows_for(info: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if bool(info.get("has_save", false)):
		rows.append({"id": ID_CONTINUE, "text": "继 续 旅 程"})
	var replays := replay_ids_for(info)
	for board_id in replays:
		if board_id == Boards.PROLOGUE:
			rows.append({"id": ID_PROLOGUE, "text": "重 温 序 章"})
		elif board_id.begins_with("ending_"):
			var kind := board_id.trim_prefix("ending_")
			rows.append({"id": StringName(ROW_ENDING + kind),
					"text": "重 温 结 局 · %s" % _spaced(Boards.ending_name(kind))})
	rows.append({"id": ID_ARENA, "text": "余 烬 竞 技 场"})
	var trial_ready := bool(info.get("trial_ready", true))
	var trial_text := "回 火 试 炼"
	if not trial_ready:
		trial_text = "回 火 试 炼 · %s后解锁" % ChapterText.number_of("level07")
	rows.append({"id": ID_TRIAL, "disabled": not trial_ready, "text": trial_text})
	rows.append({"id": ID_BACK, "text": "返 回"})
	return rows


## 可回放的分镜：序章与结局（Boards.replay_list 里看过的），外加存档里记着的那个结局——
## 旧存档在分镜系统之前就通关了，没有「看过」旗标，但结局显然已经看过。
static func replay_ids_for(info: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var flags: Variant = info.get("flags", PackedStringArray())
	var listed := Boards.replay_list(flags)
	if listed.has(Boards.PROLOGUE):
		out.append(Boards.PROLOGUE)
	var ending := String(info.get("ending", ""))
	for kind in ENDING_KINDS:
		var id := Boards.ending_id(kind)
		if listed.has(id) or (kind == ending and Boards.has(id)):
			out.append(id)
	return out


static func _spaced(text: String) -> String:
	var parts := PackedStringArray()
	for i in text.length():
		parts.append(text.substr(i, 1))
	return " ".join(parts)


# --- 选择 ---------------------------------------------------------------------

func _on_chosen(id: StringName) -> void:
	choose(id)


## 选一行（点 / 回车 / 测试都走这里）。
func choose(id: StringName) -> void:
	if _replayer.playing or _closing:
		return
	var text := String(id)
	if id == ID_BACK:
		close()
	elif id == ID_CONTINUE:
		continue_requested.emit()
	elif id == ID_ARENA:
		arena_requested.emit()
	elif id == ID_TRIAL:
		if bool(_info.get("trial_ready", true)):
			trial_requested.emit()
		else:
			Sfx.play(&"ui_denied")
	elif id == ID_PROLOGUE:
		play_replay(Boards.PROLOGUE)
	elif text.begins_with(ROW_ENDING):
		play_replay(Boards.ending_id(text.trim_prefix(ROW_ENDING)))
	elif text.begins_with(ROW_CHAPTER):
		chapter_requested.emit(text.trim_prefix(ROW_CHAPTER))


## 回放一段分镜：本页藏起来，播放器接管；成功返回 true。
func play_replay(board_id: String) -> bool:
	if _replayer.playing or not visible or _closing:
		return false
	if not _replayer.start(board_id):
		Sfx.play(&"ui_denied")
		return false
	_root.visible = false
	_sync_menu_active()
	replay_started.emit(board_id)
	return true


func _on_replay_finished(board_id: String, _completed: bool) -> void:
	_root.visible = true
	_sync_menu_active()
	# 光标回到刚才重温的那一行。
	var row := _row_for_board(board_id)
	if _menu != null and row != &"":
		var at := _menu.item_ids().find(row)
		if at >= 0:
			_menu.select(at, false)
	replay_finished.emit(board_id)


static func _row_for_board(board_id: String) -> StringName:
	if board_id == Boards.PROLOGUE:
		return ID_PROLOGUE
	if board_id.begins_with("ending_"):
		return StringName(ROW_ENDING + board_id.trim_prefix("ending_"))
	return &""


func _on_focus_changed(id: StringName) -> void:
	if _menu == null:
		return
	var at := _menu.item_ids().find(id)
	var items := _menu.items()
	if at < 0 or at >= items.size():
		return
	_pinned = items[at] as Control
	_follow_pin = true
	_layout_retries = 2
	_layout_scroll_window.call_deferred()


func _on_scroll_resized() -> void:
	if _fitting:
		return
	_layout_scroll_window()


func _on_scroll_value(_value: float) -> void:
	if _fitting:
		return
	_layout_scroll_window()


## 摘要按档案板的内宽换行，并给足高度。宽度未知时返回 false，调用方再排一次。
func _fit_summary() -> bool:
	if _summary == null or not is_instance_valid(_summary):
		return true
	var width := _summary_width()
	if width < 80.0:
		return false
	var height := _summary_height(width)
	if absf(_summary.custom_minimum_size.y - height) >= 1.0:
		_summary.custom_minimum_size = Vector2(0.0, height)
	return true


func _summary_width() -> float:
	return _dossier_box.size.x if _dossier_box != null else 0.0


func _summary_height(width: float) -> float:
	var font := _summary.get_theme_font(&"font")
	var font_size := _summary.get_theme_font_size(&"font_size")
	if font == null or font_size <= 0:
		return 72.0
	var measured := font.get_multiline_string_size(_summary.text, HORIZONTAL_ALIGNMENT_CENTER,
			width, font_size, TextServer.JUSTIFICATION_NONE,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var line_h := float(font.get_height(font_size))
	var spacing := float(_summary.get_theme_constant(&"line_spacing"))
	var lines := 1
	if line_h > 1.0:
		lines = maxi(int(ceil(measured.y / line_h)), 1)
	var raw := maxf(measured.y + spacing * float(maxi(lines - 1, 0)) + 4.0, line_h + 4.0)
	# 前情最多两三行；量宽失败时别让这一段把整列菜单顶出卡片。
	return minf(raw, line_h * 4.0 + spacing * 3.0 + 8.0)


## 视口底边落在某一行的边界上：半截行藏到视口外，滚动偏移也停在行边界。
func _layout_scroll_window() -> void:
	if _fitting or _scroll == null or _column == null:
		return
	_fitting = true
	_resort(_column)
	_resort(_scroll)
	_resort(_content)
	_resort(_menu)
	var ready := _fit_summary()
	_resort(_content)
	_resort(_menu)
	_resort(_scroll)
	_refresh_scroll_chrome()
	_resort(_column)
	_apply_row_snap()
	_fitting = false
	if not ready and _layout_retries < 6:
		_layout_retries += 1
		_layout_scroll_window.call_deferred()
	elif _layout_retries > 0:
		_layout_retries -= 1
		_layout_scroll_window.call_deferred()


func _resort(node: Node) -> void:
	if node is Container:
		(node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)


## 用行和滚动区的全局矩形对齐（跟测试同一把尺子）。半截在底下的行整行藏掉，
## 半截在顶上的行把滚动停到它的边界。最多走四步，避免顶边和底边来回抢。
func _apply_row_snap() -> void:
	if _snap_pad == null or _scroll == null or _scroll.size.y < 32.0:
		return
	var follow := _follow_pin
	_follow_pin = false
	for _step in 6:
		if not _snap_pass(follow):
			return
		_resort(_column)
		_resort(_scroll)


func _snap_rows() -> Array[Control]:
	var rows: Array[Control] = []
	if _menu == null:
		return rows
	for sub in _menu.get_children():
		if sub is Control and (sub as Control).size.y >= 1.0:
			rows.append(sub as Control)
	return rows


func _has_pin() -> bool:
	return _pinned != null and is_instance_valid(_pinned) and _pinned.size.y >= 1.0


func _snap_pass(_follow: bool) -> bool:
	var view := _scroll.get_global_rect()
	if view.size.y < 32.0:
		return false
	# 当前行一旦被点中，后面的对齐也不能再把它藏到视口外。
	if _has_pin():
		var pin := _pinned.get_global_rect()
		if pin.position.y < view.position.y - 1.0:
			_scroll.scroll_vertical = maxi(_scroll.scroll_vertical - int(ceil(view.position.y - pin.position.y)), 0)
			return true
		if pin.end.y > view.end.y + 1.0:
			_scroll.scroll_vertical += int(ceil(pin.end.y - view.end.y))
			return true
	for row in _snap_rows():
		if _has_pin() and row == _pinned:
			continue
		var box := row.get_global_rect()
		if box.position.y < view.position.y - 1.0 and box.end.y > view.position.y + 1.0:
			# 只把半截行推出顶边。往回拉会把已经贴底的当前行再顶出视口，两边来回抢。
			var before := _scroll.scroll_vertical
			_scroll.scroll_vertical = before + int(ceil(box.end.y - view.position.y))
			if _scroll.scroll_vertical != before:
				return true
			# 已经到底，滚不动：缩短视口，腾出滚动余量，下一轮再把这行推出顶边。
			var stub := box.end.y - view.position.y
			if stub >= 1.0 and _scroll.size.y - stub >= 120.0:
				_snap_pad.custom_minimum_size = Vector2(0.0, _snap_pad.custom_minimum_size.y + stub)
				return true
	var shrink := 0.0
	for row in _snap_rows():
		if _has_pin() and row == _pinned:
			continue
		var box := row.get_global_rect()
		if box.position.y < view.end.y - 1.0 and box.end.y > view.end.y + 1.0:
			shrink = maxf(shrink, view.end.y - box.position.y)
	if shrink < 1.0 or _scroll.size.y - shrink < 120.0:
		return false
	_snap_pad.custom_minimum_size = Vector2(0.0, _snap_pad.custom_minimum_size.y + shrink)
	return true


func _refresh_scroll_chrome() -> void:
	if _refreshing_scroll or _scroll == null or _more == null:
		return
	_refreshing_scroll = true
	var bar := _scroll.get_v_scroll_bar()
	var max_scroll := maxf(bar.max_value - bar.page, 0.0)
	var overflow := max_scroll > 8.0
	var show_bar := ScrollContainer.SCROLL_MODE_SHOW_ALWAYS if overflow else ScrollContainer.SCROLL_MODE_AUTO
	if _scroll.vertical_scroll_mode != show_bar:
		_scroll.vertical_scroll_mode = show_bar
	var more := overflow and float(_scroll.scroll_vertical) < max_scroll - 6.0
	_more.visible = more
	var want_h := 26.0 if more else 0.0
	if not is_equal_approx(_more.custom_minimum_size.y, want_h):
		_more.custom_minimum_size.y = want_h
	if more:
		var flags: Variant = _info.get("flags", PackedStringArray())
		var n := chapter_ids_for(flags).size()
		_more.text = "↓ 还有 %d 章 · 上下键滚动" % n if n > 0 else "↓ 还有内容 · 上下键滚动"
	_refreshing_scroll = false


# --- 开合 / 输入 --------------------------------------------------------------

func close() -> void:
	if not visible or _closing:
		return
	if _replayer.playing:
		_replayer.abort()
	_closing = true
	_sync_menu_active()
	Sfx.play(&"ui_back")
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		closed.emit())


## 不走退场动画、不发 closed（改发 dismissed）：标题要接着做别的事（读档、换场）时用。
func dismiss() -> void:
	if _replayer.playing:
		_replayer.abort()
	_closing = false
	visible = false
	if _root != null:
		_root.visible = true
	_sync_menu_active()
	dismissed.emit()


func is_open() -> bool:
	return visible


func replaying() -> bool:
	return _replayer.playing


func _sync_menu_active() -> void:
	if _menu != null:
		_menu.active = visible and not _closing and not _replayer.playing


func _unhandled_input(event: InputEvent) -> void:
	# 回放中本页是藏起来的：Enter / Esc 归播放器。
	if not visible or _replayer.playing:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- 测试 / 工具用 ------------------------------------------------------------

func menu() -> MenuList:
	return _menu


func row_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if _menu != null:
		out.assign(_menu.item_ids())
	return out


func heading_text() -> String:
	return _heading.text if _heading != null else ""


func summary_text() -> String:
	return _summary.text if _summary != null else ""


func count_text() -> String:
	return _count.text if _count != null else ""


func root_control() -> Control:
	return _root
