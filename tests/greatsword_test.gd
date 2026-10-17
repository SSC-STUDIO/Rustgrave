extends TestCase
## 主角巨剑：贴图存在、背在身后（z 低于身体）、挥砍/死亡时让位、开场插在土里且退场必收。
## 巨剑是"沉重武器"这一身份的主剪影，所以它不能只在文档里存在。

const Opening := preload("res://scripts/levels/opening_cinematic.gd")
const BACK_PATH := "res://assets/player/greatsword_back.png"
const PLANTED_PATH := "res://assets/player/greatsword_planted.png"


func test_sword_assets_exist_and_are_one_x_pixels() -> void:
	for path in [BACK_PATH, PLANTED_PATH]:
		ok(ResourceLoader.exists(path), "%s is imported" % path)
		var tex := load(path) as Texture2D
		ok(tex != null, "%s loads as a Texture2D" % path)
		if tex != null:
			# 1x 像素图：整数尺寸，宽度/高度都在角色可用的量级里（不是被放大过的贴图）。
			ok(float(tex.get_width()) == floorf(float(tex.get_width())), "integer width")
			ok(tex.get_width() <= 64, "blade width stays in one character canvas")
			ok(tex.get_height() <= 72, "blade length is about 1.4x body height, not a tower")


func test_back_sword_sits_behind_the_body_and_follows_the_visual() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -1))
	var carrier := player.visual.get_node_or_null("Greatsword") as Greatsword
	ok(carrier != null, "Player.tscn carries a Greatsword node")
	ok(carrier != null and carrier.get_parent() == player.visual,
			"it hangs off Visual, so facing flips it with the body")
	ok(carrier != null and carrier.z_index < 0, "it draws behind the knight sprite")
	var blade := carrier.get_node_or_null("Blade") as Sprite2D if carrier != null else null
	ok(blade != null and blade.texture != null, "the blade sprite has its texture")
	ok(blade != null and blade.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"pixel art must not be filtered")
	await flush(4)
	ok(carrier.is_showing(), "idle knight shows the greatsword on his back")
	arena.queue_free()


func test_sword_yields_during_a_swing_and_comes_back_after() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -1))
	var carrier := player.visual.get_node_or_null("Greatsword") as Greatsword
	ok(player.melee.start_swing(), "a swing starts")
	var hid := false
	for _i in 30:
		player.greatsword.tick(player, 1.0 / 60.0)
		if not carrier.is_showing():
			hid = true
			break
	ok(hid, "the carried blade fades out while the frames' own sword swings")
	# 挥完（后摇结束）后淡入回来；这里直接推 tick，不依赖引擎物理帧。
	var guard := 0
	while player.melee.is_busy() and guard < 240:
		player.melee.tick(1.0 / 60.0)
		player.greatsword.tick(player, 1.0 / 60.0)
		guard += 1
	for _i in 40:
		player.greatsword.tick(player, 1.0 / 60.0)
	ok(carrier.is_showing(), "the blade returns once the swing is over")
	arena.queue_free()


func test_planted_sword_stands_on_the_given_ground_point() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var tip := Vector2(72, 320)
	var planted := Greatsword.spawn_planted(arena, tip)
	ok(planted != null, "the planted variant spawns")
	ok(planted != null and planted.get_parent() == arena, "it is parented to the world host")
	ok(planted != null and planted.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"planted variant is nearest-filtered")
	ok(planted != null and planted.z_index == 1, "default draw order is above the level art")
	ok(planted != null and planted.position + Greatsword.PLANTED_TIP_PX == tip,
			"the blade tip lands on the requested ground point (integer feet)")
	arena.queue_free()


func test_opening_plants_the_sword_and_every_exit_takes_it_back() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(320, -1))
	var carrier := player.visual.get_node_or_null("Greatsword") as Greatsword
	SaveData.save_path = "user://rustgrave_greatsword_test.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.ending = ""
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	Opening.reset()
	Director.abort()
	Director.resume()
	Director.hide_hint()
	Director.choice_hold = false
	get_tree().paused = false
	ok(Opening.try_start(player, null), "the opening starts")
	var planted := arena.get_node_or_null("PlantedGreatsword")
	ok(planted != null, "the opening plants the greatsword beside the prone knight")
	ok(carrier != null and not carrier.visible, "the carried blade is off the back while he is down")
	Director.abort()
	await flush(2)
	ok(arena.get_node_or_null("PlantedGreatsword") == null, "abort removes the planted sword")
	ok(carrier != null and carrier.is_showing(), "abort puts the blade back on his back")
	ok(not SaveData.has_flag(Opening.FLAG), "an interrupted opening is still not seen")
	SaveData.delete_save()
	Opening.reset()
	arena.queue_free()
