class_name RuneCatalog
extends RefCounted
## 皮肤刻印：每套皮肤一个可选刻印槽，只给很小的数值/机制补强。
##
## 刻印通过 CharacterStats.add_modifier(&"skin_rune", modifier, 0.0) 常驻生效；
## 换肤/换刻印时先 remove_modifier 再重新挂，不会叠加。
## 解锁 id 与 EmberRank 的 rank 奖励对齐（4/7/10 阶）。

const SLOT_ID := &"skin_rune"

const RUNES := {
	&"rune_ember_grip": {
		"name": "余烬握柄",
		"desc": "弹反后的余温留在手心：防御 +1。",
		"modifier": {"defense": 1},
		"unlock": "rune_ember_grip",
	},
	&"rune_toxin_filter": {
		"name": "滤毒刻印",
		"desc": "皮肤下层的滤网：毒素抗性 +8%。",
		"modifier": {"toxin_resist": 0.08},
		"unlock": "rune_toxin_filter",
	},
	&"rune_unbroken": {
		"name": "不折之刻",
		"desc": "刻在骨上的最后一笔：生命上限 +1、防御 +1。",
		"modifier": {"max_hp": 1, "defense": 1},
		"unlock": "rune_unbroken",
	},
	&"rune_swift": {
		"name": "轻步刻印",
		"desc": "鞋底像少了一层灰：移动速度 +4%。",
		"modifier": {"speed_mult": 0.04},
		"unlock": "",
	},
}


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in RUNES:
		out.append(StringName(id))
	return out


static func has(id: StringName) -> bool:
	return RUNES.has(id)


static func def(id: StringName) -> Dictionary:
	if RUNES.has(id):
		return RUNES[id]
	return {}


static func name_of(id: StringName) -> String:
	return String(def(id).get("name", ""))


static func desc_of(id: StringName) -> String:
	return String(def(id).get("desc", ""))


## 刻印给 CharacterStats 的属性字典（无刻印返回空）。
static func modifier_of(id: StringName) -> Dictionary:
	var raw: Variant = def(id).get("modifier", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


static func line_of(id: StringName) -> String:
	if id == &"" or not has(id):
		return "无刻印"
	return "%s · %s" % [name_of(id), desc_of(id)]
