extends TestCase
## 竞技场垂直切片：规则常量、独立记录、标题入口、战役档不落盘。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const ArenaRun := preload("res://scripts/autoload/arena_run.gd")
const PATH := "user://test_arena_records.cfg"


func setup() -> void:
	ArenaRun.use_file(PATH)
	ArenaRun.use_default_file()
	ArenaRun.use_file(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func teardown() -> void:
	ArenaRun.use_default_file()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_catalog_rules_and_formatting() -> void:
	ok(ResourceLoader.exists(ArenaCatalog.SCENE), "竞技场场景存在")
	ok(ResourceLoader.exists(ArenaCatalog.TITLE_SCENE))
	eq(ArenaCatalog.DURATION, 90.0)
	ok(ArenaCatalog.MAX_ALIVE >= 1)
	eq(ArenaCatalog.format_time(90.0), "01:30")
	eq(ArenaCatalog.format_time(4.2), "00:05")
	var text := ArenaCatalog.strip_text(120, 4, 87.0)
	ok(text.contains("得分 120") and text.contains("击杀 4") and text.contains("01:27"))
	ok(ArenaCatalog.result_summary({"win": true, "score": 80, "kills": 3}).begins_with("胜"))
	ok(ArenaCatalog.result_summary({"win": false, "score": 20, "kills": 1}).begins_with("负"))
	var wave := ArenaCatalog.enemy_for_wave(0)
	ok(String(wave.get("scene", "")).begins_with("res://scenes/enemies/"))


func test_records_persist_best_score_and_runs() -> void:
	eq(ArenaRun.read_records(), {"best_score": 0, "best_kills": 0, "runs": 0})
	ArenaRun._write_records({"score": 60, "kills": 2})
	ArenaRun._write_records({"score": 140, "kills": 5})
	ArenaRun._write_records({"score": 90, "kills": 3})
	var records := ArenaRun.read_records()
	eq(int(records["best_score"]), 140, "最高分保留")
	eq(int(records["best_kills"]), 5)
	eq(int(records["runs"]), 3, "场次累加")


func test_inactive_arena_does_not_block_campaign_save() -> void:
	ok(not ArenaRun.active())
	ok(not ArenaRun.blocks_campaign_save(), "不在竞技场时不影响战役存档")
	eq(ArenaRun.score(), 0)
	eq(ArenaRun.time_left(), ArenaCatalog.DURATION)


func test_title_has_an_arena_entry() -> void:
	var packed := load("res://scenes/ui/TitleScreen.tscn") as PackedScene
	var title := packed.instantiate() as Node
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu := title.get_node_or_null("Menu") as MenuList
	ok(menu != null, "标题菜单存在")
	if menu != null:
		ok(menu.item_ids().has(&"arena"), "菜单架里有竞技场模式格")
		ok(menu.items()[3].kind == MenuItem.Kind.SECONDARY, "竞技场是模式组次档板")
	title.queue_free()
	await get_tree().process_frame
