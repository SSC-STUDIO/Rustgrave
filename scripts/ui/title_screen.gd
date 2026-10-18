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
## 回火试炼（新游戏模式）：入口由战役解锁旗标控制（契约 §5）。
const TrialCatalogScript := preload("res://scripts/data/trial_catalog.gd")
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
const RAIL_TOP := 250.0
const SPINE_X := 92.0
const DIVIDER_W := 440.0
## 行间空白（像素）：主行动成一簇、次行动成一簇、"离开"单独挂在最下。
const GAP_PRIMARY := 10.0
const GAP_GROUP := 20.0
const GAP_DIVIDER := 14.0
const GAP_SECONDARY := 6.0
const GAP_QUIT := 12.0
const INTRO_STAGGER := 0.045
const INTRO_DURATION := 0.22

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
const ID_SETTINGS := &"settings"
const ID_CONTROLS := &"controls"
const ID_QUIT := &"quit"
const ID_KEEP := &"keep"
const ID_OVERWRITE := &"overwrite"

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
var _fade: ColorRect
var _quit_caption: Label
var _quitting := false
var _quit_done := false
var _quit_tween: Tween
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
	_build_chrome()
	# 覆盖层最后加：Control 的绘制与鼠标拾取都按子节点顺序，越后越上。
	_build_overlays()
	_play_rail_intro()


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
	_menu.add_item(ID_NEW, "点 燃 余 烬", false, MenuItem.Kind.PRIMARY)
	_gap(GAP_PRIMARY)
	var cont := "回 看 余 烬" if SaveData.peek_ending() != "" else "继 续 旅 程"
	_menu.add_item(ID_CONTINUE, cont, not has_save, MenuItem.Kind.PRIMARY)
	_gap(GAP_PRIMARY)
	# 第三条主行动：回火试炼。未解锁（没通关第七章 / 没走完结局）时置灰。
	var trial_ready := TrialCatalogScript.unlocked()
	_menu.add_item(ID_TRIAL, "回 火 试 炼", not trial_ready, MenuItem.Kind.PRIMARY)
	_gap(GAP_GROUP)
	_menu.add_child(_rail_divider())
	_gap(GAP_DIVIDER)
	_menu.add_item(ID_SETTINGS, "设 置", false, MenuItem.Kind.SECONDARY)
	_gap(GAP_SECONDARY)
	_menu.add_item(ID_CONTROLS, "操 作 说 明", false, MenuItem.Kind.SECONDARY)
	_gap(GAP_QUIT)
	_menu.add_item(ID_QUIT, "离 开 锈 墓", false, MenuItem.Kind.GHOST)
	_menu.reset_size()
	_menu.chosen.connect(_on_chosen)

	# 竖脊：从第一格的主行动一直串到"离开"，两端各一颗铆钉。
	_spine = Ornaments.spine(_menu.size.y - 16.0)
	_spine.name = "RailSpine"
	_spine.position = Vector2(SPINE_X, RAIL_TOP + 8.0)
	add_child(_spine)
	# 叠在菜单之下：先加进来的先画，回头把脊挪到菜单下面。
	move_child(_spine, _menu.get_index())

	# 未解锁时用一行 12px 小字说明解锁条件（试炼入口保持置灰）。
	if not trial_ready:
		var trial_hint := UiKit.label("通关第七章或任一结局后解锁「回火试炼」",
				&"FootnoteLabel")
		trial_hint.name = "TrialLockHint"
		trial_hint.position = Vector2(RAIL_X, RAIL_TOP + _menu.size.y + 10.0)
		add_child(trial_hint)

	# 有存档时光标默认停在"继续"：回车不会再一键抹掉进度。
	if has_save:
		_menu.select(1, false)


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
	strip.anchor_left = 0.0
	strip.anchor_right = 1.0
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_left = 96.0
	strip.offset_right = -96.0
	strip.offset_top = -(BAND_HEIGHT + 96.0)
	strip.offset_bottom = -(BAND_HEIGHT + 40.0)
	add_child(strip)

	var row := HBoxContainer.new()
	row.name = "EpitaphRow"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)

	var left := Ornaments.stub_rule(true)
	left.name = "EpitaphRuleLeft"
	_pack(left)
	row.add_child(left)

	var epitaph := UiKit.label(EPITAPH, &"EpitaphLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	epitaph.name = "Epitaph"
	epitaph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pack(epitaph)
	row.add_child(epitaph)

	var right := Ornaments.stub_rule(false)
	right.name = "EpitaphRuleRight"
	_pack(right)
	row.add_child(right)


## 底部装饰带：署名靠左、导航提示靠右，都排进同一条锈色铆钉带里。
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
	row.add_child(credits)

	var hint := UiKit.label("字体 Fusion Pixel (OFL) · ↑↓ 选择 · Enter 确认",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(hint)


## 开屏：菜单架从上往下逐行渗出来，脊柱和横线同时淡入。整段 < 0.5 秒，不挡操作。
func _play_rail_intro() -> void:
	var delay := 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	for child in _menu.get_children():
		var control := child as Control
		if control == null:
			continue
		control.modulate.a = 0.0
		tween.tween_property(control, "modulate:a", 1.0, INTRO_DURATION) \
				.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		delay += INTRO_STAGGER
	_spine.modulate.a = 0.0
	var spine_tween := create_tween()
	spine_tween.tween_property(_spine, "modulate:a", 1.0, INTRO_DURATION + 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
	if _quitting:
		# 退场动画期间 keyart / 字标的呼吸会让位给淡出 tween。
		return
	_time += delta
	# 火光呼吸：keyart 整体在暖色间轻微起伏，标题牌辉光跟着更快一点的节奏。
	var warm := 0.5 + 0.5 * sin(TAU * _time / KEYART_BREATH_PERIOD)
	_keyart.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.06, 0.94, 0.86), warm)
	var glow := 0.5 + 0.5 * sin(TAU * _time / LOGO_BREATH_PERIOD)
	_masthead.modulate = Color(0.94, 0.94, 0.94).lerp(Color(1.10, 1.04, 0.98), glow)


func _on_chosen(id: StringName) -> void:
	if _started or _quitting:
		return
	match id:
		ID_NEW:
			# 有存档时"点燃余烬"会清档重来：先问一句，默认项是取消。
			if SaveData.has_save():
				open_confirm()
			else:
				_start(false)
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
		ID_QUIT:
			_quit_sequence()


## 离开锈墓的退场：菜单架逐格熄灭、背景与余烬一起暗下去，黑幕压上来后留一句
## "余烬熄灭"再退出进程。总长约 2.1 秒，任何输入都能立刻跳到退出。
func _quit_sequence() -> void:
	if _quitting or _started:
		return
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
		_start(false)
	else:
		close_confirm()


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
	WorldClock.release_menu()
