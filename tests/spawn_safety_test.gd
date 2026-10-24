extends TestCase
## 读档坐标安全阀：坐标没埋进实心、没压在判定中的机关里就原样用；否则退到
## 最后点亮的巢 → 任意巢 → 缺省出生点。

var _layout: ChapterLayout


func setup() -> void:
	SaveData.delete_save()


func teardown() -> void:
	SaveData.delete_save()


func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	_layout = ChapterLayout.new()
	add_child(_layout)
	_layout.floor_strip(host, "Floor", 0.0, 1200.0, "moss")
	return host


func test_safe_and_unsafe_positions() -> void:
	var host := _host()
	ok(SpawnSafety.is_safe(host, Vector2(200, 320)), "standing on the floor top")
	ok(SpawnSafety.is_safe(host, Vector2(200, 250)), "in the air above it")
	ok(not SpawnSafety.is_safe(host, Vector2(200, 340)), "buried in the floor")
	ok(not SpawnSafety.is_safe(host, Vector2(200, 700)), "below the world")
	ok(not SpawnSafety.is_safe(host, Vector2.INF), "no position at all")
	ok(SpawnSafety.is_safe(null, Vector2(5, 5)), "no world to check = trust the caller")


func test_a_position_inside_a_hazard_zone_is_unsafe() -> void:
	var host := _host()
	_layout.cyclic(host, "Vent", Vector2(400, 320), "steam")
	ok(not SpawnSafety.is_safe(host, Vector2(400, 320)), "right on the vent")
	ok(SpawnSafety.is_safe(host, Vector2(520, 320)), "a few steps away is fine")
	_layout.pendulum(host, "Swing", Vector2(800, 240), 70.0)
	ok(not SpawnSafety.is_safe(host, Vector2(800, 308)), "under the pendulum's sweep")


func test_safe_saved_position_is_kept() -> void:
	var host := _host()
	var kept := SpawnSafety.safe_position(host, Vector2(222, 320), Vector2(50, 300))
	eq(kept, Vector2(222, 320))


func test_unsafe_position_falls_back_to_the_last_lit_nest_then_any_nest_then_default() -> void:
	var host := _host()
	var nest_a := _layout.nest(host, "NestA", 150.0) as Node2D
	var nest_b := _layout.nest(host, "NestB", 650.0) as Node2D
	var default := Vector2(50, 300)
	var buried := Vector2(400, 360)
	# 没有点亮的巢：退到「任意一个巢」（先遇到的那个）。
	var any := SpawnSafety.safe_position(host, buried, default)
	ok(any == nest_a.global_position or any == nest_b.global_position, "any nest when none is lit")
	# 最后点亮的是 B：优先回 B。
	SaveData.register_lit_nest(SaveData.persist_path(nest_a))
	SaveData.register_lit_nest(SaveData.persist_path(nest_b))
	eq(SpawnSafety.safe_position(host, buried, default), nest_b.global_position, "the last lit nest wins")
	# 世界里一个巢也没有：缺省点。
	var empty := Node2D.new()
	add_child(empty)
	var layout2 := ChapterLayout.new()
	add_child(layout2)
	layout2.floor_strip(empty, "Floor", 0.0, 400.0, "moss")
	SaveData.lit_nests.clear()
	eq(SpawnSafety.safe_position(empty, Vector2(100, 360), default), default, "default spawn as the last resort")


func test_a_nest_that_is_itself_buried_is_skipped() -> void:
	var host := _host()
	var good := _layout.nest(host, "NestGood", 150.0) as Node2D
	var bad := _layout.nest(host, "NestBad", 650.0) as Node2D
	bad.position.y = 340.0   # 改版后被挪进了地面
	SaveData.register_lit_nest(SaveData.persist_path(bad))
	var spot := SpawnSafety.safe_position(host, Vector2(400, 360), Vector2(50, 300))
	eq(spot, good.global_position, "a buried lit nest is skipped for a usable one")
