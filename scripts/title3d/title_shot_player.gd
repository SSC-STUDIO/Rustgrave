class_name TitleShotPlayer
extends Node
## 标题运镜播放器：把 TitleShots 的纯数据按固定步长推进，发射事件并驱动
## 相机采样。没有 Tween、没有 Timer、没有随机数——同样的输入序列得到同样的
## pos/target/fov/事件顺序，headless 测试可以直接喂固定 delta。
##
## 职责边界：
##   - 只产生"这一帧镜头应该在哪"（sample_now）和事件；写相机 / 写
##     PixelStage.set_camera_offset 由调用方做（TitleWorld3D 已经在做）。
##   - intro 结束自动接 idle（auto_idle_after_intro），idle 里 25s 无输入自动进
##     attract 慢环绕；notify_input() 打断 attract 回 idle 并重置计时。
##   - 循环镜头（idle / attract）到 duration 时回到 0 继续；一次性镜头
##     （intro / confirm / quit）停在末态并发出 finished。
##
## 每帧用法：
##   player.advance(dt)                       # 同时由 TitleWorld3D 推进 rig.advance(dt)
##   var sample := player.sample_now()        # {pos, target, roll, fov, snap, ...}
##   var subpixel := TitleShots.apply_to_camera(sample, rig)

signal event_fired(kind: StringName, payload: Dictionary)
## 一个新镜头开始（含循环重播与自动接 idle）。
signal shot_started(id: StringName)
## 一次性镜头播完（每段只发一次）。
signal finished()

const Shots := preload("res://scripts/title3d/title_shots.gd")

const INTRO := &"intro"
const IDLE := &"idle"
const ATTRACT := &"attract"

## 存档变体（cold / journey / act1..act4 / give / keep / snuff）。
## TitleShots 用它挑退场灯数等变体相关的数值；可随时改，下一次 play() 生效。
var variant := &"cold"
## 实际亮着的吊灯数，-1 = 让 TitleShots 按 variant 推断。集成方应在拿到
## TitleState 的 state 后调用 configure_state()（或直接写这个字段）。
var lit_lanterns := -1
## idle 多久没输入后进入 attract（秒）。0 或 auto_attract=false 时关闭。
var attract_after := Shots.ATTRACT_IDLE_TIMEOUT
var auto_attract := true
## intro 播完自动接 idle，避免标题停在开屏末态。
var auto_idle_after_intro := true

var _id: StringName = &""
var _data: Dictionary = {}
var _t := 0.0
var _fired := 0
var _finished := false
var _idle_clock := 0.0


## 播一个镜头。未知 id 只警告、不改变当前镜头。
func play(id: StringName) -> void:
	var data := Shots.shot(id, variant, lit_lanterns)
	if data.is_empty():
		push_warning("TitleShotPlayer: unknown shot '%s'" % String(id))
		return
	_id = id
	_data = data
	_t = 0.0
	_fired = 0
	_finished = false
	_idle_clock = 0.0
	shot_started.emit(_id)


## 从标题状态字典同步变体 / 亮灯数（TitleWorld3D 的 state）。
func configure_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	variant = StringName(String(state.get("variant", variant)))
	if state.has("lit"):
		lit_lanterns = int(state.get("lit", lit_lanterns))


## 推进 dt 秒：触发到点的事件、循环或结束、跑 idle/attract 计时。
func advance(dt: float) -> void:
	var step := maxf(dt, 0.0)
	if step <= 0.0 or _data.is_empty():
		return
	var dur := duration()
	if dur <= 0.0:
		_fire_due()
		_finish()
		return
	var was_id := _id
	_t += step
	if _t >= dur:
		if Shots.loops(_data):
			_t = fmod(_t, dur)
			_fired = 0
			_fire_due()
		else:
			_t = dur
			_fire_due()
			_finish()
			return
	else:
		_fire_due()
	if was_id == IDLE and auto_attract and attract_after > 0.0:
		_idle_clock += step
		if _idle_clock >= attract_after:
			play(ATTRACT)


## 跳过当前镜头：落到末态、把还没发的事件一次性补发（保持原顺序），再发
## finished。对同一个镜头只发一次 / 重复调用无副作用（intro 跳过后按
## auto_idle_after_intro 自动接上的 idle 是一个新镜头）。
func skip() -> void:
	if _data.is_empty() or _finished:
		return
	_t = duration()
	_fire_due()
	_finish()


## 任意输入（键/鼠标/手柄）打断 attract 并重置 idle 计时；其余镜头只重置计时。
func notify_input() -> void:
	_idle_clock = 0.0
	if _id == ATTRACT:
		play(IDLE)


## 当前镜头这一帧的采样，附带播放器元数据：
## {pos, target, roll, fov, snap, events, id, time, duration, progress, finished, loop}
func sample_now() -> Dictionary:
	if _data.is_empty():
		var hero := Shots.hero_pose()
		return {
			"pos": hero.get("pos", Vector3.ZERO),
			"target": hero.get("target", Vector3.ZERO),
			"roll": float(hero.get("roll", 0.0)),
			"fov": float(hero.get("fov", Shots.FOV_DEG)),
			"snap": false,
			"events": [],
			"id": &"",
			"time": 0.0,
			"duration": 0.0,
			"progress": 0.0,
			"finished": true,
			"loop": false,
		}
	var result := Shots.sample(_data, _t)
	result["id"] = _id
	result["time"] = _t
	result["duration"] = duration()
	result["progress"] = progress()
	result["finished"] = _finished
	result["loop"] = Shots.loops(_data)
	return result


func current_id() -> StringName:
	return _id


## 一次性镜头播完 / 跳过之后为 false；循环镜头永远为 true。
func playing() -> bool:
	return not _data.is_empty() and not _finished


func duration() -> float:
	return Shots.duration(_data)


## 镜头内进度 0..1。
func progress() -> float:
	var dur := duration()
	return 0.0 if dur <= 0.0 else clampf(_t / dur, 0.0, 1.0)


func time() -> float:
	return _t


## idle 计时（秒，进入 idle / 输入后清零；attract 里不再增长）。
func idle_clock() -> float:
	return _idle_clock


## 当前镜头数据（调试 / 测试用，不要改它）。
func shot_data() -> Dictionary:
	return _data


func _fire_due() -> void:
	var events: Array = _data.get("events", [])
	while _fired < events.size():
		var event: Dictionary = events[_fired]
		if float(event.get("at", 0.0)) > _t + 1e-9:
			break
		_fired += 1
		var payload = event.get("payload", {})
		event_fired.emit(StringName(event.get("kind", &"")), payload)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var was_id := _id
	finished.emit()
	if auto_idle_after_intro and was_id == INTRO:
		play(IDLE)
