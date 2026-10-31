extends "res://scripts/title3d/props/title_prop3d.gd"
## Lantern-bearing ghosts on the far catwalk (2D: scripts/ui/title_ghosts.gd,
## docs/title-live-scene.md §6.1).
##
## Up to three hooded silhouettes patrol the far catwalk (TitleLayout
## FAR_CATWALK_*, z = -24) toward the forge, wrap behind the machine housings and come
## back out on the left. Each carries a warm lantern: an emissive cage plus an additive
## halo, but no real light (the light budget is the lighting rig's). Their stride is the
## 2D two-frame step; they only walk while the forge is hot.
##
## Node contract: exactly three rigs are built (cloak, eyes, lantern, halo); the plan's
## `ghosts` / the grade's `ghost_count` only toggles visibility. advance() writes
## transforms and halo tints, never nodes.

const MAX_GHOSTS := 3
const CATWALK_Y := 1.2
const CATWALK_Z := -24.0
const WALK_LEFT := -10.0
const WALK_RIGHT := 10.0
## 2D: 7 px/s -> 0.26 m/s on the 0.0375 m/texel contract. Extremely slow on purpose.
const SPEED := 0.30
const LAMP_GLOW := 1.5

var _rigs: Array[Node3D] = []
var _glows: Array[MeshInstance3D] = []
var _count := 0
var _walk := 0.0
var _catwalk_y := CATWALK_Y
var _catwalk_z := CATWALK_Z
var _walk_left := WALK_LEFT
var _walk_right := WALK_RIGHT


func _build() -> void:
	_catwalk_y = L("FAR_CATWALK_Y", CATWALK_Y)
	_catwalk_z = L("FAR_CATWALK_Z", CATWALK_Z)
	var half := L("FAR_CATWALK_HALF_X", WALK_RIGHT)
	_walk_left = -half
	_walk_right = half
	for i in MAX_GHOSTS:
		var rig := Node3D.new()
		rig.name = "Ghost%d" % i
		rig.position = Vector3(_walk_left, _catwalk_y, _catwalk_z)
		rig.visible = false
		add_child(rig)
		_rigs.append(rig)
		# cloak + hood silhouette (one merged mesh)
		var parts: Array = []
		parts.append(GEO.box(Vector3(0.46, 0.62, 0.30), Vector3(0.0, 0.62, 0.0), CLOAK))
		parts.append(GEO.box(Vector3(0.52, 0.22, 0.34), Vector3(0.0, 0.28, 0.0), CLOAK))
		parts.append(GEO.box(Vector3(0.34, 0.30, 0.28), Vector3(0.0, 1.06, 0.0), CLOAK))
		parts.append(GEO.box(Vector3(0.36, 0.05, 0.30), Vector3(0.0, 1.21, 0.0), CLOAK_RIM))
		parts.append(GEO.box(Vector3(0.05, 0.52, 0.05), Vector3(-0.20, 0.62, 0.12), CLOAK_RIM))
		var legs := GEO.box(Vector3(0.14, 0.28, 0.16), Vector3(-0.11, 0.10, 0.0), CLOAK)
		parts.append(legs)
		parts.append(GEO.box(Vector3(0.14, 0.28, 0.16), Vector3(0.11, 0.10, 0.0), CLOAK))
		var cloak := add_mesh(parts, GEO.mat(0), "Cloak", Vector3.ZERO, rig)
		GEO.outline(cloak, 1.0)
		# two hood lights
		var eyes := MeshInstance3D.new()
		eyes.name = "Eyes"
		var eye_parts: Array = []
		for ex in [-0.07, 0.07]:
			eye_parts.append(GEO.box(Vector3(0.06, 0.05, 0.03), Vector3(ex, 1.08, 0.15),
					EYES, Vector3.ZERO, 1.0))
		eyes.mesh = GEO.merge(eye_parts)
		eyes.material_override = GEO.mat(GEO.EMISSIVE)
		eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eyes.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		rig.add_child(eyes)
		# hand lantern: pole + emissive cage
		var lantern := MeshInstance3D.new()
		lantern.name = "Lantern"
		var lamp_parts: Array = []
		lamp_parts.append(GEO.box(Vector3(0.04, 0.36, 0.04), Vector3(0.34, 0.70, 0.05), CLOAK_RIM))
		lamp_parts.append(GEO.box(Vector3(0.16, 0.18, 0.16), Vector3(0.36, 0.48, 0.05),
				LAMP, Vector3.ZERO, 1.0))
		lantern.mesh = GEO.merge(lamp_parts)
		lantern.material_override = GEO.mat(GEO.EMISSIVE)
		lantern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lantern.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		rig.add_child(lantern)
		var glow := GEO.glow_quad(LAMP_GLOW)
		glow.name = "LampGlow"
		glow.position = Vector3(0.36, 0.48, 0.22)
		rig.add_child(glow)
		_glows.append(glow)
	_apply_grade()
	_sync()


func _apply_plan() -> void:
	if _plan.has("ghosts"):
		set_count(int(_plan["ghosts"]))


func _apply_grade() -> void:
	var g := g_int("ghost_count", -1)
	if g >= 0:
		set_count(g)
	if is_built():
		_sync()


## Show exactly n of the three ghosts (0..3).
func set_count(n: int) -> void:
	_count = clampi(n, 0, MAX_GHOSTS)
	for i in MAX_GHOSTS:
		_rigs[i].visible = i < _count


func count() -> int:
	return _count


## How many silhouette rigs are actually drawn right now.
func visible_count() -> int:
	var n := 0
	for rig in _rigs:
		if rig.visible:
			n += 1
	return n


func speed() -> float:
	if _count <= 0:
		return 0.0
	return SPEED * clampf(heat, 0.35, 1.0)


func _tick(dt: float) -> void:
	_walk += speed() * dt


## Loop length of the patrol (metres).
func loop_length() -> float:
	return _walk_right - _walk_left


func ghost_x(index: int) -> float:
	if _count <= 0:
		return _walk_left
	return _walk_left + fposmod(_walk + float(index) * loop_length() / float(MAX_GHOSTS),
			loop_length())


## Two-frame stride (2D parity): 0 / 1, the body steps up one pixel-ish on 1.
func stride(index: int) -> int:
	return int(floorf(t * 1.8 + float(index) * 0.7)) % 2


func _sync() -> void:
	if _rigs.is_empty():
		return
	var hot := clampf(heat01(), 0.0, 1.0)
	var flick_base := 0.8 + 0.2 * sin(floorf(t * 10.0) * 2.3)
	for i in MAX_GHOSTS:
		var rig := _rigs[i]
		if not rig.visible:
			continue
		var x := ghost_x(i)
		var step := stride(i)
		var bob := -0.045 * float(step)
		rig.position = Vector3(x, _catwalk_y + bob, _catwalk_z)
		var flick := flick_base * (0.85 + 0.15 * sin(float(i) * 1.7 + floorf(t * 10.0)))
		var alpha := clampf(0.55 * (0.35 + 0.65 * hot), 0.0, 0.9) * flick
		set_glow(_glows[i], Color(LAMP.r, LAMP.g, LAMP.b, alpha))


# ------------------------------------------------------------ test helpers ----

func max_ghosts() -> int:
	return MAX_GHOSTS


func walked() -> float:
	return _walk


func _snapshot_into(out: Dictionary) -> void:
	out["count"] = _count
	out["walk"] = snappedf(_walk, 0.000001)
	out["x0"] = snappedf(ghost_x(0), 0.000001)
