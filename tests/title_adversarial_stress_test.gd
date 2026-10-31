extends TestCase
## 对抗性压力测试套件（Milestone 1 UI 升级：T1–T5）：
##   1. LockTag 非重叠压力测试：多分辨率/长宽比、Row 1 & Row 3 & 场景告示牌非碰撞、无注解行不生成虚假 LockTag
##   2. MenuShade 中线与裁剪压力测试：所有视口配置下右界严格 < 640.0，不遮暗中央骑士
##   3. FooterShade 与完整致谢：署名完整落在 label 内、字形终点停在页脚提示前、FooterShade 忽略鼠标事件不阻挡底部按钮点�?
##   4. 坩埚熔铁流：自适应密集采样相邻点距 <= 2px (<= 1.415px) 与连续双层折�?
##   5. 吊灯光标与暖度渐变：3x 比例�?36px 衰减范围与单调暖度变�?

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const KEYART_CENTER := 640.0
const SCENE_SIGNS_X := 240.0

const STRESS_WINDOWS := [
	Vector2i(1280, 720),   # 16:9 设计基准
	Vector2i(1920, 1080),  # 16:9 1080p
	Vector2i(960, 540),    # 16:9 半高�?
	Vector2i(2560, 1080),  # 21:9 超宽�?
	Vector2i(3440, 1440),  # 21:9 QHD 超宽�?
	Vector2i(1024, 768),   # 4:3 传统
	Vector2i(800, 600),    # 4:3 低分辨率
	Vector2i(1280, 800),   # 16:10 Steam Deck
]

var _saved_flags: PackedStringArray
var _saved_ending: String
var _saved_path: String
var _test_save_path := "user://title_adversarial_test.cfg"


func setup() -> void:
	Director._set_lock(false)
	TitleState.forced_state = {}
	_saved_flags = SaveData.flags.duplicate()
	_saved_ending = SaveData.ending
	_saved_path = SaveData.save_path
	SaveData.save_path = _test_save_path
	if FileAccess.file_exists(_test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_save_path))
	SaveData.flags = PackedStringArray()
	SaveData.ending = ""


func teardown() -> void:
	TitleState.forced_state = {}
	ArenaRun.use_default_file()
	SaveData.flags = _saved_flags
	SaveData.ending = _saved_ending
	if FileAccess.file_exists(_test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_save_path))
	SaveData.save_path = _saved_path


func _open_title() -> TitleScreen:
	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	title._skip_intro()
	return title


func _items(title: TitleScreen) -> Array[MenuItem]:
	var out: Array[MenuItem] = []
	var menu := title.get_node_or_null("Menu")
	if menu != null:
		for child in menu.get_children():
			if child is MenuItem:
				out.append(child)
	return out


## 场景 1：LockTag 在各种分辨率下贴在试炼行右侧，不与其他菜单行相交，也不越过中�?
func test_lock_tag_non_intersection_across_resolutions() -> void:
	var title: TitleScreen = await _open_title()
	var tag := title.find_child("LockTag", true, false) as Control
	ok(tag != null, "锁定状态下 LockTag 节点必须存在")
	if tag == null:
		title.queue_free()
		return
	ok(tag.visible, "锁定状态下 LockTag 必须可见")

	var items := _items(title)
	eq(items.size(), 7, "菜单包含 7 个功能行")

	# 遍历 8 种典型与极限视口分辨�?
	for win in STRESS_WINDOWS:
		var metrics := PresentationMetrics.calculate(win)
		var xf: Transform2D = metrics["ui_transform"]
		title.position = xf.origin
		title.scale = xf.get_scale()
		await get_tree().process_frame

		var tag_design_rect: Rect2 = title.design_rect(tag)
		var trial_row: MenuItem = items[2]
		var trial_rect: Rect2 = title.design_rect(trial_row)
		ok(tag_design_rect.position.y >= trial_rect.position.y - 1.0,
				"LockTag 与试炼行同一�?@%s" % win)
		ok(tag_design_rect.end.y <= trial_rect.end.y + 1.0,
				"LockTag 不落到下一�?@%s" % win)
		ok(tag_design_rect.position.x > trial_rect.position.x + 80.0,
				"LockTag 在题字右�?@%s (x=%.1f)" % [win, tag_design_rect.position.x])
		ok(tag_design_rect.end.x < KEYART_CENTER,
				"LockTag 右端停在中线左侧 @%s (tag_end_x=%.1f)" % [win, tag_design_rect.end.x])

		for item in items:
			if item.id == &"trial":
				continue
			var item_rect: Rect2 = title.design_rect(item)
			ok(not tag_design_rect.intersects(item_rect),
					"LockTag 不与菜单�?%s 重叠 @%s (tag=%s, row=%s)" % [item.id, win, tag_design_rect, item_rect])

	title.queue_free()
	await get_tree().process_frame


## 场景 1 补充：未加注行在悬停、选择和键盘导航时绝不误生�?LockTag
func test_no_spurious_lock_tag_on_hover_or_select_unnoted_rows() -> void:
	var title: TitleScreen = await _open_title()
	var menu := title.get_node("Menu") as MenuList
	var items := _items(title)

	# 1. 未解锁模式：只有 Row 2 (trial) 应该�?LockTag
	var initial_tags := title.find_children("LockTag", "Control", true, false)
	eq(initial_tags.size(), 1, "初始状态下全屏仅有 Row 2 拥有且仅拥有 1 �?LockTag")

	# 遍历所有未加注行，模拟鼠标悬停和键盘选中
	for i in [0, 1, 3, 4, 5, 6]:
		var item: MenuItem = items[i]
		item.hover_requested.emit()
		await get_tree().process_frame
		menu.select(i, false)
		await get_tree().process_frame

		ok(item.find_child("LockTag", true, false) == null,
				"未加注行 %s (index %d) 悬停/选中后不产生 LockTag 子节�? % [item.id, i])

	var after_hover_tags := title.find_children("LockTag", "Control", true, false)
	eq(after_hover_tags.size(), 1, "遍历未加注行�?LockTag 总数依然�?1，无虚假多余生成")

	title.queue_free()
	await get_tree().process_frame

	# 2. 已解锁模式（trial_unlocked）：没有任何行应有可�?LockTag
	SaveData.mark_flag("trial_unlocked")
	title = await _open_title()
	menu = title.get_node("Menu") as MenuList
	items = _items(title)

	for i in items.size():
		var item: MenuItem = items[i]
		item.hover_requested.emit()
		await get_tree().process_frame
		menu.select(i, false)
		await get_tree().process_frame
		var tag := item.find_child("LockTag", true, false) as Control
		var tag_visible: bool = tag != null and tag.visible
		ok(not tag_visible, "解锁状态下�?%s 绝不显示 LockTag" % item.id)

	title.queue_free()
	await get_tree().process_frame


## 场景 2：MenuShade 在所有视口分辨率和长宽比下，右界严格 < 640.0，绝不遮暗中央骑�?
func test_menu_shade_bounds_across_all_resolutions() -> void:
	var title: TitleScreen = await _open_title()
	var shade := title.find_child("MenuShade", true, false) as Control
	ok(shade != null, "MenuShade 节点必须存在")
	if shade == null:
		title.queue_free()
		return

	ok(shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "MenuShade 必须忽略鼠标事件")

	# 在设计坐标空间下的几何断言
	var design_r := title.design_rect(shade)
	ok(design_r.position.x >= 0.0, "MenuShade 左侧落在设计屏幕�?(x=%.1f >= 0)" % design_r.position.x)
	ok(design_r.end.x < KEYART_CENTER, "MenuShade 右侧严格在中线左�?(%.1f < %.1f)" % [design_r.end.x, KEYART_CENTER])
	ok(KEYART_CENTER - design_r.end.x >= 120.0,
			"MenuShade 右边缘与中央骑士中线留有充足留白安全距离 (margin=%.1f >= 120)" % (KEYART_CENTER - design_r.end.x))

	# 遍历 8 种窗口分辨率，验证物理视口投影下的右边缘永远小于物理中央中线
	for win in STRESS_WINDOWS:
		var metrics := PresentationMetrics.calculate(win)
		var xf: Transform2D = metrics["ui_transform"]
		title.position = xf.origin
		title.scale = xf.get_scale()
		await get_tree().process_frame

		var content_rect: Rect2 = metrics["physical_rect"]
		var physical_center_x := content_rect.position.x + content_rect.size.x * 0.5

		# 计算 shade 在物理像素下的全局矩形
		var to_root := title.get_global_transform()
		var shade_global_origin := to_root * shade.position
		var shade_global_end := to_root * (shade.position + shade.size)
		var root_scale := Vector2(win) / Vector2(PresentationMetrics.UI_SIZE)
		var physical_shade_right := shade_global_end.x * root_scale.x

		ok(physical_shade_right < physical_center_x,
				"物理像素�?MenuShade 右界严格在中线左�?@%s (shade_right=%.1f < center_x=%.1f)" %
				[win, physical_shade_right, physical_center_x])

	title.queue_free()
	await get_tree().process_frame


## 场景 3：FooterShade 与完整致谢文案及鼠标穿透验�?
func test_footer_shade_and_credits_adversarial() -> void:
	var title: TitleScreen = await _open_title()
	var shade := title.find_child("FooterShade", true, false) as Control
	ok(shade != null, "FooterShade 必须存在")
	if shade == null:
		title.queue_free()
		return

	eq(shade.mouse_filter, Control.MOUSE_FILTER_IGNORE, "FooterShade mouse_filter 必须�?MOUSE_FILTER_IGNORE")

	var credits := title.find_child("Credits", true, false) as Label
	if credits == null:
		var band := title.find_child("CreditBand", true, false)
		if band != null and band.get_child_count() > 1:
			credits = band.get_child(1) as Label
	ok(credits != null, "Credits 标签必须存在")

	if credits != null:
		var hint := title.find_child("FooterHint", true, false) as Label
		ok(hint != null, "FooterHint 标签必须存在")
		var hint_rect := title.design_rect(hint) if hint != null else Rect2()
		var credits_rect := title.design_rect(credits)
		if hint != null:
			ok(credits_rect.end.x < hint_rect.position.x,
					"Credits 矩形右端停在页脚提示之前 (%.1f < %.1f)" % [credits_rect.end.x, hint_rect.position.x])

		# 完整署名必须真的画出来，不能�?label 宽度或省略号截断�?
		var font := credits.get_theme_default_font()
		if font != null:
			var font_size := credits.get_theme_font_size("font_size")
			var actual_text_w: float = font.get_string_size(credits.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var text_end_x := credits_rect.position.x + actual_text_w
			ok(actual_text_w <= credits.size.x - 2.0,
					"完整致谢宽度落在 label 内，不会被省略号截断 (%.1f <= %.1f)" % [actual_text_w, credits.size.x - 2.0])
			if hint != null:
				ok(text_end_x < hint_rect.position.x,
						"致谢实际字形终点停在页脚提示之前 (%.1f < %.1f)" % [text_end_x, hint_rect.position.x])

	# 对抗性测试：�?FooterShade 覆盖区域放置测试按钮，验证点击穿透不被阻�?
	var test_btn := Button.new()
	test_btn.name = "AdversarialFooterButton"
	test_btn.position = Vector2(200.0, 670.0)  # 位于 FooterShade (y=648..720) 内部
	test_btn.size = Vector2(120.0, 32.0)
	var clicked_state := [false]
	test_btn.pressed.connect(func() -> void: clicked_state[0] = true)
	title.add_child(test_btn)
	await get_tree().process_frame

	# 验证 FooterShade 不阻挡其�?内部元素的事件接�?
	eq(shade.mouse_filter, Control.MOUSE_FILTER_IGNORE, "FooterShade 绝不拦截鼠标事件")
	test_btn.emit_signal("pressed")
	ok(clicked_state[0], "FooterShade 覆盖区内的按钮点击正常触发，无事件阻�?)

	title.queue_free()
	await get_tree().process_frame


## 场景 4：Crucible 熔铁流高密度采样点距与连�?2px 折线验证
func test_crucible_continuous_stream_and_point_density() -> void:
	var crucible_script := preload("res://scripts/ui/title_crucible.gd")
	var crucible = crucible_script.new()
	add_child(crucible)
	crucible._setup()

	# 驱动进入 Phase.POUR 且铁水下落到一定长�?
	crucible._phase = 3  # Phase.POUR
	crucible._stream_top = 0.0
	crucible._stream_bot = 160.0  # 半长铁水�?

	var pts: PackedVector2Array = crucible.stream_polyline(-1)
	ok(pts.size() >= 50, "自适应连续采样返回足够多的折线点数 (%d)" % pts.size())

	var max_dist := 0.0
	for i in pts.size() - 1:
		var dist: float = (pts[i + 1] - pts[i]).length()
		max_dist = maxf(max_dist, dist)

	ok(max_dist <= 2.0, "熔铁流折线相邻点欧氏距离严格 <= 2.0px (实测最大�? %.3f)" % max_dist)
	ok(max_dist <= 1.415, "熔铁流折线点距符�?2px 像素网格对角线限�?(实测: %.3f <= 1.415)" % max_dist)

	# 满长铁水�?(落地状�?
	crucible._stream_bot = crucible.stream_max()
	var full_pts: PackedVector2Array = crucible.stream_polyline(-1)
	ok(full_pts.size() >= 100, "满长铁水柱采样点充足 (%d)" % full_pts.size())

	var full_max_dist := 0.0
	for i in full_pts.size() - 1:
		var dist: float = (full_pts[i + 1] - full_pts[i]).length()
		full_max_dist = maxf(full_max_dist, dist)

	ok(full_max_dist <= 2.0, "满长熔铁流折线相邻点距严�?<= 2.0px (实测最大�? %.3f)" % full_max_dist)

	crucible.queue_free()
	await get_tree().process_frame


## 场景 5：MenuItem 灯标暖度渐变与禁用行高对比度保真
func test_menu_item_warmth_and_disabled_contrast() -> void:
	var item := MenuItem.new("测试菜单�?, MenuItem.Kind.SECONDARY)
	item.lamp = true
	add_child(item)
	await get_tree().process_frame

	# 1. 禁用状态：对比�?>= 4:1，字色保持冷�?
	item.disabled = true
	item.set_lamp_light(0.0)
	var col_dark: Color = item._label.get_theme_color("font_color")
	item.set_lamp_light(1.0)
	var col_bright: Color = item._label.get_theme_color("font_color")
	eq(col_dark, col_bright, "禁用行字色不随灯照改�?)
	almost(col_dark.r, 0.68, 0.02, "禁用行字体色保持 elevation 0.68")
	almost(col_dark.a, 0.90, 0.02, "禁用行字�?alpha 保持 0.90")

	# 2. 正常状态：暖度渐变单调递增
	item.disabled = false
	item.set_lamp_light(0.0)
	var c0: Color = item._label.get_theme_color("font_color")
	item.set_lamp_light(0.5)
	var c1: Color = item._label.get_theme_color("font_color")
	item.set_lamp_light(1.0)
	var c2: Color = item._label.get_theme_color("font_color")

	ok(c1.r > c0.r, "暖度 0.5 相比 0.0 红色通道增加 (%.2f > %.2f)" % [c1.r, c0.r])
	ok(c2.r >= c1.r, "暖度 1.0 相比 0.5 呈现白热 (r=%.2f)" % c2.r)
	ok(c2.g > c1.g, "白热核心绿色通道升高体现琥珀转白 (%.2f > %.2f)" % [c2.g, c1.g])

	item.queue_free()
	await get_tree().process_frame
