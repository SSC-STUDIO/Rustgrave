extends CanvasLayer
## 游戏内 HUD（1280x720）：左上一条紧凑状态带（心 + 毒素槽）、顶部播报横幅、
## 底部交互提示、低血量血雾，外挂暂停菜单与触控板。
##
## 原则是"先看画面"：常驻的只有血量和毒素；剑核插座在拿到第一枚锈核后才出现，
## 袋中数量只在袋里有核时出现；目标、天气时辰、剑核名称是次要信息——换区 / 换时辰
## / 章节开头短暂显示几秒，或按住 Tab（触屏轻点状态带）随时查看。
## 导演的电影黑边出现时整个 HUD 淡出上滑，心不会被黑边切掉。情境教学提示见
## HintService（scripts/ui/hint_service.gd）。
##
## 所有外观取自项目默认主题 assets/ui/theme_rust.tres 与 UiKit.extras_theme()
## 的变体；这里只负责布局、数值与动效。

const PAUSE_MENU := preload("res://scenes/ui/PauseMenu.tscn")

## 心：11x9 的 Gothicvania 像素心按 2 倍放进 26x22 的插槽里，和 24px 字号同栅格。
const HEART_FULL_PATH := "res://assets/env/hud_heart_full.png"
const HEART_EMPTY_PATH := "res://assets/env/hud_heart_empty.png"
const HEART_SIZE := Vector2(22, 18)
const HEART_SLOT_SIZE := Vector2(26, 22)
const HEART_SEPARATION := 2
const HEART_FLASH := 0.22

## 状态带外侧的留白与毒素槽尺寸（设计单位）。心行 22 + 槽行 16 + 间隙 2 + 上下衬 8 = 48。
const STAT_MARGIN := Vector2(12.0, 8.0)
## 毒素槽宽度是下限，实际由 HBox 撑满状态带（与心行同宽），读数才像一条真正的量槽。
const TOXIN_BAR_SIZE := Vector2(96, 14)
## 槽行高度：12px 字的行高是 16，槽 14 高居中放，字框上下各留 1。
const TOXIN_ROW_HEIGHT := 16.0
## 毒素档位字（"溢 100%"）占的槽宽。12px 字最宽是 3 位数，"溢 100%" 约 39 设计像素。
const TOXIN_LABEL_WIDTH := 46.0
## 剑核插座：拿到第一枚锈核之前整条隐藏。
const SOCKET_BREATH_PERIOD := 2.4
const SOCKET_ICON := 26.0
## 与 assets/ui/banner.png 的高度一致（21 设计像素 * 2）。
const BANNER_HEIGHT := 42.0
const BANNER_TOP := 14.0
## 交互提示贴在视口底边，避开玩家所在的中下视野；字幕占用底边时整条让路。
const PROMPT_BOTTOM := 10.0
## 交互提示里键帽与文案的间距。
const PROMPT_KEY_GAP := 10.0
## 交互提示出场：向上浮 6px 的同时淡入（像素栅格上取整，不出灰边）。
const PROMPT_SLIDE := 6.0
const PROMPT_FADE := 0.18
## Boss 条在底边中央占的高度（12px 名字行 + 2 + 12 血条 + 上下 10 内容边距）；
## 交互提示在 Boss 战中抬到它上面，两者不重叠。
const BOSS_BAR_HEIGHT := 50.0
const BOSS_BAR_LIFT := 68.0
## Boss 血条里的相数刻度：与过场名号卡同一套 8px 菱形。
const BOSS_PIP := 8.0
const BOSS_PIP_GAP := 4.0
## 长文案的边界（设计像素）。短句保持自然宽；超出后单行提示用省略号收尾，
## 目标行折成最多两行。所有上限定在 1280 宽的 HUD 画布内，任何语言都不溢出。
const PROMPT_MAX_WIDTH := 1080.0
const BANNER_MAX_WIDTH := 1040.0
const OBJECTIVE_MAX_WIDTH := 860.0
const BOSS_TITLE_MAX_WIDTH := 400.0

# 危险反馈：毒素报警脉动 + 低血量血雾呼吸。
const TOXIN_ALARM_RATIO := 0.8
const TOXIN_PULSE_PERIOD := 0.5
const TOXIN_PULSE_MIN := 1.0
const TOXIN_PULSE_MAX := 1.6
## 报警脉动时档位字的乘色（绿色底字 × 暖色 = 琥珀 / 血红），别把档位读丢。
const TOXIN_TINT_WARM := Color(1.15, 0.95, 0.65)
const TOXIN_TINT_HOT := Color(1.35, 0.75, 0.35)
const TOXIN_TINT_OVERFLOW := Color(1.5, 0.45, 0.3)
const VIGNETTE_FADE_IN := 0.4
const VIGNETTE_FADE_OUT := 0.6
## 低血量血雾：只留一圈会呼吸的锈血边，压到 0.34 后骑士剪影与敌人前摇仍读得清；
## 原先 0.55 / 呼吸到 0.68 时，1-bit 抖动边会把左半屏（骑士所在）整片染红。
const VIGNETTE_ALPHA := 0.34
const VIGNETTE_BREATH_MIN := 0.18
const VIGNETTE_BREATH_MAX := 0.38
const VIGNETTE_BREATH_PERIOD := 1.8
const VIGNETTE_TINT := Color(1.0, 0.82, 0.82)

const ANNOUNCE_HOLD := 2.4
const ANNOUNCE_FADE := 0.35

## 次要信息：换区 / 换时辰后天气时辰显示 4 秒，章节开头目标显示 5 秒。
const ATMOS_HOLD := 4.0
const OBJECTIVE_HOLD := 5.0
const OBJECTIVE_DELAY := 1.2
const OBJECTIVE_REFRESH := 0.5
const REVEAL_SPEED := 4.0
## 触屏轻点状态带后保持"查看"的秒数（没有 Tab 键）。
const PEEK_TAP_HOLD := 4.0
## 电影黑边升到这个比例时 HUD 已完全淡出（黑边满格 32 单位，淡出走前 1/4）。
const LETTERBOX_FADE_AT := 0.25
const LETTERBOX_SLIDE := 28.0

var _root: Control
var _stat: VBoxContainer
var _plate: PanelContainer
var _hearts_row: HBoxContainer
var _toxin_bar: ProgressBar
var _toxin_label: Label
var _socket_strip: HBoxContainer
var _sockets: Array[Control] = []
var _pouch_label: Label
var _socket_label: Label
var _objective_label: Label
var _atmos_label: Label
var _prompt_panel: PanelContainer
var _prompt_key_panel: PanelContainer
var _prompt_key_label: Label
var _prompt_label: Label
var _banner: PanelContainer
var _announce_label: Label
var _vignette: TextureRect
var _death_overlay: Control
var _pause: PauseMenu
var _hints: HintService
var _tracker := ObjectiveTracker.new()

var _heart_full: Texture2D
var _heart_empty: Texture2D
var _hp_shown := -1
var _announce_time := 0.0
var _toxin_ratio := 0.0
var _low_hp := false
var _vignette_tween: Tween
var _time := 0.0
var _breath_time := 0.0
var _announce_queue: Array[String] = []
var _banner_tween: Tween
var _resonating := false
var _prompt_text := ""
var _cores_owned := false

var _atmos_time := 0.0
var _atmos_alpha := 0.0
var _objective_time := 0.0
var _objective_alpha := 0.0
var _objective_refresh := 0.0
var _objective_delay := OBJECTIVE_DELAY
var _peek_timer := 0.0
var _peek_was_on := false
var _peek_alpha := 0.0
var _boss_name := ""
var _insets := Vector4.ZERO
var _critical_font_sizes: Dictionary = {}
var _small_window := false

var _boss_bar_panel: PanelContainer
var _boss_title_label: Label
var _boss_hp_bar: ProgressBar
var _boss_phase_pips: PhasePips
var _boss_max_hp: int = 1
## 交互提示出场补间（换可交互物时先掐掉上一段）。
var _prompt_tween: Tween


func _ready() -> void:
	layer = 10
	WorldClock.isolate_ui_layer(self)
	DisplayServer.window_set_title("Rustgrave")
	_heart_full = UiKit.tex(HEART_FULL_PATH)
	_heart_empty = UiKit.tex(HEART_EMPTY_PATH)
	_build()
	GameEvents.player_health_changed.connect(_on_hp)
	GameEvents.toxin_changed.connect(_on_toxin)
	GameEvents.interact_prompt.connect(_on_prompt)
	GameEvents.announcement.connect(_on_announce)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.core_inserted.connect(_on_core_inserted)
	GameEvents.core_acquired.connect(_on_core_acquired)
	GameEvents.sockets_changed.connect(_refresh_cores)
	GameEvents.resonance_changed.connect(_on_resonance)
	GameEvents.boss_appeared.connect(_on_boss_appeared)
	GameEvents.boss_hp_changed.connect(_on_boss_hp_changed)
	GameEvents.boss_phase_changed.connect(_on_boss_phase_changed)
	GameEvents.boss_defeated.connect(_on_boss_defeated)
	GameEvents.chapter_started.connect(_on_chapter_started)
	WorldClock.phase_changed.connect(_on_phase_changed)
	WorldClock.weather_changed.connect(_on_weather_changed)
	WorldClock.zone_changed.connect(_on_zone_changed)
	Settings.changed.connect(_on_setting_changed)
	get_tree().root.size_changed.connect(_apply_safe_area)
	_refresh_atmosphere()
	_show_atmosphere()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		_on_hp(player.health.current, player.health.max_hp)
		_on_toxin(player.toxin.toxin, player.toxin.max_toxin)
		_refresh_cores()
	_apply_safe_area()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.extras_theme()
	add_child(_root)

	# 血雾垫在最底层：低血量时它压着画面，不该盖住心和提示。
	_build_vignette(_root)
	_build_stat_panel(_root)
	_build_banner(_root)
	_build_boss_bar(_root)
	_build_prompt(_root)
	_build_atmosphere(_root)

	# 情境提示条（顶部居中，播报横幅之下）。必须在死亡幕之前建：提示是教学，
	# 死亡幕是最高优先级，先建的先画，提示永远盖不到"余烬熄灭"上面。
	_hints = HintService.new()
	_hints.name = "HintService"
	add_child(_hints)
	_hints.attach(_root)

	_build_death_overlay(_root)

	_pause = PAUSE_MENU.instantiate()
	add_child(_pause)
	WorldClock.isolate_ui_layer(_pause)

	# Touch pad is root-window UI (PresentationMetrics-bound), not the 640×360 world.
	var touch := TouchControls.new()
	touch.name = "TouchControls"
	touch.bind_pause(_pause)
	add_child(touch)


## 左上角：状态带（心 + 毒素槽）与它右侧的剑核插座，下方是目标行与"查看"行。
func _build_stat_panel(root: Control) -> void:
	_stat = VBoxContainer.new()
	_stat.name = "StatPanel"
	_stat.offset_left = STAT_MARGIN.x
	_stat.offset_top = STAT_MARGIN.y
	_stat.add_theme_constant_override("separation", 3)
	_stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stat)

	var row := HBoxContainer.new()
	row.name = "PlateRow"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat.add_child(row)

	_plate = UiKit.panel(&"HudPlate")
	_plate.name = "Plate"
	# 触屏没有 Tab：轻点状态带就是"查看"。桌面端不拦截鼠标，免得吃掉挥砍的点击。
	_plate.mouse_filter = Control.MOUSE_FILTER_STOP if TouchInput.wants_overlay() \
			else Control.MOUSE_FILTER_IGNORE
	_plate.gui_input.connect(_on_plate_input)
	row.add_child(_plate)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(inner)

	_hearts_row = HBoxContainer.new()
	_hearts_row.name = "Hearts"
	_hearts_row.add_theme_constant_override("separation", HEART_SEPARATION)
	_hearts_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_hearts_row)

	var gauge_row := HBoxContainer.new()
	gauge_row.name = "Gauge"
	gauge_row.add_theme_constant_override("separation", 6)
	gauge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(gauge_row)
	_toxin_bar = ProgressBar.new()
	_toxin_bar.name = "ToxinBar"
	_toxin_bar.custom_minimum_size = TOXIN_BAR_SIZE
	# 撑满心行宽度：一截 96px 的短槽读数不像"量槽"，像心下面的一道暗缝。
	_toxin_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toxin_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toxin_bar.theme_type_variation = &"ToxinBarCold"
	_toxin_bar.show_percentage = false
	_toxin_bar.min_value = 0.0
	_toxin_bar.max_value = 100.0
	_toxin_bar.value = 0.0
	_toxin_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge_row.add_child(_toxin_bar)
	var label_slot := Control.new()
	label_slot.name = "ToxinLabelSlot"
	label_slot.custom_minimum_size = Vector2(TOXIN_LABEL_WIDTH, TOXIN_ROW_HEIGHT)
	label_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge_row.add_child(label_slot)
	_toxin_label = UiKit.label("冷 0%", &"TinyToxinLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_toxin_label.name = "ToxinLabel"
	_toxin_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toxin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_slot.add_child(_toxin_label)

	# 剑核插座：拿到第一枚锈核之前整条隐藏。
	_socket_strip = HBoxContainer.new()
	_socket_strip.name = "Sockets"
	_socket_strip.add_theme_constant_override("separation", 4)
	_socket_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_socket_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_socket_strip.visible = false
	row.add_child(_socket_strip)
	for i in 2:
		var cell := _make_socket(i)
		_sockets.append(cell)
		_socket_strip.add_child(cell)
	_pouch_label = UiKit.label("袋中 0", &"TinyStrongLabel")
	_pouch_label.name = "PouchLabel"
	_pouch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pouch_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pouch_label.visible = false
	_socket_strip.add_child(_pouch_label)

	_objective_label = UiKit.label("", &"TinyStrongLabel")
	_objective_label.name = "ObjectiveLabel"
	_objective_label.modulate.a = 0.0
	_objective_label.visible = false
	_stat.add_child(_objective_label)
	_socket_label = UiKit.label("", &"TinyLabel")
	_socket_label.name = "SocketLabel"
	_socket_label.modulate.a = 0.0
	_socket_label.visible = false
	_stat.add_child(_socket_label)
	_refresh_socket_keys()


## 一个插座：26x26 的铁环 + 按核着色的宝石 + 下方一行键名。
## 铁环在袋里有核、插座还空着时会缓慢呼吸 —— "这里空着、袋里有货"的暗示，
## 让玩家知道该按 1 / 2 了；镶满之后呼吸停下，环稳定压亮。
func _make_socket(index: int) -> Control:
	var cell := VBoxContainer.new()
	cell.name = "Socket%d" % index
	cell.add_theme_constant_override("separation", 0)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Control.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(SOCKET_ICON, SOCKET_ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	var ring := UiKit.sprite_rect(UiKit.TEX_SOCKET_RING)
	ring.name = "Ring"
	ring.modulate = Color(0.78, 0.7, 0.62, 0.8)
	icon.add_child(ring)
	var gem := UiKit.sprite_rect(UiKit.TEX_SOCKET_GEM)
	gem.name = "Gem"
	gem.visible = false
	icon.add_child(gem)
	var key := UiKit.label("", &"TinyLabel", HORIZONTAL_ALIGNMENT_CENTER)
	key.name = "Key"
	cell.add_child(key)
	return cell


func _build_banner(root: Control) -> void:
	_banner = UiKit.panel(&"BannerPanel")
	_banner.name = "Banner"
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = BANNER_TOP
	# 高度钉在贴图原高：横幅一被纵向拉伸，两端的尖角就会出现半像素毛边。
	_banner.custom_minimum_size = Vector2(0.0, BANNER_HEIGHT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_announce_label = UiKit.label("", &"AnnounceLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_announce_label.name = "AnnounceLabel"
	_announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 横幅钉死在贴图原高：长句只在单行内省略，不允许把两条尖角拉长。
	_announce_label.max_lines_visible = 1
	_banner.add_child(_announce_label)


func _build_boss_bar(root: Control) -> void:
	_boss_bar_panel = UiKit.panel(&"HudPanel")
	_boss_bar_panel.name = "BossBar"
	_boss_bar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_boss_bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_bar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_boss_bar_panel.offset_top = -(22.0 + BOSS_BAR_HEIGHT)
	_boss_bar_panel.offset_bottom = -22.0
	_boss_bar_panel.custom_minimum_size = Vector2(460.0, BOSS_BAR_HEIGHT)
	_boss_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_panel.visible = false
	root.add_child(_boss_bar_panel)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	_boss_bar_panel.add_child(col)

	# 名号行：名字 + 相数刻度（与过场名号卡同一套菱形，一进相就多一只）。
	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 10)
	col.add_child(title_row)
	_boss_title_label = UiKit.label("炉 约 刽 子 手 · 铸 渣 残 躯", &"BossTitleLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	_boss_title_label.name = "BossTitle"
	_boss_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(_boss_title_label)
	_boss_phase_pips = PhasePips.new()
	_boss_phase_pips.name = "BossPhase"
	title_row.add_child(_boss_phase_pips)

	_boss_hp_bar = ProgressBar.new()
	_boss_hp_bar.name = "BossHpBar"
	_boss_hp_bar.custom_minimum_size = Vector2(420.0, 12.0)
	_boss_hp_bar.theme_type_variation = &"BossHpBar"
	_boss_hp_bar.show_percentage = false
	_boss_hp_bar.min_value = 0.0
	_boss_hp_bar.max_value = 13.0
	_boss_hp_bar.value = 13.0
	col.add_child(_boss_hp_bar)


func _build_prompt(root: Control) -> void:
	_prompt_panel = UiKit.panel(&"HudPanel")
	_prompt_panel.name = "Prompt"
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_panel.offset_top = -PROMPT_BOTTOM
	_prompt_panel.offset_bottom = -PROMPT_BOTTOM
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.visible = false
	root.add_child(_prompt_panel)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", PROMPT_KEY_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.add_child(row)
	# 键帽：交互键单独一块小铁牌，和设置页键位列同一个来源（Settings → KeyLabels）。
	_prompt_key_panel = UiKit.panel(&"KeyCapPanel")
	_prompt_key_panel.name = "PromptKeyPanel"
	_prompt_key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_key_panel.visible = false
	row.add_child(_prompt_key_panel)
	_prompt_key_label = UiKit.label("", &"KeyCapLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_key_label.name = "PromptKey"
	_prompt_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_key_panel.add_child(_prompt_key_label)
	_prompt_label = UiKit.label("", &"PromptLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_label.name = "PromptLabel"
	_prompt_label.max_lines_visible = 1
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_prompt_label)


## 右上角的小标签：天气 · 时辰（换区 / 换时辰时 4 秒，或按住 Tab）。
func _build_atmosphere(root: Control) -> void:
	_atmos_label = UiKit.label("", &"TinyLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_atmos_label.name = "AtmosphereHint"
	_atmos_label.anchor_left = 1.0
	_atmos_label.anchor_right = 1.0
	_atmos_label.offset_left = -300.0
	_atmos_label.offset_right = -18.0
	_atmos_label.offset_top = 14.0
	_atmos_label.offset_bottom = 32.0
	_atmos_label.max_lines_visible = 1
	_atmos_label.clip_text = true
	_atmos_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_atmos_label.modulate.a = 0.0
	root.add_child(_atmos_label)


func _build_vignette(root: Control) -> void:
	_vignette = UiKit.sprite_rect(UiKit.TEX_VIGNETTE)
	_vignette.name = "BloodVignette"
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 贴图本身是 (140,20,20) 的 1-bit 抖动脉冲边，压暗一点读成锈血而不是红屏。
	_vignette.modulate = Color(VIGNETTE_TINT, 0.0)
	_vignette.visible = false
	root.add_child(_vignette)


func _build_death_overlay(root: Control) -> void:
	_death_overlay = Control.new()
	_death_overlay.name = "DeathOverlay"
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.modulate.a = 0.0
	_death_overlay.visible = false
	root.add_child(_death_overlay)
	_death_overlay.add_child(UiKit.scrim(0.86, 0.86, 0.86))

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_death_overlay.add_child(column)
	column.add_child(UiKit.label("余 烬 熄 灭", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())
	column.add_child(UiKit.label("在最后点亮的余烬巢重燃…", &"DimLabel",
			HORIZONTAL_ALIGNMENT_CENTER))


func _process(delta: float) -> void:
	_time += delta
	_apply_letterbox()
	_tick_reveals(delta)
	if _announce_time > 0.0:
		_announce_time -= delta
		if _announce_time <= 0.0:
			if not _announce_queue.is_empty():
				_show_announce(_announce_queue.pop_front())
			else:
				_hide_banner()
	_sync_prompt()
	if _resonating:
		var glow := 0.55 + 0.45 * sin(TAU * _time / 0.35)
		_toxin_bar.modulate = Color(1.35, 0.82 + glow * 0.15, 0.38)
		_toxin_label.modulate = Color(1.25, 0.88, 0.5)
	elif _toxin_ratio >= TOXIN_ALARM_RATIO:
		var pulse := lerpf(TOXIN_PULSE_MIN, TOXIN_PULSE_MAX,
				0.5 + 0.5 * sin(TAU * _time / TOXIN_PULSE_PERIOD))
		_toxin_bar.modulate = Color(pulse, pulse, pulse)
		# 报警脉动只调亮度，不把档位色冲成灰白：炽是琥珀、溢是血红，闪起来仍读得出。
		var tint := TOXIN_TINT_OVERFLOW if _toxin_ratio >= 0.999 else TOXIN_TINT_HOT
		_toxin_label.modulate = Color(tint.r * pulse, tint.g * pulse, tint.b * pulse)
	if _low_hp and not _vignette_tween_active():
		_breath_time += delta
		_vignette.modulate.a = lerpf(VIGNETTE_BREATH_MIN, VIGNETTE_BREATH_MAX,
				0.5 + 0.5 * sin(TAU * _breath_time / VIGNETTE_BREATH_PERIOD))
	_tick_socket_breath()


## 空插座的铁环呼吸：只在"袋里有核、插座空着"时进行（_cores_owned 已含口袋
## 判定）。幅度压在 0.55-0.95 的 alpha 之间，静止画面上也读得出"这里等着镶"，
## 又不会和 ToxinBar 的报警脉动抢同一个节奏（那是 0.5s 一次，这是 2.4s）。
func _tick_socket_breath() -> void:
	var empty_pending := _cores_owned
	if not empty_pending:
		return
	for i in _sockets.size():
		var gem := _sockets[i].get_node_or_null("Icon/Gem") as TextureRect
		var ring := _sockets[i].get_node_or_null("Icon/Ring") as TextureRect
		if gem == null or ring == null or gem.visible:
			continue
		var breath := 0.55 + 0.40 * (0.5 + 0.5 * sin(TAU * _time / SOCKET_BREATH_PERIOD))
		ring.modulate = Color(0.78, 0.7, 0.62, breath)


# --- 电影黑边 -----------------------------------------------------------------

## 导演的黑边（Director.letterbox_amount 0..1，满格每侧 32 单位）一出现，HUD 就先于
## 黑边淡出并上滑；黑边退去后淡入。用 modulate 而不是 visible：暂停菜单管着 visible。
func _apply_letterbox() -> void:
	var factor := letterbox_factor()
	if not is_equal_approx(_root.modulate.a, factor):
		_root.modulate.a = factor
	var top := _stat_top() - LETTERBOX_SLIDE * (1.0 - factor)
	if not is_equal_approx(_stat.offset_top, top):
		_stat.offset_top = top


## 1 = 完全可见，0 = 完全让给黑边。
func letterbox_factor() -> float:
	return 1.0 - clampf(Director.letterbox_amount() / LETTERBOX_FADE_AT, 0.0, 1.0)


func _stat_top() -> float:
	return STAT_MARGIN.y + _insets.y


# --- 次要信息：目标 / 天气 / 剑核名 -------------------------------------------

func peek_active() -> bool:
	return _peek_timer > 0.0 or Input.is_key_pressed(KEY_TAB)


## 触屏轻点状态带，或测试直接调用。
func peek_for(seconds: float = PEEK_TAP_HOLD) -> void:
	_peek_timer = maxf(_peek_timer, seconds)


func _on_plate_input(event: InputEvent) -> void:
	var tapped := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if tapped:
		peek_for()
		_plate.accept_event()


func _tick_reveals(delta: float) -> void:
	var peek := peek_active()
	_peek_timer = maxf(0.0, _peek_timer - delta)
	if peek and not _peek_was_on:
		_objective_refresh = 0.0
		_refresh_atmosphere()
		# 玩家已经自己按开"查看"了：那条"按 Tab 查看"的教学提示教完就该退场，
		# 不再继续横在画面顶部等它自己超时。
		if _hints != null:
			_hints.dismiss_if(&"peek")
	_peek_was_on = peek
	_atmos_time = maxf(0.0, _atmos_time - delta)
	_objective_time = maxf(0.0, _objective_time - delta)
	if _objective_delay > 0.0:
		_objective_delay -= delta
		if _objective_delay <= 0.0:
			_show_objective()
	var objective_wanted := peek or _objective_time > 0.0
	if objective_wanted:
		_objective_refresh -= delta
		if _objective_refresh <= 0.0:
			_objective_refresh = OBJECTIVE_REFRESH
			_refresh_objective()
	_atmos_alpha = move_toward(_atmos_alpha, 1.0 if (peek or _atmos_time > 0.0) else 0.0,
			delta * REVEAL_SPEED)
	_objective_alpha = move_toward(_objective_alpha,
			1.0 if (objective_wanted and _objective_label.text != "") else 0.0, delta * REVEAL_SPEED)
	_peek_alpha = move_toward(_peek_alpha, 1.0 if (peek and _cores_owned) else 0.0,
			delta * REVEAL_SPEED)
	_atmos_label.modulate.a = _atmos_alpha
	_objective_label.modulate.a = _objective_alpha
	_objective_label.visible = _objective_alpha > 0.01
	_socket_label.modulate.a = _peek_alpha
	_socket_label.visible = _peek_alpha > 0.01


func _show_atmosphere() -> void:
	_atmos_time = ATMOS_HOLD


func _show_objective() -> void:
	_objective_time = OBJECTIVE_HOLD
	_objective_refresh = 0.0


func _refresh_objective() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	if not _tracker.has_scanned():
		_tracker.scan(GameContext.world_root(player))
	_objective_label.text = _tracker.line(player, _boss_name)
	_fit_wrapped(_objective_label, _objective_label.text, OBJECTIVE_MAX_WIDTH)


## 当前显示的目标行（测试用）。
func objective_text() -> String:
	return _objective_label.text


## 量一行字在设计像素里的自然宽度。字体与字号都从主题取，12/24/36 的像素栅格不变。
func _text_width(label: Label, text: String) -> float:
	if label == null or text == "":
		return 0.0
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


## 单行文案的边界：短句保持自然宽，长句压到 max_width 并用省略号收尾。
## 只对实际超长的文本打开 clip，避免短提示被无谓地裁掉阴影 / 末字。
func _fit_single_line(label: Label, text: String, max_width: float) -> void:
	if label == null:
		return
	var width := _text_width(label, text)
	var clipped := width > max_width
	label.max_lines_visible = 1
	label.clip_text = clipped
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS \
			if clipped else TextServer.OVERRUN_NO_TRIMMING
	label.custom_minimum_size.x = minf(width, max_width)


## 目标行可以折行，但最多两行；短句不折，保持和状态带同一行的紧凑节奏。
func _fit_wrapped(label: Label, text: String, max_width: float) -> void:
	if label == null:
		return
	var width := _text_width(label, text)
	var wrapped := width > max_width
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrapped else TextServer.AUTOWRAP_OFF
	label.max_lines_visible = 2 if wrapped else -1
	label.custom_minimum_size.x = minf(width, max_width)


func _on_chapter_started(_level_id: String) -> void:
	_tracker = ObjectiveTracker.new()
	_objective_delay = 0.0
	_show_objective()
	_show_atmosphere()


# --- 血量 ---------------------------------------------------------------------

## 一颗心 = 深色插槽 + 2 倍放大的像素心。插槽让血量在明亮场景里也读得出来。
func _make_heart() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = HEART_SLOT_SIZE
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot := UiKit.sprite_rect(UiKit.TEX_HEART_SLOT)
	slot.name = "Slot"
	wrap.add_child(slot)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = _heart_full
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = (HEART_SLOT_SIZE - HEART_SIZE) * 0.5
	icon.size = HEART_SIZE
	wrap.add_child(icon)
	return wrap


func _on_hp(current: int, maximum: int) -> void:
	while _hearts_row.get_child_count() < maximum:
		_hearts_row.add_child(_make_heart())
	while _hearts_row.get_child_count() > maximum:
		var extra := _hearts_row.get_child(_hearts_row.get_child_count() - 1)
		_hearts_row.remove_child(extra)
		extra.queue_free()
	var lost := _hp_shown > current
	for i in _hearts_row.get_child_count():
		var icon := _hearts_row.get_child(i).get_node_or_null("Icon") as TextureRect
		if icon == null:
			continue
		var alive := i < current
		icon.texture = _heart_full if alive else _heart_empty
		icon.modulate = Color(1, 1, 1, 1.0 if alive else 0.5)
		# 刚刚熄灭的那颗心闪一下白，把掉血读成一次事件而不是静默变化。
		if lost and not alive and i < _hp_shown:
			_flash(icon)
	_hp_shown = current
	if current <= 1 and not _low_hp:
		_low_hp = true
		_show_vignette()
	elif current > 1 and _low_hp:
		_low_hp = false
		_hide_vignette()


func _flash(icon: TextureRect) -> void:
	icon.modulate = Color(2.4, 2.0, 1.8, 1.0)
	var tween := create_tween()
	tween.tween_property(icon, "modulate", Color(1, 1, 1, 0.5), HEART_FLASH)


func _show_vignette() -> void:
	_vignette.visible = true
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "modulate:a", VIGNETTE_ALPHA, VIGNETTE_FADE_IN)
	_vignette_tween.finished.connect(func() -> void: _breath_time = 0.0)


func _hide_vignette() -> void:
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "modulate:a", 0.0, VIGNETTE_FADE_OUT)
	_vignette_tween.tween_callback(func() -> void: _vignette.visible = false)


func _vignette_tween_active() -> bool:
	return _vignette_tween != null and _vignette_tween.is_valid() and _vignette_tween.is_running()


# --- 毒素 ---------------------------------------------------------------------

func _on_toxin(current: float, maximum: float) -> void:
	var t := 0.0 if maximum <= 0.0 else current / maximum
	_toxin_ratio = t
	_toxin_bar.value = t * 100.0
	var band := ToxinMeter.band_for(current, maximum)
	_toxin_bar.theme_type_variation = toxin_bar_variation(band)
	_toxin_label.text = "%s %d%%" % [ToxinMeter.band_label_for(band), int(t * 100.0)]
	if band == &"hot":
		_toxin_label.modulate = TOXIN_TINT_HOT
	elif band == &"warm":
		_toxin_label.modulate = TOXIN_TINT_WARM
	else:
		_toxin_label.modulate = Color.WHITE
	# 80% 以上的报警脉动由 _process 管；掉回报警线以下要立刻收掉上一次脉动的残留
	# 亮度，否则条会停在半亮的颜色上，看上去像"还满着"。
	if t < TOXIN_ALARM_RATIO:
		_toxin_bar.modulate = Color.WHITE


## 毒素档位 → 量槽样式变体（冷=毒绿、温/炽=余烬、溢=血红）。条本身换色，
## 玩家不用读 12px 的档位字也知道自己烧到哪一档了。
static func toxin_bar_variation(band: StringName) -> StringName:
	match band:
		&"overflow":
			return &"ToxinBarOverflow"
		&"hot":
			return &"ToxinBarHot"
		&"warm":
			return &"ToxinBarWarm"
	return &"ToxinBarCold"


# --- Boss ---------------------------------------------------------------------

func _on_boss_appeared(boss_name: String, current_hp: int, max_hp: int) -> void:
	if _boss_bar_panel == null:
		return
	_boss_name = boss_name
	_boss_max_hp = maxi(1, max_hp)
	_boss_title_label.text = boss_name
	_fit_single_line(_boss_title_label, boss_name, BOSS_TITLE_MAX_WIDTH)
	_boss_hp_bar.max_value = float(_boss_max_hp)
	_boss_hp_bar.value = float(current_hp)
	_boss_phase_pips.set_count(1)
	_boss_bar_panel.modulate.a = 0.0
	_boss_bar_panel.visible = true
	_sync_prompt_offsets()
	var tw := create_tween()
	tw.tween_property(_boss_bar_panel, "modulate:a", 1.0, 0.6)


## 二阶段起血条的名字旁多一只菱形：和过场名号卡同一套刻度，抬头就知道升相了。
func _on_boss_phase_changed(_boss_name: String, phase: int) -> void:
	if _boss_phase_pips == null:
		return
	_boss_phase_pips.set_count(phase)


func _on_boss_hp_changed(current_hp: int, max_hp: int) -> void:
	if _boss_hp_bar == null:
		return
	if max_hp > 0:
		_boss_max_hp = max_hp
		_boss_hp_bar.max_value = float(max_hp)
	var tw := create_tween()
	tw.tween_property(_boss_hp_bar, "value", float(current_hp), 0.15)


func _on_boss_defeated() -> void:
	_boss_name = ""
	if _boss_phase_pips != null:
		_boss_phase_pips.set_count(0)
	if _boss_bar_panel == null or not _boss_bar_panel.visible:
		return
	var tw := create_tween()
	tw.tween_property(_boss_bar_panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		_boss_bar_panel.visible = false
		_sync_prompt_offsets())


# --- 交互提示 / 播报 ----------------------------------------------------------

func _on_prompt(text: String) -> void:
	_prompt_text = text
	if _prompt_label == null:
		_sync_prompt()
		return
	var parts := KeyLabels.prompt_parts(text)
	_prompt_key_label.text = String(parts.key)
	_prompt_key_panel.visible = String(parts.key) != ""
	_prompt_label.text = String(parts.body)
	_fit_single_line(_prompt_label, _prompt_label.text, PROMPT_MAX_WIDTH)
	_sync_prompt()
func _sync_prompt() -> void:
	if _prompt_panel == null:
		return
	var cap := Director.caption()
	var cap_busy := cap != null and cap.is_busy()
	var dead := _death_overlay != null and _death_overlay.visible
	var want := _prompt_text != "" and not cap_busy and not dead
	var was := _prompt_panel.visible
	_prompt_panel.visible = want
	if want and not was:
		_play_prompt_intro()
	_sync_prompt_offsets()


## 交互提示的出场：从下方 6px 处浮上来并淡入。位置取整到像素栅格，
## 1-bit 的墨带边缘不会出现半像素灰边。重复触发（换一个可交互物）时
## 先掐掉上一段，避免两段 tween 抢同一个属性。
func _play_prompt_intro() -> void:
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_prompt_panel.modulate.a = 0.0
	var base_top := _prompt_panel.offset_top
	_prompt_panel.offset_top = base_top + PROMPT_SLIDE
	_prompt_tween = create_tween()
	_prompt_tween.set_parallel(true)
	_prompt_tween.tween_property(_prompt_panel, "modulate:a", 1.0, PROMPT_FADE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_prompt_tween.tween_property(_prompt_panel, "offset_top", base_top, PROMPT_FADE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 交互提示贴底边；Boss 条在场时抬到它之上。底边再让开触屏安全区。
func _sync_prompt_offsets() -> void:
	var lift := (BOSS_BAR_LIFT + (12.0 if _small_window else 0.0)) if _boss_bar_panel != null and _boss_bar_panel.visible else 0.0
	var bottom := PROMPT_BOTTOM + _insets.w + lift
	_prompt_panel.offset_top = -bottom
	_prompt_panel.offset_bottom = -bottom


func _on_announce(text: String) -> void:
	if text == "":
		return
	if _announce_time > 0.0 and _announce_label.text != "":
		if _announce_queue.size() < 2:
			_announce_queue.append(text)
		return
	_show_announce(text)


## 横幅只有一条补间：每次显示 / 隐藏先杀掉上一条，否则上一次淡出末尾的"清文字"
## 回调会在新播报已经亮起之后把它擦成空白条。
func _show_announce(text: String) -> void:
	# 碑文之类的播报可能带作者换行；横幅是单行铁牌，先压成一行再量宽度。
	var line := text.replace("\r", " ").replace("\n", " ").strip_edges()
	if line == "":
		return
	_announce_label.text = line
	_fit_single_line(_announce_label, line, BANNER_MAX_WIDTH)
	_announce_time = ANNOUNCE_HOLD
	_kill_banner_tween()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, ANNOUNCE_FADE)


func _kill_banner_tween() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = null


func _on_resonance(active: bool) -> void:
	_resonating = active
	if not active and _toxin_ratio < TOXIN_ALARM_RATIO:
		_toxin_bar.modulate = Color.WHITE
		_toxin_label.modulate = Color.WHITE


func _hide_banner() -> void:
	_kill_banner_tween()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, ANNOUNCE_FADE)
	_banner_tween.tween_callback(_clear_banner_text)


func _clear_banner_text() -> void:
	if _announce_time <= 0.0:
		_announce_label.text = ""


## 当前横幅文字与透明度（测试用）。
func banner_text() -> String:
	return _announce_label.text


func banner_alpha() -> float:
	return _banner.modulate.a


func _on_player_died() -> void:
	if _pause != null and _pause.is_open():
		_pause.close()
	_death_overlay.visible = true
	_sync_prompt()
	var tween := create_tween()
	tween.tween_property(_death_overlay, "modulate:a", 1.0, 0.45)


# --- 天气时辰 / 剑核 / 安全区 -------------------------------------------------

func _exit_tree() -> void:
	_disconnect_if(WorldClock.phase_changed, _on_phase_changed)
	_disconnect_if(WorldClock.weather_changed, _on_weather_changed)
	_disconnect_if(WorldClock.zone_changed, _on_zone_changed)
	_disconnect_if(Settings.changed, _on_setting_changed)
	var window := get_tree().root if get_tree() != null else null
	if window != null:
		_disconnect_if(window.size_changed, _apply_safe_area)


static func _disconnect_if(sig: Signal, target: Callable) -> void:
	if sig.is_connected(target):
		sig.disconnect(target)


func _on_phase_changed(_value: int = 0) -> void:
	_refresh_atmosphere()
	_show_atmosphere()


func _on_zone_changed(_value: int = 0) -> void:
	_refresh_atmosphere()
	_show_atmosphere()


## 天气自己换（每 50-110 秒一次）只更新文字，不抢画面。
func _on_weather_changed(_value: int = 0) -> void:
	_refresh_atmosphere()


func _refresh_atmosphere() -> void:
	if _atmos_label == null:
		return
	_atmos_label.text = WorldClock.hud_line()


func _on_setting_changed(key: StringName) -> void:
	if key == &"keys":
		_refresh_socket_keys()
		_on_prompt(_prompt_text)


func _on_core_inserted(_core: Resource, _index: int) -> void:
	_refresh_cores()


func _on_core_acquired(_core: Resource) -> void:
	_refresh_cores()


func _refresh_socket_keys() -> void:
	for i in _sockets.size():
		var key := _sockets[i].get_node_or_null("Key") as Label
		if key != null:
			key.text = KeyLabels.label(StringName("socket_%d" % (i + 1)))


func _refresh_cores() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var inv := player.inventory
	var names := PackedStringArray()
	for i in _sockets.size():
		var core := inv.socket_core(i)
		var gem := _sockets[i].get_node("Icon/Gem") as TextureRect
		var ring := _sockets[i].get_node("Icon/Ring") as TextureRect
		gem.visible = core != null
		if core != null:
			gem.modulate = core.tint
			ring.modulate = Color(1.0, 0.86, 0.62, 1.0)
			_cores_owned = true
			names.append(AbilityIds.display_name(core.ability_id))
		else:
			ring.modulate = Color(0.78, 0.7, 0.62, 0.8)
			names.append("-")
	var pouch := inv.pouch.size()
	if pouch > 0:
		_cores_owned = true
	_pouch_label.text = "袋中 %d" % pouch
	_pouch_label.visible = pouch > 0
	_socket_strip.visible = _cores_owned
	_socket_label.text = "剑核  %s" % " · ".join(names)


## 触屏刘海 / 圆角的安全区（设计单位，已换算到 HUD 层坐标）。桌面与 headless 为零。
## 只在窗口尺寸变化时重算，不逐帧问 DisplayServer。
func _apply_safe_area() -> void:
	_apply_readable_text(get_tree().root.size)
	apply_safe_insets(PresentationMetrics.safe_layer_insets(get_tree().root))


## The 640px world picture uses half-size UI at a small window. Promote critical
## readouts to 24 design pixels there so Chinese glyphs retain 12 physical pixels.
## Secondary weather copy still appears only on request; the world pixel grid stays intact.
## A headless root is a 64x64 stub that PresentationMetrics clamps up to 640x360,
## which would read as "1x window": require a genuine window (>= 640x360) before
## promoting, so headless layout tests keep the desktop typography.
func _apply_readable_text(window_size: Vector2i) -> void:
	var genuine := window_size.x >= 640 and window_size.y >= 360
	_small_window = genuine and int(PresentationMetrics.calculate(window_size)["scale"]) == 1
	var labels: Array[Label] = [_toxin_label, _objective_label, _socket_label,
		_pouch_label, _boss_title_label]
	for socket in _sockets:
		labels.append(socket.get_node("Key") as Label)
	for label in labels:
		if label == null: continue
		var id := label.get_instance_id()
		if not _critical_font_sizes.has(id):
			_critical_font_sizes[id] = label.get_theme_font_size("font_size")
		var base: int = _critical_font_sizes[id]
		label.add_theme_font_size_override("font_size", maxi(base, 24) if _small_window else base)
	if _toxin_label != null:
		(_toxin_label.get_parent() as Control).custom_minimum_size = Vector2(
			TOXIN_LABEL_WIDTH, TOXIN_ROW_HEIGHT) * (2.0 if _small_window else 1.0)
	if _boss_bar_panel != null:
		_boss_bar_panel.custom_minimum_size.y = BOSS_BAR_HEIGHT + (12.0 if _small_window else 0.0)


## 把一组安全区边距摆进 HUD 各条：状态带 / 横幅 / 天气行 / Boss 条 / 交互提示。
## 公开是为了让 headless 测试能喂一组手机刘海进来验证排版（真实刘海值只有设备知道）。
func apply_safe_insets(insets: Vector4) -> void:
	if _stat == null:
		return
	_insets = insets
	_stat.offset_left = STAT_MARGIN.x + insets.x
	_stat.offset_top = _stat_top()
	_banner.offset_top = BANNER_TOP + insets.y
	_atmos_label.offset_right = -(18.0 + insets.z)
	_atmos_label.offset_left = _atmos_label.offset_right - 282.0
	_atmos_label.offset_top = 14.0 + insets.y
	_atmos_label.offset_bottom = 32.0 + insets.y
	if _hints != null:
		_hints.set_top(HintService.TOP + insets.y)
	var bottom := 22.0 + insets.w
	_boss_bar_panel.offset_top = -(bottom + BOSS_BAR_HEIGHT + (12.0 if _small_window else 0.0))
	_boss_bar_panel.offset_bottom = -bottom
	_sync_prompt_offsets()


# --- 测试 / 工具用的读数 ------------------------------------------------------

## 状态带本体（心 + 毒素槽）在 HUD 层坐标里的矩形，不含剑核插座与下方说明行。
func plate_rect() -> Rect2:
	return _plate.get_global_rect()


## 左上角整簇（含插座）的矩形；可见的说明行也算在内。
func cluster_rect() -> Rect2:
	var rect := _plate.get_global_rect()
	if _socket_strip.visible:
		rect = rect.merge(_socket_strip.get_global_rect())
	if _objective_label.visible:
		rect = rect.merge(_objective_label.get_global_rect())
	if _socket_label.visible:
		rect = rect.merge(_socket_label.get_global_rect())
	return rect


func hint_service() -> HintService:
	return _hints


## 交互提示当前显示的键帽文字（"" = 这条提示不带键位）。测试用。
func prompt_key_text() -> String:
	return _prompt_key_label.text if _prompt_key_label != null and _prompt_key_panel.visible else ""


## 交互提示的正文（不含键帽）。
func prompt_body_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""


## Boss 血条旁当前的相数刻度数量（0 = 没有 Boss / 已击败）。
func boss_phase_count() -> int:
	return _boss_phase_pips.count if _boss_phase_pips != null else 0


## Boss 血条里名字与刻度所在的横向行，测试用（两者必须装在 460 设计像素内）。
func boss_title_row() -> Control:
	return _boss_title_label.get_parent() as Control if _boss_title_label != null else null


## Boss 血条里的相数刻度控件。
func boss_phase_pips() -> PhasePips:
	return _boss_phase_pips


## Boss 血条里的 HP 条（主题变体 BossHpBar，余烬色填充）。
func boss_hp_bar() -> ProgressBar:
	return _boss_hp_bar


## Boss 血条在 HUD 层坐标里的矩形（含名字与刻度）。
func boss_bar_rect() -> Rect2:
	return _boss_bar_panel.get_global_rect()


## 低血量血雾当前透明度（测试用：读数在 0.18..0.38 之间才算"看得见但不盖住画面"）。
func vignette_alpha() -> float:
	return _vignette.modulate.a


## Boss 血条里的相数刻度：与过场名号卡同一套 8px 菱形，第 N 相就有 N 只。
## 纯 _draw，不做几何缩放；数量为 0 时只占一格宽度，血条不会因为升相而跳动。
class PhasePips extends Control:
	var count := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_count(0)

	func set_count(value: int) -> void:
		count = maxi(0, value)
		var slots := maxi(count, 1)
		custom_minimum_size = Vector2(slots * BOSS_PIP + maxf(0.0, slots - 1) * BOSS_PIP_GAP,
				BOSS_PIP + 4.0)
		queue_redraw()

	func _draw() -> void:
		for i in count:
			var c := Vector2(i * (BOSS_PIP + BOSS_PIP_GAP) + BOSS_PIP * 0.5, size.y * 0.5)
			var pts := PackedVector2Array([
				c + Vector2(0.0, -BOSS_PIP * 0.5),
				c + Vector2(BOSS_PIP * 0.5, 0.0),
				c + Vector2(0.0, BOSS_PIP * 0.5),
				c + Vector2(-BOSS_PIP * 0.5, 0.0),
			])
			draw_colored_polygon(pts, UiKit.EMBER)
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#2A1E32"), 1.0)
