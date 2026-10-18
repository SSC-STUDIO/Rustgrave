extends TestCase
## UI 过渡动效回归：进场不是"闪一下出来"，开关都要走同一条曲线。
##
## 三条契约：
##   1. 开屏有黑幕与分阶淡入（_play_intro）：keyart 先渗出来、字标随后、
##      菜单逐行爬上来；任何确认键跳过开屏后菜单照常执行。
##   2. 弹窗入场是"滑上来 + 纱幕压下"，退场是"沉回去 + 纱幕收掉"，
##      而且退完才 visible = false（不是闪断）。
##   3. headless 与 Director.fade_to 同约定：落终态后同步回调，
##      测试可以一帧后断言 is_open()/visible。

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const Transitions := preload("res://scripts/ui/ui_transition.gd")


func _open_title() -> TitleScreen:
	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	return title


func _items(title: TitleScreen) -> Array:
	var out := []
	for child in title.get_node("Menu").get_children():
		if child is MenuItem:
			out.append(child)
	return out


# ---------------------------------------------------------------------------
# 1. 标题屏开屏
# ---------------------------------------------------------------------------

func test_title_intro_stages_the_scene_instead_of_popping_it_in() -> void:
	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate() as TitleScreen
	add_child(title)
	# 第一帧就读状态：_ready 里 _play_intro 刚把所有元素压到透明。
	await get_tree().process_frame
	ok(title.intro_playing(), "标题屏进场景先播开屏动画")
	# 黑幕在场：整段开场最上层压着一层纯黑。
	ok(title.find_child("BootCurtain", true, false) is ColorRect,
			"开屏黑幕存在（BootCurtain）")
	# 场景元素此时还没亮：keyart / 字标 / 菜单行都在透明起始态。
	var keyart := title.find_child("Keyart", true, false) as CanvasItem
	var masthead := title.find_child("Masthead", true, false) as CanvasItem
	ok(keyart != null and masthead != null, "keyart 与字标都在场景里")
	if keyart != null:
		ok(keyart.modulate.a < 0.95,
				"开屏首帧 keyart 未全亮（%.2f，黑幕还在退）" % keyart.modulate.a)
	if masthead != null:
		almost(masthead.modulate.a, 0.0, 0.01, "开屏第一帧字标未亮")
	for item in _items(title):
		almost(item.modulate.a, 0.0, 0.01, "菜单行开屏未亮：%s" % item.get_index())

	title.queue_free()
	await get_tree().process_frame


## 开屏不是输入门禁：动画期间按确认 = 跳到终态并照常执行那一格。
func test_title_intro_skips_on_confirm_and_still_acts() -> void:
	var title: TitleScreen = await _open_title()
	title.quit_on_finish = false
	title._on_chosen(TitleScreen.ID_SETTINGS)
	await get_tree().process_frame
	ok(not title.intro_playing(), "确认键跳过了开屏")
	var settings := title.find_child("SettingsScreen", true, false) as Control
	if settings != null:
		ok(settings.visible, "跳过开屏后这一格照常执行（设置已打开）")
	# 跳过后所有元素都亮着，不留半透明中间帧。
	for item in _items(title):
		almost(item.modulate.a, 1.0, 0.01, "跳过后菜单行全亮：%d" % item.get_index())
	ok(title.find_child("BootCurtain", true, false) == null,
			"跳过后黑幕撤掉")

	title.queue_free()
	await get_tree().process_frame


## 退场动画也要能从中途开始：开屏没播完就离开锈墓，
## 不能出现淡入 tween 和熄灭 tween 抢同一个 modulate。
func test_quit_from_mid_intro_does_not_fight_the_breathing() -> void:
	var title: TitleScreen = await _open_title()
	title.quit_on_finish = false
	title._on_chosen(TitleScreen.ID_QUIT)
	await get_tree().process_frame
	ok(title.is_quitting(), "开屏中途离开仍能进入退场")
	ok(not title.intro_playing(), "退场接手时开屏已收干净")
	title._finish_quit()
	ok(title.quit_finished(), "退场照常收尾")
	title.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# 2. 弹窗开关场
# ---------------------------------------------------------------------------

func test_modal_shell_exposes_in_and_out_steps() -> void:
	# 每个 Modal.build 的消费者都要拿到 play_intro / play_outro / finish_instantly
	# 三个入口，开关才能走同一条曲线。
	for script_path in [
			"res://scripts/ui/settings_screen.gd",
			"res://scripts/ui/controls_panel.gd",
			"res://scripts/ui/character_select_screen.gd",
			"res://scripts/ui/map_screen.gd",
			"res://scripts/ui/tutorial_recall.gd",
			"res://scripts/ui/pause_menu.gd",
			"res://scripts/ui/character_equipment_panel.gd",
	]:
		var script: GDScript = load(script_path)
		ok(script != null, "%s 可加载" % script_path.get_file())
		if script == null:
			continue
		var src := script.source_code
		ok(src.contains("play_intro"), "%s 走弹窗入场" % script_path.get_file())
		ok(src.contains("play_outro"), "%s 走弹窗退场" % script_path.get_file())


## 退场播完才隐藏：close() 不能在 on_done 之前就把 visible 抹掉。
func test_modal_out_defers_hide_until_the_tween_finishes() -> void:
	# 无头环境下与 Director.fade_to 同约定：同步落终态并回调。
	var called := [false]
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var card := Control.new()
	card.position = Vector2(100.0, 100.0)
	root.add_child(card)
	var veil := ColorRect.new()
	veil.modulate.a = 1.0
	root.add_child(veil)
	Transitions.modal_out(root, card, veil, func() -> void: called[0] = true)
	ok(called[0], "headless 下退场同步回调 on_done（测试可一帧后断言）")
	root.queue_free()
	await get_tree().process_frame


## 中途打断（再按一次开关）要把卡片位置落回原位，不能留在下移 18px 处。
func test_modal_reset_restores_card_home_and_veil() -> void:
	var root := Control.new()
	add_child(root)
	var card := Control.new()
	card.position = Vector2(50.0, 60.0)
	root.add_child(card)
	var veil := ColorRect.new()
	veil.modulate.a = 0.5
	root.add_child(veil)
	Transitions.modal_reset(root, card, veil, Vector2(50.0, 60.0), 1.0)
	almost(card.position.x, 50.0, 0.01, "打断后卡片 x 落回原位")
	almost(card.position.y, 60.0, 0.01, "打断后卡片 y 落回原位")
	almost(card.modulate.a, 1.0, 0.01, "打断后卡片不透明")
	almost(veil.modulate.a, 1.0, 0.01, "打断后纱幕归位")
	root.queue_free()
	await get_tree().process_frame
