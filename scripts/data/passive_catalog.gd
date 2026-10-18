extends Object
## 流派被动目录：三个起源各一条被动。数据在这里，触发点在 Player。
##
## 设计口径：
##   · 被动是"起源的玩法差异"，只改很小的一处规则，不叠数值墙；
##   · 所有被动都必须能被测试稳定复现（不用随机数）；
##   · id 由 CharacterOrigin.passive_id 指向这里，OriginCatalog 是唯一注册处。

const PASSIVES := {
	&"passive_ember_bulwark": {
		"origin": &"ember_vanguard",
		"name": "余烬壁垒",
		"desc": "完美弹反后 2 秒内防御 +1。",
	},
	&"passive_scavenger_instinct": {
		"origin": &"scrap_scavenger",
		"name": "拾荒本能",
		"desc": "拾取锈核或装备时回复 1 点生命（20 秒冷却）。",
	},
	&"passive_filter_convert": {
		"origin": &"rust_automaton",
		"name": "滤毒转能",
		"desc": "毒素满溢的伤害每两次只结算一次，并排掉 10% 毒素。",
	},
}

const HEAL_COOLDOWN := 20.0
const BULWARK_SECONDS := 2.0
const FILTER_PURIFY := 0.10


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in PASSIVES:
		out.append(StringName(id))
	return out


static func has(id: StringName) -> bool:
	return PASSIVES.has(id)


static func def(id: StringName) -> Dictionary:
	if PASSIVES.has(id):
		return PASSIVES[id]
	return {}


## 某个起源的被动 id（未知起源返回 &""）。
static func for_origin(origin_id: StringName) -> StringName:
	for id in PASSIVES:
		if StringName(PASSIVES[id].get("origin", &"")) == origin_id:
			return StringName(id)
	return &""


static func name_of(id: StringName) -> String:
	return String(def(id).get("name", ""))


static func desc_of(id: StringName) -> String:
	return String(def(id).get("desc", ""))
