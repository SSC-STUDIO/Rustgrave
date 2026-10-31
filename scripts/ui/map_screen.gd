class_name MapScreen
extends CanvasLayer
## 暂停菜单里的《ICEY》式树状节点选关与本房剖面地图：
##   · 行程冲孔带（顶沿）：14 个节点按 醒 / 疑 / 铸 / 破 四幕刻成冲孔，保留物理钢板顶缘手感。
##   · 树状节点图（左上 NodeTree）：8 主线节点横向延展 + 5 条叛逆裂隙支线上下分叉 + 归零母模皇冠节点；
##     显示父子连线、「??」未知分叉提示与【真名残片 X / 5】收集状态；支持点击 / 方向键选关与一键跃迁。
##   · 本房剖面（左下Holder）：当前房间的 SolidPlatform、余烬巢、切房门/出口与脉动骑士箭头。
##   · 节点卷宗（右侧纸签）：节点状态、伊尔指引 / 真相批注、残片状态与「跃迁至此节点」按钮。

signal closed
signal node_teleported(node_id: String)

const Modal := preload("res://scripts/ui/ui_modal.gd")
const ObjectKit := preload("res://scripts/ui/ui_object.gd")
const PAPER_INK := Color("#35291F")
const PAPER_FAINT := Color("#70604B")
const PAPER_RUST := Color("#874626")
const PAPER_TRUTH := Color("#1F4E5F")

const PAD := 24.0
const MIN_SCALE := 0.02
const VIEW_MIN := Vector2(360.0, 96.0)
const TREE_MIN := Vector2(360.0, 148.0)
const DOSSIER_W := 424.0
const RAIL_H := 100.0
const RAIL_EDGE := 24.0
const RAIL_NODE_Y := 22.0
const RAIL_RULE_Y := 22.0
const RAIL_NUM_Y := 42.0
const RAIL_CURSOR_Y := 62.0

const ROUTE_DONE := 10
const ROUTE_HERE := 11
const ROUTE_LOCKED := 12
const ROUTE_UNLOCKED := 13

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
const COL_TRUTH := Color("#7CE8FF")
const COL_UNLOCKED := Color("#C98A4B")

var _root: Control
var _shell: Dictionary = {}
var _closing := false
var _tree_canvas: NodeTreeCanvas
var _view: MapView
var _title: Label
var _empty: Label
var _facts: Label
var _truth_count: Label
var _count: Label
var _rail: RouteRail
var _dossier: PanelContainer
var _dk: Label
var _dn: Label
var _ds: Label
var _dl: Label
var _dtruth: Label
var _do: Label
var _teleport_btn: Button
var _dglyph: MapView.Glyph
var _snapshot: Dictionary = {}
var _title_tween: Tween
var _order: Array[String] = []
var _done: Array[bool] = []
var _unlocked: Array[bool] = []
var _fragments: PackedStringArray = PackedStringArray()
var _here := -1
var _sel := 0
var _num_labels: Array[Label] = []
var _act_labels: Array[Label] = []
var _tally_labels: Array[Label] = []
## 测试钩子：设置后跃迁不走真实换场，而是把目标场景路径交给回调。
var teleport_requester: Callable = Callable()


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
		"hint": "←→↑↓ 选节点 · Enter 跃迁重玩 · ✦ = 真名残片",
		"back": "Esc / M 返回",
	})
	_root = _shell["root"] as Control
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


# --- 行程横带与残片统计 -------------------------------------------------------

func _build_route_head() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "RouteHead"
	head.add_theme_constant_override("separation", 16)
	head.add_child(UiKit.label("地 图 · 节 点 树", &"SubHeadLabel"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_truth_count = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_truth_count.name = "TruthCount"
	_truth_count.modulate = COL_TRUTH
	head.add_child(_truth_count)
	_count = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_count.name = "Count"
	_count.modulate = UiKit.EMBER_ASH
	head.add_child(_count)
	return head


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


func _layout_route() -> void:
	if _rail == null or _num_labels.is_empty():
		return
	var geo := RouteRail.geometry(_rail.size.x, _order.size())
	for i in _num_labels.size():
		var lab := _num_labels[i]
		lab.position = Vector2(floorf(geo.x + float(i) * geo.y - 36.0), RAIL_NUM_Y)
		lab.size = Vector2(72.0, 18.0)
	for a in _act_labels.size():
		var first := int(TitleGauge.ACT_STARTS[a])
		var x := floorf(geo.x + float(first) * geo.y - 24.0)
		_act_labels[a].position = Vector2(x, 70.0)
		_act_labels[a].size = Vector2(28.0, 28.0)
		_tally_labels[a].position = Vector2(x + 30.0, 76.0)
		_tally_labels[a].size = Vector2(96.0, 18.0)


func _refresh_route() -> void:
	if _count == null:
		return
	var cleared := 0
	for d in _done:
		if d:
			cleared += 1
	var frag_cnt := NarrativeCatalog.fragment_count(_fragments)
	var frag_total := NarrativeCatalog.FRAGMENT_IDS.size()
	_truth_count.text = "✦ 真名残片 %d / %d" % [frag_cnt, frag_total]
	_truth_count.modulate = COL_TRUTH if frag_cnt > 0 else UiKit.ASH
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
		elif i < _unlocked.size() and _unlocked[i]:
			lab.modulate = Color(0.95, 0.78, 0.55, 0.85)
		else:
			lab.modulate = Color(1.0, 1.0, 1.0, 0.4)


# --- 树状选关画布 + 本房剖面 --------------------------------------------------

func _build_room(parent: HBoxContainer) -> void:
	var room := VBoxContainer.new()
	room.name = "Room"
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.add_theme_constant_override("separation", 6)
	parent.add_child(room)

	_tree_canvas = NodeTreeCanvas.new()
	_tree_canvas.name = "NodeTree"
	_tree_canvas.node_clicked.connect(_on_tree_node_clicked)
	room.add_child(_tree_canvas)

	var room_bar := HBoxContainer.new()
	room_bar.name = "RoomBar"
	room_bar.add_theme_constant_override("separation", 10)
	room.add_child(room_bar)
	_title = UiKit.label("", &"TinyStrongLabel")
	_title.name = "ChapterTitle"
	_title.modulate = UiKit.EMBER
	room_bar.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_bar.add_child(spacer)
	_facts = UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_facts.name = "Facts"
	room_bar.add_child(_facts)

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
	_empty = UiKit.label("当前区域剖面暂不可用", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_empty.name = "Empty"
	_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.visible = false
	holder.add_child(_empty)


# --- 章节卷宗与跃迁按钮 -------------------------------------------------------

func _build_dossier(parent: HBoxContainer) -> void:
	_dossier = PanelContainer.new()
	_dossier.name = "Dossier"
	_dossier.theme = ObjectKit.surface_theme(ObjectKit.Kind.JOURNAL)
	_dossier.custom_minimum_size = Vector2(DOSSIER_W, 0.0)
	_dossier.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var paper := ObjectKit.journey_tag_style_box().duplicate() as StyleBoxTexture
	paper.content_margin_left = 36.0
	paper.content_margin_top = 34.0
	paper.content_margin_right = 36.0
	paper.content_margin_bottom = 28.0
	_dossier.add_theme_stylebox_override("panel", paper)
	parent.add_child(_dossier)
	var pins := DossierPins.new()
	pins.name = "Pins"
	pins.bind_paper(_dossier)
	_dossier.add_child(pins)
	var box := VBoxContainer.new()
	box.name = "DossierBox"
	box.add_theme_constant_override("separation", 6)
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
	_dtruth = UiKit.label("", &"TinyStrongLabel")
	_dtruth.name = "TruthBadge"
	_dtruth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dtruth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_dtruth)
	_do = UiKit.label("", &"FootnoteLabel")
	_do.name = "Objective"
	_do.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_do.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_do)

	_teleport_btn = Button.new()
	_teleport_btn.name = "TeleportButton"
	_teleport_btn.custom_minimum_size = Vector2(0.0, 32.0)
	_teleport_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_teleport_btn.focus_mode = Control.FOCUS_NONE
	_style_paper_button(_teleport_btn)
	_teleport_btn.pressed.connect(func() -> void: teleport_to_selected())
	box.add_child(_teleport_btn)

	for label in [_dk, _dn, _ds, _dl, _dtruth, _do]:
		(label as Label).add_theme_color_override("font_color", PAPER_INK)
	_dk.add_theme_color_override("font_color", PAPER_RUST)
	_dtruth.add_theme_color_override("font_color", PAPER_TRUTH)
	_do.add_theme_color_override("font_color", PAPER_FAINT)


func _style_paper_button(btn: Button) -> void:
	for state_name in [&"normal", &"hover", &"pressed", &"disabled"]:
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 10.0
		sb.content_margin_right = 10.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		if state_name == &"disabled":
			sb.bg_color = Color(0.22, 0.18, 0.14, 0.12)
			sb.border_color = Color(0.35, 0.28, 0.22, 0.35)
		elif state_name == &"hover" or state_name == &"pressed":
			sb.bg_color = Color(0.55, 0.26, 0.12, 0.24)
			sb.border_color = PAPER_RUST
		else:
			sb.bg_color = Color(0.45, 0.22, 0.10, 0.14)
			sb.border_color = Color(0.53, 0.27, 0.15, 0.72)
		btn.add_theme_stylebox_override(state_name, sb)
	btn.add_theme_color_override("font_color", PAPER_INK)
	btn.add_theme_color_override("font_hover_color", PAPER_RUST)
	btn.add_theme_color_override("font_pressed_color", PAPER_RUST)
	btn.add_theme_color_override("font_disabled_color", PAPER_FAINT)


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
	_legend(row, ROUTE_HERE, "当前节点")
	_legend(row, ROUTE_UNLOCKED, "可跃迁")
	_legend(row, ROUTE_LOCKED, "未解锁")
	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.color = Color(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 0.8)
	divider.custom_minimum_size = Vector2(2.0, 16.0)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(divider)
	_legend(row, MapView.GLYPH_NEST_LIT, "余烬巢")
	_legend(row, MapView.GLYPH_EXIT, "房间门")
	_legend(row, MapView.GLYPH_PLAYER, "你")
	return strip


func _legend(row: HBoxContainer, kind: int, text: String) -> void:
	row.add_child(MapView.Glyph.new(kind))
	var label := UiKit.label(text, &"HudLabel")
	label.modulate = MapView.GLYPH_COLORS.get(kind, Color.WHITE)
	row.add_child(label)


# --- 快照 / 章节 --------------------------------------------------------------

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


static func current_chapter_id(world: Node) -> String:
	if world == null or not is_instance_valid(world):
		return ""
	if world is StageLevel and (world as StageLevel).stage_id != "":
		return (world as StageLevel).stage_id
	if world.scene_file_path == "":
		return ""
	for id in GameContext.LEVELS:
		if String(GameContext.LEVELS[id]) == world.scene_file_path:
			return String(id)
	for leg_id in GameContext.LEGACY_LEVELS:
		if String(GameContext.LEGACY_LEVELS[leg_id]) == world.scene_file_path:
			return String(GameContext.LEGACY_TO_STAGE.get(leg_id, ""))
	return ""


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
		elif child is RoomGate:
			exits.append({"pos": (child as Node2D).global_position,
					"locked": not (child as RoomGate).is_gate_open()})
		elif child is Player or child is Camera2D:
			continue
		if child.get_child_count() > 0:
			_gather(child, platforms, nests, exits)


static func paint_route_node(canvas: CanvasItem, c: Vector2, state: int, pulse: float = 0.5) -> void:
	var ember := GlassKit.EMBER
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
		ROUTE_UNLOCKED:
			canvas.draw_rect(Rect2(c - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), COL_UNLOCKED)
			canvas.draw_rect(Rect2(c - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color("#1B1410"))


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
		ROUTE_UNLOCKED:
			GlassKit.diamond(canvas, c, 6.0, COL_UNLOCKED)
			GlassKit.diamond(canvas, c, 3.0, GlassKit.INK)
		_:
			GlassKit.diamond(canvas, c, 6.0, GlassKit.COLD_EDGE)
			GlassKit.diamond(canvas, c, 4.0, GlassKit.COLD_IRON)


func snapshot() -> Dictionary:
	return _snapshot


func node_tree() -> Control:
	return _tree_canvas


func truth_count_text() -> String:
	return _truth_count.text if _truth_count != null else ""


func selected_chapter() -> String:
	return _order[_sel] if _sel >= 0 and _sel < _order.size() else ""


func is_selected_unlocked() -> bool:
	return _sel >= 0 and _sel < _unlocked.size() and _unlocked[_sel]


func can_teleport_selected() -> bool:
	var id := selected_chapter()
	if id == "" or not GameContext.LEVELS.has(id):
		return false
	if TrialRun.active() or ArenaRun.active():
		return false
	return is_selected_unlocked()


func select_chapter(index: int) -> void:
	if _order.is_empty():
		return
	var next := clampi(index, 0, _order.size() - 1)
	if next == _sel:
		return
	_sel = next
	if _rail != null:
		_rail.set_selected(_sel)
	if _tree_canvas != null:
		_tree_canvas.set_selected(_sel)
	_refresh_dossier()
	Sfx.play(&"ui_move")


func select_node_id(node_id: String) -> void:
	var idx := _order.find(node_id)
	if idx >= 0:
		select_chapter(idx)


func _on_tree_node_clicked(index: int) -> void:
	if index == _sel and can_teleport_selected():
		teleport_to_selected()
	else:
		select_chapter(index)


func _step_tree_vertical(dir: int) -> void:
	var cur_id := selected_chapter()
	if cur_id == "":
		return
	var cur_spec := NarrativeCatalog.node_spec(cur_id)
	var cur_y := float((cur_spec.get("pos", Vector2.ZERO) as Vector2).y)
	var best_idx := -1
	var best_score := 999999.0
	var neighbors: Array = []
	for p in (cur_spec.get("parents", []) as Array):
		neighbors.append(String(p))
	for ch in (cur_spec.get("children", []) as Array):
		neighbors.append(String(ch))
	for nb_id in neighbors:
		var nb_spec := NarrativeCatalog.node_spec(String(nb_id))
		if nb_spec.is_empty():
			continue
		var dy := float((nb_spec.get("pos", Vector2.ZERO) as Vector2).y) - cur_y
		if (dir < 0 and dy < -20.0) or (dir > 0 and dy > 20.0):
			var idx := _order.find(String(nb_id))
			if idx >= 0 and absf(dy) < best_score:
				best_score = absf(dy)
				best_idx = idx
	if best_idx >= 0:
		select_chapter(best_idx)


static func default_entry_room(node_id: String) -> String:
	var spec := NarrativeCatalog.node_spec(node_id)
	var rooms: Array = spec.get("rooms", [])
	if not rooms.is_empty():
		return String(rooms[0])
	if node_id == "stage08_true":
		return "T1"
	if node_id.begins_with("branch"):
		return "B1"
	return "S1"


## 跃迁至当前选中的已解锁节点（清掉该节点临时清房记忆，从首房重新挑战/搜集）。
func teleport_to_selected() -> bool:
	var id := selected_chapter()
	if not can_teleport_selected():
		Sfx.play(&"ui_denied")
		return false
	var path := String(GameContext.LEVELS.get(id, ""))
	if path == "":
		Sfx.play(&"ui_denied")
		return false

	var entry_room := default_entry_room(id)
	StageRoomMemory.clear_stage(id)
	StageRoomMemory.set_pending(id, entry_room, "west")
	SaveData.set_stage_room(id, entry_room, "west")
	SaveData.pending_spawn = Vector2.INF

	_dismiss_for_teleport()
	Sfx.play(&"gate")
	node_teleported.emit(id)
	if teleport_requester.is_valid():
		teleport_requester.call(path)
	elif is_inside_tree():
		Director.fade_to(path, 0.25)
	return true


func _dismiss_for_teleport() -> void:
	_closing = false
	visible = false
	if _view != null:
		_view.running = false
	if _rail != null:
		_rail.set_breathing(false)
	if _tree_canvas != null:
		_tree_canvas.set_breathing(false)
	var p := get_parent()
	if p is PauseMenu:
		var pm := p as PauseMenu
		pm.set("_map_from_hotkey", false)
		pm.set("_open_requested", false)
		pm.set("_closing", false)
		pm.visible = false
		if pm.has_method("_set_play_hud_visible"):
			pm.call("_set_play_hud_visible", true)
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false
	Director.resume()


func _default_index() -> int:
	if _here >= 0:
		return _here
	var last := -1
	for i in _done.size():
		if _done[i]:
			last = i
	if last >= 0:
		return last
	for i in _unlocked.size():
		if _unlocked[i]:
			last = i
	return maxi(last, 0)


func _refresh_dossier() -> void:
	if _dk == null:
		return
	var id := selected_chapter()
	if id == "":
		return
	var spec := NarrativeCatalog.node_spec(id)
	var cleared := _sel < _done.size() and _done[_sel]
	var unlocked := _sel < _unlocked.size() and _unlocked[_sel]
	var here := _sel == _here
	var state := ROUTE_HERE if here else (ROUTE_DONE if cleared else (ROUTE_UNLOCKED if unlocked else ROUTE_LOCKED))
	var kind: StringName = spec.get("kind", &"main")
	var kind_tag := "裂隙支线" if kind == &"branch" else ("真结局终章" if kind == &"true_end" else "主线节点")
	_dk.text = "%s 幕 · %s · %s" % [String(ChapterText.act_of(id).get("name", "")),
			ChapterText.number_of(id), kind_tag]
	_dn.text = ChapterText.name_of(id)
	_dglyph.kind = state
	_dglyph.queue_redraw()

	var frag_id := String(spec.get("fragment_id", ""))
	var has_frag := frag_id != "" and _fragments.has(frag_id)
	if frag_id != "":
		if has_frag:
			var fspec := NarrativeCatalog.fragment_spec(frag_id)
			_dtruth.text = "✦ %s（已拾取）" % String(fspec.get("title", "真名残片"))
		elif unlocked:
			_dtruth.text = "✧ 禁区深处藏有【真名残片】"
		else:
			_dtruth.text = "？？ 违抗司炉指引可偏离至此"
	elif id == "stage08_true":
		var fcnt := NarrativeCatalog.fragment_count(_fragments)
		_dtruth.text = "✦ 五枚真名已齐 · 母模禁门已开" if unlocked \
				else "需集齐五枚真名残片（当前 %d / 5）" % fcnt
	else:
		var fork_hint := String(spec.get("fork_hint", ""))
		_dtruth.text = fork_hint if (unlocked or cleared or here) else ""

	if here:
		_ds.text = "当 前 所 在"
		_ds.add_theme_color_override("font_color", PAPER_RUST)
		_dl.text = String(spec.get("truth_note", ChapterText.wake_of(id))) if has_frag \
				else String(spec.get("guide_note", ChapterText.wake_of(id)))
		_do.text = "目 标 · " + ChapterText.objective_of(id)
	elif cleared:
		_ds.text = "已 通 关"
		_ds.add_theme_color_override("font_color", PAPER_RUST)
		_dl.text = String(spec.get("truth_note", ChapterText.recap_of(id))) if has_frag \
				else ChapterText.recap_of(id)
		_do.text = "目 标 · " + ChapterText.objective_of(id)
	elif unlocked:
		_ds.text = "可 跃 迁"
		_ds.add_theme_color_override("font_color", PAPER_RUST)
		_dl.text = String(spec.get("guide_note", ChapterText.wake_of(id)))
		_do.text = "目 标 · " + ChapterText.objective_of(id)
	else:
		_ds.text = "未 解 锁"
		_ds.add_theme_color_override("font_color", PAPER_FAINT)
		if id == "stage08_true":
			_dl.text = "集齐全部五枚【真名残片】后，真伊尔将为你撕开归零母模的入口。"
		elif kind == &"branch":
			_dl.text = "顺从发光路标的人永远不会踏足此处。试着在前驱节点违抗那道声音。"
		else:
			_dl.text = "尚未抵达此节点。"
		_do.text = ""

	if _teleport_btn != null:
		if TrialRun.active() or ArenaRun.active():
			_teleport_btn.disabled = true
			_teleport_btn.text = "试 炼 / 竞 技 中 不 可 跃 迁"
		elif can_teleport_selected():
			_teleport_btn.disabled = false
			_teleport_btn.text = "重 返 本 节 起 点  [Enter]" if here else "跃 迁 至 此 节 点  [Enter]"
		else:
			_teleport_btn.disabled = true
			_teleport_btn.text = "节 点 未 解 锁"


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
	var player := get_tree().get_first_node_in_group("player") as Node2D if is_inside_tree() else null
	var world := GameContext.world_root(player) if player != null else null
	_snapshot = collect(world, player)
	_view.setup(_snapshot)
	_view.running = true
	_view.visible = not _snapshot.is_empty()
	_empty.visible = _snapshot.is_empty()
	var room_suffix := ""
	if world is StageLevel and (world as StageLevel).current_room_id != "":
		room_suffix = " · 房 %s" % (world as StageLevel).current_room_id
	_title.text = String(_snapshot.get("title", "")) + room_suffix
	_facts.text = room_facts(_snapshot)
	_fade_title()

	_fragments = SaveData.flags.duplicate()
	_done = []
	_unlocked = []
	var cur_id := current_chapter_id(world)
	_here = _order.find(cur_id)
	for i in _order.size():
		var nid := _order[i]
		var is_clr := NarrativeCatalog.is_node_cleared(nid, SaveData.flags)
		var is_unl := (i == _here) or is_clr or NarrativeCatalog.is_node_unlocked(nid, SaveData.flags)
		_done.append(is_clr)
		_unlocked.append(is_unl)
	_sel = _default_index()
	_rail.set_state(_done, _unlocked, _here, _sel)
	_rail.set_breathing(true)
	_tree_canvas.set_state(_order, _done, _unlocked, _fragments, _here, _sel)
	_tree_canvas.set_breathing(true)
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
	if _tree_canvas != null:
		_tree_canvas.set_breathing(false)
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
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
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("map"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		teleport_to_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		select_chapter(_sel - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		select_chapter(_sel + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_step_tree_vertical(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_step_tree_vertical(1)
		get_viewport().set_input_as_handled()


# --- 顶缘冲孔横带 -------------------------------------------------------------

class RouteRail extends Control:
	signal picked(index: int)

	var _done: Array[bool] = []
	var _unlocked: Array[bool] = []
	var _here := -1
	var _sel := 0
	var _t := 0.0
	var _heat := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, RAIL_H)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(false)

	static func geometry(width: float, count: int) -> Vector2:
		var n := maxi(count, 2)
		var pitch := floorf((width - 2.0 * RAIL_EDGE) / float(n - 1))
		var x0 := floorf((width - pitch * float(n - 1)) * 0.5)
		return Vector2(x0, pitch)

	func set_state(done: Array[bool], unlocked: Array[bool], here: int, sel: int) -> void:
		_done = done.duplicate()
		_unlocked = unlocked.duplicate()
		_here = here
		_sel = sel
		queue_redraw()

	func set_selected(sel: int) -> void:
		_sel = sel
		_heat = 1.0
		queue_redraw()

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
		draw_rect(Rect2(-8.0, -28.0, size.x + 16.0, 16.0), Color("#4C555A"))
		draw_line(Vector2(-8.0, -28.0), Vector2(size.x + 8.0, -28.0), Color("#7E8986"), 2.0)
		draw_line(Vector2(-8.0, -12.0), Vector2(size.x + 8.0, -12.0), Color("#222D36"), 2.0)
		for i in n - 1:
			var lit := _done[i] and _done[i + 1]
			var x_a := x0 + float(i) * pitch + 9.0
			var x_b := x0 + float(i + 1) * pitch - 9.0
			draw_rect(Rect2(x_a, RAIL_NODE_Y - 2.0, x_b - x_a, 2.0), Color("#111B25"))
			draw_rect(Rect2(x_a, RAIL_NODE_Y, x_b - x_a, 2.0),
					GlassKit.EMBER if lit else COL_ROD)
			draw_rect(Rect2(x_a, RAIL_NODE_Y + 2.0, x_b - x_a, 2.0), Color("#6A7371"))
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
			var unl := i < _unlocked.size() and _unlocked[i]
			var state := ROUTE_HERE if i == _here else (ROUTE_DONE if _done[i] else (ROUTE_UNLOCKED if unl else ROUTE_LOCKED))
			MapScreen.paint_route_node(self, c, state, pulse)
		var sc := hole_center(_sel)
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


# --- 《ICEY》式树状节点选关画布 -----------------------------------------------

class NodeTreeCanvas extends Control:
	signal node_clicked(index: int)

	const SRC_MIN := Vector2(36.0, 52.0)
	const SRC_MAX := Vector2(532.0, 332.0)

	var _order: Array[String] = []
	var _done: Array[bool] = []
	var _unlocked: Array[bool] = []
	var _fragments: PackedStringArray = PackedStringArray()
	var _here := -1
	var _sel := 0
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = TREE_MIN
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(false)

	func set_state(order: Array[String], done: Array[bool], unlocked: Array[bool],
			fragments: PackedStringArray, here: int, sel: int) -> void:
		_order = order.duplicate()
		_done = done.duplicate()
		_unlocked = unlocked.duplicate()
		_fragments = fragments.duplicate()
		_here = here
		_sel = sel
		queue_redraw()

	func set_selected(sel: int) -> void:
		_sel = sel
		queue_redraw()

	func set_breathing(on: bool) -> void:
		set_process(on)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func node_center(node_id: String) -> Vector2:
		var spec := NarrativeCatalog.node_spec(node_id)
		var raw: Vector2 = spec.get("pos", Vector2(280.0, 190.0))
		var pad_x := 28.0
		var pad_y := 22.0
		var usable := Vector2(maxf(64.0, size.x - pad_x * 2.0), maxf(48.0, size.y - pad_y * 2.0))
		var span := SRC_MAX - SRC_MIN
		var nx := clampf((raw.x - SRC_MIN.x) / span.x, 0.0, 1.0)
		var ny := clampf((raw.y - SRC_MIN.y) / span.y, 0.0, 1.0)
		return Vector2(floorf(pad_x + nx * usable.x), floorf(pad_y + ny * usable.y))

	func node_index_at(point: Vector2) -> int:
		for i in _order.size():
			var c := node_center(_order[i])
			if Rect2(c - Vector2(14.0, 14.0), Vector2(28.0, 28.0)).has_point(point):
				return i
		return -1

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var idx := node_index_at(mb.position)
		if idx >= 0:
			node_clicked.emit(idx)
			accept_event()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#13151A"))
		draw_rect(Rect2(Vector2.ZERO, size), COL_FRAME, false, 2.0)
		if _order.is_empty():
			return
		var pulse := 0.5 + 0.5 * sin(TAU * _t / 1.5)
		var font := get_theme_default_font()

		# 1. 父子拓扑连线（主线铁轨 / 裂隙折线 / 归零母模汇聚线）
		for i in _order.size():
			var cid := _order[i]
			var spec := NarrativeCatalog.node_spec(cid)
			var kind: StringName = spec.get("kind", &"main")
			var c_to := node_center(cid)
			var child_unl := i < _unlocked.size() and _unlocked[i]
			var child_done := i < _done.size() and _done[i]
			for p_var in (spec.get("parents", []) as Array):
				var pid := String(p_var)
				var p_idx := _order.find(pid)
				if p_idx < 0:
					continue
				if cid == "stage08_true" and pid != "stage07":
					# 支线残片汇聚向归零母模用细魂丝表达，不遮挡主干视野
					var fid := String(NarrativeCatalog.node_spec(pid).get("fragment_id", ""))
					if fid != "" and _fragments.has(fid):
						draw_line(node_center(pid), c_to, Color(COL_TRUTH.r, COL_TRUTH.g, COL_TRUTH.b, 0.26), 1.0)
					continue
				var c_from := node_center(pid)
				var parent_unl := p_idx < _unlocked.size() and _unlocked[p_idx]
				var edge_col := COL_ROD
				if kind == &"true_end":
					edge_col = COL_TRUTH if child_unl else Color(0.28, 0.42, 0.48, 0.45)
				elif kind == &"branch":
					edge_col = COL_TRUTH if child_done else (COL_UNLOCKED if child_unl else Color(0.45, 0.35, 0.32, 0.48))
				else:
					edge_col = GlassKit.EMBER if (child_done or child_unl) else COL_ROD
				if kind == &"branch" and not child_unl and parent_unl:
					_draw_dashed(c_from, c_to, edge_col)
				else:
					var mid := Vector2(c_from.x, c_to.y) if kind == &"branch" else Vector2((c_from.x + c_to.x) * 0.5, c_from.y)
					if kind == &"branch":
						draw_line(c_from, mid, edge_col, 2.0)
						draw_line(mid, c_to, edge_col, 2.0)
					else:
						draw_line(c_from, c_to, edge_col, 2.0)

		# 2. 绘制 14 枚节点本体与残片徽记
		for i in _order.size():
			var nid := _order[i]
			var spec := NarrativeCatalog.node_spec(nid)
			var kind: StringName = spec.get("kind", &"main")
			var c := node_center(nid)
			var unl := i < _unlocked.size() and _unlocked[i]
			var done := i < _done.size() and _done[i]
			var here := i == _here
			var frag_id := String(spec.get("fragment_id", ""))
			var has_frag := frag_id != "" and _fragments.has(frag_id)

			if here:
				draw_rect(Rect2(c - Vector2(12.0, 12.0), Vector2(24.0, 24.0)),
						Color(GlassKit.EMBER.r, GlassKit.EMBER.g, GlassKit.EMBER.b, 0.14 + 0.12 * pulse))

			if kind == &"branch":
				var fill := COL_TRUTH if has_frag else (COL_UNLOCKED if unl else GlassKit.COLD_IRON)
				GlassKit.diamond(self, c, 9.0, COL_EDGE if unl else GlassKit.COLD_EDGE)
				GlassKit.diamond(self, c, 7.0, Color("#0E1016"))
				GlassKit.diamond(self, c, 5.0, fill)
				if has_frag:
					GlassKit.diamond(self, c, 2.0, Color.WHITE)
				elif not unl and font != null:
					draw_string(font, c + Vector2(-8.0, 4.0), "??", HORIZONTAL_ALIGNMENT_CENTER, 18.0, 10,
							Color(0.72, 0.66, 0.62, 0.72))
			elif kind == &"true_end":
				var tfill := COL_TRUTH if unl else GlassKit.COLD_IRON
				GlassKit.diamond(self, c, 11.0, COL_TRUTH if unl else GlassKit.COLD_EDGE)
				GlassKit.diamond(self, c, 8.0, Color("#0B1118"))
				GlassKit.diamond(self, c, 5.0, GlassKit.EMBER_HOT if done else tfill)
			else:
				var state := ROUTE_HERE if here else (ROUTE_DONE if done else (ROUTE_UNLOCKED if unl else ROUTE_LOCKED))
				MapScreen.paint_route_node(self, c, state, pulse)

			if font != null and (unl or done or here or kind == &"main"):
				var short_lbl := String(spec.get("name", "")).substr(0, 2)
				var ly := c.y + 20.0 if c.y > size.y * 0.62 else (c.y - 12.0 if c.y < size.y * 0.38 else c.y + 20.0)
				var lcol := COL_TRUTH if has_frag else (GlassKit.EMBER_HOT if here else (Color(0.92, 0.88, 0.82, 0.88) if unl else Color(0.55, 0.52, 0.50, 0.55)))
				draw_string(font, Vector2(c.x - 18.0, ly), short_lbl, HORIZONTAL_ALIGNMENT_CENTER, 36.0, 10, lcol)

		# 3. 选中准星框
		if _sel >= 0 and _sel < _order.size():
			var sc := node_center(_order[_sel])
			var bcol := Color(GlassKit.EMBER.r, GlassKit.EMBER.g, GlassKit.EMBER.b, 0.65 + 0.35 * pulse)
			var h := 13.0
			var a := 5.0
			draw_rect(Rect2(sc.x - h, sc.y - h, a, 2.0), bcol)
			draw_rect(Rect2(sc.x - h, sc.y - h, 2.0, a), bcol)
			draw_rect(Rect2(sc.x + h - a, sc.y - h, a, 2.0), bcol)
			draw_rect(Rect2(sc.x + h - 2.0, sc.y - h, 2.0, a), bcol)
			draw_rect(Rect2(sc.x - h, sc.y + h - 2.0, a, 2.0), bcol)
			draw_rect(Rect2(sc.x - h, sc.y + h - a, 2.0, a), bcol)
			draw_rect(Rect2(sc.x + h - a, sc.y + h - 2.0, a, 2.0), bcol)
			draw_rect(Rect2(sc.x + h - 2.0, sc.y + h - a, 2.0, a), bcol)

	func _draw_dashed(a: Vector2, b: Vector2, col: Color) -> void:
		var steps := 6
		for s in steps:
			if s % 2 == 1:
				continue
			var p0 := a.lerp(b, float(s) / float(steps))
			var p1 := a.lerp(b, float(s + 1) / float(steps))
			draw_line(p0, p1, col, 1.5)


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


class MapView extends Control:
	const GLYPH_NEST_LIT := 0
	const GLYPH_NEST_DIM := 1
	const GLYPH_EXIT := 2
	const GLYPH_PLAYER := 3
	const GLYPH_EXIT_LOCKED := 4

	const GLYPH_COLORS := {
		GLYPH_NEST_LIT: COL_NEST_LIT,
		GLYPH_NEST_DIM: COL_NEST_DIM,
		GLYPH_EXIT: COL_EXIT,
		GLYPH_PLAYER: COL_PLAYER,
		ROUTE_DONE: GlassKit.EMBER,
		ROUTE_HERE: GlassKit.EMBER_HOT,
		ROUTE_UNLOCKED: COL_UNLOCKED,
		ROUTE_LOCKED: UiKit.ASH,
	}
	const GLYPH_EDGE := Color("#2A1E32")

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
					canvas.draw_rect(Rect2(c + Vector2(-5, -8), Vector2(10, 16)),
							Color(COL_EXIT_LOCKED, alpha), false, 2.0)
					canvas.draw_rect(Rect2(c + Vector2(-2, -3), Vector2(4, 11)), GLYPH_EDGE)
				GLYPH_PLAYER:
					var tri := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(-6, 6)])
					canvas.draw_colored_polygon(tri, Color(COL_PLAYER, alpha))
					canvas.draw_polyline(tri + PackedVector2Array([tri[0]]), GLYPH_EDGE, 1.0)
				ROUTE_DONE, ROUTE_HERE, ROUTE_UNLOCKED, ROUTE_LOCKED:
					MapScreen.paint_route_legend(canvas, c, p_kind)
