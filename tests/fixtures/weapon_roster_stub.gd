extends RefCounted
## 契约 §3.1 的武器 roster 测试替身（外部角色/武器线所有；此文件只用于正向契约测试）。
## 与 LoadoutBridge 的静态 API 形状完全一致：
##   ids() -> Array[StringName]
##   def(id) -> Dictionary  {display_name, slot, moveset_id, pickup_art, desc, unlocked_by}
##   default_id() -> StringName

const IRON_BLADE := {
	"display_name": "锈铁长刃",
	"slot": &"weapon",
	"moveset_id": &"sword",
	"pickup_art": "res://assets/env/rust_core.png",
	"desc": "断口还在，能砍。",
	"unlocked_by": "start",
}
const BELL_HAMMER := {
	"display_name": "铸钟锤",
	"slot": &"weapon",
	"moveset_id": &"hammer",
	"pickup_art": "res://assets/env/rust_core.png",
	"desc": "钟铸成了，锤就不用了。",
	"unlocked_by": "level07b",
}


static func ids() -> Array[StringName]:
	return [&"iron_blade", &"bell_hammer"]


static func default_id() -> StringName:
	return &"iron_blade"


static func def(id: StringName) -> Dictionary:
	match id:
		&"iron_blade":
			return IRON_BLADE.duplicate(true)
		&"bell_hammer":
			return BELL_HAMMER.duplicate(true)
		_:
			return {}


## 契约外但外部线常带的公开入口：LoadoutBridge.apply_to_player 会 feature-detect 它。
static func apply_to_player(_player: Node) -> void:
	pass
