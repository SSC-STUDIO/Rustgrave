extends Node
## WorldClock autoload: cemetery day/night + weather + light energy.
## Publishes mood_tint / nest_light_* / moon_fill / indoor_fill. No Light nodes.
## Do not give this script a class_name — the autoload name is the API.
##
## Full cycle is 20 real minutes (day → night ≈ 10). Pause, Director playback,
## choice hold, fades, and the title menu freeze the clock so sky contrast
## never fights a fade or a pause overlay.

enum Phase { DAWN, DAY, DUSK, NIGHT }
## CLEAR is appended so saved integer weather ids stay valid.
enum Weather { HAZE, RAIN, FOG, EMBER_WIND, RUST_RAIN, CLEAR }
enum Zone { OUTDOORS, INDOORS }

signal phase_changed(phase: int)
signal weather_changed(weather: int)
signal zone_changed(zone: int)
signal clock_ticked(time_of_day: float, phase: int)
signal wind_changed(heading: float, speed: float)

## 20 min around the clock; 昼→夜 lands near the 8–12 min brief.
const CYCLE_SECONDS := 1200.0
const DEFAULT_TIME := 0.52
const TITLE_TIME := 0.56
const TICK_INTERVAL := 0.25
const WEATHER_HOLD_MIN := 50.0
const WEATHER_HOLD_MAX := 110.0
const BLEND_MIN := 3.0
const BLEND_MAX := 8.0

## Outdoor night is a cold corridor so WorldLight pools can carve.
## Floor stays above a black frame; HUD isolate keeps UI readable.
const NIGHT_TINT := Color(0.36, 0.34, 0.48)
const DAY_TINT := Color(0.82, 0.80, 0.88)
const DAWN_TINT := Color(0.78, 0.74, 0.86)
const DUSK_TINT := Color(0.70, 0.60, 0.68)
## Indoor: warmer than outdoor night. Readability comes from the warm pool.
const INDOOR_TINT := Color(0.66, 0.52, 0.42)
const RUST_RAIN_INTERVAL := 1.6
const RUST_RAIN_EXPOSE := 8.0
const BREEZE_BASE := 0.28
const INDOOR_WIND_FADE := 1.5
const HEADING_TURN := 42.0
## 局部天气区域进出时的交叉淡入：比换天快，走到漏雨的屋檐下要当场开始下。
const REGION_BLEND := 1.4
## 配方里的 hold 再小也要留一口气，否则每帧都在重掷天气。
const PROFILE_HOLD_MIN := 20.0

## 章节天气配方里可以出现的键。缺省项一律回落到全局逻辑，所以空配方 == 现状。
const PROFILE_KEYS := ["allowed", "weights", "hold", "intensity"]

var time_of_day: float = DEFAULT_TIME
var phase: int = Phase.DAY
var weather: int = Weather.HAZE
var previous_weather: int = Weather.HAZE
var weather_blend: float = 1.0
var zone: int = Zone.OUTDOORS
var menu_hold: bool = false
## Test-only multiplier; gameplay stays at 1.
var time_scale: float = 1.0
## -1 left / +1 right. Presentation nodes read wind_vector(), never sprites here.
var wind_heading: float = -1.0
var wind_speed: float = BREEZE_BASE
var gust: float = 1.0

## 本章天气配方（见 set_weather_profile）。空字典 == 沿用全局阶段权重表。
var profile: Dictionary = {}
## 生效天气三元组。`weather` / `previous_weather` / `weather_blend` 仍是基础态：
## 只由全局时钟和关卡 ambient() 写。局部区域改的是下面这三个，表现层一律读这三个。
var _weather_now: int = Weather.HAZE
var _weather_prev: int = Weather.HAZE
var _weather_mix: float = 1.0
## 生效强度 0..1：区域指定 > 本章配方 > 1.0。表现层用它缩降雨量/雾量/风尘。
var _intensity: float = 1.0
var _intensity_target: float = 1.0
## 本章配方掷出的强度（每次换天重掷一次）。
var _profile_intensity: float = 1.0
## 局部天气区域栈（后进先出）。每项 {id, weather, intensity, wind_scale}。
var _regions: Array[Dictionary] = []

var _weather_hold: float = 80.0
var _blend_duration: float = 5.0
var _tick_emit: float = 0.0
var _rust_accum: float = 0.0
var _zone_depth: int = 0
## 室内/室外区域栈：进一层压一层，出一层回落到剩下那层。
var _zone_stack: Array[int] = []
## 这一关的基础层（关卡装载时 set_zone 的那一层）。
var _base_zone: int = Zone.OUTDOORS
var _heading_target: float = -1.0
var _heading_hold: float = 48.0
var _gust_t: float = 0.0
var _rng := RandomNumberGenerator.new()
## Per-visit sky plate. Rolled on boot and again each time a level bakes the sky.
var _sky_seed: int = 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	phase = phase_at(time_of_day)
	_weather_hold = _rng.randf_range(WEATHER_HOLD_MIN, WEATHER_HOLD_MAX)
	_blend_duration = _rng.randf_range(BLEND_MIN, BLEND_MAX)
	roll_sky_seed()
	_sync_effective(true)


func sky_seed() -> int:
	return _sky_seed


func roll_sky_seed() -> int:
	_sky_seed = _rng.randi()
	if _sky_seed == 0:
		_sky_seed = 1
	return _sky_seed


func _process(delta: float) -> void:
	if is_frozen():
		return
	var scaled := delta * time_scale
	tick(scaled)
	_tick_hazards(scaled)


func is_frozen() -> bool:
	if menu_hold:
		return true
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree != null and tree.paused:
		return true
	if Director.playing or Director.choice_hold or Director.is_fading():
		return true
	return false


## Advance the clock. Used by _process and by tests (call while unfrozen).
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	time_of_day = fposmod(time_of_day + delta / CYCLE_SECONDS, 1.0)
	_refresh_phase()
	_tick_weather(delta)
	_tick_regions(delta)
	_tick_wind(delta)
	_tick_emit += delta
	if _tick_emit >= TICK_INTERVAL:
		_tick_emit = 0.0
		clock_ticked.emit(time_of_day, phase)


## Test helper: jump forward without waiting out the 20-minute cycle.
func advance(seconds: float) -> void:
	tick(maxf(0.0, seconds))


func set_time(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	_refresh_phase()
	clock_ticked.emit(time_of_day, phase)


func set_weather(next_weather: int, instant: bool = false) -> void:
	var w := _clamp_weather(next_weather)
	if instant:
		previous_weather = w
		weather = w
		weather_blend = 1.0
		_sync_effective(true)
		weather_changed.emit(weather)
		return
	if w == weather and weather_blend >= 1.0:
		return
	previous_weather = weather
	weather = w
	weather_blend = 0.0
	_blend_duration = _rng.randf_range(BLEND_MIN, BLEND_MAX)
	if _regions.is_empty():
		_sync_effective(false)
	weather_changed.emit(weather)


func set_weather_hold(seconds: float) -> void:
	_weather_hold = maxf(0.0, seconds)
	if weather_blend < 1.0:
		weather_blend = 1.0


func reset() -> void:
	menu_hold = false
	time_of_day = DEFAULT_TIME
	phase = phase_at(time_of_day)
	weather = Weather.HAZE
	previous_weather = Weather.HAZE
	weather_blend = 1.0
	_zone_depth = 0
	_zone_stack.clear()
	_base_zone = Zone.OUTDOORS
	set_zone(Zone.OUTDOORS)
	wind_heading = -1.0
	_heading_target = -1.0
	_heading_hold = 48.0
	_gust_t = 0.0
	gust = 1.0
	_snap_wind_speed()
	_weather_hold = _rng.randf_range(WEATHER_HOLD_MIN, WEATHER_HOLD_MAX)
	_blend_duration = _rng.randf_range(BLEND_MIN, BLEND_MAX)
	_tick_emit = 0.0
	_rust_accum = 0.0
	time_scale = 1.0
	profile.clear()
	_regions.clear()
	_intensity = 1.0
	_intensity_target = 1.0
	_sync_effective(true)


func set_zone(next_zone: int) -> void:
	var z := Zone.INDOORS if next_zone == Zone.INDOORS else Zone.OUTDOORS
	# 直接 set_zone（关卡装载、读档）就是"这一关的基础层"：出完所有区域后回到这层。
	if _zone_stack.is_empty():
		_base_zone = z
	if z == zone:
		return
	zone = z
	zone_changed.emit(zone)


func enter_zone(next_zone: int) -> void:
	var z := Zone.INDOORS if next_zone == Zone.INDOORS else Zone.OUTDOORS
	_zone_stack.append(z)
	_zone_depth = _zone_stack.size()
	set_zone(z)


## 出门时回落到栈里剩下的那一层；栈空了才回落到 fallback。
## fallback < 0（默认）表示回到"这一关的基础层"，所以室内关的整关 IndoorZone 出栈后
## 还是室内、露天中庭出栈后才回到室内，两头都对。
## `leaving_zone` >= 0 时按值移除栈里最后一个匹配项：重叠区域乱序退出也不会串层。
func leave_zone(fallback_zone: int = -1, leaving_zone: int = -1) -> void:
	if not _zone_stack.is_empty():
		var removed := false
		if leaving_zone >= 0:
			for i in range(_zone_stack.size() - 1, -1, -1):
				if _zone_stack[i] == leaving_zone:
					_zone_stack.remove_at(i)
					removed = true
					break
		if not removed:
			_zone_stack.pop_back()
	_zone_depth = _zone_stack.size()
	if not _zone_stack.is_empty():
		set_zone(_zone_stack[_zone_stack.size() - 1])
		return
	if fallback_zone < 0:
		set_zone(_base_zone)
	else:
		set_zone(Zone.INDOORS if fallback_zone == Zone.INDOORS else Zone.OUTDOORS)


func zone_id() -> String:
	return "indoors" if zone == Zone.INDOORS else "outdoors"


## ------------------------------------------------------ 每章 / 每片天气 --
## 全局时钟只回答"现在几点、大致什么天"。这两层在它上面加细节：
## 配方（profile）决定这一章会刮什么风下什么雨；区域（region）决定这条街、
## 这个天井、这段垛口此刻是不是另一副天。

## 本章天气配方。可给的键（其余键忽略，空字典 == 沿用全局表）：
##   allowed:   Array[int]              —— 本章只会出现这些天气
##   weights:   Dictionary              —— {阶段 id: {天气 id: 权重}}，缺的阶段回落全局表
##   hold:      float | Vector2(min,max)—— 一次天气持续多久
##   intensity: float | Vector2(min,max)—— 强度区间（每次换天重掷一次）
func set_weather_profile(next_profile: Dictionary) -> void:
	profile.clear()
	if not next_profile.is_empty():
		for key in next_profile:
			if PROFILE_KEYS.has(String(key)):
				profile[String(key)] = next_profile[key]
	_weather_hold = _profile_hold()
	_roll_profile_intensity()
	_sync_effective(false)


func clear_weather_profile() -> void:
	if profile.is_empty():
		return
	profile.clear()
	_roll_profile_intensity()
	_sync_effective(false)


func has_weather_profile() -> bool:
	return not profile.is_empty()


## 进一片局部天气区域。同 id 重复进不会叠层；spec 可含
## weather(int，-1 = 沿用基础天气) / intensity(float) / wind_scale(float)。
func enter_weather_region(id: StringName, spec: Dictionary = {}) -> void:
	if String(id) == "":
		return
	leave_weather_region(id)
	var raw_weather := int(spec.get("weather", -1))
	_regions.append({
		"id": id,
		"weather": raw_weather if raw_weather < 0 else _clamp_weather(raw_weather),
		"intensity": clampf(float(spec.get("intensity", 1.0)), 0.0, 1.0),
		"wind_scale": maxf(float(spec.get("wind_scale", 1.0)), 0.0),
	})
	_sync_effective(false)


func leave_weather_region(id: StringName) -> void:
	var found := false
	for i in range(_regions.size() - 1, -1, -1):
		if StringName(_regions[i]["id"]) == id:
			_regions.remove_at(i)
			found = true
	if found:
		_sync_effective(false)


## 出关卡 / 读档时清栈：漏掉一次 body_exited 不会把天气永久钉在别处。
func clear_weather_regions() -> void:
	if _regions.is_empty():
		return
	_regions.clear()
	_sync_effective(false)


func active_weather_region() -> StringName:
	if _regions.is_empty():
		return &""
	return StringName(_regions.back()["id"])


## 当前**生效**的天气（含区域覆盖），不是基础态。
func effective_weather() -> int:
	return _weather_now


## 生效强度 0..1：区域 > 本章配方 > 1.0。表现层用它缩降雨量/雾量/风尘。
func weather_intensity() -> float:
	return clampf(_intensity, 0.0, 1.0)


## 基础态天气 id —— 存档只认这个，区域覆盖不进盘。
func weather_id_base() -> String:
	return _id_from_weather(weather)


func isolate_ui_layer(layer: CanvasLayer) -> void:
	if layer == null:
		return
	layer.follow_viewport_enabled = false
	if layer.is_inside_tree():
		RenderingServer.canvas_set_modulate(layer.get_canvas(), Color.WHITE)
	for child in layer.get_children():
		if child is CanvasItem:
			var item := child as CanvasItem
			# 只洗 RGB。Juice 的全屏闪白层启动时 modulate.a = 0；
			# 若写成 Color.WHITE 会把它重新点亮，标题屏/关卡立刻整屏惨白。
			item.modulate = Color(1.0, 1.0, 1.0, item.modulate.a)


func hold_for_menu() -> void:
	menu_hold = true
	_zone_depth = 0
	_zone_stack.clear()
	_regions.clear()
	set_zone(Zone.OUTDOORS)
	set_time(TITLE_TIME)
	set_weather(Weather.HAZE, true)
	_snap_wind_speed()


func release_menu() -> void:
	menu_hold = false


func snapshot() -> Dictionary:
	return {
		"time_of_day": time_of_day,
		# 存档只记基础态：区域覆盖是"此刻站在哪"的产物，读档后由区域重新装配。
		"weather": weather_id_base(),
		"phase": phase_id(),
		"zone": zone_id(),
		"wind_heading": wind_heading,
	}


func apply_snapshot(data: Dictionary) -> void:
	set_time(float(data.get("time_of_day", DEFAULT_TIME)))
	set_weather(weather_from_id(String(data.get("weather", "haze"))), true)
	if String(data.get("zone", "outdoors")) == "indoors":
		set_zone(Zone.INDOORS)
	else:
		set_zone(Zone.OUTDOORS)
	var heading := float(data.get("wind_heading", wind_heading))
	wind_heading = -1.0 if heading < 0.0 else 1.0
	_heading_target = wind_heading
	_snap_wind_speed()


func phase_at(t: float) -> int:
	var x := fposmod(t, 1.0)
	if x < 0.12:
		return Phase.DAWN
	if x < 0.50:
		return Phase.DAY
	if x < 0.62:
		return Phase.DUSK
	return Phase.NIGHT


func phase_id() -> String:
	match phase:
		Phase.DAWN:
			return "dawn"
		Phase.DUSK:
			return "dusk"
		Phase.NIGHT:
			return "night"
		_:
			return "day"


func phase_label() -> String:
	match phase:
		Phase.DAWN:
			return "黎明"
		Phase.DUSK:
			return "黄昏"
		Phase.NIGHT:
			return "夜晚"
		_:
			return "白昼"


func weather_id() -> String:
	return _id_from_weather(_weather_now)


func _id_from_weather(w: int) -> String:
	match w:
		Weather.RAIN:
			return "rain"
		Weather.FOG:
			return "fog"
		Weather.EMBER_WIND:
			return "ember_wind"
		Weather.RUST_RAIN:
			return "rust_rain"
		Weather.CLEAR:
			return "clear"
		_:
			return "haze"


func weather_from_id(id: String) -> int:
	match id:
		"rain":
			return Weather.RAIN
		"fog":
			return Weather.FOG
		"ember_wind":
			return Weather.EMBER_WIND
		"rust_rain":
			return Weather.RUST_RAIN
		"clear":
			return Weather.CLEAR
		_:
			return Weather.HAZE


func weather_label() -> String:
	return _weather_label(_weather_now)


func _weather_label(w: int) -> String:
	match w:
		Weather.RAIN:
			return "雨"
		Weather.FOG:
			return "浓雾"
		Weather.EMBER_WIND:
			return "余烬风"
		Weather.RUST_RAIN:
			return "锈雨"
		Weather.CLEAR:
			return "晴"
		_:
			return "薄雾"


func hud_line() -> String:
	# 室内看不见天，也没有天气；HUD 只报「地下」，时钟仍在背后走。
	if zone == Zone.INDOORS:
		return "地下 · %s" % phase_label()
	return "%s · %s" % [weather_label(), phase_label()]


func mood_tint() -> Color:
	if zone == Zone.INDOORS:
		return _indoor_tint()
	var a := _phase_tint(phase)
	var b := _weather_mul(_blend_weather())
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, 1.0)


func outdoor_tint() -> Color:
	var a := _phase_tint(phase)
	var b := _weather_mul(_blend_weather())
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, 1.0)


func indoor_tint() -> Color:
	return _indoor_tint()


func _indoor_tint() -> Color:
	var b := _weather_mul(_blend_weather())
	var c := Color(INDOOR_TINT.r * b.r, INDOOR_TINT.g * b.g, INDOOR_TINT.b * b.b, 1.0)
	c.r = maxf(c.r, 0.52)
	c.g = maxf(c.g, 0.42)
	c.b = maxf(c.b, 0.34)
	return c


func mood_luminance() -> float:
	var c := mood_tint()
	return (c.r + c.g + c.b) / 3.0


## fog_band.png itself peaks at ~0.6 alpha, so these layer alphas read at
## roughly 60%: thick fog needs ~0.6 here to actually look thick.
func fog_far_alpha() -> float:
	return _fog_alpha(0.13, 0.24, 0.50, 0.16)


func fog_near_alpha() -> float:
	return _fog_alpha(0.20, 0.34, 0.62, 0.22)


func silhouette_modulate() -> Color:
	var faded := 1.0
	var w := _blend_weather()
	if w == Weather.FOG:
		faded = 0.52
	elif w == Weather.RAIN:
		faded = 0.78
	elif w == Weather.RUST_RAIN:
		faded = 0.70
	elif w == Weather.EMBER_WIND:
		faded = 0.90
	if phase == Phase.NIGHT:
		faded *= 0.82
	return Color(1, 1, 1, clampf(faded, 0.40, 1.0))


## Cloud cover for the drifting cloud plates (0 = clear sky). Blends across a
## weather change like the fog bands; night thins the wisps so the moon reads.
func cloud_alpha() -> float:
	var a := lerpf(_weather_cloud(_weather_prev), _weather_cloud(_weather_now), clampf(_weather_mix, 0.0, 1.0))
	if phase == Phase.NIGHT:
		a *= 0.75
	return clampf(a, 0.0, 0.9)


func _weather_cloud(w: int) -> float:
	match w:
		Weather.CLEAR:
			return 0.16
		Weather.RAIN:
			return 0.88
		Weather.RUST_RAIN:
			return 0.82
		Weather.FOG:
			return 0.72
		Weather.EMBER_WIND:
			return 0.42
		_:
			return 0.62


## Low fog rolling across the graveyard floor, in front of the play canvas.
## Zero indoors / on the title; thick fog is the only weather that really shows it.
func ground_fog_alpha() -> float:
	if not weather_fx_allowed():
		return 0.0
	var a := lerpf(_weather_ground_fog(_weather_prev), _weather_ground_fog(_weather_now), clampf(_weather_mix, 0.0, 1.0))
	if phase == Phase.NIGHT:
		a += 0.05
	elif phase == Phase.DAWN:
		a += 0.06
	return clampf(a, 0.0, 0.8) * _fx_intensity()


func _weather_ground_fog(w: int) -> float:
	match w:
		Weather.CLEAR:
			return 0.0
		Weather.FOG:
			return 0.62
		Weather.RAIN:
			return 0.18
		Weather.RUST_RAIN:
			return 0.20
		Weather.EMBER_WIND:
			return 0.05
		_:
			return 0.10


## Screen-space fog veil over the whole world (below HUD): the washed-out look
## that says "thick fog" at a glance. Bands alone only tint the ground line.
func fog_veil_alpha() -> float:
	if not weather_fx_allowed():
		return 0.0
	var a := lerpf(_weather_veil(_weather_prev), _weather_veil(_weather_now), clampf(_weather_mix, 0.0, 1.0))
	return clampf(a, 0.0, 0.35) * _fx_intensity()


func _weather_veil(w: int) -> float:
	match w:
		Weather.FOG:
			return 0.22
		Weather.RAIN:
			return 0.05
		Weather.RUST_RAIN:
			return 0.06
		Weather.EMBER_WIND:
			return 0.03
		Weather.CLEAR:
			return 0.0
		_:
			return 0.02


## 0..1 spawn density for wind-borne dust / leaf flecks. Calm haze barely
## sheds anything; ember wind and storms fill the air. Gusts push it further.
func wind_mote_density() -> float:
	if not weather_fx_allowed() or is_frozen():
		return 0.0
	var d := clampf((wind_speed - 0.10) / 0.55, 0.0, 1.0)
	return clampf(d * lerpf(0.85, 1.25, clampf((gust - 0.7) / 0.55, 0.0, 1.0)) * _fx_intensity(), 0.0, 1.0)


func sky_modulate() -> Color:
	match phase:
		Phase.DAWN:
			return Color(0.90, 0.86, 1.0)
		Phase.DUSK:
			return Color(1.02, 0.82, 0.78)
		Phase.NIGHT:
			return Color(0.72, 0.70, 0.92)
		_:
			return Color(1, 1, 1)


func nest_rain_mul() -> float:
	## Outdoor rain soaks shrine fire. Indoor / menu already report rain 0.
	var rain := rain_opacity()
	if rain <= 0.0:
		return 1.0
	return lerpf(1.0, 0.26, rain)


func nest_light_energy() -> float:
	var e := 1.35
	match phase:
		Phase.NIGHT:
			e = 2.60
		Phase.DUSK:
			e = 1.90
		Phase.DAWN:
			e = 1.55
	return e * nest_rain_mul()


func nest_light_radius() -> float:
	var r := 140.0
	match phase:
		Phase.NIGHT:
			r = 210.0
		Phase.DUSK:
			r = 170.0
		Phase.DAWN:
			r = 155.0
	return r * lerpf(1.0, 0.40, rain_opacity())


func moon_fill_energy() -> float:
	return outdoor_moon_energy()


func outdoor_moon_energy() -> float:
	if menu_hold or zone == Zone.INDOORS:
		return 0.0
	match phase:
		Phase.NIGHT:
			return 0.23 * lerpf(1.0, 0.58, rain_opacity())
		Phase.DUSK:
			return 0.11 * lerpf(1.0, 0.58, rain_opacity())
		Phase.DAWN:
			return 0.05 * lerpf(1.0, 0.58, rain_opacity())
		_:
			return 0.0


func indoor_fill_energy() -> float:
	return 0.85


func indoor_fill_radius() -> float:
	return 220.0


func heart_light_energy() -> float:
	return 0.70


func heart_light_radius() -> float:
	return 80.0


func weather_weight(kind: int) -> float:
	var from_w := 1.0 if _weather_prev == kind else 0.0
	var to_w := 1.0 if _weather_now == kind else 0.0
	return lerpf(from_w, to_w, clampf(_weather_mix, 0.0, 1.0))


func weather_fx_allowed() -> bool:
	return zone == Zone.OUTDOORS and not menu_hold


func rain_opacity() -> float:
	if not weather_fx_allowed():
		return 0.0
	return clampf((weather_weight(Weather.RAIN) + weather_weight(Weather.RUST_RAIN)) * _fx_intensity(), 0.0, 1.0)


func ember_wind_opacity() -> float:
	if not weather_fx_allowed():
		return 0.0
	return clampf(weather_weight(Weather.EMBER_WIND) * _fx_intensity(), 0.0, 1.0)


## 生效强度：区域 > 本章配方 > 1.0。只在"有东西在下/在飘"的取数上用它，
## 晴天的取数本来就近 0，乘了也不会把画面压没。
func _fx_intensity() -> float:
	return clampf(_intensity, 0.0, 1.0)


## 区域自带的风力倍率（避风的矮墙下 0.3，垛口上 1.4）。
func _wind_scale() -> float:
	if _regions.is_empty():
		return 1.0
	return maxf(float(_regions.back().get("wind_scale", 1.0)), 0.0)


## 1 when rust rain is fully in; night also upgrades ordinary rain.
func rust_rain_mix() -> float:
	var rust := weather_weight(Weather.RUST_RAIN)
	if phase == Phase.NIGHT:
		rust = maxf(rust, weather_weight(Weather.RAIN) * 0.90)
	return rust


func is_rust_raining() -> bool:
	return rust_rain_mix() >= 0.45


func rust_rain_applies() -> bool:
	if is_frozen() or menu_hold:
		return false
	if zone != Zone.OUTDOORS:
		return false
	return is_rust_raining()


func apply_rust_rain_expose(player: Node = null) -> bool:
	if not rust_rain_applies():
		return false
	var p := player as Player
	if p == null:
		p = _find_player()
	if p == null or p.toxin == null or p.health == null:
		return false
	if p.health.current <= 0:
		return false
	p.toxin.expose(RUST_RAIN_EXPOSE)
	return true


func rain_audio_gain() -> float:
	var clear := maxf(weather_weight(Weather.RAIN) - rust_rain_mix(), 0.0)
	return _audio_gate(clear)


func rust_rain_audio_gain() -> float:
	return _audio_gate(rust_rain_mix())


func drone_audio_gain() -> float:
	if menu_hold:
		return 0.0
	var g := 0.22
	if zone == Zone.INDOORS:
		g = 0.10
	g *= 0.85 + 0.15 * clampf(gust, 0.7, 1.25)
	if is_inside_tree():
		var tree := get_tree()
		if tree != null and tree.paused:
			g *= 0.35
	return g


func wind_vector() -> Vector2:
	return Vector2(wind_heading * wind_speed * gust, 0.0)


func sway_radians() -> float:
	if wind_speed <= 0.04:
		return 0.0
	return deg_to_rad(10.0) * wind_heading * clampf(wind_speed * 2.4, 0.35, 1.4) * gust


func is_breeze_active() -> bool:
	return wind_speed > 0.04


func weather_wind_speed() -> float:
	var s := BREEZE_BASE
	s += weather_weight(Weather.RAIN) * 0.28
	s += weather_weight(Weather.RUST_RAIN) * 0.32
	s += weather_weight(Weather.EMBER_WIND) * 0.48
	s -= weather_weight(Weather.FOG) * 0.10
	s -= weather_weight(Weather.CLEAR) * 0.08
	return clampf(s, 0.08, 0.85) * _wind_scale()


func _tick_wind(delta: float) -> void:
	if delta <= 0.0:
		return
	_gust_t += delta
	gust = clampf(0.92 + 0.18 * sin(_gust_t * 0.37) + 0.10 * sin(_gust_t * 0.91), 0.70, 1.25)
	_heading_hold -= delta
	if _heading_hold <= 0.0:
		if _rng.randf() < 0.55:
			_heading_target = -_heading_target
		_heading_hold = _rng.randf_range(36.0, 72.0)
	wind_heading = move_toward(wind_heading, _heading_target, delta / HEADING_TURN * 2.0)
	var target := 0.0 if (zone == Zone.INDOORS or menu_hold) else weather_wind_speed()
	var prev := wind_speed
	wind_speed = move_toward(wind_speed, target, delta / INDOOR_WIND_FADE)
	if absf(prev - wind_speed) > 0.04 or absf(wind_heading - _heading_target) < 0.01:
		wind_changed.emit(wind_heading, wind_speed)


func _snap_wind_speed() -> void:
	gust = 1.0
	if zone == Zone.INDOORS or menu_hold:
		wind_speed = 0.0
	else:
		wind_speed = weather_wind_speed()
	wind_changed.emit(wind_heading, wind_speed)


func _audio_gate(amount: float) -> float:
	if menu_hold:
		return 0.0
	var g := clampf(amount, 0.0, 1.0)
	if zone == Zone.INDOORS:
		g *= 0.12
	if is_inside_tree():
		var tree := get_tree()
		if tree != null and tree.paused:
			g *= 0.08
	return g


func _tick_hazards(delta: float) -> void:
	if not rust_rain_applies():
		_rust_accum = 0.0
		return
	_rust_accum += delta
	if _rust_accum < RUST_RAIN_INTERVAL:
		return
	_rust_accum = 0.0
	apply_rust_rain_expose()


func _find_player() -> Player:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Player


func _refresh_phase() -> void:
	var next := phase_at(time_of_day)
	if next == phase:
		return
	phase = next
	phase_changed.emit(phase)


func _tick_weather(delta: float) -> void:
	if weather_blend < 1.0:
		weather_blend = minf(1.0, weather_blend + delta / maxf(_blend_duration, 0.05))
		return
	_weather_hold -= delta
	if _weather_hold > 0.0:
		return
	# Cutscenes already freeze the whole clock; this is the extra latch so a
	# hold that expires on the first unfrozen frame cannot hard-cut weather.
	if Director.playing or Director.choice_hold or Director.is_fading():
		return
	set_weather(_pick_weather(), false)
	_weather_hold = _profile_hold()
	_roll_profile_intensity()


## ------------------------------------------------------- 生效三元组维护 --

## 让生效三元组跟上"现在该显示什么"。snap=true 不留过渡（开机/读档/瞬间换天）。
func _sync_effective(snap: bool = false) -> void:
	var desired := _desired_weather()
	if snap:
		_weather_prev = desired
		_weather_now = desired
		_weather_mix = 1.0
	elif desired != _weather_now:
		_weather_prev = _weather_now
		_weather_now = desired
		_weather_mix = 0.0
	if _regions.is_empty() and not snap:
		# 没有区域时完全不维护第二套淡入：直接镜像基础态。
		_weather_prev = previous_weather
		_weather_mix = weather_blend
	_intensity_target = _desired_intensity()
	if snap:
		_intensity = _intensity_target


func _tick_regions(delta: float) -> void:
	if _regions.is_empty():
		if _weather_now != weather or _weather_prev != previous_weather or _weather_mix != weather_blend:
			_weather_prev = previous_weather
			_weather_now = weather
			_weather_mix = weather_blend
		_intensity_target = _desired_intensity()
		_intensity = move_toward(_intensity, _intensity_target, delta / 2.5)
		return
	var desired := _desired_weather()
	if desired != _weather_now:
		_weather_prev = _weather_now
		_weather_now = desired
		_weather_mix = 0.0
		weather_changed.emit(_weather_now)
	_weather_mix = minf(1.0, _weather_mix + delta / maxf(REGION_BLEND, 0.05))
	_intensity_target = _desired_intensity()
	_intensity = move_toward(_intensity, _intensity_target, delta / 2.5)


func _desired_weather() -> int:
	if not _regions.is_empty():
		var w := int(_regions.back()["weather"])
		# -1 = 这一片只是避风/加雾，天气本身跟着基础态走。
		if w >= 0:
			return _clamp_weather(w)
	return weather


func _desired_intensity() -> float:
	if not _regions.is_empty():
		return clampf(float(_regions.back()["intensity"]), 0.0, 1.0)
	if not profile.is_empty():
		return _profile_intensity
	return 1.0


## 强度区间每换一次天重掷一次，避免同一片雨在区间里抖。
func _roll_profile_intensity() -> void:
	if profile.has("intensity"):
		var spec = profile["intensity"]
		if spec is Vector2:
			var v := spec as Vector2
			_profile_intensity = clampf(_rng.randf_range(minf(v.x, v.y), maxf(v.x, v.y)), 0.0, 1.0)
		else:
			_profile_intensity = clampf(float(spec), 0.0, 1.0)
		return
	_profile_intensity = 1.0


func _profile_hold() -> float:
	if not profile.has("hold"):
		return _rng.randf_range(WEATHER_HOLD_MIN, WEATHER_HOLD_MAX)
	var spec = profile["hold"]
	if spec is Vector2:
		var v := spec as Vector2
		return maxf(_rng.randf_range(minf(v.x, v.y), maxf(v.x, v.y)), PROFILE_HOLD_MIN)
	return maxf(float(spec), PROFILE_HOLD_MIN)


## 有配方时按配方掷；配方给不出合法选项就返回 -1，回落全局阶段权重表。
func _pick_profile_weather() -> int:
	if not (profile.has("weights") or profile.has("allowed")):
		return -1
	var allowed: Array = profile.get("allowed", [])
	var table: Dictionary = profile.get("weights", {})
	var row: Dictionary = {}
	if not table.is_empty():
		row = table.get(phase_id(), {})
		if row.is_empty():
			row = table.get("*", {})
	var options: Array[int] = []
	var weights: Array[float] = []
	if not row.is_empty():
		for key in row:
			var w := clampf(float(row[key]), 0.0, 1000.0)
			var kind := weather_from_id(String(key))
			if w <= 0.0:
				continue
			if not allowed.is_empty() and not allowed.has(kind):
				continue
			options.append(kind)
			weights.append(w)
	elif not allowed.is_empty():
		for kind in allowed:
			options.append(_clamp_weather(int(kind)))
			weights.append(1.0)
	if options.is_empty():
		return -1
	# 和全局表一样：尽量不连着两次同一种天气。
	var picked: Array[int] = []
	var picked_w: Array[float] = []
	for i in options.size():
		if options[i] == _weather_now and options.size() > 1:
			continue
		picked.append(options[i])
		picked_w.append(weights[i])
	if picked.is_empty():
		picked = options
		picked_w = weights
	var total := 0.0
	for w in picked_w:
		total += w
	if total <= 0.0:
		return picked[0]
	var r := _rng.randf() * total
	for i in picked.size():
		r -= picked_w[i]
		if r <= 0.0:
			return picked[i]
	return picked[picked.size() - 1]


func _pick_weather() -> int:
	var from_profile := _pick_profile_weather()
	if from_profile >= 0:
		return from_profile
	var r := _rng.randf()
	var next := weather
	match phase:
		Phase.NIGHT:
			if r < 0.34:
				next = Weather.FOG
			elif r < 0.52:
				next = Weather.HAZE
			elif r < 0.66:
				next = Weather.CLEAR
			elif r < 0.86:
				next = Weather.RUST_RAIN
			elif r < 0.95:
				next = Weather.RAIN
			else:
				next = Weather.EMBER_WIND
		Phase.DUSK, Phase.DAWN:
			if r < 0.26:
				next = Weather.FOG
			elif r < 0.48:
				next = Weather.HAZE
			elif r < 0.62:
				next = Weather.CLEAR
			elif r < 0.80:
				next = Weather.RAIN
			elif r < 0.92:
				next = Weather.RUST_RAIN
			else:
				next = Weather.EMBER_WIND
		_:
			if r < 0.30:
				next = Weather.HAZE
			elif r < 0.54:
				next = Weather.CLEAR
			elif r < 0.76:
				next = Weather.RAIN
			elif r < 0.88:
				next = Weather.FOG
			elif r < 0.96:
				next = Weather.RUST_RAIN
			else:
				next = Weather.EMBER_WIND
	if next == weather:
		next = Weather.HAZE if weather != Weather.HAZE else Weather.CLEAR
	return next


func _phase_tint(p: int) -> Color:
	match p:
		Phase.DAWN:
			return DAWN_TINT
		Phase.DUSK:
			return DUSK_TINT
		Phase.NIGHT:
			return NIGHT_TINT
		_:
			return DAY_TINT


func _weather_mul(w: int) -> Color:
	match w:
		Weather.RAIN:
			return Color(0.94, 0.95, 0.98)
		Weather.FOG:
			return Color(0.90, 0.90, 0.96)
		Weather.EMBER_WIND:
			return Color(1.04, 0.92, 0.86)
		Weather.RUST_RAIN:
			return Color(0.90, 0.84, 0.78)
		Weather.CLEAR:
			return Color(1.05, 1.03, 1.0)
		_:
			return Color(1, 1, 1)


func _blend_weather() -> int:
	if _weather_mix < 0.5:
		return _weather_prev
	return _weather_now


func _fog_alpha(haze: float, rain: float, fog: float, ember: float) -> float:
	var from_a := _weather_fog(_weather_prev, haze, rain, fog, ember)
	var to_a := _weather_fog(_weather_now, haze, rain, fog, ember)
	var a := lerpf(from_a, to_a, clampf(_weather_mix, 0.0, 1.0))
	if phase == Phase.NIGHT:
		a += 0.06
	elif phase == Phase.DUSK or phase == Phase.DAWN:
		a += 0.03
	return clampf(a, 0.08, 0.72) * _fx_intensity()


func _weather_fog(w: int, haze: float, rain: float, fog: float, ember: float) -> float:
	match w:
		Weather.RAIN:
			return rain
		Weather.FOG:
			return fog
		Weather.EMBER_WIND:
			return ember
		Weather.RUST_RAIN:
			return rain + 0.04
		Weather.CLEAR:
			return haze * 0.5
		_:
			return haze


func _clamp_weather(w: int) -> int:
	if w < 0 or w > Weather.CLEAR:
		return Weather.HAZE
	return w
