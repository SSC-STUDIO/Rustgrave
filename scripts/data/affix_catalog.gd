class_name AffixCatalog
extends RefCounted
## 装备词缀：纯数据 + 确定性生成（同一个装备 id 永远得到同一套词缀）。
##
## 稀有度决定词缀条数：common 0 / rare 1 / epic 2。
## 词缀值是"词缀等级"（rare/epic 两档），不叠加随机数——掉落 id 里带基座与稀有度，
## 存档只存 id，读档时 for_id() 重新生成，永远一致，不需要额外存档字段。

const RARITY_COMMON := &"common"
const RARITY_RARE := &"rare"
const RARITY_EPIC := &"epic"
const RARITIES: Array[StringName] = [RARITY_COMMON, RARITY_RARE, RARITY_EPIC]
const RARITY_NAMES := {
	RARITY_COMMON: "普通",
	RARITY_RARE: "稀有",
	RARITY_EPIC: "史诗",
}
const RARITY_AFFIX_COUNT := {
	RARITY_COMMON: 0,
	RARITY_RARE: 1,
	RARITY_EPIC: 2,
}

## stat = CharacterStats / EquipmentItem 都能读的键（和 recalculate 的提取口径一致）。
const AFFIXES := {
	&"sharp": {
		"name": "锋锐",
		"stat": &"attack",
		"values": {RARITY_RARE: 1, RARITY_EPIC: 2},
		"template": "攻击 +%s",
	},
	&"sturdy": {
		"name": "坚壁",
		"stat": &"defense",
		"values": {RARITY_RARE: 1, RARITY_EPIC: 1},
		"template": "防御 +%s",
	},
	&"vital": {
		"name": "余烬生命",
		"stat": &"max_hp",
		"values": {RARITY_RARE: 1, RARITY_EPIC: 2},
		"template": "生命上限 +%s",
	},
	&"filtered": {
		"name": "滤毒",
		"stat": &"toxin_resist",
		"values": {RARITY_RARE: 0.05, RARITY_EPIC: 0.10},
		"template": "毒素抗性 +%s%%",
	},
	&"emberward": {
		"name": "余烬护佑",
		"stat": &"toxin_decay",
		"values": {RARITY_RARE: 0.10, RARITY_EPIC: 0.20},
		"template": "毒素消解 +%s/s",
	},
	&"swift": {
		"name": "轻步",
		"stat": &"speed_mult",
		"values": {RARITY_RARE: 0.03, RARITY_EPIC: 0.06},
		"template": "移动速度 +%s%%",
	},
}


static func is_rarity(rarity: StringName) -> bool:
	return RARITIES.has(rarity)


static func rarity_name(rarity: StringName) -> String:
	return String(RARITY_NAMES.get(rarity, RARITY_NAMES[RARITY_COMMON]))


static func affix_count(rarity: StringName) -> int:
	return int(RARITY_AFFIX_COUNT.get(rarity, 0))


## 确定性词缀：同一个 (base_id, rarity) 永远同一套。
static func affixes_for(base_id: StringName, rarity: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := affix_count(rarity)
	if count <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(base_id)) ^ hash(String(rarity)) * 2654435761
	var pool: Array[StringName] = []
	for id in AFFIXES:
		pool.append(StringName(id))
	# 洗牌后取前 count 个（同 id 稳定）。
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i in count:
		var id := pool[i]
		var def: Dictionary = AFFIXES[id]
		var values: Dictionary = def["values"]
		var value: Variant = values.get(rarity, values[RARITY_RARE])
		out.append({
			"id": id,
			"name": String(def["name"]),
			"stat": StringName(def["stat"]),
			"value": value,
		})
	return out


## 把一组词缀聚合成 CharacterStats 能吃的属性字典。
static func total(affixes: Array) -> Dictionary:
	var out := {
		"attack": 0,
		"defense": 0,
		"max_hp": 0,
		"toxin_resist": 0.0,
		"toxin_decay": 0.0,
		"speed_mult": 0.0,
	}
	for affix in affixes:
		if not (affix is Dictionary):
			continue
		var stat := StringName((affix as Dictionary).get("stat", &""))
		if not out.has(stat):
			continue
		var value: Variant = (affix as Dictionary).get("value", 0)
		if out[stat] is float:
			out[stat] = float(out[stat]) + float(value)
		else:
			out[stat] = int(out[stat]) + int(value)
	return out


## 单条词缀的显示文案（如 "锋锐 · 攻击 +1"）。
static func line_for(affix: Dictionary) -> String:
	var id := StringName(affix.get("id", &""))
	var def: Dictionary = AFFIXES.get(id, {})
	var template := String(def.get("template", ""))
	var value: Variant = affix.get("value", 0)
	var shown := ""
	if value is int or value is float:
		var f := float(value)
		if is_zero_approx(f - roundf(f)):
			shown = str(int(roundf(f)))
		else:
			shown = "%.2f" % (f * 100.0)
	return "%s · %s" % [String(affix.get("name", "")), template % shown]


## 一套词缀的完整显示行。
static func lines_for(affixes: Array) -> Array[String]:
	var out: Array[String] = []
	for affix in affixes:
		if affix is Dictionary:
			out.append(line_for(affix))
	return out
