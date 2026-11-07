class_name TitleShots
extends RefCounted
## 3D 标题的运镜镜头表：纯数据 + 静态纯函数，没有节点、没有 Tween、没有随机数。
##
## 一个镜头是一本字典：
##   {id, variant, duration, loop, path, keys, orbit, events}
## - path = &"keys"（默认）：在 keys 之间按 smoothstep 缓动插值。每个 key 是
##   {t, pos, target, roll, fov, snap, ease}。
## - path = &"orbit"：绕 orbit.center 的慢速正弦环绕（attract），t=0 与 t=duration
##   都恰好是英雄机位，循环无缝。
## 事件是 {kind: StringName, at: float, payload: Dictionary}，按 at 升序排列，
## 由 TitleShotPlayer 保证只发一次。sample() 把整张事件表原样放在结果的 events
## 里（调试/上层检查用），不改动它。
##
## 坐标取自 scripts/title3d/kit/layout.gd（TitleLayout，纯常量，运行时 load 兜底），
## 只要那份契约在，标题就会跟着大厅布局走；布局还没落盘时用本文件顶部的
## FALLBACK_* 常量（0,4.3,0 取景目标 / (3.5,15,-12) 天窗），两边数值一致。
##
## 时序沿用 2D 标题屏 scripts/ui/title_screen.gd：
##   BOOT_FADE=0.5、LOGO_AT=1.60、LOGO_TIME=0.80、MENU_AT=1.95、开屏 2.8s、
##   推镜 1.6s、吊灯从 0.30s 起每 0.16s 一盏、确认推进 5 纹素 / 0.55s、
##   退场每盏灯 0.2s。

const LAYOUT_PATH := "res://scripts/title3d/kit/layout.gd"

# ---------------------------------------------------------------- 纹素契约 ----
const OUTPUT_ROWS := 360
const OUTPUT_COLUMNS := 640
const VIEW_HEIGHT := 13.5
const FOV_DEG := 30.0

# ------------------------------------------------------------ 开屏时序常量 ----
const INTRO_DURATION := 2.8
const BOOT_FADE := 0.5
const LOGO_AT := 1.60
const LOGO_TIME := 0.80
const MENU_AT := 1.95
const MENU_STAGGER := 0.07
const MENU_LAND := 0.26
const DOLLY_TIME := 1.6
const LANTERN_WAVE_START := 0.30
const LANTERN_WAVE_STAGGER := 0.16
const LANTERN_COUNT := 14
## 开屏俯冲起点的广角（落位回 FOV_DEG）。
const INTRO_AERIAL_FOV := 42.0
const AERIAL_DROP := 0.8

# ------------------------------------------------------------ 其余镜头常量 ----
const HERO_YAW_DEG := 6.0
const HERO_PITCH_DEG := 4.0
const IDLE_DURATION := 7.0
const ATTRACT_DURATION := 20.0
const ATTRACT_ORBIT_DEG := 6.0
const ATTRACT_IDLE_TIMEOUT := 25.0
const CONFIRM_DURATION := 0.55
const CONFIRM_PUSH_TEXELS := 5.0
const QUIT_PULLBACK := 0.12
const LANTERN_OUT_STAGGER := 0.2

# ------------------------------------------------------------ 布局兜底常量 ----
## 与 scripts/title3d/kit/layout.gd 的契约一致；layout 读不到时用它。
const FALLBACK_CAMERA_TARGET := Vector3(0.0, 4.3, 0.0)
const FALLBACK_KNIGHT_POS := Vector3(0.0, 0.0, 0.0)
const FALLBACK_SKYLIGHT_CENTER := Vector3(3.5, 15.0, -12.0)
const FALLBACK_AERIAL_TARGET := Vector3(-2.3, 0.05, 0.6)
const FALLBACK_ROOF_Y := 15.0

static var _layout_script: GDScript = null
static var _layout_checked := false


# ------------------------------------------------------------------- 镜头表 ----

## 全部镜头 id，按开屏到退场的顺序。
static func ids() -> PackedStringArray:
	return PackedStringArray(["intro", "idle", "attract", "confirm", "quit"])


## 取一个镜头的数据。未知 id 返回空字典（播放器会忽略并警告）。
## `variant`：cold / journey / act1..act4 / give / keep / snuff（退场时长用）。
## `lanterns`：退场要逐盏吹灭的灯数；-1 = 按 variant 推断（见 _quit_lanterns）。
static func shot(id: StringName, variant := &"cold", lanterns := -1) -> Dictionary:
	match String(id):
		"intro":
			return _intro_shot(variant)
		"idle":
			return _idle_shot(variant)
		"attract":
			return _attract_shot(variant)
		"confirm":
			return _confirm_shot(variant)
		"quit":
			return _quit_shot(variant, lanterns)
	return {}


## 镜头时长（秒）。空镜头为 0。
static func duration(s: Dictionary) -> float:
	return maxf(float(s.get("duration", 0.0)), 0.0)


## 镜头是否循环（idle / attract）。
static func loops(s: Dictionary) -> bool:
	return bool(s.get("loop", false))


## 输出纹素在焦平面（z=0）上的世界尺寸（米）。
static func world_per_texel() -> float:
	return VIEW_HEIGHT / float(OUTPUT_ROWS)


## 取景高度 13.5m、FOV 30° 的相机到焦平面距离（米）。
static func focus_distance() -> float:
	return VIEW_HEIGHT / (2.0 * tan(deg_to_rad(FOV_DEG) * 0.5))


# ---------------------------------------------------------------- 英雄机位 ----

## 骑士脚底点（焦平面 z=0 上，TitleLayout.KNIGHT_POS）。
static func hero_feet() -> Vector3:
	return _layout_vec3(&"KNIGHT_POS", FALLBACK_KNIGHT_POS)


## 相机取景目标（TitleLayout.CAMERA_TARGET：(0,4.3,0)）。
static func hero_target() -> Vector3:
	return _layout_vec3(&"CAMERA_TARGET", FALLBACK_CAMERA_TARGET)


## 桥面英雄机位（idle/confirm/quit 的基准）：在焦平面上距目标 focus_distance，
## 从 +Z 侧略偏右（yaw 6°）略高（pitch 4°）看过去，3/4 角度给透视纵深。
static func hero_pose() -> Dictionary:
	return _hero_pose_from(hero_target(), HERO_YAW_DEG, HERO_PITCH_DEG, focus_distance())


## 开屏起点：天窗豁口下方一点，沿光柱俯视大厅，广角。
static func aerial_pose() -> Dictionary:
	var sky := _layout_vec3(&"SKYLIGHT_CENTER", FALLBACK_SKYLIGHT_CENTER)
	var roof := _layout_float(&"ROOF_Y", FALLBACK_ROOF_Y)
	var pos := Vector3(sky.x, minf(sky.y - AERIAL_DROP, roof - AERIAL_DROP), sky.z)
	var target := _layout_vec3(&"BEAM_TO", FALLBACK_AERIAL_TARGET)
	return _pose(pos, target, INTRO_AERIAL_FOV, false)


## 确认入场的推进机位：从英雄机位朝目标推进 5 个输出纹素。
static func confirm_pose() -> Dictionary:
	var hero := hero_pose()
	var target: Vector3 = hero["target"]
	var pos: Vector3 = hero["pos"]
	return _pose(pos + (target - pos).normalized() * (CONFIRM_PUSH_TEXELS * world_per_texel()),
			target, FOV_DEG, true)


## 退场机位：沿视轴后退 12%，其余不动（骑士剪影留在画面中心）。
static func quit_pose() -> Dictionary:
	var hero := hero_pose()
	var target: Vector3 = hero["target"]
	var pos: Vector3 = hero["pos"]
	return _pose(target + (pos - target) * (1.0 + QUIT_PULLBACK), target, FOV_DEG, true)


# ---------------------------------------------------------------- 纯采样 ----

## 在时刻 t 采样镜头（t 超出 [0, duration] 时钳制）。
## 返回 {pos, target, roll, fov, snap, events}。
static func sample(s: Dictionary, t: float) -> Dictionary:
	var dur := duration(s)
	var tt := clampf(t, 0.0, dur)
	if String(s.get("path", &"keys")) == "orbit":
		return _sample_orbit(s, tt, dur)
	return _sample_keys(s, tt)


## 采样结果 -> 相机 Transform3D（-Z 指向 target，roll 绕视线）。
static func pose(s: Dictionary) -> Transform3D:
	var pos: Vector3 = s.get("pos", Vector3.ZERO)
	var target: Vector3 = s.get("target", pos + Vector3.FORWARD)
	var look := target - pos
	if look.length_squared() < 1e-10:
		look = Vector3.FORWARD
	var basis := Basis.looking_at(look, Vector3.UP)
	var roll := float(s.get("roll", 0.0))
	if not is_zero_approx(roll):
		basis = basis * Basis(Vector3.BACK, roll)
	return Transform3D(basis, pos)


## 采样 -> 驱动相机 rig 一步：设置 fov、应用位姿，返回亚纹素偏移。
## 集成方每帧只需要这一行：
##   var sub := TitleShots.apply_to_camera(player.sample_now(), rig)
static func apply_to_camera(s: Dictionary, camera) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	camera.fov = clampf(float(s.get("fov", FOV_DEG)), 1.0, 179.0)
	return camera.apply_pose(pose(s), bool(s.get("snap", true)))


## 到 t 为止已经应当触发的事件（含 at == t）。
static func events_until(s: Dictionary, t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in s.get("events", []):
		if float(event.get("at", 0.0)) <= t + 1e-9:
			out.append(event)
	return out


## [from_t, to_t) 内应当触发的事件（供播放器/测试核对）。
static func events_between(s: Dictionary, from_t: float, to_t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in s.get("events", []):
		var at := float(event.get("at", 0.0))
		if at > from_t + 1e-9 and at <= to_t + 1e-9:
			out.append(event)
	return out


# ------------------------------------------------------------ 镜头构造器 ----

static func _intro_shot(variant: StringName) -> Dictionary:
	var aerial := aerial_pose()
	var hero := hero_pose()
	var keys := [
		_key(aerial, 0.0),
		_key(hero, DOLLY_TIME),
		_key(hero, INTRO_DURATION),
	]
	return {
		"id": &"intro",
		"variant": variant,
		"duration": INTRO_DURATION,
		"loop": false,
		"path": &"keys",
		"ease": &"smoothstep",
		"keys": keys,
		"events": _intro_events(),
	}


static func _idle_shot(variant: StringName) -> Dictionary:
	return {
		"id": &"idle",
		"variant": variant,
		"duration": IDLE_DURATION,
		"loop": true,
		"path": &"keys",
		"ease": &"smoothstep",
		"keys": [_key(hero_pose(), 0.0)],
		"events": [],
	}


static func _attract_shot(variant: StringName) -> Dictionary:
	return {
		"id": &"attract",
		"variant": variant,
		"duration": ATTRACT_DURATION,
		"loop": true,
		"path": &"orbit",
		"keys": [],
		"orbit": {
			"center": hero_target(),
			"distance": focus_distance(),
			"yaw_deg": HERO_YAW_DEG,
			"pitch_deg": HERO_PITCH_DEG,
			"amplitude_deg": ATTRACT_ORBIT_DEG,
			"fov": FOV_DEG,
			"roll": 0.0,
		},
		"events": [],
	}


static func _confirm_shot(variant: StringName) -> Dictionary:
	var events: Array = [
		_event(&"flash", 0.0, {"strength": 1.0, "source": &"confirm"}),
		_event(&"furnace_surge", 0.10, {"strength": 1.0}),
	]
	return {
		"id": &"confirm",
		"variant": variant,
		"duration": CONFIRM_DURATION,
		"loop": false,
		"path": &"keys",
		"ease": &"smoothstep",
		"keys": [_key(hero_pose(), 0.0), _key(confirm_pose(), CONFIRM_DURATION)],
		"events": events,
	}


static func _quit_shot(variant: StringName, lanterns: int) -> Dictionary:
	var count := _quit_lanterns(variant, lanterns)
	# 灯数 x 0.2s；一盏灯都没有时也给一拍（对齐 2D TitleWorld.quit_out 的 0.2s 兜底）。
	var dur := float(maxi(count, 1)) * LANTERN_OUT_STAGGER
	var events: Array = [
		_event(&"grade_to_dark", 0.0, {"duration": dur, "target": &"dark"}),
	]
	for i in count:
		events.append(_event(&"lantern_out", LANTERN_OUT_STAGGER * float(i),
				{"index": i, "lanterns": count}))
	return {
		"id": &"quit",
		"variant": variant,
		"duration": dur,
		"loop": false,
		"path": &"keys",
		"ease": &"smoothstep",
		"keys": [_key(hero_pose(), 0.0), _key(quit_pose(), dur)],
		"events": _sorted_events(events),
	}


## 退场逐盏吹灭的灯数：显式值优先，否则按存档变体推断。
static func _quit_lanterns(variant: StringName, lanterns: int) -> int:
	if lanterns >= 0:
		return clampi(lanterns, 0, LANTERN_COUNT)
	match String(variant):
		"give", "keep", "true_break", "journey", "act1", "act2", "act3", "act4":
			return LANTERN_COUNT
	return 0


static func _intro_events() -> Array:
	var events: Array = []
	for i in LANTERN_COUNT:
		events.append(_event(&"lantern_wave",
				LANTERN_WAVE_START + LANTERN_WAVE_STAGGER * float(i),
				{"index": i, "lanterns": LANTERN_COUNT, "stagger": LANTERN_WAVE_STAGGER}))
	events.append(_event(&"hammer_strike", LOGO_AT, {"force": 1.0}))
	events.append(_event(&"logo_forge", LOGO_AT, {"duration": LOGO_TIME}))
	events.append(_event(&"menu_reveal", MENU_AT, {"stagger": MENU_STAGGER, "land": MENU_LAND}))
	# 吊灯逐盏点亮会跨过 1.60 / 1.95，事件表必须单调递增：稳定排序，同刻保持
	# 插入顺序（锤击先于字标锻造）。
	return _sorted_events(events)


## 稳定按 at 升序排序事件（播放器按表顺序发事件，表必须单调）。
static func _sorted_events(events: Array) -> Array:
	var sorted: Array = []
	for event in events:
		var at := float(event.get("at", 0.0))
		var index := sorted.size()
		for i in sorted.size():
			if at < float(sorted[i].get("at", 0.0)) - 1e-12:
				index = i
				break
		sorted.insert(index, event)
	return sorted


# ---------------------------------------------------------------- 采样实现 ----

static func _sample_keys(s: Dictionary, tt: float) -> Dictionary:
	var keys: Array = s.get("keys", [])
	var events: Array = s.get("events", [])
	if keys.is_empty():
		return {"pos": Vector3.ZERO, "target": Vector3.ZERO, "roll": 0.0, "fov": FOV_DEG,
				"snap": true, "events": events}
	if keys.size() == 1 or tt <= float(keys[0].get("t", 0.0)):
		return _sample_of_key(keys[0], events)
	var last: Dictionary = keys[keys.size() - 1]
	if tt >= float(last.get("t", 0.0)):
		return _sample_of_key(last, events)
	for i in range(keys.size() - 1):
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		var ta := float(a.get("t", 0.0))
		var tb := float(b.get("t", 0.0))
		if tt < ta or tt > tb:
			continue
		var u := 0.0 if tb <= ta else (tt - ta) / (tb - ta)
		var eased := ease01(u, StringName(a.get("ease", s.get("ease", &"smoothstep"))))
		var pos: Vector3 = (a.get("pos", Vector3.ZERO) as Vector3).lerp(b.get("pos", Vector3.ZERO), eased)
		var target: Vector3 = (a.get("target", Vector3.ZERO) as Vector3).lerp(
				b.get("target", Vector3.ZERO), eased)
		return {
			"pos": pos,
			"target": target,
			"roll": lerpf(float(a.get("roll", 0.0)), float(b.get("roll", 0.0)), eased),
			"fov": lerpf(float(a.get("fov", FOV_DEG)), float(b.get("fov", FOV_DEG)), eased),
			# snap 在段的中间切换：前半段仍是快速运动（不吸附），后半段落位（吸附）。
			"snap": bool(a.get("snap", true)) if u < 0.5 else bool(b.get("snap", true)),
			"events": events,
		}
	return _sample_of_key(last, events)


static func _sample_orbit(s: Dictionary, tt: float, dur: float) -> Dictionary:
	var orbit: Dictionary = s.get("orbit", {})
	var center: Vector3 = orbit.get("center", hero_target())
	var distance := float(orbit.get("distance", focus_distance()))
	var yaw := deg_to_rad(float(orbit.get("yaw_deg", HERO_YAW_DEG)))
	var pitch := deg_to_rad(float(orbit.get("pitch_deg", HERO_PITCH_DEG)))
	var amplitude := deg_to_rad(float(orbit.get("amplitude_deg", ATTRACT_ORBIT_DEG)))
	var phase := 0.0 if dur <= 0.0 else TAU * tt / dur
	var azimuth := yaw + amplitude * sin(phase)
	var dir := Vector3(sin(azimuth) * cos(pitch), sin(pitch), cos(azimuth) * cos(pitch))
	return {
		"pos": center + dir * distance,
		"target": center,
		"roll": float(orbit.get("roll", 0.0)),
		"fov": float(orbit.get("fov", FOV_DEG)),
		"snap": true,
		"events": s.get("events", []),
	}


# ---------------------------------------------------------------- 小工具 ----

## 缓动：默认 smoothstep（3u²-2u³）；linear / in / out 可选。
static func ease01(u: float, kind: StringName = &"smoothstep") -> float:
	var x := clampf(u, 0.0, 1.0)
	match String(kind):
		"linear":
			return x
		"in":
			return x * x
		"out":
			return 1.0 - (1.0 - x) * (1.0 - x)
	return x * x * (3.0 - 2.0 * x)


static func _hero_pose_from(target: Vector3, yaw_deg: float, pitch_deg: float,
		distance: float) -> Dictionary:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return _pose(target + dir * distance, target, FOV_DEG, true)


static func _pose(pos: Vector3, target: Vector3, fov: float, snap: bool, roll := 0.0,
		ease := &"smoothstep") -> Dictionary:
	return {"pos": pos, "target": target, "roll": roll, "fov": fov, "snap": snap, "ease": ease}


static func _key(pose_dict: Dictionary, at: float) -> Dictionary:
	var key := pose_dict.duplicate()
	key["t"] = at
	return key


static func _sample_of_key(key: Dictionary, events: Array) -> Dictionary:
	return {
		"pos": key.get("pos", Vector3.ZERO),
		"target": key.get("target", Vector3.ZERO),
		"roll": float(key.get("roll", 0.0)),
		"fov": float(key.get("fov", FOV_DEG)),
		"snap": bool(key.get("snap", true)),
		"events": events,
	}


static func _event(kind: StringName, at: float, payload := {}) -> Dictionary:
	return {"kind": kind, "at": at, "payload": payload}


# ------------------------------------------------------------- 布局读取 ----

## scripts/title3d/kit/layout.gd（TitleLayout，纯常量）。读不到时返回 null。
static func layout_script() -> GDScript:
	if not _layout_checked:
		_layout_checked = true
		if ResourceLoader.exists(LAYOUT_PATH):
			_layout_script = load(LAYOUT_PATH) as GDScript
	return _layout_script


## 读布局常量；缺失或类型不对时用兜底值。
static func layout_value(name: StringName, fallback):
	var script := layout_script()
	if script == null:
		return fallback
	var constants: Dictionary = script.get_script_constant_map()
	for key in constants.keys():
		if String(key) == String(name):
			return constants[key]
	return fallback


static func _layout_vec3(name: StringName, fallback: Vector3) -> Vector3:
	var value = layout_value(name, fallback)
	return value if value is Vector3 else fallback


static func _layout_float(name: StringName, fallback: float) -> float:
	var value = layout_value(name, fallback)
	return float(value) if value is float or value is int else fallback
