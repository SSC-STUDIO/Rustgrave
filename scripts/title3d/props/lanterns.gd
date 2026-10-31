extends "res://scripts/title3d/props/title_prop3d.gd"
## Roof chains and the 14 progress lanterns of the 3D forge hall
## (2D: scripts/ui/title_chain.gd + title_lantern.gd, docs/title-live-scene.md §6.1).
##
## · 6 decorative chains hang from the lantern rail, ending in an iron weight.
## · 14 lanterns hang in two rows of seven (front row at LANTERN_FRONT_Z, back row at
##   LANTERN_BACK_Z), each on its own chain so it can swing on a slow sine.
## · Exactly `grade.lantern_lit` (0..14) of them are lit — one per cleared chapter,
##   N/14 — revealed from the far/high row toward the near/low row (`set_lit`),
##   fading in per lantern like the 2D intro, and doused one by one on `quit_out`.
## · `lantern_pulse()` / `lantern_wave()` are the menu-focus flare reactions; the
##   flame flicker runs on a 12 fps stepped clock (2D parity).
##
## Node contract: 6 decorative chain rigs + 14 lantern rigs, built once. `advance()`
## never creates or frees a node; it only writes rotations/visibility/scale/tint.

const LANTERN_COUNT := 14
const DECOR_CHAINS := 6
const TOP_Y := 11.2
const HANG_Y := 6.8
const FRONT_Z := 2.2
const BACK_Z := -2.8
const LANTERN_RADIUS := 0.46
const LANTERN_XS := [-7.5, -5.0, -2.5, 0.0, 2.5, 5.0, 7.5]
## Sway: the whole chain swings; per-chain phase keeps the rail from snapping in unison.
const SWAY_DEG := 2.0
const SWAY_PERIOD := 6.8
## A lit lantern's additive halo diameter (metres) at full heat.
const GLOW_SIZE := 2.3
## 2D lantern flicker is stepped at 12 fps, not a smooth fade.
const FLICKER_FPS := 12.0

var _chain_rigs: Array[Node3D] = []
var _lantern_rigs: Array[Node3D] = []
var _lit: PackedFloat32Array = PackedFloat32Array()
var _lit_target: PackedByteArray = PackedByteArray()
var _flare: PackedFloat32Array = PackedFloat32Array()
var _cores: Array[MeshInstance3D] = []
var _glows: Array[MeshInstance3D] = []
## Lantern indices in "far/high row first" order (2D intro reveal order).
var _lit_order: Array[int] = []
var _tint := LAMP
var _wave_t := -1.0
var _wave_next := 0
## quit_out: douse one lantern every `_douse_stagger` seconds, last lit first.
var _douse_stagger := 0.0
var _douse_t := 0.0


func _build() -> void:
	_lit.resize(LANTERN_COUNT)
	_lit_target.resize(LANTERN_COUNT)
	_flare.resize(LANTERN_COUNT)
	for i in LANTERN_COUNT:
		_lit[i] = 0.0
		_lit_target[i] = 0
		_flare[i] = 0.0
	_tint = g_color("lantern", LAMP)
	_rails()
	_decorative_chains()
	_build_lantern_rigs()
	# Reveal order: back (farther, higher on screen) row first, then the front row.
	for i in LANTERN_COUNT:
		_lit_order.append(i)
	_lit_order.sort_custom(func(a: int, b: int) -> bool:
		var za := FRONT_Z if a < 7 else BACK_Z
		var zb := FRONT_Z if b < 7 else BACK_Z
		if is_equal_approx(za, zb):
			return a < b
		return za < zb)
	_apply_grade()
	_sync()


## The rail the chains hang from (one static mesh with brackets and hanger plates).
func _rails() -> void:
	var parts: Array = []
	var half := 8.6
	parts.append(GEO.box(Vector3(half * 2.0, 0.22, 0.22), Vector3(0.0, TOP_Y + 0.12, FRONT_Z), IRON_DARK))
	parts.append(GEO.box(Vector3(0.10, 0.10, BACK_Z * -2.0 + 1.0), Vector3(half, TOP_Y + 0.12, (FRONT_Z + BACK_Z) * 0.5), IRON_DARK))
	parts.append(GEO.box(Vector3(0.10, 0.10, BACK_Z * -2.0 + 1.0), Vector3(-half, TOP_Y + 0.12, (FRONT_Z + BACK_Z) * 0.5), IRON_DARK))
	parts.append(GEO.box(Vector3(half * 2.0, 0.10, 0.12), Vector3(0.0, TOP_Y + 0.12, BACK_Z), IRON))
	for z in [FRONT_Z, BACK_Z]:
		for i in LANTERN_COUNT / 2:
			var x := -7.5 + float(i) * 2.5
			parts.append(GEO.box(Vector3(0.16, 0.16, 0.16), Vector3(x, TOP_Y + 0.05, z), IRON_LIGHT))
	add_mesh(parts, GEO.mat(0), "Rail")


## Six free-hanging chains with an iron weight at the end (pure decoration, 2D parity).
func _decorative_chains() -> void:
	for i in DECOR_CHAINS:
		var x := -8.4 + float(i) * 3.35
		var z := FRONT_Z if i % 2 == 0 else BACK_Z
		var rig := Node3D.new()
		rig.name = "Chain%d" % i
		rig.position = Vector3(x, TOP_Y, z)
		add_child(rig)
		var length := 3.2 + 0.55 * float((i * 5) % 3)
		var parts: Array = []
		var links := int(length / 0.34)
		for k in links:
			var y := -0.14 - 0.34 * float(k)
			if k % 2 == 0:
				parts.append(GEO.box(Vector3(0.12, 0.30, 0.05), Vector3(0.0, y, 0.0), IRON_LIGHT))
			else:
				parts.append(GEO.box(Vector3(0.05, 0.30, 0.12), Vector3(0.0, y, 0.0), IRON))
		parts.append(GEO.box(Vector3(0.26, 0.24, 0.20), Vector3(0.0, -length - 0.28, 0.0), IRON_DARK))
		add_mesh(parts, GEO.mat(0), "Links", Vector3.ZERO, rig)
		_chain_rigs.append(rig)


## Fourteen lantern rigs: front row (nearest camera) then the back row. All positions
## come from the shared TitleLayout constants.
func _build_lantern_rigs() -> void:
	var top_y := L("LANTERN_TOP_Y", TOP_Y)
	var hang_y := L("LANTERN_HANG_Y", HANG_Y)
	var front_z := L("LANTERN_FRONT_Z", FRONT_Z)
	var back_z := L("LANTERN_BACK_Z", BACK_Z)
	var xs_value = LV("LANTERN_XS", LANTERN_XS)
	var xs: Array = xs_value if xs_value is Array else LANTERN_XS
	var drop := maxf(top_y - hang_y, 1.0)
	for i in LANTERN_COUNT:
		var row := 0 if i < 7 else 1
		var col := i % 7
		var x := float(xs[col]) if col < xs.size() else -7.5 + float(col) * 2.5
		var z := front_z if row == 0 else back_z
		var rig := Node3D.new()
		rig.name = "Lantern%d" % i
		rig.position = Vector3(x, top_y, z)
		add_child(rig)
		_lantern_rigs.append(rig)
		# chain down to the cage roof; the cage is baked into the same mesh (the rig
		# only ever rotates as a whole, so one MeshInstance per lantern is enough)
		var chain_span := drop - 0.62
		var parts: Array = []
		var links := maxi(int(chain_span / 0.34), 2)
		for k in links:
			var y := -0.10 - 0.34 * float(k)
			if k % 2 == 0:
				parts.append(GEO.box(Vector3(0.085, 0.30, 0.04), Vector3(0.0, y, 0.0), IRON_LIGHT))
			else:
				parts.append(GEO.box(Vector3(0.04, 0.30, 0.085), Vector3(0.0, y, 0.0), IRON))
		var cage_offset := Vector3(0.0, -drop, 0.0)
		for part in _cage_parts():
			var xf: Transform3D = part["xform"]
			xf.origin += cage_offset
			part["xform"] = xf
			parts.append(part)
		add_mesh(parts, GEO.mat(0), "Body", Vector3.ZERO, rig)
		# glass/flame core: emissive, hidden until the lantern is lit
		var core := MeshInstance3D.new()
		core.name = "Core"
		core.mesh = GEO.merge([GEO.box(Vector3(0.30, 0.34, 0.30), Vector3.ZERO, HOT_CORE,
				Vector3.ZERO, 1.0)])
		core.material_override = GEO.mat(GEO.EMISSIVE)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		core.position = Vector3(0.0, -drop, 0.0)
		rig.add_child(core)
		_cores.append(core)
		var glow := GEO.glow_quad(GLOW_SIZE)
		glow.name = "Halo"
		glow.position = Vector3(0.0, -drop, 0.16)
		rig.add_child(glow)
		_glows.append(glow)


## A small iron cage: frame rings, corner posts, pitched roof and hook.
func _cage_parts() -> Array:
	var r := LANTERN_RADIUS
	var parts: Array = []
	parts.append(GEO.box(Vector3(r * 1.55, 0.10, r * 1.55), Vector3(0.0, 0.34, 0.0), IRON))
	parts.append(GEO.box(Vector3(r * 1.55, 0.10, r * 1.55), Vector3(0.0, -0.34, 0.0), IRON_DARK))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append(GEO.box(Vector3(0.075, 0.70, 0.075),
					Vector3(r * 0.72 * sx, 0.0, r * 0.72 * sz), IRON_LIGHT))
	parts.append(GEO.box(Vector3(r * 1.85, 0.12, r * 1.85), Vector3(0.0, 0.44, 0.0), IRON))
	parts.append(GEO.box(Vector3(r * 0.95, 0.12, r * 0.95), Vector3(0.0, 0.56, 0.0), IRON_LIGHT))
	parts.append(GEO.box(Vector3(0.05, 0.26, 0.05), Vector3(0.0, 0.72, 0.0), IRON_DARK))
	return parts


# ------------------------------------------------------------------ plan ------

func _apply_plan() -> void:
	if _plan.has("lantern_lit"):
		set_lit(int(_plan["lantern_lit"]))


func _apply_grade() -> void:
	_tint = g_color("lantern", LAMP)
	var lit := g_int("lantern_lit", -1)
	if lit >= 0:
		set_lit(lit)
	if is_built():
		_sync()


## TitleWorld3D name for `set_lit_count` (old TitleWorld callback compatibility):
## light exactly `n` of the fourteen lanterns, fading each one in.
func set_lit(n: int) -> void:
	set_lit_count(n, false)


## Light exactly `n` of the fourteen lanterns. `instant` skips the per-lantern fade.
func set_lit_count(n: int, instant: bool = false) -> void:
	var count := clampi(n, 0, LANTERN_COUNT)
	for i in LANTERN_COUNT:
		_lit_target[i] = 0
	for rank in count:
		if rank < _lit_order.size():
			_lit_target[_lit_order[rank]] = 1
	if instant:
		for i in LANTERN_COUNT:
			_lit[i] = float(_lit_target[i])


## TitleWorld3D quit sequence: the first lantern goes out immediately (2D parity),
## then one every `seconds_per_lantern`.
func quit_out(seconds_per_lantern: float) -> void:
	_douse_stagger = maxf(seconds_per_lantern, 0.01)
	_douse_t = 0.0
	_douse_one()


## Menu focus: every lantern flares once (2D `nudge`).
func lantern_pulse(strength: float = 1.0) -> void:
	for i in LANTERN_COUNT:
		if _lit_target[i] == 1:
			_flare[i] = maxf(_flare[i], 0.9 * strength)


## 'continue' reaction: the lit lanterns flare one after another, near to far.
func lantern_wave() -> void:
	_wave_t = 0.0
	_wave_next = 0


func _tick(dt: float) -> void:
	for i in LANTERN_COUNT:
		_lit[i] = move_toward(_lit[i], float(_lit_target[i]), dt * 5.0)
		_flare[i] = maxf(0.0, _flare[i] - dt * 1.6)
	if _wave_t >= 0.0:
		_wave_t += dt
		while _wave_next < LANTERN_COUNT and _wave_t >= 0.16 * float(_wave_next):
			var idx := _lit_order[_wave_next] if _wave_next < _lit_order.size() else _wave_next
			if _lit_target[idx] == 1:
				_flare[idx] = maxf(_flare[idx], 0.9)
			_wave_next += 1
		if _wave_next >= LANTERN_COUNT:
			_wave_t = -1.0
	if _douse_stagger > 0.0:
		_douse_t += dt
		while _douse_t >= _douse_stagger:
			_douse_t -= _douse_stagger
			if not _douse_one():
				_douse_stagger = 0.0
				break


## Extinguish the next still-lit lantern, if any (lowest index first, like the 2D
## TitleWorld.quit_out tween order).
func _douse_one() -> bool:
	for i in LANTERN_COUNT:
		if _lit_target[i] == 1:
			_lit_target[i] = 0
			return true
	return false


func _sync() -> void:
	if _lantern_rigs.is_empty():
		return
	var step := floorf(t * FLICKER_FPS)
	var glow_scale := glow01()
	for i in _chain_rigs.size():
		_chain_rigs[i].rotation.z = deg_to_rad(SWAY_DEG) * sin(
				t * TAU / SWAY_PERIOD + float(i) * 1.17)
	for i in LANTERN_COUNT:
		var rig := _lantern_rigs[i]
		var phase := 0.6 + float(i) * 0.73
		rig.rotation.z = deg_to_rad(SWAY_DEG * 0.8) * sin(t * TAU / SWAY_PERIOD + phase)
		rig.rotation.x = deg_to_rad(SWAY_DEG * 0.45) * cos(
				t * TAU / (SWAY_PERIOD * 1.7) + phase)
		var energy := _lit[i] * _flicker(i, step) + _flare[i] * 0.9
		var on := _lit[i] > 0.02
		var core := _cores[i]
		core.visible = on
		core.scale = Vector3.ONE * (0.72 + 0.34 * clampf(energy, 0.0, 1.6))
		var alpha := clampf(0.42 * energy, 0.0, 0.95) * maxf(glow_scale, 0.25)
		set_glow(_glows[i], Color(_tint.r, _tint.g, _tint.b, alpha))


## 12 fps stepped flame flicker (2D parity): deterministic per lantern and clock step.
func _flicker(index: int, step: float) -> float:
	var seed_value := float(index) * 3.7
	var n := sin(step * 1.7 + seed_value) * 0.6 + sin(step * 4.3 + seed_value * 2.0) * 0.4
	return clampf(1.0 + g_float("lantern_flicker", 1.0) * 0.18 * n, 0.55, 1.45)


# ------------------------------------------------------------ test helpers ----

func lantern_count() -> int:
	return LANTERN_COUNT


func chain_count() -> int:
	return DECOR_CHAINS


## Lanterns whose state is lit (the exact N/14 mapping, independent of fade progress).
func lit_count() -> int:
	var n := 0
	for i in LANTERN_COUNT:
		n += int(_lit_target[i])
	return n


## Lanterns that are visually on right now (fade progress > half).
func glowing_count() -> int:
	var n := 0
	for i in LANTERN_COUNT:
		if _lit[i] > 0.5:
			n += 1
	return n


func lantern_lit(index: int) -> bool:
	return index >= 0 and index < LANTERN_COUNT and _lit_target[index] == 1


func halo_alpha(index: int) -> float:
	if index < 0 or index >= _glows.size():
		return 0.0
	var prim := _glows[index].mesh as PrimitiveMesh
	if prim == null:
		return 0.0
	var m := prim.material as StandardMaterial3D
	return m.albedo_color.a if m != null else 0.0


func lantern_position(index: int) -> Vector3:
	if index < 0 or index >= _lantern_rigs.size():
		return Vector3.ZERO
	return _lantern_rigs[index].global_position


func _snapshot_into(out: Dictionary) -> void:
	out["lit"] = lit_count()
	out["glowing"] = glowing_count()
	out["halo0"] = snappedf(halo_alpha(0), 0.000001)
	out["halo13"] = snappedf(halo_alpha(13), 0.000001)
	out["sway"] = snappedf(_lantern_rigs[0].rotation.z if not _lantern_rigs.is_empty() else 0.0,
			0.000001)
