class_name TitleScreen
extends Control
## 标题屏：keyart + 字标与插座剑 + 左下菜单架 + 右下墓志 + 底部署名带。
##
## 版式：字标与副题压在顶部正中（与 keyart 的光柱同轴），菜单改成左下的一列"铁架"：
## 竖脊串起五格——两格主行动（右端收成箭头）、一道短铆钉横线、两格次行动（右端剪出
## 燕尾）、一格只剩四只角标的"离开"；墓志挪到右下角和菜单配重。中间留白正好露出
## keyart 的骑士与光柱：这是旧版居中竖排整块吃掉的那片画面。
##
## 菜单由 MenuList 负责键鼠导航（上下键跳过禁用项、回车确认、悬停跟随），
## 操作说明复用 ControlsPanel（与暂停菜单同一份）。
## 气氛三件套：keyart 火光呼吸、字标辉光呼吸、上升余烬与飘落灰烬。
## 异形按钮板由 scripts/ui/menu_plate.gd 用同一套调色板现画：不新增贴图、不改主题。

const KEYART_PATH := "res://assets/kenney_clean/backgrounds/title_keyart.png"
const LEVEL_PATH := "res://scenes/levels/Level01_Static.tscn"
const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Plate := preload("res://scripts/ui/menu_plate.gd")
const KnightLightScript := preload("res://scripts/ui/keyart_knight_light.gd")
const DossierJagScript := preload("res://scripts/ui/dossier_jag.gd")
const Transitions := preload("res://scripts/ui/ui_transition.gd")
## 回火试炼（新游戏模式）：入口由战役解锁旗标控制（契约 §5）。
const TrialCatalogScript := preload("res://scripts/data/trial_catalog.gd")
const TrialRecordsScript := preload("res://scripts/data/trial_records.gd")
const EmberRankScript := preload("res://scripts/data/ember_rank.gd")
const ArenaRunScript := preload("res://scripts/autoload/arena_run.gd")
const SkinCatalogScript := preload("res://scripts/data/skin_catalog.gd")
const TRIAL_MENU := "res://scenes/ui/TrialMenu.tscn"

const EMBERS_RISING := 30
const EMBERS_FALLING := 14
const KEYART_BREATH_PERIOD := 5.5
const LOGO_BREATH_PERIOD := 3.2
const FADE_OUT := 0.7
const BAND_HEIGHT := 34.0
## 角饰要躲开底部装饰带，否则会跟署名文字撞在一起。
const CORNER_INSET := 16.0
const TOP_INSET := 30.0
## 墓志取「失败的净化偶自己先锈透」。一句，不是台词。
const EPITAPH := "失败的净化偶，自己先锈透了。"

## 左下菜单架：竖脊在 x=92，板面从 x=112 挂出去。
const RAIL_X := 112.0
const RAIL_TOP := 224.0
const SPINE_X := 92.0
const DIVIDER_W := 440.0
## 行间空白（像素）：主行动成一簇、次行动成一簇、"离开"单独挂在最下。
const GAP_PRIMARY := 10.0
const GAP_GROUP := 20.0
const GAP_DIVIDER := 14.0
const GAP_SECONDARY := 6.0
const GAP_QUIT := 74.0
const INTRO_STAGGER := 0.045
const INTRO_DURATION := 0.22
## 开屏总谱（黑幕 → 场景 → 字标 → 菜单）：见 _play_intro。
const BOOT_FADE := 0.55
const RAIL_STAGGER := 0.045
const RAIL_DURATION := 0.22

## 离开锈墓的退场动画：一格格熄灭 → 铁门落下的闷响 → 压黑 → 留一句墓志才退出。
## 任何按键/点击都能立刻跳到退出（开游戏不该被退场动画拖住）。
const QUIT_ROW_STAGGER := 0.055
const QUIT_RAIL_FADE := 0.30
const QUIT_SCENE_FADE := 0.55
const QUIT_BLACKOUT_DELAY := 0.32
const QUIT_BLACKOUT := 0.85
const QUIT_CAPTION_DELAY := 1.12
const QUIT_CAPTION_FADE := 0.35
const QUIT_HOLD := 0.6
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

var _started := false
var _time := 0.0
var _keyart: TextureRect
var _masthead: Control
var _menu: MenuList
var _spine: Control
var _controls: ControlsPanel
var _settings: SettingsScreen
var _confirm: CanvasLayer
var _confirm_menu: MenuList
var _char_select: CharacterSelectScreen
var _update_prompt: UpdatePrompt
var _fade: ColorRect
var _quit_caption: Label
var _quitting := false
var _quit_done := false
var _quit_tween: Tween
## 开屏黑幕：整段开场里盖在最上层的纯黑矩形，播完即撤。
var _curtain: ColorRect
var _intro_playing := false
## 测试开关：置 false 时把退出动画完整走一遍，但不真的结束进程（headless 套件用）。
var quit_on_finish := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 标题屏是根窗口里的普通 Control（不在 GamePresentation 下）。套上同一条
	# 整数内容矩形，非 16:9 窗口才会和游戏中 UI 一样留黑边，而不是被拉满。
	PresentationMetrics.bind_control(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	DisplayServer.window_set_title("Rustgrave")
	_build_window_backdrop()
	# 标题屏自己的主题：Music 的契约要求在这里显式声明（_poll_world 的轮询只是兜底）。
	# set_state(&"calm") 清掉上一局残留的 danger / boss / death 闭锁。
	Music.set_state(&"calm")
	Music.set_theme(&"title")
	DisplayFit.apply()
	WorldClock.hold_for_menu()
	_build_backdrop()
	_build_masthead()
	_build_rail()
	_build_inscription()
	_build_dossier()
	_build_chrome()
	# 覆盖层最后加：Control 的绘制与鼠标拾取都按子节点顺序，越后越上。
	_build_overlays()
	# 新版本检查：静默拉一次 manifest，结果只让菜单多一格"有新版本"，
	# 不弹窗、不打断。检查失败/没有新版时菜单保持原样。
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
	_keyart.texture = UiKit.tex(KEYART_PATH)
	_keyart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keyart)

	# 上下压暗：字标和菜单要压住拱顶的光柱，中段仍把骑士留出来，并盖掉右下角水印。
	add_child(UiKit.scrim(0.74, 0.26, 0.90))
	# 左侧再压一道：菜单架那几格压在齿轮上，文字与空心角标要有底色才读得出。
	add_child(UiKit.scrim_side(0.42, 780.0))
	# 中央骑士的呼吸轮廓光/落影/光柱浮尘：压在暗角之后、前景余烬之前。
	_knight_light = KnightLightScript.new()
	add_child(_knight_light)
	add_child(UiKit.EmberField.build(Rect2(Vector2.ZERO, Vector2(1280, 720)),
			EMBERS_RISING, EMBERS_FALLING))
	UiKit.corner_brackets(self, CORNER_INSET, BAND_HEIGHT + CORNER_INSET)


## 顶部正中：插座剑夹字标，下面一行副题。整块保持原来的居中构图。
func _build_masthead() -> void:
	var column := VBoxContainer.new()
	column.name = "MastheadColumn"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_top = TOP_INSET
	column.offset_bottom = -(BAND_HEIGHT + 40.0)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_masthead = HBoxContainer.new()
	_masthead.name = "Masthead"
	_masthead.alignment = BoxContainer.ALIGNMENT_CENTER
	_masthead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_masthead)

	var left_sword := Ornaments.sword()
	left_sword.name = "SocketSwordLeft"
	_pack(left_sword)
	_masthead.add_child(left_sword)

	var logo := UiKit.sprite_rect(UiKit.TEX_TITLE_LOGO)
	logo.name = "TitleLogo"
	_pack(logo)
	_masthead.add_child(logo)

	var right_sword := Ornaments.sword()
	right_sword.name = "SocketSwordRight"
	_pack(right_sword)
	_masthead.add_child(right_sword)

	var subtitle := UiKit.label("锈 墓 · 余 烬 骑 士", &"SubHeadLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.name = "Subtitle"
	_pack(subtitle)
	column.add_child(subtitle)


## 左下菜单架：竖脊串起五格菜单。行距用空白节点而不是容器 separation，
## 主/次行动之间的分组距离才能和原来的 10px 节奏不同。
func _build_rail() -> void:
	_menu = MenuList.new()
	_menu.name = "Menu"
	_menu.add_theme_constant_override("separation", 0)
	_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu.position = Vector2(RAIL_X, RAIL_TOP)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)

	var has_save := SaveData.has_save()
	# 整架换紧凑板 + 收紧行距：总高 344，和右侧档案同顶（RAIL_TOP）同底。
	_menu.add_item(ID_NEW, "点 燃 余 烬", false, MenuItem.Kind.PRIMARY, true)
	_gap(6.0)
	var cont := "回 看 余 烬" if SaveData.peek_ending() != "" else "继 续 旅 程"
	_menu.add_item(ID_CONTINUE, cont, not has_save, MenuItem.Kind.PRIMARY, true)
	_gap(4.0)
	_menu.add_child(_rail_hairline())
	_gap(6.0)
	var trial_ready := TrialCatalogScript.unlocked()
	_menu.add_item(ID_TRIAL, "回 火 试 炼", not trial_ready, MenuItem.Kind.SECONDARY, true)
	_gap(4.0)
	_menu.add_item(ID_ARENA, "余 烬 竞 技 场", false, MenuItem.Kind.SECONDARY, true)
	_gap(6.0)
	_menu.add_item(ID_SETTINGS, "设 置", false, MenuItem.Kind.SECONDARY, true)
	_gap(4.0)
	_menu.add_item(ID_CONTROLS, "操 作 说 明", false, MenuItem.Kind.SECONDARY, true)
	_gap(20.0)
	var foot_rule := _rail_hairline()
	foot_rule.custom_minimum_size = Vector2(260.0, 2.0)
	_menu.add_child(foot_rule)
	_gap(GAP_QUIT - 22.0)
	_menu.add_item(ID_QUIT, "离 开 锈 墓", false, MenuItem.Kind.GHOST, true)
	_menu.reset_size()
	_menu.chosen.connect(_on_chosen)

	# 竖脊：从第一格的主行动一直串到"离开"，两端各一颗铆钉。
	# 左架投影：光从天井中央打下来，影子向外侧（左）落。
	var shadow := ColorRect.new()
	shadow.name = "RailShadow"
	shadow.color = Color(0.0, 0.0, 0.0, 0.26)
	shadow.position = _menu.position + Vector2(-5.0, 6.0)
	shadow.size = _menu.size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)
	move_child(shadow, _menu.get_index())

	# 从"天花板梁"垂下来的锁链：和背景里的垂链同一语汇，把菜单架挂进场景。
	# 起点收到 y=32：链子从窗棂下第一道横梁出发，长度够、才读得出"挂着"。
	var chain := Ornaments.chain(RAIL_TOP + 8.0 - 32.0)
	chain.name = "RailChain"
	chain.position = Vector2(
			SPINE_X + (Ornaments.SPINE_W - Ornaments.CHAIN_W) * 0.5, 32.0)
	add_child(chain)

	_spine = Ornaments.spine(_menu.size.y - 16.0)
	_spine.name = "RailSpine"
	_spine.position = Vector2(SPINE_X, RAIL_TOP + 8.0)
	add_child(_spine)
	# 叠在菜单之下：先加进来的先画，回头把脊挪到菜单下面。
	move_child(_spine, _menu.get_index())

	# 有存档时光标默认停在"继续"：回车不会再一键抹掉进度。
	if has_save:
		_menu.select(1, false)


## 紧凑版分隔：2px 锈线（原铆钉横线在短架里太占高）。
func _rail_hairline() -> Control:
	var rule := ColorRect.new()
	rule.name = "RailDivider"
	rule.color = Color("#3A2012")
	rule.custom_minimum_size = Vector2(360.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _rail_divider() -> Control:
	var rule := Ornaments.rivet_rule(DIVIDER_W)
	rule.name = "RailDivider"
	return rule


func _gap(height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(spacer)


func _pack(node: Control) -> void:
	node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## 右下角的墓志：两道短铆钉夹一行字，和左下的菜单架配重。
func _build_inscription() -> void:
	var strip := Control.new()
	strip.name = "Inscription"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 墓志收进右下角：不再横穿整幅画面（旧版 96→1184 的通栏会把 keyart
	# 中央的骑士切成两半）。与左下"离开锈墓"同一基线——屏幕底部的两个重音点
	# （排版约束见 tests/title_screen_test.gd 的 test_quit_aligns_with_epitaph）：
	# 当前菜单 quit 行中心 y=606，32px 高的 strip 故取 top=590。
	strip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	strip.offset_left = -(DIVIDER_W + 96.0)
	strip.offset_right = -SPINE_X
	strip.offset_top = 590.0
	strip.offset_bottom = 590.0 + 32.0
	add_child(strip)

	var row := HBoxContainer.new()
	row.name = "EpitaphRow"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)

	var left := Ornaments.stub_rule(true)
	left.name = "EpitaphRuleLeft"
	left.custom_minimum_size = Vector2(48.0, 16.0)
	_pack(left)
	row.add_child(left)

	var epitaph := UiKit.label(EPITAPH, &"EpitaphLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	epitaph.name = "Epitaph"
	epitaph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pack(epitaph)
	row.add_child(epitaph)

	var right := Ornaments.stub_rule(false)
	right.name = "EpitaphRuleRight"
	right.custom_minimum_size = Vector2(48.0, 16.0)
	_pack(right)
	row.add_child(right)


## 底部装饰带：署名靠左、导航提示靠右，都排进同一条锈色铆钉带里。
## 右侧「行程档案」：把本次旅程/成长/试炼记录从系统里拉出来放进标题屏，
## 让开始界面不再只有六格菜单。无存档时显示占位文案，不隐藏面板。
var _dossier_values: Dictionary = {}
var _update_notice: Button
var _dossier_wrap: Control
var _dossier_jag: Control
var _dossier_spine: Control
var _rail_chain: Control
var _dossier_chain: Control
var _knight_light: Control
var _rail_chain_base := 0.0
var _dossier_chain_base := 0.0


func _build_dossier() -> void:
	# 与左侧铁架同构：包一层定位壳，壳左边立一根竖脊（左架脊在板左，档案脊也在板左），
	# 每行标签前挂一小截横钉，机芯/铆钉/锈线沿用同一套 Ornaments。
	var wrap := Control.new()
	wrap.name = "DossierWrap"
	wrap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# 右边缘到屏幕的距离与左栏脊到屏幕的距离一致（对称）。
	# wrap 上移到 RAIL_TOP-18：板面自身还有 18px 内偏移，这样大板顶边和
	# 左菜单架第一格同顶（实测对齐，之前差 18px）。
	# 高度与菜单架同底：菜单（含底部横线与离开行）实测 402px 高，
	# 右栏板面跟随，两栏底边落在同一条水平线上。
	wrap.offset_left = -500.0
	wrap.offset_top = RAIL_TOP - 18.0
	wrap.offset_right = -SPINE_X
	wrap.offset_bottom = RAIL_TOP - 18.0 + 344.0 + 18.0
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dossier_wrap = wrap
	add_child(wrap)

	# 右栏改用和左架同族的不规则大板：右侧箭头纹理水平翻转后朝向画面中央，
	# 正好照应左侧主板的右向凸起；投影也用同一张板形，不再是方块阴影。
	var plate_size := Plate.plate_size(Plate.Shape.DOSSIER)
	var arrow := plate_size.x - Plate.body_width(Plate.Shape.DOSSIER)
	var plate_tex := Plate.texture(Plate.Shape.DOSSIER, Plate.State.NORMAL)

	var shadow_plate := TextureRect.new()
	shadow_plate.name = "DossierShadow"
	shadow_plate.texture = plate_tex
	shadow_plate.flip_h = true
	shadow_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow_plate.size = plate_size
	shadow_plate.position = Vector2(30.0, 7.0)
	shadow_plate.modulate = Color(0.0, 0.0, 0.0, 0.35)
	shadow_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(shadow_plate)

	# 和左架对称：右栏也从天花板垂一根链到自己的竖脊。起点同左链（y=32），
	# 右栏 wrap 已上移到 RAIL_TOP-24，链长要按新的相对位置重算。
	var chain := Ornaments.chain((RAIL_TOP + 18.0) - 32.0)
	chain.name = "DossierChain"
	chain.position = Vector2(2.0 + (Ornaments.SPINE_W - Ornaments.CHAIN_W) * 0.5,
			-(RAIL_TOP + 18.0) + 32.0)
	wrap.add_child(chain)

	# 左缘两块参差铁舌：模仿左边菜单板的箭头/燕尾轮廓。
	_dossier_jag = DossierJagScript.new()
	wrap.add_child(_dossier_jag)

	var plate := TextureRect.new()
	plate.name = "DossierPlate"
	plate.texture = plate_tex
	plate.flip_h = true
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.size = plate_size
	plate.position = Vector2(24.0, 0.0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(plate)

	# 竖脊与板同高（板 344，上下各留 18px 边）。
	var spine := Ornaments.spine(344.0 - 36.0)
	spine.name = "DossierSpine"
	spine.position = Vector2(2.0, 18.0)
	_dossier_spine = spine
	wrap.add_child(spine)

	var panel := PanelContainer.new()
	panel.name = "Dossier"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24.0 + arrow + 18.0
	panel.offset_top = 18.0
	panel.offset_right = -(408.0 - (24.0 + plate_size.x) + 18.0)
	panel.offset_bottom = -26.0
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	# 标题行：左右各一道短角铁，和铁架的分组横线同一语汇。
	var head_row := HBoxContainer.new()
	head_row.name = "DossierHeadRow"
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_theme_constant_override("separation", 8)
	box.add_child(head_row)
	var stub_l := Ornaments.stub_rule(true)
	stub_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(stub_l)
	var head := UiKit.label("行 程 档 案", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	head.modulate = UiKit.EMBER
	head.name = "DossierHead"
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head)
	var stub_r := Ornaments.stub_rule(false)
	stub_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(stub_r)
	box.add_child(Ornaments.rivet_rule(280.0))
	_add_dossier_row(box, "Rank", "余 烬 阶 位")
	_add_dossier_row(box, "Skin", "当 前 外 观")
	_add_dossier_row(box, "Trials", "回 火 试 炼")
	_add_dossier_row(box, "Arena", "余 烬 竞 技 场")
	_add_dossier_row(box, "Chapter", "上 次 行 程")
	if not TrialCatalogScript.unlocked():
		var trial_hint := UiKit.label("通关第七章或任一结局后解锁「回火试炼」",
				&"FootnoteLabel")
		trial_hint.name = "TrialLockHint"
		trial_hint.modulate = UiKit.ASH
		trial_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		trial_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trial_hint.custom_minimum_size = Vector2(0.0, 28.0)
		box.add_child(trial_hint)
	var hint := UiKit.label("Tab 查看目标 · Esc 暂停 · 章节存档记录在烬巢",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint.name = "DossierHint"
	hint.modulate = UiKit.ASH
	box.add_child(hint)
	_update_notice = Button.new()
	_update_notice.name = "UpdateNotice"
	_update_notice.text = "有 新 版 本 · 查 看"
	_update_notice.theme_type_variation = &"SettingsButton"
	# 档案行都是 16px 小字，按钮保持同量级：stylebox 自带 6px 上下边距，
	# 这里显式压掉，22px 一行才和 TinyStrongLabel 行高协调（默认会撑到 40）。
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb := _update_notice.get_theme_stylebox(st).duplicate() as StyleBox
		if sb != null:
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			_update_notice.add_theme_stylebox_override(st, sb)
	_update_notice.custom_minimum_size = Vector2(0.0, 22.0)
	_update_notice.size_flags_horizontal = Control.SIZE_SHRINK_END
	_update_notice.add_theme_font_size_override("font_size", 12)
	_update_notice.focus_mode = Control.FOCUS_ALL
	_update_notice.visible = false
	_update_notice.pressed.connect(_open_update_prompt)
	box.add_child(_update_notice)
	# 弹性留白把收口推到底边，行文与底注之间不留悬空。
	var flex := Control.new()
	flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(flex)
	# 底部收口：短角铁 + 小注，和铁架底部的铆钉呼应。
	var foot_rule := Ornaments.stub_rule(false)
	foot_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(foot_rule)
	var foot := UiKit.label("档 案 随 存 档 更 新", &"FootnoteLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	foot.name = "DossierFoot"
	foot.modulate = UiKit.ASH
	box.add_child(foot)
	_refresh_dossier()

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
	tag.custom_minimum_size = Vector2(84.0, 0.0)
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
	var has_save := SaveData.has_save()
	var rank_text := "尚无余烬 · 点燃后开始记录"
	if has_save:
		# 一行放得下：阶位 + 阶名 + 属性点；XP 进度在角色面板里看。
		rank_text = "%d 阶 · %s · 点 %d" % [SaveData.ember_rank,
				EmberRankScript.name_for_rank(SaveData.ember_rank),
				SaveData.attribute_points]
	_dossier_values["Rank"].text = rank_text

	var skin := StringName(SaveData.skin_id) if SaveData.skin_id != "" else SkinCatalogScript.DEFAULT_SKIN
	_dossier_values["Skin"].text = SkinCatalogScript.name_of(skin)

	var trial_text := "未踏足"
	if ResourceLoader.exists("res://scripts/data/trial_records.gd"):
		var all: Dictionary = TrialRecordsScript.all()
		var count := 0
		for track in all.values():
			if track is Dictionary:
				count += (track as Dictionary).size()
		if count > 0:
			trial_text = "%d 条记录" % count
	_dossier_values["Trials"].text = trial_text

	var arena_text := "未踏足"
	var arena_records: Dictionary = ArenaRunScript.read_records()
	if int(arena_records.get("runs", 0)) > 0:
		arena_text = "最佳 %d 分 · %d 场" % [
			int(arena_records.get("best_score", 0)), int(arena_records.get("runs", 0))]
	_dossier_values["Arena"].text = arena_text

	var chapter_text := "尚无旅程"
	if has_save and SaveData.data.has("meta"):
		var scene := String((SaveData.data["meta"] as Dictionary).get("scene", ""))
		var level_id := ""
		for id in GameContext.LEVELS:
			if String(GameContext.LEVELS[id]) == scene:
				level_id = String(id)
				break
		if level_id != "":
			chapter_text = ChapterText.title_of(level_id)
			var recap := ChapterText.recap_of(level_id)
			if recap != "":
				chapter_text = recap
			if chapter_text.length() > 18:
				chapter_text = chapter_text.substr(0, 18) + "…"
	_dossier_values["Chapter"].text = chapter_text


func _build_chrome() -> void:
	var band := UiKit.panel(&"BandPanel")
	band.name = "CreditBand"
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 1.0
	band.anchor_bottom = 1.0
	band.offset_top = -BAND_HEIGHT
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	band.add_child(row)

	var credits := UiKit.label(
			"美术 ansimuz · aamatniekss · Kronovi · CodeManu · Kenney — 音频 Kenney",
			&"FootnoteLabel")
	credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	credits.modulate = Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.9)
	row.add_child(credits)

	var hint := UiKit.label("字体 Fusion Pixel (OFL) · ↑↓ 选择 · Enter 确认",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 操作提示染成余烬色：署名带里只有这一行是"给玩家的指令"，
	# 同行的署名是纯信息，两行不能同权。
	hint.modulate = UiKit.EMBER_ASH
	row.add_child(hint)


## 开屏：黑幕与 keyart 交叉淡入淡出 → 字标跟着亮 → 菜单架逐行爬上来 →
## 脊柱、墓志、署名带收尾。整段约 1.1 秒，期间不挡操作（菜单一直可点）。
## 任何一步都可以被 _skip_intro() 一把跳过：玩家进设置再回来、或者换关回来时
## 不该被同一段开场拖第二次。
func _play_intro() -> void:
	_intro_playing = true
	# 菜单架在开屏期间保持 active：悬停/上下键照常工作，确认键由 _on_chosen
	# 跳过开屏后照常执行——进场动画不是输入门禁，只是"还没演完"。
	# 黑幕：盖住整个窗口（内容矩形外也有边），与 keyart 交叉淡出。
	_curtain = ColorRect.new()
	_curtain.name = "BootCurtain"
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.color = Color.BLACK
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_curtain)

	# 场景四件套的初始态：全透明，等帷幕退去后依次渗出来。
	_keyart.modulate.a = 0.0
	_masthead.modulate.a = 0.0
	_spine.modulate.a = 0.0
	# 新节点也参与开屏：链条/骑士光影/右栏与脊柱同一拍淡入，避免"啪"地出现。
	for extra in [_rail_chain, _dossier_chain, _dossier_wrap, _dossier_spine,
			_dossier_jag, _knight_light]:
		if extra is CanvasItem:
			(extra as CanvasItem).modulate.a = 0.0
	var inscription := get_node_or_null("Inscription")
	if inscription != null:
		(inscription as CanvasItem).modulate.a = 0.0
	var band := get_node_or_null("CreditBand")
	if band != null:
		(band as CanvasItem).modulate.a = 0.0
	for child in _menu.get_children():
		var control := child as Control
		if control != null:
			control.modulate.a = 0.0

	# 并行时间轴：每段自带 set_delay，总时长 = 最大 (delay + duration)。
	var tw := create_tween()
	tw.set_parallel(true)
	# 0.00s 黑幕退去，keyart 同时渗出来（火光先着）。
	tw.tween_property(_curtain, "modulate:a", 0.0, BOOT_FADE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_keyart, "modulate:a", 1.0, BOOT_FADE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 0.35s 字标醒过来：比 keyart 晚半拍，logo 辉光跟着更快一点的节奏。
	tw.tween_property(_masthead, "modulate:a", 1.0, INTRO_DURATION) \
			.set_delay(BOOT_FADE * 0.64) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 右侧档案/垂链/骑士光与脊柱同一批淡入。
	var side_delay := BOOT_FADE * 0.9
	for extra in [_rail_chain, _dossier_chain, _dossier_wrap, _dossier_spine,
			_dossier_jag, _knight_light]:
		if extra is CanvasItem:
			tw.tween_property(extra, "modulate:a", 1.0, RAIL_DURATION) \
					.set_delay(side_delay)
	# 0.50s 起菜单逐行爬上来（0.045s/行），脊柱同步淡入。
	var delay := BOOT_FADE * 0.9
	for child in _menu.get_children():
		var control := child as Control
		if control == null:
			continue
		tw.tween_property(control, "modulate:a", 1.0, RAIL_DURATION) \
				.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		delay += RAIL_STAGGER
	tw.tween_property(_spine, "modulate:a", 1.0, RAIL_DURATION) \
			.set_delay(BOOT_FADE * 0.9) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 墓志和署名带最后收尾（菜单爬完的那一刻）。
	tw.tween_property(inscription, "modulate:a", 1.0, RAIL_DURATION + 0.1) \
			.set_delay(delay) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(band, "modulate:a", 1.0, RAIL_DURATION + 0.1) \
			.set_delay(delay) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 收尾：全部就位后撤掉黑幕、置回非播放态。
	var total := delay + RAIL_DURATION + 0.1
	tw.tween_callback(func() -> void:
		_intro_playing = false
		if _curtain != null and is_instance_valid(_curtain):
			_curtain.queue_free()
			_curtain = null
	).set_delay(total)


## 跳过开屏：直接落到终态（不删帷幕之外的东西，_quit_sequence 还要用）。
func _skip_intro() -> void:
	if not _intro_playing:
		return
	_intro_playing = false
	# 把还挂着的入场 tween 一次抹平：子节点各自 create_tween 的那批
	# 随节点释放而失效，这里直接把透明状态和位置落到位。
	Transitions.snap_visible([
			_keyart, _masthead, _spine,
			get_node_or_null("Inscription"),
			get_node_or_null("CreditBand"),
			_knight_light, _dossier_wrap, _dossier_spine, _dossier_jag,
			_rail_chain, _dossier_chain,
	])
	for child in _menu.get_children():
		var control := child as Control
		if control != null:
			control.modulate.a = 1.0
	if _curtain != null and is_instance_valid(_curtain):
		_curtain.queue_free()
		_curtain = null


## 开屏是否还在播（测试与 _on_chosen 用：动画期间选择键不响应）。
func intro_playing() -> bool:
	return _intro_playing


func _build_overlays() -> void:
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


func _process(delta: float) -> void:
	_time += delta
	_animate_chains()
	if _quitting or _intro_playing:
		# 退场/开屏动画期间 keyart / 字标的呼吸会让位给 tween，
		# 否则 _process 会和 tween 抢同一个 modulate 属性。
		return
	# 火光呼吸：keyart 整体在暖色间轻微起伏，标题牌辉光跟着更快一点的节奏。
	var warm := 0.5 + 0.5 * sin(TAU * _time / KEYART_BREATH_PERIOD)
	_keyart.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.06, 0.94, 0.86), warm)
	var glow := 0.5 + 0.5 * sin(TAU * _time / LOGO_BREATH_PERIOD)
	_masthead.modulate = Color(0.94, 0.94, 0.94).lerp(Color(1.10, 1.04, 0.98), glow)


## 两条吊链缓慢摆动：只做整数像素横移，像素字/链环不会发虚。
func _animate_chains() -> void:
	if _rail_chain != null and is_instance_valid(_rail_chain):
		_rail_chain.position.x = _rail_chain_base + roundf(sin(_time * 0.65) * 2.0)
	if _dossier_chain != null and is_instance_valid(_dossier_chain):
		_dossier_chain.position.x = _dossier_chain_base + roundf(sin(_time * 0.65 + 1.7) * 2.0)


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
			_start(true)
		ID_TRIAL:
			_menu.active = false
			Sfx.play(&"gate")
			Director.fade_to(TRIAL_MENU, 0.5)
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


func _on_update_checked(status: StringName, _entry: Dictionary) -> void:
	if status != &"available":
		return
	if _update_notice == null or not is_instance_valid(_update_notice):
		return
	_update_notice.visible = true


## 版本提示从"菜单架多一行"挪到档案里的小按钮：模式组固定五格，不会被动态行撑出屏幕。
func _open_update_prompt() -> void:
	if _quitting or _started:
		return
	if _intro_playing:
		_skip_intro()
	_menu.active = false
	if _update_prompt != null:
		_update_prompt.open(UpdateService.entry())


## 离开锈墓的退场：菜单架逐格熄灭、背景与余烬一起暗下去，黑幕压上来后留一句
## "余烬熄灭"再退出进程。总长约 2.1 秒，任何输入都能立刻跳到退出。
func _quit_sequence() -> void:
	if _quitting or _started:
		return
	# 开屏中途离开：先把入场动画抹平，否则逐格熄灭会和淡入的 tween 抢属性。
	if _intro_playing:
		_skip_intro()
	_quitting = true
	_menu.active = false
	Sfx.play(&"ui_back")
	# 音乐先让路，给铁门声留出空间。
	Music.duck(-10.0, 1.6)
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

	# 字标、墓志、署名带、火花一起暗下去：TitleScreen 的直系画布子节点里，
	# 黑幕和菜单自己另有安排，跳过它们。
	for child in get_children():
		if not (child is CanvasItem) or child == _fade or child == _menu:
			continue
		_quit_tween.tween_property(child, "modulate:a", 0.0, QUIT_SCENE_FADE) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 铁门落下的闷响：进关用 gate，离开锈墓也用 gate，一来一去。
	_quit_tween.tween_callback(func() -> void: Sfx.play(&"gate", 0.0, -6.0)) \
			.set_delay(QUIT_BLACKOUT_DELAY)

	# 黑幕压上来，最后浮出一句墓志。
	_quit_tween.tween_property(_fade, "color:a", 1.0, QUIT_BLACKOUT) \
			.set_delay(QUIT_BLACKOUT_DELAY) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_quit_tween.tween_property(_quit_caption, "modulate:a", 1.0, QUIT_CAPTION_FADE) \
			.set_delay(QUIT_CAPTION_DELAY) \
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
	Director.fade_to(target, FADE_OUT)


func _exit_tree() -> void:
	if UpdateService.checked.is_connected(_on_update_checked):
		UpdateService.checked.disconnect(_on_update_checked)
	WorldClock.release_menu()
