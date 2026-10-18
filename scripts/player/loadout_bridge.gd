class_name LoadoutBridge
extends RefCounted
## 角色/武器系统的只读适配层（契约 §3）。外部角色/武器 agent 拥有
## `scripts/data/character_roster.gd` 与 `scripts/data/weapon_roster.gd`；
## 本战役线只通过这里取显示名/默认值/发放解锁，**不直接引用对方内部**。
##
## 设计约束：
## - roster 脚本不存在或字段缺失时，所有调用安全回退到"当前单角色 + 现有装备"，
##   战役永远可玩（feature-detect）。
## - 只读 + 写 SaveData 的 profile（character_id / extras 解锁表），不写别处。
## - 静态 API（无 autoload），HUD/暂停/标题在打开时读一次即可。

const CHARACTER_ROSTER_PATH := "res://scripts/data/character_roster.gd"
const WEAPON_ROSTER_PATH := "res://scripts/data/weapon_roster.gd"
const EXTRAS_CHARACTERS := "unlocked_characters"
const EXTRAS_WEAPONS := "unlocked_weapons"

static var _character_roster: Script
static var _weapon_roster: Script
static var _character_probed := false
static var _weapon_probed := false

## 仅测试用 roster 注入：[character_script, weapon_script]，元素可以是 Script
## （当作 roster）或 null（模拟该 roster 缺失）。空数组 = 生产路径（默认）。
## 契约测试用它跑「roster 存在」的正向分支，而不把测试替身文件写进 scripts/data/。
## 生产代码永远不写这个变量；teardown 里清空并 reset_roster_cache() 即可复原。
static var test_roster_override: Array = []


## ---------------------------------------------------------------- rosters --

static func _roster(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Script


static func _roster_for(index: int, path: String) -> Script:
	if not test_roster_override.is_empty():
		var value: Variant = test_roster_override[index] if index < test_roster_override.size() else null
		return value as Script
	return _roster(path)


## 测试专用：清空 probe 缓存（注入/撤销 roster 後必须调）。
static func reset_roster_cache() -> void:
	_character_roster = null
	_weapon_roster = null
	_character_probed = false
	_weapon_probed = false


static func character_roster() -> Script:
	if not _character_probed:
		_character_probed = true
		_character_roster = _roster_for(0, CHARACTER_ROSTER_PATH)
	return _character_roster


static func weapon_roster() -> Script:
	if not _weapon_probed:
		_weapon_probed = true
		_weapon_roster = _roster_for(1, WEAPON_ROSTER_PATH)
	return _weapon_roster


## 调用 roster 的静态函数（Godot 4 允许通过实例调静态方法）。失败返回 null。
## roster 脚本通常 extends RefCounted：不能对它调 free()（引擎会报
## "Can't free a RefCounted object"），交给引用计数回收。
static func _call(script: Script, method: String, args: Array = []) -> Variant:
	if script == null or not script.can_instantiate():
		return null
	var obj: Object = script.new()
	if obj == null:
		return null
	if not obj.has_method(method):
		if not obj is RefCounted:
			obj.free()
		return null
	var value: Variant = obj.callv(method, args)
	if not obj is RefCounted:
		obj.free()
	return value


static func character_available() -> bool:
	var roster := character_roster()
	if roster == null:
		return false
	var ids: Variant = _call(roster, "ids")
	return ids is Array and not (ids as Array).is_empty()


static func weapon_available() -> bool:
	var roster := weapon_roster()
	if roster == null:
		return false
	var ids: Variant = _call(roster, "ids")
	return ids is Array and not (ids as Array).is_empty()


## 契约 §3.1：任一 roster 可用即视为外部系统存在（HUD/标题据此决定显示挂点）。
static func available() -> bool:
	return character_available() or weapon_available()


static func _ids_typed(roster: Script) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in _ids(roster):
		out.append(StringName(String(value)))
	return out


## 便于 UI/测试枚举的角色 id（无 roster 时为空数组）。
static func character_ids() -> Array[StringName]:
	return _ids_typed(character_roster())


static func weapon_ids() -> Array[StringName]:
	return _ids_typed(weapon_roster())


static func default_weapon_id() -> StringName:
	var roster := weapon_roster()
	if roster == null:
		return &""
	var value: Variant = _call(roster, "default_id")
	return StringName(String(value)) if value != null else &""


static func _ids(roster: Script) -> Array:
	var value: Variant = _call(roster, "ids")
	return value if value is Array else []


static func _ids_has(roster: Script, id: String) -> bool:
	for value in _ids(roster):
		if String(value) == id:
			return true
	return false


## 契约 §3.1 的 weapon_id()：缺失/空时返回当前装备 weapon 的 id。
static func weapon_id(player: Node = null) -> StringName:
	return equipped_weapon_id(player)


## 契约 §3.1：把 rosters 的公开应用入口接到玩家。对方没提供 apply_to_player
## 时 no-op（feature-detect）；本战役永远不因为缺入口而中断。
static func apply_to_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	for roster in [character_roster(), weapon_roster()]:
		if roster == null:
			continue
		_call(roster, "apply_to_player", [player])


## ------------------------------------------------------------- read-only --

static func default_character_id() -> StringName:
	var roster := character_roster()
	if roster == null:
		return &""
	var value: Variant = _call(roster, "default_id")
	return StringName(String(value)) if value != null else &""


## 当前角色：存档里有就用存档（且必须在 roster 里）；否则 roster 默认，再否则 &""。
## 未知 id（旧档 / 换包 / 外部线删角色）回退默认，不崩也不留空显示。
static func character_id() -> StringName:
	var saved := StringName(SaveData.character_id)
	if saved != &"":
		var roster := character_roster()
		if roster == null:
			return saved
		if _ids_has(roster, String(saved)):
			return saved
		return default_character_id()
	return default_character_id()


static func character_def(id: StringName = &"") -> Dictionary:
	var roster := character_roster()
	if roster == null:
		return {}
	var key := id if id != &"" else character_id()
	if key == &"":
		return {}
	var value: Variant = _call(roster, "def", [key])
	return value if value is Dictionary else {}


static func display_character() -> String:
	var def := character_def()
	return String(def.get("display_name", ""))


static func weapon_def(id: StringName) -> Dictionary:
	var roster := weapon_roster()
	if roster == null:
		return {}
	var value: Variant = _call(roster, "def", [id])
	return value if value is Dictionary else {}


## 当前装备武器 id（唯一来源是现有 EquipmentInventory；roster 只补显示信息）。
static func equipped_weapon_id(player: Node = null) -> StringName:
	var inv: Variant = _equipment_inventory(player)
	if inv == null:
		return &""
	var weapon: Variant = inv.get_equipped(&"weapon")
	if weapon == null:
		return &""
	var id_prop: Variant = weapon.get("id")
	return StringName(String(id_prop)) if id_prop != null else &""


static func display_weapon(player: Node = null) -> String:
	var id := equipped_weapon_id(player)
	if id == &"":
		return ""
	var def := weapon_def(id)
	var name := String(def.get("display_name", ""))
	if name != "":
		return name
	var inv: Variant = _equipment_inventory(player)
	if inv != null:
		var weapon: Variant = inv.get_equipped(&"weapon")
		if weapon != null:
			var display: Variant = weapon.get("display_name")
			if display != null:
				return String(display)
	return ""


static func _equipment_inventory(player: Node) -> Variant:
	if player == null:
		return null
	for prop in ["equipment_inventory", "equipment"]:
		if player.get(prop) != null:
			return player.get(prop)
	var node := player.get_node_or_null("EquipmentInventory")
	return node


## ------------------------------------------------------------- rewards ----

## 关卡奖励位发放：解锁角色/武器引用并保存。
## roster 不存在时返回 false，由调用方（EquipmentPickup）走等价回退，绝不死锁。
static func grant(kind: String, id: String, player: Node = null) -> bool:
	if id.strip_edges() == "":
		return false
	match kind:
		"character":
			if not character_available():
				return false
			if not _ids_has(character_roster(), id):
				return false
			return _unlock(EXTRAS_CHARACTERS, id)
		"weapon":
			if not weapon_available():
				return false
			if not _ids_has(weapon_roster(), id):
				return false
			if weapon_def(StringName(id)).is_empty():
				return false
			return _unlock(EXTRAS_WEAPONS, id)
		_:
			# "equipment" 等：交给现有装备系统（物品 id → EquipmentInventory bag）。
			var inv: Variant = _equipment_inventory(player)
			if inv == null or not inv.has_method("add_to_bag"):
				return false
			var catalog: Script = load("res://scripts/data/equipment_catalog.gd") as Script
			if catalog == null:
				return false
			var factory: Variant = catalog.call("for_id", id) if catalog.has_method("for_id") else null
			if not factory is Variant or factory == null:
				return false
			return bool(inv.call("add_to_bag", factory))


static func _unlock(key: String, id: String) -> bool:
	var current: Variant = SaveData.get_extra(key, [])
	var list: Array = current if current is Array else []
	if not list.has(id):
		list.append(id)
	SaveData.set_extra(key, list)
	SaveData.persist_profile()
	return true


static func is_unlocked(kind: String, id: String) -> bool:
	var key := EXTRAS_CHARACTERS if kind == "character" else EXTRAS_WEAPONS
	var current: Variant = SaveData.get_extra(key, [])
	return current is Array and (current as Array).has(id)


## HUD/暂停显示用的一行：有 roster 时用名字，否则空（调用方隐藏控件）。
static func loadout_line(player: Node = null) -> String:
	var parts: Array[String] = []
	var c := display_character()
	if c != "":
		parts.append(c)
	var w := display_weapon(player)
	if w != "":
		parts.append(w)
	return " · ".join(parts)
