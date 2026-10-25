class_name PauseMenu
extends CanvasLayer
## 暂停菜单：Esc 开合；左列是"铁架"式动作栏，右列是本次行程的读数面。
##
## 标题带写「行程暂停」：小字是当前章节的编号，大标题是章节名，标题下面一道章节刻度条
## （GlassKit.ChapterRail）标出战役进度和正在进行的那一章。右列不是石头板，而是一块玻璃读数面：
## 三组小题头下面是左对齐的键、右对齐的值，每一行前面一粒菱形——它回答「我在哪、还剩什么」，
## 和回看余烬那种居中的旅程档案错开。
##
## 版式沿用标题屏那套语言：主行动（回到锈墓）是一整块箭头板，系统类动作是燕尾小板，
## 回标题是只有四只角标的第三层，中间用铆钉横线分组。
##
## 整棵子树 PROCESS_MODE_ALWAYS，所以 get_tree().paused 之后自己还能动。
## 全屏、像素平滑、音量、键位等选项都搬进了设置界面（SettingsScreen）；
## 从这里打开设置 / 教程回看 / 操作说明 / 地图 / 故事都只是在它们上面再盖一层，
## 不碰暂停状态，关闭后菜单光标回到原来那一行。
## 故事页（journal_screen.gd）回答「现在要做什么 / 前情 / 人物 / 名词」，并能回放看过的分镜；
## 回放时本层卡片先藏起来（_on_story_replay_started），播完再回来。

const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"
const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Modal := preload("res://scripts/ui/ui_modal.gd")
const JournalScript := preload("res://scripts/ui/journal_screen.gd")

const ID_RESUME := &"resume"
const ID_EQUIPMENT := &"equipment"
const ID_SETTINGS := &"settings"
const ID_TUTORIAL := &"tutorial"
const ID_CONTROLS := &"controls"
const ID_MAP := &"map"
## 故事页：现在要做什么 / 前情 / 人物 / 名词 / 重看分镜（journal_screen.gd）。
const ID_STORY := &"story"
const ID_TITLE := &"title"
const ID_TRIAL_RESTART := &"trial_restart"
const ID_TRIAL_EXIT := &"trial_exit"
const ID_ARENA_RESTART := &"arena_restart"
const ID_ARENA_EXIT := &"arena_exit"
const TrialRunScript := preload("res://scripts/autoload/trial_run.gd")
const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

## 左列铁架：竖脊贴左缘，板面从 RAIL_X 挂出去；行距由空白节点控，主/次/第三层分开。
## 菜单自然高度 = 主行动 60 + 组距 14 + 铆钉线 16 + 组距 10 + 五格次行动 5×52 + 四道间距 4×6 + 第三层 52 = 436，
## 正好落进 640 高卡片的读数区（440）。标题带换成章节刻度后，铆钉横线让位给刻度条。
const RAIL_X := 24.0
const RAIL_W := 482.0
const DIVIDER_W := 440.0
const MENU_TOP := 0.0
const GAP_GROUP := 14.0
const GAP_DIVIDER := 10.0
const GAP_SECONDARY := 6.0
## 卡片里除读数区以外的部分：内容边距 60 + 标题带 86 + 两道段距 20 + 底部提示带 34。
const CHROME_H := 200.0
## 七格菜单加上「角色与装备」一格（LoadoutBridge 可用时）撑到 494，卡片会被撑到这个上限。
const CARD_MAX_HEIGHT := 700.0
## 读数面的键列宽（12px 小字，和 HUD 的紧凑小字同档）。
const KEY_COLUMN := 92.0
## 标题带：小字写章节编号 + 行程暂停，大标题写章节名；与地图共用 MapScreen.chapter_title 的口径。
const HEAD_KICKER := "行 程 暂 停"
const HEAD_FALLBACK := "暂 停"
## 读数面底板：HUD 的墨带（左侧锈脊 + 铆钉，右侧渐隐），复制一份压成和卡片同一透明度。
const DOSSIER_BASE := &"HudPlate"
const DOSSIER_MARGINS := Vector4(26.0, 18.0, 26.0, 16.0)

var _root: Control
var _shell: Dictionary = {}
var _layout: Control
var _menu: MenuList
var _trial_menu: MenuList
var _arena_menu: MenuList
var _spine: Control
var _controls: ControlsPanel
var _settings: SettingsScreen
var _tutorial: TutorialRecall
var _map_from_hotkey := false
var _map: MapScreen
## journal_screen.gd 没有 class_name：这里不标类型，成员（open / dismiss / replaying…）走动态调用。
var _journal
var _equipment: CanvasLayer
## Esc during a scene fade (respawn fade-in, chapter arrival, Continue) used to be
## dropped without a sound; the request is now kept and honoured once the fade ends.
var _open_requested := false
## 退场动画进行中：防连按 Esc 起两条 tween、重复解除暂停。
var _closing := false

var _kicker_label: Label
var _title_label: Label
var _chapter_rail: GlassKit.ChapterRail
var _dossier_objective: Label
var _dossier_cores: Label
var _dossier_nests: Label
var _dossier_viewport: Label
## 读数行前的菱形：key = 档案键（objective / cores / nests / viewport）。
var _bullets: Dictionary = {}
var _tracker: ObjectiveTracker


## 读数行前的一粒菱形：有数据时烧成余烬，没有数据时是冷铁。
class Bullet extends Control:
	var lit := false:
		set(value):
			lit = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(14.0, 14.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := Vector2(7.0, 7.0)
		if lit:
			GlassKit.diamond(self, c, 5.0, GlassKit.EMBER)
			GlassKit.diamond(self, c, 2.0, GlassKit.EMBER_HOT)
		else:
			GlassKit.diamond(self, c, 4.0, GlassKit.COLD_EDGE)
			GlassKit.diamond(self, c, 2.0, GlassKit.COLD)


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
		"kicker": HEAD_KICKER,
		"title": HEAD_FALLBACK,
		"size": Vector2(1020.0, 640.0),
		"hint": "↑↓ 选择 · Enter 确认",
		"back": "Esc 继续",
		"veil": 0.62,
	})
	_root = _shell["root"] as Control
	var body := _shell["body"] as Control
	_build_header()

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
	_fit_card_to_rail()

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
	_journal = JournalScript.new()
	_journal.layer = 21
	_journal.closed.connect(_resume_menu)
	# 回放分镜时播放器升到层 24，盖过本层（20）和故事页（21）：卡片仍先藏，播完再回来。
	_journal.replay_started.connect(_on_story_replay_started)
	_journal.replay_finished.connect(_on_story_replay_finished)
	add_child(_journal)

	const EQUIPMENT_PANEL_SCENE := "res://scenes/ui/CharacterEquipmentPanel.tscn"
	const EQUIPMENT_PANEL_SCRIPT := "res://scripts/ui/character_equipment_panel.gd"
	if ResourceLoader.exists(EQUIPMENT_PANEL_SCENE):
		_equipment = (load(EQUIPMENT_PANEL_SCENE) as PackedScene).instantiate()
	elif ResourceLoader.exists(EQUIPMENT_PANEL_SCRIPT):
		_equipment = (load(EQUIPMENT_PANEL_SCRIPT) as GDScript).new()
	else:
		_equipment = CanvasLayer.new()
	_equipment.layer = 21
	if _equipment.has_signal("closed"):
		_equipment.connect("closed", _resume_menu)
	add_child(_equipment)

	_refresh_dossier()


## 标题带：Modal 给的小字和大标题保留，把章节刻度条插在大标题与铆钉横线之间。
func _build_header() -> void:
	var card: Node = _shell.get("card") as Control
	var header: Node = card.get_node_or_null("Content/Header") if card != null else null
	if header == null:
		return
	_kicker_label = header.get_node_or_null("Kicker") as Label
	_title_label = header.get_node_or_null("Title") as Label
	_chapter_rail = GlassKit.ChapterRail.new()
	_chapter_rail.name = "ChapterRail"
	header.add_child(_chapter_rail)
	if _title_label != null:
		header.move_child(_chapter_rail, _title_label.get_index() + 1)
	# 章节刻度条就是标题下面的那道线：壳子自带的铆钉横线收起来，不然两道横线叠在一起。
	var rivet := header.get_node_or_null("Rule") as Control
	if rivet != null:
		rivet.visible = false


## 左列：竖脊 + 挂在竖脊上的六格动作（主行动 / 系统动作 / 回标题三档间距不同）。
func _build_rail(parent: Control) -> void:
	var rail := Control.new()
	rail.name = "Rail"
	# 高度跟读数区走（撑满），菜单从顶上开始排；竖脊按菜单高度画（见 open）。
	rail.custom_minimum_size = Vector2(RAIL_W, 0.0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	# 故事页紧跟在地图后面：地图回答「在哪」，故事页回答「为什么」。
	var systems := [
		[ID_SETTINGS, "设 置"],
		[ID_MAP, "地 图"],
		[ID_STORY, "故 事"],
		[ID_TUTORIAL, "教 程 回 看"],
		[ID_CONTROLS, "操 作 说 明"],
	]
	if LoadoutBridge.available():
		systems.insert(0, [ID_EQUIPMENT, "角 色 与 装 备"])
	for i in systems.size():
		_menu.add_item(StringName(systems[i][0]), String(systems[i][1]), false,
				MenuItem.Kind.SECONDARY)
		if i + 1 < systems.size():
			_gap(GAP_SECONDARY)
	_menu.add_item(ID_TITLE, "返 回 标 题", false, MenuItem.Kind.GHOST)
	_menu.chosen.connect(_on_chosen)

	# 试炼左列：重开本场 / 退出试炼（只有两格）。
	_trial_menu = MenuList.new()
	_trial_menu.name = "TrialMenu"
	_trial_menu.position = Vector2(RAIL_X, MENU_TOP)
	_trial_menu.visible = false
	rail.add_child(_trial_menu)
	_trial_menu.add_item(ID_TRIAL_RESTART, "重 开 本 场", false, MenuItem.Kind.PRIMARY)
	var trial_gap := Control.new()
	trial_gap.custom_minimum_size = Vector2(0.0, GAP_GROUP)
	trial_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_menu.add_child(trial_gap)
	_trial_menu.add_item(ID_TRIAL_EXIT, "退 出 试 炼", false, MenuItem.Kind.SECONDARY)
	_trial_menu.chosen.connect(_on_chosen)

	# 竞技场对局中：继续 / 重开对局 / 退出竞技场。战役七格菜单留着，只是先藏起来。
	_arena_menu = MenuList.new()
	_arena_menu.name = "ArenaMenu"
	_arena_menu.position = Vector2(RAIL_X, MENU_TOP)
	_arena_menu.visible = false
	rail.add_child(_arena_menu)
	_arena_menu.add_item(ID_RESUME, "继 续", false, MenuItem.Kind.PRIMARY)
	var arena_gap := Control.new()
	arena_gap.custom_minimum_size = Vector2(0.0, GAP_GROUP)
	arena_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena_menu.add_child(arena_gap)
	_arena_menu.add_item(ID_ARENA_RESTART, "重 开 对 局", false, MenuItem.Kind.SECONDARY)
	var arena_gap_b := Control.new()
	arena_gap_b.custom_minimum_size = Vector2(0.0, GAP_SECONDARY)
	arena_gap_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena_menu.add_child(arena_gap_b)
	_arena_menu.add_item(ID_ARENA_EXIT, "退 出 竞 技 场", false, MenuItem.Kind.GHOST)
	_arena_menu.chosen.connect(_on_chosen)

	# 竖脊串起六格；两端铆钉+中段菱形和标题屏是同一只铁件。
	var spine := Ornaments.spine(_menu.size.y - 16.0)
	spine.name = "Spine"
	spine.position = Vector2(0.0, MENU_TOP + 6.0)
	rail.add_child(spine)
	rail.move_child(spine, 0)
	_spine = spine


## 左列菜单比读数区高（多了「角色与装备」这一行）时把卡片撑高，最后一格就不会压到底部提示带上；
## 上限 CARD_MAX_HEIGHT，仍留得出卡片四周的暗幕。用的是菜单的最小高度（各行之和）：此时还没排版，size 是 0。
func _fit_card_to_rail() -> void:
	var card := _shell.get("card") as Control
	if card == null or _menu == null:
		return
	var need := MENU_TOP + _menu.get_combined_minimum_size().y + CHROME_H
	if need > card.custom_minimum_size.y:
		card.custom_minimum_size.y = minf(need, CARD_MAX_HEIGHT)


## 右列：玻璃读数面。三组小题头（现况 / 剑与巢 / 显示）下面是左键右值的读数行，
## 底部一行脚注。整列叫 DossierColumn：竞技场对局里整列收起（见 open / _release_arena_pause）。
func _build_dossier(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.name = "DossierColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	var plate := PanelContainer.new()
	plate.name = "Dossier"
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var glass := _glass_box(DOSSIER_BASE, GlassKit.CARD_ALPHA, DOSSIER_MARGINS)
	if glass != null:
		plate.add_theme_stylebox_override(&"panel", glass)
	column.add_child(plate)

	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 10)
	plate.add_child(inner)

	inner.add_child(_group_head("现 况"))
	_dossier_objective = _readout_row(inner, "目 标", "objective")
	inner.add_child(_hairline())
	inner.add_child(_group_head("剑 与 巢"))
	_dossier_cores = _readout_row(inner, "锈 核", "cores")
	_dossier_nests = _readout_row(inner, "余 烬 巢", "nests")
	inner.add_child(_hairline())
	inner.add_child(_group_head("显 示"))
	_dossier_viewport = _readout_row(inner, "视 口", "viewport")

	inner.add_child(GlassKit.spacer())
	inner.add_child(UiKit.label("剑核随时可在插座台换装 · 进度在余烬巢刻录",
			&"FootnoteLabel"))


## 玻璃底板：取主题里现成的板面贴图，复制一份只改着色透明度（与 GlassKit.glass 同一手法），
## 内边距按这一列的读数行收紧。
static func _glass_box(variation: StringName, alpha: float, margins: Vector4) -> StyleBox:
	var base := UiKit.extras_theme().get_stylebox(&"panel", variation) as StyleBoxTexture
	if base == null:
		return null
	var box := base.duplicate() as StyleBoxTexture
	box.modulate_color = Color(1.0, 1.0, 1.0, alpha)
	box.content_margin_left = margins.x
	box.content_margin_top = margins.y
	box.content_margin_right = margins.z
	box.content_margin_bottom = margins.w
	return box


## 读数组的小题头：12px 余烬小字 + 一根发丝线，和标题带的 kicker 同一语汇。
func _group_head(text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Head_" + text.replace(" ", "")
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(GlassKit.kicker(text))
	var stub := Ornaments.stub_rule(false)
	stub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stub)
	return row


## 组与组之间的暗锈发丝线（比小题头的线更淡，只分段）。
func _hairline() -> Control:
	var line := ColorRect.new()
	line.name = "Hairline"
	line.color = Color(UiKit.RUST_MID.r, UiKit.RUST_MID.g, UiKit.RUST_MID.b, 0.45)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## 一行读数：菱形 + 左边 12px 的键 + 右边 24px 的值（右对齐；章节名、目标句可能很长，允许换行）。
## 返回值那一格，供 _set_dossier 写字。
func _readout_row(parent: VBoxContainer, key: String, id: String) -> Label:
	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override("separation", 12)
	# 读数行给足一行 24px 的高度：一整列是账本式的疏朗，不是一堆挤在一起的小字。
	row.custom_minimum_size = Vector2(0.0, 40.0)
	parent.add_child(row)
	var bullet := Bullet.new()
	bullet.name = "Bullet"
	row.add_child(bullet)
	_bullets[id] = bullet
	var key_label := UiKit.label(key, &"TinyStrongLabel")
	key_label.custom_minimum_size = Vector2(KEY_COLUMN, 0.0)
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(key_label)
	var value := UiKit.label("—", &"BodyLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	value.name = "Value"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value)
	return value


## 档案值的语义色：目标是暖白（它是"现在要做什么"），锈核/巢穴用地图图例里"已点燃余烬巢"的同一个琥珀 ——
## 暂停档案、地图、图例三屏说的是同一枚巢，颜色不能各说各话；视口最暗（纯技术信息）。
const DOSSIER_COLORS := {
	&"objective": Color("#E4DCCC"),
	&"cores": Color("#FFC14A"),
	&"nests": Color("#FFC14A"),
	&"viewport": UiKit.ASH,
}


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
	if TrialRunScript.active():
		_set_heading(HEAD_KICKER, "回 火 试 炼", -1)
		_set_dossier(&"objective", TrialRunScript.status_line())
		_set_dossier(&"cores", _cores_summary())
		_set_dossier(&"nests", "—")
		_set_dossier(&"viewport", DisplayFit.get_resolution_string())
		return
	var heading := _chapter_heading()
	_set_heading(String(heading[0]), String(heading[1]), int(heading[2]))
	_set_dossier(&"objective", _objective_line())
	_set_dossier(&"cores", _cores_summary())
	_set_dossier(&"nests", "已刻录 %d 处" % SaveData.lit_nests.size())
	_set_dossier(&"viewport", DisplayFit.get_resolution_string())


## 标题带：小字 + 大标题 + 章节刻度条（当前章节下标，-1 = 不标）。
func _set_heading(kicker: String, title: String, current: int) -> void:
	if _kicker_label != null:
		_kicker_label.text = kicker
	if _title_label != null:
		_title_label.text = title
	if _chapter_rail != null:
		_chapter_rail.set_journey(GlassKit.done_from_flags(SaveData.flags), current)


func _set_dossier(key: StringName, text: String) -> void:
	var label := dossier_label(String(key))
	if label == null:
		return
	label.text = text
	var tint: Color = DOSSIER_COLORS.get(key, Color.WHITE)
	var empty := text == "—"
	# 空值（"—"）压暗：没有数据时不染色，避免一列彩色占位符。
	label.modulate = Color(tint.r, tint.g, tint.b, 0.45) if empty else tint
	var bullet := _bullets.get(String(key)) as Bullet
	if bullet != null:
		bullet.lit = not empty


## 标题带的两段：[小字, 章节名, 当前章节下标]。
## 章节名与地图共用 MapScreen.chapter_title() 这一份口径（"锈墓・壹 — 腐液回廊"），
## 按分隔符拆开：编号进小字，名字进大标题，两处不会写出两个名字。取不到时标题写「暂 停」。
func _chapter_heading() -> Array:
	var full := _chapter_title()
	var number := ""
	var chapter_name := full
	var cut := full.find(" — ")
	if cut > 0:
		number = full.substr(0, cut)
		chapter_name = full.substr(cut + 3)
	var id := String(_journal.current_chapter_id()) if _journal != null else ""
	var index := ChapterText.index_of(id) if id != "" else -1
	var kicker := HEAD_KICKER if number == "" else "%s · %s" % [number, HEAD_KICKER]
	var title := chapter_name if chapter_name != "" else HEAD_FALLBACK
	return [kicker, title, index]


## 当前章节名：与地图共用 MapScreen.chapter_title() 这一份口径，避免档案卡和
## 地图对同一关写出两个名字（第一章的名字只在开场分镜里写一次）。取不到时返回 ""。
func _chapter_title() -> String:
	return MapScreen.chapter_title(GameContext.world_root(self))


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


## 是否有子界面（设置 / 回看 / 说明 / 地图 / 故事）盖在菜单上。
func sub_screen_open() -> bool:
	return _controls.visible or _settings.visible or _tutorial.visible or _map.visible \
			or (_journal != null and _journal.visible) \
			or (_equipment != null and _equipment.visible)


func _resume_menu() -> void:
	if _map_from_hotkey:
		_map_from_hotkey = false
		close()
		return
	if _arena_menu != null and _arena_menu.visible:
		_arena_menu.active = true
	elif _trial_menu != null and _trial_menu.visible:
		_trial_menu.active = true
	else:
		_menu.active = true


func open() -> void:
	# 淡入淡出换关的 0.45 秒里暂停，下一关会带着 paused / suspended 加载出来。
	# 所以淡变期间只记下请求，淡变结束再开（见 _process），而不是吞掉这次 Esc。
	if visible or Director.choice_hold:
		return
	# 全屏分镜（序章 / 章间 / 结局）播放中不开菜单：它会盖住分镜，分镜自己有跳过。
	if Director.board_blocks_pause():
		_open_requested = false
		return
	# 大厅、倒计时、结算自己有按钮，这里不再叠一层暂停。
	if _arena_pause_blocked():
		_open_requested = false
		return
	if Director.is_fading():
		_open_requested = true
		return
	_open_requested = false
	_closing = false
	visible = true
	# 试炼换成两格；竞技场对局换成三格。普通暂停菜单仍是原来那一列。
	var arena_mode := _arena_match_open()
	var trial_mode := not arena_mode and TrialRunScript.active()
	_menu.visible = not trial_mode and not arena_mode
	_trial_menu.visible = trial_mode
	_arena_menu.visible = arena_mode
	_menu.active = not trial_mode and not arena_mode
	_trial_menu.active = trial_mode
	_arena_menu.active = arena_mode
	var dossier := _layout.get_node_or_null("DossierColumn") as CanvasItem
	if dossier != null:
		dossier.visible = not arena_mode
	if _spine != null:
		var active_list: MenuList = _menu
		if arena_mode:
			active_list = _arena_menu
		elif trial_mode:
			active_list = _trial_menu
		# 竖脊按 custom_minimum_size 来画，只改 size 不会变高。
		var spine_h := maxf(24.0, active_list.size.y - 16.0)
		_spine.custom_minimum_size = Vector2(_spine.custom_minimum_size.x, spine_h)
		_spine.size = Vector2(_spine.custom_minimum_size.x, spine_h)
		_spine.queue_redraw()
	_set_play_hud_visible(false)
	_refresh_dossier()
	(_shell.get("play_intro") as Callable).call()
	get_tree().paused = true
	Director.suspend()
	UiKit.sfx(&"ui_pause", &"ui_select")


## 淡变期间按下、还没兑现的暂停请求。
func open_pending() -> bool:
	if Director.choice_hold:
		_open_requested = false
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
	_map_from_hotkey = false
	_open_requested = false
	if not visible or _closing:
		return
	_closing = true
	# 子界面直接收起，不走退场动画：暂停菜单自己正要整层退场，
	# 再让每张卡片各播一遍只会把收尾拖成三秒。想让子界面单独播退场，
	# 走它们自己的 close()。
	_controls.visible = false
	_tutorial.visible = false
	_map.visible = false
	if _journal != null:
		# 故事页回放到一半被关：先把分镜播放器收掉，再恢复本层卡片（见 replay_finished）。
		_journal.dismiss()
	if _settings.visible:
		_settings.close()
	if _equipment != null and _equipment.visible:
		if _equipment.has_method("close"):
			_equipment.close()
		elif _equipment.has_method("close_panel"):
			_equipment.close_panel()
		else:
			_equipment.visible = false
	Sfx.play(&"ui_back")
	# 暂停菜单自己走退场动画：卡片沉回去、纱幕收掉，然后才解除暂停、
	# HUD 才回来。退场期间再按 Esc 由 _closing 挡掉（不会起第二条 tween）。
	var on_finish := func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		_set_play_hud_visible(true)
		if Director.choice_hold:
			return
		get_tree().paused = false
		Director.resume()

	if _shell.has("play_outro") and _shell.get("play_outro") is Callable:
		(_shell.get("play_outro") as Callable).call(on_finish)
	else:
		on_finish.call()


func _set_play_hud_visible(show: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var chrome := parent.get_node_or_null("Root") as CanvasItem
	if chrome != null:
		chrome.visible = show


func _unhandled_input(event: InputEvent) -> void:
	# 故事页在回放分镜：Enter / Esc 归播放器（它在树里排在暂停菜单前面，会晚一步收到），
	# 这里不能抢先把 Esc 当成「继续游戏」。
	if _journal != null and _journal.replaying():
		return
	if event.is_action_pressed("map") and not event.is_echo():
		if ArenaRun.active():
			get_viewport().set_input_as_handled()
			return
		if not visible and GameContext.gameplay_input_enabled() and not Director.is_fading():
			open()
			if visible:
				_map_from_hotkey = true
				_menu.active = false
				_trial_menu.active = false
				if _arena_menu != null:
					_arena_menu.active = false
				_map.open()
		elif visible and not sub_screen_open():
			_on_chosen(ID_MAP)
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	# 大厅 / 倒计时 / 结算自己处理 Esc，这里不打开暂停，也不把键吃掉。
	if not visible and _arena_pause_blocked():
		return
	if Director.choice_hold and not visible:
		return
	# 分镜在演：Esc 不碰暂停菜单。故事页回放里 Esc = 跳过整段，由播放器自己接（不吃掉这个键）。
	if Director.board_active():
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
		ID_EQUIPMENT:
			_menu.active = false
			if _equipment != null:
				if _equipment.has_method("open_panel"):
					_equipment.open_panel(true)
				elif _equipment.has_method("open"):
					_equipment.open()
				else:
					_equipment.visible = true
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
		ID_STORY:
			_menu.active = false
			_journal.open()
		ID_TITLE:
			get_tree().paused = false
			Director.resume()
			Director.fade_to(TITLE_PATH)
		ID_TRIAL_RESTART:
			# 重开本场：先恢复暂停/收起菜单，再让 TrialRun 重载当前场（不计死亡）。
			close()
			TrialRunScript.retry_stage()
		ID_TRIAL_EXIT:
			# 退出试炼：回标题，不写战役档（TrialRun.abandon + 换场）。
			close()
			TrialRunScript.exit_to_title()
		ID_ARENA_RESTART:
			_release_arena_pause(true)
		ID_ARENA_EXIT:
			_release_arena_pause(false)


func _arena_match_open() -> bool:
	return ArenaRun.active() and ArenaRun.phase() == ArenaCatalog.PHASE_PLAYING


func _arena_pause_blocked() -> bool:
	return ArenaRun.active() and not _arena_match_open()


## 先解开暂停再重开或回标题，避免 ArenaRun 的计时停在 paused 里。
func _release_arena_pause(restart: bool) -> void:
	_open_requested = false
	_closing = false
	visible = false
	_menu.visible = true
	_menu.active = true
	if _arena_menu != null:
		_arena_menu.visible = false
		_arena_menu.active = false
	if _trial_menu != null:
		_trial_menu.visible = false
		_trial_menu.active = false
	if _layout != null:
		var dossier := _layout.get_node_or_null("DossierColumn") as CanvasItem
		if dossier != null:
			dossier.visible = true
	_set_play_hud_visible(true)
	Sfx.play(&"ui_back")
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	Director.resume()
	if restart:
		ArenaRun.restart_match()
	else:
		ArenaRun.exit_to_title()


## 故事页开始回放分镜：本层卡片藏起来，让分镜播放器（回放层 24）露出来。
func _on_story_replay_started(_board_id: String) -> void:
	if _root != null:
		_root.visible = false


## 回放结束 / 被跳过 / 被打断：卡片回来（故事页自己会恢复到「重 看」页）。
func _on_story_replay_finished(_board_id: String) -> void:
	if _root != null:
		_root.visible = true


# --- 测试用 -------------------------------------------------------------------

func menu() -> MenuList:
	return _menu


func arena_menu() -> MenuList:
	return _arena_menu


func settings_screen() -> SettingsScreen:
	return _settings


func tutorial_recall() -> TutorialRecall:
	return _tutorial


func map_screen() -> MapScreen:
	return _map


## 故事页（journal_screen.gd，没有 class_name，所以返回 CanvasLayer）。
func journal_screen() -> CanvasLayer:
	return _journal


func controls_panel() -> ControlsPanel:
	return _controls


func equipment_panel() -> CanvasLayer:
	return _equipment


## 标题带的大标题（"chapter"）与读数行的值格（"objective" / "cores" / "nests" / "viewport"）。
func dossier_label(key: String) -> Label:
	match key:
		"chapter":
			return _title_label
		"objective":
			return _dossier_objective
		"cores":
			return _dossier_cores
		"nests":
			return _dossier_nests
		"viewport":
			return _dossier_viewport
	return null
