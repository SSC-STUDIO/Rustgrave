extends Object
## 主动技能目录：两个技能槽（Q / E）共用的静态数据。
##
## 只描述"是什么"和"冷却多久"；实际效果在 Player.cast_skill 里按 effect 分发。
## 技能 id 与 EmberRank 解锁表对应（3 阶 ember_burst、6 阶 hollow_guard、9 阶 rust_lance）。

const SKILLS := {
	&"ember_burst": {
		"name": "余烬冲击",
		"desc": "向前喷出一团余烬，造成 2 点伤害并击退。",
		"cooldown": 6.0,
		"effect": &"burst",
		"unlock_rank": 3,
	},
	&"hollow_guard": {
		"name": "炉心格挡",
		"desc": "2 秒内防御 +2、毒素抗性 +40%。",
		"cooldown": 10.0,
		"effect": &"guard",
		"unlock_rank": 6,
	},
	&"rust_lance": {
		"name": "锈枪突进",
		"desc": "向前突进一段距离，撞到的敌人受 1 点伤害。",
		"cooldown": 8.0,
		"effect": &"lance",
		"unlock_rank": 9,
	},
	&"toxin_purge": {
		"name": "滤毒净化",
		"desc": "排掉一半毒素并回复 1 点生命。",
		"cooldown": 12.0,
		"effect": &"purge",
		"unlock_rank": 999,
	},
}

## 新档默认技能：槽 1 给余烬冲击，槽 2 空。以后由角色选择/装备面板覆盖。
const DEFAULT_SLOT_1 := &"ember_burst"
const DEFAULT_SLOT_2 := &""
const SLOT_COUNT := 2
const INPUT_ACTIONS: Array[StringName] = [&"skill_1", &"skill_2"]


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in SKILLS:
		out.append(StringName(id))
	return out


static func has(id: StringName) -> bool:
	return SKILLS.has(id)


static func def(id: StringName) -> Dictionary:
	if SKILLS.has(id):
		return SKILLS[id]
	return {}


static func name_of(id: StringName) -> String:
	return String(def(id).get("name", ""))


static func desc_of(id: StringName) -> String:
	return String(def(id).get("desc", ""))


static func cooldown_of(id: StringName) -> float:
	return float(def(id).get("cooldown", 0.0))


static func effect_of(id: StringName) -> StringName:
	return StringName(def(id).get("effect", &""))


static func input_action(slot: int) -> StringName:
	return INPUT_ACTIONS[clampi(slot, 0, SLOT_COUNT - 1)]
