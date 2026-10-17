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

## ----------------------------------------------------------- deep audit --
## 原有检查只问「脚下有没有台面」。这一层问「身体合不合理」：
##   · 可站台面被别的实心埋住（点站不上去）
##   · 台面上方没有站立净空（头顶着天花板/吊台）
##   · 吊台行程被实体挡住（坐个台子穿过地板）
##   · 毒池被地板/岩台盖住（露不出来）
##   · 地面线出现 >160px 的断口且没有坑或吊台可借
##   · 道具/敌人身体嵌进实心，或互相穿插（半截碑、门里长敌人）
##   · 落地敌人站在毒池里；出口贴右墙；节点漂出镜头界
const HEADROOM_MIN := 20.0
const BODY_EMBED_DEPTH := 4.0
const BODY_EMBED_RATIO := 0.25
const PROP_OVERLAP_RATIO := 0.30
const DOCK_TOLERANCE := 2.0
const EXIT_WALL_CLEAR := 80.0
const BOUNDS_PAD := 24.0
const WORLD_FLOOR_MAX := 480.0
const POOL_COVER_DEPTH := 8.0
const TOP_SAMPLE_STEP := 8.0

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
	var entries := solid_entries(host)
	_check_platforms(host, solids, camera_limits, problems)
	_check_enemies(host, solids, tops, problems)
	_check_props(host, solids, tops, problems)
	_check_grounded_decor(host, tops, problems)
	_check_toxin_pools(host, solids, tops, problems)
	_check_buried_tops(host, entries, tops, problems)
	_check_headroom(host, entries, tops, problems)
	_check_lift_paths(host, entries, problems)
	_check_pool_coverage(host, entries, problems)
	_check_bodies_in_pools(host, problems)
	_check_body_embeds(host, entries, problems)
	_check_prop_overlaps(host, problems)
	_check_floor_gaps(host, tops, problems)
	_check_bounds(host, entries, camera_limits, problems)
	_check_exit_clearance(host, camera_limits, problems)
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


## ------------------------------------------------------- deep audit checks --

## A walkable top buried inside another solid: part of the ledge you cannot
## stand on because rock fills it. A mound step standing ON a floor (its top
## above the floor line, earth dipping in) is the authored look — only a lid
## whose top sits at/below the walking surface swallows the ledge.
static func _check_buried_tops(_host: Node, entries: Array[Dictionary], tops: Array[TopSeg], problems: Array[String]) -> void:
	for seg in tops:
		var bad := ""
		var x := seg.x0
		while x <= seg.x1 and bad == "":
			var blocker := _entry_at(entries, Vector2(x, seg.y - 4.0))
			if blocker != "":
				var r := _entry_rect(entries, blocker)
				if r.position.y >= seg.y + 4.0:
					bad = blocker
			x += TOP_SAMPLE_STEP
		if bad != "":
			problems.append("ledge %s (y=%.0f, x %.0f..%.0f) is buried under %s — you cannot stand on part of it" % [seg.owner_name, seg.y, seg.x0, seg.x1, bad])


## No standing clearance above a ledge: the knight (~26-32px) bonks or
## squeezes. A block you can hop onto (top within one jump of the ledge) is
## just a step, not a trap; only a lid too tall to climb and too low to walk
## under is a problem.
static func _check_headroom(_host: Node, entries: Array[Dictionary], tops: Array[TopSeg], problems: Array[String]) -> void:
	for seg in tops:
		var bad := ""
		var x := seg.x0
		while x <= seg.x1 and bad == "":
			var blocker := _entry_at(entries, Vector2(x, seg.y - HEADROOM_MIN))
			if blocker != "" and not _same_owner(seg, blocker):
				var r := _entry_rect(entries, blocker)
				var step_over := r.position.y >= seg.y - JUMP_RISE_MAX
				if not step_over:
					bad = blocker
			x += TOP_SAMPLE_STEP
		if bad != "":
			problems.append("ledge %s (y=%.0f, x %.0f..%.0f) has no headroom — %s sits right on top of it" % [seg.owner_name, seg.y, seg.x0, seg.x1, bad])


## A lift that rides through terrain on its way. Docks flush with a floor top
## (deck resting on the surface) are allowed; anything else is a stuck lift.
static func _check_lift_paths(_host: Node, entries: Array[Dictionary], problems: Array[String]) -> void:
	for node in _descendants(_host):
		if not node is MovingPlatform:
			continue
		var m := node as MovingPlatform
		var a := _to_global(m, m.start_position())
		var b := _to_global(m, m.end_position())
		var deck := Vector2(m.width, MovingPlatform.WORLD)
		var sweep := Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(b.x - a.x) + deck.x, absf(b.y - a.y) + deck.y)
		for e in entries:
			if e["kind"] != "solid":
				continue
			var r := e["rect"] as Rect2
			var ov := _overlap(sweep, r)
			if ov.x <= 2.0 or ov.y <= 2.0:
				continue
			var flush_dock := absf(r.position.y - a.y) <= DOCK_TOLERANCE or absf(r.position.y - b.y) <= DOCK_TOLERANCE
			if not flush_dock:
				problems.append("lift %s travels through %s (overlap %.0fx%.0f) — the deck clips terrain" % [m.name, e["name"], ov.x, ov.y])


## A pool surface you cannot see because a floor or slab lies over it. Small
## lips standing IN the pool (pit climb stones at the surface) are authored.
static func _check_pool_coverage(_host: Node, entries: Array[Dictionary], problems: Array[String]) -> void:
	for node in _descendants(_host):
		if not node is ToxinPool:
			continue
		var pool := node as ToxinPool
		var rect := pool.surface_rect()
		for e in entries:
			if e["kind"] != "solid":
				continue
			var r := e["rect"] as Rect2
			var ov := _overlap(rect, r)
			if ov.x <= 8.0 or ov.y <= POOL_COVER_DEPTH:
				continue
			if r.position.y >= rect.position.y - 4.0:
				continue  # an island at/below the surface, not a lid
			problems.append("toxin pool %s is covered by %s (overlap %.0fx%.0f)" % [pool.name, e["name"], ov.x, ov.y])


## Anything with feet standing in sludge: enemies drown, plates sink.
static func _check_bodies_in_pools(_host: Node, problems: Array[String]) -> void:
	var pools: Array[Dictionary] = []
	for node in _descendants(_host):
		if node is ToxinPool:
			pools.append({"name": String(node.name), "rect": (node as ToxinPool).surface_rect().grow(2.0)})
	if pools.is_empty():
		return
	for node in _descendants(_host):
		if not (node is Interactable or node is CorePickup or node is EnemyBase):
			continue
		if node is ToxinPool or node is HookAnchor or node is AtmosphereZone:
			continue
		if node is EnemyBase:
			var airborne := node is FlyingDemonEnemy or node is GhostEnemy \
					or (node.has_method("is_airborne") and bool(node.call("is_airborne")))
			if airborne:
				continue
		var feet := feet_of(node)
		if feet == Vector2.INF:
			continue
		for pool in pools:
			var rect := pool["rect"] as Rect2
			if rect.has_point(feet):
				problems.append("%s (%s) stands inside toxin pool %s at %s" % [node.name, _cls(node), pool["name"], feet])


## A body half inside rock: stele sunk in a wall, nest in a step, enemy in a
## gate. Wall dressing (torch plates, windows, gargoyles) is meant to overlap.
## Frame-animated enemies get a nominal box — their canvases dwarf the foe.
static func _check_body_embeds(_host: Node, entries: Array[Dictionary], problems: Array[String]) -> void:
	for node in _descendants(_host):
		if not (node is Interactable or node is CorePickup or node is EnemyBase or node is TorchLight):
			continue
		if node is ToxinPool or node is HookAnchor or node is AtmosphereZone:
			continue
		var airborne := false
		if node is EnemyBase:
			airborne = node is FlyingDemonEnemy or node is GhostEnemy \
					or (node.has_method("is_airborne") and bool(node.call("is_airborne")))
		if airborne or node is TorchLight or node.z_index < 0:
			continue  # wall-mounted or flying by design
		var box := node_aabb(node as Node2D) if not (node is EnemyBase) else _enemy_box(node as Node2D)
		if box.has_area() == false:
			continue
		for e in entries:
			var r := e["rect"] as Rect2
			var ov := _overlap(box, r)
			if ov.x <= BODY_EMBED_DEPTH or ov.y <= BODY_EMBED_DEPTH:
				continue
			var ratio := (ov.x * ov.y) / maxf(box.get_area(), 1.0)
			if ratio >= BODY_EMBED_RATIO:
				problems.append("%s (%s) at %s is embedded %.0f%% inside %s" % [node.name, _cls(node), (node as Node2D).global_position, ratio * 100.0, e["name"]])
				break


## Two solid props sharing the same space (or an enemy spawned inside one).
static func _check_prop_overlaps(_host: Node, problems: Array[String]) -> void:
	var props: Array[Node2D] = []
	var enemies: Array[Node2D] = []
	for node in _descendants(_host):
		if node is ToxinPool or node is HookAnchor or node is AtmosphereZone:
			continue
		if node is CorePickup or (node is Interactable and not (node is PressurePlate)):
			props.append(node as Node2D)
		elif node is EnemyBase:
			var airborne := node is FlyingDemonEnemy or node is GhostEnemy \
					or (node.has_method("is_airborne") and bool(node.call("is_airborne")))
			if not airborne:
				enemies.append(node as Node2D)
	for i in props.size():
		for j in range(i + 1, props.size()):
			var a := props[i]
			var b := props[j]
			var ov := _overlap(node_aabb(a), node_aabb(b))
			var area := minf(node_aabb(a).get_area(), node_aabb(b).get_area())
			if area > 0.0 and (ov.x * ov.y) / area >= PROP_OVERLAP_RATIO:
				problems.append("%s (%s) and %s (%s) overlap (%.0f%%) at %s" % [a.name, _cls(a), b.name, _cls(b), (ov.x * ov.y) / area * 100.0, a.global_position])
	for e in enemies:
		for p in props:
			if p is PressurePlate:
				continue
			var ov := _overlap(_enemy_box(e), node_aabb(p))
			var area := minf(_enemy_box(e).get_area(), node_aabb(p).get_area())
			if area > 0.0 and (ov.x * ov.y) / area >= PROP_OVERLAP_RATIO:
				problems.append("%s (%s) spawns inside %s (%s) at %s" % [e.name, _cls(e), p.name, _cls(p), e.global_position])


## A hole in the dominant floor line wider than any jump, with no pit or lift
## to excuse it: the main route dead-ends there. Branch ledges at other
## heights are a different matter — only the widest floor line is policed.
static func _check_floor_gaps(_host: Node, tops: Array[TopSeg], problems: Array[String]) -> void:
	var by_y: Dictionary = {}
	for seg in tops:
		if not by_y.has(seg.y):
			by_y[seg.y] = []
		(by_y[seg.y] as Array).append(seg)
	var line_y := 0.0
	var line_w := -1.0
	for y in by_y:
		var w := 0.0
		for seg in (by_y[y] as Array):
			w += seg.x1 - seg.x0
		if w > line_w:
			line_w = w
			line_y = y
	if line_w <= 0.0:
		return
	var line: Array = (by_y[line_y] as Array).duplicate()
	line.sort_custom(func(a: TopSeg, b: TopSeg) -> bool: return a.x1 < b.x1)
	var pools: Array[Rect2] = []
	var decks: Array[Rect2] = []
	var anchors: Array[Vector2] = []
	for node in _descendants(_host):
		if node is ToxinPool:
			pools.append((node as ToxinPool).surface_rect())
		elif node is MovingPlatform:
			var m := node as MovingPlatform
			var a := _to_global(m, m.start_position())
			var b := _to_global(m, m.end_position())
			decks.append(Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(b.x - a.x) + m.width, absf(b.y - a.y) + MovingPlatform.WORLD))
		elif node is HookAnchor:
			anchors.append((node as Node2D).global_position)
	for i in range(line.size() - 1):
		var left: TopSeg = line[i]
		var right: TopSeg = line[i + 1]
		if right.x0 <= left.x1:
			continue
		var gap := right.x0 - left.x1
		if gap <= DROP_GAP_MAX:
			continue
		var covered := false
		for r in pools:
			if r.position.x <= left.x1 + 8.0 and r.end.x >= right.x0 - 8.0:
				covered = true
		for r in decks:
			if r.position.x < right.x0 - 8.0 and r.end.x > left.x1 + 8.0 and r.position.y >= line_y - 48.0 and r.position.y <= line_y + 140.0:
				covered = true
		# Any ledge within one jump / drop of the line that pokes into the gap
		# bridges it (pit beds, gear perches, stepping stones).
		for seg in tops:
			if covered:
				break
			if seg == left or seg == right:
				continue
			if seg.x1 <= left.x1 + 4.0 or seg.x0 >= right.x0 - 4.0:
				continue
			if seg.y < line_y - JUMP_RISE_MAX - 8.0 or seg.y > line_y + DROP_GAP_MAX:
				continue
			covered = true
		for an in anchors:
			if an.y < line_y - 24.0 and an.y > line_y - HOOK_REACH and an.x > left.x1 - HOOK_LAND_X and an.x < right.x0 + HOOK_LAND_X:
				covered = true
		if not covered:
			problems.append("main floor line at y=%.0f breaks between %s (ends %.0f) and %s (starts %.0f): %.0fpx gap with no pit, lift or hook to cross" % [line_y, left.owner_name, left.x1, right.owner_name, right.x0, gap])


## Anything outside the camera limits or below the world floor.
static func _check_bounds(_host: Node, entries: Array[Dictionary], limits: Rect2, problems: Array[String]) -> void:
	var x0 := -INF
	var x1 := INF
	var y0 := -INF
	if limits.has_area():
		x0 = limits.position.x - BOUNDS_PAD
		x1 = limits.end.x + BOUNDS_PAD
		y0 = limits.position.y - 320.0
	for e in entries:
		var r := e["rect"] as Rect2
		if r.position.x < x0 or r.end.x > x1 or r.position.y < y0 or r.end.y > WORLD_FLOOR_MAX:
			problems.append("%s at %s drifts outside the level bounds" % [e["name"], r])
	for node in _descendants(_host):
		if not (node is Interactable or node is CorePickup or node is EnemyBase or node is TorchLight):
			continue
		if node is ToxinPool or node is HookAnchor or node is AtmosphereZone:
			continue
		var n2 := node as Node2D
		if n2.global_position.x < x0 or n2.global_position.x > x1:
			problems.append("%s (%s) at x=%.0f is outside the camera limits" % [node.name, _cls(node), n2.global_position.x])
		elif n2.global_position.y < y0 or n2.global_position.y > WORLD_FLOOR_MAX:
			problems.append("%s (%s) at y=%.0f is outside the level bounds" % [node.name, _cls(node), n2.global_position.y])


## The exit door must not kiss the east wall (docs: leave >= 80px).
static func _check_exit_clearance(_host: Node, limits: Rect2, problems: Array[String]) -> void:
	if not limits.has_area():
		return
	for node in _descendants(_host):
		if not node is LevelExit:
			continue
		var x := (node as Node2D).global_position.x
		if x > limits.end.x - EXIT_WALL_CLEAR:
			problems.append("exit %s at x=%.0f hugs the east wall (limit %.0f, need >= %.0fpx clear)" % [node.name, x, limits.end.x, EXIT_WALL_CLEAR])
		if x < limits.position.x + EXIT_WALL_CLEAR:
			problems.append("exit %s at x=%.0f hugs the west wall (limit %.0f, need >= %.0fpx clear)" % [node.name, x, limits.position.x, EXIT_WALL_CLEAR])


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

## Solid collision boxes with names, so a buried top can blame its blocker.
## kind: "solid" / "lift" (deck at one travel end) / "gear".
static func solid_entries(host: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in _descendants(host):
		if node is SolidPlatform:
			var p := node as SolidPlatform
			out.append({"rect": Rect2(p.global_position, p.size), "name": String(p.name), "kind": "solid"})
		elif node is MovingPlatform:
			var m := node as MovingPlatform
			var deck := Vector2(m.width, MovingPlatform.WORLD)
			var a := _to_global(m, m.start_position())
			var b := _to_global(m, m.end_position())
			out.append({"rect": Rect2(a, deck), "name": String(m.name), "kind": "lift"})
			out.append({"rect": Rect2(b, deck), "name": String(m.name), "kind": "lift"})
		elif node is GearPlatform:
			var g := node as GearPlatform
			var sz := Vector2(g.radius * 2.0, g.radius * 2.0)
			out.append({"rect": Rect2(g.global_position - Vector2(g.radius, g.radius), sz), "name": String(g.name), "kind": "gear"})
	return out


## Rough world-space AABB of a node from its Sprite2D descendants (audit only).
static func node_aabb(node: Node2D) -> Rect2:
	var box := Rect2()
	var any := false
	for c in _descendants(node):
		if c is Sprite2D:
			var s := c as Sprite2D
			var r := s.get_rect()
			var xf := s.get_global_transform()
			for p in [xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y)]:
				box = Rect2(p, Vector2.ZERO) if not any else box.expand(p)
				any = true
	if not any:
		box = Rect2(node.global_position - Vector2(8, 8), Vector2(16, 16))
	return box


## Nominal body box for a grounded enemy (feet at the origin). Frame-animated
## canvases are 100px+ wide; the visible foe is not, and overlaps must be
## judged on the foe, not the sheet.
static func _enemy_box(node: Node2D) -> Rect2:
	return Rect2(node.global_position - Vector2(14.0, 48.0), Vector2(28.0, 48.0))


static func _overlap(a: Rect2, b: Rect2) -> Vector2:
	var x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	return Vector2(maxf(x, 0.0), maxf(y, 0.0))


static func _point_in_entries(entries: Array[Dictionary], point: Vector2, skip_name: String = "") -> String:
	for e in entries:
		if e["name"] == skip_name:
			continue
		var r := e["rect"] as Rect2
		if r.grow(-1.0).has_point(point):
			return String(e["name"])
	return ""


## Name of the first solid containing the point ("" when free).
static func _entry_at(entries: Array[Dictionary], point: Vector2) -> String:
	for e in entries:
		var r := e["rect"] as Rect2
		if r.grow(-1.0).has_point(point):
			return String(e["name"])
	return ""


static func _entry_rect(entries: Array[Dictionary], name: String) -> Rect2:
	for e in entries:
		if e["name"] == name:
			return e["rect"] as Rect2
	return Rect2()


static func _same_owner(seg: TopSeg, entry_name: String) -> bool:
	if seg.owner_name == entry_name:
		return true
	return seg.owner_name.contains("@") and seg.owner_name.get_slice("@", 0) == entry_name

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
