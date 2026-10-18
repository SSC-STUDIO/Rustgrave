extends RefCounted
## 回火试炼的独立记录文件（user://rustgrave_trials.cfg，version 1）。
##
## 文件不带 class_name：使用方统一
## `const Records := preload("res://scripts/data/trial_records.gd")`。
##
## 为什么要独立文件：试炼不许碰战役 `SaveData`（契约 §2/§5）。删掉战役档不该清空
## 试炼记录；清空试炼记录也不该影响战役。两边唯一的交叉是"只读解锁旗标"。
##
## 文件结构（ConfigFile）：
##   [meta]    version = 1
##   [records] boss_rush = {"all": {ms, deaths, rank, no_hit, runs, score_ms, updated}}
##             time_attack = {"level02": {...}, ...}
##             bare_steel = {...}
##   [*]       其他未知 section / key 原样保留（未来加字段不丢玩家数据）
##
## 损坏回退：格式错误 / 版本不认识 / 字段类型不对 → 当空记录处理（读永不崩），
## 下一次 submit() 会写一份干净的新文件；已知字段类型每次读取都做一次清洗。

const VERSION := 1
const DEFAULT_PATH := "user://rustgrave_trials.cfg"
## 用 preload 而不是全局类名：新 class_name 要等编辑器 / --import 写类缓存，
## 多 agent 分支合并期间先用脚本资源引用，合并后也照样能用。
const Catalog := preload("res://scripts/data/trial_catalog.gd")
const META_SECTION := "meta"
const RECORDS_SECTION := "records"
## 记录里由本文件维护的字段（其余字段原样往返）。
const MANAGED_FIELDS: Array[String] = ["ms", "deaths", "rank", "no_hit", "runs",
		"score_ms", "updated"]

static var _path := DEFAULT_PATH
static var _cache: Dictionary = {}
static var _foreign: Dictionary = {}
static var _loaded := false
static var _corrupt := false


# --- 路径 / 加载 ---------------------------------------------------------------

static func path() -> String:
	return _path


## 测试与工具用：改记录文件位置并清空内存缓存。
## 名字不能叫 set_path：脚本资源本身继承 Resource.set_path()，经 preload 常量调用时
## 会先命中 Resource 的同名方法而静默丢掉这次调用。
static func use_file(new_path: String) -> void:
	_path = new_path
	_loaded = false
	_cache = {}
	_foreign = {}
	_corrupt = false


static func use_default_file() -> void:
	use_file(DEFAULT_PATH)


## 是否读到过损坏文件（下一次 save 会重写成干净版本）。测试与报错提示用。
static func was_corrupt() -> bool:
	_ensure_loaded()
	return _corrupt


static func _ensure_loaded() -> void:
	if not _loaded:
		read_from_disk()


## 重新从磁盘读取。返回 true = 读到了可用的 v1 文件。
## 名字不能叫 reload()：Script 资源自带 reload()，经 preload 常量调用会命中它而
## 静默丢掉这次读取（与 set_path 同一类坑）。
static func read_from_disk() -> bool:
	_cache = {}
	_foreign = {}
	_corrupt = false
	_loaded = true
	if not FileAccess.file_exists(_path):
		return false
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		_corrupt = true
		return false
	var text := file.get_as_text()
	file.close()
	var cfg := ConfigFile.new()
	if cfg.parse(text) != OK:
		_corrupt = true
		return false
	if int(cfg.get_value(META_SECTION, "version", 0)) != VERSION:
		_corrupt = true
		return false
	# [records] 里一条赛道一个 key（track_id -> {target_id: record}），人和工具都读得懂；
	# 兼容早期只写一个 "records" 大字典的版本。
	var raw: Variant = cfg.get_value(RECORDS_SECTION, "records", {})
	if raw is Dictionary:
		for track_key in (raw as Dictionary):
			var per_target: Variant = (raw as Dictionary)[track_key]
			if per_target is Dictionary and not _cache.has(String(track_key)):
				_cache[String(track_key)] = _clean_track(per_target)
	if cfg.has_section(RECORDS_SECTION):
		for track_key in cfg.get_section_keys(RECORDS_SECTION):
			if track_key == "records":
				continue
			var per_target: Variant = cfg.get_value(RECORDS_SECTION, track_key)
			if per_target is Dictionary:
				_cache[String(track_key)] = _clean_track(per_target)
	# 未知 section 原样保留（[meta]/[records] 之外）。
	for section in cfg.get_sections():
		if section == META_SECTION or section == RECORDS_SECTION:
			continue
		var sandbox: Dictionary = {}
		for key in cfg.get_section_keys(section):
			sandbox[key] = cfg.get_value(section, key)
		_foreign[section] = sandbox
	return true


static func _clean_track(per_target: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for target_key in per_target:
		var record: Variant = per_target[target_key]
		if not record is Dictionary:
			continue
		out[String(target_key)] = _clean_record(record as Dictionary)
	return out


static func _clean_record(record: Dictionary) -> Dictionary:
	var out: Dictionary = record.duplicate(true)
	out["ms"] = maxi(0, int(record.get("ms", 0)))
	out["deaths"] = maxi(0, int(record.get("deaths", 0)))
	var rank := String(record.get("rank", "B"))
	out["rank"] = rank if rank in ["S", "A", "B"] else "B"
	out["no_hit"] = bool(record.get("no_hit", false))
	out["runs"] = maxi(1, int(record.get("runs", 1)))
	out["score_ms"] = maxi(0, int(record.get("score_ms", out["ms"])))
	return out


# --- 查询 ---------------------------------------------------------------------

static func all() -> Dictionary:
	_ensure_loaded()
	return _cache.duplicate(true)


## 某赛道的全部目标记录（track_id -> record）。track 用 Catalog.Track。
static func for_track(track: int) -> Dictionary:
	_ensure_loaded()
	var track_id := String(Catalog.track_id(track))
	return (_cache.get(track_id, {}) as Dictionary).duplicate(true)


## 某目标的记录；没有记录返回空字典。
static func best(track: int, target_id: String) -> Dictionary:
	_ensure_loaded()
	var track_id := String(Catalog.track_id(track))
	var per_target: Dictionary = _cache.get(track_id, {})
	return (per_target.get(target_id, {}) as Dictionary).duplicate(true)


static func has_best(track: int, target_id: String) -> bool:
	return not best(track, target_id).is_empty()


static func best_ms(track: int, target_id: String) -> int:
	return int(best(track, target_id).get("ms", -1))


static func best_rank(track: int, target_id: String) -> StringName:
	return StringName(String(best(track, target_id).get("rank", "")))


## 该目标是否有一场"无伤"记录（Boss 连战用）。
static func has_no_hit(track: int, target_id: String) -> bool:
	return bool(best(track, target_id).get("no_hit", false))


## 一条记录的一行摘要；没有记录返回空串。
static func summary_line(track: int, target_id: String) -> String:
	var record := best(track, target_id)
	if record.is_empty():
		return ""
	var parts := [format_ms(int(record.get("ms", 0))), "死亡 %d" % int(record.get("deaths", 0)),
			"评级 %s" % String(record.get("rank", "B"))]
	if bool(record.get("no_hit", false)):
		parts.append("无伤")
	return " · ".join(parts)


# --- 写入 ---------------------------------------------------------------------

## 提交一次成绩。返回 {record, is_best, is_first, rank, previous}。
## 成绩相同或更慢时只累计 runs / 无伤标记，不覆盖最佳时间；未知字段原样保留。
static func submit(track: int, target_id: String, result: Dictionary) -> Dictionary:
	_ensure_loaded()
	var track_id := String(Catalog.track_id(track))
	var previous := best(track, target_id)
	var is_first := previous.is_empty()
	var runs := int(previous.get("runs", 0)) + 1
	var ms := maxi(0, int(result.get("elapsed_ms", 0)))
	var deaths := maxi(0, int(result.get("deaths", 0)))
	var score := Catalog.score_ms(track, ms, deaths)
	var rank := String(result.get("rank", ""))
	if rank == "":
		rank = String(Catalog.rank_for(track, ms, deaths,
				int(result.get("stage_count", 1))))
	var prev_score := int(previous.get("score_ms", score + 1))
	var is_best := is_first or score < prev_score
	var record: Dictionary = previous.duplicate(true)
	# 未知字段（未来 schema）从旧记录原样保留。
	record["runs"] = runs
	record["updated"] = Time.get_datetime_string_from_system()
	# 无伤是"达成过"的标记：打出一场无伤就保留，和最佳时间是否被刷新无关。
	record["no_hit"] = bool(previous.get("no_hit", false)) or bool(result.get("no_hit", false))
	if is_best:
		record["ms"] = ms
		record["deaths"] = deaths
		record["rank"] = rank
		record["score_ms"] = score
	elif not is_first:
		record["ms"] = int(previous.get("ms", ms))
		record["deaths"] = int(previous.get("deaths", deaths))
		record["rank"] = String(previous.get("rank", rank))
		record["score_ms"] = prev_score
	var per_target: Dictionary = _cache.get(track_id, {})
	per_target[target_id] = record
	_cache[track_id] = per_target
	save()
	return {
		"record": record.duplicate(true),
		"is_best": is_best,
		"is_first": is_first,
		"rank": StringName(rank),
		"previous": previous,
	}


## 清空全部记录（重写空文件；未知 section 保留）。
static func clear_all() -> void:
	_ensure_loaded()
	_cache = {}
	save()


static func save() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(META_SECTION, "version", VERSION)
	cfg.set_value(META_SECTION, "saved_at", Time.get_datetime_string_from_system())
	for track_key in _cache:
		cfg.set_value(RECORDS_SECTION, String(track_key), _cache[track_key])
	for section in _foreign:
		for key in (_foreign[section] as Dictionary):
			cfg.set_value(section, key, (_foreign[section] as Dictionary)[key])
	var tmp := _path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		return false
	var dir := DirAccess.open(_path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(_path):
		dir.remove(_path.get_file())
	if dir.rename(tmp.get_file(), _path.get_file()) != OK:
		return false
	_corrupt = false
	return true


## 测试用：删掉记录文件并清缓存。
static func delete_file() -> void:
	for suffix in ["", ".tmp"]:
		var target: String = _path + String(suffix)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	_loaded = false
	_cache = {}
	_foreign = {}
	_corrupt = false


# --- 格式化 -------------------------------------------------------------------

## 123456 -> "02:03.4"；不足一分钟也给 "00:07.2"。
static func format_ms(ms: int) -> String:
	var safe := maxi(0, ms)
	var total_tenths := int(round(float(safe) / 100.0))
	var minutes := total_tenths / 600
	var seconds := (total_tenths / 10) % 60
	var tenths := total_tenths % 10
	return "%02d:%02d.%d" % [minutes, seconds, tenths]


static func format_rank(rank: StringName) -> String:
	return String(rank)


static func rank_label(rank: StringName) -> String:
	return "评 级  %s" % String(rank) if rank != &"" else ""
