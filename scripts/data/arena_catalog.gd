extends Object
## 竞技场（垂直切片）：规则常量与记录文件路径。纯数据，不碰场景/存档。
##
## 这一版是"限时生存竞技"切片：单场 90 秒，敌人按波次刷出，击杀得分；
## 活到时间结束 = 胜，死亡 = 负。3v3 推线（兵线/塔/水晶）是后续目标，
## 见 docs/arena-mode.md 的路线图。

const SCENE := "res://scenes/levels/Arena_Duel.tscn"
const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const RECORDS_PATH := "user://rustgrave_arena.cfg"
const RECORDS_VERSION := 1

const DURATION := 90.0
const WAVE_INTERVAL := 6.0
const MAX_ALIVE := 4
const SPAWN_X := 560.0
const PLAYER_SPAWN := Vector2(120.0, 300.0)

## 每波随机敌人：kind 与得分。
const ENEMIES := [
	{"kind": "scrapper", "scene": "res://scenes/enemies/ScrapperEnemy.tscn", "score": 20},
	{"kind": "spitter", "scene": "res://scenes/enemies/SpitterEnemy.tscn", "score": 30},
	{"kind": "ghost", "scene": "res://scenes/enemies/GhostEnemy.tscn", "score": 35},
]

const KILL_SCORE_MULTIPLIER := 1.0


static func enemy_for_wave(index: int) -> Dictionary:
	if ENEMIES.is_empty():
		return {}
	return ENEMIES[posmod(index, ENEMIES.size())]


static func format_time(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


static func strip_text(score: int, kills: int, time_left: float) -> String:
	return "竞技场 · 剩余 %s · 击杀 %d · 得分 %d" % [
		format_time(time_left), kills, score]


static func result_summary(result: Dictionary) -> String:
	var win := bool(result.get("win", false))
	var score := int(result.get("score", 0))
	var kills := int(result.get("kills", 0))
	return "%s · 得分 %d · 击杀 %d" % ["胜" if win else "负", score, kills]
