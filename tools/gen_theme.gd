extends SceneTree
## 生成 res://assets/ui/theme_rust.tres —— 全项目共用的锈墓 UI 主题。
##
## 主题是 UI 外观的唯一权威：字体/字号/配色/9-slice 面板全部写在这里，
## 界面脚本只负责结构与动效，不再散落 add_theme_*_override。
## 重新生成： & Godot --headless --path . --script res://tools/gen_theme.gd

const OUT_PATH := "res://assets/ui/theme_rust.tres"
const FONT_PATH := "res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"

## 缝合像素字体的设计尺寸是 12px；只允许整数倍，否则字形会被重采样糊掉。
const SIZE_SMALL := 12
const SIZE_BODY := 24
const SIZE_HEAD := 36

const BONE := Color("#E4DCCC")
const BONE_DIM := Color("#A39A8E")
const BONE_EPITAPH := Color("#C8BBA8")
const BONE_FAINT := Color("#8E8578")
const EMBER := Color("#FFC14A")
const EMBER_ASH := Color("#E8B090")
const RUST_LIGHT := Color("#CD5C5C")
const SLUDGE_LIT := Color("#9ED092")
const TEXT_DISABLED := Color("#5E574F")
## 12px 小字的描边色：与文字投影同源的暗色，alpha 略高，保证压在任何背景上都读得出。
const OUTLINE_DARK := Color(0.04, 0.03, 0.06, 0.92)
const SHADOW := Color(0.04, 0.03, 0.06, 0.85)


func _init() -> void:
	var theme := Theme.new()
	var font := load(FONT_PATH) as Font
	if font == null:
		push_error("字体缺失：" + FONT_PATH)
		quit(1)
		return
	theme.default_font = font
	theme.default_font_size = SIZE_BODY

	_setup_labels(theme)
	_setup_panels(theme)
	_setup_buttons(theme)
	_setup_bars(theme)
	_setup_containers(theme)

	var err := ResourceSaver.save(theme, OUT_PATH)
	if err != OK:
		push_error("主题保存失败 err=%d" % err)
		quit(1)
		return
	print("wrote ", OUT_PATH)
	quit()


## 9-slice 贴图样式盒。margin 为贴图边距（像素），content 为内容内缩。
func _sb(path: String, margin: Vector4, content: Vector4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path) as Texture2D
	sb.texture_margin_left = margin.x
	sb.texture_margin_top = margin.y
	sb.texture_margin_right = margin.z
	sb.texture_margin_bottom = margin.w
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w
	return sb


## 菜单行样式盒：中段平铺，让贴图里的抖动斑点按 1:1 重复而不是被拉成一片纯色。
func _row(path: String, margin: Vector4, content: Vector4) -> StyleBoxTexture:
	var sb := _sb(path, margin, content)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sb


func _setup_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", BONE)
	theme.set_color("font_shadow_color", "Label", SHADOW)
	# 阴影偏移保持偶数，跟 2x 的 UI 像素栅格对齐。
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_constant("line_spacing", "Label", 4)

	## 变体清单：名称 -> [字号, 颜色, 是否要投影]
	## HUD 紧凑小字（Hud* / Tiny*，12px）改用 1px 描边而不是投影：投影在 12px 字上
	## 会把笔画糊成一团，描边能保证压在任何背景上都读得出。
	var variations := {
		"HeadLabel": [SIZE_HEAD, EMBER, true],
		"SubHeadLabel": [SIZE_BODY, EMBER_ASH, true],
		"BodyLabel": [SIZE_BODY, BONE, false],
		"DimLabel": [SIZE_BODY, BONE_DIM, false],
		"EpitaphLabel": [SIZE_BODY, BONE_EPITAPH, true],
		"KeyCapLabel": [SIZE_BODY, EMBER, false],
		"HudLabel": [SIZE_SMALL, BONE_DIM, true],
		"HudStrongLabel": [SIZE_SMALL, EMBER_ASH, true],
		"HudToxinLabel": [SIZE_SMALL, SLUDGE_LIT, true],
		# Tiny* 是 HUD 紧凑小字的同一档（12px + 1px 描边），与 Hud* 同源同色；
		# 两个名字都保留，免得 UI 脚本一半用 Tiny 一半用 Hud。
		"TinyLabel": [SIZE_SMALL, BONE_DIM, true],
		"TinyStrongLabel": [SIZE_SMALL, EMBER_ASH, true],
		"TinyToxinLabel": [SIZE_SMALL, SLUDGE_LIT, true],
		"PromptLabel": [SIZE_BODY, EMBER, true],
		"AnnounceLabel": [SIZE_BODY, EMBER_ASH, true],
		"FootnoteLabel": [SIZE_SMALL, BONE_FAINT, true],
		"MenuItemLabel": [SIZE_BODY, BONE, true],
		"MenuItemLabelSelected": [SIZE_BODY, EMBER, true],
		"MenuItemLabelDisabled": [SIZE_BODY, TEXT_DISABLED, false],
	}
	for name in variations:
		var spec: Array = variations[name]
		theme.set_type_variation(name, "Label")
		theme.set_font_size("font_size", name, spec[0])
		theme.set_color("font_color", name, spec[1])
		if not bool(spec[2]):
			theme.set_constant("shadow_offset_x", name, 0)
			theme.set_constant("shadow_offset_y", name, 0)
	# 24px 的强调字（横幅 / 交互提示 / 播报）保留 2px 暗描边，和投影叠加出立体感；
	# 12px 的小字只描 1px —— 描边一粗，像素字的笔画就被吃掉了。
	for name in ["PromptLabel", "AnnounceLabel", "MenuItemLabel", "MenuItemLabelSelected",
			"SubHeadLabel", "HeadLabel", "EpitaphLabel"]:
		theme.set_color("font_outline_color", name, OUTLINE_DARK)
		theme.set_constant("outline_size", name, 2)
	# 12px 的小字统一走 1px 暗描边，不要 2px 投影（会把像素笔画糊掉）。
	for name in ["HudLabel", "HudStrongLabel", "HudToxinLabel",
			"TinyLabel", "TinyStrongLabel", "TinyToxinLabel", "FootnoteLabel"]:
		theme.set_color("font_outline_color", name, OUTLINE_DARK)
		theme.set_constant("outline_size", name, 1)
		theme.set_constant("line_spacing", name, 0)


func _setup_panels(theme: Theme) -> void:
	## 面板内腔是抖动斑点，所以中段同样要平铺。
	var stone := _row("res://assets/ui/panel_stone.png",
			Vector4(10, 10, 10, 10), Vector4(18, 14, 18, 14))
	var ornate := _row("res://assets/ui/panel_ornate.png",
			Vector4(18, 18, 18, 18), Vector4(34, 30, 34, 30))
	var hud := _row("res://assets/ui/panel_hud.png",
			Vector4(8, 8, 8, 8), Vector4(14, 10, 14, 10))
	var banner := _sb("res://assets/ui/banner.png",
			Vector4(22, 0, 22, 0), Vector4(28, 4, 28, 4))
	banner.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	## 底部装饰带：锈色发丝线压住上沿，铆钉留在左右两片切图里。
	var band := _sb("res://assets/ui/band_edge.png",
			Vector4(10, 6, 10, 2), Vector4(24, 10, 24, 6))

	theme.set_stylebox("panel", "Panel", stone)
	theme.set_stylebox("panel", "PanelContainer", stone)
	for variation in ["OrnatePanel", "HudPanel", "BannerPanel", "BandPanel"]:
		theme.set_type_variation(variation, "PanelContainer")
	theme.set_stylebox("panel", "OrnatePanel", ornate)
	theme.set_stylebox("panel", "HudPanel", hud)
	theme.set_stylebox("panel", "BannerPanel", banner)
	theme.set_stylebox("panel", "BandPanel", band)


func _setup_buttons(theme: Theme) -> void:
	## 菜单项左侧要留出余烬光标与小火盆的位置，所以左内边距比右侧宽得多。
	var content := Vector4(64, 12, 28, 12)
	var margin := Vector4(8, 8, 8, 8)
	var normal := _row("res://assets/ui/btn_normal.png", margin, content)
	var hover := _row("res://assets/ui/btn_hover.png", margin, content)
	var pressed := _row("res://assets/ui/btn_pressed.png", margin, content)
	var disabled := _row("res://assets/ui/btn_disabled.png", margin, content)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)

	## MenuItem 用 Panel 表达行底，靠切换变体换状态贴图（见 scripts/ui/menu_item.gd）。
	for variation in ["MenuRowNormal", "MenuRowSelected", "MenuRowDisabled"]:
		theme.set_type_variation(variation, "Panel")
	theme.set_stylebox("panel", "MenuRowNormal", normal)
	theme.set_stylebox("panel", "MenuRowSelected", hover)
	theme.set_stylebox("panel", "MenuRowDisabled", disabled)
	# 焦点框会叠在 normal 之上，这里留空：选中态由 hover 贴图统一表达。
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", BONE)
	theme.set_color("font_hover_color", "Button", EMBER)
	theme.set_color("font_pressed_color", "Button", EMBER_ASH)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)
	theme.set_color("font_focus_color", "Button", EMBER)


func _setup_bars(theme: Theme) -> void:
	## 槽的中段平铺而不是拉伸，贴图里那一道刻度就变成整条分段标尺。
	var track := _sb("res://assets/ui/bar_track.png",
			Vector4(4, 4, 4, 4), Vector4(0, 0, 0, 0))
	track.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	theme.set_stylebox("background", "ProgressBar", track)
	theme.set_stylebox("fill", "ProgressBar",
			_sb("res://assets/ui/bar_fill_toxin.png", Vector4(4, 4, 4, 4), Vector4(0, 0, 0, 0)))
	theme.set_font_size("font_size", "ProgressBar", SIZE_SMALL)
	theme.set_color("font_color", "ProgressBar", BONE_DIM)

	theme.set_type_variation("EmberBar", "ProgressBar")
	theme.set_stylebox("fill", "EmberBar",
			_sb("res://assets/ui/bar_fill_ember.png", Vector4(4, 4, 4, 4), Vector4(0, 0, 0, 0)))


func _setup_containers(theme: Theme) -> void:
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	theme.set_constant("h_separation", "GridContainer", 24)
	theme.set_constant("v_separation", "GridContainer", 8)
