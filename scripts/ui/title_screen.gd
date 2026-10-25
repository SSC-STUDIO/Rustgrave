class_name TitleScreen
extends Control
## 标题屏（v3）：一幅实时点光的像素场景（TitleWorld，640x360 SubViewport）+ 轻量版式。
##
## 场景：余烬骑士背着巨剑站在铁桥上，天窗落下光柱，巨齿轮缓缓转动，几盏吊灯随存档
## 进度点亮（见 TitleWorld：无存档 / 进行中按幕调色 / 三种结局各一幅）。场景经由原有的
## `Keyart` TextureRect 显示（同一套像素平滑着色器，和游戏里的世界图一致）。
##
## 版式（1280x720 设计空间）：字标居中偏上，"锻入"式显现（白热 → 锈色扫过 + 火星），
## 副题随后淡入；菜单是左下一列被一盏吊灯照着的字（行动 / 模式 / 系统 / 离开四组，
## 每行 52px 触控高度；灯即光标，聚焦时灯落到那一行、字被照亮，并让场景轻推一下）；
## 右侧是"旅程标尺"：14 个章节刻度（已通关亮、当前搏动）+ 四枚小数据片
## （阶位 / 外观 / 试炼 / 竞技场），悬停或按 Tab 展开完整档案；底部是慢速打字机
## 轮换的墓志，署名收成页脚一行，页脚右侧随菜单焦点写一句当前行的说明（MENU_HINTS）。
##
## 菜单每一行聚焦时，炉厅里还有各自的反应（TitleWorld.react_to：炉火一涌 / 锻锤敲一下 /
## 火盆加亮 / 光柱云影放缓 / 破旗一掀 / 魂光升起），见 docs/title-live-scene.md §6。
## 有结局时「继续」行写作「回看余烬」，打开 ember_recap.gd 的总结页（继续 / 重温序章与结局 /
## 再入某章）；旅程列里的「回看余烬」按钮随时打开同一页。
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
## 「回看余烬」总结页（ember_recap.gd，没有 class_name）。
const RecapScript := preload("res://scripts/ui/ember_recap.gd")
const TRIAL_MENU := "res://scenes/ui/TrialMenu.tscn"
## 再入某章的落点：数据驱动章节（level02b 起）读各自 layout 的 entry_spawn()，
## 走 ChapterLayout.entry_spawn_of（出口门送人过去用的也是它）；用 load() 取而不是类名，
## 标题不因这条依赖在类缓存没刷新时黑屏。
const CHAPTER_LAYOUT_PATH := "res://scripts/levels/chapter_layout.gd"
## 前两章是手写关卡，没有 layout.entry_spawn()：这张表是它们的入口出生点，
## 数值来自 Level01Static.DEFAULT_SPAWN（第一章起点）与 Level02Layout.ENTRY_SPAWN
## （从第一章掉进地窟的落点）；tests/title_screen_test.gd 会逐项对照源常量，防止漂移。
const ENTRY_SPAWN_OVERRIDES := {
	"level01": Vector2(96.0, 320.0),
	"level02": Vector2(96.0, 40.0),
}
const ENTRY_SPAWN_FALLBACK := Vector2(96.0, 300.0)

## 「回看余烬」：一行刻在旅程列底部的字，不是一块铁条。
## 常态是暗锈细线；焦点 / 悬停时细线烧长，字左侧亮一粒余烬。
class RecapStrip:
	extends Control
	const HEIGHT := 26.0
	const LABEL := "回 看 余 烬"
	var _lit := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_lit(value: bool) -> void:
		if _lit == value:
			return
		_lit = value
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var font := get_theme_default_font()
		var col := UiKit.EMBER if _lit else Color(0.78, 0.70, 0.62, 0.72)
		if font != null:
			draw_string(font, Vector2(10.0 if _lit else 0.0, h * 0.5 + 5.0), LABEL,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		var line := Color(1.0, 0.62, 0.22, 0.9) if _lit else Color(0.42, 0.26, 0.16, 0.4)
		var line_w := 148.0 if _lit else 72.0
		draw_rect(Rect2(0.0, h - 2.0, line_w, 1.0), line)
		if _lit:
			draw_rect(Rect2(0.0, h * 0.5 - 2.0, 3.0, 3.0), Color(1.0, 0.86, 0.45))

## 副题两侧的余烬菱形饰：作为 Subtitle 的子节点画在文字两边，随副题定宽自动对中。
class SubtitleFlanks:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = -30.0
		offset_right = 30.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var cy := floorf(size.y * 0.5)
		for cx in [12.0, size.x - 12.0]:
			var inward := 1.0 if cx < size.x * 0.5 else -1.0
			# 一道短锈线指向文字，线头一粒 2px 余烬菱形。
			draw_rect(Rect2(cx - 5.0 if inward < 0.0 else cx + 2.0, cy, 6.0, 1.0),
					Color(0.42, 0.26, 0.16, 0.8))
			var c := Vector2(cx, cy - 1.0)
			for dy in range(-2, 3):
				var half := 2 - absi(dy)
				draw_rect(Rect2(c.x - half - 1.0, c.y + dy, 2.0 * half + 3.0, 1.0),
						Color(0.55, 0.28, 0.10, 0.9))
			for dy in range(-1, 2):
				var half := 1 - absi(dy)
				draw_rect(Rect2(c.x - half, c.y + dy, 2.0 * half + 1.0, 1.0),
						Color(1.0, 0.76, 0.29, 0.95))

## 墓志取「没用上的人偶自己先锈透」（你就是那个人偶）。一句，不是台词。
const EPITAPH := "没用上的人偶，自己先锈透了。"
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
## 墓志行（与"离开"行同一条中心线）。右端停在 988，给旅程列里的「回看余烬」留出缝。
const EPITAPH_RECT := Rect2(584.0, 624.0, 404.0, 32.0)
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

## 页脚右侧：焦点停在哪一行，就用一句话说明这一行是什么（每句 ≤ 24 字）。
## 「继续」行在有结局时写作「回看余烬」，说明见 RECAP_HINT。没有说明（或没有焦点）时是 FOOTER_DEFAULT。
const MENU_HINTS := {
	ID_NEW: "点燃余烬 · 选出身，开始新的旅程",
	ID_CONTINUE: "继续旅程 · 回到上次的余烬巢",
	ID_TRIAL: "回火试炼 · 单场挑战，刷新最佳成绩",
	ID_ARENA: "余烬竞技场 · 3v3 推线，摧毁敌方水晶",
	ID_SETTINGS: "设置 · 音量、画面、键位与辅助",
	ID_CONTROLS: "操作说明 · 当前键位与手柄按键",
	ID_QUIT: "离开锈墓 · 退出游戏",
}
const RECAP_HINT := "回看余烬 · 翻看行程，重温序章与结局"
const FOOTER_DEFAULT := "↑↓ 选择 · Enter 确认 · Tab 档案"

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
var _logo_flash: ColorRect
var _subtitle: Label
var _menu: MenuList
var _lamp: TitleLampCursor
var _controls: ControlsPanel
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
## 通关后的「回看余烬」总结页（ember_recap.gd）；菜单「继续」行在有结局时也打开它。
var _recap
var _continue_opens_recap := false
## 页脚右侧的一句话说明（焦点在哪行就写哪行）。
var _footer_hint: Label
var _hint_tween: Tween
## 界面搭完之后才置 true：搭菜单时默认选中「继续」那一下焦点不触发场景反应。
var _ui_ready := false
var _card: TitleCard
var _dossier_values: Dictionary = {}
var _dossier_recap: Label
var _dossier_open := false
var _dossier_pinned := false
var _card_tween: Tween

# epitaph typewriter
var _epitaph: Label
var _ep_backing: ColorRect
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
	# 炉厅环境床走 Sfx.set_title_bed（循环床，不进一次性 LIBRARY）。没有这个方法就不开。
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
	_ui_ready = true
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
	_keyart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_keyart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_keyart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_keyart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keyart)
	if live_scene_enabled:
		_build_live_world()
		# 字标在顶、墓志在底：只压这两条边。菜单靠吊灯自己的光，不再铺一块左帘。
		add_child(UiKit.scrim(0.40, 0.0, 0.32))
		add_child(UiKit.scrim_side(0.16, 340.0))
		# 旅程字刻在右侧机壳上，只留一条很窄的暗边，炉门还露在外面。
		var right_scrim := UiKit.scrim_side(0.18, 240.0)
		right_scrim.flip_h = true
		right_scrim.anchor_left = 1.0
		right_scrim.anchor_right = 1.0
		right_scrim.offset_left = -240.0
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
	PresentationMetrics.configure_world(_world_viewport, PresentationMetrics.for_window(get_tree().root))
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
	PresentationMetrics.configure_world(_world_viewport, metrics)
	_smooth_material.set_shader_parameter("scale_hint", 1)


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
	# 字标背后一小团炉温，让铁字像还烫着，而不是贴在画面上。
	var halo := TextureRect.new()
	halo.name = "LogoHalo"
	halo.texture = load("res://assets/title/glow.png")
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.show_behind_parent = true
	halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	halo.offset_left = -36.0
	halo.offset_top = -16.0
	halo.offset_right = 36.0
	halo.offset_bottom = 18.0
	var halo_mat := CanvasItemMaterial.new()
	halo_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = halo_mat
	halo.modulate = Color(1.0, 0.62, 0.28, 0.16)
	_logo.add_child(halo)

	_subtitle = UiKit.label("锈 墓 · 余 烬 骑 士", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.name = "Subtitle"
	_subtitle.custom_minimum_size = Vector2(0.0, SUBTITLE_H)
	_pack(_subtitle)
	column.add_child(_subtitle)
	# 副题两侧的余烬菱形饰（随副题定宽对中）。
	var flanks := SubtitleFlanks.new()
	flanks.name = "SubtitleFlanks"
	_subtitle.add_child(flanks)

	# 锻入完成时的落锤闪光：一层加法混合的白热，亮一下就熄。
	_logo_flash = ColorRect.new()
	_logo_flash.name = "LogoFlash"
	_logo_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_logo_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_flash.color = Color(1.0, 0.92, 0.72, 0.0)
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_logo_flash.material = blend
	_logo.add_child(_logo_flash)


## 左下菜单：一盏吊灯照着四组字。行距用空白节点而不是容器 separation。
func _build_rail() -> void:
	# 灯在菜单之前加：字画在灯和光晕上面，灯又画在场景上面。
	_lamp = TitleLampCursor.new()
	_lamp.name = "MenuLamp"
	_lamp.position = Vector2(RAIL_X - 36.0, 0.0)
	_lamp.size = Vector2(72.0, 720.0)
	_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lamp)

	_menu = MenuList.new()
	_menu.name = "Menu"
	_menu.lamp_style = true
	_menu.add_theme_constant_override("separation", 0)
	_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu.position = Vector2(RAIL_X, RAIL_TOP)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)

	var has_save := SaveData.has_save()
	# 行动
	_menu.add_item(ID_NEW, "点 燃 余 烬", false, MenuItem.Kind.PRIMARY, true)
	# 通关过：这一行写「回看余烬」，也就真的打开总结页（总结页里仍有「继续旅程」）。
	_continue_opens_recap = SaveData.peek_ending() != ""
	var cont := "回 看 余 烬" if _continue_opens_recap else "继 续 旅 程"
	_menu.add_item(ID_CONTINUE, cont, not has_save, MenuItem.Kind.PRIMARY, true)
	_gap(GROUP_GAP)
	# 模式
	var trial_ready := _trial_ready()
	var trial_item := _menu.add_item(ID_TRIAL, "回 火 试 炼", not trial_ready, MenuItem.Kind.SECONDARY, true)
	if not trial_ready:
		trial_item.set_note("%s后解锁" % TrialCatalogScript.unlock_chapter_label())
		# 禁用行不进键盘导航，但鼠标悬停时页脚仍交代它为什么锁着。
		trial_item.mouse_entered.connect(
				func() -> void: _set_footer_hint("回火试炼 · 通关%s后解锁" % TrialCatalogScript.unlock_chapter_label()))
		trial_item.mouse_exited.connect(
				func() -> void: if _menu != null: _refresh_footer_hint(_menu.selected_id()))
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
	# 版式细节：标题下压一道锈线，列左侧一根细导引线（和菜单架的脊/芯片左侧条同语汇）。
	var head_rule := ColorRect.new()
	head_rule.name = "JourneyRule"
	head_rule.position = Vector2(0.0, 17.0)
	head_rule.size = Vector2(JOURNEY_W, 1.0)
	head_rule.color = Color(0.42, 0.26, 0.16, 0.28)
	head_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journey.add_child(head_rule)
	var guide := ColorRect.new()
	guide.name = "JourneyGuide"
	guide.position = Vector2(-10.0, 8.0)
	guide.size = Vector2(1.0, JOURNEY_H - 16.0)
	guide.color = Color(0.42, 0.26, 0.16, 0.12)
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journey.add_child(guide)

	_journey_recap = UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_journey_recap.name = "JourneyRecap"
	# 两行摘要停在标尺墨线左侧 8px，底边也让开标尺顶，避免「守炉：…」盖住壹贰叁。
	var recap_w := TitleGauge.INK_LEFT - 8.0
	_journey_recap.position = Vector2(0.0, 36.0)
	_journey_recap.size = Vector2(recap_w, 34.0)
	_journey_recap.custom_minimum_size = Vector2(recap_w, 34.0)
	_journey_recap.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_journey_recap.max_lines_visible = 2
	_journey_recap.clip_text = true
	_journey_recap.clip_contents = true
	_journey_recap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_journey_recap.vertical_alignment = VERTICAL_ALIGNMENT_TOP
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

	# 回看余烬：和芯片一样只剩字和一根细线。Button 负责焦点、点击与导航。
	var recap := Button.new()
	recap.name = "RecapButton"
	recap.flat = true
	recap.text = ""
	recap.focus_mode = Control.FOCUS_ALL
	recap.position = Vector2(0.0, chip_y + TitleChip.CHIP_SIZE.y * 2.0 + 16.0)
	recap.custom_minimum_size = Vector2(JOURNEY_W, RecapStrip.HEIGHT)
	recap.size = Vector2(JOURNEY_W, RecapStrip.HEIGHT)
	recap.pressed.connect(open_recap)
	# 悬停 / 聚焦时页脚说明跟着写，左缘迸一小簇火星；离开恢复菜单那行的说明。
	recap.mouse_entered.connect(_on_recap_attention.bind(true))
	recap.focus_entered.connect(_on_recap_attention.bind(true))
	recap.mouse_exited.connect(_on_recap_attention.bind(false))
	recap.focus_exited.connect(_on_recap_attention.bind(false))
	_journey.add_child(recap)
	var strip := RecapStrip.new()
	strip.name = "Strip"
	strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recap.add_child(strip)
	recap.focus_entered.connect(strip.set_lit.bind(true))
	recap.focus_exited.connect(strip.set_lit.bind(false))
	recap.mouse_entered.connect(strip.set_lit.bind(true))
	recap.mouse_exited.connect(strip.set_lit.bind(false))

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
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := UiKit.label("行 程 档 案", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_CENTER)
	head.modulate = UiKit.EMBER
	head.name = "DossierHead"
	box.add_child(head)
	_dossier_section(box, "成 长")
	_add_dossier_row(box, "Rank", "余 烬 阶 位")
	_add_dossier_row(box, "Skin", "当 前 外 观")
	_dossier_section(box, "旅 程")
	_add_dossier_row(box, "Trials", "回 火 试 炼")
	_add_dossier_row(box, "Arena", "余 烬 竞 技 场")
	_add_dossier_row(box, "Chapter", "上 次 行 程")
	_dossier_recap = UiKit.label("", &"FootnoteLabel")
	_dossier_recap.name = "DossierRecap"
	_dossier_recap.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_dossier_recap.custom_minimum_size = Vector2(0.0, 44.0)
	_dossier_recap.modulate = Color(UiKit.EMBER_ASH.r, UiKit.EMBER_ASH.g, UiKit.EMBER_ASH.b, 0.85)
	box.add_child(_dossier_recap)
	if not _trial_ready():
		var trial_hint := UiKit.label("通关%s或任一结局后解锁「回火试炼」" % TrialCatalogScript.unlock_chapter_label(), &"FootnoteLabel")
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


## 档案卡的小节标题：琥珀色小字 + 一条渐隐锈线，把"成长/旅程"分开。
func _dossier_section(parent: VBoxContainer, title: String) -> void:
	var row := HBoxContainer.new()
	row.name = "DossierSection" + title
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lab := UiKit.label(title, &"TinyStrongLabel")
	lab.modulate = Color(UiKit.EMBER_ASH.r, UiKit.EMBER_ASH.g, UiKit.EMBER_ASH.b, 0.9)
	row.add_child(lab)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.color = Color(0.42, 0.26, 0.16, 0.55)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)


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

	var arena_records: Dictionary = ArenaRunScript.read_records()
	var arena_wins := int(arena_records.get("wins", 0))
	var arena_text := "胜 %d 场" % arena_wins
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
	(_chips["Arena"] as TitleChip).set_chip("竞", "胜 %d 场" % arena_wins, arena_wins > 0)


## 结局的短名（取自结局概述冒号前的几个字：还火 / 守炉 / 熄火）。
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

	var row := Control.new()
	row.name = "EpitaphRow"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)

	# 铭文条的一道顶线，右端一粒余烬钉：给这行字一个"刻在碑上"的锚点。
	var rule := ColorRect.new()
	rule.name = "EpitaphRule"
	rule.position = Vector2(0.0, 0.0)
	rule.size = Vector2(EPITAPH_RECT.size.x, 1.0)
	rule.color = Color(0.42, 0.26, 0.16, 0.28)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	var nail := ColorRect.new()
	nail.name = "EpitaphNail"
	nail.position = Vector2(EPITAPH_RECT.size.x - 3.0, -1.0)
	nail.size = Vector2(3.0, 3.0)
	nail.color = Color(UiKit.EMBER.r, UiKit.EMBER.g, UiKit.EMBER.b, 0.8)
	nail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nail)

	# 字背后的柔和底衬：桥面上的栏杆和火星会从字底下穿过，垫一层才读得稳。
	_ep_backing = ColorRect.new()
	_ep_backing.name = "EpitaphBacking"
	_ep_backing.color = Color(0.02, 0.01, 0.03, 0.16)
	_ep_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_ep_backing)

	_ep_lines = PackedStringArray([EPITAPH])
	for line in ChapterText.TITLE_LINES:
		_ep_lines.append(line)
	# 整句右齐在墓志条里。条本身比旅程列窄一截，字再长也停在条内，不压到「回看余烬」。
	_epitaph = UiKit.label(EPITAPH, &"EpitaphLabel", HORIZONTAL_ALIGNMENT_RIGHT)
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
	# 页脚右侧染成余烬色：页脚里只有这一行是"给玩家的话"——焦点停在哪一行，
	# 就用一句话说明它是什么（MENU_HINTS）；没有焦点时是操作提示。
	var hint := UiKit.label(FOOTER_DEFAULT, &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	hint.name = "FooterHint"
	hint.position = Vector2(FOOTER_RECT.size.x - 400.0, 6.0)
	hint.size = Vector2(400.0, 20.0)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.modulate = UiKit.EMBER_ASH
	band.add_child(hint)
	_footer_hint = hint
	if _menu != null:
		_refresh_footer_hint(_menu.selected_id())

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
	_controls = ControlsPanel.new()
	_controls.layer = 5
	_controls.closed.connect(func() -> void: _menu.active = true)
	add_child(_controls)
	_settings = SettingsScreen.new()
	_settings.layer = 6
	_settings.closed.connect(func() -> void: _menu.active = true)
	add_child(_settings)
	_build_recap_page()
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
	if _lamp != null:
		_lamp.modulate.a = 0.0
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
	tw.tween_callback(_logo_settle_flash).set_delay(LOGO_AT + LOGO_TIME)
	for k in 5:
		tw.tween_callback(_logo_spark.bind(0.12 + 0.19 * float(k))) \
				.set_delay(LOGO_AT + LOGO_TIME * (0.12 + 0.19 * float(k)))
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.35).set_delay(LOGO_AT + LOGO_TIME * 0.85) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 吊灯和第一行一起落下：链从屋架上放下来，火在落到字上时才点着。
	if _lamp != null:
		tw.tween_property(_lamp, "modulate:a", 1.0, 0.35).set_delay(MENU_AT)
		tw.tween_callback(_lamp.arm).set_delay(MENU_AT)
	# 菜单逐条落位
	var delay := MENU_AT
	for i in rows.size():
		var row := rows[i]
		tw.tween_property(row, "modulate:a", 1.0, 0.2).set_delay(delay)
		# TRANS_BACK：落位带一点回弹，像铁条被挂上挂架。
		tw.tween_property(row, "land", 0.0, MENU_LAND).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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


## 锻入收尾：白热在字标上亮一下再熄，像锻锤最后落了一记。
func _logo_settle_flash() -> void:
	if _logo_flash == null or not is_instance_valid(_logo_flash):
		return
	var tw := create_tween()
	tw.tween_property(_logo_flash, "color:a", 0.42, 0.05)
	tw.tween_property(_logo_flash, "color:a", 0.0, 0.32) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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
	_update_lamp()
	if _lamp != null:
		_lamp.ignite(true)
		_lamp.modulate.a = 1.0
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
	_update_lamp()
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


## 吊灯跟到当前行，字的亮度按离火焰的距离算。继续旅程被照到时，右侧旅程列一起亮起来。
func _update_lamp() -> void:
	if _lamp == null or _menu == null:
		return
	var items := _menu.items()
	var selected := _menu.selected_id()
	var idx := _menu.item_ids().find(selected)
	if idx >= 0 and idx < items.size():
		var row := _local_rect(items[idx])
		_lamp.set_target_center_y(row.get_center().y - _lamp.position.y)
	var lamp_y := _lamp.position.y + _lamp.lantern_center().y
	for item in items:
		var row_item := item as MenuItem
		if row_item == null or not row_item.lamp:
			continue
		var dy := absf(_local_rect(row_item).get_center().y - lamp_y)
		var amt := clampf(1.0 - dy / 120.0, 0.28, 1.0)
		if row_item.disabled:
			amt *= 0.45
		if row_item.selected and not row_item.disabled:
			amt = maxf(amt, 0.92)
		row_item.light = amt
	if _intro_playing or _quitting or _journey == null:
		return
	_set_journey_tone(1.0 if selected == ID_CONTINUE else 0.58)


func _set_journey_tone(tone: float) -> void:
	for node_name in ["JourneyHeader", "JourneyCount", "JourneyChapter", "JourneyRecap",
			"JourneyGauge", "JourneyRule", "JourneyGuide", "RecapButton"]:
		var node := _journey.get_node_or_null(String(node_name)) as CanvasItem
		if node != null and not is_equal_approx(node.modulate.a, tone):
			node.modulate.a = tone
	for chip in _chips.values():
		var node := chip as CanvasItem
		if node != null and not is_equal_approx(node.modulate.a, tone):
			node.modulate.a = tone


## 火星从灯焰上迸出来；灯还没落下时，退回到这一行的中心。
func _lamp_spark_at(item: Control) -> Vector2:
	if _lamp != null and _lamp.modulate.a > 0.2:
		return _lamp.position + _lamp.lantern_center()
	return _local_rect(item).get_center()


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
			# 新句先轻轻亮起，再开始打字；换行不再硬切。
			_epitaph.modulate.a = smoothstep(0.0, 1.0,
					clampf(_ep_t / 0.22, 0.0, 1.0))
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
			_epitaph.modulate.a = 1.0 - smoothstep(0.0, 1.0,
				clampf(_ep_t / EPITAPH_FADE, 0.0, 1.0))
			if _ep_t >= EPITAPH_FADE:
				_ep_index = (_ep_index + 1) % _ep_lines.size()
				_epitaph.text = _ep_lines[_ep_index]
				_fit_epitaph()
				_epitaph.visible_characters = 0
				_epitaph.modulate.a = 1.0
				_ep_phase = 1
				_ep_t = 0.0


## 墓志标签按当前这一行的整句定宽，右端贴着墓志条，不超出条的右缘。
func _fit_epitaph() -> void:
	var font := _epitaph.get_theme_font(&"font")
	var font_size := _epitaph.get_theme_font_size(&"font_size")
	var width := 8.0
	if font != null:
		width = font.get_string_size(_epitaph.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var max_w := EPITAPH_RECT.size.x
	var use := minf(ceilf(width) + 8.0, max_w)
	_epitaph.clip_text = true
	_epitaph.custom_minimum_size = Vector2(use, EPITAPH_RECT.size.y)
	_epitaph.size = Vector2(use, EPITAPH_RECT.size.y)
	_epitaph.position = Vector2(max_w - use, 0.0)
	if _ep_backing != null:
		# 底衬比字稍宽一点、比行高稍薄一点，压在字的正后方。
		_ep_backing.position = Vector2(max_w - use - 8.0, 5.0)
		_ep_backing.size = Vector2(use + 8.0, EPITAPH_RECT.size.y - 10.0)


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
	_refresh_footer_hint(id)
	if _world != null and not _intro_playing:
		_world.nudge(1.0)
		# 每一行在炉厅里有自己的反应（炉火一涌 / 锻锤敲一下 / 火盆加亮…），见 TitleWorld.react_to
		if _ui_ready:
			_world.react_to(id)
	if _ui_sparks != null and item != null and not _intro_playing:
		var at := _lamp_spark_at(item)
		_ui_sparks.burst(at * 0.5, 8, 62.0)
		if _lamp != null:
			_lamp.flare(0.85)


## 页脚右侧的说明：这一行是什么（MENU_HINTS）。「继续」行在有结局时是「回看余烬」。
## 不认识的 id 返回空串。
static func hint_for(id: StringName, recap_row: bool = false) -> String:
	if id == ID_CONTINUE and recap_row:
		return RECAP_HINT
	return String(MENU_HINTS.get(id, ""))


## 「回看余烬」按钮的悬停 / 聚焦：页脚写它的说明，左缘迸一小簇火星。
func _on_recap_attention(over: bool) -> void:
	if _quitting or _started:
		return
	if over:
		_set_footer_hint(RECAP_HINT)
		if _ui_ready and not _intro_playing and _ui_sparks != null:
			var recap := _journey.get_node_or_null("RecapButton") as Control
			if recap != null:
				var r := _local_rect(recap)
				_ui_sparks.burst(Vector2(r.position.x + 4.0, r.position.y + r.size.y * 0.5) * 0.5,
						6, 52.0)
	elif _menu != null:
		_refresh_footer_hint(_menu.selected_id())


func _refresh_footer_hint(id: StringName) -> void:
	var text := hint_for(id, _continue_opens_recap)
	_set_footer_hint(text if text != "" else FOOTER_DEFAULT)


## 换页脚说明：淡出 → 换字 → 淡入，不硬切。无显示服务器（headless）时直接写。
func _set_footer_hint(text: String) -> void:
	if _footer_hint == null or _footer_hint.text == text:
		return
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		_footer_hint.text = text
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_footer_hint, "modulate:a", 0.0, 0.08)
	_hint_tween.tween_callback(func() -> void: _footer_hint.text = text)
	_hint_tween.tween_property(_footer_hint, "modulate:a", 1.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 页脚右侧现在写的是什么（测试读）。
func footer_hint_text() -> String:
	return _footer_hint.text if _footer_hint != null else ""


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
			# 有结局时这一行写的是「回看余烬」：打开总结页，由总结页决定继续 / 重温 / 再入某章。
			if _continue_opens_recap:
				open_recap()
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


## 「回看余烬」总结页：结局、已过的章数、继续旅程、重温序章 / 结局、模式入口、再入某一章。
## 有结局时菜单里的「继续」行（写作「回看余烬」）和旅程列的「回看余烬」按钮都打开它。
## 页面本身见 ember_recap.gd（OrnatePanel 卡片 + MenuList，与其他弹窗一致）。
func open_recap() -> void:
	if _started or _quitting or _recap == null:
		return
	if _intro_playing:
		_skip_intro()
	if _recap.is_open():
		return
	_menu.active = false
	# 总结页是一块半透明的玻璃卡：标题菜单若还亮着，它的文字会从卡片下面透出来。淡出菜单，
	# 只让场景的光透过去（关闭时再淡回来）。
	_fade_title_menu(0.0)
	_recap.open(_recap_info())


## 标题菜单的淡入淡出：只动 modulate:a，不碰 active（输入由 active 单独管）。
func _fade_title_menu(alpha: float) -> void:
	if _menu == null:
		return
	var tw := create_tween()
	tw.tween_property(_menu, "modulate:a", alpha, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 标题还没读档时，试炼解锁只在磁盘旗标里。内存空着不能把钟楼之后的存档显示成未解锁。
func _trial_ready() -> bool:
	if TrialCatalogScript.unlocked():
		return true
	if not SaveData.data.is_empty():
		return false
	var flags: PackedStringArray = TitleWorld.peek_save().get("flags", PackedStringArray())
	return flags.has(TrialCatalogScript.UNLOCK_FLAG) \
			or flags.has(TrialCatalogScript.chapter_flag(TrialCatalogScript.UNLOCK_CHAPTER)) \
			or flags.has("game_complete")


## 总结页要的数据。旗标取「内存 + 磁盘合并」的那份（标题刚启动时 SaveData.flags 还没读档，
## 直接读它会把已通关的章全算成 0）。
func _recap_info() -> Dictionary:
	var peek := TitleWorld.peek_save()
	return {
		"ending": SaveData.peek_ending(),
		"flags": peek.get("flags", PackedStringArray()),
		"has_save": bool(peek.get("has_save", false)),
		"trial_ready": _trial_ready(),
	}


func _build_recap_page() -> void:
	_recap = RecapScript.new()
	_recap.layer = 4
	_recap.closed.connect(_close_recap)
	_recap.dismissed.connect(_close_recap)
	_recap.continue_requested.connect(_recap_continue)
	_recap.arena_requested.connect(_recap_arena)
	_recap.trial_requested.connect(_recap_trial)
	_recap.chapter_requested.connect(_reenter_chapter)
	add_child(_recap)


## 总结页关了（Esc / 返回 / 点卡片外）：菜单把输入拿回来。
func _close_recap() -> void:
	if _menu != null and not _started and not _quitting:
		_menu.active = true
		_fade_title_menu(1.0)


## 总结页里的「继续旅程」：和菜单的「继续」行读同一份存档。
func _recap_continue() -> void:
	if _started or _quitting:
		return
	_recap.dismiss()
	_start(true)


func _recap_arena() -> void:
	if _started or _quitting:
		return
	_recap.dismiss()
	_on_chosen(ID_ARENA)


func _recap_trial() -> void:
	if _started or _quitting:
		return
	_recap.dismiss()
	_on_chosen(ID_TRIAL)


## 再入某章的落点：该章的入口出生点（出口门把人送进这一章时用的同一个点）。
static func chapter_entry_spawn(id: String) -> Vector2:
	if ENTRY_SPAWN_OVERRIDES.has(id):
		return ENTRY_SPAWN_OVERRIDES[id]
	if ResourceLoader.exists(CHAPTER_LAYOUT_PATH):
		var script := load(CHAPTER_LAYOUT_PATH) as GDScript
		if script != null:
			var spawn: Vector2 = script.call(&"entry_spawn_of", id)
			return spawn
	return ENTRY_SPAWN_FALLBACK


func _reenter_chapter(id: String) -> void:
	if _started or _quitting:
		return
	var path := String(GameContext.LEVELS.get(id, ""))
	if path == "" or not GameContext.is_world_scene(path):
		return
	_recap.dismiss()
	_started = true
	_menu.active = false
	var spawn := chapter_entry_spawn(id)
	if not SaveData.data.has("meta") or not SaveData.data["meta"] is Dictionary:
		SaveData.data["meta"] = {}
	(SaveData.data["meta"] as Dictionary)["scene"] = path
	if SaveData.data.has("player") and SaveData.data["player"] is Dictionary:
		(SaveData.data["player"] as Dictionary)["pos"] = spawn
	SaveData.pending_spawn = spawn
	Sfx.play(&"gate")
	_confirm_effect()
	Director.fade_to(path, FADE_OUT)


## 测试 / 工具：总结页句柄与是否正开着。
func recap_page():
	return _recap


func recap_open() -> bool:
	return _recap != null and _recap.is_open()


## 确认入场：白热闪光 + 镜头朝骑士前推 + 在选中条上迸一簇火星 + 条身一道白热扫过。
## 随后调用方淡出换关。
func _confirm_effect() -> void:
	if _world != null:
		_world.enter_push(5.0, 0.55)
	if _menu != null:
		var items := _menu.items()
		var idx := _menu.item_ids().find(_menu.selected_id())
		if idx >= 0 and idx < items.size():
			var item := items[idx] as MenuItem
			if _ui_sparks != null:
				_ui_sparks.burst(_lamp_spark_at(item) * 0.5, 14, 90.0)
			if _lamp != null:
				_lamp.flare(1.2)
			item.flash()


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
	if _lamp != null:
		_lamp.douse()
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
	if _started or _quitting:
		return
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
	if _started or _quitting:
		return
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
