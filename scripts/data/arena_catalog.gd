extends Object
## 3v3 推线竞技场的纯数据：地图、单位、难度、波次、商店、记录 v2。
## 不碰场景、不写存档。运行时见 ArenaRun，规则说明见 docs/arena-mode.md。

const SCENE := "res://scenes/levels/Arena_Duel.tscn"
const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const RECORDS_PATH := "user://rustgrave_arena.cfg"
const RECORDS_VERSION := 2

const PHASE_IDLE := "idle"
const PHASE_LOBBY := "lobby"
const PHASE_COUNTDOWN := "countdown"
const PHASE_PLAYING := "playing"
const PHASE_RESULT := "result"

const TEAM_PLAYER := "player"
const TEAM_ENEMY := "enemy"
const TEAM_NEUTRAL := "neutral"

const DIFF_APPRENTICE := "apprentice"
const DIFF_VETERAN := "veteran"
const DIFF_FORGE := "forge"
const DEFAULT_DIFFICULTY := DIFF_VETERAN
const DIFFICULTY_ORDER: Array[String] = [DIFF_APPRENTICE, DIFF_VETERAN, DIFF_FORGE]

## 12 分钟。DURATION 保留旧名字，给 time_left() 的空闲默认值用。
const MATCH_SECONDS := 720.0
const DURATION := MATCH_SECONDS
const COUNTDOWN_SECONDS := 3.0
const FIRST_WAVE_DELAY := 1.0
const WAVE_INTERVAL := 30.0
## 每波小兵在上一波基础上 +6% 生命和伤害，封顶 +72%（第 13 波）。
const WAVE_GROWTH := 0.06
const WAVE_GROWTH_CAP := 1.72
## 6 分钟后炉火躁动：小兵出手变快，已暴露的塔每 UNREST_STEP 秒掉 1 点血。
const UNREST_AT := 360.0
const UNREST_STEP := 3.5
const UNREST_CD := 0.78
## 己方小兵贴到敌塔、英雄血量还安全时，优先压塔而不是在中路对耗。
const SIEGE_PUSH_RANGE := 220.0
const SIEGE_SAFE_HP := 0.5
const ASSIST_WINDOW := 8.0
const ELITE_RESPAWN := 45.0
const BLESSING_TIME := 12.0
const BLESSING_DAMAGE := 1.3
const MAX_LEVEL := 6
const RESPAWN_BASE := 5.0
const RESPAWN_PER_LEVEL := 1.25
const RETREAT_HP := 0.34
const RETREAT_DONE := 0.85
const FOUNTAIN_RADIUS := 78.0
const FOUNTAIN_HEAL := 4.0
const MINION_CAP := 8

## 单条平路。祭台只画不挡：丘顶比地面高 44px，跳跃约 36px，上不去；
## 实体坡会在接缝把全队卡住。精英站在祭台旁的地面上，走近才交手。
const LANE_LEFT := 0.0
const LANE_RIGHT := 3840.0
const LANE_LENGTH := 3840.0
const GROUND_Y := 312.0
const ALTAR_Y := 292.0
const VIEW_H := 360.0

## 纵深带：脚底 y，小的更远（更靠画面上方）。和跳跃高度 z 分开。
## 宽 76px，落在要求的 60–80 里。GROUND_Y 仍是参照线，也在带内（偏前）。
const DEPTH_BACK := 252.0
const DEPTH_FRONT := 328.0
const DEPTH_MID := 290.0
const DEPTH_SPEED := 74.0
const JUMP_Z := 176.0
const JUMP_Z_GRAVITY := 460.0
const JUMP_Z_MAX := 34.0
const TOL_MELEE := 16.0
const TOL_BOLT := 30.0
const DEPTH_LANES: Array[float] = [262.0, 290.0, 318.0]

const BLUE_FOUNTAIN := Vector2(150, 312)
const BLUE_CRYSTAL := Vector2(460, 312)
const BLUE_INNER := Vector2(900, 312)
const BLUE_OUTER := Vector2(1280, 312)
const RED_OUTER := Vector2(2560, 312)
const RED_INNER := Vector2(2940, 312)
const RED_CRYSTAL := Vector2(3380, 312)
const RED_FOUNTAIN := Vector2(3690, 312)
const ELITE_POS := Vector2(1920, GROUND_Y)
const ELITE_AGGRO := 110.0
const BLUE_MINION_X := 540.0
const RED_MINION_X := 3300.0
const PLAYER_SPAWN := Vector2(300, 312)
const ALTAR_RECT := Rect2(1760, 268, 320, 44)

const HERO_HP: Array[int] = [10, 12, 14, 17, 20, 24]
const HERO_DMG: Array[int] = [1, 1, 2, 2, 3, 3]
const XP_STEP: Array[int] = [24, 40, 58, 78, 100]

const TEAM_TINT := {
	"player": Color(0.62, 0.78, 1.25, 1),
	"enemy": Color(1.22, 0.62, 0.56, 1),
	"neutral": Color(1.15, 0.96, 0.62, 1),
}

const DIFFICULTIES := {
	"apprentice": {
		"id": "apprentice",
		"label": "见习",
		"damage_mul": 0.55,
		"minion_hp_mul": 0.6,
		"minion_dmg_mul": 0.8,
		"respawn_mul": 0.6,
		"cooldown_mul": 1.4,
		"react": 0.42,
		"think": 0.38,
	},
	"veteran": {
		"id": "veteran",
		"label": "老练",
		"damage_mul": 1.0,
		"minion_hp_mul": 1.0,
		"minion_dmg_mul": 1.0,
		"respawn_mul": 1.0,
		"cooldown_mul": 1.0,
		"react": 0.2,
		"think": 0.22,
	},
	"forge": {
		"id": "forge",
		"label": "炉火",
		"damage_mul": 1.35,
		"minion_hp_mul": 1.5,
		"minion_dmg_mul": 1.2,
		"respawn_mul": 1.45,
		"cooldown_mul": 0.7,
		"react": 0.08,
		"think": 0.12,
	},
}

## 跟战役同一档的整数：英雄 1 级一刀 1，塔 2。血量按「赢下兵线的 2 名英雄带兵」估算，
## 外塔大约 70 秒后倒，水晶大约 3 分钟，不会 30 秒推完；两边对耗则打满 12 分钟。
const UNIT_STATS := {
	"melee": {"hp": 6, "dmg": 1, "speed": 46.0, "range": 22.0, "cd": 0.9, "xp": 8, "ember": 5, "sight": 120.0, "siege": 0},
	"ranged": {"hp": 4, "dmg": 1, "speed": 40.0, "range": 148.0, "cd": 1.35, "xp": 8, "ember": 5, "sight": 180.0, "siege": 0},
	"siege": {"hp": 12, "dmg": 1, "speed": 32.0, "range": 28.0, "cd": 1.15, "xp": 14, "ember": 8, "sight": 140.0, "siege": 8},
	"hero": {"hp": 10, "dmg": 1, "speed": 78.0, "range": 32.0, "cd": 0.62, "xp": 28, "ember": 16, "sight": 150.0, "siege": 0},
	"tower": {"hp": 64, "dmg": 2, "speed": 0.0, "range": 176.0, "cd": 1.25, "xp": 18, "ember": 10, "sight": 176.0, "siege": 0},
	"crystal": {"hp": 84, "dmg": 1, "speed": 0.0, "range": 136.0, "cd": 1.4, "xp": 0, "ember": 0, "sight": 136.0, "siege": 0},
	"elite": {"hp": 18, "dmg": 2, "speed": 0.0, "range": 42.0, "cd": 0.95, "xp": 36, "ember": 20, "sight": 110.0, "siege": 0},
}

const MINION_VISUAL := {
	"melee": {"char": "skeleton", "action": "walk", "fps": 10.0, "pos": Vector2(0, -26), "scale": 1.0},
	"ranged": {"char": "fire_skull", "action": "fly", "fps": 10.0, "pos": Vector2(2, -8), "scale": 0.42},
	"siege": {"char": "scrapper_hell_hound", "action": "walk", "fps": 10.0, "pos": Vector2(0, -16), "scale": 1.0},
}

const HERO_ROSTER := [
	{"id": "ally_0", "team": "player", "label": "灰卫·灯", "skin": "skin_ash_runner", "ranged": false, "slot": 0, "pos": Vector2(220, 312)},
	{"id": "ally_1", "team": "player", "label": "灰卫·钟", "skin": "skin_cemetery_hero", "ranged": true, "slot": 1, "pos": Vector2(360, 312)},
	{"id": "enemy_0", "team": "enemy", "label": "锈誓·刃", "skin": "skin_fantasy_knight", "ranged": false, "slot": 0, "pos": Vector2(3580, 312)},
	{"id": "enemy_1", "team": "enemy", "label": "锈誓·颅", "skin": "skin_gothic_hero", "ranged": true, "slot": 1, "pos": Vector2(3660, 312)},
	{"id": "enemy_2", "team": "enemy", "label": "锈誓·砧", "skin": "skin_cemetery_hero", "ranged": false, "slot": 2, "pos": Vector2(3740, 312)},
]

const SHOP := [
	{"id": "edge", "label": "锋刃", "cost": 18, "attack": 1, "hp": 0, "speed": 0.0},
	{"id": "plate", "label": "炉甲", "cost": 18, "attack": 0, "hp": 3, "speed": 0.0},
	{"id": "haste", "label": "疾步", "cost": 12, "attack": 0, "hp": 0, "speed": 16.0},
]


static func hostile(a: String, b: String) -> bool:
	return a != "" and b != "" and a != b


static func difficulty_def(id: String) -> Dictionary:
	if DIFFICULTIES.has(id):
		var raw: Dictionary = DIFFICULTIES[id]
		return raw.duplicate(true)
	var fallback: Dictionary = DIFFICULTIES[DEFAULT_DIFFICULTY]
	return fallback.duplicate(true)


static func difficulty_label(id: String) -> String:
	var row := difficulty_def(id)
	return String(row.get("label", "老练"))


## 1 点伤害乘难度后通常仍是 1。塔从 2 点拉开成 1/2/3；英雄和小兵靠 cooldown_mul 拉开手速。
static func scaled_damage(base_damage: int, kind: String, difficulty_id: String) -> int:
	var diff := difficulty_def(difficulty_id)
	var mul := float(diff.get("damage_mul", 1.0))
	if kind == "minion":
		mul *= float(diff.get("minion_dmg_mul", 1.0))
	return maxi(1, int(round(float(maxi(0, base_damage)) * mul)))


static func scaled_max_hp(base_hp: int, kind: String, difficulty_id: String) -> int:
	if kind != "minion":
		return maxi(1, base_hp)
	var diff := difficulty_def(difficulty_id)
	var mul := float(diff.get("minion_hp_mul", 1.0))
	return maxi(1, int(round(float(maxi(1, base_hp)) * mul)))


static func cooldown_scale(kind: String, difficulty_id: String) -> float:
	if kind != "hero" and kind != "minion" and kind != "elite":
		return 1.0
	var diff := difficulty_def(difficulty_id)
	return maxf(0.25, float(diff.get("cooldown_mul", 1.0)))


static func unit_stat(role: String) -> Dictionary:
	if UNIT_STATS.has(role):
		var raw: Dictionary = UNIT_STATS[role]
		return raw.duplicate(true)
	return {}


static func shop_item(id: String) -> Dictionary:
	for raw in SHOP:
		if raw is Dictionary:
			var row: Dictionary = raw
			if String(row.get("id", "")) == id:
				return row.duplicate(true)
	return {}


static func hero_hp(level: int) -> int:
	var lv := clampi(level, 1, MAX_LEVEL)
	return int(HERO_HP[lv - 1])


static func hero_damage(level: int) -> int:
	var lv := clampi(level, 1, MAX_LEVEL)
	return int(HERO_DMG[lv - 1])


static func xp_needed(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	var lv := clampi(level, 1, MAX_LEVEL - 1)
	return int(XP_STEP[lv - 1])


static func respawn_seconds(level: int, difficulty_id: String) -> float:
	var diff := difficulty_def(difficulty_id)
	var mul := float(diff.get("respawn_mul", 1.0))
	var lv := clampi(level, 1, MAX_LEVEL)
	return (RESPAWN_BASE + float(lv - 1) * RESPAWN_PER_LEVEL) * mul


## 无头模拟用。-1 表示正式对局，兵线槽位不抖动。
static var match_seed := -1


static func set_match_seed(value: int) -> void:
	match_seed = value


static func wave_power(index: int) -> float:
	var steps := maxi(0, index - 1)
	return minf(WAVE_GROWTH_CAP, 1.0 + WAVE_GROWTH * float(steps))


## 正式对局三股兵线按槽位对齐。模拟种子只把每波第二只小兵错开一股，避免左右完全镜像。
static func lane_slot(slot: int, wave_index: int, side: int) -> int:
	var base := posmod(slot, 3)
	if match_seed < 0 or slot != 1:
		return base
	var nudge := 1
	if posmod(match_seed + wave_index + side, 2) == 0:
		nudge = 2
	return posmod(base + nudge, 3)


static func wave_kinds(index: int) -> PackedStringArray:
	var kinds := PackedStringArray()
	kinds.append("melee")
	kinds.append("melee")
	kinds.append("ranged")
	if index > 0 and index % 3 == 0:
		kinds.append("siege")
	return kinds


static func structure_anchor(team: String, index: int) -> Vector2:
	if team == TEAM_ENEMY:
		if index <= 0:
			return RED_OUTER
		if index == 1:
			return RED_INNER
		return RED_CRYSTAL
	if index <= 0:
		return BLUE_OUTER
	if index == 1:
		return BLUE_INNER
	return BLUE_CRYSTAL


static func structure_kind(index: int) -> String:
	if index <= 0:
		return "outer"
	if index == 1:
		return "inner"
	return "crystal"


static func structure_label(index: int) -> String:
	if index <= 0:
		return "外塔"
	if index == 1:
		return "内塔"
	return "水晶"


static func fountain_for(team: String) -> Vector2:
	if team == TEAM_ENEMY:
		return RED_FOUNTAIN
	return BLUE_FOUNTAIN


static func surface_y(_x: float) -> float:
	return GROUND_Y


static func depth_span() -> float:
	return DEPTH_FRONT - DEPTH_BACK


static func clamp_depth(feet_y: float) -> float:
	return clampf(feet_y, DEPTH_BACK, DEPTH_FRONT)


static func in_depth(feet_y: float) -> bool:
	return feet_y >= DEPTH_BACK - 0.01 and feet_y <= DEPTH_FRONT + 0.01


static func lane_y(slot: int) -> float:
	var n := DEPTH_LANES.size()
	if n <= 0:
		return DEPTH_MID
	var i := slot % n
	if i < 0:
		i += n
	return float(DEPTH_LANES[i])


static func hit_tolerance(kind: String) -> float:
	if kind == "bolt" or kind == "tower":
		return TOL_BOLT
	return TOL_MELEE


static func node_depth(node: Node) -> float:
	var cursor: Node = node
	while cursor != null:
		if cursor.has_method(&"arena_depth"):
			return float(cursor.call(&"arena_depth"))
		cursor = cursor.get_parent()
	if node is Node2D:
		return (node as Node2D).global_position.y
	return DEPTH_MID


static func node_spans_depth(node: Node) -> bool:
	var cursor: Node = node
	while cursor != null:
		if cursor.has_method(&"arena_spans_depth"):
			return bool(cursor.call(&"arena_spans_depth"))
		cursor = cursor.get_parent()
	return false


static func attack_kind(node: Node) -> String:
	var cursor: Node = node
	while cursor != null:
		if cursor.is_in_group("arena_bolt"):
			return "bolt"
		cursor = cursor.get_parent()
	return "melee"


## 塔和水晶横跨整条带，任何深度都能打到。其余目标要脚底深度差不超过容差。
static func depths_touch(attacker: Node, target: Node, kind: String = "") -> bool:
	if target != null and node_spans_depth(target):
		return true
	if attacker != null and node_spans_depth(attacker):
		return true
	var use := kind
	if use == "":
		use = attack_kind(attacker)
	return absf(node_depth(attacker) - node_depth(target)) <= hit_tolerance(use)


## 带内只比横向距离：泉水算一整条纵深上的基地，不因站得远近而走出治疗圈。
## 带外仍用旧的圆，单元测试里脚不在带上时行为和以前一样。
static func near_fountain(point: Vector2, well: Vector2) -> bool:
	if in_depth(point.y):
		return absf(point.x - well.x) <= FOUNTAIN_RADIUS
	return point.distance_to(well) <= FOUNTAIN_RADIUS


## 跳得越高，椭圆越小越淡。z = 0 时 rx 11 / alpha 0.5。
static func shadow_metrics(height: float) -> Dictionary:
	var k := clampf(height / JUMP_Z_MAX, 0.0, 1.0)
	return {
		"rx": lerpf(11.0, 5.0, k),
		"ry": lerpf(4.0, 2.0, k),
		"alpha": lerpf(0.5, 0.1, k),
	}


## 脚底 y 小的画在后面。场景靠父节点 y_sort_enabled，单位 z_index 必须相同。
static func ysort_behind(back_feet: float, front_feet: float) -> bool:
	return back_feet < front_feet


## 外塔始终可打；内塔要外塔倒了；水晶要两座塔都倒了。已毁的不再受伤。
static func exposed(index: int, outer_alive: bool, inner_alive: bool, self_alive: bool) -> bool:
	if not self_alive:
		return false
	if index <= 0:
		return true
	if index == 1:
		return not outer_alive
	return (not outer_alive) and (not inner_alive)


static func timeout_outcome(blue_towers: int, red_towers: int, blue_kills: int, red_kills: int) -> String:
	if blue_towers != red_towers:
		if blue_towers > red_towers:
			return "win"
		return "loss"
	if blue_kills != red_kills:
		if blue_kills > red_kills:
			return "win"
		return "loss"
	return "draw"


static func empty_records() -> Dictionary:
	return {
		"version": RECORDS_VERSION,
		"best_score": 0,
		"best_kills": 0,
		"runs": 0,
		"wins": 0,
		"losses": 0,
		"draws": 0,
		"fastest_win": 0.0,
	}


## v1 只有 best_score / best_kills / runs。缺的键补 0，已有的不改。
static func migrate_records(raw: Dictionary) -> Dictionary:
	var out := empty_records()
	out["best_score"] = int(raw.get("best_score", 0))
	out["best_kills"] = int(raw.get("best_kills", 0))
	out["runs"] = int(raw.get("runs", 0))
	out["wins"] = int(raw.get("wins", 0))
	out["losses"] = int(raw.get("losses", 0))
	out["draws"] = int(raw.get("draws", 0))
	out["fastest_win"] = float(raw.get("fastest_win", 0.0))
	out["version"] = RECORDS_VERSION
	return out


static func format_time(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


static func strip_text(score: int, kills: int, time_left: float) -> String:
	return "灰卫 · 击杀 %d · 得分 %d · %s" % [kills, score, format_time(time_left)]


static func result_summary(result: Dictionary) -> String:
	var outcome := String(result.get("outcome", ""))
	var word := "负"
	if outcome == "win" or bool(result.get("win", false)):
		word = "胜"
	if outcome == "draw" or bool(result.get("draw", false)):
		word = "平"
	var elapsed := float(result.get("elapsed", result.get("duration", 0.0)))
	return "%s · %s · 击杀 %d" % [word, format_time(elapsed), int(result.get("kills", 0))]
