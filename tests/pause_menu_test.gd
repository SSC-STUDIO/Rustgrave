extends TestCase
## Ending choice and pause must not fight over tree.paused.


func setup() -> void:
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false


func teardown() -> void:
	Director.choice_hold = false
	Director.resume()
	if get_tree().paused:
		get_tree().paused = false


func test_choice_hold_blocks_pause_open() -> void:
	var menu := PauseMenu.new()
	add_child(menu)
	await flush(1)
	Director.choice_hold = true
	get_tree().paused = true
	menu.open()
	ok(not menu.is_open(), "choice hold blocks Esc pause")
	ok(get_tree().paused, "ending stay paused")


func test_choice_hold_close_does_not_unpause() -> void:
	var menu := PauseMenu.new()
	add_child(menu)
	await flush(1)
	menu.open()
	ok(menu.is_open())
	ok(get_tree().paused)
	Director.choice_hold = true
	menu.close()
	ok(not menu.is_open(), "pause layer hides")
	ok(get_tree().paused, "close does not resume the tree during ending")


## 暂停档案卡和地图共用同一个章节名口径：第一章 / 第二章读 ChapterTitles，
## 数据驱动章节读 layout.title()。地图以前对第一章显示空标题。
func test_map_and_pause_share_the_chapter_title_source() -> void:
	var first := Level01Static.new()
	eq(MapScreen.chapter_title(first), ChapterTitles.LEVEL01,
			"level 1 title comes from the shared chapter titles")
	first.free()

	var second := Level02Undercroft.new()
	# 第二章的章节名现在由 Level02Layout.title() 提供（文本在 ChapterText）；真实场景
	# _ready 会把这个 Layout 子节点挂进来，裸 fixture 也补一个同名子节点走同一条路径。
	var crypt := Level02Layout.new()
	crypt.name = "Layout"
	second.add_child(crypt)
	eq(MapScreen.chapter_title(second), ChapterTitles.LEVEL02,
			"level 2 title comes from the shared chapter titles")
	second.free()

	var host := ChapterLevel.new()
	var layout := ChapterLayout.new()
	layout.name = "Layout"
	host.add_child(layout)
	host.layout = layout
	eq(MapScreen.chapter_title(host), layout.title(),
			"data-driven chapter title comes from layout.title()")
	host.free()


## 地图快照必须真的收得到平台、出生点和玩家，且在无平台时明确返回空（不画错图）。
func test_map_snapshot_collects_the_live_world() -> void:
	var world := Node2D.new()
	world.name = "MapFixtureWorld"
	add_child(world)
	var platform := SolidPlatform.new()
	platform.name = "Floor"
	platform.size = Vector2(240.0, 16.0)
	platform.position = Vector2(100.0, 200.0)
	world.add_child(platform)
	var player := Node2D.new()
	player.name = "Player"
	player.position = Vector2(180.0, 160.0)
	world.add_child(player)
	await flush(1)
	var snapshot := MapScreen.collect(world, player)
	eq((snapshot.get("platforms", []) as Array).size(), 1, "platform collected")
	eq(snapshot.get("player", Vector2.INF), Vector2(180.0, 160.0), "player marker collected")
	ok(not snapshot.is_empty(), "map can draw this room")

	var empty := Node2D.new()
	add_child(empty)
	eq(MapScreen.collect(empty, player), {}, "a room without platforms reports no map")
	world.queue_free()
	empty.queue_free()
	await flush(1)


func test_map_hotkey_opens_directly_and_returns_to_play() -> void:
	Director.abort()
	GameContext._blocked_through_frame = -1
	var menu := PauseMenu.new()
	add_child(menu)
	await flush(1)
	var event := InputEventAction.new()
	event.action = &"map"
	event.pressed = true
	menu._unhandled_input(event)
	ok(menu.map_screen().visible, "dedicated hotkey goes directly to map")
	ok(get_tree().paused, "map pauses play")
	menu.map_screen().close()
	await flush(20)
	ok(not menu.is_open(), "closing direct map returns to play")
	ok(not get_tree().paused)


func test_real_start_event_opens_closes_and_returns_from_submenus() -> void:
	Director.abort()
	GameContext._blocked_through_frame = -1
	var menu := PauseMenu.new()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	await _tap_start()
	ok(menu.is_open(), "真实 Start 经 InputMap 打开暂停菜单")
	ok(get_tree().paused, "Start 打开菜单后暂停游戏")
	await _tap_start()
	await flush(20)
	ok(not menu.is_open(), "再次按 Start 关闭暂停菜单")
	ok(not get_tree().paused, "Start 关闭菜单后恢复游戏")

	await _tap_start()
	for submenu in [PauseMenu.ID_SETTINGS, PauseMenu.ID_TUTORIAL, PauseMenu.ID_CONTROLS, PauseMenu.ID_MAP]:
		menu._on_chosen(submenu)
		await flush(20)
		ok(menu.sub_screen_open(), "%s 子页已打开" % String(submenu))
		await _tap_start()
		await flush(20)
		ok(not menu.sub_screen_open(), "Start 从 %s 返回暂停菜单" % String(submenu))
		ok(menu.is_open() and get_tree().paused, "子页返回后仍停在暂停菜单")
	await _tap_start()
	await flush(20)
	ok(not menu.is_open() and not get_tree().paused, "子页返回后可继续用 Start 恢复游戏")


func _tap_start() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_START
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_START
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

