class_name UiKit
extends Object
## UI 共用素材路径、配色与构件工厂。
##
## 外观规则全部写在 assets/ui/theme_rust.tres（项目默认主题）里，这里只提供
## “按主题变体造节点”的快捷方式和主题表达不了的东西（贴图路径、粒子）。
## 界面脚本不应再出现 add_theme_*_override —— 需要新样式就去加主题变体。

const THEME_PATH := "res://assets/ui/theme_rust.tres"
## 异形菜单板（标题屏 / 暂停菜单 / 设置页标签共用）。它只画图，不依赖 UiKit。
const Plate := preload("res://scripts/ui/menu_plate.gd")

const TEX_TITLE_LOGO := "res://assets/ui/title_logo.png"
const TEX_DIVIDER := "res://assets/ui/divider.png"
const TEX_CORNER := "res://assets/ui/corner_bracket.png"
const TEX_CURSOR := "res://assets/ui/cursor_spike.png"
const TEX_HEART_SLOT := "res://assets/ui/heart_slot.png"
const TEX_VIGNETTE := "res://assets/ui/vignette_blood.png"
const TEX_BAND := "res://assets/ui/band_edge.png"
const TEX_HUD_BACKING := "res://assets/ui/hud_backing.png"
const TEX_SOCKET_RING := "res://assets/ui/socket_ring.png"
const TEX_SOCKET_GEM := "res://assets/ui/socket_gem.png"
const TEX_BAR_TRACK := "res://assets/ui/bar_track.png"
const TEX_BAR_EMBER := "res://assets/ui/bar_fill_ember.png"
const TEX_BAR_TOXIN := "res://assets/ui/bar_fill_toxin.png"
const TEX_PANEL_HUD := "res://assets/ui/panel_hud.png"
const TEX_BTN_NORMAL := "res://assets/ui/btn_normal.png"
const TEX_BTN_HOVER := "res://assets/ui/btn_hover.png"
const TEX_BTN_PRESSED := "res://assets/ui/btn_pressed.png"
const TEX_BTN_DISABLED := "res://assets/ui/btn_disabled.png"

## 触控最小命中尺寸（设计单位）。所有可点的行、按钮不得低于它。
const TOUCH_MIN := 52.0

## 余烬帧表：由 CC0 的 CodeManu 火焰帧在 tools/gen_ui_kit.py 里蒸馏成 6x6 像素，
## 因此只能以整数倍缩放绘制 —— 非整数倍会让 6px 的粒子直接糊成一团。
const TEX_EMBER_MOTES := "res://assets/ui/ember_motes.png"
const MOTE_FRAMES := 8

## 代码侧需要的颜色（tint / 呼吸），与主题里的文字色同源。
const EMBER := Color("#FFC14A")
const EMBER_ASH := Color("#E8B090")
const RUST_MID := Color("#A0522D")
const ASH := Color("#8A8680")
const SCRIM := Color(0.02, 0.01, 0.03)


static func tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return ArtTexture.load_texture(path)


## 主题变体标签。variation 为空则用 Label 基础样式。
static func label(text: String, variation: StringName = &"",
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if variation != &"":
		l.theme_type_variation = variation
	return l


static func panel(variation: StringName = &"") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != &"":
		p.theme_type_variation = variation
	return p


## 像素贴图矩形：统一关掉过滤，避免 9-slice 之外的散件被插值糊掉。
static func sprite_rect(path: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(path)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 装饰横线。放进容器里也不会被拉伸变形（自然尺寸居中绘制）。
static func divider() -> TextureRect:
	var r := sprite_rect(TEX_DIVIDER)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	var art := r.texture
	if art != null:
		r.custom_minimum_size = art.get_size()
	return r


## 四角哥特花饰。inset 为距边缘的像素数，bottom_inset 可单独避开底部装饰带。
static func corner_brackets(parent: Control, inset: float = 10.0,
		bottom_inset: float = -1.0) -> void:
	var art := tex(TEX_CORNER)
	if art == null:
		return
	if bottom_inset < 0.0:
		bottom_inset = inset
	for i in 4:
		var r := TextureRect.new()
		r.texture = art
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.flip_h = i % 2 == 1
		r.flip_v = i >= 2
		r.anchor_left = 1.0 if r.flip_h else 0.0
		r.anchor_right = r.anchor_left
		r.anchor_top = 1.0 if r.flip_v else 0.0
		r.anchor_bottom = r.anchor_top
		var w := float(art.get_width())
		var h := float(art.get_height())
		r.offset_left = -(w + inset) if r.flip_h else inset
		r.offset_right = r.offset_left + w
		r.offset_top = -(h + bottom_inset) if r.flip_v else inset
		r.offset_bottom = r.offset_top + h
		r.modulate = Color(1, 1, 1, 0.85)
		parent.add_child(r)


## 竖向渐变遮罩：给 keyart 压暗上下两端，让标题与菜单文字站得住。
## 用渐变贴图而不是纯色块，避免出现生硬的色带边缘。
static func scrim(top: float, mid: float, bottom: float) -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.42, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(SCRIM.r, SCRIM.g, SCRIM.b, top),
		Color(SCRIM.r, SCRIM.g, SCRIM.b, mid),
		Color(SCRIM.r, SCRIM.g, SCRIM.b, mid),
		Color(SCRIM.r, SCRIM.g, SCRIM.b, bottom),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 4
	gt.height = 256
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(0.0, 1.0)
	var r := TextureRect.new()
	r.texture = gt
	r.stretch_mode = TextureRect.STRETCH_SCALE
	# 渐变要平滑，这一层是唯一允许线性过滤的 UI 贴图。
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 左侧横向渐变遮罩：标题屏的左下菜单架压在 keyart 的齿轮上，这一层把画面左侧
## 轻轻压暗（向右淡到全透），按钮上的文字和空心角标才站得住。
static func scrim_side(alpha: float = 0.40, width: float = 760.0) -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	grad.colors = PackedColorArray([
		Color(SCRIM.r, SCRIM.g, SCRIM.b, alpha),
		Color(SCRIM.r, SCRIM.g, SCRIM.b, alpha * 0.46),
		Color(SCRIM.r, SCRIM.g, SCRIM.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var r := TextureRect.new()
	r.texture = gt
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.anchor_left = 0.0
	r.anchor_right = 0.0
	r.anchor_top = 0.0
	r.anchor_bottom = 1.0
	r.offset_right = width
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 界面音效。音频包的 UI 音（ui_tick / ui_pause / hint_show）是可选的：
## 库里有就放它，没有就放 fallback（可为空 = 静音）。不直接引用 Sfx 的常量，
## 免得音频包改结构时这里编译不过。
static func sfx(key: StringName, fallback: StringName = &"") -> void:
	if has_sfx(key):
		Sfx.play(key)
	elif fallback != &"":
		Sfx.play(fallback)


static func has_sfx(key: StringName) -> bool:
	var script := Sfx.get_script() as Script
	if script == null:
		return false
	var library: Variant = script.get_script_constant_map().get("LIBRARY", null)
	return library is Dictionary and (library as Dictionary).has(key)


# --- 补充主题 ---------------------------------------------------------------
# theme_rust.tres 由 tools/gen_theme.gd 生成，覆盖字体/配色/面板/菜单行。滑条、
# HudPlate（HUD 墨带）、设置页按钮与提示条样式只服务 HUD 与设置界面，放在这个
# 运行时主题里，挂在各自的根节点上（Control.theme 向下继承，缺的类型回落到
# 项目主题），免得动生成器和生成物。
# 文字变体一律进 theme_rust.tres（含 12px 的 Hud*/Tiny* 小字），这里不再定义。

static var _extras: Theme
static var _font_baselines: Dictionary = {}
static var _text_scale := 1.0


## Scale shared themes from immutable baselines, preserving heading/body/small ratios.
## Updating a Theme emits changed, so labels and buttons already on screen refresh.
static func apply_text_scale(factor: float) -> void:
	_text_scale = clampf(factor, 0.85, 1.35)
	_scale_theme(load(THEME_PATH) as Theme)
	if _extras != null:
		_scale_theme(_extras)


static func _scale_theme(theme: Theme) -> void:
	if theme == null:
		return
	var id := theme.get_instance_id()
	if not _font_baselines.has(id):
		var sizes: Dictionary = {"default": theme.default_font_size}
		for type in theme.get_font_size_type_list():
			for key in theme.get_font_size_list(type):
				sizes[String(type) + "/" + key] = theme.get_font_size(key, type)
		_font_baselines[id] = sizes
	var baseline: Dictionary = _font_baselines[id]
	if int(baseline["default"]) > 0:
		theme.default_font_size = roundi(int(baseline["default"]) * _text_scale)
	for key in baseline:
		if key == "default":
			continue
		var parts := String(key).split("/")
		theme.set_font_size(parts[1], parts[0], roundi(int(baseline[key]) * _text_scale))



static func extras_theme() -> Theme:
	if _extras != null:
		return _extras
	var t := Theme.new()
	_extras_panels(t)
	_extras_labels(t)
	_extras_buttons(t)
	_extras_slider(t)
	_extras_scrollbars(t)
	_extras_bars(t)
	_extras = t
	_scale_theme(t)
	return t


## 9-slice 贴图样式盒（与 gen_theme.gd 的 _sb 同义）。
static func _sb(path: String, margin: int, content: Vector4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(path)
	sb.texture_margin_left = margin
	sb.texture_margin_top = margin
	sb.texture_margin_right = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sb


static func _extras_panels(t: Theme) -> void:
	# 墨带：左侧锈脊 + 铆钉，右侧抖动渐隐（见 gen_ui_kit.py 的 hud_backing）。
	# 贴图 40x32：左切 12、右切 16，上下无边，所以高度随内容走。
	var plate := StyleBoxTexture.new()
	plate.texture = tex(TEX_HUD_BACKING)
	plate.texture_margin_left = 12
	plate.texture_margin_right = 16
	plate.content_margin_left = 20
	plate.content_margin_right = 22
	plate.content_margin_top = 4
	plate.content_margin_bottom = 4
	plate.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	t.set_type_variation(&"HudPlate", &"PanelContainer")
	t.set_stylebox("panel", &"HudPlate", plate)
	# 一行提示条：比 HudPanel 更薄，24px 字配上下 8px。
	t.set_type_variation(&"HintPanel", &"PanelContainer")
	t.set_stylebox("panel", &"HintPanel", _sb(TEX_PANEL_HUD, 8, Vector4(18, 8, 18, 8)))
	# 12px 的紧凑提示条（"Tab 目标 · 天气"）：同一块铁牌，墨带更薄，
	# 顶部只占 24 设计像素高，不再是一条压在画面上的大横幅。
	t.set_type_variation(&"HintPanelTiny", &"PanelContainer")
	t.set_stylebox("panel", &"HintPanelTiny", _sb(TEX_PANEL_HUD, 8, Vector4(16, 3, 16, 3)))
	# 交互提示的键帽：一块小铁牌装一个 24px 键名，和设置页的键位写法同源。
	t.set_type_variation(&"KeyCapPanel", &"PanelContainer")
	t.set_stylebox("panel", &"KeyCapPanel", _sb(TEX_BTN_NORMAL, 8, Vector4(12, 1, 12, 1)))
	# 设置页的行底（无光标留白）。
	t.set_type_variation(&"SettingsRowNormal", &"Panel")
	t.set_stylebox("panel", &"SettingsRowNormal", _sb(TEX_BTN_NORMAL, 8, Vector4.ZERO))
	t.set_type_variation(&"SettingsRowFocused", &"Panel")
	t.set_stylebox("panel", &"SettingsRowFocused", _sb(TEX_BTN_HOVER, 8, Vector4.ZERO))


static func _extras_labels(t: Theme) -> void:
	t.set_type_variation(&"HintLabel", &"Label")
	t.set_font_size("font_size", &"HintLabel", 24)
	t.set_color("font_color", &"HintLabel", Color("#E4DCCC"))
	t.set_color("font_shadow_color", &"HintLabel", Color(0.04, 0.03, 0.06, 0.85))
	t.set_constant("shadow_offset_x", &"HintLabel", 2)
	t.set_constant("shadow_offset_y", &"HintLabel", 2)
	t.set_type_variation(&"HintMarkLabel", &"Label")
	t.set_font_size("font_size", &"HintMarkLabel", 24)
	t.set_color("font_color", &"HintMarkLabel", EMBER)
	# 紧凑提示（12px）：只给"说明/提示"档，比 24px 的教学条矮一半 ——
	# 顶部那条"Tab 目标 · 天气"不该占掉 1/12 的画面。
	t.set_type_variation(&"TinyHintLabel", &"Label")
	t.set_font_size("font_size", &"TinyHintLabel", 12)
	t.set_color("font_color", &"TinyHintLabel", Color("#E4DCCC"))
	t.set_color("font_outline_color", &"TinyHintLabel", Color(0.04, 0.03, 0.06, 0.92))
	t.set_constant("outline_size", &"TinyHintLabel", 1)
	t.set_constant("line_spacing", &"TinyHintLabel", 0)
	# HUD 紧凑小字（Hud* / Tiny*）已收进项目主题 theme_rust.tres（12px + 1px 描边），
	# 这里不再重复定义 —— 主题是唯一权威，两处各写一份必然 drift。


static func _extras_buttons(t: Theme) -> void:
	for variation in [&"SettingsButton", &"KeyCapButton"]:
		t.set_type_variation(variation, &"Button")
		t.set_stylebox("normal", variation, _sb(TEX_BTN_NORMAL, 8, Vector4(14, 6, 14, 6)))
		t.set_stylebox("hover", variation, _sb(TEX_BTN_HOVER, 8, Vector4(14, 6, 14, 6)))
		t.set_stylebox("pressed", variation, _sb(TEX_BTN_PRESSED, 8, Vector4(14, 6, 14, 6)))
		t.set_stylebox("hover_pressed", variation, _sb(TEX_BTN_HOVER, 8, Vector4(14, 6, 14, 6)))
		t.set_stylebox("disabled", variation, _sb(TEX_BTN_DISABLED, 8, Vector4(14, 6, 14, 6)))
		# 键盘焦点画在 normal 之上：用 hover 贴图，和菜单的"选中"同一个样子。
		t.set_stylebox("focus", variation, _sb(TEX_BTN_HOVER, 8, Vector4(14, 6, 14, 6)))
		t.set_color("font_color", variation, Color("#E4DCCC"))
		t.set_color("font_hover_color", variation, EMBER)
		t.set_color("font_focus_color", variation, EMBER)
		t.set_color("font_pressed_color", variation, EMBER)
		t.set_color("font_hover_pressed_color", variation, EMBER)
		t.set_color("font_disabled_color", variation, Color("#5E574F"))
		t.set_font_size("font_size", variation, 24)
	t.set_color("font_color", &"KeyCapButton", EMBER)
	t.set_color("font_hover_color", &"KeyCapButton", Color("#FFE0A0"))
	t.set_color("font_focus_color", &"KeyCapButton", Color("#FFE0A0"))

	# 与菜单行同源的 TAG 牌：未选是暗铁，悬停/焦点/已选是金框。设置页标签页
	# 和页脚按钮都用它 —— 玩家在标题屏、暂停菜单、设置页看到的是同一个"选中"信号。
	for variation in [&"TabButton", &"PlateButton"]:
		t.set_type_variation(variation, &"Button")
		t.set_stylebox("normal", variation, Plate.style_box(Plate.Shape.TAG, Plate.State.NORMAL))
		t.set_stylebox("hover", variation, Plate.style_box(Plate.Shape.TAG, Plate.State.SELECTED))
		t.set_stylebox("pressed", variation, Plate.style_box(Plate.Shape.TAG, Plate.State.SELECTED))
		t.set_stylebox("hover_pressed", variation,
				Plate.style_box(Plate.Shape.TAG, Plate.State.SELECTED))
		t.set_stylebox("focus", variation, Plate.style_box(Plate.Shape.TAG, Plate.State.SELECTED))
		t.set_stylebox("disabled", variation, Plate.style_box(Plate.Shape.TAG, Plate.State.DISABLED))
		t.set_color("font_color", variation, Color("#E4DCCC"))
		t.set_color("font_hover_color", variation, EMBER)
		t.set_color("font_focus_color", variation, EMBER)
		t.set_color("font_pressed_color", variation, EMBER)
		t.set_color("font_hover_pressed_color", variation, EMBER)
		t.set_color("font_disabled_color", variation, Color("#5E574F"))
		t.set_font_size("font_size", variation, 24)


## 滚动条：仓库里现成的槽/填充贴图，拉伸方向改成纵向平铺。
## 默认主题的滚动条是灰的，放在花边卡片里很出戏。
static func _extras_scrollbars(t: Theme) -> void:
	var track := StyleBoxTexture.new()
	track.texture = tex(TEX_BAR_TRACK)
	_margins(track, 4)
	track.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	var grab := StyleBoxTexture.new()
	grab.texture = tex(TEX_BAR_EMBER)
	_margins(grab, 4)
	grab.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	var grab_hot := grab.duplicate() as StyleBoxTexture
	grab_hot.modulate_color = Color(1.25, 1.1, 0.9)
	for variation in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox("scroll", variation, track)
		t.set_stylebox("scroll_focus", variation, track)
		t.set_stylebox("grabber", variation, grab)
		t.set_stylebox("grabber_highlight", variation, grab_hot)
		t.set_stylebox("grabber_pressed", variation, grab_hot)


static func _extras_slider(t: Theme) -> void:
	var track := StyleBoxTexture.new()
	track.texture = tex(TEX_BAR_TRACK)
	_margins(track, 4)
	track.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	var fill := StyleBoxTexture.new()
	fill.texture = tex(TEX_BAR_EMBER)
	_margins(fill, 4)
	var fill_hot := fill.duplicate() as StyleBoxTexture
	fill_hot.modulate_color = Color(1.25, 1.1, 0.9)
	t.set_stylebox("slider", &"HSlider", track)
	t.set_stylebox("grabber_area", &"HSlider", fill)
	t.set_stylebox("grabber_area_highlight", &"HSlider", fill_hot)
	t.set_stylebox("focus", &"HSlider", StyleBoxEmpty.new())
	var gem := tex(TEX_SOCKET_GEM)
	if gem != null:
		t.set_icon("grabber", &"HSlider", gem)
		t.set_icon("grabber_highlight", &"HSlider", gem)
		t.set_icon("grabber_disabled", &"HSlider", gem)
	t.set_constant("center_grabber", &"HSlider", 0)


static func _margins(sb: StyleBoxTexture, px: int) -> void:
	sb.texture_margin_left = px
	sb.texture_margin_top = px
	sb.texture_margin_right = px
	sb.texture_margin_bottom = px


## HUD 条：毒素槽按档位换填充色，Boss 血条用余烬色。
## 只改贴图的调制色（换色不换图）：同一张 bar_track 当槽底，空槽在墨带上也读得出
## 是"量槽"而不是一道暗缝；毒素冷=毒绿、温/炽=余烬、溢=血红，Boss 血条=琥珀余烬。
## 全部落在 Palette 的既有色阶里，不新增贴图。
static func _extras_bars(t: Theme) -> void:
	# 槽底压暗：原图内芯只有 (20,16,31)，提亮后会读成一条"浅紫满槽"——空槽必须
	# 是画面里最暗的一道凹槽，只留一点铁灰刻度和边线提示"这里是量槽"。
	var toxin_track := _bar_texture(TEX_BAR_TRACK, Color(0.72, 0.68, 0.74))
	var boss_track := _bar_texture(TEX_BAR_TRACK, Color(0.9, 0.9, 0.9))
	var toxin_cold := _bar_texture(TEX_BAR_TOXIN, Color.WHITE)
	var toxin_warm := _bar_texture(TEX_BAR_EMBER, Color(1.0, 0.92, 0.7))
	var toxin_hot := _bar_texture(TEX_BAR_EMBER, Color(1.0, 0.55, 0.26))
	var toxin_overflow := _bar_texture(TEX_BAR_EMBER, Color(1.0, 0.3, 0.2))
	var boss_fill := _bar_texture(TEX_BAR_EMBER, Color(1.06, 1.0, 0.92))
	for spec: Array in [
		[&"ToxinBarCold", toxin_track, toxin_cold],
		[&"ToxinBarWarm", toxin_track, toxin_warm],
		[&"ToxinBarHot", toxin_track, toxin_hot],
		[&"ToxinBarOverflow", toxin_track, toxin_overflow],
		[&"BossHpBar", boss_track, boss_fill],
	]:
		var variation: StringName = spec[0]
		t.set_type_variation(variation, &"ProgressBar")
		t.set_stylebox("background", variation, spec[1])
		t.set_stylebox("fill", variation, spec[2])


## 一条 9-slice 量条贴图：横向平铺保留贴图自己的刻度，纵向随条高拉伸。
static func _bar_texture(path: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(path)
	_margins(sb, 4)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.modulate_color = tint
	return sb


## 一片余烬：6x6 的蒸馏帧，随机上升或飘落。UI 层用，不参与玩法。
class EmberMote extends Sprite2D:
	const FRAME_STEP := 0.11

	var _bounds := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var _drift := Vector2.ZERO
	var _sway_amp := 8.0
	var _sway_freq := 1.4
	var _phase := 0.0
	var _age := 0.0
	var _frame0 := 0

	func setup(sheet: Texture2D, bounds: Rect2, falling: bool) -> void:
		_bounds = bounds
		texture = sheet
		hframes = UiKit.MOTE_FRAMES
		vframes = 1
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_frame0 = randi_range(0, UiKit.MOTE_FRAMES - 1)
		frame = _frame0
		_phase = randf() * TAU
		_sway_amp = randf_range(5.0, 16.0)
		_sway_freq = randf_range(0.8, 2.0)
		# 只允许整数倍缩放：远处的一格，近处的两格。
		var zoom := 1 if randf() < 0.65 else 2
		scale = Vector2(zoom, zoom)
		if falling:
			_drift = Vector2(0.0, randf_range(9.0, 24.0))
			modulate = UiKit.ASH.lerp(UiKit.EMBER_ASH, randf() * 0.5)
			modulate.a = randf_range(0.30, 0.55)
		else:
			_drift = Vector2(0.0, -randf_range(18.0, 48.0))
			modulate = UiKit.EMBER.lerp(UiKit.RUST_MID, randf() * 0.6)
			modulate.a = randf_range(0.55, 1.0)
		position = Vector2(randf_range(_bounds.position.x, _bounds.end.x),
				randf_range(_bounds.position.y, _bounds.end.y))

	func _process(delta: float) -> void:
		_age += delta
		position += _drift * delta
		position.x += sin(_age * _sway_freq + _phase) * _sway_amp * delta
		frame = (_frame0 + int(_age / FRAME_STEP)) % UiKit.MOTE_FRAMES
		# 出界后从对侧重新入场，保持恒定密度。
		if _drift.y < 0.0 and position.y < _bounds.position.y - 8.0:
			position = Vector2(randf_range(_bounds.position.x, _bounds.end.x), _bounds.end.y + 6.0)
		elif _drift.y > 0.0 and position.y > _bounds.end.y + 8.0:
			position = Vector2(randf_range(_bounds.position.x, _bounds.end.x), _bounds.position.y - 6.0)


## 余烬粒子层。挂在界面根节点上；headless 或缺帧表时自动退化为空层。
class EmberField extends Node2D:
	static func build(bounds: Rect2, rising: int, falling: int) -> EmberField:
		var field := EmberField.new()
		field.name = "EmberField"
		var sheet := UiKit.tex(UiKit.TEX_EMBER_MOTES)
		if sheet == null or DisplayServer.get_name() == "headless":
			return field
		for i in rising + falling:
			var mote := EmberMote.new()
			field.add_child(mote)
			mote.setup(sheet, bounds, i >= rising)
		return field
