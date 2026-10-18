extends RefCounted
## 契约 §3.1 的角色 roster 测试替身（外部角色/武器线所有；此文件只用于正向契约测试）。
## 与 LoadoutBridge 的静态 API 形状完全一致，不含任何项目状态：
##   ids() -> Array[StringName]
##   def(id) -> Dictionary  {display_name, char_frames_id, body_size, hurt_size,
##                           speed_mult, max_hp_mod, intro_line, ability_set}
##   default_id() -> StringName
## 三个角色覆盖：无能力（基础）、钩锁、余烬步——用于「主路线不依赖能力」矩阵。

const KNIGHT := {
	"display_name": "余烬骑士",
	"char_frames_id": &"knight_frames",
	"body_size": Vector2(14, 26),
	"hurt_size": Vector2(10, 22),
	"speed_mult": 1.0,
	"max_hp_mod": 0,
	"intro_line": "剑是捡的，火是借的。",
}
const GOTHIC_HERO := {
	"display_name": "哥特骑手",
	"char_frames_id": &"gothic_frames",
	"body_size": Vector2(16, 28),
	"hurt_size": Vector2(12, 24),
	"speed_mult": 1.08,
	"max_hp_mod": 1,
	"intro_line": "我从井口下来，没打算原路回去。",
}
const ASH_RUNNER := {
	"display_name": "灰行者",
	"char_frames_id": &"ash_frames",
	"body_size": Vector2(12, 24),
	"hurt_size": Vector2(10, 20),
	"speed_mult": 1.16,
	"max_hp_mod": -1,
	"intro_line": "灰会记住每一个脚印。",
}
const ABILITY_SETS := {
	&"knight": [],
	&"gothic_hero": [&"hookshot"],
	&"ash_runner": [&"ember_step"],
}


static func ids() -> Array[StringName]:
	return [&"knight", &"gothic_hero", &"ash_runner"]


static func default_id() -> StringName:
	return &"knight"


static func def(id: StringName) -> Dictionary:
	var out: Dictionary = {}
	match id:
		&"knight":
			out = KNIGHT.duplicate(true)
		&"gothic_hero":
			out = GOTHIC_HERO.duplicate(true)
		&"ash_runner":
			out = ASH_RUNNER.duplicate(true)
		_:
			return {}
	var abilities: Array[StringName] = []
	for ability in ABILITY_SETS[id]:
		abilities.append(StringName(ability))
	out["ability_set"] = abilities
	return out


## 契约外但外部线常带的公开入口：LoadoutBridge.apply_to_player 会 feature-detect 它。
static func apply_to_player(_player: Node) -> void:
	pass
