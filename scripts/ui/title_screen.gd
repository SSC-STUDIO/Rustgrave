class_name TitleScreen
extends Control
## 标题屏（v3）：一幅实时点光的像素场景（TitleWorld，640x360 SubViewport）+ 轻量版式。
##
## 场景：余烬骑士背着巨剑站在铁桥上，天窗落下光柱，巨齿轮缓缓转动，几盏吊灯随存档
## 进度点亮（见 TitleWorld：无存档 / 进行中按幕调色 / 三种结局各一幅）。场景经由原有的
## `Keyart` TextureRect 显示（同一套像素平滑着色器，和游戏里的世界图一致）。
##
## 版式（1280x720 设计空间）：字标居中偏上，"锻入"式显现（白热 → 锈色扫过 + 火星），
## 副题随后淡入；菜单是左下一列压暗的"铁条"（行动 / 模式 / 系统 / 离开四组，每行
## 52px 触控高度，余烬光标；聚焦时在条上迸火星并让场景轻推一下）；右侧是"旅程标尺"：
## 14 个章节刻度（已通关亮、当前搏动）+ 四枚小数据片（阶位 / 外观 / 试炼 / 竞技场），
## 悬停或按 Tab 展开完整档案；底部是慢速打字机轮换的墓志，署名收成页脚一行。
##
## 动效：开屏（吊灯逐盏点亮 → 字标锻入 → 菜单逐条落位，可被 _skip_intro 一把跳过，
## 不是输入门禁）、确认入场（白热闪光 + 镜头前推 + 淡出）、离开（吊灯一盏盏熄灭，
## 只剩巨剑剪影，再浮出墓志）。
##
## 菜单由 MenuList 负责键鼠导航，操作说明复用 ControlsPanel（与暂停菜单同一份）。
## USE_LIVE_SCENE=false 时退回旧的静态 keyart（同一个 Keyart 节点）。

const KEYART_PATH := "res://assets/kenney_clean/backgrounds/title_keyart.png"
## The title shows a live, lit pixel scene (TitleWorld) instead of the static key art.
## Flip to false to fall back to the old keyart in the same `Keyart` TextureRect.
const USE_LIVE_SCENE := true
const WORLD_SCENE := "res://scenes/ui/TitleWorld.tscn"
const SMOOTH_SHADER := preload("res://assets/shaders/pixel_smooth.gdshader")
const FORGE_SHADER := preload("res://assets/shaders/title_forge.gdshader")
const LEVEL_PATH := "res://scenes/levels/Level01_Static.tscn"
const Transitions := preload("res://scripts/ui/ui_transition.gd")
const KnightLightScript := preload("res://scripts/ui/keyart_knight_light.gd")
## 回火试炼（新游戏模式）：入口由战役解锁旗标控制（契约 §5）。
const TrialCatalogScript := preload("res://scripts/data/trial_catalog.gd")
const TrialRecordsScript := preload("res://scripts/data/trial_records.gd")
const EmberRankScript := preload("res://scripts/data/ember_rank.gd")
const ArenaRunScript := preload("res://scripts/autoload/arena_run.gd")
const SkinCatalogScript := preload("res://scripts/data/skin_catalog.gd")
const TRIAL_MENU := "res://scenes/ui/TrialMenu.tscn"

## 墓志取「失败的净化偶自己先锈透」。一句，不是台词。
const EPITAPH := "失败的净化偶，自己先锈透了。"
const FADE_OUT := 0.7
const LOGO_BREATH_PERIOD := 3.2
# fallback (static keyart) atmosphere
const EMBERS_RISING := 30
const EMBERS_FALLING := 14
const KEYART_BREATH_PERIOD := 5.5
const CORNER_INSET := 16.0
const BAND_HEIGHT := 34.0

# ---- layout (design px, 1280x720) -------------------------------------------------
const TOP_INSET := 28.0
const LOGO_H := 110.0
const SUBTITLE_H := 30.0
## 左下菜单：七行 x 52 + 三道组间距 16 = 412；底边 666，"离开"行中心 640。
const RAIL_X := 72.0
const RAIL_TOP := 254.0
const GROUP_GAP := 16.0
const QUIT_CENTER_Y := 640.0
## 右侧旅程列。
const JOURNEY_X := 1000.0
const JOURNEY_Y := 188.0
const JOURNEY_W := 208.0
const JOURNEY_H := 420.0
## 展开的档案卡（收起时停在右侧 CARD_SLIDE 处不可见，展开时滑回）。
const CARD_RECT := Rect2(820.0, 184.0, 388.0, 424.0)
const CARD_SLIDE := 24.0
## 墓志行（与"离开"行同一条中心线）。
const EPITAPH_RECT := Rect2(688.0, 624.0, 520.0, 32.0)
const FOOTER_RECT := Rect2(72.0, 688.0, 1136.0, 28.0)

# ---- motion ------------------------------------------------------------------------
const BOOT_FADE := 0.5
const LOGO_AT := 0.45
const LOGO_TIME := 0.95
const MENU_AT := 1.45
const MENU_STAGGER := 0.07
const MENU_LAND := 0.26
const EPITAPH_CHAR := 0.085
const EPITAPH_HOLD := 5.5
const EPITAPH_FADE := 0.7
## 离开锈墓：吊灯一盏盏熄灭 → 只剩巨剑剪影 → 留一句墓志才退出。任何按键/点击都能立刻跳到退出。
const QUIT_ROW_STAGGER := 0.055
const QUIT_RAIL_FADE := 0.30
const QUIT_SCENE_FADE := 0.55
const QUIT_CAPTION_FADE := 0.35
const QUIT_HOLD := 0.7
const QUIT_CAPTION := "余 烬 熄 灭。"

const ID_NEW := &"new"
const ID_CONTINUE := &"continue"
const ID_TRIAL := &"trial"
const ID_ARENA := &"arena"
const ID_SETTINGS := &"settings"
const ID_CONTROLS := &"controls"
const ID_QUIT := &"quit"
const ID_KEEP := &"keep"
const ID_OVERWRITE := &"overwrite"
const ID_UPDATE := &"update"

## Instance switch (tests set it before add_child); defaults to the USE_LIVE_SCENE const.
var live_scene_enabled: bool = USE_LIVE_SCENE
## 测试开关：置 false 时把退出动画完整走一遍，但不真的结束进程（headless 套件用）。
var quit_on_finish := true
## 测试接缝：替换 ArenaRun.start()（返回是否真的开始了一场）。
var arena_start: Callable = Callable()

var _started := false
var _time := 0.0
var _look: Dictionary = {}
var _world_viewport: SubViewport
var _world: TitleWorld
var _smooth_material: ShaderMaterial
var _keyart: TextureRect
var _masthead: Control
var _logo: TextureRect
var _logo_material: ShaderMaterial
var _subtitle: Label
var _menu: MenuList
var _controls: ControlsPanel
var _recap: CanvasLayer
var _settings: SettingsScreen
var _confirm: CanvasLayer
var _confirm_menu: MenuList
var _char_select: CharacterSelectScreen
var _update_prompt: UpdatePrompt
var _update_notice: Button
var _fade: ColorRect
var _quit_caption: Label
var _quitting := false
var _quit_done := false
var _quit_tween: Tween
## 开屏黑幕：整段开场里盖在最上层的纯黑矩形，播完即撤。
var _curtain: ColorRect
var _intro_playing := false
var _intro_tween: Tween
var _knight_light: Control
var _ui_sparks: TitleSparks

# journey column
var _journey: Control
var _gauge: TitleGauge
var _chips: Dictionary = {}
var _journey_count: Label
var _journey_chapter: Label
var _journey_recap: Label
var _card: TitleCard
var _dossier_values: Dictionary = {}
var _dossier_recap: Label
var _dossier_open := false
var _dossier_pinned := false
var _card_tween: Tween

# epitaph typewriter
var _epitaph: Label
var _ep_lines: PackedStringArray = []
var _ep_index := 0
var _ep_phase := 0            # 0 idle, 1 typing, 2 holding, 3 fading
var _ep_t := 0.0

var _pointer_seen := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 标题屏是根窗口里的普通 Control（不在 GamePresentation 下）。套上同一条
	# 整数内容矩形，非 16:9 窗口才会和游戏中 UI 一样留黑边，而不是被拉满。
	PresentationMetrics.bind_control(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	DisplayServer.window_set_title("Rustgrave")
	_build_window_backdrop()
	_look = TitleWorld.state_from_save()
	# 标题屏自己的主题：Music 的契约要求在这里显式声明（_poll_world 的轮询只是兜底）。
	# set_state(&"calm") 清掉上一局残留的 danger / boss / death 闭锁。
	Music.set_state(&"calm")
	Music.set_theme(&"title")
	DisplayFit.apply()
	WorldClock.hold_for_menu()
	# 音频包若提供了标题环境床（炉厅低鸣），开着它；没有就什么都不做。
	if Sfx.has_method(&"set_title_bed"):
		Sfx.call(&"set_title_bed", true)
	_build_backdrop()
	_build_masthead()
	_build_rail()
	_build_journey()
	_build_inscription()
	_build_chrome()
	_build_ui_sparks()
	# 覆盖层最后加：Control 的绘制与鼠标拾取都按子节点顺序，越后越上。
	_build_overlays()
	# 新版本检查：静默拉一次 manifest，结果只让页脚多一个按钮，
	# 不弹窗、不打断。检查失败/没有新版时保持原样。
	UpdateService.checked.connect(_on_update_checked)
	UpdateService.check_async()
	_play_intro()


## 内容矩形之外的留边：GamePresentation 用黑底垫世界图，标题屏也必须一致，
## 否则非 16:9 窗口会露出项目清屏色（暗紫）而不是黑边。
func _build_window_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WindowBackdrop"
	layer.layer = -10
	add_child(layer)
	var black := ColorRect.new()
	black.name = "Black"
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)


func _build_backdrop() -> void:
	_keyart = TextureRect.new()
	_keyart.name = "Keyart"
	_keyart.set_anchors_preset(Control.PRESET_FULL_RECT)
	_keyart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_keyart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_keyart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keyart)
	if live_scene_enabled:
		_build_live_world()
		# 字标压在顶部、菜单压在左下：只轻轻压暗这两处，中段（骑士与光柱）留给场景。
		add_child(UiKit.scrim(0.58, 0.0, 0.50))
		add_child(UiKit.scrim_side(0.30, 520.0))
		# the journey column hangs over the right-hand machinery: darken that edge too
		var right_scrim := UiKit.scrim_side(0.42, 420.0)
		right_scrim.flip_h = true
		right_scrim.anchor_left = 1.0
		right_scrim.anchor_right = 1.0
		right_scrim.offset_left = -420.0
		right_scrim.offset_right = 0.0
		add_child(right_scrim)
		return
	_keyart.texture = UiKit.tex(KEYART_PATH)
	# 旧版静态 keyart 的氛围：上下压暗 + 骑士光影 + 余烬 + 角饰。
	add_child(UiKit.scrim(0.74, 0.26, 0.90))
	add_child(UiKit.scrim_side(0.42, 780.0))
	_knight_light = KnightLightScript.new()
	add_child(_knight_light)
	add_child(UiKit.EmberField.build(Rect2(Vector2.ZERO, Vector2(1280, 720)),
			EMBERS_RISING, EMBERS_FALLING))
	UiKit.corner_brackets(self, CORNER_INSET, BAND_HEIGHT + CORNER_INSET)


## The live scene: a 640x360 SubViewport (same recipe as GamePresentation's world) holding
## a TitleWorld, shown through the existing `Keyart` TextureRect + pixel-smoothing shader.
func _build_live_world() -> void:
	_world_viewport = SubViewport.new()
	_world_viewport.name = "WorldViewport"
	_world_viewport.size = PresentationMetrics.WORLD_SIZE
	_world_viewport.world_2d = World2D.new()
	_world_viewport.disable_3d = true
	_world_viewport.snap_2d_transforms_to_pixel = true
	_world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_world_viewport)
	var packed := load(WORLD_SCENE) as PackedScene
	_world = packed.instantiate() as TitleWorld
	_world.state = _look
	_world_viewport.add_child(_world)
	_keyart.texture = _world_viewport.get_texture()
	_smooth_material = ShaderMaterial.new()
	_smooth_material.shader = SMOOTH_SHADER
	_smooth_material.set_shader_parameter("smoothing",
			bool(Settings.value(&"pixel_smoothing", GamePresentation.pixel_smoothing)))
	_keyart.material = _smooth_material
	get_tree().root.size_changed.connect(_update_smooth_scale)
	_update_smooth_scale()


func _update_smooth_scale() -> void:
	if _smooth_material == null:
		return
	var metrics := PresentationMetrics.for_window(get_tree().root)
	_smooth_material.set_shader_parameter("scale_hint", int(metrics["scale"]))


## 顶部正中：字标夹在副题上面，整块居中。
func _build_masthead() -> void:
	var column := VBoxContainer.new()
	column.name = "MastheadColumn"
	column.set_anchors_preset(Control.PRESET_TOP_WIDE)
	column.offset_top = TOP_INSET
	column.offset_bottom = TOP_INSET + LOGO_H + 8.0 + SUBTITLE_H
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_masthead = HBoxContainer.new()
	_masthead.name = "Masthead"
	(_masthead as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_masthead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_masthead)

	_logo = UiKit.sprite_rect(UiKit.TEX_TITLE_LOGO)
	_logo.name = "TitleLogo"
	_pack(_logo)
	_logo_material = ShaderMaterial.new()
	_logo_material.shader = FORGE_SHADER
	_logo_material.set_shader_parameter("progress", 1.0)
	_logo.material = _logo_material
	_masthead.add_child(_logo)

	_subtitle = UiKit.label("锈 墓 · 余 烬 骑 士", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.name = "Subtitle"
	_subtitle.custom_minimum_size = Vector2(0.0, SUBTITLE_H)
	_pack(_subtitle)
	column.add_child(_subtitle)


## 左下菜单：压暗的铁条分四组。行距用空白节点而不是容器 separation。
func _build_rail() -> void:
	_menu = MenuList.new()
	_menu.name = "Menu"
	_menu.strip_style = true
	_menu.add_theme_constant_override("separation", 0)
	_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu.position = Vector2(RAIL_X, RAIL_TOP)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)

	var has_save := SaveData.has_save()
	# 行动
	_menu.add_item(ID_NEW, "点 燃 余 烬", false, MenuItem.Kind.PRIMARY, true)
	var cont := "回 看 余 烬" if SaveData.peek_ending() != "" else "继 续 旅 程"
	_menu.add_item(ID_CONTINUE, cont, not has_save, MenuItem.Kind.PRIMARY, true)
	_gap(GROUP_GAP)
	# 模式
	var trial_ready := TrialCatalogScript.unlocked()
	var trial_item := _menu.add_item(ID_TRIAL, "回 火 试 炼", not trial_ready, MenuItem.Kind.SECONDARY, true)
	if not trial_ready:
		trial_item.set_note("第七章后解锁")
	_menu.add_item(ID_ARENA, "余 烬 竞 技 场", false, MenuItem.Kind.SECONDARY, true)
	_gap(GROUP_GAP)
	# 系统
	_menu.add_item(ID_SETTINGS, "设 置", false, MenuItem.Kind.SECONDARY, true)
	_menu.add_item(ID_CONTROLS, "操 作 说 明", false, MenuItem.Kind.SECONDARY, true)
	_gap(GROUP_GAP)
	# 离开
	_menu.add_item(ID_QUIT, "离 开 锈 墓", false, MenuItem.Kind.GHOST, true)
	_menu.reset_size()
	_menu.chosen.connect(_on_chosen)
	_menu.focus_changed.connect(_on_focus_changed)
	# 有存档时光标默认停在"继续"：回车不会再一键抹掉进度。
	if has_save:
		_menu.select(1, false)


func _gap(height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(spacer)


func _pack(node: Control) -> void:
	node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER


# ------------------------------------------------------------------ journey ----

## 右侧旅程列：章节标尺 + 四枚小数据片；悬停 / Tab 展开完整档案卡。
func _build_journey() -> void:
	_journey = Control.new()
	_journey.name = "JourneyColumn"
	_journey.position = Vector2(JOURNEY_X, JOURNEY_Y)
	_journey.size = Vector2(JOURNEY_W, JOURNEY_H)
	_journey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_journey)

	var header := UiKit.label("旅 程", &"TinyStrongLabel")
	header.name = "JourneyHeader"
	header.modulate = UiKit.EMBER
	header.position = Vector2(0.0, 0.0)
	header.size = Vector2(120.0, 16.0)
	_journey.add_child(header)
	_journey_count = UiKit.label("", &"TinyLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_journey_count.name = "JourneyCount"
	_journey_count.position = Vector2(JOURNEY_W - 90.0, 0.0)
	_journey_count.size = Vector2(90.0, 16.0)
	_journey.add_child(_journey_count)
	_journey_chapter = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_journey_chapter.name = "JourneyChapter"
	_journey_chapter.position = Vector2(0.0, 20.0)
	_journey_chapter.size = Vector2(JOURNEY_W, 16.0)
	_journey_chapter.clip_text = true
	_journey_chapter.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_journey.add_child(_journey_chapter)
	_journey_recap = UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_journey_recap.name = "JourneyRecap"
	_journey_recap.position = Vector2(0.0, 38.0)
	_journey_recap.size = Vector2(JOURNEY_W, 30.0)
	_journey_recap.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_journey_recap.max_lines_visible = 2
	_journey_recap.clip_text = true
	_journey.add_child(_journey_recap)

	_gauge = TitleGauge.new()
	_gauge.name = "JourneyGauge"
	_gauge.position = Vector2(0.0, 78.0)
	_journey.add_child(_gauge)

	var chip_y := 78.0 + _gauge.custom_minimum_size.y + 8.0
	var specs := [["Rank", "阶", 0, 0], ["Skin", "装", 1, 0], ["Trials", "试", 0, 1], ["Arena", "竞", 1, 1]]
	for spec in specs:
		var chip := TitleChip.new()
		chip.name = "Chip" + String(spec[0])
		chip.tag_text = String(spec[1])
		chip.position = Vector2(float(spec[2]) * (TitleChip.CHIP_SIZE.x + 12.0),
				chip_y + float(spec[3]) * (TitleChip.CHIP_SIZE.y + 6.0))
		_journey.add_child(chip)
		_chips[String(spec[0])] = chip

	_build_dossier_card()
	_refresh_dossier()


## 展开的完整档案：与旧版同名的节点（Dossier / DossierRank / ...），平时收起。
func _build_dossier_card() -> void:
	_card = TitleCard.new()
	_card.name = "DossierWrap"
	# closed: parked 24px to the right and invisible; it slides home when it opens
	_card.position = CARD_RECT.position + Vector2(CARD_SLIDE, 0.0)
	_card.size = CARD_RECT.size
	_card.visible = false
	_card.modulate.a = 0.0
	add_child(_card)

	var panel := PanelContainer.new()
	panel.name = "Dossier"
	panel.position = Vector2(22.0, 22.0)
	panel.size = CARD_RECT.size - Vector2(44.0, 44.0)
	panel.custom_minimum_size = panel.size
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := UiKit.label("行 程 档 案", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	head.modulate = UiKit.EMBER
	head.name = "DossierHead"
	box.add_child(head)
	_add_dossier_row(box, "Rank", "余 烬 阶 位")
	_add_dossier_row(box, "Skin", "当 前 外 观")
	_add_dossier_row(box, "Trials", "回 火 试 炼")
	_add_dossier_row(box, "Arena", "余 烬 竞 技 场")
	_add_dossier_row(box, "Chapter", "上 次 行 程")
	_dossier_recap = UiKit.label("", &"FootnoteLabel")
	_dossier_recap.name = "DossierRecap"
	_dossier_recap.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_dossier_recap.custom_minimum_size = Vector2(0.0, 44.0)
	_dossier_recap.modulate = Color(UiKit.EMBER_ASH.r, UiKit.EMBER_ASH.g, UiKit.EMBER_ASH.b, 0.85)
	box.add_child(_dossier_recap)
	if not TrialCatalogScript.unlocked():
		var trial_hint := UiKit.label("通关第七章或任一结局后解锁「回火试炼」", &"FootnoteLabel")
		trial_hint.name = "TrialLockHint"
		trial_hint.modulate = UiKit.ASH
		trial_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		trial_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trial_hint.custom_minimum_size = Vector2(0.0, 30.0)
		box.add_child(trial_hint)
	var hint := UiKit.label("Tab 收起 · 悬停展开 · 章节存档记录在烬巢", &"FootnoteLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	hint.name = "DossierHint"
	hint.modulate = UiKit.ASH
	box.add_child(hint)
	var flex := Control.new()
	flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(flex)
	var foot := UiKit.label("档 案 随 存 档 更 新", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	foot.name = "DossierFoot"
	foot.modulate = UiKit.ASH
	box.add_child(foot)


func _add_dossier_row(parent: VBoxContainer, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.name = "DossierRow" + key
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var tick := ColorRect.new()
	tick.name = "Tick" + key
	tick.color = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.55)
	tick.custom_minimum_size = Vector2(10.0, 2.0)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tick)
	var tag := UiKit.label(title, &"TinyLabel")
	tag.modulate = UiKit.ASH
	tag.custom_minimum_size = Vector2(96.0, 0.0)
	row.add_child(tag)
	var value := UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	value.name = "Dossier" + key
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.clip_text = true
	value.max_lines_visible = 1
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(value)
	_dossier_values[key] = value


func _refresh_dossier() -> void:
	if _dossier_values.is_empty():
		return
	var peek := TitleWorld.peek_save()
	# the same look the live scene was built from (forced states in tools / tests included)
	var has_save := bool(_look.get("has_save", peek.get("has_save", false)))
	var rank := clampi(int(_look.get("rank", peek.get("rank", 1))), 1, 10)
	var points := int(_look.get("points", peek.get("points", 0)))
	var rank_text := "尚无余烬 · 点燃后开始记录"
	if has_save:
		# 一行放得下：阶位 + 阶名 + 属性点；XP 进度在角色面板里看。
		rank_text = "%d 阶 · %s · 点 %d" % [rank, EmberRankScript.name_for_rank(rank), points]
	_dossier_values["Rank"].text = rank_text

	var skin_id := String(_look.get("skin", peek.get("skin", "")))
	var skin := StringName(skin_id) if skin_id != "" else SkinCatalogScript.DEFAULT_SKIN
	var skin_name: String = SkinCatalogScript.name_of(skin)
	_dossier_values["Skin"].text = skin_name

	var trial_text := "未踏足"
	var trial_count := 0
	if ResourceLoader.exists("res://scripts/data/trial_records.gd"):
		var all: Dictionary = TrialRecordsScript.all()
		for track in all.values():
			if track is Dictionary:
				trial_count += (track as Dictionary).size()
		if trial_count > 0:
			trial_text = "%d 条记录" % trial_count
	_dossier_values["Trials"].text = trial_text

	var arena_text := "未踏足"
	var arena_records: Dictionary = ArenaRunScript.read_records()
	var arena_runs := int(arena_records.get("runs", 0))
	if arena_runs > 0:
		arena_text = "最佳 %d 分 · %d 场" % [int(arena_records.get("best_score", 0)), arena_runs]
	_dossier_values["Arena"].text = arena_text

	var chapter_text := "尚无旅程"
	var recap := ""
	var chapter_id := String(_look.get("chapter_id", ""))
	if has_save and chapter_id != "":
		chapter_text = ChapterText.title_of(chapter_id)
		recap = ChapterText.recap_of(chapter_id)
	var ending := String(_look.get("ending", ""))
	if ending != "":
		chapter_text = _ending_name(ending)
		recap = ChapterText.ending_summary_of(ending)
	_dossier_values["Chapter"].text = chapter_text
	_dossier_recap.text = recap

	# collapsed column: chips + chapter line
	var cleared := int(_look.get("cleared", 0))
	_journey_count.text = "%02d / %02d" % [cleared, ChapterText.order().size()]
	_journey_chapter.text = chapter_text if (has_save or ending != "") else "尚无旅程 · 尚未点燃"
	_journey_recap.text = recap
	_journey_recap.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.95)
	var done: Array[bool] = []
	done.assign(_look.get("done", []))
	_gauge.set_journey(done, int(_look.get("chapter_index", -1)) if ending == "" else -1)
	(_chips["Rank"] as TitleChip).set_chip("阶", str(rank) if has_save else "—", has_save)
	(_chips["Skin"] as TitleChip).set_chip("装", skin_name, has_save)
	(_chips["Trials"] as TitleChip).set_chip("试", str(trial_count) if trial_count > 0 else "—", trial_count > 0)
	(_chips["Arena"] as TitleChip).set_chip("竞", str(int(arena_records.get("best_score", 0))) if arena_runs > 0 else "—",
			arena_runs > 0)


## 结局的短名（取自结局概述冒号前的几个字：送剑 / 守火 / 熄灭残芯）。
func _ending_name(kind: String) -> String:
	var summary := ChapterText.ending_summary_of(kind)
	var cut := summary.find("：")
	return summary.substr(0, cut) if cut > 0 else "旅程已终"


# ------------------------------------------------------------- inscription -----

## 底部墓志：一行字，慢速打字机轮换；第一句永远是 EPITAPH。
func _build_inscription() -> void:
	var strip := Control.new()
	strip.name = "Inscription"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	strip.position = EPITAPH_RECT.position
	strip.size = EPITAPH_RECT.size
	add_child(strip)

	var row := HBoxContainer.new()
	row.name = "EpitaphRow"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)

	_ep_lines = PackedStringArray([EPITAPH,
			String(ChapterText.OPENING["situation"]),
			String(ChapterText.OPENING["lamp"]),
			String(ChapterText.OPENING["question"])])
	# Left-aligned, sized to the whole line: a typed prefix then grows to the right while
	# the finished line still sits flush with the right margin (the row ends at x=1208).
	_epitaph = UiKit.label(EPITAPH, &"EpitaphLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_epitaph.name = "Epitaph"
	_epitaph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pack(_epitaph)
	row.add_child(_epitaph)
	_fit_epitaph()


## 页脚：署名靠左、导航提示靠右，一行小字，没有底板。
func _build_chrome() -> void:
	var band := Control.new()
	band.name = "CreditBand"
	band.position = FOOTER_RECT.position
	band.size = FOOTER_RECT.size
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var rule := ColorRect.new()
	rule.name = "FooterRule"
	rule.color = Color(0.23, 0.125, 0.07, 0.7)
	rule.position = Vector2(0.0, 0.0)
	rule.size = Vector2(FOOTER_RECT.size.x, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(rule)
	var credits := UiKit.label(
			"美术 ansimuz · aamatniekss · Kronovi · CodeManu · Kenney — 音频 Kenney · 字体 Fusion Pixel (OFL)",
			&"FootnoteLabel")
	credits.position = Vector2(0.0, 6.0)
	credits.size = Vector2(FOOTER_RECT.size.x - 420.0, 20.0)
	credits.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	credits.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.9)
	band.add_child(credits)
	# 操作提示染成余烬色：页脚里只有这一行是"给玩家的指令"。
	var hint := UiKit.label("↑↓ 选择 · Enter 确认 · Tab 档案", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	hint.position = Vector2(FOOTER_RECT.size.x - 400.0, 6.0)
	hint.size = Vector2(400.0, 20.0)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.modulate = UiKit.EMBER_ASH
	band.add_child(hint)

	_update_notice = Button.new()
	_update_notice.name = "UpdateNotice"
	_update_notice.text = "有 新 版 本 · 查 看"
	# SettingsButton lives in the runtime extras theme (not the project theme)
	_update_notice.theme = UiKit.extras_theme()
	_update_notice.theme_type_variation = &"SettingsButton"
	# 档案行都是 12px 小字，按钮保持同量级：stylebox 自带 6px 上下边距，
	# 这里显式压掉，22px 一行才和小字协调（默认会撑到 40）。
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb := _update_notice.get_theme_stylebox(st).duplicate() as StyleBox
		if sb != null:
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			_update_notice.add_theme_stylebox_override(st, sb)
	_update_notice.add_theme_font_size_override("font_size", 12)
	_update_notice.focus_mode = Control.FOCUS_ALL
	_update_notice.visible = false
	_update_notice.pressed.connect(_open_update_prompt)
	add_child(_update_notice)
	# Size only after it is in the tree: a Control's size is clamped *up* to its minimum, and
	# outside the tree the minimum still comes from the default (24px, wide-margin) button theme.
	_update_notice.reset_size()
	_update_notice.position = Vector2(1040.0, 661.0)
	_update_notice.size = Vector2(168.0, 22.0)


## UI 层的火星池（聚焦迸火星、字标锻入的火星）：复用 TitleSparks 的火星部分，放大两倍，
## 落在 UI 的 2px 栅格上。
func _build_ui_sparks() -> void:
	_ui_sparks = TitleSparks.new()
	_ui_sparks.name = "UiSparks"
	_ui_sparks.scale = Vector2(2.0, 2.0)
	add_child(_ui_sparks)


# ---------------------------------------------------------------- overlays -----

func _build_overlays() -> void:
	_recap = load("res://scripts/ui/ember_recap.gd").new() as CanvasLayer
	_recap.name = "EmberRecap"
	_recap.layer = 8
	_recap.closed.connect(func() -> void: _menu.active = true)
	add_child(_recap)
	_controls = ControlsPanel.new()
	_controls.layer = 5
	_controls.closed.connect(func() -> void: _menu.active = true)
	add_child(_controls)
	_settings = SettingsScreen.new()
	_settings.layer = 6
	_settings.closed.connect(func() -> void: _menu.active = true)
	add_child(_settings)
	_build_confirm()
	_build_character_select()
	_update_prompt = UpdatePrompt.new()
	_update_prompt.layer = 7
	_update_prompt.closed.connect(func() -> void: _menu.active = true)
	add_child(_update_prompt)

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	# 压黑之后才浮出来的一句话：退场不是"闪断"，是余烬熄灭。
	_quit_caption = UiKit.label(QUIT_CAPTION, &"EpitaphLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_quit_caption.name = "QuitCaption"
	_quit_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quit_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quit_caption.modulate.a = 0.0
	_fade.add_child(_quit_caption)


# ------------------------------------------------------------------- intro -----

## 开屏：黑幕退去 → 吊灯一盏盏点亮 → 字标锻入（白热扫过 + 火星）→ 副题 → 菜单逐条落位 →
## 旅程列、墓志、页脚收尾。整段约 2.5 秒，期间不挡操作（菜单一直可点）。
## 任何一步都可以被 _skip_intro() 一把跳过：玩家进设置再回来、或者换关回来时
## 不该被同一段开场拖第二次。
func _play_intro() -> void:
	_intro_playing = true
	# 菜单在开屏期间保持 active：悬停/上下键照常工作，确认键由 _on_chosen
	# 跳过开屏后照常执行——进场动画不是输入门禁，只是"还没演完"。
	# 黑幕：盖住整个窗口（内容矩形外也有边），与场景交叉淡出。
	_curtain = ColorRect.new()
	_curtain.name = "BootCurtain"
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.color = Color.BLACK
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_curtain)

	# 初始态：全透明 / 未锻入 / 菜单条偏在左边，等帷幕退去后依次出现。
	_keyart.modulate.a = 0.0
	_masthead.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_logo_material.set_shader_parameter("progress", 0.0)
	_journey.modulate.a = 0.0
	var inscription := get_node_or_null("Inscription") as CanvasItem
	var band := get_node_or_null("CreditBand") as CanvasItem
	if inscription != null:
		inscription.modulate.a = 0.0
	if band != null:
		band.modulate.a = 0.0
	if _knight_light != null:
		_knight_light.modulate.a = 0.0
	var rows: Array[MenuItem] = []
	for child in _menu.get_children():
		var control := child as Control
		if control == null:
			continue
		control.modulate.a = 0.0
		if child is MenuItem:
			(child as MenuItem).land = 1.0
			rows.append(child as MenuItem)
	if _world != null:
		_world.play_intro()
	_ep_phase = 0

	var tw := create_tween()
	_intro_tween = tw
	tw.set_parallel(true)
	tw.tween_property(_curtain, "modulate:a", 0.0, BOOT_FADE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_keyart, "modulate:a", 1.0, BOOT_FADE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _knight_light != null:
		tw.tween_property(_knight_light, "modulate:a", 1.0, 0.4).set_delay(BOOT_FADE)
	# 字标锻入
	tw.tween_property(_masthead, "modulate:a", 1.0, 0.05).set_delay(LOGO_AT)
	tw.tween_property(_logo_material, "shader_parameter/progress", 1.0, LOGO_TIME) \
			.set_delay(LOGO_AT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: UiKit.sfx(&"forge_pulse", &"gate")).set_delay(LOGO_AT)
	for k in 5:
		tw.tween_callback(_logo_spark.bind(0.12 + 0.19 * float(k))) \
				.set_delay(LOGO_AT + LOGO_TIME * (0.12 + 0.19 * float(k)))
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.35).set_delay(LOGO_AT + LOGO_TIME * 0.85) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 菜单逐条落位
	var delay := MENU_AT
	for i in rows.size():
		var row := rows[i]
		tw.tween_property(row, "modulate:a", 1.0, 0.2).set_delay(delay)
		tw.tween_property(row, "land", 0.0, MENU_LAND).set_delay(delay) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		delay += MENU_STAGGER
	var menu_end := delay + MENU_LAND
	tw.tween_property(_journey, "modulate:a", 1.0, 0.35).set_delay(MENU_AT + 0.35)
	if inscription != null:
		tw.tween_property(inscription, "modulate:a", 1.0, 0.3).set_delay(menu_end - 0.1)
	if band != null:
		tw.tween_property(band, "modulate:a", 1.0, 0.3).set_delay(menu_end - 0.1)
	# 收尾：全部就位后撤掉黑幕、置回非播放态、墓志开始打字。
	tw.tween_callback(_finish_intro).set_delay(menu_end + 0.1)


func _finish_intro() -> void:
	_intro_playing = false
	if _curtain != null and is_instance_valid(_curtain):
		_curtain.queue_free()
		_curtain = null
	_ep_phase = 1
	_ep_t = 0.0


## 字标锻入时沿着扫过的前沿迸几粒火星。
func _logo_spark(k: float) -> void:
	if _ui_sparks == null or _logo == null:
		return
	var r := _local_rect(_logo)
	_ui_sparks.burst(Vector2(r.position.x + r.size.x * k, r.position.y + r.size.y * 0.55) * 0.5, 7, 70.0)


## 跳过开屏：直接落到终态（不删帷幕之外的东西，_quit_sequence 还要用）。
func _skip_intro() -> void:
	if not _intro_playing:
		return
	_intro_playing = false
	# 先把还在跑的入场 tween 杀掉，再把透明状态和位置落到位：
	# 不然它的后续步骤会把这里写下的终态又改回去。
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_logo_material.set_shader_parameter("progress", 1.0)
	Transitions.snap_visible([
			_keyart, _masthead, _subtitle, _journey,
			get_node_or_null("Inscription"),
			get_node_or_null("CreditBand"),
			_knight_light,
	])
	for child in _menu.get_children():
		var control := child as Control
		if control != null:
			control.modulate.a = 1.0
		if child is MenuItem:
			(child as MenuItem).land = 0.0
	if _world != null:
		_world.skip_intro()
	if _curtain != null and is_instance_valid(_curtain):
		_curtain.queue_free()
		_curtain = null
	_ep_phase = 1
	_ep_t = 0.0


## 开屏是否还在播（测试与 _on_chosen 用：动画期间选择键不响应）。
func intro_playing() -> bool:
	return _intro_playing


# ------------------------------------------------------------------ per frame ---

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_seen = true


func _process(delta: float) -> void:
	_time += delta
	_update_pointer()
	_update_dossier_hover()
	_update_epitaph(delta)
	if _quitting or _intro_playing:
		# 退场/开屏动画期间字标 / keyart 的呼吸会让位给 tween，
		# 否则 _process 会和 tween 抢同一个 modulate 属性。
		return
	if _world == null:
		# 旧版静态 keyart：火光在暖色间轻微起伏。
		var warm := 0.5 + 0.5 * sin(TAU * _time / KEYART_BREATH_PERIOD)
		_keyart.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.06, 0.94, 0.86), warm)
	# 字标辉光呼吸。
	var glow := 0.5 + 0.5 * sin(TAU * _time / LOGO_BREATH_PERIOD)
	_masthead.modulate = Color(0.94, 0.94, 0.94).lerp(Color(1.10, 1.04, 0.98), glow)


## 鼠标在标题屏上的位置 → 场景的整数像素视差（没动过鼠标就居中，截图/测试因此可重复）。
func _update_pointer() -> void:
	if _world == null:
		return
	if not _pointer_seen or _quitting:
		_world.set_pointer(Vector2.ZERO)
		return
	var local := get_local_mouse_position()
	_world.set_pointer(Vector2(local.x / 640.0 - 1.0, local.y / 360.0 - 1.0))


## 悬停旅程列（或展开后悬停在卡上）/ Tab 固定：展开完整档案。
func _update_dossier_hover() -> void:
	var want := _dossier_pinned
	if _pointer_seen and _menu != null and _menu.active and not _quitting and not _intro_playing:
		var m := get_local_mouse_position()
		var zone := Rect2(JOURNEY_X - 8.0, JOURNEY_Y - 6.0, JOURNEY_W + 16.0, JOURNEY_H + 12.0)
		if zone.has_point(m) or (_dossier_open and CARD_RECT.has_point(m)):
			want = true
	if want != _dossier_open:
		_set_dossier_open(want)


func _set_dossier_open(open: bool) -> void:
	_dossier_open = open
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	var instant := DisplayServer.get_name() == "headless"
	if open:
		_card.visible = true
	var home_x := CARD_RECT.position.x
	if instant:
		_card.modulate.a = 1.0 if open else 0.0
		_card.position.x = home_x if open else home_x + CARD_SLIDE
		_card.visible = open
		_journey.modulate.a = 0.0 if open else (1.0 if not _intro_playing else _journey.modulate.a)
		return
	_card_tween = create_tween()
	_card_tween.set_parallel(true)
	_card_tween.tween_property(_card, "modulate:a", 1.0 if open else 0.0, 0.18)
	_card_tween.tween_property(_card, "position:x", home_x if open else home_x + CARD_SLIDE, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(_journey, "modulate:a", 0.0 if open else 1.0, 0.18)
	if not open:
		_card_tween.chain().tween_callback(func() -> void: _card.visible = false)


func dossier_open() -> bool:
	return _dossier_open


## 墓志：慢速打字机轮换，第一句永远是 EPITAPH。
func _update_epitaph(delta: float) -> void:
	if _epitaph == null or _ep_phase == 0 or _quitting:
		return
	_ep_t += delta
	var line: String = _ep_lines[_ep_index]
	match _ep_phase:
		1:
			var shown := int(_ep_t / EPITAPH_CHAR)
			_epitaph.visible_characters = shown
			if shown >= line.length():
				_epitaph.visible_characters = -1
				_ep_phase = 2
				_ep_t = 0.0
		2:
			if _ep_t >= EPITAPH_HOLD:
				_ep_phase = 3
				_ep_t = 0.0
		3:
			_epitaph.modulate.a = 1.0 - clampf(_ep_t / EPITAPH_FADE, 0.0, 1.0)
			if _ep_t >= EPITAPH_FADE:
				_ep_index = (_ep_index + 1) % _ep_lines.size()
				_epitaph.text = _ep_lines[_ep_index]
				_fit_epitaph()
				_epitaph.visible_characters = 0
				_epitaph.modulate.a = 1.0
				_ep_phase = 1
				_ep_t = 0.0


## 墓志标签按当前这一行的整句宽度定宽（右端对齐由 HBox 的 END 对齐保证）。
func _fit_epitaph() -> void:
	var font := _epitaph.get_theme_font(&"font")
	var font_size := _epitaph.get_theme_font_size(&"font_size")
	var width := 8.0
	if font != null:
		width = font.get_string_size(_epitaph.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_epitaph.custom_minimum_size = Vector2(minf(ceilf(width) + 8.0, EPITAPH_RECT.size.x), EPITAPH_RECT.size.y)


## 当前打字机的那一行（测试读）。
func epitaph_line() -> String:
	return _ep_lines[_ep_index] if not _ep_lines.is_empty() else ""


# ------------------------------------------------------------------ choices -----

func _on_focus_changed(id: StringName) -> void:
	if _quitting or _started or _menu == null:
		return
	var idx := _menu.item_ids().find(id)
	var items := _menu.items()
	if idx < 0 or idx >= items.size():
		return
	var item := items[idx] as MenuItem
	if _world != null and not _intro_playing:
		_world.nudge(1.0)
	if _ui_sparks != null and item != null and not _intro_playing:
		var r := _local_rect(item)
		var at := Vector2(r.position.x + MenuItem.STRIP_CURSOR_X + 6.0, r.position.y + r.size.y * 0.5)
		_ui_sparks.burst(at * 0.5, 8, 62.0)


## 控件在标题屏设计空间里的矩形（与窗口缩放无关：标题屏自己被缩放时
## Control.get_global_rect() 的 size 不跟着缩，所以走完整的全局变换）。
func _local_rect(control: Control) -> Rect2:
	var to_local := get_global_transform().affine_inverse() * control.get_global_transform()
	var a: Vector2 = to_local * Vector2.ZERO
	var b: Vector2 = to_local * control.size
	return Rect2(a, b - a).abs()


## 设计空间里的矩形（公开给测试 / 工具）。
func design_rect(control: Control) -> Rect2:
	return _local_rect(control)


func _on_chosen(id: StringName) -> void:
	if _started or _quitting:
		return
	# 开屏没播完时确认键 = 直接跳到终态并照常执行这一格：
	# 进场动画不是门禁，玩家/测试按了确认就该有反应。
	if _intro_playing:
		_skip_intro()
	match id:
		ID_NEW:
			# 有存档时"点燃余烬"先弹确认覆盖；确认后打开选人。无存档时直接打开选人。
			if SaveData.has_save():
				open_confirm()
			else:
				_menu.active = false
				_char_select.open()
		ID_CONTINUE:
			if SaveData.peek_ending() != "":
				_menu.active = false
				_recap.open()
			else:
				_start(true)
		ID_TRIAL:
			_menu.active = false
			Sfx.play(&"gate")
			_confirm_effect()
			Director.fade_to(TRIAL_MENU, 0.5)
		ID_ARENA:
			# 余烬竞技场：和试炼入口同一套待遇（落闸声 + 前推闪光 + ArenaRun 自带的淡出）。
			_menu.active = false
			Sfx.play(&"gate")
			_confirm_effect()
			if not _start_arena():
				_menu.active = true
				Sfx.play(&"ui_denied")
		ID_SETTINGS:
			_menu.active = false
			_settings.open()
		ID_CONTROLS:
			_menu.active = false
			_controls.open()
		ID_UPDATE:
			_menu.active = false
			if _update_prompt != null:
				_update_prompt.open(UpdateService.entry())
		ID_QUIT:
			_quit_sequence()


func _start_arena() -> bool:
	if arena_start.is_valid():
		return bool(arena_start.call())
	return ArenaRunScript.start()


## 确认入场：白热闪光 + 镜头朝骑士前推 + 在选中条上迸一簇火星。随后调用方淡出换关。
func _confirm_effect() -> void:
	if _world != null:
		_world.enter_push(5.0, 0.55)
	if _ui_sparks != null and _menu != null:
		var items := _menu.items()
		var idx := _menu.item_ids().find(_menu.selected_id())
		if idx >= 0 and idx < items.size():
			var r := _local_rect(items[idx] as Control)
			_ui_sparks.burst(Vector2(r.position.x + 24.0, r.position.y + r.size.y * 0.5) * 0.5, 14, 90.0)


func _on_update_checked(status: StringName, _entry: Dictionary) -> void:
	if status != &"available":
		return
	if _update_notice == null or not is_instance_valid(_update_notice):
		return
	_update_notice.visible = true


## 版本提示不进菜单（模式组固定，不会被动态行撑出屏幕）：页脚上方一个小按钮。
func _open_update_prompt() -> void:
	if _quitting or _started:
		return
	if _intro_playing:
		_skip_intro()
	_menu.active = false
	if _update_prompt != null:
		_update_prompt.open(UpdateService.entry())


# --------------------------------------------------------------------- quit -----

## 离开锈墓的退场：菜单条逐格熄灭、吊灯一盏盏灭掉、整个炉厅暗下去，只剩巨剑的剪影；
## 然后浮出一句"余烬熄灭"再退出进程。任何输入都能立刻跳到退出。
func _quit_sequence() -> void:
	if _quitting or _started:
		return
	# 开屏中途离开：先把入场动画抹平，否则逐格熄灭会和淡入的 tween 抢属性。
	if _intro_playing:
		_skip_intro()
	_quitting = true
	_menu.active = false
	_dossier_pinned = false
	if _dossier_open:
		_set_dossier_open(false)
	Sfx.play(&"ui_back")
	# 音乐先让路，给铁门声留出空间。
	Music.duck(-10.0, 1.6)
	var dark_at := 0.9
	if _world != null:
		dark_at = _world.quit_out(0.2)
	_quit_tween = create_tween()
	_quit_tween.set_parallel(true)

	# 一格格熄灭：从"点燃余烬"一路烧到"离开锈墓"。
	var row := 0
	for child in _menu.get_children():
		var control := child as Control
		if control == null:
			continue
		_quit_tween.tween_property(control, "modulate:a", 0.0, QUIT_RAIL_FADE) \
				.set_delay(QUIT_ROW_STAGGER * row) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		row += 1

	# 字标、旅程列、墓志、页脚一起暗下去：TitleScreen 的直系画布子节点里，
	# 黑幕和菜单自己另有安排；活景留着（巨剑剪影还要在里面亮着）。
	for child in get_children():
		if not (child is CanvasItem) or child == _fade or child == _menu:
			continue
		if _world != null and child == _keyart:
			continue
		_quit_tween.tween_property(child, "modulate:a", 0.0, QUIT_SCENE_FADE) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 铁门落下的闷响：进关用 gate，离开锈墓也用 gate，一来一去。
	_quit_tween.tween_callback(func() -> void: Sfx.play(&"gate", 0.0, -6.0)).set_delay(dark_at * 0.85)
	# 最后浮出一句墓志。
	_quit_tween.tween_property(_quit_caption, "modulate:a", 1.0, QUIT_CAPTION_FADE) \
			.set_delay(dark_at + 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_quit_tween.chain().tween_interval(QUIT_HOLD)
	_quit_tween.chain().tween_callback(_finish_quit)


## 收尾：把黑幕补满（跳过时不留下半透明的中间帧），然后退出。
## quit_on_finish 是给 headless 测试留的开关，正常游戏永远是 true。
func _finish_quit() -> void:
	if _quit_done:
		return
	_quit_done = true
	if _quit_tween != null and _quit_tween.is_valid():
		_quit_tween.kill()
	_fade.color.a = 1.0
	if not quit_on_finish:
		return
	get_tree().quit()


func is_quitting() -> bool:
	return _quitting


func quit_finished() -> bool:
	return _quit_done


## 覆盖存档确认框：取消在上、默认选中；确认覆盖才真的清档开局。
func _build_confirm() -> void:
	_confirm = CanvasLayer.new()
	_confirm.name = "OverwriteConfirm"
	_confirm.layer = 7
	_confirm.visible = false
	add_child(_confirm)
	PresentationMetrics.bind_layer(_confirm)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(root)
	root.add_child(UiKit.scrim(0.72, 0.66, 0.78))
	var frame := UiKit.panel(&"OrnatePanel")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(frame)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(column)
	column.add_child(UiKit.label("覆 盖 存 档 ？", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())
	column.add_child(UiKit.label("现有进度会被清除，从头点燃。", &"DimLabel",
			HORIZONTAL_ALIGNMENT_CENTER))
	_confirm_menu = MenuList.new()
	_confirm_menu.name = "ConfirmMenu"
	_confirm_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_confirm_menu.add_theme_constant_override("separation", 12)
	_confirm_menu.active = false
	column.add_child(_confirm_menu)
	# 取消是默认项、也是安全出口，用燕尾板；清档是不可逆动作，只留四只角标。
	_confirm_menu.compact(_confirm_menu.add_item(
			ID_KEEP, "取 消", false, MenuItem.Kind.SECONDARY))
	_confirm_menu.compact(_confirm_menu.add_item(
			ID_OVERWRITE, "确 认 覆 盖", false, MenuItem.Kind.GHOST))
	_confirm_menu.chosen.connect(_on_confirm_chosen)


func open_confirm() -> void:
	_menu.active = false
	_confirm.visible = true
	_confirm_menu.active = true
	_confirm_menu.select(0, false)
	# 确认框是压暗+缩放进场（UiKit 的既有小件节奏），这里直接可见：
	# 它是模态层级里最小的一层，再套一层 0.17s 滑入会把"覆盖存档？"
	# 这个不可逆动作的反馈拖慢。纱幕类大屏才有滑入。


func close_confirm() -> void:
	_confirm.visible = false
	_confirm_menu.active = false
	_menu.active = true


func confirm_open() -> bool:
	return _confirm != null and _confirm.visible


func _on_confirm_chosen(id: StringName) -> void:
	if id == ID_OVERWRITE:
		_confirm.visible = false
		_confirm_menu.active = false
		_char_select.open()
	else:
		close_confirm()


func _build_character_select() -> void:
	var packed: PackedScene = load("res://scenes/ui/CharacterSelectScreen.tscn")
	if packed != null:
		_char_select = packed.instantiate() as CharacterSelectScreen
	if _char_select == null:
		_char_select = CharacterSelectScreen.new()
	_char_select.layer = 8
	_char_select.cancelled.connect(_on_char_select_cancelled)
	_char_select.embark_requested.connect(_on_char_select_embark)
	add_child(_char_select)


func _on_char_select_cancelled() -> void:
	_char_select.close()
	_menu.active = true


func _on_char_select_embark(origin_id: StringName, loadout: Dictionary) -> void:
	_char_select.close()
	_started = true
	_menu.active = false
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	if SaveData.has_method("init_new_game"):
		SaveData.call("init_new_game", origin_id, loadout)
		# 外观是 loadout 的一部分：启程后写进 profile（init_new_game 会重置为默认）。
		var skin := String(loadout.get("skin", ""))
		var rune := String(loadout.get("rune", ""))
		if skin != "":
			SaveData.set_skin(skin, rune)
			SaveData.persist_profile()
	else:
		SaveData.delete_save()
		var w = loadout.get("weapon", "broken_sword")
		var a = loadout.get("armor", "broken_armor")
		var t = loadout.get("trinket", "broken_pendant")
		var w_id = w.id if (w != null and "id" in w) else String(w)
		var a_id = a.id if (a != null and "id" in a) else String(a)
		var t_id = t.id if (t != null and "id" in t) else String(t)
		SaveData.data = {
			"player": { "origin": String(origin_id) },
			"equipment": {
				"weapon": String(w_id),
				"armor": String(a_id),
				"trinket": String(t_id),
				"bag": []
			}
		}
	Sfx.play(&"gate")
	_confirm_effect()
	Director.fade_to(LEVEL_PATH, FADE_OUT)


func character_select_screen() -> CharacterSelectScreen:
	return _char_select


func _unhandled_input(event: InputEvent) -> void:
	if _quitting:
		# 退出游戏不该被退场动画拖住：任意按键 / 点击直接收尾。
		if event is InputEventKey or event is InputEventMouseButton \
				or event is InputEventJoypadButton:
			_finish_quit()
			get_viewport().set_input_as_handled()
		return
	if confirm_open() and event.is_action_pressed("ui_cancel"):
		close_confirm()
		get_viewport().set_input_as_handled()
		return
	# Tab：固定 / 收起完整档案（没有弹窗压在上面时）。
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_TAB and _menu != null and _menu.active:
		_dossier_pinned = not _dossier_pinned
		_set_dossier_open(_dossier_pinned)
		get_viewport().set_input_as_handled()


func _start(continue_game: bool) -> void:
	_started = true
	_menu.active = false
	# 标题进关不沿用上一局死亡排队：继续走存档坐标，新开清档。
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	var target := LEVEL_PATH
	if continue_game:
		SaveData.load_game()
		target = SaveData.saved_scene(LEVEL_PATH)
	else:
		SaveData.delete_save()
	Sfx.play(&"gate")
	_confirm_effect()
	Director.fade_to(target, FADE_OUT)


func _notification(what: int) -> void:
	# 活景只在标题可见时渲染：被盖住 / 隐藏时不再烧 GPU。
	if what == NOTIFICATION_VISIBILITY_CHANGED and _world_viewport != null:
		_world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS \
				if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


## 暴露给测试 / 工具的只读句柄。
func world() -> TitleWorld:
	return _world


func look() -> Dictionary:
	return _look


func _exit_tree() -> void:
	if UpdateService.checked.is_connected(_on_update_checked):
		UpdateService.checked.disconnect(_on_update_checked)
	var tree := get_tree()
	if tree != null and tree.root.size_changed.is_connected(_update_smooth_scale):
		tree.root.size_changed.disconnect(_update_smooth_scale)
	if Sfx.has_method(&"set_title_bed"):
		Sfx.call(&"set_title_bed", false)
	WorldClock.release_menu()
