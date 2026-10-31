extends Node
## 余烬印记：炉厅记得你来过（标题屏的私人记录层）。
##
## 每次真正踏入旅程（新开 / 继续之旅 / 回看后再入）记一次「点燃 visit」；
## 每次倒下（GameEvents.player_died）记一次「殁 death」。标题屏据此画出：
##   · 字标外的「印记环」（title_sigil_ring.gd）——每次点燃是一枚刻度，
##     新的还亮着，旧的随真实时间冷却；
##   · 轮换墓志里的私人句子（"炉厅记得 · 你已点燃 N 次"）；
##   · 档案卡「旅程」里的印记行。
##
## 记录**独立于存档**：删档不会擦掉炉厅的记忆——这正是设计。存档是这一世，
## 印记是每一世。数据落在 user://rustgrave_sigils.cfg，与存档文件分开。
##
## 自动化（headless 套件 / 工具）不写生产记录：record_visit / record_death 在
## headless 下是空操作；测试走 append_raw + store_path 重定向。

## 一「天」的秒数：印记的时间单位是真实的日子。
const DAY := 86400.0
## 容量上限：环上最多 64 枚（多了只保留最近的），死亡记录 64 条。
const MAX_VISITS := 96
const MAX_DEATHS := 64
const RING_TICKS := 64
const DEFAULT_STORE := "user://rustgrave_sigils.cfg"

## 测试 / 工具可以重定向；生产永远走用户目录。
var store_path := DEFAULT_STORE
## 生产记录的闸门（保留给需要静音真实写入的场合）。
var recording_enabled := true

var visits: Array[Dictionary] = []
var deaths: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 玩家倒下时记一笔「殁」。标题屏不在场也要记——炉厅一直醒着。
	GameEvents.player_died.connect(_on_player_died)
	load_store()


## 记一次「点燃」。kind: "new"（新旅程）| "continue"（继续 / 再入）。
## level_id 是落点章节（GameContext 的关卡 id）；认不出就空串。
func record_visit(kind: String, level_id: String = "") -> Dictionary:
	if not _production_ok():
		return {}
	return append_raw(today(), kind, level_id)


func _on_player_died() -> void:
	if not _production_ok():
		return
	append_raw(today(), "death", _current_level_id())


## 直接写入（测试 / 工具用）。day 是以「天」为单位的整数时间戳（today()）。
func append_raw(day: int, kind: String, level_id: String = "") -> Dictionary:
	var rec := {"d": maxi(day, 0), "k": String(kind), "c": String(level_id)}
	if kind == "death":
		deaths.append(rec)
		while deaths.size() > MAX_DEATHS:
			deaths.pop_front()
	else:
		visits.append(rec)
		while visits.size() > MAX_VISITS:
			visits.pop_front()
	save_store()
	return rec


func clear() -> void:
	visits.clear()
	deaths.clear()
	save_store()


func visit_count() -> int:
	return visits.size()


func last_visit() -> Dictionary:
	return visits.back() if not visits.is_empty() else {}


func last_death() -> Dictionary:
	return deaths.back() if not deaths.is_empty() else {}


## 「现在」的整数天戳（静态给工具 / 测试对表用）。
static func today() -> int:
	return int(floor(Time.get_unix_time_from_system() / DAY))


## 天差 → 人话：今天 / 昨天 / N 天前 / N 个月前。
static func ago_text(days: int) -> String:
	if days <= 0:
		return "今天"
	if days == 1:
		return "昨天"
	if days < 30:
		return "%d 天前" % days
	return "%d 个月前" % maxi(1, days / 30)


func load_store() -> void:
	visits.clear()
	deaths.clear()
	var cfg := ConfigFile.new()
	if cfg.load(store_path) != OK:
		return
	for v in cfg.get_value("sigils", "visits", []):
		if v is Dictionary:
			visits.append(v)
	for d in cfg.get_value("sigils", "deaths", []):
		if d is Dictionary:
			deaths.append(d)


func save_store() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sigils", "visits", visits)
	cfg.set_value("sigils", "deaths", deaths)
	cfg.save(store_path)


func _production_ok() -> bool:
	return recording_enabled and DisplayServer.get_name() != "headless"


## 死亡那一刻在哪个章节：当前场景文件反查关卡 id（主线 + 遗留表都认）。
func _current_level_id() -> String:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	var path := String(tree.current_scene.scene_file_path)
	for id in GameContext.LEVELS:
		if String(GameContext.LEVELS[id]) == path:
			return String(id)
	for id in GameContext.LEGACY_LEVELS:
		if String(GameContext.LEGACY_LEVELS[id]) == path:
			return String(id)
	return ""


## 关卡 id → 短章名（墓志 / 档案 / 印记环悬停共用）。认不出给空串，由调用方兜底。
static func chapter_label_of(level_id: String) -> String:
	if level_id.is_empty():
		return ""
	if ChapterText.has(level_id):
		return ChapterText.name_of(level_id)
	if ChapterText.LEGACY_CHAPTERS.has(level_id):
		return String(ChapterText.LEGACY_CHAPTERS[level_id].get("name", ""))
	return ""
