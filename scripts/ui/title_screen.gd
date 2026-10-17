class_name TitleScreen
extends Control
## 标题屏：keyart + 字标与插座剑 + 墓志 + 铆钉横线 + 四项菜单。
##
## 菜单由 MenuList 负责键鼠导航，操作说明复用 ControlsPanel（与暂停菜单同一份）。
## 气氛三件套：keyart 火光呼吸、字标辉光呼吸、上升余烬与飘落灰烬。
## 标题、墓志、横线、菜单收成一列，间距用主题的 10px，底部让开署名带。

const KEYART_PATH := "res://assets/kenney_clean/backgrounds/title_keyart.png"
const LEVEL_PATH := "res://scenes/levels/Level01_Static.tscn"
const Ornaments := preload("res://scripts/ui/title_ornament.gd")

const EMBERS_RISING := 30
const EMBERS_FALLING := 14
const KEYART_BREATH_PERIOD := 5.5
const LOGO_BREATH_PERIOD := 3.2
const FADE_OUT := 0.7
const BAND_HEIGHT := 34.0
## 角饰要躲开底部装饰带，否则会跟署名文字撞在一起。
const CORNER_INSET := 16.0
const TOP_INSET := 36.0
## 列的底边停在署名带之上，菜单再长也不会压进铆钉带。
const FOOTER_GAP := 20.0
## 墓志取自「失败的净化偶自己先锈透」。一句，不是台词。
const EPITAPH := "失败的净化偶，自己先锈透了。"

const ID_NEW := &"new"
const ID_CONTINUE := &"continue"
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
var _controls: ControlsPanel
var _settings: SettingsScreen
var _confirm: CanvasLayer
var _confirm_menu: MenuList
var _fade: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	DisplayServer.window_set_title("Rustgrave")
	DisplayFit.apply()
	WorldClock.hold_for_menu()
	_build_backdrop()
	_build_stack()
	_build_chrome()
	# 覆盖层最后加：Control 的绘制与鼠标拾取都按子节点顺序，越后越上。
	_build_overlays()


func _build_backdrop() -> void:
	_keyart = TextureRect.new()
	_keyart.name = "Keyart"
	_keyart.set_anchors_preset(Control.PRESET_FULL_RECT)
	_keyart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_keyart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_keyart.texture = UiKit.tex(KEYART_PATH)
	_keyart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keyart)

	# 上下压暗：墓志和菜单要压住拱顶的光柱，中段仍把骑士留出来，并盖掉右下角水印。
	add_child(UiKit.scrim(0.74, 0.26, 0.90))
	add_child(UiKit.EmberField.build(Rect2(Vector2.ZERO, Vector2(1280, 720)),
			EMBERS_RISING, EMBERS_FALLING))
	UiKit.corner_brackets(self, CORNER_INSET, BAND_HEIGHT + CORNER_INSET)


## 字标、墓志、铆钉线、菜单同一列、同一档间距，水平居中。
func _build_stack() -> void:
	var column := VBoxContainer.new()
	column.name = "TitleColumn"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_top = TOP_INSET
	column.offset_bottom = -(BAND_HEIGHT + FOOTER_GAP)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_masthead = HBoxContainer.new()
	_masthead.name = "Masthead"
	_masthead.alignment = BoxContainer.ALIGNMENT_CENTER
	_pack(_masthead)
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

	var epitaph_row := HBoxContainer.new()
	epitaph_row.name = "EpitaphRow"
	epitaph_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pack(epitaph_row)
	column.add_child(epitaph_row)

	var epitaph_left := Ornaments.stub_rule(true)
	epitaph_left.name = "EpitaphRuleLeft"
	_pack(epitaph_left)
	epitaph_row.add_child(epitaph_left)

	var epitaph := UiKit.label(EPITAPH, &"EpitaphLabel", HORIZONTAL_ALIGNMENT_CENTER)
	epitaph.name = "Epitaph"
	_pack(epitaph)
	epitaph_row.add_child(epitaph)

	var epitaph_right := Ornaments.stub_rule(false)
	epitaph_right.name = "EpitaphRuleRight"
	_pack(epitaph_right)
	epitaph_row.add_child(epitaph_right)

	var rule := Ornaments.rivet_rule()
	rule.name = "RivetRule"
	_pack(rule)
	column.add_child(rule)

	_menu = MenuList.new()
	_menu.name = "Menu"
	_pack(_menu)
	column.add_child(_menu)
	_menu.add_item(ID_NEW, "点 燃 余 烬")
	var cont := "回 看 余 烬" if SaveData.peek_ending() != "" else "继 续 旅 程"
	var has_save := SaveData.has_save()
	_menu.add_item(ID_CONTINUE, cont, not has_save)
	_menu.add_item(ID_SETTINGS, "设 置")
	_menu.add_item(ID_CONTROLS, "操 作 说 明")
	_menu.add_item(ID_QUIT, "离 开 锈 墓")
	# 有存档时光标默认停在"继续"：回车不会再一键抹掉进度。
	if has_save:
		_menu.select(1, false)
	_menu.chosen.connect(_on_chosen)


func _pack(node: Control) -> void:
	node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER


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


func _process(delta: float) -> void:
	_time += delta
	# 火光呼吸：keyart 整体在暖色间轻微起伏，标题牌辉光跟着更快一点的节奏。
	var warm := 0.5 + 0.5 * sin(TAU * _time / KEYART_BREATH_PERIOD)
	_keyart.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.06, 0.94, 0.86), warm)
	var glow := 0.5 + 0.5 * sin(TAU * _time / LOGO_BREATH_PERIOD)
	_masthead.modulate = Color(0.94, 0.94, 0.94).lerp(Color(1.10, 1.04, 0.98), glow)


func _on_chosen(id: StringName) -> void:
	if _started:
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
		ID_SETTINGS:
			_menu.active = false
			_settings.open()
		ID_CONTROLS:
			_menu.active = false
			_controls.open()
		ID_QUIT:
			get_tree().quit()


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
	root.add_child(UiKit.scrim(0.90, 0.90, 0.90))
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
	_confirm_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_confirm_menu.active = false
	column.add_child(_confirm_menu)
	_confirm_menu.add_item(ID_KEEP, "取 消")
	_confirm_menu.add_item(ID_OVERWRITE, "确 认 覆 盖")
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
