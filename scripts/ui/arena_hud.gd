extends CanvasLayer
## 3v3 正式界面：赛前大厅、倒计时、局内 HUD、结算、基地炉台。
## 层 10 是局内条，子层 ArenaOverlay（15）是大厅 / 结算 / 炉台。
## 挂上后 ArenaRun.set_ui_attached(true)，右上角临时文字条不再显示。
## 没有 class_name。场景退出时断开 Autoload 信号，并藏掉所有遮罩。
##
## 视觉与回看余烬是同一套玻璃语汇（GlassKit）：局内的记分、塔况、英雄状态是半透明切角卡，击杀播报是右侧的暗玻璃小条，
## 小题头用 12px 的 kicker，数字用 24px；大厅是玻璃左列，炉台是玻璃弹窗，结算是按结果着色的判章。
## 竞技场没有波次读数，这里不凭空加一个。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const LaneMap := preload("res://scripts/ui/arena_minimap.gd")
const Modal := preload("res://scripts/ui/ui_modal.gd")

const FLY_POINTS: Array[Vector2] = [
	Vector2(320, 180),
	Vector2(3520, 180),
	Vector2(480, 180),
]
const FLY_STEP := 2.6
const CALL_HOLD := 0.75
const FEED_LIFE := 5.0
const FEED_CAP := 5
const LOCKED_BAR := Color(0.42, 0.42, 0.46, 1.0)
const STRUCTURE_TINT := Color(0.95, 0.78, 0.42, 1.0)
## 结算判章的颜色与结局印记同口径：胜 = 还火金，平 = 守炉橙，负 = 熄火灰紫。
const WIN_TINT := Color("#FFC14A")
const DRAW_TINT := Color("#D9743A")
const LOSS_TINT := Color("#8C8290")
const RED_RUST := Color("#CD5C5C")

const ID_START := &"start"
const ID_BACK := &"back"
const ID_DIFFICULTY := &"difficulty"
const ID_REMATCH := &"rematch"
const ID_TITLE := &"title"
const ID_CLOSE := &"close"

var _root: Control
var _overlay: CanvasLayer
var _lobby: Control
var _lobby_menu: MenuList
var _roster_label: Label
var _rules_label: Label
var _records_label: Label
var _countdown: Control
var _countdown_label: Label
var _countdown_halo: Control
var _match: Control
var _score_label: RichTextLabel
var _map: Control
var _feed_head: Label
var _feed_boxes: Dictionary = {}
var _feed_labels: Array[RichTextLabel] = []
var _feed: Array = []
var _blue_names: Array[Label] = []
var _blue_fills: Array[ColorRect] = []
var _blue_locks: Array[Label] = []
var _red_names: Array[Label] = []
var _red_fills: Array[ColorRect] = []
var _red_locks: Array[Label] = []
var _level_label: Label
var _xp_fill: ColorRect
var _ember_label: Label
var _bless_label: Label
var _near_label: Label
var _respawn_plate: Control
var _respawn_label: Label
var _bless_plate: Control
var _bless_banner: Label
var _shop: Control
var _shop_menu: MenuList
var _shop_ember: Label
var _shop_status: Label
var _result_root: Control
var _result_menu: MenuList
var _result_meta: Label
var _result_score: Label
var _result_player: Label
var _result_mvp: Label
var _result_record: Label
var _result_title: Label
var _result_seal: VerdictSeal

var _flying := false
var _fly_index := 0
var _fly_time := 0.0
var _was_countdown := false
var _call_left := 0.0
var _bless_left := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_INHERIT
	_build()
	PresentationMetrics.bind_layer(self)
	PresentationMetrics.bind_layer(_overlay)
	WorldClock.isolate_ui_layer(self)
	WorldClock.isolate_ui_layer(_overlay)
	_connect_run()
	ArenaRun.set_ui_attached(true, self)
	_apply_phase(ArenaRun.phase())


func _exit_tree() -> void:
	_disconnect_run()
	_flying = false
	_call_left = 0.0
	_bless_left = 0.0
	_hide_masks()
	ArenaRun.set_ui_attached(false, self)


func _process(delta: float) -> void:
	_advance(delta)


## 测试和 _process 共用。把镜头、播报淡出、倒计时「开战」往前推 delta 秒。
func _advance(delta: float) -> void:
	if _flying and ArenaRun.phase() == ArenaCatalog.PHASE_LOBBY:
		_fly_time += delta
		if _fly_time >= FLY_STEP:
			_fly_time = 0.0
			_fly_index += 1
			if _fly_index >= FLY_POINTS.size():
				_end_fly(true)
			else:
				_aim_camera(FLY_POINTS[_fly_index])
	if _call_left > 0.0:
		_call_left = maxf(0.0, _call_left - delta)
	if _bless_left > 0.0:
		_bless_left = maxf(0.0, _bless_left - delta)
	if _bless_banner != null:
		_bless_banner.visible = _bless_left > 0.0 and _match != null and _match.visible
		_sync_banner()
	_decay_feed(delta)
	_sync_countdown()
	_refresh_match()


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	var phase := ArenaRun.phase()
	if phase == ArenaCatalog.PHASE_LOBBY:
		if _flying and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel")):
			_end_fly(true)
			_mark_handled()
			return
		if event.is_action_pressed(&"ui_left"):
			_cycle_difficulty(-1)
			_mark_handled()
			return
		if event.is_action_pressed(&"ui_right"):
			_cycle_difficulty(1)
			_mark_handled()
			return
		if not _flying and event.is_action_pressed(&"ui_cancel"):
			_focus_id(_lobby_menu, ID_BACK)
			_mark_handled()
		return
	if phase == ArenaCatalog.PHASE_RESULT:
		if event.is_action_pressed(&"ui_cancel"):
			_focus_id(_result_menu, ID_TITLE)
			_mark_handled()
		return
	if phase != ArenaCatalog.PHASE_PLAYING:
		return
	if _shop.visible and event.is_action_pressed(&"ui_cancel"):
		_close_shop()
		_mark_handled()
		return
	if event.is_action_pressed(&"interact"):
		if _shop.visible:
			_close_shop()
			_mark_handled()
		elif _near_fountain():
			_open_shop()
			_mark_handled()


# ------------------------------------------------------------------- build --

func _build() -> void:
	_root = Control.new()
	_root.name = "MatchChrome"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.extras_theme()
	add_child(_root)

	_overlay = CanvasLayer.new()
	_overlay.name = "ArenaOverlay"
	_overlay.layer = 15
	add_child(_overlay)

	_build_lobby()
	_build_countdown()
	_build_match()
	_build_shop()
	_build_result()
	if _countdown != null and _countdown.get_parent() == _root:
		_root.move_child(_countdown, _root.get_child_count() - 1)


## 赛前：左列玻璃卡（花边外壳 + 半透明），飞镜头时后面的场馆还看得见。
## 名册 / 规则 / 战绩各有一行 kicker；菜单用铁条版式，与回看余烬的行程入口同一套。
func _build_lobby() -> void:
	_lobby = Control.new()
	_lobby.name = "Lobby"
	_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby.clip_contents = true
	_lobby.visible = false
	_overlay.add_child(_lobby)

	var card := UiKit.panel(&"OrnatePanel")
	card.name = "LobbyCard"
	card.anchor_left = 0.0
	card.anchor_top = 0.0
	card.anchor_right = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = 16.0
	card.offset_top = 12.0
	card.offset_right = 532.0
	card.offset_bottom = -12.0
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	GlassKit.glass(card)
	_lobby.add_child(card)

	var column := VBoxContainer.new()
	column.name = "LobbyColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	column.add_child(GlassKit.kicker("竞 技 场", HORIZONTAL_ALIGNMENT_CENTER))
	var title := UiKit.label("赛 前", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "LobbyTitle"
	column.add_child(title)
	column.add_child(UiKit.label("灰卫  对  锈誓", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(GlassKit.rule())

	var scroll := ScrollContainer.new()
	scroll.name = "LobbyScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.custom_minimum_size = Vector2(420, 0)
	scroll.add_child(body)

	body.add_child(GlassKit.kicker("名 册"))
	_roster_label = UiKit.label("", &"BodyLabel")
	_roster_label.name = "Roster"
	_roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_roster_label.custom_minimum_size = Vector2(420, 0)
	body.add_child(_roster_label)
	body.add_child(GlassKit.kicker("规 则"))
	_rules_label = UiKit.label("", &"FootnoteLabel")
	_rules_label.name = "Rules"
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_rules_label)
	body.add_child(GlassKit.kicker("战 绩"))
	_records_label = UiKit.label("", &"BodyLabel")
	_records_label.name = "Records"
	_records_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_records_label)

	column.add_child(GlassKit.rule())
	_lobby_menu = MenuList.new()
	_lobby_menu.name = "LobbyMenu"
	_lobby_menu.strip_style = true
	_lobby_menu.add_theme_constant_override("separation", 6)
	column.add_child(_lobby_menu)
	_lobby_menu.add_item(ID_DIFFICULTY, _difficulty_line(), false, MenuItem.Kind.SECONDARY, true)
	_lobby_menu.add_item(ID_START, "开 战", false, MenuItem.Kind.PRIMARY, true)
	_lobby_menu.add_item(ID_BACK, "返 回 标 题", false, MenuItem.Kind.GHOST, true)
	_lobby_menu.select(1, false)
	_lobby_menu.chosen.connect(_on_lobby_chosen)
	var hint := UiKit.label("← → 切换难度 · Enter 确认 · Esc 跳过镜头", &"FootnoteLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	hint.name = "LobbyHint"
	column.add_child(hint)


func _build_countdown() -> void:
	_countdown = Control.new()
	_countdown.name = "Countdown"
	_countdown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.visible = false
	_root.add_child(_countdown)
	# 数字背后压一枚菱形光环，倒计时像一枚印在台面上的章。
	_countdown_halo = Halo.new()
	_countdown_halo.name = "CountdownHalo"
	_countdown_halo.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_halo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_halo.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown.add_child(_countdown_halo)
	_countdown_label = UiKit.label("3", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_countdown_label.name = "CountdownText"
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown_label.custom_minimum_size = Vector2(280, 120)
	_countdown_label.add_theme_font_size_override("font_size", 96)
	_countdown.add_child(_countdown_label)


## 局内：顶部记分条、两侧塔况卡、右上小地图、右侧击杀播报、左下英雄状态卡、中央复活与祝福。
func _build_match() -> void:
	_match = Control.new()
	_match.name = "PlayChrome"
	_match.set_anchors_preset(Control.PRESET_FULL_RECT)
	_match.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match.visible = false
	_root.add_child(_match)

	# 记分：顶部中央的玻璃条。「时 限」小题头压在时间上方，比分行用 24px。
	var score_plate := Chamfer.new()
	score_plate.name = "ScorePlate"
	score_plate.anchor_left = 0.5
	score_plate.anchor_right = 0.5
	score_plate.offset_left = -250.0
	score_plate.offset_right = 250.0
	score_plate.offset_top = 8.0
	score_plate.custom_minimum_size = Vector2(500.0, 0.0)
	# 左上角是战役的心条（到 x≈378），记分条要让开它：宽 500，左缘落在 390。
	score_plate.set_pad(10.0, 10.0, 10.0, 8.0)
	score_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match.add_child(score_plate)
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 0)
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_plate.add_child(score_box)
	score_box.add_child(GlassKit.kicker("时 限", HORIZONTAL_ALIGNMENT_CENTER))
	_score_label = _bbcode_line(HORIZONTAL_ALIGNMENT_CENTER, 24)
	_score_label.name = "ScoreText"
	_score_label.fit_content = false
	_score_label.custom_minimum_size = Vector2(0.0, 28.0)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_box.add_child(_score_label)

	_build_tower_column("BlueTowers", Vector2(16.0, 64.0), true)
	_build_tower_column("RedTowers", Vector2(1052.0, 64.0), false)

	_map = LaneMap.new() as Control
	_map.name = "Minimap"
	_map.position = Vector2(1052.0, 176.0)
	_map.size = Vector2(212.0, 80.0)
	_map.custom_minimum_size = Vector2(212.0, 80.0)
	_match.add_child(_map)

	# 击杀播报：右侧一列暗玻璃小条，每条右缘一根灯口（击杀余烬色，拆塔锈红）。
	_feed_boxes = {
		"kill": _feed_box(GlassKit.EMBER),
		"tower": _feed_box(RED_RUST),
	}
	var feed := VBoxContainer.new()
	feed.name = "KillFeed"
	feed.position = Vector2(1040.0, 272.0)
	feed.custom_minimum_size = Vector2(224.0, 120.0)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_theme_constant_override("separation", 3)
	_match.add_child(feed)
	_feed_head = GlassKit.kicker("击 杀 播 报", HORIZONTAL_ALIGNMENT_RIGHT)
	_feed_head.name = "FeedKicker"
	_feed_head.visible = false
	feed.add_child(_feed_head)
	for i in FEED_CAP:
		var line := _bbcode_line(HORIZONTAL_ALIGNMENT_RIGHT, 12)
		line.name = "Feed%d" % i
		line.visible = false
		line.custom_minimum_size = Vector2(224.0, 20.0)
		line.add_theme_stylebox_override(&"normal", _feed_boxes["kill"])
		feed.add_child(line)
		_feed_labels.append(line)

	_build_status()

	# 复活倒计时：屏幕中央一块小切角牌，红色轮廓。
	var respawn_plate := Chamfer.new()
	respawn_plate.name = "RespawnPlate"
	respawn_plate.accent = RED_RUST
	# 最小宽度定死：秒数从一位变两位时牌子不跟着抖。
	respawn_plate.custom_minimum_size = Vector2(340.0, 0.0)
	_respawn_plate = respawn_plate
	_respawn_plate.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_respawn_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	_respawn_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_respawn_plate.visible = false
	_match.add_child(_respawn_plate)
	_respawn_label = UiKit.label("", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_respawn_label.name = "RespawnText"
	_respawn_label.visible = false
	_respawn_plate.add_child(_respawn_label)

	# 炉火祝福公告：顶部中央，score 条下方。
	_bless_plate = Chamfer.new()
	_bless_plate.name = "BlessingPlate"
	_bless_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bless_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bless_plate.offset_top = 88.0
	_bless_plate.custom_minimum_size = Vector2(300.0, 40.0)
	_bless_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bless_plate.visible = false
	_match.add_child(_bless_plate)
	_bless_banner = UiKit.label("", &"AnnounceLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_bless_banner.name = "BlessingBanner"
	_bless_banner.visible = false
	_bless_plate.add_child(_bless_banner)


## 塔况卡：一张切角卡，顶上一行队色 kicker，三行外塔 / 内塔 / 水晶，每行一条 4 格刻度的血条。
func _build_tower_column(node_name: String, at: Vector2, blue: bool) -> void:
	var card := Chamfer.new()
	card.name = node_name
	card.position = at
	card.accent = _accent_for(blue)
	card.custom_minimum_size = Vector2(212.0, 0.0)
	card.set_pad(12.0, 10.0, 12.0, 8.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	column.add_child(_team_kicker("灰 卫" if blue else "锈 誓", card.accent))
	var prefix := "Blue" if blue else "Red"
	for index in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(row)
		var name_label := UiKit.label("外塔", &"TinyStrongLabel")
		name_label.name = "%sName%d" % [prefix, index]
		name_label.custom_minimum_size = Vector2(40.0, 16.0)
		row.add_child(name_label)
		var track := ColorRect.new()
		track.custom_minimum_size = Vector2(112.0, 8.0)
		track.color = Color(0.03, 0.025, 0.04, 0.9)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(track)
		var fill := ColorRect.new()
		fill.name = "%sFill%d" % [prefix, index]
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.anchor_right = 1.0
		track.add_child(fill)
		track.add_child(_ticks(4))
		var lock_label := UiKit.label("", &"TinyStrongLabel")
		lock_label.name = "%sLock%d" % [prefix, index]
		lock_label.custom_minimum_size = Vector2(22.0, 16.0)
		lock_label.visible = false
		row.add_child(lock_label)
		if blue:
			_blue_names.append(name_label)
			_blue_fills.append(fill)
			_blue_locks.append(lock_label)
		else:
			_red_names.append(name_label)
			_red_fills.append(fill)
			_red_locks.append(lock_label)


## 英雄状态卡（左下）：kicker「余烬骑士」，等级与经验、分段余烬经验条，余烬 / 炉火，近泉水时的交互提示。
func _build_status() -> void:
	var status := Chamfer.new()
	status.name = "PlayerStatus"
	status.position = Vector2(16.0, 576.0)
	status.accent = GlassKit.EMBER
	status.custom_minimum_size = Vector2(300.0, 0.0)
	status.set_pad(12.0, 10.0, 12.0, 8.0)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match.add_child(status)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(status_box)
	status_box.add_child(GlassKit.kicker("余 烬 骑 士"))
	_level_label = UiKit.label("等级 1", &"BodyLabel")
	_level_label.name = "LevelText"
	status_box.add_child(_level_label)
	var xp_track := ColorRect.new()
	xp_track.custom_minimum_size = Vector2(276.0, 10.0)
	xp_track.color = Color(0.03, 0.025, 0.04, 0.9)
	xp_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.add_child(xp_track)
	_xp_fill = ColorRect.new()
	_xp_fill.name = "XpFill"
	_xp_fill.color = Color(1.0, 0.76, 0.29, 0.95)
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_fill.anchor_right = 0.0
	xp_track.add_child(_xp_fill)
	xp_track.add_child(_ticks(10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.add_child(row)
	_ember_label = UiKit.label("余烬 0", &"BodyLabel")
	_ember_label.name = "EmberText"
	_ember_label.modulate = UiKit.EMBER
	_ember_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ember_label)
	_bless_label = UiKit.label("炉火 —", &"BodyLabel")
	_bless_label.name = "BlessText"
	_bless_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bless_label)
	_near_label = UiKit.label("", &"FootnoteLabel")
	_near_label.name = "NearText"
	_near_label.modulate = UiKit.EMBER
	_near_label.custom_minimum_size = Vector2(0.0, 16.0)
	status_box.add_child(_near_label)


func _build_shop() -> void:
	_shop = Control.new()
	_shop.name = "Shop"
	_shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop.visible = false
	_overlay.add_child(_shop)
	# 炉台是玻璃弹窗：花边外壳 + 半透明，战场透出来。
	var card := UiKit.panel(&"OrnatePanel")
	card.name = "ShopCard"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(460, 320)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	GlassKit.glass(card)
	_shop.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	column.add_child(GlassKit.kicker("己 方 泉 水", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.label("炉 台", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_shop_ember = UiKit.label("余烬 0", &"BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_shop_ember.name = "ShopEmber"
	_shop_ember.modulate = UiKit.EMBER
	column.add_child(_shop_ember)
	column.add_child(GlassKit.rule())
	_shop_menu = MenuList.new()
	_shop_menu.name = "ShopMenu"
	# 购买行用次行动燕尾板（文字区 320px，单空格排版下「锋刃 18 余烬 攻击+1」居中有余）；铁条只在左列用。
	_shop_menu.add_theme_constant_override("separation", 4)
	column.add_child(_shop_menu)
	for raw in ArenaRun.shop_items():
		if raw is not Dictionary:
			continue
		var item: Dictionary = raw
		var item_id := String(item.get("id", ""))
		if item_id == "":
			continue
		_shop_menu.add_item(StringName(item_id), _shop_line(item), false, MenuItem.Kind.SECONDARY)
	_shop_menu.add_item(ID_CLOSE, "关 闭", false, MenuItem.Kind.GHOST)
	_shop_menu.chosen.connect(_on_shop_chosen)
	_shop_menu.active = false
	_shop_status = UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_shop_status.name = "ShopStatus"
	column.add_child(_shop_status)
	column.add_child(UiKit.label("Esc 或交互键关闭", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER))


## 结算：Modal 玻璃弹窗。标题（胜 / 负 / 平）下面是一枚判章，然后是「战况」「个人」两张切角卡，最后是新纪录与菜单。
func _build_result() -> void:
	var shell: Dictionary = Modal.build(_overlay, {
		"title": "对 局 结 算",
		"kicker": "灰卫 对 锈誓",
		"size": Vector2(800, 640),
		"hint": "Enter 确认",
		"back": "Esc 选中返回标题",
		"veil": 0.62,
	})
	_result_root = shell["root"] as Control
	_result_root.name = "ResultRoot"
	_result_root.visible = false
	_result_title = _result_root.find_child("Title", true, false) as Label
	if _result_title != null:
		_result_title.add_theme_font_size_override("font_size", 48)
	var body: Control = shell["body"] as Control
	var column := VBoxContainer.new()
	column.name = "ResultBody"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	body.add_child(column)

	_result_seal = VerdictSeal.new()
	_result_seal.name = "ResultSeal"
	column.add_child(_result_seal)
	_result_meta = UiKit.label("", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_result_meta.name = "ResultMeta"
	column.add_child(_result_meta)

	var cards := HBoxContainer.new()
	cards.name = "ResultCards"
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 16)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(cards)
	var war := _section_card("WarCard", "战 况", cards, 332.0)
	_result_score = UiKit.label("", &"BodyLabel")
	_result_score.name = "ResultScore"
	war.add_child(_result_score)
	var mine := _section_card("PlayerCard", "个 人", cards, 332.0)
	_result_player = UiKit.label("", &"BodyLabel")
	_result_player.name = "ResultPlayer"
	_result_player.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mine.add_child(_result_player)
	_result_mvp = UiKit.label("", &"AnnounceLabel")
	_result_mvp.name = "ResultMvp"
	mine.add_child(_result_mvp)

	_result_record = UiKit.label("新纪录", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_result_record.name = "NewRecord"
	_result_record.visible = false
	column.add_child(_result_record)
	_result_menu = MenuList.new()
	_result_menu.name = "ResultMenu"
	_result_menu.add_theme_constant_override("separation", 6)
	column.add_child(_result_menu)
	_result_menu.add_item(ID_REMATCH, "再 来 一 局", false, MenuItem.Kind.PRIMARY)
	_result_menu.add_item(ID_TITLE, "返 回 标 题", false, MenuItem.Kind.GHOST)
	_result_menu.chosen.connect(_on_result_chosen)
	_result_menu.active = false


# ------------------------------------------------------------------ signals --

func _connect_run() -> void:
	_link(ArenaRun.phase_changed, _on_phase)
	_link(ArenaRun.kill_feed, _on_kill)
	_link(ArenaRun.tower_destroyed, _on_tower)
	_link(ArenaRun.match_finished, _on_finished)
	_link(ArenaRun.match_restarted, _on_restarted)
	_link(ArenaRun.blessing_granted, _on_blessing)


func _disconnect_run() -> void:
	_unlink(ArenaRun.phase_changed, _on_phase)
	_unlink(ArenaRun.kill_feed, _on_kill)
	_unlink(ArenaRun.tower_destroyed, _on_tower)
	_unlink(ArenaRun.match_finished, _on_finished)
	_unlink(ArenaRun.match_restarted, _on_restarted)
	_unlink(ArenaRun.blessing_granted, _on_blessing)


func _link(sig: Signal, target: Callable) -> void:
	if not sig.is_connected(target):
		sig.connect(target)


func _unlink(sig: Signal, target: Callable) -> void:
	if sig.is_connected(target):
		sig.disconnect(target)


func _on_phase(phase: String) -> void:
	_apply_phase(phase)


func _on_finished(_result: Dictionary) -> void:
	if ArenaRun.phase() == ArenaCatalog.PHASE_RESULT:
		_fill_result()


func _on_restarted() -> void:
	_feed.clear()
	_redraw_feed()
	_bless_left = 0.0
	if _bless_banner != null:
		_bless_banner.visible = false
	_sync_banner()
	_close_shop()


func _on_kill(entry: Dictionary) -> void:
	var killer := String(entry.get("killer_label", ""))
	var victim := String(entry.get("victim_label", ""))
	if killer == "":
		killer = "—"
	if victim == "":
		victim = "—"
	var killer_hex := _hex(_team_color(String(entry.get("killer_team", ""))))
	var victim_hex := _hex(_team_color(String(entry.get("victim_team", ""))))
	var line := "[color=#%s]%s[/color]  击败  [color=#%s]%s[/color]" % [
		killer_hex, killer, victim_hex, victim]
	_push_feed(line, "kill")


func _on_tower(team: String, index: int) -> void:
	var side := "灰卫" if team == ArenaCatalog.TEAM_PLAYER else "锈誓"
	var what := ArenaCatalog.structure_label(index)
	var line := "[color=#%s]◆ %s%s 被摧毁[/color]" % [_hex(STRUCTURE_TINT), side, what]
	_push_feed(line, "tower")


func _on_blessing(team: String) -> void:
	if team == ArenaCatalog.TEAM_PLAYER:
		_bless_banner.text = "炉火祝福"
	else:
		_bless_banner.text = "锈誓获得炉火祝福"
	_bless_left = 2.6
	_bless_banner.visible = _match.visible
	_sync_banner()


func _on_lobby_chosen(id: StringName) -> void:
	if id == ID_DIFFICULTY:
		_cycle_difficulty(1)
	elif id == ID_START:
		_end_fly(false)
		ArenaRun.begin_match()
	elif id == ID_BACK:
		_end_fly(false)
		ArenaRun.exit_to_title()


func _on_result_chosen(id: StringName) -> void:
	if id == ID_REMATCH:
		ArenaRun.restart_match()
	elif id == ID_TITLE:
		ArenaRun.exit_to_title()


func _on_shop_chosen(id: StringName) -> void:
	if id == ID_CLOSE:
		_close_shop()
		return
	var bought := ArenaRun.buy(String(id))
	var ember := int(bought.get("ember", ArenaRun.player_ember()))
	_shop_ember.text = "余烬 %d" % ember
	if bool(bought.get("ok", false)):
		_shop_status.text = "已强化 · 余烬 %d" % ember
		return
	_shop_status.text = _shop_reason(String(bought.get("reason", "")), ember)


# --------------------------------------------------------------------- phase --

func _apply_phase(phase: String) -> void:
	var lobby := phase == ArenaCatalog.PHASE_LOBBY
	var countdown := phase == ArenaCatalog.PHASE_COUNTDOWN
	var playing := phase == ArenaCatalog.PHASE_PLAYING
	var result := phase == ArenaCatalog.PHASE_RESULT
	_lobby.visible = lobby
	_match.visible = playing
	_result_root.visible = result
	if countdown:
		_call_left = 0.0
		_countdown.visible = true
		_countdown_label.text = _countdown_digit()
	elif playing and _was_countdown:
		_call_left = CALL_HOLD
		_countdown.visible = true
		_countdown_label.text = "开战"
	elif not playing:
		_call_left = 0.0
		_countdown.visible = false
	_was_countdown = countdown
	if lobby:
		if not _flying:
			_begin_fly()
		_refresh_lobby()
	else:
		_end_fly(false)
	if playing:
		_release_camera()
	else:
		_close_shop()
	_result_menu.active = result
	_lobby_menu.active = lobby and not _flying
	if result:
		_fill_result()
		_focus_id(_result_menu, ID_REMATCH)
	if not playing:
		_show_respawn(false)
	_refresh_match()


func _hide_masks() -> void:
	if _lobby != null:
		_lobby.visible = false
	if _countdown != null:
		_countdown.visible = false
	if _match != null:
		_match.visible = false
	if _shop != null:
		_shop.visible = false
	if _result_root != null:
		_result_root.visible = false
	if _lobby_menu != null:
		_lobby_menu.active = false
	if _result_menu != null:
		_result_menu.active = false
	if _shop_menu != null:
		_shop_menu.active = false


func _sync_countdown() -> void:
	if ArenaRun.phase() == ArenaCatalog.PHASE_COUNTDOWN:
		_countdown.visible = true
		_countdown_label.text = _countdown_digit()
		return
	if _call_left > 0.0 and ArenaRun.phase() == ArenaCatalog.PHASE_PLAYING:
		_countdown.visible = true
		_countdown_label.text = "开战"
		return
	if ArenaRun.phase() != ArenaCatalog.PHASE_COUNTDOWN:
		_countdown.visible = false


func _countdown_digit() -> String:
	var n := int(ceil(ArenaRun.countdown_left()))
	if n >= 3:
		return "3"
	if n == 2:
		return "2"
	return "1"


# --------------------------------------------------------------------- lobby --

func _refresh_lobby() -> void:
	_roster_label.text = _roster_text()
	_rules_label.text = "摧毁敌方水晶。\n外塔倒下后才能打内塔，两座塔都倒水晶才露出。\n12 分钟到点，先比拆塔数，再比击杀数。"
	_records_label.text = _records_text()
	_sync_difficulty_item()


## 名册压成两行：每队一行，队名在前，队员用「·」接起来。队员的「灰卫·」「锈誓·」前缀已由队名交代，只留名字。
func _roster_text() -> String:
	var blue := PackedStringArray(["你 · 余烬骑士"])
	var red := PackedStringArray()
	for raw in ArenaCatalog.HERO_ROSTER:
		if raw is not Dictionary:
			continue
		var hero: Dictionary = raw
		var team := String(hero.get("team", ""))
		var label := String(hero.get("label", ""))
		var short := label.get_slice("·", label.get_slice_count("·") - 1)
		if team == ArenaCatalog.TEAM_PLAYER:
			blue.append(short)
		elif team == ArenaCatalog.TEAM_ENEMY:
			red.append(short)
	return "灰卫   %s\n锈誓   %s" % [" · ".join(blue), " · ".join(red)]


func _records_text() -> String:
	var rec := ArenaRun.read_records()
	var fastest := float(rec.get("fastest_win", 0.0))
	var fast_text := "—"
	if fastest > 0.05:
		fast_text = ArenaCatalog.format_time(fastest)
	return "胜 %d    负 %d    平 %d    场次 %d\n最多击杀 %d    最快胜利 %s" % [
		int(rec.get("wins", 0)),
		int(rec.get("losses", 0)),
		int(rec.get("draws", 0)),
		int(rec.get("runs", 0)),
		int(rec.get("best_kills", 0)),
		fast_text,
	]


func _difficulty_line() -> String:
	return "难 度    ←  %s  →" % ArenaCatalog.difficulty_label(ArenaRun.difficulty_id())


func _sync_difficulty_item() -> void:
	if _lobby_menu == null:
		return
	var line := _difficulty_line()
	for child in _lobby_menu.items():
		if child is MenuItem and (child as MenuItem).id == ID_DIFFICULTY:
			(child as MenuItem).set_text(line)


func _cycle_difficulty(step: int) -> void:
	if ArenaRun.phase() != ArenaCatalog.PHASE_LOBBY and ArenaRun.phase() != ArenaCatalog.PHASE_IDLE:
		return
	var order := ArenaCatalog.DIFFICULTY_ORDER
	var n := order.size()
	if n <= 0:
		return
	var idx := order.find(ArenaRun.difficulty_id())
	if idx < 0:
		idx = 0
	var next_i := (idx + step) % n
	if next_i < 0:
		next_i += n
	ArenaRun.set_difficulty(order[next_i])
	_sync_difficulty_item()


func _begin_fly() -> void:
	_flying = true
	_fly_index = 0
	_fly_time = 0.0
	if _lobby_menu != null:
		_lobby_menu.active = false
	_aim_camera(FLY_POINTS[0])


func _end_fly(enable_menu: bool) -> void:
	var was := _flying
	_flying = false
	if was:
		_release_camera()
	if enable_menu and _lobby_menu != null and ArenaRun.phase() == ArenaCatalog.PHASE_LOBBY:
		_lobby_menu.active = true


func _aim_camera(at: Vector2) -> void:
	var world := _world()
	if world == null:
		return
	if world.has_method("set_camera_driver"):
		world.call("set_camera_driver", false)
	if not world.has_method("camera"):
		return
	var cam_v: Variant = world.call("camera")
	if cam_v != null and cam_v.has_method("focus"):
		cam_v.call("focus", at, 1.0, 1.15)


func _release_camera() -> void:
	var world := _world()
	if world == null or not world.has_method("camera"):
		return
	var cam_v: Variant = world.call("camera")
	if cam_v != null and cam_v.has_method("release"):
		cam_v.call("release")


func _world() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("game_world")


# --------------------------------------------------------------------- match --

func _refresh_match() -> void:
	if _match == null or not _match.visible:
		return
	var board := ArenaRun.scoreboard()
	var rows: Array = ArenaRun.tower_status()
	var blue := _as_dict(board.get("blue", {}))
	var red := _as_dict(board.get("red", {}))
	var time_text := ArenaCatalog.format_time(float(board.get("time_left", ArenaRun.time_left())))
	var score_text := "[color=#%s]灰卫 %d杀 · 塔%d[/color]  %s  [color=#%s]塔%d · %d杀 锈誓[/color]" % [
		_hex(_team_color(ArenaCatalog.TEAM_PLAYER)),
		int(blue.get("kills", 0)),
		_living_towers(rows, ArenaCatalog.TEAM_PLAYER),
		time_text,
		_hex(_team_color(ArenaCatalog.TEAM_ENEMY)),
		_living_towers(rows, ArenaCatalog.TEAM_ENEMY),
		int(red.get("kills", 0)),
	]
	if _score_label.text != score_text:
		_score_label.text = score_text
	_paint_towers(rows, ArenaCatalog.TEAM_PLAYER, _blue_names, _blue_fills, _blue_locks)
	_paint_towers(rows, ArenaCatalog.TEAM_ENEMY, _red_names, _red_fills, _red_locks)
	if _map != null and _map.has_method("set_snapshot"):
		_map.call("set_snapshot", ArenaRun.minimap_data(), _camera_view())
	_refresh_player()


func _refresh_player() -> void:
	var lv := ArenaRun.player_level()
	var xp := ArenaRun.player_xp()
	var need := ArenaCatalog.xp_needed(lv)
	var ratio := 1.0
	var xp_text := "满"
	if need > 0:
		ratio = clampf(float(xp) / float(need), 0.0, 1.0)
		xp_text = "%d/%d" % [xp, need]
	_level_label.text = "等级 %d   经验 %s" % [lv, xp_text]
	if _xp_fill != null:
		_xp_fill.anchor_right = ratio
	_ember_label.text = "余烬 %d" % ArenaRun.player_ember()
	var bless := ArenaRun.blessing_time_left(ArenaCatalog.TEAM_PLAYER)
	if bless > 0.05:
		_bless_label.text = "炉火 %d 秒" % int(ceil(bless))
		_bless_label.modulate = Color(1.15, 0.86, 0.42)
	else:
		_bless_label.text = "炉火 —"
		_bless_label.modulate = Color(0.7, 0.66, 0.6)
	if _near_fountain() and not _shop.visible:
		_near_label.text = "按 %s 打开炉台" % KeyLabels.label(&"interact")
	else:
		_near_label.text = ""
	var left := ArenaRun.respawn_time_left(null)
	if left > 0.05:
		_show_respawn(true)
		_respawn_label.text = "复活倒计时 %d 秒" % int(ceil(left))
	else:
		_show_respawn(false)


func _show_respawn(on: bool) -> void:
	if _respawn_label != null:
		_respawn_label.visible = on
	if _respawn_plate != null:
		_respawn_plate.visible = on


func _sync_banner() -> void:
	if _bless_plate != null and _bless_banner != null:
		_bless_plate.visible = _bless_banner.visible


func _paint_towers(rows: Array, team: String, names: Array[Label], fills: Array[ColorRect],
		locks: Array[Label]) -> void:
	var tint := _team_color(team)
	for index in names.size():
		var row := _row_for(rows, team, index)
		var kind := String(row.get("kind", ArenaCatalog.structure_kind(index)))
		var caption := String(row.get("label", ArenaCatalog.structure_label(index)))
		names[index].text = caption
		var max_hp := maxi(1, int(row.get("max_hp", 1)))
		var hp := int(row.get("hp", 0))
		var alive := bool(row.get("alive", false))
		var exposed := bool(row.get("exposed", true))
		var ratio := 0.0
		if alive and max_hp > 0:
			ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		fills[index].anchor_right = ratio
		var locked := kind == "crystal" and not exposed
		if not alive:
			fills[index].color = Color(0.32, 0.28, 0.26)
			names[index].modulate = Color(0.55, 0.5, 0.48)
		elif not exposed:
			fills[index].color = LOCKED_BAR
			names[index].modulate = Color(0.55, 0.55, 0.58)
		else:
			fills[index].color = tint
			names[index].modulate = Color.WHITE
		locks[index].text = "锁" if locked else ""
		locks[index].visible = locked


func _living_towers(rows: Array, team: String) -> int:
	var n := 0
	for index in [0, 1]:
		if bool(_row_for(rows, team, index).get("alive", false)):
			n += 1
	return n


func _row_for(rows: Array, team: String, index: int) -> Dictionary:
	for raw in rows:
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		if String(row.get("team", "")) == team and int(row.get("index", -1)) == index:
			return row
	return {}


func _camera_view() -> Rect2:
	var world := _world()
	if world == null or not world.has_method("camera"):
		return Rect2()
	var cam_v: Variant = world.call("camera")
	if cam_v == null or not (cam_v is Camera2D):
		return Rect2()
	var cam := cam_v as Camera2D
	var zoom_x := cam.zoom.x
	if zoom_x <= 0.01:
		zoom_x = 1.0
	var half := Vector2(PresentationMetrics.WORLD_SIZE) * 0.5 / zoom_x
	return Rect2(cam.global_position - half, half * 2.0)


func _push_feed(line: String, kind: String = "kill") -> void:
	_feed.append({"text": line, "age": 0.0, "kind": kind})
	while _feed.size() > FEED_CAP:
		_feed.pop_front()
	_redraw_feed()


func _decay_feed(delta: float) -> void:
	if _feed.is_empty():
		return
	var kept: Array = []
	for raw in _feed:
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		var age := float(row.get("age", 0.0)) + delta
		if age >= FEED_LIFE:
			continue
		row["age"] = age
		kept.append(row)
	_feed = kept
	_redraw_feed()


func _redraw_feed() -> void:
	if _feed_head != null:
		_feed_head.visible = not _feed.is_empty()
	for i in _feed_labels.size():
		var label := _feed_labels[i]
		if i >= _feed.size() or _feed[i] is not Dictionary:
			label.visible = false
			label.text = ""
			label.modulate = Color.WHITE
			continue
		var row: Dictionary = _feed[i]
		var age := float(row.get("age", 0.0))
		label.visible = true
		var text := String(row.get("text", ""))
		if label.text != text:
			label.text = text
		var kind := String(row.get("kind", "kill"))
		if String(label.get_meta(&"feed_kind", "")) != kind:
			label.set_meta(&"feed_kind", kind)
			label.add_theme_stylebox_override(&"normal", _feed_boxes.get(kind, _feed_boxes["kill"]))
		var alpha := clampf(1.0 - age / FEED_LIFE, 0.0, 1.0)
		label.modulate = Color(1.0, 1.0, 1.0, alpha)


# ---------------------------------------------------------------------- shop --

func _open_shop() -> void:
	if ArenaRun.phase() != ArenaCatalog.PHASE_PLAYING:
		return
	if not _near_fountain():
		return
	_shop.visible = true
	_shop_menu.active = true
	_shop_ember.text = "余烬 %d" % ArenaRun.player_ember()
	_shop_status.text = ""
	_near_label.text = ""


func _close_shop() -> void:
	if _shop == null:
		return
	_shop.visible = false
	if _shop_menu != null:
		_shop_menu.active = false


func _near_fountain() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var knight := tree.get_first_node_in_group("player") as Node2D
	if knight == null:
		return false
	var well := ArenaCatalog.fountain_for(ArenaCatalog.TEAM_PLAYER)
	return ArenaCatalog.near_fountain(knight.global_position, well)


## 一行一件强化。文字区 320px 居中，间距只留单空格：宽了会压到左侧的光标。
func _shop_line(item: Dictionary) -> String:
	var caption := String(item.get("label", item.get("id", "")))
	var cost := int(item.get("cost", 0))
	var extra := ""
	if int(item.get("attack", 0)) > 0:
		extra += " 攻击+%d" % int(item.get("attack", 0))
	if int(item.get("hp", 0)) > 0:
		extra += " 生命+%d" % int(item.get("hp", 0))
	if float(item.get("speed", 0.0)) > 0.0:
		extra += " 移速+%d" % int(item.get("speed", 0.0))
	return "%s %d 余烬%s" % [caption, cost, extra]


func _shop_reason(reason: String, ember: int) -> String:
	var tail := "余烬 %d" % ember
	if reason == "ember":
		return "余烬不足 · %s" % tail
	if reason == "range":
		return "需站在己方泉水旁 · %s" % tail
	if reason == "phase":
		return "对局中才能强化 · %s" % tail
	if reason == "unknown":
		return "没有这件强化 · %s" % tail
	if reason == "":
		return tail
	return "%s · %s" % [reason, tail]


# -------------------------------------------------------------------- result --

func _fill_result() -> void:
	var result := ArenaRun.match_result()
	var outcome := String(result.get("outcome", ""))
	var headline := "平 局"
	var tint := DRAW_TINT
	if outcome == "win" or bool(result.get("win", false)):
		headline = "胜 利"
		tint = WIN_TINT
	elif outcome == "loss":
		headline = "失 败"
		tint = LOSS_TINT
	elif outcome == "draw" or bool(result.get("draw", false)):
		headline = "平 局"
		tint = DRAW_TINT
	if _result_title != null:
		_result_title.text = headline
	if _result_seal != null:
		_result_seal.tint = tint
	var elapsed := float(result.get("elapsed", result.get("duration", 0.0)))
	_result_meta.text = "时长 %s    难度 %s" % [
		ArenaCatalog.format_time(elapsed),
		ArenaCatalog.difficulty_label(String(result.get("difficulty", ""))),
	]
	_result_score.text = "灰卫  击杀 %d  拆塔 %d\n锈誓  击杀 %d  拆塔 %d" % [
		int(result.get("blue_kills", 0)),
		int(result.get("blue_towers", 0)),
		int(result.get("red_kills", 0)),
		int(result.get("red_towers", 0)),
	]
	var player := _as_dict(result.get("player", {}))
	_result_player.text = "你   K %d   D %d   A %d    补刀 %d    等级 %d" % [
		int(player.get("kills", 0)),
		int(player.get("deaths", 0)),
		int(player.get("assists", 0)),
		int(player.get("last_hits", 0)),
		int(player.get("level", 1)),
	]
	var mvp := _as_dict(result.get("mvp", {}))
	var mvp_label := String(mvp.get("label", "—"))
	if mvp_label == "":
		mvp_label = "—"
	_result_mvp.text = "MVP  %s" % mvp_label
	var fresh := bool(result.get("new_record", false))
	_result_record.visible = fresh
	_result_record.text = "新纪录"


func _focus_id(menu: MenuList, id: StringName) -> void:
	if menu == null:
		return
	var at := menu.item_ids().find(id)
	if at >= 0:
		menu.select(at, false)


func _mark_handled() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _team_color(team: String) -> Color:
	var raw: Variant = ArenaCatalog.TEAM_TINT.get(team, Color(0.75, 0.72, 0.66))
	if raw is Color:
		return raw as Color
	return Color(0.75, 0.72, 0.66)


## 队色用作卡片顶边和小题头：TEAM_TINT 有超过 1 的通道（给贴图乘色用），这里压回 0..1。
func _accent_for(blue: bool) -> Color:
	var raw := _team_color(ArenaCatalog.TEAM_PLAYER if blue else ArenaCatalog.TEAM_ENEMY)
	return Color(minf(raw.r, 1.0), minf(raw.g, 1.0), minf(raw.b, 1.0), 1.0)


## Label 没有 BBCode。记分（24px）和击杀条（12px + 1px 描边）用 RichTextLabel。
## 字号直接给：未入树的 sample 读不到变体字号，会回落到项目默认的 24px（这正是旧击杀条偏大的原因）。
func _bbcode_line(align: HorizontalAlignment, font_px: int = 12) -> RichTextLabel:
	var sample := UiKit.label("", &"TinyStrongLabel" if font_px <= 12 else &"BodyLabel", align)
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.scroll_active = false
	line.fit_content = true
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.horizontal_alignment = align
	line.add_theme_font_override("normal_font", sample.get_theme_font(&"font"))
	line.add_theme_font_size_override("normal_font_size", font_px)
	line.add_theme_color_override("default_color", Color("#E4DCCC"))
	if font_px <= 12:
		line.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.92))
		line.add_theme_constant_override("outline_size", 1)
	sample.free()
	return line


## 队色小题头（「灰 卫」「锈 誓」）：字色直接用队色。不用 modulate：它会乘上 12px 小字自带的余烬色，队色被压灰。
func _team_kicker(text: String, accent: Color) -> Label:
	var label := UiKit.label(text, &"TinyStrongLabel")
	label.add_theme_color_override(&"font_color", accent)
	label.custom_minimum_size = Vector2(0.0, 22.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 结果卡：一张切角玻璃卡，顶上一行 kicker，下面是内容。宽度固定，高度随内容。
func _section_card(card_name: String, kicker_text: String, parent: Control, width: float) -> VBoxContainer:
	var card := Chamfer.new()
	card.name = card_name
	card.custom_minimum_size = Vector2(width, 0.0)
	card.set_pad(16.0, 12.0, 16.0, 12.0)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.name = card_name + "Box"
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	box.add_child(GlassKit.kicker(kicker_text))
	return box


func _ticks(segments: int) -> Control:
	var ticks := Ticks.new()
	ticks.segments = segments
	return ticks


static func _feed_box(accent: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.035, 0.07, 0.62)
	box.border_width_right = 2
	box.border_color = accent
	box.content_margin_left = 8.0
	box.content_margin_right = 10.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box


func _hex(tint: Color) -> String:
	return tint.to_html(false)


func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}


# ------------------------------------------------------------ inner widgets --

## 局内与结算用的玻璃切角卡：标题档案卡的轮廓（2px 阶梯切角、锈线描边、顶边一道光），
## 填充是单块多边形，半透明也不会在叠合处发深。它是 PanelContainer：子节点的最小尺寸决定卡片大小。
class Chamfer extends PanelContainer:
	var cut := 6.0:
		set(value):
			cut = value
			queue_redraw()
	var fill_alpha := 0.66:
		set(value):
			fill_alpha = value
			queue_redraw()
	var accent: Color = Color(1.0, 0.76, 0.29, 1.0):
		set(value):
			accent = value
			queue_redraw()
	var _pad_box := StyleBoxEmpty.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_pad(12.0, 10.0, 12.0, 8.0)
		add_theme_stylebox_override(&"panel", _pad_box)

	func set_pad(left: float, top: float, right: float, bottom: float) -> void:
		_pad_box.content_margin_left = left
		_pad_box.content_margin_top = top
		_pad_box.content_margin_right = right
		_pad_box.content_margin_bottom = bottom

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 8.0 or h < 8.0:
			return
		var c := cut
		draw_colored_polygon(_stair_points(w, h, c), Color(0.07, 0.05, 0.09, fill_alpha))
		var edge := Color(0.42, 0.24, 0.13, 0.95)
		draw_rect(Rect2(c, 0.0, w - 2.0 * c, 1.0), edge)
		draw_rect(Rect2(c, h - 1.0, w - 2.0 * c, 1.0), edge)
		draw_rect(Rect2(0.0, c, 1.0, h - 2.0 * c), edge)
		draw_rect(Rect2(w - 1.0, c, 1.0, h - 2.0 * c), edge)
		for i in int(c / 2.0):
			var o := 2.0 * float(i)
			draw_rect(Rect2(c - 2.0 - o, 2.0 + o, 2.0, 2.0), edge)
			draw_rect(Rect2(w - c + o, 2.0 + o, 2.0, 2.0), edge)
			draw_rect(Rect2(c - 2.0 - o, h - 4.0 - o, 2.0, 2.0), edge)
			draw_rect(Rect2(w - c + o, h - 4.0 - o, 2.0, 2.0), edge)
		draw_rect(Rect2(c * 2.0, 1.0, w - c * 4.0, 2.0), Color(accent.r, accent.g, accent.b, 0.8))

	static func _stair_points(w: float, h: float, c: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(c, 0.0), Vector2(w - c, 0.0), Vector2(w - c, c - 2.0), Vector2(w - 2.0, c - 2.0),
			Vector2(w - 2.0, c), Vector2(w, c), Vector2(w, h - c), Vector2(w - 2.0, h - c),
			Vector2(w - 2.0, h - c + 2.0), Vector2(w - c, h - c + 2.0), Vector2(w - c, h), Vector2(c, h),
			Vector2(c, h - c + 2.0), Vector2(2.0, h - c + 2.0), Vector2(2.0, h - c), Vector2(0.0, h - c),
			Vector2(0.0, c), Vector2(2.0, c), Vector2(2.0, c - 2.0), Vector2(c, c - 2.0),
		])


## 分段刻度：在量条上每隔 1/n 压一道暗线，读数像一根刻了格的铁尺。
class Ticks extends Control:
	var segments := 10:
		set(value):
			segments = maxi(value, 1)
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in range(1, segments):
			var x := floorf(w * float(i) / float(segments))
			draw_rect(Rect2(x, 0.0, 1.0, h), Color(0.04, 0.03, 0.06, 0.8))


## 结算判章：菱形章 + 两侧细线，和结局印记（GlassKit.SealMark）同一套菱形语汇，但更大，
## 外圈多两道刻线。颜色随结果：胜 = 还火金，平 = 守炉橙，负 = 熄火灰紫。
class VerdictSeal extends Control:
	var tint: Color = Color(1.0, 0.76, 0.29, 1.0):
		set(value):
			tint = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, 48.0)

	func _draw() -> void:
		var c := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5))
		var line := Color(tint.r, tint.g, tint.b, 0.42)
		draw_rect(Rect2(c.x - 132.0, c.y, 88.0, 1.0), line)
		draw_rect(Rect2(c.x + 44.0, c.y, 88.0, 1.0), line)
		GlassKit.diamond(self, Vector2(c.x - 132.0, c.y), 3.0, line)
		GlassKit.diamond(self, Vector2(c.x + 132.0, c.y), 3.0, line)
		GlassKit.diamond(self, c, 22.0, Color(tint.r, tint.g, tint.b, 0.14))
		GlassKit.diamond(self, c, 18.0, Color(tint.r, tint.g, tint.b, 0.4))
		GlassKit.diamond(self, c, 14.0, Color(tint.r, tint.g, tint.b, 0.18))
		GlassKit.diamond(self, c, 10.0, tint)
		GlassKit.diamond(self, c, 7.0, GlassKit.INK)
		GlassKit.diamond(self, c, 4.0, tint)
		GlassKit.diamond(self, c, 2.0, GlassKit.EMBER_HOT)


## 开战倒计时背后的菱形光环：两圈刻线，四个方位各一粒余烬。
class Halo extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(200.0, 200.0)

	func _draw() -> void:
		var c := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5))
		_ring(c, 96.0, Color(0.37, 0.29, 0.24, 0.7))
		_ring(c, 80.0, Color(1.0, 0.76, 0.29, 0.22))
		for p in [Vector2(c.x - 96.0, c.y), Vector2(c.x + 96.0, c.y),
				Vector2(c.x, c.y - 96.0), Vector2(c.x, c.y + 96.0)]:
			GlassKit.diamond(self, p, 4.0, GlassKit.EMBER)

	func _ring(c: Vector2, r: float, col: Color) -> void:
		draw_polyline(PackedVector2Array([
			Vector2(c.x, c.y - r), Vector2(c.x + r, c.y), Vector2(c.x, c.y + r),
			Vector2(c.x - r, c.y), Vector2(c.x, c.y - r),
		]), col, 2.0)
