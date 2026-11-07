extends "res://scripts/title3d/props/title_prop3d.gd"
## Greatsword conveyor (2D: scripts/ui/title_sword_chain.gd,
## docs/title-live-scene.md §6.1).
##
## Three named greatswords hang from travelling hooks on the rail: they ride from the
## left of the hall toward the forge mouth (TitleLayout SWORD_CHAIN_FROM -> TO),
## then drop down the vertical channel into the mouth. Each delivery fires
## `fired("delivered", {index, position})` for the world's spark burst + forge flare.
##
## Three modes (TitleState.prop_plan `chain_mode`):
##   RUN     the chain runs at a heat-driven speed; swords are loaded at the left end
##           (they grow in instead of popping)
##   EMPTY   the sword is gone ('give' / 'true_break'): hooks hang empty, the chain
##           does not move
##   STILL   the forge is out ('snuff'): the swords still hang on the chain, but it
##           no longer moves and the runes are cold
##
## Node contract: rail + three hook rigs (hook, blade, rune glow) built once; moving a
## sword is a transform write, EMPTY only toggles visibility.

const MODE_RUN := 0
const MODE_EMPTY := 1
const MODE_STILL := 2

const SWORD_COUNT := 3
const RAIL_FROM := Vector3(-5.0, 8.8, -8.0)
const RAIL_TO := Vector3(11.4, 8.8, -8.0)
## Below this the sword is hidden behind the forge mouth's wall: it has been fed in.
const DROP_END_Y := 2.6
## Metres per second at heat 1.0. Slow and ceremonial, like the 2D 6 px/s chain.
const SPEED := 0.8
## The last 0.25 m before the hanging point counts as "into the mouth".
const DELIVERY_GATE := 0.25
const SWORD_LENGTH := 2.5

var _mode := MODE_RUN
var _from := RAIL_FROM
var _to := RAIL_TO
var _horizontal := 16.4
var _vertical := 6.2
var _roll := 0.0
var _deliveries := 0
var _flash := 0.0
var _hooks: Array[Node3D] = []
var _blades: Array[MeshInstance3D] = []
var _runes: Array[MeshInstance3D] = []
var _glows: Array[MeshInstance3D] = []
var _mouth_glow: MeshInstance3D
var _prev := PackedFloat32Array()


func _build() -> void:
	_from = LV3("SWORD_CHAIN_FROM", RAIL_FROM)
	_to = LV3("SWORD_CHAIN_TO", RAIL_TO)
	_horizontal = maxf(_to.x - _from.x, 1.0)
	_vertical = maxf(_from.y - DROP_END_Y, 1.0)
	var parts: Array = []
	# twin rails + cross ties, then the vertical channel above the mouth
	parts.append(GEO.box(Vector3(_horizontal + 1.2, 0.14, 0.18),
			Vector3((_from.x + _to.x) * 0.5, _from.y + 0.08, _from.z), IRON_DARK))
	parts.append(GEO.box(Vector3(_horizontal + 1.2, 0.06, 0.12),
			Vector3((_from.x + _to.x) * 0.5, _from.y + 0.18, _from.z), IRON_LIGHT))
	var x := _from.x - 0.4
	while x <= _to.x + 0.4:
		parts.append(GEO.box(Vector3(0.10, 0.26, 0.10), Vector3(x, _from.y + 0.3, _from.z), IRON))
		x += 2.2
	parts.append(GEO.box(Vector3(0.26, _vertical + 0.4, 0.26),
			Vector3(_to.x, _from.y - (_vertical + 0.4) * 0.5 + 0.2, _from.z), IRON_DARK))
	parts.append(GEO.box(Vector3(0.5, 0.3, 0.5), Vector3(_to.x, _from.y - _vertical, _from.z), IRON))
	var rail := add_mesh(parts, GEO.mat(0), "Rail")
	GEO.outline(rail, 1.0)
	# the forge mouth flare: ticks up when a sword is fed in
	_mouth_glow = GEO.glow_quad(2.2)
	_mouth_glow.name = "MouthGlow"
	_mouth_glow.position = point_at(_horizontal + _vertical) + Vector3(0.0, 0.2, 0.45)
	add_child(_mouth_glow)
	_prev.resize(SWORD_COUNT)
	for i in SWORD_COUNT:
		_prev[i] = sword_s(i)
		var hook := Node3D.new()
		hook.name = "Sword%d" % i
		add_child(hook)
		_hooks.append(hook)
		add_mesh([GEO.box(Vector3(0.16, 0.16, 0.12), Vector3.ZERO, IRON_LIGHT),
				GEO.box(Vector3(0.04, 0.22, 0.04), Vector3(0.0, -0.16, 0.0), IRON)],
				GEO.mat(0), "Hook", Vector3.ZERO, hook)
		# the blade: hilt + crossguard + broad steel blade with a tapered tip
		var blade_parts: Array = []
		blade_parts.append(GEO.box(Vector3(0.10, 0.34, 0.10), Vector3(0.0, -0.44, 0.0), IRON_DARK))
		blade_parts.append(GEO.box(Vector3(0.16, 0.10, 0.16), Vector3(0.0, -0.66, 0.0), IRON_LIGHT))
		blade_parts.append(GEO.box(Vector3(0.78, 0.10, 0.18), Vector3(0.0, -0.80, 0.0), STEEL_DARK))
		blade_parts.append(GEO.box(Vector3(0.26, 1.55, 0.10), Vector3(0.0, -1.62, 0.0), STEEL))
		blade_parts.append(GEO.box(Vector3(0.06, 1.45, 0.12), Vector3(0.0, -1.60, 0.02), STEEL_LIGHT))
		blade_parts.append(GEO.box(Vector3(0.16, 0.22, 0.08), Vector3(0.0, -2.44, 0.0), STEEL_DARK))
		var blade := add_mesh(blade_parts, GEO.mat(0), "Blade", Vector3.ZERO, hook)
		GEO.outline(blade, 1.0)
		_blades.append(blade)
		# the four name-runes cut down the blade: only hot while the chain runs
		var rune := MeshInstance3D.new()
		rune.name = "Runes"
		var rune_parts: Array = []
		for m in 4:
			rune_parts.append(GEO.box(Vector3(0.09, 0.10, 0.03),
					Vector3(0.0, -1.05 - 0.30 * float(m), 0.07), HOT, Vector3.ZERO, 1.0))
		rune.mesh = GEO.merge(rune_parts)
		rune.material_override = GEO.mat(GEO.EMISSIVE)
		rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rune.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		hook.add_child(rune)
		_runes.append(rune)
		var glow := GEO.glow_quad(1.5)
		glow.name = "RuneGlow"
		glow.position = Vector3(0.0, -1.6, 0.25)
		hook.add_child(glow)
		_glows.append(glow)
	_apply_grade()
	_sync()


func _apply_plan() -> void:
	if _plan.has("chain_mode"):
		set_mode(int(_plan["chain_mode"]))
	if _plan.has("chain_speed"):
		pass


func _apply_grade() -> void:
	if _grade.has("chain_mode"):
		set_mode(int(_grade["chain_mode"]))
	if is_built():
		_sync()


func set_mode(new_mode: int) -> void:
	_mode = clampi(new_mode, 0, 2)
	if is_built():
		_sync()


func mode() -> int:
	return _mode


func speed() -> float:
	if _mode != MODE_RUN or heat < 0.06:
		return 0.0
	return SPEED * clampf(heat, 0.2, 1.3)


## Full path length: horizontal run + the vertical drop into the mouth.
func path_length() -> float:
	return _horizontal + _vertical


## Distance s (0 = hanging point at the rail start) -> hang position.
func point_at(s: float) -> Vector3:
	if s <= _horizontal:
		return Vector3(_from.x + s, _from.y, _from.z)
	return Vector3(_to.x, _from.y - (s - _horizontal), _from.z)


## Current distance travelled by sword i (they are equally spaced on the closed loop).
func sword_s(i: int) -> float:
	var length := path_length()
	return fposmod(_roll + float(i) * length / float(SWORD_COUNT), length)


func _tick(dt: float) -> void:
	_flash = move_toward(_flash, 0.0, dt * 1.6)
	var v := speed()
	if v <= 0.0:
		return
	_roll += v * dt
	var gate := path_length() - DELIVERY_GATE
	for i in SWORD_COUNT:
		var s := sword_s(i)
		if _prev[i] < gate and s >= gate:
			_deliveries += 1
			_flash = 1.0
			emit_fired(&"delivered", {"index": i, "position": point_at(s),
					"deliveries": _deliveries})
		_prev[i] = s


func _sync() -> void:
	if _hooks.is_empty():
		return
	var running := _mode == MODE_RUN
	var hot := heat01()
	for i in SWORD_COUNT:
		var hook := _hooks[i]
		var s := sword_s(i)
		if _mode == MODE_EMPTY:
			hook.position = point_at(s)
			hook.scale = Vector3.ONE
			_blades[i].visible = false
			_runes[i].visible = false
			_glows[i].visible = false
			continue
		var at := point_at(s)
		hook.position = at
		_blades[i].visible = true
		# swords grow in as they are hung on at the left end (2D fade-in)
		var grow := clampf(s / 0.6, 0.0, 1.0)
		_hooks[i].scale = Vector3.ONE * maxf(grow, 0.001)
		var warm := running and hot > 0.06
		_runes[i].visible = warm
		_runes[i].scale = Vector3.ONE
		var alpha := clampf(0.35 * hot, 0.0, 0.6) * (0.7 + 0.3 * sin(floorf(t * 6.0) + float(i)))
		if not warm:
			alpha = 0.0
		set_glow(_glows[i], Color(1.0, 0.55, 0.22, alpha))
	# the mouth receives the sword: a short flare at the channel end
	var mouth_warm := clampf(_flash, 0.0, 1.0) * clampf(heat01(), 0.0, 1.0)
	set_glow(_mouth_glow, Color(1.0, 0.55, 0.2, 0.55 * mouth_warm))


# ------------------------------------------------------------ test helpers ----

func deliveries() -> int:
	return _deliveries


func roll() -> float:
	return _roll


func is_moving() -> bool:
	return speed() > 0.0


## Swords currently drawn (EMPTY = 0).
func visible_swords() -> int:
	var n := 0
	for i in SWORD_COUNT:
		if _blades[i].visible:
			n += 1
	return n


func sword_position(i: int) -> Vector3:
	if i < 0 or i >= _hooks.size():
		return Vector3.ZERO
	return _hooks[i].position


func runes_lit() -> bool:
	for i in SWORD_COUNT:
		if _runes[i].visible:
			return true
	return false


func _snapshot_into(out: Dictionary) -> void:
	out["mode"] = _mode
	out["roll"] = snappedf(_roll, 0.000001)
	out["deliveries"] = _deliveries
	out["visible"] = visible_swords()
