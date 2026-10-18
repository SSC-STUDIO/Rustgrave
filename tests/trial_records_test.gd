extends TestCase
## 回火试炼独立记录文件：往返 / 更快成绩覆盖 / 更慢成绩只加 runs /
## 未知字段保留 / 损坏与版本回退 / 时间格式化。

const Records := preload("res://scripts/data/trial_records.gd")
const Catalog := preload("res://scripts/data/trial_catalog.gd")
const TEST_PATH := "user://trial_records_test.cfg"


func setup() -> void:
	Records.use_file(TEST_PATH)
	Records.delete_file()


func teardown() -> void:
	Records.delete_file()
	Records.use_default_file()


func _write_file(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _config() -> ConfigFile:
	var cfg := ConfigFile.new()
	eq(cfg.load(TEST_PATH), OK, "记录文件可读")
	return cfg


func test_missing_file_reads_as_empty_records() -> void:
	ok(not Records.read_from_disk(), "没有文件时 reload 返回 false")
	var best := Records.best(Catalog.Track.TIME_ATTACK, "level01")
	eq(best, {}, "没有记录")
	eq(Records.summary_line(Catalog.Track.TIME_ATTACK, "level01"), "", "没有摘要行")


func test_round_trip_writes_an_independent_v1_file() -> void:
	var submit := Records.submit(Catalog.Track.TIME_ATTACK, "level03", {
		"elapsed_ms": 83000, "deaths": 1, "rank": "A", "no_hit": false,
	})
	ok(bool(submit["is_best"]) and bool(submit["is_first"]), "首跑即最佳")
	ok(FileAccess.file_exists(TEST_PATH), "记录写到独立文件")
	ok(not TEST_PATH.begins_with(SaveData.save_path.get_base_dir() + "rustgrave_save"),
			"记录文件不是战役档")
	var cfg := _config()
	eq(int(cfg.get_value("meta", "version", 0)), 1, "记录文件 version 1")
	ok(cfg.has_section("records"), "写进 records section")
	# 重新从磁盘读：内存缓存丢掉也能恢复。
	Records.read_from_disk()
	var record := Records.best(Catalog.Track.TIME_ATTACK, "level03")
	eq(int(record.get("ms", 0)), 83000, "用时往返")
	eq(int(record.get("deaths", 0)), 1, "死亡数往返")
	eq(String(record.get("rank", "")), "A", "评级往返")
	eq(int(record.get("runs", 0)), 1, "runs 从 1 起")
	eq(Records.best_ms(Catalog.Track.TIME_ATTACK, "level03"), 83000)
	eq(Records.best_rank(Catalog.Track.TIME_ATTACK, "level03"), &"A")
	ok("01:23.0" in Records.summary_line(Catalog.Track.TIME_ATTACK, "level03"),
			"摘要带格式化时间")
	eq(Records.best(Catalog.Track.TIME_ATTACK, "level04"), {}, "别的目标不受影响")


func test_faster_run_replaces_slower_only_bumps_runs() -> void:
	Records.submit(Catalog.Track.TIME_ATTACK, "level03",
			{"elapsed_ms": 90000, "deaths": 0, "rank": "A"})
	var slower := Records.submit(Catalog.Track.TIME_ATTACK, "level03",
			{"elapsed_ms": 120000, "deaths": 2, "rank": "B"})
	ok(not bool(slower["is_best"]), "更慢不算最佳")
	eq(int(Records.best_ms(Catalog.Track.TIME_ATTACK, "level03")), 90000, "最佳时间不被覆盖")
	eq(int((Records.best(Catalog.Track.TIME_ATTACK, "level03") as Dictionary)["runs"]), 2,
			"重跑次数累计")
	var faster := Records.submit(Catalog.Track.TIME_ATTACK, "level03",
			{"elapsed_ms": 70000, "deaths": 0, "rank": "S"})
	ok(bool(faster["is_best"]), "更快就是新最佳")
	eq(int(Records.best_ms(Catalog.Track.TIME_ATTACK, "level03")), 70000)
	eq(Records.best_rank(Catalog.Track.TIME_ATTACK, "level03"), &"S")
	eq(int((Records.best(Catalog.Track.TIME_ATTACK, "level03") as Dictionary)["runs"]), 3)


func test_boss_rush_no_hit_is_kept_even_when_time_gets_better() -> void:
	var track := Catalog.Track.BOSS_RUSH
	Records.submit(track, Catalog.ALL_BOSSES_ID,
			{"elapsed_ms": 200000, "deaths": 0, "no_hit": true, "rank": "A"})
	ok(Records.has_no_hit(track, Catalog.ALL_BOSSES_ID), "无伤标记写入")
	Records.submit(track, Catalog.ALL_BOSSES_ID,
			{"elapsed_ms": 150000, "deaths": 1, "no_hit": false, "rank": "A"})
	ok(bool((Records.best(track, Catalog.ALL_BOSSES_ID) as Dictionary)["no_hit"]),
			"无伤是达成过的标记，不被更快的非无伤成绩抹掉")
	eq(int(Records.best_ms(track, Catalog.ALL_BOSSES_ID)), 150000, "时间仍取更快的那次")


func test_unknown_fields_and_sections_are_preserved() -> void:
	_write_file("""[meta]
version=1

[records]
time_attack={"level03":{"ms":90000,"deaths":0,"rank":"A","runs":1,"score_ms":90000,"future_field":"keep-me"}}

[future_section]
foo=7
""")
	ok(Records.read_from_disk(), "读到 v1 文件")
	eq(String((Records.best(Catalog.Track.TIME_ATTACK, "level03") as Dictionary)
			.get("future_field", "")), "keep-me", "未知记录字段读进内存")
	Records.submit(Catalog.Track.TIME_ATTACK, "level03",
			{"elapsed_ms": 80000, "deaths": 0, "rank": "S"})
	Records.read_from_disk()
	eq(String((Records.best(Catalog.Track.TIME_ATTACK, "level03") as Dictionary)
			.get("future_field", "")), "keep-me", "刷新记录后未知字段仍在")
	var cfg := _config()
	eq(int(cfg.get_value("future_section", "foo", 0)), 7, "未知 section 原样保留")


func test_corrupt_file_falls_back_to_empty_and_rewrites_cleanly() -> void:
	_write_file("this is not a config :: [broken")
	ok(not Records.read_from_disk(), "坏文件当读不到")
	ok(Records.was_corrupt(), "标记损坏，便于下次覆写")
	eq(Records.best(Catalog.Track.TIME_ATTACK, "level03"), {}, "损坏时记录为空，不崩")
	Records.submit(Catalog.Track.TIME_ATTACK, "level03",
			{"elapsed_ms": 60000, "deaths": 0, "rank": "S"})
	var cfg := _config()
	eq(int(cfg.get_value("meta", "version", 0)), 1, "损坏后写出干净 v1 文件")
	ok(not Records.was_corrupt(), "写成功后不再标记损坏")
	# 版本不认识也回退为空。
	_write_file("[meta]\nversion=99\n[records]\ntime_attack={}\n")
	ok(not Records.read_from_disk(), "未知版本拒绝")
	eq(Records.best(Catalog.Track.TIME_ATTACK, "level03"), {}, "未知版本不读出半截数据")


func test_clear_all_keeps_foreign_sections() -> void:
	_write_file("""[meta]
version=1

[records]
time_attack={"level03":{"ms":90000,"deaths":0,"rank":"A","runs":1,"score_ms":90000}}

[future_section]
foo=7
""")
	Records.read_from_disk()
	Records.clear_all()
	var cfg := _config()
	eq(int(cfg.get_value("future_section", "foo", 0)), 7, "清记录不动未知 section")
	Records.read_from_disk()
	eq(Records.best(Catalog.Track.TIME_ATTACK, "level03"), {}, "记录清空")


func test_format_ms_and_rank_helpers() -> void:
	eq(Records.format_ms(0), "00:00.0")
	eq(Records.format_ms(7200), "00:07.2")
	eq(Records.format_ms(83000), "01:23.0")
	eq(Records.format_ms(123456), "02:03.5")
	eq(Records.format_ms(-5), "00:00.0", "负值不会画出负时间")
	eq(Records.format_rank(&"S"), "S")
	ok("S" in Records.rank_label(&"S"), "评级标签")
