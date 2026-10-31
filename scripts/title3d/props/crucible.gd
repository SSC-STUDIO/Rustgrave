extends "res://scripts/title3d/props/title_prop3d.gd"
## Travelling crucible hoist (2D: scripts/ui/title_crucible.gd,
## docs/title-live-scene.md §6.1).
##
## The hoist rides the overhead rail from the forge side out over the lava chasm,
## stops, tips the pot and pours a thin (2 px) molten stream straight down ~13 m to
## the river. One ~22.6 s round at heat 1.0, ported 1:1 from the 2D phase table:
##   LOAD 2.0 -> TO_POUR 7.0 -> TILT 1.2 -> POUR 3.4 -> UNTILT 1.0 -> TO_LOAD 8.0
## `fired("poured")` the moment the stream reaches the lava (plus `fired("splash")`
## every 0.55 s while it keeps pouring). At a snuffed forge the hoist freezes at the
## load end, unlit.
##
## Coordinates: TitleLayout CRUCIBLE_RAIL_FROM/TO (y = 9.4, z = -9), lava at
## LAYOUT.LAVA_Y (-5.55). Node contract: rail/cart/pot/stream/sparks built once;
## advance() only moves the cart, rotates the pot, scales the stream and tints halos.

enum Phase { LOAD, TO_POUR, TILT, POUR, UNTILT, TO_LOAD }

const RAIL_FROM := Vector3(10.5, 9.4, -9.0)
const RAIL_TO := Vector3(2.0, 9.4, -9.0)
const LAVA_Y := -5.55
const T_LOAD := 2.0
const T_TO_POUR := 7.0
const T_TILT := 1.2
const T_POUR := 3.4
const T_UNTILT := 1.0
const T_TO_LOAD := 8.0
## The molten stream front falls at 10 m/s: it reaches the river ~1.3 s after tilting.
const STREAM_SPEED := 10.0
const SPLASH_EVERY := 0.55
const CUP_DROP := 1.35
const SPARK_COUNT := 8

var _rail_y := 9.4
var _from_x := RAIL_FROM.x
var _to_x := RAIL_TO.x
var _rail_z := -9.0
var _lava := LAVA_Y
var _cart: Node3D
var _pot: Node3D
var _chain: MeshInstance3D
var _pot_glow: MeshInstance3D
var _stream: MeshInstance3D
var _impact_glow: MeshInstance3D
var _sparks: Array[MeshInstance3D] = []
var _spark_pos := PackedVector3Array()
var _spark_vel := PackedVector3Array()
var _spark_age := PackedFloat32Array()
var _spark_span := PackedFloat32Array()
var _spark_alive := PackedByteArray()

var _phase: int = Phase.POUR
var _pt := 0.0
var _x := RAIL_TO.x
var _tilt := 0.0
var _stream_top := 0.0
var _stream_bot := 0.0
var _landed := false
var _splash_t := 0.0
var _pours := 0
var _impact_flash := 0.0
var _splash_pulse := 0.0


func _build() -> void:
	var from := LV3("CRUCIBLE_RAIL_FROM", RAIL_FROM)
	var to := LV3("CRUCIBLE_RAIL_TO", RAIL_TO)
	_rail_y = from.y
	_from_x = from.x
	_to_x = to.x
	_rail_z = from.z
	_lava = L("LAVA_Y", LAVA_Y)
	_x = _to_x
	var lo := minf(from.x, to.x) - 0.9
	var hi := maxf(from.x, to.x) + 0.9
	var z := from.z
	var span := hi - lo
	var mid := (lo + hi) * 0.5
	var parts: Array = []
	parts.append(GEO.box(Vector3(span, 0.16, 0.22), Vector3(mid, _rail_y + 0.10, z), IRON_DARK))
	parts.append(GEO.box(Vector3(span, 0.08, 0.10), Vector3(mid, _rail_y + 0.18, z), IRON_LIGHT))
	# hanger straps up to the roof truss + end stops
	var x := lo
	while x <= hi:
		parts.append(GEO.box(Vector3(0.08, 1.7, 0.08), Vector3(x, _rail_y + 0.95, z), IRON_DARK))
		parts.append(GEO.box(Vector3(0.28, 0.08, 0.28), Vector3(x, _rail_y + 0.22, z), IRON))
		x += 2.8
	parts.append(GEO.box(Vector3(0.3, 0.34, 0.3), Vector3(lo, _rail_y + 0.22, z), IRON_LIGHT))
	parts.append(GEO.box(Vector3(0.3, 0.34, 0.3), Vector3(hi, _rail_y + 0.22, z), IRON_LIGHT))
	var rail := add_mesh(parts, GEO.mat(0), "Rail")
	GEO.outline(rail, 1.0)
	# cart + hanging pot
	_cart = Node3D.new()
	_cart.name = "Cart"
	_cart.position = Vector3(_x, _rail_y, z)
	add_child(_cart)
	var cart_parts: Array = []
	cart_parts.append(GEO.box(Vector3(0.62, 0.24, 0.44), Vector3(0.0, -0.02, 0.0), IRON))
	cart_parts.append(GEO.box(Vector3(0.66, 0.08, 0.48), Vector3(0.0, 0.12, 0.0), IRON_LIGHT))
	for sx in [-1.0, 1.0]:
		cart_parts.append(GEO.cyl(0.11, 0.40, 8, Vector3(0.22 * sx, 0.0, 0.0), IRON_DARK,
				Vector3(0.0, 0.0, 90.0)))
	cart_parts.append(GEO.box(Vector3(0.10, 0.10, 0.10), Vector3(0.0, -0.18, 0.0), IRON_DARK))
	var cart_mi := add_mesh(cart_parts, GEO.mat(0), "Trolley", Vector3.ZERO, _cart)
	GEO.outline(cart_mi, 1.0)
	# chain links from the trolley down to the pot bail
	var chain_parts: Array = []
	for i in 4:
		var y := -0.24 - 0.24 * float(i)
		if i % 2 == 0:
			chain_parts.append(GEO.box(Vector3(0.06, 0.24, 0.04), Vector3(0.0, y, 0.0), IRON_LIGHT))
		else:
			chain_parts.append(GEO.box(Vector3(0.04, 0.24, 0.06), Vector3(0.0, y, 0.0), IRON))
	_chain = add_mesh(chain_parts, GEO.mat(0), "Chain", Vector3.ZERO, _cart)
	# the pot: a squat bucket riding a pivot so it can tip
	_pot = Node3D.new()
	_pot.name = "Pot"
	_pot.position = Vector3(0.0, -CUP_DROP, 0.0)
	_cart.add_child(_pot)
	var pot_parts: Array = []
	pot_parts.append(GEO.cyl(0.42, 0.52, 12, Vector3(0.0, -0.22, 0.0), IRON_DARK))
	pot_parts.append(GEO.cyl(0.46, 0.10, 12, Vector3(0.0, 0.04, 0.0), IRON))
	pot_parts.append(GEO.box(Vector3(0.20, 0.10, 0.20), Vector3(-0.40, 0.02, 0.0), IRON_LIGHT))
	pot_parts.append(GEO.box(Vector3(0.06, 0.34, 0.06), Vector3(0.0, 0.24, 0.0), IRON_DARK))
	var pot_mi := add_mesh(pot_parts, GEO.mat(0), "Bucket", Vector3.ZERO, _pot)
	GEO.outline(pot_mi, 1.0)
	# molten metal surface inside the pot (emissive, only while hot)
	var melt := MeshInstance3D.new()
	melt.name = "Melt"
	melt.mesh = GEO.merge([GEO.cyl(0.37, 0.06, 12, Vector3.ZERO, HOT, Vector3.ZERO, 1.0)])
	melt.material_override = GEO.mat(GEO.EMISSIVE)
	melt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	melt.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	melt.position = Vector3(0.0, 0.0, 0.0)
	_pot.add_child(melt)
	_pot_glow = GEO.glow_quad(1.6)
	_pot_glow.name = "PotGlow"
	_pot_glow.position = Vector3(0.0, -CUP_DROP - 0.05, 0.35)
	_cart.add_child(_pot_glow)
	# the pour stream: one thin box scaled in Y (2 px wide on the 640x360 target)
	_stream = MeshInstance3D.new()
	_stream.name = "Stream"
	_stream.mesh = GEO.merge([GEO.box(Vector3(0.11, 1.0, 0.11), Vector3.ZERO, HOT, Vector3.ZERO, 1.0)])
	_stream.material_override = GEO.mat(GEO.EMISSIVE)
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stream.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_stream.visible = false
	add_child(_stream)
	_impact_glow = GEO.glow_quad(3.4)
	_impact_glow.name = "ImpactGlow"
	add_child(_impact_glow)
	# pooled splash sparks
	_spark_pos.resize(SPARK_COUNT)
	_spark_vel.resize(SPARK_COUNT)
	_spark_age.resize(SPARK_COUNT)
	_spark_span.resize(SPARK_COUNT)
	_spark_alive.resize(SPARK_COUNT)
	for i in SPARK_COUNT:
		_spark_alive[i] = 0
		_spark_span[i] = 0.0
		_spark_age[i] = 0.0
		var spark := GEO.sprite_quad(0.30, 0.30, GEO.pixel_texture(2))
		spark.name = "Splash%d" % i
		spark.visible = false
		add_child(spark)
		_sparks.append(spark)
	# 2D parity: the title opens mid-pour so the stream is already growing.
	_phase = Phase.POUR
	_pt = 0.0
	_x = to.x
	_tilt = 1.0
	_stream_top = 0.0
	_stream_bot = 0.0
	_landed = false
	_apply_grade()
	_sync()


func _apply_grade() -> void:
	if is_built():
		_sync()


func speed() -> float:
	if heat < 0.06:
		return 0.0
	return clampf(heat, 0.25, 1.3)


func _duration(which: int) -> float:
	match which:
		Phase.LOAD:
			return T_LOAD
		Phase.TO_POUR:
			return T_TO_POUR
		Phase.TILT:
			return T_TILT
		Phase.POUR:
			return T_POUR
		Phase.UNTILT:
			return T_UNTILT
	return T_TO_LOAD


func _tick(dt: float) -> void:
	if _impact_flash > 0.0:
		_impact_flash = maxf(0.0, _impact_flash - dt * 2.4)
	if _splash_pulse > 0.0:
		_splash_pulse = maxf(0.0, _splash_pulse - dt * 4.0)
	_update_sparks(dt)
	var sp := speed()
	if sp <= 0.0:
		return
	var d := dt * sp
	_pt += d
	var dur := _duration(_phase)
	var p := clampf(_pt / dur, 0.0, 1.0)
	match _phase:
		Phase.LOAD:
			_x = _rail_right()
		Phase.TO_POUR:
			_x = lerpf(_rail_right(), _rail_left(), smooth01(p))
		Phase.TILT:
			_x = _rail_left()
			_tilt = p
		Phase.POUR:
			_tilt = 1.0
			_stream_bot = minf(_stream_bot + STREAM_SPEED * d, _stream_max())
			if not _landed and _stream_bot >= _stream_max():
				_landed = true
				_impact_flash = 1.0
				_splash_pulse = 1.0
				_pours += 1
				_splash_t = 0.0
				emit_fired(&"poured", {"position": _impact_point(), "pours": _pours})
			elif _landed:
				_splash_t += d
				if _splash_t >= SPLASH_EVERY:
					_splash_t -= SPLASH_EVERY
					_splash_pulse = 1.0
					_burst_sparks(2)
					emit_fired(&"splash", {"position": _impact_point()})
		Phase.UNTILT:
			_tilt = 1.0 - p
			_stream_top = minf(_stream_top + STREAM_SPEED * d, _stream_bot)
		Phase.TO_LOAD:
			_x = lerpf(_rail_left(), _rail_right(), smooth01(p))
	if p >= 1.0:
		_go((_phase + 1) % Phase.size())


func _go(next: int) -> void:
	_phase = next
	_pt = 0.0
	match next:
		Phase.POUR:
			_stream_top = 0.0
			_stream_bot = 0.0
			_landed = false
			_splash_t = 0.0
		Phase.TO_LOAD:
			_tilt = 0.0
			_stream_top = 0.0
			_stream_bot = 0.0
			_landed = false


func _rail_right() -> float:
	return _from_x


func _rail_left() -> float:
	return _to_x


## The stream front's maximum travel: from the tipped pot lip down to the lava.
func _stream_max() -> float:
	return _lip_point().y - _lava


## World position of the tipped pot's lip (the stream's top end).
func _lip_point() -> Vector3:
	return Vector3(_x - 0.44, _rail_y - CUP_DROP + 0.08, _rail_z)


func _impact_point() -> Vector3:
	var lip := _lip_point()
	return Vector3(lip.x, _lava, lip.z)


## 'poured' / spark payload position (world space label for the world FX layer).
func impact_point() -> Vector3:
	return _impact_point()


func _update_sparks(dt: float) -> void:
	for i in SPARK_COUNT:
		if _spark_alive[i] == 0:
			continue
		_spark_age[i] += dt
		if _spark_age[i] >= _spark_span[i]:
			_spark_alive[i] = 0
			_sparks[i].visible = false
			continue
		_spark_vel[i].y -= 5.0 * dt
		_spark_pos[i] += _spark_vel[i] * dt
		var fade := 1.0 - _spark_age[i] / maxf(_spark_span[i], 0.001)
		set_sprite(_sparks[i], Color(HOT.r, HOT.g, HOT.b, fade))


func _burst_sparks(count: int) -> void:
	var spawn := _impact_point()
	for i in SPARK_COUNT:
		if _spark_alive[i] == 1:
			continue
		var ang := rng.randf() * TAU
		_spark_pos[i] = spawn
		_spark_vel[i] = Vector3(cos(ang) * (0.8 + rng.randf() * 1.4),
				1.6 + rng.randf() * 2.2, sin(ang) * 0.9)
		_spark_age[i] = 0.0
		_spark_span[i] = 0.45 + rng.randf() * 0.4
		_spark_alive[i] = 1
		_sparks[i].visible = true
		count -= 1
		if count <= 0:
			break


func _sync() -> void:
	if _cart == null:
		return
	_cart.position = Vector3(_x, _rail_y, _cart.position.z)
	_pot.rotation.z = -_tilt * (PI * 0.5)
	var hot := heat01()
	var span := _stream_max()
	var visible_len := maxf(_stream_bot - _stream_top, 0.0)
	_stream.visible = visible_len > 0.01 and hot > 0.04
	if _stream.visible:
		var lip := _lip_point()
		var top_len := _stream_top
		_stream.position = Vector3(lip.x, lip.y - top_len - visible_len * 0.5, lip.z)
		_stream.scale = Vector3(1.0, maxf(visible_len, 0.02), 1.0)
	var flick := 0.8 + 0.2 * sin(floorf(t * 12.0) * 1.7)
	set_glow(_pot_glow, Color(1.0, 0.55, 0.2, 0.30 * hot * flick * (0.4 + 0.6 * _tilt)))
	var impact := _impact_point()
	_impact_glow.position = impact + Vector3(0.0, 0.35, 0.4)
	var impact_alpha := 0.0
	if _landed:
		impact_alpha = (0.35 + 0.25 * _splash_pulse + 0.6 * _impact_flash) * hot
	set_glow(_impact_glow, Color(1.0, 0.55, 0.18, clampf(impact_alpha, 0.0, 1.0)))
	for i in SPARK_COUNT:
		if _spark_alive[i] == 1:
			_sparks[i].position = _spark_pos[i]


## Jump straight to the pour (tools / tests): only valid while travelling or loading.
func force_pour() -> void:
	if _phase == Phase.LOAD or _phase == Phase.TO_POUR or _phase == Phase.TO_LOAD:
		_x = _rail_left()
		_go(Phase.TILT)


# ------------------------------------------------------------ test helpers ----

func phase() -> int:
	return _phase


func is_pouring() -> bool:
	return _phase == Phase.POUR and _stream_bot > _stream_top


func has_landed() -> bool:
	return _landed


func pour_count() -> int:
	return _pours


func trolley_x() -> float:
	return _x


func tilt() -> float:
	return _tilt


func stream_length() -> float:
	return maxf(_stream_bot - _stream_top, 0.0)


func is_frozen() -> bool:
	return speed() <= 0.0


func _snapshot_into(out: Dictionary) -> void:
	out["phase"] = _phase
	out["pt"] = snappedf(_pt, 0.000001)
	out["x"] = snappedf(_x, 0.000001)
	out["tilt"] = snappedf(_tilt, 0.000001)
	out["stream"] = snappedf(_stream_bot - _stream_top, 0.000001)
	out["pours"] = _pours
