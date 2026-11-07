extends Node3D
## Base class for the 3D forge-hall title props (`scripts/title3d/props/*.gd`).
##
## Ported behaviour, not drawing code, from the 2D live title scene
## (docs/title-live-scene.md §6.1/§6.2, scripts/ui/title_prop.gd):
##   · `advance(dt)` owns the clock; big deltas are split into <= MAX_STEP steps so a
##     state machine can never skip a transition. Nothing else calls `_process`.
##   · `configure(plan)` takes `TitleState.prop_plan(state)` (chain_mode / ghosts /
##     souls_rate / souls_escape / braziers / knight_turns).
##   · `apply_grade(grade)` takes `TitleState.grade(state)` (forge heat, gear_speed,
##     lantern_lit, ember_rate, steam_rate, souls_*, braziers, knight_pose, ...).
##   · Widgets emit `fired(kind, payload)` for the one-shot world reactions:
##       strike / poured / delivered (and the extras documented per prop).
##   · Everything is built once in `_build()`; `advance()` never adds/removes nodes and
##     never allocates (fixed arrays, no per-frame dictionaries/strings).
##   · Deterministic: a fixed RNG seed (`SEED_BASE`, overridable through setup ctx) and
##     no wall-clock/TIME reads in game logic, so two instances fed the same dt
##     sequence end in exactly the same state.
##
## Wiring contract with `TitleWorld3D`: instantiate the prop script, `add_child()` it at
## world origin (props use hall world coordinates internally, see TitleLayout constants),
## then `setup(ctx)` -> `configure(plan)` -> `apply_grade(grade)`, and call
## `advance(dt)` once per frame. Menu focus reactions call the per-prop interaction
## methods (`surge()`, `strike_now()`, `gaze(seconds)`, `boost_braziers()`, `gust()`,
## `soul_boost(n)`, `lantern_pulse()`, `lantern_wave()`). Connect `fired` to spawn world
## sparks / flare the furnace.

signal fired(kind: StringName, payload: Dictionary)

const GEO := preload("res://scripts/title3d/props/prop_geo.gd")
## Shared 3D coordinate contract (title-kit owns this file; props read the same
## constants instead of duplicating positions). Preloaded, not class_name-referenced,
## so the headless test boot never depends on the global class cache.
const LAYOUT := preload("res://scripts/title3d/kit/layout.gd")

## A state machine step: mirrors the 2D base class so tests can feed big deltas.
const MAX_STEP := 0.1
## Fixed RNG seed: deterministic props across runs/machines.
const SEED_BASE := 0x51ED2701

# The 2D title palette, shared by every prop.
const OUTLINE := Color("#0B0910")
const IRON_DARK := Color("#241C22")
const IRON := Color("#3C343C")
const IRON_LIGHT := Color("#6A5A5E")
const HOT_CORE := Color(1.0, 0.93, 0.70)
const HOT := Color(1.0, 0.62, 0.20)
const HOT_DEEP := Color(0.86, 0.30, 0.10)
const EMBER_COOL := Color(0.42, 0.08, 0.04)
const GLOW_WARM := Color(1.0, 0.55, 0.20)
const STEEL := Color("#8A8F9A")
const STEEL_LIGHT := Color("#B9BEC8")
const STEEL_DARK := Color("#555B68")
const CLOTH := Color("#5C2A26")
const CLOTH_LIGHT := Color("#7C3A30")
const CLOTH_DARK := Color("#3A1A1C")
const EMBLEM := Color("#B08A4A")
const CLOAK := Color("#1B2230")
const CLOAK_RIM := Color("#3A4660")
const EYES := Color(0.62, 0.84, 1.0)
const LAMP := Color(1.0, 0.72, 0.35)
const SOUL_CORE := Color(0.92, 0.97, 1.0)
const SOUL_HALO := Color(0.55, 0.78, 1.0)
## Emissive multiplier when the hall is cold (the 2D `lift` trick, in 3D it only
## dims the glow halos; geometry brightness comes from the lighting rig).
const COLD_LIFT := 0.35

## Furnace heat 0..1.6 (2D `forge`, includes the 'new' menu surge). 0 = snuffed.
var heat := 0.0
## Additive glow brightness multiplier (2D `lift`): 1 = normal, < 1 = dark hall.
var lift := Color.WHITE
## Prop clock (seconds), advanced by `advance()`.
var t := 0.0
var rng := RandomNumberGenerator.new()
## Cloud-shade speed multiplier (settings menu: 0.3 while focused). Ambient props can
## read it; the light shaft itself lives in TitleLighting.
var cloud_scale := 1.0

var _built := false
var _plan: Dictionary = {}
var _grade: Dictionary = {}
var _ctx: Dictionary = {}
var _layout = null
var _seed := SEED_BASE
var _surge := 0.0
var _cloud_target := 1.0
var _glow_serial := 0


# ------------------------------------------------------------------- wiring ----

## One-time construction. Safe to call before or after `add_child()`; a second call
## only re-applies plan/grade (nodes are built once and never rebuilt).
func setup(ctx: Dictionary = {}) -> void:
	_ctx = ctx
	_layout = ctx.get("layout", null)
	_seed = int(ctx.get("seed", SEED_BASE))
	rng.seed = _seed
	if not _built:
		_build()
		_built = true
	_apply_plan()
	_apply_grade()
	_sync()


## `TitleState.prop_plan(state)`: variant structure (sword chain mode, ghost count,
## soul flow, braziers, knight turning). Tolerant: unknown keys are ignored.
func configure(plan: Dictionary) -> void:
	for key in plan:
		_plan[key] = plan[key]
	if _built:
		_apply_plan()
		_sync()


## `TitleState.grade(state)`: the per-variant look. Called again whenever the title
## state changes (and may be called every frame by the world with the same dict).
func apply_grade(grade: Dictionary) -> void:
	_grade = grade
	heat = float(grade.get("forge", grade.get("furnace", heat)))
	_apply_grade()
	if _built:
		_sync()


## Advance the prop clock. `dt` is split into <= MAX_STEP steps; node transforms are
## synced once at the end. Never allocates.
func advance(dt: float) -> void:
	if not _built or dt <= 0.0:
		return
	var left := dt
	while left > 0.0:
		var step := minf(left, MAX_STEP)
		left -= step
		t += step
		_surge = move_toward(_surge, 0.0, step * 0.9)
		cloud_scale = move_toward(cloud_scale, _cloud_target, step * 1.2)
		_tick(step)
	_sync()


## 'new' menu row: the furnace surges (heat + 50% for a moment, then decays).
func surge(strength: float = 1.0) -> void:
	_surge = maxf(_surge, strength)
	_on_surge(strength)
	if _built:
		_sync()


## 'settings' menu row: cloud shade / ambient drift slows down. Pass 1.0 to restore.
func slow_clouds(scale: float = 0.3) -> void:
	_cloud_target = clampf(scale, 0.05, 1.0)


# ------------------------------------------------------------------ overrides --

## Build every node/child here. Called once from setup().
func _build() -> void:
	pass


## Apply cached plan. Must only change parameters/visibility, never add nodes.
func _apply_plan() -> void:
	pass


## Apply cached grade. Must only change parameters/visibility, never add nodes.
func _apply_grade() -> void:
	pass


## Advance prop state by one step (<= MAX_STEP). No node sync needed here.
func _tick(_dt: float) -> void:
	pass


## Push the current state onto node transforms / visibility / glow tints.
func _sync() -> void:
	pass


func _on_surge(_strength: float) -> void:
	pass


# ---------------------------------------------------------------- lifecycle ---

func is_built() -> bool:
	return _built


func plan() -> Dictionary:
	return _plan


func grade() -> Dictionary:
	return _grade


func layout_ref():
	return _layout


## Effective heat (2D `heat` = grade forge * intro/quit level * (1 + surge * 0.5)).
func eff_heat() -> float:
	return clampf(heat * (1.0 + _surge * 0.5), 0.0, 1.6)


func heat01() -> float:
	return clampf(eff_heat(), 0.0, 1.0)


## 0..1 glow strength that also respects the dark (cold / quit) hall.
func glow01() -> float:
	return clampf(heat01() * lift.r, 0.0, 1.0)


## Movement speed multiplier: 0 at a snuffed forge, 2D clamps to [min_sp, max_sp].
func speed_scale(min_sp: float = 0.3, max_sp: float = 1.3) -> float:
	if heat < 0.06:
		return 0.0
	return clampf(heat, min_sp, max_sp)


# ------------------------------------------------------------- grade/plan -----

## Smoothstep 0..1 (2D title_prop.gd `smooth`).
func smooth01(p: float) -> float:
	var c := clampf(p, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func g_float(key: String, fallback: float = 0.0) -> float:
	return float(_grade.get(key, fallback))


func g_int(key: String, fallback: int = 0) -> int:
	return int(_grade.get(key, fallback))


func g_bool(key: String, fallback: bool = false) -> bool:
	return bool(_grade.get(key, fallback))


func g_color(key: String, fallback: Color = Color.WHITE) -> Color:
	var v = _grade.get(key, fallback)
	return v if v is Color else fallback


func g_name(key: String, fallback: StringName = &"") -> StringName:
	return StringName(_grade.get(key, fallback))


func p_float(key: String, fallback: float = 0.0) -> float:
	return float(_plan.get(key, fallback))


func p_int(key: String, fallback: int = 0) -> int:
	return int(_plan.get(key, fallback))


func p_bool(key: String, fallback: bool = false) -> bool:
	return bool(_plan.get(key, fallback))


# ------------------------------------------------------------ layout reads ----

## Read a TitleLayout constant by name (falls back to the prop's local default while
## the kit is still landing or when a constant is not provided yet).
func L(key: String, fallback: float) -> float:
	var v = _layout_value(key, null)
	if v is float or v is int:
		return float(v)
	return fallback


func LV3(key: String, fallback: Vector3) -> Vector3:
	var v = _layout_value(key, null)
	if v is Vector3:
		return v
	return fallback


func LV2(key: String, fallback: Vector2) -> Vector2:
	var v = _layout_value(key, null)
	if v is Vector2:
		return v
	return fallback


## Raw TitleLayout constant (Array / String / etc) by name, with a fallback.
func LV(key: String, fallback = null):
	return _layout_value(key, fallback)


func _layout_value(key: String, fallback):
	var script: Script = null
	if _layout is Script:
		script = _layout
	elif _layout is Object:
		script = _layout.get_script()
	if script == null:
		script = LAYOUT
	if script == null:
		return fallback
	var map: Dictionary = script.get_script_constant_map()
	return map.get(key, fallback)


# --------------------------------------------------------------- node build ---

## Merge `parts` into one mesh and add a MeshInstance3D at `pos` (under `parent`, or
## under this prop when `parent` is null). Defensive: an empty/failed merge still
## returns a (mesh-less) instance instead of passing null to add_child, so a broken
## primitive can never pollute the engine error stream mid-development.
func add_mesh(parts: Array, material: Material, node_name: String,
		pos: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var merged := GEO.merge(parts)
	if merged == null or merged.get_surface_count() == 0:
		push_warning("title3d prop %s: empty mesh for part group %s" % [name, node_name])
		merged = ArrayMesh.new()
	var mi := GEO.mesh_instance(merged, material, pos, node_name)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = merged
		mi.position = pos
	if parent == null:
		add_child(mi)
	else:
		parent.add_child(mi)
	return mi


## Add an additive billboard halo of `size_m` metres. Tint per frame with set_glow().
func add_glow(size_m: float, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := GEO.glow_quad(size_m)
	_glow_serial += 1
	mi.name = "Glow%d" % _glow_serial
	mi.position = pos
	add_child(mi)
	return mi


## Add a billboard pixel sprite (spark / soul / flame) with its own tintable material.
func add_sprite(width_m: float, height_m: float, tex: Texture2D,
		pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := GEO.sprite_quad(width_m, height_m, tex)
	_glow_serial += 1
	mi.name = "Sprite%d" % _glow_serial
	mi.position = pos
	add_child(mi)
	return mi


func set_glow(mi: MeshInstance3D, color: Color) -> void:
	GEO.tint_glow(mi, color)


func set_sprite(mi: MeshInstance3D, color: Color) -> void:
	GEO.tint_sprite(mi, color)


# ------------------------------------------------------------------- events ---

## Emit a one-shot world reaction. Payload dictionaries are only allocated on the
## (rare) event itself; never call this per frame.
func emit_fired(kind: StringName, payload: Dictionary = {}) -> void:
	fired.emit(kind, payload)


# ------------------------------------------------------------ test helpers ----

## Compact, allocation-free-in-game state digest used by the determinism test.
func state_snapshot() -> Dictionary:
	var out := {"t": t, "heat": heat, "surge": _surge}
	_snapshot_into(out)
	return out


func _snapshot_into(_out: Dictionary) -> void:
	pass


## Total descendants (tests assert it is unchanged after hundreds of advances).
func node_count() -> int:
	return _count_children(self)


func _count_children(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		n += 1 + _count_children(child)
	return n
