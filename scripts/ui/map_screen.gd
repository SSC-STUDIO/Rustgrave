class_name MapScreen
extends CanvasLayer
## 暂停菜单里的"地图"，四块内容：
##   · 行程横带（上）：14 章按 醒 / 账 / 铸 / 炉 四幕刻成一排冲孔，已通关的孔烧亮，
##     此刻所在 = 外圈光晕，未抵达 = 冷铁。←→ 或点击切换选中的章节。
##   · 本关剖面（左中）：所有 SolidPlatform 的矩形，整幅关卡等比压进视口；余烬巢 / 出口 /
##     骑士（脉动的白色箭头）从正在运行的场景直接画出来，不依赖任何关卡数据文件。
##   · 章节卷宗（右下）：选中章节的序号、名字、状态与一句话（取自 ChapterText）。
##   · 图例（最底下一条）：行程的三种状态与本关的符号。
## 找不到任何平台（测试夹具、标题屏）时本关剖面显示"地图暂不可用"，行程照常显示。
## 地图只在打开时取一次快照（暂停时世界不动），所以不会逐帧遍历场景。

signal closed

const Modal := preload("res://scripts/ui/ui_modal.gd")
const ObjectKit := preload("res://scripts/ui/ui_object.gd")
const PAPER_INK := Color("#35291F")
const PAPER_FAINT := Color("#70604B")
const PAPER_RUST := Color("#874626")

## 剖面四周的留白；视口尺寸跟着卡片布局走（MapView 自己在 resized 时重算比例）。
const PAD := 36.0
const MIN_SCALE := 0.02
const VIEW_MIN := Vector2(360.0, 176.0)
## 右下卷宗卡的宽度，剖面占剩下的左侧。
const DOSSIER_W := 424.0
## The chapter selector is the punched top edge of the plate itself. Numbers
## and act engravings sit below the holes rather than adding a second selector.
const RAIL_H := 100.0
## 节点离两端的留白：与幕名的左缘（节点再左 24px）正好贴齐卡片的左右内缘。
const RAIL_EDGE := 24.0
const RAIL_NODE_Y := 22.0
const RAIL_RULE_Y := 22.0
const RAIL_NUM_Y := 42.0
const RAIL_CURSOR_Y := 62.0
## 路线节点的三种状态：行程横带、卷宗角标、图例共用同一套绘制。
const ROUTE_DONE := 10
const ROUTE_HERE := 11
const ROUTE_LOCKED := 12

const COL_BACK := Color("#17191D")
const COL_FRAME := Color("#736355")
const COL_PLATFORM := Color("#88796A")
const COL_PLATFORM_TOP := Color("#B8AC8F")
const COL_NEST_LIT := Color("#FFC14A")
const COL_NEST_DIM := Color("#8A8680")
const COL_EXIT := Color("#E4DCCC")
const COL_EXIT_LOCKED := Color("#6E5A50")
const COL_PLAYER := Color("#FFFFFF")
const COL_ROD := Color("#564B42")
const COL_EDGE := Color("#93744F")

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _view: MapView
var _title: Label
var _empty: Label
var _facts: Label
var _count: Label
var _rail: RouteRail
var _dossier: PanelContainer
var _dk: Label
var _dn: Label
var _ds: Label
var _dl: Label
var _do: Label
var _dglyph: MapView.Glyph
var _snapshot: Dictionary = {}
## 章节名淡入补间（换关重开地图时先掐掉上一段）。
var _title_tween: Tween
## 战役顺序的章节 id（ChapterText.order）；行程的全部状态都按这个下标算。
var _order: Array[String] = []
var _done: Array[bool] = []
var _here := -1  ## 此刻所在章节的下标（-1 = 世界不在任何章节里，例如测试夹具）
var _sel := 0    ## 当前选中的章节下标
var _num_labels: Array[Label] = []
var _act_labels: Array[Label] = []
var _tally_labels: Array[Label] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_order = ChapterText.order()
	_shell = Modal.build(self, {
		"object": ObjectKit.Kind.PLATE,
		"title": "地 图",
		"size": Vector2(1120.0, 640.0),
		"hint": "←→ 选章 · 实心余烬 = 已点燃 · 空心 = 未点燃 · 白箭头是你",
		"back": "Esc / 回车 返回",
	})
	_root = _shell["root"] as Control
	# The physical chapter holes own the top of this plate. Keep the shared
	# Header node for callers, but let the selector replace its vertical space.
	(_shell["card"] as Control).get_node("Content/Header").visible = false
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

	_rail = RouteRail.new()
	_rail.name = "Route"
	_rail.picked.connect(select_chapter)
	_rail.resized.connect(_layout_route)
	column.add_child(_rail)
	_build_route_labels()
	column.add_child(_build_route_head())

	var middle := HBoxContainer.new()
	middle.name = "Middle"
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 16)
	column.add_child(middle)
	_build_room(middle)
	_build_dossier(middle)

	column.add_child(_build_legend())


# --- 行程横带 -----------------------------------------------------------------

func _build_route_head() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "RouteHead"
	head.add_child(UiKit.label("地 图 · 行 程", &"SubHeadLabel"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_count = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_count.name = "Count"
	_count.modulate = UiKit.EMBER_ASH
	head.add_child(_count)
	return head


## 幕名、幕的进度、章节序号都是横带上的文字，挂在 RouteRail 下面按节点位置摆。
func _build_route_labels() -> void:
	for i in _order.size():
		var num := UiKit.label(ChapterText.number_of(_order[i]), &"TinyLabel",
				HORIZONTAL_ALIGNMENT_CENTER)
		num.name = "Num%02d" % (i + 1)
		_rail.add_child(num)
		_num_labels.append(num)
	for a in TitleGauge.ACT_STARTS.size():
		var act_name := String(ChapterText.ACTS[a].get("name", ""))
		var glyph := UiKit.label(act_name, &"SubHeadLabel")
		glyph.name = "Act%d" % a
		_rail.add_child(glyph)
		_act_labels.append(glyph)
		var tally := UiKit.label("", &"TinyLabel")
		tally.name = "Tally%d" % a
		_rail.add_child(tally)
		_tally_labels.append(tally)
	_layout_route()


## 文字的位置跟着节点走：章节序号落在节点正下方，幕名落在幕的第一个节点左上方。
func _layout_route() -> void:
	if _rail == null or _num_labels.is_empty():
		return
	var geo := RouteRail.geometry(_rail.size.x, _order.size())
	for i in _num_labels.size():
		var lab := _num_labels[i]
		lab.position = Vector2(geo.x + float(i) * geo.y - 36.0, RAIL_NUM_Y)
		lab.size = Vector2(72.0, 18.0)
	for a in _act_labels.size():
		var first := int(TitleGauge.ACT_STARTS[a])
		var x := geo.x + float(first) * geo.y - 24.0
		_act_labels[a].position = Vector2(x, 70.0)
		_act_labels[a].size = Vector2(28.0, 28.0)
		_tally_labels[a].position = Vector2(x + 30.0, 76.0)
		_tally_labels[a].size = Vector2(96.0, 18.0)


## 行程的读数：已过几章、每幕的进度、各章文字的颜色。
func _refresh_route() -> void:
	if _count == null:
		return
	var cleared := 0
	for d in _done:
		if d:
			cleared += 1
	_count.text = "已过 %d / %d 章" % [cleared, _order.size()]
	for a in _tally_labels.size():
		var first := int(TitleGauge.ACT_STARTS[a])
		var end := int(TitleGauge.ACT_STARTS[a + 1]) \
				if a + 1 < TitleGauge.ACT_STARTS.size() else _order.size()
		var done_in_act := 0
		for i in range(first, mini(end, _done.size())):
			if _done[i]:
				done_in_act += 1
		_tally_labels[a].text = "%d / %d" % [done_in_act, end - first]
		var act_here := _here >= first and _here < end
		_act_labels[a].modulate = UiKit.EMBER if act_here else Color(1.0, 1.0, 1.0, 0.7)
		_tally_labels[a].modulate = UiKit.EMBER_ASH if act_here else UiKit.ASH
	for i in _num_labels.size():
		var lab := _num_labels[i]
		if i == _here:
			lab.modulate = GlassKit.EMBER_HOT
		elif i < _done.size() and _done[i]:
			lab.modulate = Color(1.0, 1.0, 1.0, 0.95)
		else:
			lab.modulate = Color(1.0, 1.0, 1.0, 0.4)


# --- 本关剖面 -----------------------------------------------------------------

func _build_room(parent: HBoxContainer) -> void:
	var room := VBoxContainer.new()
	room.name = "Room"
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.add_theme_constant_override("separation", 6)
	parent.add_child(room)
	room.add_child(GlassKit.kicker("本 关 剖 面"))
	_title = UiKit.label("", &"SubHeadLabel")
	_title.name = "ChapterTitle"
	_title.modulate = UiKit.EMBER
	room.add_child(_title)
	var holder := Control.new()
	holder.name = "Holder"
	holder.custom_minimum_size = VIEW_MIN
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.add_child(holder)
	_view = MapView.new()
	_view.name = "View"
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_view)
	_empty = UiKit.label("地图暂不可用", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_empty.name = "Empty"
	_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.visible = false
	holder.add_child(_empty)
	_facts = UiKit.label("", &"FootnoteLabel")
	_facts.name = "Facts"
	room.add_child(_facts)


# --- 章节卷宗 -----------------------------------------------------------------

## 铁板角上钉住的章节纸签：暗墨写在不透明纸上，不透出铁板划痕。
func _build_dossier(parent: HBoxContainer) -> void:
	_dossier = PanelContainer.new()
	_dossier.name = "Dossier"
	_dossier.theme = ObjectKit.surface_theme(ObjectKit.Kind.JOURNAL)
	_dossier.custom_minimum_size = Vector2(DOSSIER_W, 0.0)
	_dossier.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var paper := ObjectKit.journey_tag_style_box().duplicate() as StyleBoxTexture
	paper.content_margin_left = 36.0
	paper.content_margin_top = 40.0
	paper.content_margin_right = 36.0
	paper.content_margin_bottom = 36.0
	_dossier.add_theme_stylebox_override("panel", paper)
	parent.add_child(_dossier)
	var pins := DossierPins.new()
	pins.name = "Pins"
	pins.bind_paper(_dossier)
	_dossier.add_child(pins)
	var box := VBoxContainer.new()
	box.name = "DossierBox"
	box.add_theme_constant_override("separation", 8)
	_dossier.add_child(box)

	_dk = GlassKit.kicker("")
	_dk.modulate = Color.WHITE
	_dk.name = "Kicker"
	box.add_child(_dk)
	_dn = UiKit.label("", &"SubHeadLabel")
	_dn.name = "ChapterName"
	_dn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_dn)
	var status := HBoxContainer.new()
	status.name = "Status"
	status.add_theme_constant_override("separation", 8)
	box.add_child(status)
	_dglyph = MapView.Glyph.new(ROUTE_LOCKED)
	_dglyph.name = "StatusGlyph"
	status.add_child(_dglyph)
	_ds = UiKit.label("", &"TinyStrongLabel")
	_ds.name = "StatusLabel"
	status.add_child(_ds)
	var rule := GlassKit.rule(120.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)
	_dl = UiKit.label("", &"BodyLabel")
	_dl.name = "Line"
	_dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_dl)
	box.add_child(GlassKit.spacer())
	_do = UiKit.label("", &"FootnoteLabel")
	_do.name = "Objective"
	_do.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_do.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_do)
	for label in [_dk, _dn, _ds, _dl, _do]:
		(label as Label).add_theme_color_override("font_color", PAPER_INK)
	_dk.add_theme_color_override("font_color", PAPER_RUST)
	_do.add_theme_color_override("font_color", PAPER_FAINT)


# --- 图例 ---------------------------------------------------------------------

func _build_legend() -> Control:
	var strip := LegendStrip.new()
	strip.name = "Legend"
	var row := HBoxContainer.new()
	row.name = "LegendRow"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	strip.add_child(row)
	_legend(row, ROUTE_DONE, "已通关")
	_legend(row, ROUTE_HERE, "你在这章")
	_legend(row, ROUTE_LOCKED, "未抵达")
	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.color = Color(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 0.8)
	divider.custom_minimum_size = Vector2(2.0, 16.0)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(divider)
	_legend(row, MapView.GLYPH_NEST_LIT, "已点燃的余烬巢")
	_legend(row, MapView.GLYPH_NEST_DIM, "未点燃")
	_legend(row, MapView.GLYPH_EXIT, "出口")
	_legend(row, MapView.GLYPH_PLAYER, "你")
	return strip


## 图例一项：符号与文字用同一个色相 —— 扫一眼图例就能把"哪个颜色是哪种东西"带到地图里去。
func _legend(row: HBoxContainer, kind: int, text: String) -> void:
	row.add_child(MapView.Glyph.new(kind))
	var label := UiKit.label(text, &"HudLabel")
	label.modulate = MapView.GLYPH_COLORS.get(kind, Color.WHITE)
	row.add_child(label)


# --- 快照 / 章节 --------------------------------------------------------------

## 从当前世界取快照。player 为空 / 场景里没有平台时返回空字典。
static func collect(world: Node, player: Node2D) -> Dictionary:
	var platforms: Array[Rect2] = []
	var nests: Array[Dictionary] = []
	var exits: Array[Dictionary] = []
	if world != null:
		_gather(world, platforms, nests, exits)
	if platforms.is_empty():
		return {}
	return {
		"platforms": platforms,
		"nests": nests,
		"exits": exits,
		"player": player.global_position if player != null else Vector2.INF,
		"title": chapter_title(world),
	}


## 当前世界对应的章节 id：按 GameContext.LEVELS 反查场景路径（第一章也认），查不到返回 ""。
static func current_chapter_id(world: Node) -> String:
	if world == null or not is_instance_valid(world) or world.scene_file_path == "":
		return ""
	for id in GameContext.LEVELS:
		if String(GameContext.LEVELS[id]) == world.scene_file_path:
			return String(id)
	return ""


## 本关一行读数：余烬巢点了几个、出口开没开（同一份快照，不另外读场景）。
static func room_facts(snap: Dictionary) -> String:
	if snap.is_empty():
		return ""
	var parts := PackedStringArray()
	var nests: Array = snap.get("nests", [])
	if not nests.is_empty():
		var lit := 0
		for nest in nests:
			if bool((nest as Dictionary).get("lit", false)):
				lit += 1
		parts.append("余烬巢 %d / %d 已点燃" % [lit, nests.size()])
	var exits: Array = snap.get("exits", [])
	if not exits.is_empty():
		var sealed := false
		for ex in exits:
			if bool((ex as Dictionary).get("locked", false)):
				sealed = true
		parts.append("出口 " + ("封锁" if sealed else "已开"))
	return " · ".join(parts)


## 当前关的章节名。暂停菜单档案与地图共用这一份口径：
## 数据驱动章节读 layout.title()，旧章节读脚本常量，第一章读开场分镜的 CHAPTER。
## 任何一个来源都取不到时返回 ""（地图不显示空标题，档案显示破折号）。
static func chapter_title(world: Node) -> String:
	if world == null or not is_instance_valid(world):
		return ""
	var layout: Variant = world.get("layout")
	if layout != null and layout.has_method("title"):
		var from_property := String(layout.call("title"))
		if from_property != "":
			return from_property
	var node := world.get_node_or_null("Layout")
	if node != null and node.has_method("title"):
		var from_node := String(node.call("title"))
		if from_node != "":
			return from_node
	var script := world.get_script() as Script
	if script != null:
		var consts := script.get_script_constant_map()
		if consts.has("LEVEL_TITLE"):
			return String(consts["LEVEL_TITLE"])
		if consts.has("CHAPTER"):
			return String(consts["CHAPTER"])
	# 第一章的名字只在 ChapterTitles 里写一次。不要 preload opening_cinematic.gd：
	# HUD.tscn → PauseMenu → MapScreen 已经在 preload 链上，开场分镜又引 ChapterLevel
	# （它 preload HUD.tscn），这条链会让所有关卡拿到空 PackedScene。
	if script != null and script.resource_path.get_file() == "level01_static.gd":
		return String(ChapterTitles.LEVEL01)
	return ""


static func _gather(node: Node, platforms: Array[Rect2], nests: Array[Dictionary],
		exits: Array[Dictionary]) -> void:
	for child in node.get_children():
		if child is SolidPlatform:
			var plat := child as SolidPlatform
			platforms.append(Rect2(plat.global_position, plat.size))
			continue
		if child is EmberNest:
			nests.append({"pos": (child as Node2D).global_position,
					"lit": (child as EmberNest).is_lit()})
		elif child is LevelExit:
			exits.append({"pos": (child as Node2D).global_position,
					"locked": (child as LevelExit).is_locked()})
		elif child is Player or child is Camera2D:
			continue
		if child.get_child_count() > 0:
			_gather(child, platforms, nests, exits)


## 路线节点的绘制（大号，用在横带上）。pulse 0..1 给"此刻"的光晕呼吸。
static func paint_route_node(canvas: CanvasItem, c: Vector2, state: int, pulse: float = 0.5) -> void:
	var ember := GlassKit.EMBER
	# 冲孔先画凹入的暗芯和下沿反光，再把已抵达的孔烧亮。
	canvas.draw_rect(Rect2(c - Vector2(9.0, 9.0), Vector2(18.0, 18.0)), COL_EDGE)
	canvas.draw_rect(Rect2(c - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), Color("#090A0E"))
	canvas.draw_rect(Rect2(c + Vector2(-7.0, 7.0), Vector2(14.0, 2.0)), Color("#8C7B67"))
	match state:
		ROUTE_DONE:
			canvas.draw_rect(Rect2(c - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), ember)
			canvas.draw_rect(Rect2(c - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), GlassKit.EMBER_HOT)
		ROUTE_HERE:
			canvas.draw_rect(Rect2(c - Vector2(12.0, 12.0), Vector2(24.0, 24.0)),
					Color(ember.r, ember.g, ember.b, 0.08 + 0.10 * pulse))
			canvas.draw_rect(Rect2(c - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), ember.lerp(GlassKit.EMBER_HOT, pulse))
			canvas.draw_rect(Rect2(c - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), GlassKit.EMBER_HOT)


## 同一套状态，缩到图例和卷宗角标那么大（约 18px 见方）。
static func paint_route_legend(canvas: CanvasItem, c: Vector2, state: int) -> void:
	var ember := GlassKit.EMBER
	match state:
		ROUTE_DONE:
			GlassKit.diamond(canvas, c, 7.0, COL_EDGE)
			GlassKit.diamond(canvas, c, 6.0, ember)
			GlassKit.diamond(canvas, c, 2.0, GlassKit.EMBER_HOT)
		ROUTE_HERE:
			GlassKit.diamond(canvas, c, 8.0, Color(ember.r, ember.g, ember.b, 0.5))
			GlassKit.diamond(canvas, c, 5.0, COL_EDGE)
			GlassKit.diamond(canvas, c, 4.0, ember)
		_:
			GlassKit.diamond(canvas, c, 6.0, GlassKit.COLD_EDGE)
			GlassKit.diamond(canvas, c, 4.0, GlassKit.COLD_IRON)


func snapshot() -> Dictionary:
	return _snapshot


## 当前选中的章节 id（没有行程数据时为 ""）。
func selected_chapter() -> String:
	return _order[_sel] if _sel >= 0 and _sel < _order.size() else ""


## 切换选中的章节：←→ 与点击都走这里。越界夹到首尾，换了才响一声。
func select_chapter(index: int) -> void:
	if _order.is_empty():
		return
	var next := clampi(index, 0, _order.size() - 1)
	if next == _sel:
		return
	_sel = next
	if _rail != null:
		_rail.set_selected(_sel)
	_refresh_dossier()
	Sfx.play(&"ui_move")


func _default_index() -> int:
	if _here >= 0:
		return _here
	var last := -1
	for i in _done.size():
		if _done[i]:
			last = i
	return maxi(last, 0)


func _refresh_dossier() -> void:
	if _dk == null:
		return
	var id := selected_chapter()
	if id == "":
		return
	var cleared := _sel < _done.size() and _done[_sel]
	var here := _sel == _here
	var state := ROUTE_HERE if here else (ROUTE_DONE if cleared else ROUTE_LOCKED)
	_dk.text = "%s 幕 · %s 章" % [String(ChapterText.act_of(id).get("name", "")),
			ChapterText.number_of(id)]
	_dn.text = ChapterText.name_of(id)
	_dglyph.kind = state
	_dglyph.queue_redraw()
	if here:
		_ds.text = "进 行 中"
		_ds.add_theme_color_override("font_color", PAPER_RUST)
		_dl.text = ChapterText.wake_of(id)
		_dl.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_do.text = "目 标 · " + ChapterText.objective_of(id)
	elif cleared:
		_ds.text = "已 通 关"
		_ds.add_theme_color_override("font_color", PAPER_RUST)
		_dl.text = ChapterText.recap_of(id)
		_dl.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_do.text = ""
	else:
		_ds.text = "未 抵 达"
		_ds.add_theme_color_override("font_color", PAPER_FAINT)
		_dl.text = "尚未抵达。"
		_dl.modulate = Color.WHITE
		_do.text = ""


## 章节名随开屏淡入：卡片是"啪"一下到位（见 ui_modal 的约定），但文字
## 慢 0.12s 亮起，读起来像标题先落、内容后显，而不是整块一起闪出来。
func _fade_title() -> void:
	if _title == null:
		return
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	_title.modulate = Color(UiKit.EMBER.r, UiKit.EMBER.g, UiKit.EMBER.b, 0.0)
	_title_tween = create_tween()
	_title_tween.tween_property(_title, "modulate:a", 1.0, 0.24) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# --- 开合 / 输入 --------------------------------------------------------------

func open() -> void:
	_closing = false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var world := GameContext.world_root(player) if player != null else null
	_snapshot = collect(world, player)
	_view.setup(_snapshot)
	_view.running = true
	_view.visible = not _snapshot.is_empty()
	_empty.visible = _snapshot.is_empty()
	_title.text = String(_snapshot.get("title", ""))
	_facts.text = room_facts(_snapshot)
	_fade_title()
	# 行程：已通关来自存档旗标（与故事页同一口径），「此刻」来自当前世界。
	_done = GlassKit.done_from_flags(SaveData.flags)
	_here = _order.find(current_chapter_id(world))
	_sel = _default_index()
	_rail.set_state(_done, _here, _sel)
	_rail.set_breathing(true)
	_refresh_route()
	_refresh_dossier()
	visible = true
	(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_view.running = false
	if _rail != null:
		_rail.set_breathing(false)
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	# 退场动画播完才隐藏：卡片沉回去、纱幕收掉，然后才 emit closed。
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		closed.emit()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept") or event.is_action_pressed("map"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		select_chapter(_sel - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		select_chapter(_sel + 1)
		get_viewport().set_input_as_handled()


## 行程横带：一条铁轨串起 14 个节点，幕与幕之间用一道横线分开。纯绘制，
## 文字是它的子 Label（由 MapScreen 排位）。点击节点选中；只在打开时才逐帧呼吸。
class RouteRail extends Control:
	signal picked(index: int)

	var _done: Array[bool] = []
	var _here := -1
	var _sel := 0
	var _t := 0.0
	var _heat := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, RAIL_H)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(false)

	## 节点的横向排布：返回 (第一个节点的 x, 相邻节点的间距)。间距向下取整，两端留白对称。
	static func geometry(width: float, count: int) -> Vector2:
		var n := maxi(count, 2)
		var pitch := floorf((width - 2.0 * RAIL_EDGE) / float(n - 1))
		var x0 := floorf((width - pitch * float(n - 1)) * 0.5)
		return Vector2(x0, pitch)

	func set_state(done: Array[bool], here: int, sel: int) -> void:
		_done = done.duplicate()
		_here = here
		_sel = sel
		queue_redraw()

	func set_selected(sel: int) -> void:
		_sel = sel
		_heat = 1.0
		queue_redraw()

	## Drawing and mouse targeting share one physical hole centre.
	func hole_center(index: int) -> Vector2:
		var geo := geometry(size.x, _done.size())
		return Vector2(floorf(geo.x + float(index) * geo.y), RAIL_NODE_Y)

	func hole_at_position(point: Vector2) -> int:
		for i in _done.size():
			if Rect2(hole_center(i) - Vector2(16.0, 16.0), Vector2(32.0, 32.0)).has_point(point):
				return i
		return -1

	func selected_hole_is_burning() -> bool:
		return _sel >= 0 and _sel < _done.size()

	func set_breathing(on: bool) -> void:
		set_process(on)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		_heat = maxf(0.0, _heat - delta * 3.0)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mouse := event as InputEventMouseButton
		if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		var i := hole_at_position(mouse.position)
		if i >= 0:
			picked.emit(i)
			accept_event()

	func _draw() -> void:
		var n := _done.size()
		if n == 0:
			return
		var geo := geometry(size.x, n)
		var x0 := geo.x
		var pitch := geo.y
		var pulse := 0.5 + 0.5 * sin(TAU * _t / 1.6)
		# Close the texture's two anonymous suspension slots with a pressed lip:
		# the row below is the single, interactive set of chapter punch holes.
		draw_rect(Rect2(-8.0, -28.0, size.x + 16.0, 16.0), Color("#4C555A"))
		draw_line(Vector2(-8.0, -28.0), Vector2(size.x + 8.0, -28.0), Color("#7E8986"), 2.0)
		draw_line(Vector2(-8.0, -12.0), Vector2(size.x + 8.0, -12.0), Color("#222D36"), 2.0)
		# 节点之间的铁轨：两端都通关时烧成余烬。
		for i in n - 1:
			var lit := _done[i] and _done[i + 1]
			var x_a := x0 + float(i) * pitch + 9.0
			var x_b := x0 + float(i + 1) * pitch - 9.0
			draw_rect(Rect2(x_a, RAIL_NODE_Y - 2.0, x_b - x_a, 2.0), Color("#111B25"))
			draw_rect(Rect2(x_a, RAIL_NODE_Y, x_b - x_a, 2.0),
					GlassKit.EMBER if lit else COL_ROD)
			draw_rect(Rect2(x_a, RAIL_NODE_Y + 2.0, x_b - x_a, 2.0), Color("#6A7371"))
		# 幕：一道横线横跨本幕的节点，幕与幕之间留一段缝；全幕通关时横线烧成余烬。
		for a in TitleGauge.ACT_STARTS.size():
			var first: int = int(TitleGauge.ACT_STARTS[a])
			var end: int = int(TitleGauge.ACT_STARTS[a + 1]) \
					if a + 1 < TitleGauge.ACT_STARTS.size() else n
			var x_from := x0 + float(first) * pitch - 24.0
			var x_to := x0 + float(mini(end, n) - 1) * pitch + 24.0
			var act_done := true
			for i in range(first, mini(end, n)):
				if not _done[i]:
					act_done = false
			var rule := Color(GlassKit.EMBER.r, GlassKit.EMBER.g, GlassKit.EMBER.b, 0.5) \
					if act_done else COL_ROD
			draw_rect(Rect2(x_from, RAIL_RULE_Y, x_to - x_from, 2.0), rule)
			draw_rect(Rect2(x_from, RAIL_RULE_Y, 2.0, 10.0), rule)
		for i in n:
			var c := hole_center(i)
			var state := ROUTE_HERE if i == _here else (ROUTE_DONE if _done[i] else ROUTE_LOCKED)
			MapScreen.paint_route_node(self, c, state, pulse)
		# 选中：四角括号（和卡片同一套 2px 栅格）+ 节点底下一根余烬短棒。
		var sc := hole_center(_sel)
		# Selection heats the punched metal itself, including unopened chapters.
		# The brackets are an additional aiming aid, never the only selection cue.
		var burn := GlassKit.EMBER.lerp(GlassKit.EMBER_HOT, 0.35 + 0.30 * pulse + 0.35 * _heat)
		draw_rect(Rect2(sc - Vector2(12.0, 12.0), Vector2(24.0, 24.0)),
				Color(burn.r, burn.g, burn.b, (0.12 + 0.12 * pulse + 0.12 * _heat) * Settings.flash_scale))
		draw_rect(Rect2(sc - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), burn)
		draw_rect(Rect2(sc - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), GlassKit.EMBER_HOT)
		_bracket(sc, 13.0, Color(GlassKit.EMBER.r, GlassKit.EMBER.g, GlassKit.EMBER.b,
				0.55 + 0.45 * pulse))
		draw_rect(Rect2(sc.x - 6.0, RAIL_CURSOR_Y, 12.0, 2.0), GlassKit.EMBER)

	func _bracket(c: Vector2, h: float, col: Color) -> void:
		var a := 6.0
		var l := c.x - h
		var r := c.x + h - 2.0
		var t := c.y - h
		var b := c.y + h - 2.0
		draw_rect(Rect2(l, t, a, 2.0), col)
		draw_rect(Rect2(l, t, 2.0, a), col)
		draw_rect(Rect2(r - a + 2.0, t, a, 2.0), col)
		draw_rect(Rect2(r, t, 2.0, a), col)
		draw_rect(Rect2(l, b, a, 2.0), col)
		draw_rect(Rect2(l, b - a + 2.0, 2.0, a), col)
		draw_rect(Rect2(r - a + 2.0, b, a, 2.0), col)
		draw_rect(Rect2(r, b - a + 2.0, 2.0, a), col)


## The four nails belong to this paper attachment, not to the steel plate's
## installation animation. Node2D keeps them outside PanelContainer's text box.
class DossierPins extends Node2D:
	var _paper: Control

	func bind_paper(paper: Control) -> void:
		_paper = paper
		paper.item_rect_changed.connect(queue_redraw)

	func pin_positions() -> Array[Vector2]:
		if not is_instance_valid(_paper):
			return []
		return [Vector2(22.0, 22.0), Vector2(_paper.size.x - 28.0, 22.0),
				_paper.size - Vector2(26.0, 26.0), Vector2(22.0, _paper.size.y - 26.0)]

	func _draw() -> void:
		for p in pin_positions():
			draw_rect(Rect2(p + Vector2(-6.0, -4.0), Vector2(14.0, 14.0)), Color("#5D4F3A"))
			draw_rect(Rect2(p - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), Color("#231E1B"))
			draw_rect(Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color("#8B7958"))
			draw_line(p + Vector2(-4.0, -4.0), p + Vector2(2.0, -4.0), Color("#D1B980"), 2.0)
			draw_line(p + Vector2(-2.0, 2.0), p + Vector2(2.0, -2.0), Color("#3B3027"), 2.0)


## 图例条：压暗的半透明铁条，上下一道锈线，两端削角（与卷宗卡同一个阶梯）。
class LegendStrip extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, 34.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var fill := Color(0.03, 0.02, 0.04, 0.5)
		draw_rect(Rect2(6.0, 0.0, w - 12.0, h), fill)
		draw_rect(Rect2(2.0, 4.0, w - 4.0, h - 8.0), fill)
		draw_rect(Rect2(0.0, 6.0, w, h - 12.0), fill)
		var edge := Color(0.30, 0.17, 0.10, 0.85)
		draw_rect(Rect2(6.0, 0.0, w - 12.0, 1.0), edge)
		draw_rect(Rect2(6.0, h - 1.0, w - 12.0, 1.0), edge)


## 把快照画成一张剖面。纯绘制，数据在 setup() 里换成屏幕坐标；尺寸跟着控件走。
class MapView extends Control:
	const GLYPH_NEST_LIT := 0
	const GLYPH_NEST_DIM := 1
	const GLYPH_EXIT := 2
	const GLYPH_PLAYER := 3
	const GLYPH_EXIT_LOCKED := 4

	## 图例与地图共用的符号色：图例文字、地图里的图标、卷宗的状态字都从这里取。
	const GLYPH_COLORS := {
		GLYPH_NEST_LIT: COL_NEST_LIT,
		GLYPH_NEST_DIM: COL_NEST_DIM,
		GLYPH_EXIT: COL_EXIT,
		GLYPH_PLAYER: COL_PLAYER,
		ROUTE_DONE: GlassKit.EMBER,
		ROUTE_HERE: GlassKit.EMBER_HOT,
		ROUTE_LOCKED: UiKit.ASH,
	}
	## 玩家箭头的描边色：压在已点燃的琥珀巢或暖白出口门上时，纯白箭头会
	## 溶进底色；一圈深墨描边让"你"在任何符号上都读得出来。
	const GLYPH_EDGE := Color("#2A1E32")

	## 地图打开时才逐帧重绘（脉动的玩家箭头）；关着的时候不白耗。
	var running := false
	var _snap: Dictionary = {}
	var _bounds := Rect2()
	var _scale := 1.0
	var _origin := Vector2.ZERO
	var _time := 0.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_fit()
			queue_redraw()

	func setup(snap: Dictionary) -> void:
		_snap = snap
		_bounds = Rect2()
		_measure()
		_fit()
		queue_redraw()

	func _process(delta: float) -> void:
		if not running or _snap.is_empty():
			return
		_time += delta
		queue_redraw()

	## 世界包围盒：平台 + 所有标记，四周各留 24 世界像素。
	func _measure() -> void:
		if _snap.is_empty():
			return
		var box: Rect2 = (_snap["platforms"] as Array[Rect2])[0]
		for rect in _snap["platforms"]:
			box = box.merge(rect)
		for n in _snap["nests"]:
			box = box.expand(n["pos"])
		for e in _snap["exits"]:
			box = box.expand(e["pos"])
		var player_pos: Vector2 = _snap["player"]
		if player_pos != Vector2.INF:
			box = box.expand(player_pos)
		_bounds = box.grow(24.0)

	## 按当前控件尺寸算比例：整幅等比压进视口，四周留 PAD。
	func _fit() -> void:
		if _snap.is_empty() or _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
			return
		var avail := size - Vector2(PAD, PAD)
		if avail.x < 8.0 or avail.y < 8.0:
			return
		_scale = maxf(MIN_SCALE, minf(avail.x / _bounds.size.x, avail.y / _bounds.size.y))
		_origin = (size - _bounds.size * _scale) * 0.5

	func to_view(world: Vector2) -> Vector2:
		return (_origin + (world - _bounds.position) * _scale).round()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), COL_BACK)
		draw_rect(Rect2(Vector2.ZERO, size), COL_FRAME, false, 2.0)
		if _snap.is_empty():
			return
		for rect in _snap["platforms"]:
			var a := to_view(rect.position)
			var box := Vector2(maxf(2.0, rect.size.x * _scale), maxf(2.0, rect.size.y * _scale)).round()
			draw_rect(Rect2(a, box), COL_PLATFORM)
			draw_rect(Rect2(a, Vector2(box.x, 2.0)), COL_PLATFORM_TOP)
		for e in _snap["exits"]:
			var kind := GLYPH_EXIT if not bool(e["locked"]) else GLYPH_EXIT_LOCKED
			Glyph.paint(self, to_view(e["pos"]), kind, 1.0)
		for n in _snap["nests"]:
			Glyph.paint(self, to_view(n["pos"]), GLYPH_NEST_LIT if n["lit"] else GLYPH_NEST_DIM, 1.0)
		var player_pos: Vector2 = _snap["player"]
		if player_pos != Vector2.INF:
			var pulse := 0.7 + 0.3 * sin(TAU * _time / 1.2)
			Glyph.paint(self, to_view(player_pos), GLYPH_PLAYER, pulse)

	## 图例与地图共用的小图标：以 center 为中心，约 12x12 的像素块。
	class Glyph extends Control:
		var kind := 0

		func _init(p_kind: int = 0) -> void:
			kind = p_kind
			custom_minimum_size = Vector2(18.0, 18.0)
			mouse_filter = Control.MOUSE_FILTER_IGNORE

		func _draw() -> void:
			paint(self, size * 0.5, kind, 1.0)

		static func paint(canvas: CanvasItem, c: Vector2, p_kind: int, alpha: float) -> void:
			match p_kind:
				GLYPH_NEST_LIT:
					var pts := PackedVector2Array([c + Vector2(0, -7), c + Vector2(6, 0),
							c + Vector2(0, 7), c + Vector2(-6, 0)])
					canvas.draw_colored_polygon(pts, Color(COL_NEST_LIT, alpha))
					canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#7A3A12"), 1.0)
				GLYPH_NEST_DIM:
					var pts2 := PackedVector2Array([c + Vector2(0, -6), c + Vector2(5, 0),
							c + Vector2(0, 6), c + Vector2(-5, 0)])
					canvas.draw_polyline(pts2 + PackedVector2Array([pts2[0]]), COL_NEST_DIM, 2.0)
				GLYPH_EXIT:
					canvas.draw_rect(Rect2(c + Vector2(-5, -8), Vector2(10, 16)), COL_EXIT)
					canvas.draw_rect(Rect2(c + Vector2(-5, -8), Vector2(10, 16)), GLYPH_EDGE, false, 1.0)
					canvas.draw_rect(Rect2(c + Vector2(-2, -3), Vector2(4, 11)), GLYPH_EDGE)
				GLYPH_EXIT_LOCKED:
					# 封锁的出口：门框是暗铁、门洞仍压暗，和"已开"的暖白门一眼分开。
					canvas.draw_rect(Rect2(c + Vector2(-5, -8), Vector2(10, 16)),
							Color(COL_EXIT_LOCKED, alpha), false, 2.0)
					canvas.draw_rect(Rect2(c + Vector2(-2, -3), Vector2(4, 11)), GLYPH_EDGE)
				GLYPH_PLAYER:
					var tri := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(-6, 6)])
					canvas.draw_colored_polygon(tri, Color(COL_PLAYER, alpha))
					canvas.draw_polyline(tri + PackedVector2Array([tri[0]]), GLYPH_EDGE, 1.0)
				ROUTE_DONE, ROUTE_HERE, ROUTE_LOCKED:
					MapScreen.paint_route_legend(canvas, c, p_kind)
