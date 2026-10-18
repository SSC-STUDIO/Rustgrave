class_name EmberRank
extends RefCounted
## 余烬阶位：纯数据 + 纯函数，不碰存档、不发信号（EmberProgress 负责落档）。
##
## 阶位 1..10；XP 只增。第 N 阶的门槛是「累计 XP」：
##   rank 1 = 0，rank 2 = 120，…… rank 10 = 4760。
## 升一阶给 1 点可分配属性点（attribute_points）；具体加到哪项由角色面板决定。
## 解锁表是给 M4（皮肤/刻印）和 M3（主动技能）用的 id 占位：达到阶位时由
## EmberProgress 把 id 写进 profile.extras 的解锁列表。

const MAX_RANK := 10

## index = rank - 1，单位：累计 XP。
const TOTAL_XP: Array[int] = [0, 120, 300, 560, 920, 1400, 2020, 2760, 3660, 4760]

const RANK_NAMES: Array[String] = [
	"拾灰者", "燃薪者", "余烬侍从", "灰烬骑士", "炉心守卫",
	"铆钉行者", "炽骸领队", "熄灯者", "墓碑主宰", "余烬之王",
]

## XP 来源（集中在这里，方便调数值）。
const BOSS_XP := 90
const CHAPTER_XP := 30
const TRIAL_XP := 60
const ARENA_WIN_XP := 120
const ARENA_LOSS_XP := 30

## 阶位 → 解锁 id（皮肤 / 刻印 / 技能）。空 = 只给属性点。
const REWARDS := {
	2: [&"skin_ash_runner"],
	3: [&"skill_ember_burst"],
	4: [&"rune_ember_grip"],
	5: [&"skin_cemetery_hero"],
	6: [&"skill_hollow_guard"],
	7: [&"rune_toxin_filter"],
	8: [&"skin_gothic_hero"],
	9: [&"skill_rust_lance"],
	10: [&"rune_unbroken"],
}


static func clamp_rank(rank: int) -> int:
	return clampi(rank, 1, MAX_RANK)


## 达到某阶需要的累计 XP。
static func xp_for_rank(rank: int) -> int:
	return TOTAL_XP[clamp_rank(rank) - 1]


## 当前累计 XP 对应的阶位（1..MAX_RANK）。
static func rank_for_xp(xp: int) -> int:
	var total := maxi(0, xp)
	var rank := 1
	for i in TOTAL_XP.size():
		if total >= TOTAL_XP[i]:
			rank = i + 1
		else:
			break
	return clamp_rank(rank)


## 在当前阶位内已经积累的 XP（用于"3 阶 172/260"这类显示）。
static func xp_into_rank(xp: int) -> int:
	var total := maxi(0, xp)
	return total - xp_for_rank(rank_for_xp(total))


## 从当前阶位升到下一阶还差多少 XP；满阶返回 0。
static func xp_to_next(xp: int) -> int:
	var total := maxi(0, xp)
	var rank := rank_for_xp(total)
	if rank >= MAX_RANK:
		return 0
	return xp_for_next_rank(total)


static func xp_for_next_rank(xp: int) -> int:
	var total := maxi(0, xp)
	var rank := rank_for_xp(total)
	if rank >= MAX_RANK:
		return 0
	return xp_for_rank(rank + 1) - total


## 下一阶所需的总区间长度（当前阶内进度分母）。
static func rank_span(rank: int) -> int:
	var r := clamp_rank(rank)
	if r >= MAX_RANK:
		return 0
	return xp_for_rank(r + 1) - xp_for_rank(r)


## 0..1 的阶内进度；满阶恒为 1。
static func progress(xp: int) -> float:
	var rank := rank_for_xp(xp)
	if rank >= MAX_RANK:
		return 1.0
	var span := rank_span(rank)
	if span <= 0:
		return 1.0
	return clampf(float(xp_into_rank(xp)) / float(span), 0.0, 1.0)


## 达到 rank 时累计获得的属性点（rank 1 为 0）。
static func points_for_rank(rank: int) -> int:
	return clamp_rank(rank) - 1


static func name_for_rank(rank: int) -> String:
	return RANK_NAMES[clamp_rank(rank) - 1]


## 达到该rank新解锁的 id（rank 1 没有）。
static func rewards_for_rank(rank: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var raw: Variant = REWARDS.get(clamp_rank(rank), [])
	if raw is Array:
		for value in raw:
			out.append(StringName(value))
	return out


static func is_max_rank(rank: int) -> bool:
	return clamp_rank(rank) >= MAX_RANK


## 存档/UI 都用的单行摘要："3 阶 · 余烬侍从 · 172/260"。
static func summary(xp: int) -> String:
	var rank := rank_for_xp(xp)
	var name := name_for_rank(rank)
	if rank >= MAX_RANK:
		return "%d 阶 · %s · 已满" % [rank, name]
	return "%d 阶 · %s · %d/%d" % [rank, name, xp_into_rank(xp), rank_span(rank)]
