extends Object
## 可破坏道具的静态数据：外观（复用仓库现有废墟贴图）、材质、耐久、掉落的余烬。
##
## 道具不是"另一种可交互物"：它们是 StaticBody2D + Hurtbox，任何来源的伤害都能打；
## 轻击/重击的差别由 `blade_only` 决定（默认任何人都能砍碎，重击更快）。
## 只放在支路/角落：主线必经路径不允许只靠打碎道具通过。

const PROPS := {
	&"scrap_heap": {
		"name": "碎铁堆",
		"texture": "res://assets/env/rubble_a.png",
		"region": Rect2(0, 15, 27, 24),
		"size": Vector2(24, 20),
		"material": &"metal",
		"max_hp": 2,
		"heal": 1,
		"blade_only": false,
		"announce": "碎铁堆塌了，锈屑里滚出一粒余烬。",
	},
	&"rust_urn": {
		"name": "锈罐",
		"texture": "res://assets/env/rubble_b.png",
		"region": Rect2(0, 16, 27, 24),
		"size": Vector2(20, 18),
		"material": &"metal",
		"max_hp": 1,
		"heal": 1,
		"blade_only": false,
		"announce": "锈罐碎了，一星余烬飞了出来。",
	},
	&"bramble_knot": {
		"name": "腐藤结",
		"texture": "res://assets/env/moss_vine.png",
		"region": Rect2(0, 16, 16, 28),
		"size": Vector2(16, 26),
		"material": &"wet",
		"max_hp": 2,
		"heal": 1,
		"blade_only": false,
		"announce": "藤结断开，里面的余烬亮了一下。",
	},
}

const FALLBACK := &"scrap_heap"


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in PROPS:
		out.append(StringName(id))
	return out


static func has(prop_id: StringName) -> bool:
	return PROPS.has(prop_id)


static func def(prop_id: StringName) -> Dictionary:
	if PROPS.has(prop_id):
		return PROPS[prop_id]
	return PROPS[FALLBACK]


## 破坏后能否立刻开一条路：道具只是障碍，不是地形破坏；一律不写"必经点"。
static func feet_offset(size: Vector2) -> Vector2:
	return Vector2(-size.x * 0.5, -size.y)
