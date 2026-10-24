class_name SpawnSafety
extends RefCounted
## 读档 / 重生坐标的安全阀。
##
## v3 改造会挪动台面、塌陷台和机关：旧存档里的 `player.pos`（以及重生用的巢坐标）有可能
## 落进新的实心里、或正压在周期机关的判定区里。关卡生成骑士时先问一次这里：
## 坐标安全就原样用；不安全就退到最后一个点亮的余烬巢，再退到任意一个巢，最后用关卡缺省出生点。
## 只读几何，不改任何节点、不写存档。

## 身体中段的两个探点（相对脚点）。再往上的头顶净空由 LevelSanity 的 headroom 规则保证，
## 这里不重复，免得把合法的矮顶巢误判成"埋住"。
const PROBES := [-3.0, -12.0]
const WORLD_FLOOR_MAX := 480.0
const HAZARD_PAD := 8.0


static func is_safe(world: Node, pos: Vector2) -> bool:
	if world == null:
		return true
	if pos == Vector2.INF or pos.y > WORLD_FLOOR_MAX:
		return false
	var solids := LevelSanity.solid_rects(world)
	for dy in PROBES:
		if LevelSanity.inside_solid(solids, pos + Vector2(0.0, float(dy))):
			return false
	var body_point := pos + Vector2(0.0, -13.0)
	for hz in LevelSanity.hazards(world):
		var kind := String(hz.get_meta("hazard_kind", ""))
		var zone := Rect2()
		match kind:
			"cyclic":
				zone = (hz as CyclicHazard).hit_rect()
			"pendulum":
				zone = (hz as PendulumHazard).danger_rect()
			_:
				continue
		if zone.grow(HAZARD_PAD).has_point(body_point):
			return false
	return true


## 返回可以放骑士的坐标。`saved` 不安全时依次退到：最后点亮的巢 → 任意巢 → `fallback`。
static func safe_position(world: Node, saved: Vector2, fallback: Vector2) -> Vector2:
	if is_safe(world, saved):
		return saved
	var lit := _last_lit_nest(world)
	if lit != null and is_safe(world, lit.global_position):
		return lit.global_position
	for node in _nests(world):
		if is_safe(world, node.global_position):
			return node.global_position
	return fallback


static func _last_lit_nest(world: Node) -> Node2D:
	var path := SaveData.last_lit_nest()
	if path == "" or world == null:
		return null
	var nest := SaveData.resolve_saved_node(world, path)
	return nest as Node2D


static func _nests(world: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if world == null:
		return out
	for node in world.find_children("*", "EmberNest", true, false):
		if node is Node2D:
			out.append(node as Node2D)
	return out
