extends Node
## Sfx autoload: tiny pooled sound-effect player keyed by short names.
## One-shots live under assets/kenney_clean/audio/*.ogg (CC0, Kenney)
## plus a project-original splash slap. Weather loops live under
## assets/audio/ambience/ (project-original CC0).
## Loads are guarded so the suite stays green even before/without assets.

const POOL_SIZE := 14
const BASE_DB := -9.0
const AMBIENCE_FADE := 2.6
const NEST_HISS_FADE := 1.1
const STRIDE_INTERVAL := 0.38

## key -> curated CC0 sound (see assets/external/CREDITS.md for sources).
const LIBRARY := {
	&"swing": "res://assets/kenney_clean/audio/swing.ogg",
	&"hit_flesh": "res://assets/kenney_clean/audio/hit_flesh.ogg",
	&"hurt": "res://assets/kenney_clean/audio/hurt.ogg",
	&"parry": "res://assets/kenney_clean/audio/parry.ogg",
	&"dash": "res://assets/kenney_clean/audio/dash.ogg",
	&"jump": "res://assets/kenney_clean/audio/jump.ogg",
	&"land": "res://assets/kenney_clean/audio/land.ogg",
	&"step": "res://assets/kenney_clean/audio/step.ogg",
	&"splash": "res://assets/audio/sfx/splash.wav",
	&"spit": "res://assets/kenney_clean/audio/spit.ogg",
	&"pickup": "res://assets/kenney_clean/audio/pickup.ogg",
	&"insert": "res://assets/kenney_clean/audio/insert.ogg",
	&"gate": "res://assets/kenney_clean/audio/gate.ogg",
	&"ui_move": "res://assets/kenney_clean/audio/ui_move.ogg",
	&"ui_select": "res://assets/kenney_clean/audio/ui_select.ogg",
	&"ui_back": "res://assets/kenney_clean/audio/ui_back.ogg",
	&"ui_denied": "res://assets/kenney_clean/audio/ui_denied.ogg",
}

## Looping weather beds (project-original CC0 rain / nest steam; Kenney has none).
const AMBIENCE := {
	&"rain": "res://assets/audio/ambience/rain.wav",
	&"rust_rain": "res://assets/audio/ambience/rust_rain.wav",
	&"cemetery": "res://assets/audio/ambience/cemetery_drone.wav",
	&"nest_hiss": "res://assets/audio/ambience/nest_hiss.wav",
}

const AMBIENCE_LEVEL := {
	&"rain": 0.28,
	&"rust_rain": 0.28,
	&"cemetery": 0.28,
	&"nest_hiss": 0.20,
}

var _pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _ambience: Dictionary = {}
var _ambience_gain: Dictionary = {}
var _nest_steam: Dictionary = {}
var _stride_t := 0.0
var _stride_on := false
var _drip_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = _bus_or_master(&"Sfx")
		p.volume_db = BASE_DB
		add_child(p)
		_pool.append(p)
	_ensure_ambience()


func _process(delta: float) -> void:
	_fade_ambience(&"rain", WorldClock.rain_audio_gain(), delta)
	_fade_ambience(&"rust_rain", WorldClock.rust_rain_audio_gain(), delta)
	_fade_ambience(&"cemetery", WorldClock.drone_audio_gain(), delta)
	_fade_ambience(&"nest_hiss", _nest_steam_target(), delta, NEST_HISS_FADE)
	_tick_rain_hits(delta)


func play(key: StringName, pitch_jitter: float = 0.08, volume_db: float = BASE_DB) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream := _resolve_stream(key)
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return


## World-positioned one-shot (CONTRACT: callers pass the source's global_position;
## the audio package attenuates / pans by distance to the camera). Until then it
## behaves like play() so callers can adopt the API now.
func play_at(key: StringName, _world_pos: Vector2, pitch_jitter: float = 0.08, volume_db: float = BASE_DB) -> void:
	play(key, pitch_jitter, volume_db)


## Grounded walk cadence. Presentation only — callers already decided "moving".
## `surface` (CONTRACT): &"stone" | &"dirt" | &"metal" | &"wet" | &"sludge"; unknown = stone.
func tick_stride(moving: bool, wet: bool, delta: float, _surface: StringName = &"stone") -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not moving:
		_stride_on = false
		_stride_t = 0.0
		return
	if not _stride_on:
		_stride_on = true
		_stride_t = 0.0
	_stride_t -= delta
	if _stride_t > 0.0:
		return
	_stride_t = STRIDE_INTERVAL
	play(&"step", 0.11, -15.0)
	if wet:
		play(&"splash", 0.16, -21.0)


## Lit nests report rain-gated steam; the loudest one drives the hiss bed.
func set_nest_steam(id: int, gain: float) -> void:
	if gain <= 0.001:
		_nest_steam.erase(id)
	else:
		_nest_steam[id] = clampf(gain, 0.0, 1.0)


## Lazily resolve + cache; missing files degrade to silence, not errors.
func _resolve_stream(key: StringName) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	var path: String = LIBRARY.get(key, "")
	var stream: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	# One-shot SFX must never loop; each stream type spells it differently.
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		stream.loop = false
	_streams[key] = stream
	return stream


func _ensure_ambience() -> void:
	for key in AMBIENCE:
		if _ambience.has(key):
			continue
		var player := AudioStreamPlayer.new()
		player.name = "Ambience_%s" % String(key)
		player.bus = _bus_or_master(&"Ambience")
		player.volume_db = -80.0
		var path: String = AMBIENCE[key]
		if path != "" and ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream is AudioStreamWAV:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = 0
			elif stream is AudioStreamOggVorbis:
				stream.loop = true
			player.stream = stream
		add_child(player)
		_ambience[key] = player
		_ambience_gain[key] = 0.0


func _fade_ambience(key: StringName, target: float, delta: float, fade: float = AMBIENCE_FADE) -> void:
	if not _ambience.has(key):
		return
	var player: AudioStreamPlayer = _ambience[key]
	if player.stream == null:
		return
	var cur := float(_ambience_gain.get(key, 0.0))
	var next := move_toward(cur, clampf(target, 0.0, 1.0), delta / maxf(fade, 0.05))
	_ambience_gain[key] = next
	if next <= 0.001:
		player.volume_db = -80.0
		if player.playing:
			player.stop()
		return
	var level := float(AMBIENCE_LEVEL.get(key, 0.28))
	player.volume_db = linear_to_db(next * level)
	if not player.playing:
		player.play()


func _nest_steam_target() -> float:
	var best := 0.0
	for g in _nest_steam.values():
		best = maxf(best, float(g))
	return best


func _tick_rain_hits(delta: float) -> void:
	var rain := WorldClock.rain_audio_gain() + WorldClock.rust_rain_audio_gain()
	if rain <= 0.12:
		_drip_t = 0.0
		return
	_drip_t -= delta
	if _drip_t > 0.0:
		return
	_drip_t = lerpf(0.72, 0.28, clampf(rain, 0.0, 1.0))
	play(&"splash", 0.22, lerpf(-24.0, -18.0, clampf(rain, 0.0, 1.0)))


func _bus_or_master(name: StringName) -> StringName:
	return name if AudioServer.get_bus_index(name) >= 0 else &"Master"


func bus_percent(bus_name: StringName) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = 0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0) * 100.0


func set_bus_percent(bus_name: StringName, percent: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var linear := clampf(percent / 100.0, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
