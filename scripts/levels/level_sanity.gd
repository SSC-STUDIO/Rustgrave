class_name LevelSanity
extends RefCounted
## 关卡体检：把「半空里冒出来的东西」变成可断言的规则。
## 对一个已经搭好的关卡 host（Platforms/Props/Enemies/... 都在树里）做纯几何检查：
##   · 每个落地道具 / 落地敌人 / 路牌 / 接地装饰脚下有台面（顶面 ±slack）
##   · 飞行/穿墙敌人不嵌在实体里；同类敌人不重叠
##   · 悬浮的锈核要么下方 64px 内有台面，要么附近有钩锁锚点
##   · 毒池躺在坑里（坑底在池面之下 ≤ 池深+16px），不被地板盖住
##   · 平台不在原点（.tscn 注释吃掉 position 的老毛病）、都在镜头界内
##   · 从出生点起，按「单跳 ≤34px、跨 ≤72px、下落更远、钩锁可借力」能走到出口和每个余烬巢
## 只读几何，不改任何节点。返回问题字串列表，空即通过。

const FOOT_SLACK_UP := 3.0
const FOOT_SLACK_DOWN := 8.0
const FOOT_X_PAD := 4.0
const ENEMY_FOOT_SLACK := 4.0
const SAME_TYPE_MIN_GAP := 24.0
const PICKUP_HOVER_MAX := 64.0
const PICKUP_HOOK_REACH := 96.0
const JUMP_RISE_MAX := 34.0
const JUMP_GAP_MAX := 72.0
const DROP_GAP_PER_PX := 0.5
const DROP_GAP_MAX := 160.0
const HOOK_REACH := 250.0
const HOOK_LAND_BELOW := 110.0
const HOOK_LAND_X := 96.0

## 各类道具的脚点（相对节点原点）。精灵尺寸/偏移见各脚本 ensure_sprite。
const FEET_BY_CLASS := {
	"EmberNest": Vector2(6, 16),
	"LoreStele": Vector2(0, 0),
	"PressurePlate": Vector2(12, 8),
	"ScrapPile": Vector2(9, 18),
	"SocketStation": Vector2(8, 32),
	"PurificationShrine": Vector2(9, 32),
	"FilterGear": Vector2(6, 12),
	"ForgeHeart": Vector2(8, 32),
	"ArenaDoor": Vector2(8, 64),
	"RustyGate": Vector2(8, 64),
	"LevelExit": Vector2(0, 0),
}


## A solid's walkable top: x range at height y (global).
class TopSeg:
	var x0: float
	var x1: float
	var y: float
	var owner_name: String
	func _init(a: float, b: float, top: float, who: String) -> void:
		x0 = a
		x1 = b
		y = top
		owner_name = who


static func check(host: Node, camera_limits: Rect2 = Rect2()) -> Array[String]:
	var problems: Array[String] = []
	var solids := solid_rects(host)
	var tops := top_segments(host)
	if solids.is_empty():
		problems.append("no solid platforms at all")
		return problems
	_check_platforms(host, solids, camera_limits, problems)
	_check_enemies(host, solids, tops, problems)
	_check_props(host, solids, tops, problems)
	_check_grounded_decor(host, tops, problems)
	_check_toxin_pools(host, solids, tops, problems)
	return problems


## ---------------------------------------------------------------- geometry --

static func solid_rects(host: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for node in _descendants(host):
		if node is SolidPlatform:
			var p := node as SolidPlatform
			rects.append(Rect2(p.global_position, p.size))
		elif node is MovingPlatform:
			var m := node as MovingPlatform
			var deck := Vector2(m.width, MovingPlatform.WORLD)
			rects.append(Rect2(_to_global(m, m.start_position()), deck))
			rects.append(Rect2(_to_global(m, m.end_position()), deck))
		elif node is GearPlatform:
			var g := node as GearPlatform
			rects.append(Rect2(g.global_position - Vector2(g.radius, g.radius), Vector2(g.radius * 2.0, g.radius * 2.0)))
	return rects


static func top_segments(host: Node) -> Array[TopSeg]:
	var segs: Array[TopSeg] = []
	for node in _descendants(host):
		if node is SolidPlatform:
			var p := node as SolidPlatform
			# Walls / ceilings are solids you cannot stand on top of usefully; skip
			# anything thinner than 24px wide or whose top is at/above the ceiling line.
			if p.size.x < 24.0 or String(p.name).begins_with("Ceiling") or p.has_meta("non_walkable"):
				continue
			segs.append(TopSeg.new(p.global_position.x, p.global_position.x + p.size.x, p.global_position.y, String(p.name)))
		elif node is MovingPlatform:
			var m := node as MovingPlatform
			var a := _to_global(m, m.start_position())
			var b := _to_global(m, m.end_position())
			segs.append(TopSeg.new(a.x, a.x + m.width, a.y, String(m.name) + "@start"))
			segs.append(TopSeg.new(b.x, b.x + m.width, b.y, String(m.name) + "@end"))
		elif node is GearPlatform:
			var g := node as GearPlatform
			segs.append(TopSeg.new(g.global_position.x - g.radius, g.global_position.x + g.radius, g.global_position.y - g.radius, String(g.name)))
	return segs


static func _to_global(node: Node2D, local_pos: Vector2) -> Vector2:
	var parent := node.get_parent() as Node2D
	return parent.to_global(local_pos) if parent != null else local_pos


static func standing_on(tops: Array[TopSeg], feet: Vector2, slack_up: float = FOOT_SLACK_UP, slack_down: float = FOOT_SLACK_DOWN) -> TopSeg:
	var best: TopSeg = null
	var best_d := INF
	for seg in tops:
		if feet.x < seg.x0 - FOOT_X_PAD or feet.x > seg.x1 + FOOT_X_PAD:
			continue
		var d := feet.y - seg.y
		if d < -slack_up or d > slack_down:
			continue
		if absf(d) < best_d:
			best_d = absf(d)
			best = seg
	return best


static func inside_solid(solids: Array[Rect2], point: Vector2) -> bool:
	for r in solids:
		if r.grow(-1.0).has_point(point):
			return true
	return false


static func feet_of(node: Node) -> Vector2:
	if node.has_method("feet_point"):
		return node.call("feet_point")
	var n2 := node as Node2D
	if n2 == null:
		return Vector2.INF
	# Planted decor records its authored foot point (parent space) as metadata.
	if node.has_meta("feet"):
		var parent := node.get_parent() as Node2D
		var feet: Vector2 = node.get_meta("feet")
		return parent.to_global(feet) if parent != null else feet
	var script := node.get_script() as Script
	while script != null:
		var cname := script.get_global_name()
		if FEET_BY_CLASS.has(cname):
			return n2.global_position + (FEET_BY_CLASS[cname] as Vector2)
		script = script.get_base_script()
	var fill := node.get_node_or_null("Fill")
	if fill is Sprite2D:
		var spr := fill as Sprite2D
		var r := spr.get_rect()
		return spr.to_global(Vector2(r.get_center().x, r.end.y))
	if node is Sprite2D:
		var spr2 := node as Sprite2D
		var r2 := spr2.get_rect()
		return spr2.to_global(Vector2(r2.get_center().x, r2.end.y))
	return n2.global_position


## ------------------------------------------------------------------ checks --

static func _check_platforms(host: Node, solids: Array[Rect2], limits: Rect2, problems: Array[String]) -> void:
	for node in _descendants(host):
		if node is SolidPlatform:
			var p := node as SolidPlatform
			if p.position == Vector2.ZERO and p.size != Vector2.ZERO and String(p.name) != "GroundLeft" and String(p.name) != "FloorA":
				problems.append("platform %s sits at the origin (lost its position?)" % p.name)
			if limits.has_area():
				var r := Rect2(p.global_position, p.size)
				if r.end.x < limits.position.x - 16.0 or r.position.x > limits.end.x + 16.0:
					problems.append("platform %s lies outside the camera limits" % p.name)


static func _check_enemies(host: Node, solids: Array[Rect2], tops: Array[TopSeg], problems: Array[String]) -> void:
	var enemies: Array[Node2D] = []
	for node in _descendants(host):
		if node is EnemyBase:
			enemies.append(node as Node2D)
	for e in enemies:
		var airborne := e is FlyingDemonEnemy or e is GhostEnemy \
				or (e.has_method("is_airborne") and bool(e.call("is_airborne")))
		if airborne:
			if inside_solid(solids, e.global_position):
				problems.append("%s (%s) is embedded in a solid at %s" % [e.name, _cls(e), e.global_position])
		else:
			if standing_on(tops, e.global_position, ENEMY_FOOT_SLACK, ENEMY_FOOT_SLACK) == null:
				problems.append("%s (%s) has no platform under its feet at %s" % [e.name, _cls(e), e.global_position])
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			var a := enemies[i]
			var b := enemies[j]
			if _cls(a) == _cls(b) and a.global_position.distance_to(b.global_position) < SAME_TYPE_MIN_GAP:
				problems.append("%s and %s (%s) overlap at %s" % [a.name, b.name, _cls(a), a.global_position])


static func _check_props(host: Node, solids: Array[Rect2], tops: Array[TopSeg], problems: Array[String]) -> void:
	var anchors: Array[Vector2] = []
	for node in _descendants(host):
		if node is HookAnchor:
			anchors.append((node as Node2D).global_position)
	for node in _descendants(host):
		if node is ToxinPool or node is HookAnchor or node is AtmosphereZone:
			continue
		if node is CorePickup:
			var pick := node as Node2D
			var ok_hover := false
			for seg in tops:
				if pick.global_position.x >= seg.x0 - FOOT_X_PAD and pick.global_position.x <= seg.x1 + FOOT_X_PAD \
						and seg.y >= pick.global_position.y - 4.0 and seg.y - pick.global_position.y <= PICKUP_HOVER_MAX:
					ok_hover = true
					break
			if not ok_hover:
				for a in anchors:
					if a.distance_to(pick.global_position) <= PICKUP_HOOK_REACH:
						ok_hover = true
						break
			if not ok_hover:
				problems.append("pickup %s hovers at %s with no platform beneath and no hook nearby" % [pick.name, pick.global_position])
			continue
		if node is Interactable:
			var feet := feet_of(node)
			if feet == Vector2.INF:
				continue
			if standing_on(tops, feet) == null:
				problems.append("%s (%s) has nothing under its feet at %s" % [node.name, _cls(node), feet])
	var signs := host.get_node_or_null("Waymarks")
	if signs != null:
		for sign in signs.get_children():
			if sign is Node2D and standing_on(tops, (sign as Node2D).global_position) == null:
				problems.append("waymark %s floats at %s" % [sign.name, (sign as Node2D).global_position])


static func _check_grounded_decor(host: Node, tops: Array[TopSeg], problems: Array[String]) -> void:
	for node in _descendants(host):
		if not node.is_in_group("grounded"):
			continue
		var feet := feet_of(node)
		if feet == Vector2.INF:
			continue
		if standing_on(tops, feet, FOOT_SLACK_UP, FOOT_SLACK_DOWN) == null:
			problems.append("decor %s floats at %s" % [node.name, feet])


static func _check_toxin_pools(host: Node, solids: Array[Rect2], tops: Array[TopSeg], problems: Array[String]) -> void:
	for node in _descendants(host):
		if not node is ToxinPool:
			continue
		var pool := node as ToxinPool
		var rect := pool.surface_rect()
		var has_bed := false
		for seg in tops:
			if seg.x1 <= rect.position.x or seg.x0 >= rect.end.x:
				continue
			if seg.y >= rect.position.y and seg.y <= rect.end.y + 16.0:
				has_bed = true
			elif seg.y < rect.position.y and seg.y > rect.position.y - 48.0 and seg.x0 <= rect.position.x + 8.0 and seg.x1 >= rect.end.x - 8.0:
				problems.append("toxin pool %s is covered by %s" % [pool.name, seg.owner_name])
		if not has_bed:
			problems.append("toxin pool %s at %s has no pit floor under it" % [pool.name, rect])


## ------------------------------------------------------------ reachability --

## Platforms reachable from `from_point` by walking, single jumps, drops and
## hookshot pulls. Returns the set of TopSeg reached (by index into top_segments).
static func reachable_segments(host: Node, from_point: Vector2, allow_hook: bool = true) -> Array[TopSeg]:
	var tops := top_segments(host)
	var anchors: Array[Vector2] = []
	for node in _descendants(host):
		if node is HookAnchor:
			anchors.append((node as Node2D).global_position)
	var start := _segment_below(tops, from_point)
	var reached: Array[TopSeg] = []
	if start == null:
		return reached
	var queue: Array[TopSeg] = [start]
	reached.append(start)
	while not queue.is_empty():
		var cur: TopSeg = queue.pop_front()
		for seg in tops:
			if reached.has(seg):
				continue
			if _can_hop(cur, seg) or (allow_hook and _can_hook(cur, seg, anchors)) or _same_lift(cur, seg):
				reached.append(seg)
				queue.append(seg)
	return reached


## Riding a lift: its start and end decks are one place.
static func _same_lift(a: TopSeg, b: TopSeg) -> bool:
	var a_lift := a.owner_name.get_slice("@", 0)
	var b_lift := b.owner_name.get_slice("@", 0)
	return a.owner_name.contains("@") and b.owner_name.contains("@") and a_lift == b_lift


static func is_reachable(host: Node, from_point: Vector2, target: Vector2, allow_hook: bool = true) -> bool:
	for seg in reachable_segments(host, from_point, allow_hook):
		if target.x >= seg.x0 - FOOT_X_PAD and target.x <= seg.x1 + FOOT_X_PAD and absf(target.y - seg.y) <= FOOT_SLACK_DOWN + 40.0:
			return true
	return false


static func _segment_below(tops: Array[TopSeg], point: Vector2) -> TopSeg:
	var best: TopSeg = null
	for seg in tops:
		if point.x < seg.x0 - FOOT_X_PAD or point.x > seg.x1 + FOOT_X_PAD:
			continue
		if seg.y < point.y - FOOT_SLACK_UP:
			continue
		if best == null or seg.y < best.y:
			best = seg
	return best


static func _gap(a: TopSeg, b: TopSeg) -> float:
	if b.x0 > a.x1:
		return b.x0 - a.x1
	if a.x0 > b.x1:
		return a.x0 - b.x1
	return 0.0


static func _can_hop(a: TopSeg, b: TopSeg) -> bool:
	var gap := _gap(a, b)
	var rise := a.y - b.y
	if rise > JUMP_RISE_MAX:
		return false
	if rise >= 0.0:
		return gap <= JUMP_GAP_MAX
	var drop := -rise
	return gap <= minf(DROP_GAP_MAX, JUMP_GAP_MAX + drop * DROP_GAP_PER_PX)


static func _can_hook(a: TopSeg, b: TopSeg, anchors: Array[Vector2]) -> bool:
	for anchor in anchors:
		var ax := clampf(anchor.x, a.x0, a.x1)
		var from := Vector2(ax, a.y - 48.0)
		if anchor.y >= a.y or from.distance_to(anchor) > HOOK_REACH:
			continue
		var landing_dy := b.y - anchor.y
		if landing_dy < -8.0 or landing_dy > HOOK_LAND_BELOW:
			continue
		var bx := clampf(anchor.x, b.x0, b.x1)
		if absf(bx - anchor.x) <= HOOK_LAND_X:
			return true
	return false


## ---------------------------------------------------------------- helpers --

static func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			out.append(c)
			stack.append(c)
	return out


static func _cls(node: Node) -> String:
	var script := node.get_script() as Script
	if script != null and script.get_global_name() != "":
		return script.get_global_name()
	return node.get_class()
