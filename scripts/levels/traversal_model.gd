class_name TraversalModel
extends RefCounted
## 玩家"真的跳得过去吗"的数值来源。
##
## 关卡体检（`LevelSanity`）原先手写 JUMP_RISE_MAX / JUMP_GAP_MAX 两个魔数，
## 和 `PlayerController` 的实际手感各说各话。这里把包络**从控制器导出值算出来**：
## 读 `player_controller.gd` 的 max_speed / jump_velocity / 重力倍率，加上
## `Player.tscn` 的碰撞盒尺寸，用和物理帧同频的欧拉积分跑一遍跳跃，
## 得到真实的最大上升高度、滞空时间、同高横跨上限与下落补偿。
##
## 除了包络，这里还提供两个几何判定：
##   · `can_hop()` —— 整条跳跃弧线扫过实体没有（不是只看 x 间距）
##   · `headroom()` / `headroom_ok()` —— 站上去头顶够不够 26px
## 两者都只读几何，不改任何节点。

# Player.tscn: CollisionShape2D 的 RectangleShape2D size = Vector2(14, 26)，
# 且 CollisionShape2D 在 position = (0, -13)，所以节点原点就是脚底。
const PLAYER_HALF := 7.0
const PLAYER_HEIGHT := 26.0
const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const PLAYER_CONTROLLER := "res://scripts/player/player_controller.gd"

## 起跳时脚掌离台面边缘留的余量：圆心顶到边缘 +7 时只剩 1px 接触，
## 物理上会掉；留 4px 让"起跳点"是个真站得住的位置。
const EDGE_MARGIN := 4.0
## 头顶净空余量：26px 身高之外再留 2px，落点不会因为帧抖动卡在天花板上。
const HEAD_MARGIN := 2.0
## 弧线积分的物理步长与最长飞行时间（秒）。
const STEP := 1.0 / 60.0
const MAX_FLIGHT := 2.5
## 起跳点往台面里退这几档，逐个试（贴脸墙时前面几档会被丢掉）。
const BACKOFFS: Array[float] = [8.0, 16.0, 24.0, 32.0]
## 掉落超过这个深度就当作掉出关卡，不再继续积分。
const FALL_LIMIT := 640.0

static var _envelope: Dictionary = {}


## 输出：gravity / max_speed / jump_velocity / apex_window / apex_scale /
## fall_scale / max_fall_speed / rise / air_time / gap_level / fall_speed_per_px
static func envelope() -> Dictionary:
	if not _envelope.is_empty():
		return _envelope
	var values := _controller_values()
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var vy: float = float(values["jump_velocity"])
	var feet := 0.0
	var t := 0.0
	var apex := 0.0
	var air := MAX_FLIGHT
	# 起跳后一直积到落回同一高度（脚底 y 回到 0）。
	while t < MAX_FLIGHT:
		var scale := 1.0
		if absf(vy) < float(values["apex_window"]):
			scale = float(values["apex_gravity_scale"])
		elif vy > 0.0:
			scale = float(values["fall_gravity_scale"])
		vy += gravity * scale * STEP
		if vy > float(values["max_fall_speed"]):
			vy = float(values["max_fall_speed"])
		feet += vy * STEP
		t += STEP
		apex = minf(apex, feet)
		if feet >= 0.0 and t > 0.1:
			air = t
			break
	_envelope = {
		"gravity": gravity,
		"max_speed": float(values["max_speed"]),
		"jump_velocity": float(values["jump_velocity"]),
		"rise": -apex,
		"air_time": air,
		# 同高横跨：滞空 × 全速，加上起跳侧 3px 余量与落脚侧整个半宽。
		"gap_level": float(values["max_speed"]) * air + (PLAYER_HALF - EDGE_MARGIN) + PLAYER_HALF,
	}
	_envelope["fall_speed_per_px"] = 0.0
	return _envelope


## 真实最大上升高度（约 36.7px）。
static func max_rise() -> float:
	return float(envelope()["rise"])


## 同高、满速起跳时的最大边缘到边缘间距（约 66px）。
static func max_gap_level() -> float:
	return float(envelope()["gap_level"])


## 比同高多掉 drop 像素时能多跨多远；从**起跳**算起（含上升段），
## 不然会算出一个比同高还短的假数字。
static func gap_for_drop(drop: float) -> float:
	if drop <= 0.0:
		return max_gap_level()
	var values := _controller_values()
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var vy: float = float(values["jump_velocity"])
	var feet := 0.0
	var t := 0.0
	while t < MAX_FLIGHT and feet < drop:
		var scale := 1.0
		if absf(vy) < float(values["apex_window"]):
			scale = float(values["apex_gravity_scale"])
		elif vy > 0.0:
			scale = float(values["fall_gravity_scale"])
		vy += gravity * scale * STEP
		if vy > float(values["max_fall_speed"]):
			vy = float(values["max_fall_speed"])
		feet += vy * STEP
		t += STEP
	return float(values["max_speed"]) * t + (PLAYER_HALF - EDGE_MARGIN) + PLAYER_HALF


## 跳跃弧线是否被实体挡住。`solids` 是实体包围盒（世界坐标）。
## 只要有一个起跳点能让整条弧线干净地落到 b 上就是真。
static func can_hop(a: LevelSanity.TopSeg, b: LevelSanity.TopSeg, solids: Array[Rect2]) -> bool:
	if b.y < a.y - max_rise():
		return false
	var dir := 1.0 if (b.x0 + b.x1) * 0.5 >= (a.x0 + a.x1) * 0.5 else -1.0
	# 起跳点从"最靠近 b 的边缘"起：贴着边缘跳最远，往里退只是为了躲开
	# 起跳瞬间就贴脸的墙；退 32px 足够，再往里只是白扔速度。
	var edge: float = a.x1 + PLAYER_HALF - EDGE_MARGIN if dir > 0.0 else a.x0 - PLAYER_HALF + EDGE_MARGIN
	var min_x := a.x0 + PLAYER_HALF - EDGE_MARGIN
	var max_x := a.x1 - PLAYER_HALF + EDGE_MARGIN
	var candidates: Array[float] = [edge]
	for back: float in BACKOFFS:
		var px: float = edge - dir * back
		if px >= min_x and px <= max_x:
			candidates.append(px)
	for from_x in candidates:
		if _arc_lands(from_x, a.y, dir, b, solids):
			return true
	return false


## 站上去头顶够不够。`solids` 里 y 上沿低于 top 的实体才算天花板。
static func headroom(solids: Array[Rect2], x0: float, x1: float, top: float) -> float:
	var best := 1000.0
	for r in solids:
		if r.end.y > top - 0.5:
			continue
		if r.end.x <= x0 or r.position.x >= x1:
			continue
		best = minf(best, top - r.end.y)
	return best


static func headroom_ok(solids: Array[Rect2], x0: float, x1: float, top: float) -> bool:
	return headroom(solids, x0, x1, top) >= PLAYER_HEIGHT + HEAD_MARGIN


## 从 (from_x, top) 起跳，按真实重力积分，落到 b 上且不撞实体就返回 true。
static func _arc_lands(from_x: float, top: float, dir: float, b: LevelSanity.TopSeg,
		solids: Array[Rect2]) -> bool:
	var values := _controller_values()
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var speed := float(values["max_speed"])
	var vy: float = float(values["jump_velocity"])
	var feet := top
	var x := from_x
	var t := 0.0
	var land_lo := b.x0 - PLAYER_HALF
	var land_hi := b.x1 + PLAYER_HALF
	while t < MAX_FLIGHT:
		var scale := 1.0
		if absf(vy) < float(values["apex_window"]):
			scale = float(values["apex_gravity_scale"])
		elif vy > 0.0:
			scale = float(values["fall_gravity_scale"])
		vy += gravity * scale * STEP
		if vy > float(values["max_fall_speed"]):
			vy = float(values["max_fall_speed"])
		feet += vy * STEP
		x += dir * speed * STEP
		t += STEP
		if feet > top + FALL_LIMIT:
			return false
		# 落到 b 上：脚下已经到/过上表面，且身体与 b 的台面有重叠。
		if vy > 0.0 and feet >= b.y and feet <= b.y + PLAYER_HEIGHT \
				and x >= land_lo and x <= land_hi:
			return true
		if _body_hits(solids, x, feet):
			return false
		if dir > 0.0 and x > land_hi:
			return false
		if dir < 0.0 and x < land_lo:
			return false
	return false


## 身体（14×26，脚底在 feet）扫过任何实体。
static func _body_hits(solids: Array[Rect2], x: float, feet: float) -> bool:
	var box := Rect2(x - PLAYER_HALF, feet - PLAYER_HEIGHT, PLAYER_HALF * 2.0, PLAYER_HEIGHT)
	box = box.grow(-1.0)
	for r in solids:
		if r.intersects(box):
			return true
	return false


static func _controller_values() -> Dictionary:
	var script := load(PLAYER_CONTROLLER) as GDScript
	if script == null or not script.can_instantiate():
		return _fallback_values()
	var probe: Node = script.new()
	var out := {
		"max_speed": float(probe.get("max_speed")),
		"jump_velocity": float(probe.get("jump_velocity")),
		"apex_window": float(probe.get("apex_window")),
		"apex_gravity_scale": float(probe.get("apex_gravity_scale")),
		"fall_gravity_scale": float(probe.get("fall_gravity_scale")),
		"max_fall_speed": float(probe.get("max_fall_speed")),
	}
	probe.free()
	if out["max_speed"] <= 0.0 or out["jump_velocity"] >= 0.0:
		return _fallback_values()
	return out


## 兜底：控制器读不到时也别让体检崩掉，用当前实测值。
static func _fallback_values() -> Dictionary:
	return {
		"max_speed": 108.0,
		"jump_velocity": -268.0,
		"apex_window": 16.0,
		"apex_gravity_scale": 0.62,
		"fall_gravity_scale": 1.85,
		"max_fall_speed": 420.0,
	}
