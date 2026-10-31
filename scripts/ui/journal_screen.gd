extends CanvasLayer
## 故事页：暂停菜单「故 事」打开的覆盖层。玩家随时能回答四个问题——
##   现在要做什么 / 前情是什么 / 这些人是谁 / 这些词什么意思，
## 再加一个入口：把看过的分镜（序章、章间、结局、滚动字幕）重看一遍。
##
## 四页（←→ 或手柄肩键切页，↑↓ 滚动 / 选择，Esc 返回上一层）：
##   现 在  所在章节 + 章节刻度 + 「现在要做什么」（ChapterText.objective_of）+「前情」（StoryFlow.recap_text）
##   人 物  已出场的人物（ChapterText.revealed_cast），一人一张玻璃卡；初见菱形按所在章节是否通关点燃
##   名 词  已出场的名词（ChapterText.revealed_terms），两栏，行间是锈色发丝线
##   重 看  Boards.replay_list(存档旗标)：只列看过的；选一项就回放
##
## 版式：顶上一排标签（当前页压一根余烬短棒），右端是「01 / 04」；每页一行小字题头。
##
## 回放走 board_replay.gd（Director.board().play_board(id, {"replay": true})）。回放时本页先藏起来
## （并发 replay_started，让暂停菜单把自己的卡片也藏起来），播完 / 被跳过后恢复到「重 看」页、
## 光标还停在刚才那一项（replay_finished）。
##
## 外壳与教程回看 / 地图是同一套（ui_modal.gd），整棵子树 PROCESS_MODE_ALWAYS，暂停中照常工作。
## 本文件不写 class_name：暂停菜单按 preload 取用（避开 .godot 类缓存）。

signal closed
signal replay_started(id: String)
signal replay_finished(id: String)

const Modal := preload("res://scripts/ui/ui_modal.gd")
const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Boards := preload("res://scripts/data/storyboards.gd")
const ReplayScript := preload("res://scripts/ui/board_replay.gd")

const TAB_NOW := 0
const TAB_CAST := 1
const TAB_TERMS := 2
const TAB_REPLAY := 3
const TAB_TITLES: Array[String] = ["现 在", "人 物", "名 词", "重 看"]
const TAB_HINTS: Array[String] = [
	"←→ 切页 · ↑↓ 滚动",
	"←→ 切页 · ↑↓ 滚动",
	"←→ 切页 · ↑↓ 滚动",
	"←→ 切页 · ↑↓ 选择 · Enter 重看",
]
## 每页顶上那行小字题头（与 TAB_TITLES 同序）。
const PAGE_KICKERS: Array[String] = ["所 在 · 此 刻", "初 见 · 人 物", "白 话 · 名 词", "分 镜 · 回 放"]
const CARD_SIZE := Vector2(940.0, 620.0)
## 压暗到能看出底下的暂停卡片是一层，但不至于铺黑；比默认 0.55 深，玻璃卡不会透出暂停菜单的字。
const VEIL := 0.76
const TAB_WIDTH := 144.0
const SCROLL_STEP := 64.0
const GRID_H_SEP := 28
const GRID_V_SEP := 12
const RAIL_WIDTH := 276.0
const PAGE_INDEX_WIDTH := 96.0
## 取不到本章目标时的兜底（章节表里 14 章都有目标，这只是防御）。
const GOAL_FALLBACK := "把火种带去炉心。"
const REPLAY_EMPTY_HEAD := "还没有可重看的分镜"
const REPLAY_EMPTY_NOTE := "看过的序章、章间和结局，会留在这里。"

var _root: Control
var _shell: Dictionary = {}
var _hint: Label
var _tab_buttons: Array[Button] = []
var _tab_bars: Array[ColorRect] = []
var _index_label: Label
var _pages: Array[Control] = []
var _scrollers: Array[ScrollContainer] = []
var _tab := TAB_NOW
var _closing := false
var _section_count := 0

var _chapter_override := ""
var _chapter_id := ""
var _chapter_label: Label
var _chapter_rail: GlassKit.ChapterRail
var _objective_label: Label
var _recap_label: Label
var _truth_label: Label
var _cast_rows: Array[Control] = []
var _term_rows: Array[Control] = []
var _replay_scroll: ScrollContainer
var _replay_holder: VBoxContainer
var _replay_menu: MenuList
var _replay_empty: Control
var _replay_ids: Array[String] = []
var _replayer = ReplayScript.new()


## 人物卡：一人一张玻璃卡。左侧一粒「初见」菱形：所在章节已通关 = 余烬点亮，还没通关 = 冷铁。
## 名字在上（Name），一句话在下（Text），右上角写初见的章节（Met）。
class CastCard extends Control:
	const HEIGHT := 128.0
	var _plate: StyleBox
	var _lit := false
	var _name_label: Label
	var _text_label: Label
	var _met_label: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, HEIGHT)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var base := UiKit.extras_theme().get_stylebox(&"panel", &"HintPanel") as StyleBoxTexture
		if base != null:
			var glass := base.duplicate() as StyleBoxTexture
			glass.modulate_color = Color(1.0, 1.0, 1.0, GlassKit.CARD_ALPHA)
			_plate = glass

	func setup(who: String, text: String, first_chapter: String, lit: bool) -> void:
		_lit = lit
		_name_label = UiKit.label(who, &"KeyCapLabel")
		_name_label.name = "Name"
		add_child(_name_label)
		_text_label = UiKit.label(text, &"BodyLabel")
		_text_label.name = "Text"
		_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_text_label)
		var met := "初 见 · 序 章" if first_chapter == "" \
				else "初 见 · %s" % ChapterText.subtitle_of(first_chapter)
		_met_label = UiKit.label(met, &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		_met_label.name = "Met"
		_met_label.modulate = UiKit.EMBER if _lit else UiKit.ASH
		add_child(_met_label)
		_layout()

	func set_text(text: String) -> void:
		if _text_label != null:
			_text_label.text = text
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_layout()

	func _layout() -> void:
		if _name_label == null:
			return
		_name_label.position = Vector2(40.0, 14.0)
		_name_label.size = Vector2(maxf(size.x - 200.0, 40.0), 30.0)
		_met_label.position = Vector2(size.x - 160.0, 16.0)
		_met_label.size = Vector2(144.0, 24.0)
		_text_label.position = Vector2(40.0, 50.0)
		_text_label.size = Vector2(maxf(size.x - 62.0, 40.0), maxf(size.y - 58.0, 20.0))
		queue_redraw()

	func _draw() -> void:
		if _plate != null:
			draw_style_box(_plate, Rect2(Vector2.ZERO, size))
		var c := Vector2(20.0, 28.0)
		if _lit:
			GlassKit.diamond(self, c, 9.0, Color(GlassKit.EMBER.r, GlassKit.EMBER.g, GlassKit.EMBER.b, 0.25))
			GlassKit.diamond(self, c, 6.0, GlassKit.EMBER)
			GlassKit.diamond(self, c, 2.0, GlassKit.EMBER_HOT)
		else:
			GlassKit.diamond(self, c, 5.0, GlassKit.COLD_EDGE)
			GlassKit.diamond(self, c, 2.0, GlassKit.COLD)


## 名词行：左列名字（琥珀），右列白话；行底一根锈色发丝线，两栏之间一根竖线（left_column 的那一栏右缘）。
class TermEntry extends HBoxContainer:
	## 与网格的 h_separation / v_separation 保持一致（内部类不读外层常量）。
	const GAP_H := 28.0
	const GAP_V := 12.0
	const NAME_WIDTH := 96.0
	var left_column := false:
		set(value):
			left_column = value
			queue_redraw()

	func _init() -> void:
		add_theme_constant_override("separation", 16)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(term: String, text: String) -> void:
		var name_label := UiKit.label(term, &"KeyCapLabel")
		name_label.name = "Name"
		name_label.custom_minimum_size = Vector2(NAME_WIDTH, 0.0)
		name_label.size_flags_vertical = Control.SIZE_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		add_child(name_label)
		var body := UiKit.label(text, &"BodyLabel")
		body.name = "Text"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.size_flags_vertical = Control.SIZE_FILL
		# 名与白话都从这一行的顶边起排：同一行里两栏的字高要对齐，不能一栏居中一栏贴顶。
		body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		add_child(body)

	func _draw() -> void:
		# 发丝线画在格子之间的缝里（网格的 v_separation 的一半处），两栏之间的竖线同理。
		var rust := Color(UiKit.RUST_MID.r, UiKit.RUST_MID.g, UiKit.RUST_MID.b, 0.55)
		draw_rect(Rect2(0.0, size.y + GAP_V * 0.5, size.x, 1.0), rust)
		if left_column:
			draw_rect(Rect2(size.x + GAP_H * 0.5, 0.0, 1.0, size.y + GAP_V * 0.5), rust)


# --- 构建 ---------------------------------------------------------------------

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
		"title": "故 事",
		"size": CARD_SIZE,
		"hint": TAB_HINTS[TAB_NOW],
		"back": "Esc 返回",
		"veil": VEIL,
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	_hint = _shell["hint"] as Label
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close())

	var body := _shell["body"] as Control
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)

	column.add_child(_tab_strip())
	var host := Control.new()
	host.name = "Pages"
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(host)
	_build_now_page(host)
	_build_cast_page(host)
	_build_terms_page(host)
	_build_replay_page(host)
	_chapter_id = current_chapter_id()
	_apply_reveals()
	_show_page(TAB_NOW)


## 顶上的标签行：四个页名（TabButton 同一套标签板），当前页底下一根余烬短棒，
## 右端是页码；行底一根锈色发丝线把标签和页面分开。
func _tab_strip() -> Control:
	var wrap := VBoxContainer.new()
	wrap.name = "TabStrip"
	wrap.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.name = "Tabs"
	row.add_theme_constant_override("separation", 12)
	wrap.add_child(row)
	var group := ButtonGroup.new()
	for i in TAB_TITLES.size():
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = TAB_TITLES[i]
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.button_group = group
		# 键盘 / 手柄走 ←→（见 _unhandled_input），不让标签行抢走回车。
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(TAB_WIDTH, UiKit.TOUCH_MIN)
		tab.pressed.connect(show_tab.bind(i))
		var bar := ColorRect.new()
		bar.name = "EmberBar"
		bar.color = UiKit.EMBER
		bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_left = 18.0
		bar.offset_right = -18.0
		bar.offset_top = -4.0
		bar.offset_bottom = -1.0
		bar.visible = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_child(bar)
		row.add_child(tab)
		_tab_buttons.append(tab)
		_tab_bars.append(bar)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	_index_label = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_index_label.name = "PageIndex"
	_index_label.modulate = UiKit.EMBER_ASH
	_index_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_index_label.custom_minimum_size = Vector2(PAGE_INDEX_WIDTH, UiKit.TOUCH_MIN)
	row.add_child(_index_label)
	wrap.add_child(_hairline())
	return wrap


## 新建一页：页根（可见性由 _show_page 切换）+ 页首题头；返回页内可滚动的列表。
func _add_page(host: Control, page_name: String, kicker_index: int) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = page_name
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	host.add_child(page)
	page.add_child(_page_head(PAGE_KICKERS[kicker_index]))
	_pages.append(page)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_scrollers.append(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	return list


## 页首题头：12px 余烬小字 + 一根发丝线，每页一行，告诉玩家这一页是什么。
func _page_head(text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "PageHead"
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := GlassKit.kicker(text)
	tag.name = "Kicker"
	row.add_child(tag)
	var stub := Ornaments.stub_rule(false)
	stub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stub)
	return row


func _build_now_page(host: Control) -> void:
	var list := _add_page(host, "NowPage", 0)
	_chapter_label = UiKit.label("", &"HeadLabel")
	_chapter_label.name = "Chapter"
	list.add_child(_chapter_label)
	_chapter_rail = GlassKit.ChapterRail.new()
	_chapter_rail.name = "ChapterRail"
	# 刻度条按自己的宽度居中画；标题是左对齐的，所以刻度条也贴左：宽 276 = 13 格 × 20 + 两端各 8，
	# 第一粒的光晕正好落在文字列的左缘上。
	_chapter_rail.custom_minimum_size = Vector2(RAIL_WIDTH, 14.0)
	_chapter_rail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	list.add_child(_chapter_rail)
	list.add_child(_section("现在要做什么"))
	_objective_label = _body_label("Objective")
	list.add_child(_objective_label)
	list.add_child(_section("前情"))
	_recap_label = _body_label("Recap")
	list.add_child(_recap_label)
	list.add_child(_section("真名残片"))
	_truth_label = _body_label("TruthFragments")
	list.add_child(_truth_label)


## 人物页：两列玻璃卡，行优先排（已出场的才显示，见 _reveal_rows）。
func _build_cast_page(host: Control) -> void:
	var list := _add_page(host, "CastPage", 1)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", GRID_H_SEP)
	grid.add_theme_constant_override("v_separation", 12)
	list.add_child(grid)
	for key in ChapterText.CAST:
		var first := ChapterText.cast_first_chapter(String(key))
		var card := CastCard.new()
		card.name = "Entry_" + String(key)
		# 序章 / 开场就在的人物算作「已点亮」；其余看初见那一章是否通关。
		card.setup(String(key), String(ChapterText.CAST[key]), first,
				first == "" or chapter_cleared(first))
		grid.add_child(card)
		_cast_rows.append(card)


## 名词页：两栏，行间发丝线；左栏每行右缘一根竖线（_place_term_columns 分配）。
func _build_terms_page(host: Control) -> void:
	var list := _add_page(host, "TermsPage", 2)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", GRID_H_SEP)
	grid.add_theme_constant_override("v_separation", GRID_V_SEP)
	list.add_child(grid)
	for key in ChapterText.TERMS:
		var row := TermEntry.new()
		row.name = "Entry_" + String(key)
		row.setup(String(key), String(ChapterText.TERMS[key]))
		grid.add_child(row)
		_term_rows.append(row)


func _build_replay_page(host: Control) -> void:
	var page := VBoxContainer.new()
	page.name = "ReplayPage"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	host.add_child(page)
	page.add_child(_page_head(PAGE_KICKERS[3]))
	_pages.append(page)

	var stack := Control.new()
	stack.name = "Stack"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(stack)

	_replay_scroll = ScrollContainer.new()
	_replay_scroll.name = "Scroll"
	_replay_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_replay_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(_replay_scroll)
	_replay_holder = VBoxContainer.new()
	_replay_holder.name = "Holder"
	_replay_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_scroll.add_child(_replay_holder)
	_scrollers.append(_replay_scroll)

	# 空态：一句暖白的主答案 + 一行暗脚注（和教程回看同一种写法）。
	var empty := VBoxContainer.new()
	empty.name = "EmptyBox"
	empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	empty.alignment = BoxContainer.ALIGNMENT_CENTER
	empty.add_theme_constant_override("separation", 6)
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty.visible = false
	stack.add_child(empty)
	var head := UiKit.label(REPLAY_EMPTY_HEAD, &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	head.name = "EmptyHead"
	head.modulate = Color("#E4DCCC")
	empty.add_child(head)
	var note := UiKit.label(REPLAY_EMPTY_NOTE, &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	note.name = "EmptyNote"
	empty.add_child(note)
	_replay_empty = empty


func _section(text: String) -> Control:
	_section_count += 1
	var row := HBoxContainer.new()
	row.name = "Section%d" % _section_count
	row.add_theme_constant_override("separation", 10)
	var tag := UiKit.label(text, &"TinyStrongLabel")
	tag.name = "Tag"
	tag.modulate = UiKit.EMBER_ASH
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tag)
	var stub := Ornaments.stub_rule(false)
	stub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stub)
	return row


func _hairline() -> Control:
	var line := ColorRect.new()
	line.name = "Hairline"
	line.color = Color(UiKit.RUST_MID.r, UiKit.RUST_MID.g, UiKit.RUST_MID.b, 0.45)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _body_label(label_name: String) -> Label:
	var label := UiKit.label("", &"BodyLabel")
	label.name = label_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


# --- 内容 ---------------------------------------------------------------------

## 当前章节 id：先看世界场景属于哪一章；认不出来（单元测试宿主 / 竞技场）就按存档进度
## 推：第一个还没通关的章节，全通关了就是终章。
func current_chapter_id() -> String:
	if _chapter_override != "":
		return _chapter_override
	var world := GameContext.world_root(self)
	if world is StageLevel and (world as StageLevel).stage_id != "":
		return (world as StageLevel).stage_id
	var path := ""
	if world != null:
		path = String(world.scene_file_path)
	for id in GameContext.LEVEL_ORDER:
		if path != "" and String(GameContext.LEVELS.get(id, "")) == path:
			return id
	return progress_chapter_id()


## 按存档旗标推的「下一章」：第一个没通关的章节；全通关 = 终章。
static func progress_chapter_id() -> String:
	var order := ChapterText.order()
	for id in order:
		var flag := StoryFlow.done_flag(id)
		if flag == "" or not SaveData.has_flag(flag):
			return id
	return order[order.size() - 1] if not order.is_empty() else ""


## 某一章是否已通关（存档旗标）：人物卡的「初见」菱形用它点亮。
static func chapter_cleared(id: String) -> bool:
	var flag := StoryFlow.done_flag(id)
	return flag != "" and SaveData.has_flag(flag)


## 测试 / 工具：固定「当前章节」（空串 = 恢复自动判断）。
func set_chapter(id: String) -> void:
	_chapter_override = id
	if visible:
		refresh()


## 把四页的内容按当前存档重读一遍（每次打开都会调）。
func refresh() -> void:
	_chapter_id = current_chapter_id()
	var title := ChapterText.title_of(_chapter_id)
	_chapter_label.text = title if title != "" else "锈 墓"
	_chapter_rail.set_journey(GlassKit.done_from_flags(SaveData.flags),
			ChapterText.index_of(_chapter_id))
	var goal := ChapterText.objective_of(_chapter_id)
	_objective_label.text = goal if goal != "" else GOAL_FALLBACK
	_recap_label.text = StoryFlow.recap_text()
	if _truth_label != null:
		var fcnt := NarrativeCatalog.fragment_count(SaveData.flags)
		if fcnt <= 0:
			_truth_label.text = "已拾得 0 / 5 枚。顺从路标只会重蹈柴薪覆辙；试着违抗指引探查裂隙。"
		else:
			var lines := PackedStringArray(["已拾得 %d / 5 枚：" % fcnt])
			for fid in NarrativeCatalog.FRAGMENT_IDS:
				if SaveData.flags.has(fid):
					var fspec := NarrativeCatalog.fragment_spec(fid)
					lines.append("· %s — %s" % [String(fspec.get("title", fid)), String(fspec.get("summary", ""))])
			_truth_label.text = "\n".join(lines)
	_apply_reveals()
	_refresh_replay()
	for scroller in _scrollers:
		scroller.scroll_vertical = 0


## 人物 / 名词只显示「当前章节或已通关进度」已经走到的条目，避免暂停菜单剧透。
func _apply_reveals() -> void:
	var progress := ChapterText.progress_index(_chapter_id, SaveData.flags)
	_reveal_rows(_cast_rows, true, progress)
	_reveal_rows(_term_rows, false, progress)
	_place_term_columns()


func _reveal_rows(rows: Array[Control], is_cast: bool, progress: int) -> void:
	for row in rows:
		var name_label := row.get_node_or_null("Name") as Label
		var who := ""
		if name_label != null:
			who = name_label.text
		var first := ChapterText.term_first_chapter(who)
		if is_cast:
			first = ChapterText.cast_first_chapter(who)
			if row is CastCard:
				(row as CastCard).set_text(ChapterText.cast_of_with_flags(who, SaveData.flags))
		row.visible = ChapterText.is_revealed(first, progress)


## 名词两栏：可见的第偶数条在左栏（行优先排，左栏每行右缘画竖线）。
func _place_term_columns() -> void:
	var shown := 0
	for row in _term_rows:
		if not row.visible:
			continue
		var entry := row as TermEntry
		entry.left_column = shown % 2 == 0
		shown += 1


func _refresh_replay() -> void:
	_replay_ids = Boards.replay_list(SaveData.flags)
	if _replay_menu != null:
		_replay_holder.remove_child(_replay_menu)
		_replay_menu.queue_free()
		_replay_menu = null
	_replay_menu = MenuList.new()
	_replay_menu.name = "ReplayMenu"
	_replay_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_replay_menu.add_theme_constant_override("separation", 8)
	# 重看列表用铁条版式（与总结页同一套），压在半透明卡上靠深色板保证可读。
	_replay_menu.strip_style = true
	for id in _replay_ids:
		var item := _replay_menu.add_item(StringName(id), Boards.title_of(id), false,
				MenuItem.Kind.PRIMARY)
		item.dark_plate = true
	_replay_menu.chosen.connect(_on_replay_chosen)
	_replay_menu.focus_changed.connect(_on_replay_focus)
	_replay_holder.add_child(_replay_menu)
	_replay_empty.visible = _replay_ids.is_empty()
	_replay_scroll.visible = not _replay_ids.is_empty()
	_sync_menu_active()


# --- 开合 / 切页 --------------------------------------------------------------

func open(chapter_id: String = "") -> void:
	if chapter_id != "":
		_chapter_override = chapter_id
	_closing = false
	refresh()
	_show_page(TAB_NOW)
	visible = true
	_root.visible = true
	(_shell.get("play_intro") as Callable).call()
	_sync_menu_active()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


func close() -> void:
	if not visible or _closing:
		return
	# 回放中被关（Esc 之外的路径）：先把播放器收掉，暂停菜单的卡片才会回来。
	if _replayer.playing:
		_replayer.abort()
	_closing = true
	_sync_menu_active()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	# 退场动画播完才隐藏：卡片沉回去、纱幕收掉，然后才 emit closed。
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		_sync_menu_active()
		closed.emit())


## 不走退场动画、不发 closed：暂停菜单整层收起时用。
func dismiss() -> void:
	if _replayer.playing:
		_replayer.abort()
	_closing = false
	visible = false
	if _root != null:
		_root.visible = true
	_sync_menu_active()


func is_open() -> bool:
	return visible


func replaying() -> bool:
	return _replayer.playing


func current_tab() -> int:
	return _tab


func tab_count() -> int:
	return _pages.size()


func show_tab(index: int) -> void:
	var target := clampi(index, 0, _pages.size() - 1)
	if target == _tab and _pages[target].visible:
		return
	_show_page(target)
	UiKit.sfx(&"ui_tick", &"ui_move")


func step_tab(step: int) -> void:
	show_tab(posmod(_tab + step, _pages.size()))


## 换页：页面显隐、标签按下态、当前页的余烬短棒、页码「02 / 04」与提示带一起切。
func _show_page(index: int) -> void:
	_tab = clampi(index, 0, _pages.size() - 1)
	for i in _pages.size():
		_pages[i].visible = i == _tab
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
		_tab_bars[i].visible = i == _tab
	if _hint != null:
		_hint.text = TAB_HINTS[_tab]
	if _index_label != null:
		_index_label.text = "%02d / %02d" % [_tab + 1, _pages.size()]
	_sync_menu_active()


## 「重 看」那列只在它自己的页上、本页开着、没在退场也没在回放时吃输入。
func _sync_menu_active() -> void:
	if _replay_menu == null:
		return
	_replay_menu.active = visible and _tab == TAB_REPLAY and not _closing \
			and not _replayer.playing


func scroll_by(pixels: float) -> void:
	if _tab >= _scrollers.size():
		return
	var scroller := _scrollers[_tab]
	scroller.scroll_vertical = maxi(0, scroller.scroll_vertical + int(pixels))


# --- 回放 ---------------------------------------------------------------------

func _on_replay_chosen(id: StringName) -> void:
	play_replay(String(id))


## 回放一段分镜：本页藏起来，播放器接管；成功返回 true。
func play_replay(id: String) -> bool:
	if _replayer.playing or not visible or _closing:
		return false
	if not _replayer.start(id):
		Sfx.play(&"ui_denied")
		return false
	_root.visible = false
	_sync_menu_active()
	replay_started.emit(id)
	return true


func _on_replay_finished(id: String, _completed: bool) -> void:
	_root.visible = true
	_sync_menu_active()
	if _replay_menu != null:
		var at := _replay_ids.find(id)
		if at >= 0:
			_replay_menu.select(at, false)
	replay_finished.emit(id)


func _on_replay_focus(id: StringName) -> void:
	if _replay_menu == null:
		return
	var at := _replay_menu.item_ids().find(id)
	var items := _replay_menu.items()
	if at < 0 or at >= items.size():
		return
	if at == 0:
		_replay_scroll.scroll_vertical = 0
	else:
		_replay_scroll.ensure_control_visible.call_deferred(items[at] as Control)


# --- 输入 ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# 回放中本页是藏起来的：Enter / Esc 归播放器，不要在这里吃掉。
	if not visible or _replayer.playing:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_page_up") \
			or _is_shoulder(event, JOY_BUTTON_LEFT_SHOULDER):
		step_tab(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_page_down") \
			or _is_shoulder(event, JOY_BUTTON_RIGHT_SHOULDER):
		step_tab(1)
		get_viewport().set_input_as_handled()
	elif _tab != TAB_REPLAY and event.is_action_pressed(&"ui_down", true):
		scroll_by(SCROLL_STEP)
		get_viewport().set_input_as_handled()
	elif _tab != TAB_REPLAY and event.is_action_pressed(&"ui_up", true):
		scroll_by(-SCROLL_STEP)
		get_viewport().set_input_as_handled()


func _is_shoulder(event: InputEvent, button: JoyButton) -> bool:
	return event is InputEventJoypadButton and event.pressed \
			and (event as InputEventJoypadButton).button_index == button


# --- 测试 / 工具用 ------------------------------------------------------------

func chapter_label() -> Label:
	return _chapter_label


func objective_label() -> Label:
	return _objective_label


func recap_label() -> Label:
	return _recap_label


func truth_label() -> Label:
	return _truth_label


## 人物页每一行的名字（按显示顺序）。
func cast_names_shown() -> Array[String]:
	return _entry_names(_cast_rows)


func term_names_shown() -> Array[String]:
	return _entry_names(_term_rows)


func entry_text(rows_kind: int, title: String) -> String:
	var rows := _cast_rows if rows_kind == TAB_CAST else _term_rows
	for row in rows:
		if not row.visible:
			continue
		if (row.get_node("Name") as Label).text == title:
			return (row.get_node("Text") as Label).text
	return ""


func _entry_names(rows: Array[Control]) -> Array[String]:
	var out: Array[String] = []
	for row in rows:
		if row.visible:
			out.append((row.get_node("Name") as Label).text)
	return out


## 「重 看」页能回放的分镜 id（顺序 = 列表顺序）。
func replay_ids() -> Array[String]:
	return _replay_ids.duplicate()


func replay_menu() -> MenuList:
	return _replay_menu


func replay_empty_visible() -> bool:
	return _replay_empty.visible


func page(index: int) -> Control:
	return _pages[index]


func tab_button(index: int) -> Button:
	return _tab_buttons[index]


func root_control() -> Control:
	return _root


func hint_text() -> String:
	return _hint.text if _hint != null else ""
