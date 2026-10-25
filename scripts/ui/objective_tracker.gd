class_name ObjectiveTracker
extends RefCounted
## HUD 的"目标"一行。关卡目前没有专门的目标数据，所以这里只用场景里已有的东西
## 推出一句通用的话（优先级从上到下）：
##   0. 关卡作者给了 world.set_meta(&"objective", "…") → 原样用（给剧情关卡留的口子）
##   1. Boss 战中            → 击败 {Boss 名}
##   2. 血量 ≤ 2 且附近有余烬巢 → 回余烬巢恢复 ←/→
##   3. 有出口：已开 → 前往 {门名} ←/→；封锁 → {门名} 尚未开启
##   4. 没有出口但有未点燃的巢 → 点燃沿途的余烬巢
##   5. 其余 → 空（HUD 不显示这一行）
## 场景只在 scan() 时遍历一次（出口、余烬巢不会凭空出现），之后每次取值只读缓存节点的位置与状态。
##
## line() 的文案口径不变（暂停页的"目标"行也读它）。HUD 把前缀 "目标 · " 收掉，改由
## "目 标" 小标题带着；目标左侧的菱形列由 marks() 给：点燃沿途的余烬巢时一巢一粒（已点燃 = 余烬色），
## 其余目标只有一粒（未完成 = 冷铁）。

const META_KEY := &"objective"
const PREFIX := "目标 · "
## 血量低到这个值时，附近的余烬巢比出口更要紧。
const LOW_HP := 2
## "附近"的余烬巢半径（世界像素，约 1.4 屏宽）。
const NEST_NEAR := 900.0

var _nests: Array = []
var _exits: Array = []
var _world: Node


func scan(world: Node) -> void:
	_nests.clear()
	_exits.clear()
	_world = world
	if world != null:
		_collect(world)


func has_scanned() -> bool:
	return _world != null and is_instance_valid(_world)


func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is EmberNest:
			_nests.append(child)
		elif child is LevelExit:
			_exits.append(child)
		elif child is Player or child is Camera2D or child is CollisionShape2D:
			continue
		if child.get_child_count() > 0:
			_collect(child)


## 当前目标行；"" 表示没有可说的。
func line(player: Player, boss_name: String = "") -> String:
	return String(_state(player, boss_name)["text"])


## HUD 显示用：去掉 "目标 · " 前缀（小标题"目 标"已经说了）。
static func body_of(full: String) -> String:
	return full.trim_prefix(PREFIX)


## 目标左侧的菱形：nests 一巢一粒（按位置从左到右），done = 已点燃；其余目标一粒，恒为未完成。
## 没有目标时为空数组。
func marks(player: Player, boss_name: String = "") -> Array[bool]:
	var out: Array[bool] = []
	var kind: StringName = _state(player, boss_name)["kind"]
	if kind == &"nests":
		var placed: Array[Dictionary] = []
		for n in _nests:
			if is_instance_valid(n):
				placed.append({"x": (n as Node2D).global_position.x, "lit": (n as EmberNest).is_lit()})
		placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["x"]) < float(b["x"]))
		for d in placed:
			out.append(bool(d["lit"]))
	elif kind != &"":
		out.append(false)
	return out


func _state(player: Player, boss_name: String) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {"kind": &"", "text": ""}
	if _world != null and is_instance_valid(_world) and _world.has_meta(META_KEY):
		var authored := String(_world.get_meta(META_KEY))
		if authored != "":
			return {"kind": &"authored", "text": PREFIX + authored}
	var nests: Array[Dictionary] = []
	for n in _nests:
		if is_instance_valid(n):
			nests.append({"x": (n as Node2D).global_position.x, "lit": (n as EmberNest).is_lit()})
	var door := {}
	for e in _exits:
		if is_instance_valid(e):
			var exit := e as LevelExit
			door = {"x": exit.global_position.x, "locked": exit.is_locked(),
					"label": exit.door_label}
			break
	return decide(player.global_position.x, player.health.current, nests, door, boss_name)


## 纯函数：不碰场景，方便单测。nests: [{x, lit}]；door: {} 或 {x, locked, label}。
static func compose(player_x: float, hp: int, nests: Array[Dictionary],
		door: Dictionary, boss_name: String) -> String:
	return String(decide(player_x, hp, nests, door, boss_name)["text"])


## 同 compose，但连同"是哪一条目标"一起给出（kind: boss / heal / locked / door / nests，无目标为 &""）。
static func decide(player_x: float, hp: int, nests: Array[Dictionary],
		door: Dictionary, boss_name: String) -> Dictionary:
	var boss := boss_name.replace(" ", "")
	if boss != "":
		return {"kind": &"boss", "text": "目标 · 击败%s" % boss}
	if hp <= LOW_HP and not nests.is_empty():
		var near := _nearest(player_x, nests)
		if absf(float(near["x"]) - player_x) <= NEST_NEAR:
			return {"kind": &"heal",
					"text": ("目标 · 回余烬巢恢复 %s" % _arrow(player_x, float(near["x"]))).strip_edges()}
	if not door.is_empty():
		var label := String(door.get("label", "出口"))
		if bool(door.get("locked", false)):
			return {"kind": &"locked", "text": "目标 · %s尚未开启" % label}
		return {"kind": &"door",
				"text": ("目标 · 前往%s %s" % [label, _arrow(player_x, float(door["x"]))]).strip_edges()}
	var unlit: Array[Dictionary] = []
	for n in nests:
		if not bool(n["lit"]):
			unlit.append(n)
	if not unlit.is_empty():
		return {"kind": &"nests",
				"text": ("目标 · 点燃沿途的余烬巢 %s" % _arrow(player_x, float(_nearest(player_x, unlit)["x"]))).strip_edges()}
	return {"kind": &"", "text": ""}


static func _nearest(player_x: float, nests: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = nests[0]
	for n in nests:
		if absf(float(n["x"]) - player_x) < absf(float(best["x"]) - player_x):
			best = n
	return best


## 目标就在脚边（40 像素内）时不画箭头。
static func _arrow(from_x: float, to_x: float) -> String:
	if absf(to_x - from_x) < 40.0:
		return ""
	return "→" if to_x > from_x else "←"


## 目标左侧的菱形列（HUD 目标条里用）。done = 余烬色（已点燃的巢），open = 冷铁。
class Marks extends Control:
	const PITCH := 14.0
	const RIM := 4.0
	var _done: Array[bool] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		visible = false

	func set_marks(done: Array[bool]) -> void:
		_done = done.duplicate()
		var n := _done.size()
		custom_minimum_size = Vector2(float(n) * PITCH, 2.0 * RIM + 2.0 if n > 0 else 0.0)
		visible = n > 0
		queue_redraw()

	func mark_count() -> int:
		return _done.size()

	func _draw() -> void:
		var cy := floorf(size.y * 0.5)
		for i in _done.size():
			var c := Vector2(floorf(RIM + float(i) * PITCH), cy)
			if _done[i]:
				GlassKit.diamond(self, c, RIM, GlassKit.EMBER)
				GlassKit.diamond(self, c, 2.0, GlassKit.EMBER_HOT)
			else:
				GlassKit.diamond(self, c, RIM, GlassKit.COLD_IRON)
				GlassKit.diamond(self, c, 2.0, GlassKit.COLD)
