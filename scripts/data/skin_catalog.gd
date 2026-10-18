class_name SkinCatalog
extends RefCounted
## 玩家外观（皮肤）：复用仓库里三套玩家帧素材，按"逻辑动作 → 素材动作/帧段"映射，
## 缺动作时回退到默认骑士素材，保证任何关卡动作都不缺帧。
##
## 画布几何：帧是 centered Sprite，pos = (canvas_w/2 - 身体中心x, canvas_h/2 - 不透明底边y)，
## 这样脚底落在节点原点、身体对准碰撞体中轴（数值由 tools 里量像素得出，见每套的 offset）。

const DEFAULT_SKIN := &"skin_fantasy_knight"

## 逻辑动作 → [素材动作, 起始帧, 结束帧(-1 = 到末尾)]。
## 三套素材动作集不同，这里把它们统一到骑士的 11 个动作。
const LOGICAL_ACTIONS: Array[StringName] = [
	&"idle", &"run", &"jump", &"fall", &"dash", &"hurt",
	&"death", &"turn", &"attack1", &"attack2", &"attack_combo",
]

const SKINS := {
	&"skin_fantasy_knight": {
		"name": "余烬骑士",
		"desc": "锈墓里醒来的骑士，残甲与巨剑一起烧着。",
		"folder": "player_fantasy_knight",
		"tint": Color.WHITE,
		"offset": Vector2(6.0, -40.0),
		"origin": &"ember_vanguard",
		"unlock": "start",
		"actions": {
			&"idle": ["idle", 0, -1], &"run": ["run", 0, -1],
			&"jump": ["jump", 0, -1], &"fall": ["fall", 0, -1],
			&"dash": ["dash", 0, -1], &"hurt": ["hurt", 0, -1],
			&"death": ["death", 0, -1], &"turn": ["turn", 0, -1],
			&"attack1": ["attack1", 0, -1], &"attack2": ["attack2", 0, -1],
			&"attack_combo": ["attack_combo", 0, -1],
		},
	},
	&"skin_ash_runner": {
		"name": "灰行客",
		"desc": "在灰烬里跑得比火还快，一身冷灰的拾荒者装束。",
		"folder": "player_fantasy_knight",
		"tint": Color(0.78, 0.90, 1.05, 1.0),
		"offset": Vector2(6.0, -40.0),
		"origin": &"scrap_scavenger",
		"unlock": "skin_ash_runner",
		"actions": {
			&"idle": ["idle", 0, -1], &"run": ["run", 0, -1],
			&"jump": ["jump", 0, -1], &"fall": ["fall", 0, -1],
			&"dash": ["dash", 0, -1], &"hurt": ["hurt", 0, -1],
			&"death": ["death", 0, -1], &"turn": ["turn", 0, -1],
			&"attack1": ["attack1", 0, -1], &"attack2": ["attack2", 0, -1],
			&"attack_combo": ["attack_combo", 0, -1],
		},
	},
	&"skin_cemetery_hero": {
		"name": "墓园行客",
		"desc": "从墓园另一头走来的旧日英雄，动作更轻、更短。",
		"folder": "player_cemetery_hero",
		"tint": Color(0.92, 1.02, 0.96, 1.0),
		"offset": Vector2(12.0, -29.0),
		"origin": &"rust_automaton",
		"unlock": "skin_cemetery_hero",
		"actions": {
			&"idle": ["idle", 0, -1], &"run": ["run", 0, -1],
			&"jump": ["jump", 0, -1], &"fall": ["jump", 0, -1],
			&"dash": ["run", 0, -1], &"hurt": ["hurt", 0, -1],
			&"death": ["hurt", 0, -1], &"turn": ["idle", 0, -1],
			&"attack1": ["attack", 0, 2], &"attack2": ["attack", 1, -1],
			&"attack_combo": ["attack", 0, -1],
		},
		## 打击帧画布内的身体中心偏右，单给攻击一个偏移。
		"action_offsets": {
			&"attack1": Vector2(7.0, -29.0),
			&"attack2": Vector2(7.0, -29.0),
			&"attack_combo": Vector2(7.0, -29.0),
		},
	},
	&"skin_gothic_hero": {
		"name": "哥特猎手",
		"desc": "窄肩长刃、动作利落，像从教堂彩窗里走下来的猎人。",
		"folder": "player_gothic_hero",
		"tint": Color(1.02, 0.96, 0.92, 1.0),
		"offset": Vector2(0.0, -23.0),
		"origin": &"",
		"unlock": "skin_gothic_hero",
		"actions": {
			&"idle": ["idle", 0, -1], &"run": ["run", 0, -1],
			&"jump": ["jump", 0, -1], &"fall": ["jump", 0, -1],
			&"dash": ["run", 0, -1], &"hurt": ["hurt", 0, -1],
			&"death": ["hurt", 0, -1], &"turn": ["idle", 0, -1],
			&"attack1": ["attack", 0, 2], &"attack2": ["attack", 2, -1],
			&"attack_combo": ["attack", 0, -1],
		},
		"action_offsets": {
			&"attack1": Vector2(4.0, -23.0),
			&"attack2": Vector2(4.0, -23.0),
			&"attack_combo": Vector2(4.0, -23.0),
		},
	},
}


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in SKINS:
		out.append(StringName(id))
	return out


static func has(id: StringName) -> bool:
	return SKINS.has(id)


static func def(id: StringName) -> Dictionary:
	if SKINS.has(id):
		return SKINS[id]
	return SKINS[DEFAULT_SKIN]


static func name_of(id: StringName) -> String:
	return String(def(id).get("name", ""))


static func desc_of(id: StringName) -> String:
	return String(def(id).get("desc", ""))


static func folder_of(id: StringName) -> String:
	return String(def(id).get("folder", ""))


static func tint_of(id: StringName) -> Color:
	return def(id).get("tint", Color.WHITE)


## 逻辑动作在该皮肤下的帧段偏移（攻击类允许单独覆盖）。
static func offset_for(id: StringName, action: StringName) -> Vector2:
	var overrides: Dictionary = def(id).get("action_offsets", {})
	if overrides.has(action):
		return overrides[action]
	return def(id).get("offset", Vector2.ZERO)


static func default_for_origin(origin_id: StringName) -> StringName:
	for id in SKINS:
		if StringName(SKINS[id].get("origin", &"")) == origin_id and origin_id != &"":
			return StringName(id)
	return DEFAULT_SKIN


## 取某个逻辑动作的帧；缺动作/帧段非法时回退到默认骑士的同名动作。
static func frames_for(skin_id: StringName, action: StringName) -> Array[Texture2D]:
	var frames := _frames_from(skin_id, action)
	if frames.is_empty() and skin_id != DEFAULT_SKIN:
		frames = _frames_from(DEFAULT_SKIN, action)
	return frames


static func _frames_from(skin_id: StringName, action: StringName) -> Array[Texture2D]:
	var actions: Dictionary = def(skin_id).get("actions", {})
	if not actions.has(action):
		return []
	var spec: Array = actions[action]
	if spec.size() < 3:
		return []
	var source := String(spec[0])
	var all := CharFrames.anim(folder_of(skin_id), source)
	if all.is_empty():
		return []
	var from := maxi(0, int(spec[1]))
	var to := int(spec[2])
	if to < 0 or to >= all.size():
		to = all.size() - 1
	if from > to:
		return []
	var out: Array[Texture2D] = []
	for i in range(from, to + 1):
		out.append(all[i])
	return out


## 某个皮肤的动作表（给测试/面板显示，返回 {action: frame_count}）。
static func action_frame_counts(skin_id: StringName) -> Dictionary:
	var out := {}
	for action in LOGICAL_ACTIONS:
		out[action] = frames_for(skin_id, action).size()
	return out
