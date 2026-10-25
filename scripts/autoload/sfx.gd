extends Node
## Sfx autoload: pooled one-shot player keyed by short names, world-positioned one-shots,
## per-surface footsteps, weather beds and per-theme ambience beds.
## Do not give this script a class_name — the autoload name is the API.
##
## Sources: assets/audio/sfx/*.wav are project-original (tools/gen_audio_sfx.py, CC0);
## a few keys still use the curated Kenney CC0 copies in assets/kenney_clean/audio/;
## see assets/external/CREDITS.md. Loads are guarded so the suite stays green even
## before/without assets. Headless: every entry point is a silent no-op for audio but
## the voice bookkeeping, positional maths and surface mapping still run (testable).
##
## POSITIONAL AUDIO. World sounds are deliberately not AudioStreamPlayer2D: the world is
## rendered inside a 640x360 SubViewport, and an AudioStreamPlayer2D only hears through the
## listener of the viewport that owns it (the root window, which has no camera), so its
## falloff / pan would be constant or wrong. play_at() instead reads the active camera
## (group "game_camera", Camera2D.get_screen_center_position()), attenuates by world
## distance, and routes the voice to one of five pre-panned buses (Sfx, SfxPanL1/L2/R1/R2:
## AudioEffectPanner at -0.85 / -0.45 / 0 / +0.45 / +0.85 under the Sfx bus). No camera
## (title screen, tests) => behaves like play().
##
## CONTRACT used by other packages: play(key, jitter, db), play_at(key, world_pos, jitter, db),
## tick_stride(moving, wet, delta, surface), surface_for_skin(skin), set_nest_steam(id, gain),
## set_theme_bed(theme) (called by Music). Unknown keys are silent no-ops.

const POOL_SIZE := 20
const BASE_DB := -9.0
## Added to every one-shot (not to weather / drip ambience): keeps SFX peaks above the music bed.
const SFX_MAKEUP_DB := 6.0
const AMBIENCE_FADE := 2.6
const NEST_HISS_FADE := 1.1
const BED_FADE := 2.4
const ZONE_FADE := 1.4
const DEFAULT_MAX_VOICES := 3
const DEFAULT_MIN_INTERVAL := 0.03

## key -> sound (see assets/external/CREDITS.md for sources). Keys with several takes list
## them in VARIANTS (the first take is the entry here).
const LIBRARY := {
	&"swing": "res://assets/audio/sfx/swing_a.wav",
	&"hit_flesh": "res://assets/kenney_clean/audio/hit_flesh.ogg",
	&"hurt": "res://assets/audio/sfx/hurt.wav",
	&"parry": "res://assets/audio/sfx/parry_a.wav",
	&"dash": "res://assets/audio/sfx/dash.wav",
	&"jump": "res://assets/audio/sfx/jump.wav",
	&"land": "res://assets/audio/sfx/land_a.wav",
	&"step": "res://assets/audio/sfx/step_stone_a.wav",
	&"splash": "res://assets/audio/sfx/splash.wav",
	&"spit": "res://assets/audio/sfx/spit.wav",
	&"pickup": "res://assets/kenney_clean/audio/pickup.ogg",
	&"insert": "res://assets/kenney_clean/audio/insert.ogg",
	&"gate": "res://assets/kenney_clean/audio/gate.ogg",
	&"ui_move": "res://assets/kenney_clean/audio/ui_move.ogg",
	&"ui_select": "res://assets/kenney_clean/audio/ui_select.ogg",
	&"ui_back": "res://assets/kenney_clean/audio/ui_back.ogg",
	&"ui_denied": "res://assets/kenney_clean/audio/ui_denied.ogg",
	# --- combat ---
	&"swing_heavy": "res://assets/audio/sfx/swing_heavy_a.wav",
	&"hit_metal": "res://assets/audio/sfx/hit_metal_a.wav",
	&"hit_bone": "res://assets/audio/sfx/hit_bone_a.wav",
	&"hit_heavy": "res://assets/audio/sfx/hit_heavy_a.wav",
	&"shield_block": "res://assets/audio/sfx/shield_block_a.wav",
	&"shield_break": "res://assets/audio/sfx/shield_break.wav",
	&"enemy_die": "res://assets/audio/sfx/enemy_die.wav",
	&"death": "res://assets/audio/sfx/death.wav",
	&"toxin_warn": "res://assets/audio/sfx/toxin_warn.wav",
	&"heal": "res://assets/audio/sfx/heal.wav",
	&"land_heavy": "res://assets/audio/sfx/land_heavy.wav",
	# --- bosses / enemies ---
	&"boss_axe_swing": "res://assets/audio/sfx/boss_axe_swing.wav",
	&"boss_axe_slam": "res://assets/audio/sfx/boss_axe_slam.wav",
	&"boss_roar": "res://assets/audio/sfx/boss_roar.wav",
	&"horse_charge": "res://assets/audio/sfx/horse_charge.wav",
	&"spit_charge": "res://assets/audio/sfx/spit_charge.wav",
	&"ghost_wail": "res://assets/audio/sfx/ghost_wail.wav",
	&"skull_flame": "res://assets/audio/sfx/skull_flame.wav",
	# --- world / interactables ---
	&"hook_fire": "res://assets/audio/sfx/hook_fire.wav",
	&"hook_hit": "res://assets/audio/sfx/hook_hit.wav",
	&"plate_click": "res://assets/audio/sfx/plate_click.wav",
	&"rustgate_melt": "res://assets/audio/sfx/rustgate_melt.wav",
	&"nest_light": "res://assets/audio/sfx/nest_light.wav",
	&"nest_rest": "res://assets/audio/sfx/nest_rest.wav",
	&"core_get": "res://assets/audio/sfx/core_get.wav",
	&"door_open": "res://assets/audio/sfx/door_open.wav",
	&"bell_toll": "res://assets/audio/sfx/bell_toll.wav",
	&"forge_pulse": "res://assets/audio/sfx/forge_pulse.wav",
	&"drip": "res://assets/audio/sfx/drip_a.wav",
	&"gear_creak": "res://assets/audio/sfx/gear_creak_a.wav",
	# 机关专用键：还没有单独采样时先指向已经在库里的声音。
	# HazardFx 会优先用这些键；文件一换，机关不用改代码。
	&"hazard_steam_warn": "res://assets/audio/sfx/gear_creak_a.wav",
	&"hazard_steam": "res://assets/audio/sfx/drip_a.wav",
	&"hazard_flame_warn": "res://assets/audio/sfx/nest_light.wav",
	&"hazard_flame": "res://assets/audio/sfx/skull_flame.wav",
	&"hazard_slag_warn": "res://assets/audio/sfx/drip_a.wav",
	&"hazard_slag": "res://assets/audio/sfx/drip_b.wav",
	&"hazard_bell_warn": "res://assets/audio/sfx/gear_creak_b.wav",
	&"hazard_bell": "res://assets/audio/sfx/bell_toll.wav",
	&"hazard_shock_warn": "res://assets/audio/sfx/forge_pulse.wav",
	&"hazard_shock": "res://assets/audio/sfx/forge_pulse.wav",
	&"hazard_collapse_warn": "res://assets/audio/sfx/gear_creak_a.wav",
	&"hazard_collapse": "res://assets/audio/sfx/land_heavy.wav",
	&"hazard_pendulum": "res://assets/audio/sfx/swing_heavy_a.wav",
	# --- UI ---
	&"ui_pause": "res://assets/audio/sfx/ui_pause.wav",
	&"ui_tick": "res://assets/audio/sfx/ui_tick.wav",
	&"hint_show": "res://assets/audio/sfx/hint_show.wav",
	# --- footsteps (see tick_stride / surface_for_skin) ---
	&"step_stone": "res://assets/audio/sfx/step_stone_a.wav",
	&"step_dirt": "res://assets/audio/sfx/step_dirt_a.wav",
	&"step_metal": "res://assets/audio/sfx/step_metal_a.wav",
	&"step_wet": "res://assets/audio/sfx/step_wet_a.wav",
	&"step_sludge": "res://assets/audio/sfx/step_sludge_a.wav",
}

## Extra takes per key (picked at random, never the same take twice in a row).
const VARIANTS := {
	&"step_stone": ["res://assets/audio/sfx/step_stone_a.wav", "res://assets/audio/sfx/step_stone_b.wav", "res://assets/audio/sfx/step_stone_c.wav"],
	&"step_dirt": ["res://assets/audio/sfx/step_dirt_a.wav", "res://assets/audio/sfx/step_dirt_b.wav", "res://assets/audio/sfx/step_dirt_c.wav"],
	&"step_metal": ["res://assets/audio/sfx/step_metal_a.wav", "res://assets/audio/sfx/step_metal_b.wav", "res://assets/audio/sfx/step_metal_c.wav"],
	&"step_wet": ["res://assets/audio/sfx/step_wet_a.wav", "res://assets/audio/sfx/step_wet_b.wav", "res://assets/audio/sfx/step_wet_c.wav"],
	&"step_sludge": ["res://assets/audio/sfx/step_sludge_a.wav", "res://assets/audio/sfx/step_sludge_b.wav", "res://assets/audio/sfx/step_sludge_c.wav"],
	&"step": ["res://assets/audio/sfx/step_stone_a.wav", "res://assets/audio/sfx/step_stone_b.wav", "res://assets/audio/sfx/step_stone_c.wav"],
	&"land": ["res://assets/audio/sfx/land_a.wav", "res://assets/audio/sfx/land_b.wav"],
	&"swing": ["res://assets/audio/sfx/swing_a.wav", "res://assets/audio/sfx/swing_b.wav"],
	&"swing_heavy": ["res://assets/audio/sfx/swing_heavy_a.wav", "res://assets/audio/sfx/swing_heavy_b.wav"],
	&"hit_metal": ["res://assets/audio/sfx/hit_metal_a.wav", "res://assets/audio/sfx/hit_metal_b.wav"],
	&"hit_bone": ["res://assets/audio/sfx/hit_bone_a.wav", "res://assets/audio/sfx/hit_bone_b.wav"],
	&"hit_heavy": ["res://assets/audio/sfx/hit_heavy_a.wav", "res://assets/audio/sfx/hit_heavy_b.wav"],
	&"shield_block": ["res://assets/audio/sfx/shield_block_a.wav", "res://assets/audio/sfx/shield_block_b.wav"],
	&"parry": ["res://assets/audio/sfx/parry_a.wav", "res://assets/audio/sfx/parry_b.wav"],
	&"drip": ["res://assets/audio/sfx/drip_a.wav", "res://assets/audio/sfx/drip_b.wav", "res://assets/audio/sfx/drip_c.wav"],
	&"gear_creak": ["res://assets/audio/sfx/gear_creak_a.wav", "res://assets/audio/sfx/gear_creak_b.wav"],
}

## dB added per key on top of the caller's level (balances the Kenney copies, whose peaks
## range from 0 to -30 dBFS, against the project-original sounds normalised to -3..-14).
const TRIM_DB := {
	&"hit_flesh": -3.0, &"gate": -3.0, &"insert": -2.0, &"pickup": -3.0,
	&"ui_select": 19.0, &"ui_move": 6.0, &"ui_denied": 9.0, &"ui_back": -6.0,
}

## key -> Vector2(max voices, min seconds between starts). Missing keys use the defaults.
## At the cap the oldest voice of the key is stolen (the newest hit is always the one heard),
## unless the repeat interval has not elapsed, in which case the new one is dropped.
const VOICE_RULES := {
	&"step": Vector2(2, 0.16), &"step_stone": Vector2(2, 0.16), &"step_dirt": Vector2(2, 0.16),
	&"step_metal": Vector2(2, 0.16), &"step_wet": Vector2(2, 0.16), &"step_sludge": Vector2(2, 0.16),
	&"swing": Vector2(2, 0.07), &"swing_heavy": Vector2(2, 0.1),
	&"hit_flesh": Vector2(3, 0.045), &"hit_metal": Vector2(3, 0.045), &"hit_bone": Vector2(3, 0.045),
	&"hit_heavy": Vector2(3, 0.06), &"hurt": Vector2(2, 0.12), &"parry": Vector2(2, 0.08),
	&"shield_block": Vector2(2, 0.07), &"shield_break": Vector2(1, 0.2), &"enemy_die": Vector2(3, 0.06),
	&"death": Vector2(1, 1.0), &"land": Vector2(2, 0.08), &"land_heavy": Vector2(1, 0.2),
	&"jump": Vector2(2, 0.08), &"dash": Vector2(2, 0.1),
	&"boss_axe_swing": Vector2(1, 0.3), &"boss_axe_slam": Vector2(1, 0.3), &"boss_roar": Vector2(1, 0.6),
	&"horse_charge": Vector2(1, 0.6), &"spit_charge": Vector2(1, 0.3), &"ghost_wail": Vector2(2, 0.5),
	&"skull_flame": Vector2(3, 0.1), &"spit": Vector2(2, 0.1),
	&"ui_move": Vector2(1, 0.04), &"ui_tick": Vector2(1, 0.03), &"ui_select": Vector2(2, 0.05),
	&"ui_back": Vector2(2, 0.05), &"ui_denied": Vector2(1, 0.08), &"ui_pause": Vector2(1, 0.15),
	&"hint_show": Vector2(1, 0.5), &"heal": Vector2(1, 0.4), &"toxin_warn": Vector2(1, 0.45),
	&"splash": Vector2(3, 0.05), &"drip": Vector2(2, 0.15), &"gear_creak": Vector2(1, 0.8),
	&"bell_toll": Vector2(2, 0.5), &"nest_light": Vector2(1, 0.4), &"nest_rest": Vector2(1, 1.0),
	&"core_get": Vector2(1, 0.6), &"door_open": Vector2(1, 0.5), &"forge_pulse": Vector2(1, 0.3),
	&"rustgate_melt": Vector2(1, 0.6), &"hook_fire": Vector2(1, 0.2), &"hook_hit": Vector2(1, 0.15),
	&"plate_click": Vector2(2, 0.1),
}

## Pool-exhaustion priority (default 1): a new voice may steal the oldest voice of equal or
## lower priority; ambience-grade keys (0) never displace anything.
const PRIORITY := {
	&"parry": 3, &"hurt": 3, &"death": 3, &"boss_roar": 3, &"boss_axe_slam": 3, &"shield_break": 3,
	&"hit_flesh": 2, &"hit_metal": 2, &"hit_bone": 2, &"hit_heavy": 2, &"shield_block": 2,
	&"step": 0, &"step_stone": 0, &"step_dirt": 0, &"step_metal": 0, &"step_wet": 0, &"step_sludge": 0,
	&"splash": 0, &"drip": 0, &"gear_creak": 0, &"ui_tick": 0, &"ui_move": 0,
}

## Looping beds. Weather + drone are driven by WorldClock; the bed_* loops by the Music theme.
const AMBIENCE := {
	&"rain": "res://assets/audio/ambience/rain.wav",
	&"rust_rain": "res://assets/audio/ambience/rust_rain.wav",
	&"cemetery": "res://assets/audio/ambience/cemetery_drone.wav",
	&"nest_hiss": "res://assets/audio/ambience/nest_hiss.wav",
	&"bed_wind": "res://assets/audio/ambience/bed_wind.ogg",
	&"bed_hall": "res://assets/audio/ambience/bed_hall.ogg",
	&"bed_forge": "res://assets/audio/ambience/bed_forge.ogg",
	&"bed_workshop": "res://assets/audio/ambience/bed_workshop.ogg",
	&"bed_core": "res://assets/audio/ambience/bed_core.ogg",
	&"bed_title": "res://assets/audio/ambience/bed_forge.ogg",
}

const BED_KEYS: Array[StringName] = [
	&"bed_wind", &"bed_hall", &"bed_forge", &"bed_workshop", &"bed_core", &"bed_title",
]

const AMBIENCE_LEVEL := {
	&"rain": 0.28,
	&"rust_rain": 0.28,
	&"cemetery": 0.28,
	&"nest_hiss": 0.20,
	&"bed_wind": 0.5,
	# 地窟和圣殿的厅堂床原先 0.8，和音乐床叠在一起发闷。压到音乐下面。
	&"bed_hall": 0.42,
	&"bed_forge": 0.45,
	&"bed_workshop": 0.6,
	&"bed_core": 0.55,
	# 标题炉厅：同一条锻床，音量跟床身走，不另开一条 LIBRARY 一次性音。
	&"bed_title": 0.45,
}

## Music theme -> { bed key: 0..1 target }. Themes not listed (title, graveyard) keep only
## the WorldClock weather and cemetery drone.
const THEME_BEDS := {
	&"undercroft": {&"bed_hall": 1.0},
	&"town": {&"bed_wind": 0.7},
	&"cathedral": {&"bed_hall": 1.0},
	&"workshop": {&"bed_workshop": 1.0},
	&"bell_tower": {&"bed_wind": 1.0},
	&"slag": {&"bed_forge": 1.0},
	&"ramparts": {&"bed_wind": 0.9},
	&"core": {&"bed_forge": 0.6, &"bed_core": 1.0},
}
## The cemetery drone is the graveyard's bed; elsewhere it only underlays the themed bed.
const THEME_DRONE_SCALE := {
	&"title": 1.0, &"graveyard": 1.0, &"undercroft": 0.35, &"town": 0.5, &"cathedral": 0.35,
	&"workshop": 0.25, &"bell_tower": 0.4, &"slag": 0.2, &"ramparts": 0.5, &"core": 0.2,
}
## Sparse one-shots that sell the room: theme -> [[key, min s, max s, min dB, max dB], ...].
const THEME_EVENTS := {
	&"undercroft": [[&"drip", 1.3, 4.2, -9.0, -4.0]],
	&"cathedral": [[&"drip", 4.0, 9.0, -12.0, -7.0]],
	&"workshop": [[&"gear_creak", 6.0, 14.0, -8.0, -3.0]],
	&"bell_tower": [[&"gear_creak", 7.0, 15.0, -9.0, -4.0]],
	&"slag": [[&"gear_creak", 9.0, 18.0, -10.0, -5.0]],
	&"core": [[&"gear_creak", 8.0, 16.0, -10.0, -5.0]],
}

## Positional falloff (world pixels; the world view is 640 px wide at zoom 1).
const POS_NEAR := 110.0
const POS_FAR := 720.0
const POS_FLOOR_DB := -30.0
const POS_HALF_WIDTH := 320.0
const PAN_BUSES: Array[StringName] = [&"SfxPanL2", &"SfxPanL1", &"Sfx", &"SfxPanR1", &"SfxPanR2"]

## Footsteps: surface -> Vector2(seconds between steps, dB), and the one-shot key per surface.
const SURFACES: Array[StringName] = [&"stone", &"dirt", &"metal", &"wet", &"sludge"]
const STRIDE := {
	&"stone": Vector2(0.38, -15.0), &"dirt": Vector2(0.38, -17.0), &"metal": Vector2(0.40, -13.0),
	&"wet": Vector2(0.38, -15.0), &"sludge": Vector2(0.46, -14.0),
}
const STEP_KEYS := {
	&"stone": &"step_stone", &"dirt": &"step_dirt", &"metal": &"step_metal",
	&"wet": &"step_wet", &"sludge": &"step_sludge",
}
## EVERY SolidPlatform.skin value (scripts/world/solid_platform.gd) -> surface. Unknown => stone.
const SKIN_SURFACE := {
	&"auto": &"dirt", &"ground": &"dirt",
	&"floating": &"stone", &"stone": &"stone",
	&"moss": &"wet", &"moss_float": &"wet",
	&"brick": &"stone", &"brick_float": &"stone",
	&"castle": &"stone", &"castle_float": &"stone",
	&"iron": &"metal", &"iron_float": &"metal",
	&"basalt": &"stone", &"basalt_float": &"stone",
	&"rampart": &"stone", &"rampart_float": &"stone",
	# 圣殿铺面（第 4 章 CHAPTER family "nave"）：以前只靠"未知 => stone"兜底，
	# 表里写明后才和 solid_platform.gd 的 skin 列表保持同步。
	&"nave": &"stone", &"nave_float": &"stone",
}

## Debug / test visibility of the last accepted voice.
var last_key: StringName = &""
var last_db: float = 0.0
var last_bus: StringName = &""
var last_pan: float = 0.0
## Tests (and cutscenes) may pin the listener; Vector2.INF = use the game camera.
var listener_override: Vector2 = Vector2.INF

var _pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _variant_last: Dictionary = {}
var _ambience: Dictionary = {}
var _ambience_gain: Dictionary = {}
var _nest_steam: Dictionary = {}
var _stride_t := 0.0
var _stride_on := false
var _drip_t := 0.0
var _headless := false
var _v_key: Array[StringName] = []
var _v_start := PackedFloat64Array()
var _v_end := PackedFloat64Array()
var _v_prio := PackedInt32Array()
var _last_start: Dictionary = {}
var _cam: Camera2D = null
var _view_pos := Vector2.ZERO
var _view_half := POS_HALF_WIDTH
var _cam_next_search := 0.0
var _bed_theme: StringName = &""
var _bed_target: Dictionary = {}
var _drone_scale := 1.0
var _drone_scale_cur := 1.0
var _pause_gain := 1.0
var _event_t: Array[float] = []
var _indoor := 0.0
var _amb_reverb: AudioEffectReverb = null
var _sfx_reverb: AudioEffectReverb = null
var _sfx_bus := -1


func _init() -> void:
	_reset_voice_book()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		set_process(false)
		return
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = _bus_or_master(&"Sfx")
		p.volume_db = BASE_DB
		add_child(p)
		_pool.append(p)
	_cache_effects()
	_ensure_ambience()


func _process(delta: float) -> void:
	var tree := get_tree()
	var paused := tree != null and tree.paused
	_pause_gain = move_toward(_pause_gain, 0.35 if paused else 1.0, delta / 0.4)
	_drone_scale_cur = move_toward(_drone_scale_cur, _drone_scale, delta / BED_FADE)
	_fade_ambience(&"rain", WorldClock.rain_audio_gain(), delta)
	_fade_ambience(&"rust_rain", WorldClock.rust_rain_audio_gain(), delta)
	_fade_ambience(&"cemetery", WorldClock.drone_audio_gain() * _drone_scale_cur, delta)
	_fade_ambience(&"nest_hiss", _nest_steam_target(), delta, NEST_HISS_FADE)
	for key in BED_KEYS:
		_fade_ambience(key, float(_bed_target.get(key, 0.0)) * _pause_gain, delta, BED_FADE)
	_tick_rain_hits(delta)
	if not paused:
		_tick_theme_events(delta)
	_apply_zone_reverb(delta)


# --- one-shots --------------------------------------------------------------

func play(key: StringName, pitch_jitter: float = 0.08, volume_db: float = BASE_DB) -> void:
	_play_voice(key, pitch_jitter, volume_db, &"Sfx", 0.0, true)


## World-positioned one-shot. Callers pass the source's global_position; the voice is
## attenuated by distance to the camera and panned left / right of it (see the header).
func play_at(key: StringName, world_pos: Vector2, pitch_jitter: float = 0.08, volume_db: float = BASE_DB) -> void:
	if not _read_listener():
		play(key, pitch_jitter, volume_db)
		return
	var att := attenuation_db(world_pos.distance_to(_view_pos))
	if att <= -79.0:
		return
	var pan := pan_for(world_pos.x - _view_pos.x, _view_half)
	_play_voice(key, pitch_jitter, volume_db + att, pan_bus_for(pan), pan, true)


## Grounded walk cadence. Presentation only — callers already decided "moving".
## `surface` (CONTRACT): &"stone" | &"dirt" | &"metal" | &"wet" | &"sludge"; unknown = stone.
## `wet` (raining) adds a splash under stone / dirt / metal steps.
func tick_stride(moving: bool, wet: bool, delta: float, surface: StringName = &"stone") -> void:
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
	var s: StringName = surface if STRIDE.has(surface) else &"stone"
	var rule: Vector2 = STRIDE[s]
	_stride_t = rule.x
	play(STEP_KEYS[s], 0.11, rule.y)
	if wet and s != &"wet" and s != &"sludge":
		play(&"splash", 0.16, -21.0)


## Lit nests report rain-gated steam; the loudest one drives the hiss bed.
func set_nest_steam(id: int, gain: float) -> void:
	if gain <= 0.001:
		_nest_steam.erase(id)
	else:
		_nest_steam[id] = clampf(gain, 0.0, 1.0)


## Music calls this on every theme change: picks the themed bed(s), the cemetery-drone
## share and the sparse room events (drips, creaks). Unknown theme => weather only.
func set_theme_bed(theme: StringName) -> void:
	_bed_theme = theme
	_bed_target.clear()
	var beds: Dictionary = THEME_BEDS.get(theme, {})
	for key in beds:
		_bed_target[key] = float(beds[key])
	_drone_scale = float(THEME_DRONE_SCALE.get(theme, 1.0))
	var events: Array = THEME_EVENTS.get(theme, [])
	_event_t.clear()
	for e in events:
		_event_t.append(randf_range(float(e[1]) * 0.3, float(e[2]) * 0.6))


func bed_theme() -> StringName:
	return _bed_theme


var _title_bed := false


## 标题炉厅的环境床。离开标题时只撤掉自己铺上的那一层。
func set_title_bed(on: bool) -> void:
	if on:
		_title_bed = true
		# "forge" 不是音乐主题，set_theme_bed 会把目标清空。标题床单独叠在当前主题上。
		_bed_target[&"bed_title"] = 0.85
	elif _title_bed:
		_title_bed = false
		_bed_target.erase(&"bed_title")


# --- pure helpers (static, unit-tested) -------------------------------------

static func attenuation_db(dist: float) -> float:
	if dist <= POS_NEAR:
		return 0.0
	if dist >= POS_FAR:
		return -80.0
	var t := (dist - POS_NEAR) / (POS_FAR - POS_NEAR)
	return POS_FLOOR_DB * pow(t, 1.35)


## -1 (left) .. +1 (right); never a hard pan, so distant sounds still sit in the picture.
static func pan_for(dx: float, half_width: float = POS_HALF_WIDTH) -> float:
	return clampf(dx / (maxf(half_width, 1.0) * 1.15), -1.0, 1.0) * 0.9


static func pan_bus_for(pan: float) -> StringName:
	if pan <= -0.62:
		return PAN_BUSES[0]
	if pan <= -0.22:
		return PAN_BUSES[1]
	if pan >= 0.62:
		return PAN_BUSES[4]
	if pan >= 0.22:
		return PAN_BUSES[3]
	return PAN_BUSES[2]


static func surface_for_skin(skin: StringName) -> StringName:
	return SKIN_SURFACE.get(skin, &"stone")


## Footstep surface for a floor collider (e.g. the CharacterBody2D's last slide collision):
## SolidPlatform skins map through SKIN_SURFACE ("auto" follows SolidPlatform's own rule:
## thin + wide = floating slab = stone, else ground = dirt); gear / moving platforms are metal.
## `in_sludge` (the knight stands in a ToxinPool) wins over everything.
static func surface_for_collider(collider: Object, in_sludge: bool = false) -> StringName:
	if in_sludge:
		return &"sludge"
	if collider == null:
		return &"stone"
	var script := collider.get_script() as Script
	if script != null:
		var cls := script.get_global_name()
		if cls == &"GearPlatform" or cls == &"MovingPlatform":
			return &"metal"
	var skin = collider.get("skin")
	if skin == null:
		return &"stone"
	var skin_id := StringName(str(skin))
	if skin_id == &"auto":
		var size = collider.get("size")
		if size is Vector2 and size.y <= 16.5 and size.x > 16.5:
			return &"stone"
	return surface_for_skin(skin_id)


## Ambience / Sfx reverb wet level for an indoor amount 0 (open air) .. 1 (enclosed).
static func reverb_wet(bus: StringName, indoor: float) -> float:
	var k := clampf(indoor, 0.0, 1.0)
	if bus == &"Ambience":
		return lerpf(0.06, 0.32, k)
	return lerpf(0.0, 0.14, k)


static func voice_rule(key: StringName) -> Vector2:
	return VOICE_RULES.get(key, Vector2(DEFAULT_MAX_VOICES, DEFAULT_MIN_INTERVAL))


static func priority_of(key: StringName) -> int:
	return int(PRIORITY.get(key, 1))


# --- voice bookkeeping ------------------------------------------------------

func _reset_voice_book() -> void:
	_v_key.resize(POOL_SIZE)
	_v_start.resize(POOL_SIZE)
	_v_end.resize(POOL_SIZE)
	_v_prio.resize(POOL_SIZE)
	for i in POOL_SIZE:
		_v_key[i] = &""
		_v_start[i] = -1000.0
		_v_end[i] = -1000.0
		_v_prio[i] = 0
	_last_start.clear()


func _slot_free(i: int, now: float) -> bool:
	if _v_end[i] > now and (_pool.is_empty() or _pool[i].playing):
		return false
	return true


## Reserve a voice slot for `key` at time `now` (seconds) lasting `length`.
## Returns the pool index (the caller may reuse / restart that player) or -1 = denied.
func _acquire(key: StringName, now: float, length: float, prio: int) -> int:
	var rule := voice_rule(key)
	if now - float(_last_start.get(key, -1000.0)) < rule.y:
		return -1
	var active := 0
	var oldest := -1
	var oldest_t := INF
	for i in POOL_SIZE:
		if _v_key[i] == key and not _slot_free(i, now):
			active += 1
			if _v_start[i] < oldest_t:
				oldest = i
				oldest_t = _v_start[i]
	var slot := -1
	if active >= int(rule.x):
		slot = oldest
	else:
		for i in POOL_SIZE:
			if _slot_free(i, now):
				slot = i
				break
		if slot < 0:
			var victim := -1
			var vt := INF
			var vp := 99
			for i in POOL_SIZE:
				if _v_prio[i] < vp or (_v_prio[i] == vp and _v_start[i] < vt):
					victim = i
					vp = _v_prio[i]
					vt = _v_start[i]
			if victim >= 0 and vp <= prio and prio > 0:
				slot = victim
	if slot < 0:
		return -1
	_v_key[slot] = key
	_v_start[slot] = now
	_v_end[slot] = now + maxf(length, 0.02)
	_v_prio[slot] = prio
	_last_start[key] = now
	return slot


## Active (not yet finished) voices of `key` at `now` according to the bookkeeping.
func voices_active(key: StringName, now: float) -> int:
	var n := 0
	for i in POOL_SIZE:
		if _v_key[i] == key and _v_end[i] > now:
			n += 1
	return n


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _play_voice(key: StringName, pitch_jitter: float, volume_db: float, bus: StringName, pan: float,
		makeup: bool) -> void:
	var stream := _resolve_stream(key)
	if stream == null:
		return
	var pitch := 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	var length := stream.get_length() / maxf(pitch, 0.1)
	var slot := _acquire(key, _now(), length, priority_of(key))
	if slot < 0:
		return
	var db := volume_db + float(TRIM_DB.get(key, 0.0)) + (SFX_MAKEUP_DB if makeup else 0.0)
	last_key = key
	last_db = db
	last_bus = bus
	last_pan = pan
	if _headless or slot >= _pool.size():
		return
	var p := _pool[slot]
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = _bus_or_master(bus)
	p.play()


## Lazily resolve + cache; missing files degrade to silence, not errors.
func _resolve_stream(key: StringName) -> AudioStream:
	var path: String = LIBRARY.get(key, "")
	if VARIANTS.has(key):
		var takes: Array = VARIANTS[key]
		var idx := randi() % takes.size()
		if takes.size() > 1 and idx == int(_variant_last.get(key, -1)):
			idx = (idx + 1) % takes.size()
		_variant_last[key] = idx
		path = String(takes[idx])
	if path == "":
		return null
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	# One-shot SFX must never loop; each stream type spells it differently.
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		stream.loop = false
	_streams[path] = stream
	return stream


# --- listener ---------------------------------------------------------------

## Fills _view_pos / _view_half from the override or the active game camera.
## Returns false when there is no listener (title screen, tests) => callers play centred.
func _read_listener() -> bool:
	if listener_override.x != INF:
		_view_pos = listener_override
		_view_half = POS_HALF_WIDTH
		return true
	var cam := _find_camera()
	if cam == null:
		return false
	_view_pos = cam.get_screen_center_position()
	_view_half = POS_HALF_WIDTH
	var vp := cam.get_viewport()
	if vp != null:
		_view_half = vp.get_visible_rect().size.x * 0.5 / maxf(cam.zoom.x, 0.01)
	return true


func _find_camera() -> Camera2D:
	if _cam != null and is_instance_valid(_cam) and _cam.is_inside_tree():
		return _cam
	_cam = null
	if not is_inside_tree():
		return null
	var now := _now()
	if now < _cam_next_search:
		return null
	_cam_next_search = now + 0.5
	for node in get_tree().get_nodes_in_group("game_camera"):
		var cam := node as Camera2D
		if cam != null and cam.is_inside_tree():
			_cam = cam
			if cam.is_current():
				break
	return _cam


# --- weather, beds, room events ---------------------------------------------

func _cache_effects() -> void:
	var amb := AudioServer.get_bus_index(&"Ambience")
	if amb >= 0 and AudioServer.get_bus_effect_count(amb) > 0:
		_amb_reverb = AudioServer.get_bus_effect(amb, 0) as AudioEffectReverb
	_sfx_bus = AudioServer.get_bus_index(&"Sfx")
	if _sfx_bus >= 0 and AudioServer.get_bus_effect_count(_sfx_bus) > 0:
		_sfx_reverb = AudioServer.get_bus_effect(_sfx_bus, 0) as AudioEffectReverb
		AudioServer.set_bus_effect_enabled(_sfx_bus, 0, false)


func _apply_zone_reverb(delta: float) -> void:
	var target := 1.0 if WorldClock.zone == WorldClock.Zone.INDOORS else 0.0
	if is_equal_approx(_indoor, target):
		return
	_indoor = move_toward(_indoor, target, delta / ZONE_FADE)
	if _amb_reverb != null:
		_amb_reverb.wet = reverb_wet(&"Ambience", _indoor)
	if _sfx_reverb != null:
		var wet := reverb_wet(&"Sfx", _indoor)
		_sfx_reverb.wet = wet
		# Outdoors the Sfx reverb is bypassed entirely (it costs CPU even at wet 0).
		AudioServer.set_bus_effect_enabled(_sfx_bus, 0, wet > 0.002)


func _tick_theme_events(delta: float) -> void:
	var events: Array = THEME_EVENTS.get(_bed_theme, [])
	for i in mini(events.size(), _event_t.size()):
		_event_t[i] -= delta
		if _event_t[i] > 0.0:
			continue
		var e: Array = events[i]
		_event_t[i] = randf_range(float(e[1]), float(e[2]))
		var pan := randf_range(-0.8, 0.8)
		_play_voice(StringName(e[0]), 0.1, randf_range(float(e[3]), float(e[4])), pan_bus_for(pan), pan, false)


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
				# loop_end 0 would mean a zero-length loop; spell out the whole sample.
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = maxi(1, int(round(stream.get_length() * float(stream.mix_rate))))
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
	var pan := randf_range(-0.8, 0.8)
	_play_voice(&"splash", 0.22, lerpf(-24.0, -18.0, clampf(rain, 0.0, 1.0)), pan_bus_for(pan), pan, false)


# --- buses ------------------------------------------------------------------

func _bus_or_master(name: StringName) -> StringName:
	return name if AudioServer.get_bus_index(name) >= 0 else &"Master"


## Slider value 0..100 (Settings owns the persisted copy for Master / Music / Sfx / Ambience).
func bus_percent(bus_name: StringName) -> float:
	if Settings.VOLUME_BUSES.has(bus_name):
		return Settings.volume_percent(bus_name)
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = 0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0) * 100.0


func set_bus_percent(bus_name: StringName, percent: float) -> void:
	if Settings.VOLUME_BUSES.has(bus_name):
		Settings.set_volume_percent(bus_name, percent)
		return
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var linear := clampf(percent / 100.0, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
