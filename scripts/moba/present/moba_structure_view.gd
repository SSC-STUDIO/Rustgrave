extends Node3D
## Visible tower / crystal for the sim-driven arena.
##
## MobaSim publishes the structure health and the winner; the world position
## comes from MobaViewMap (tower lane x = +-16, crystal lane x = +-26). This node
## owns the 3D structure, its floating health bar, the beam/light pool, the hit
## flash and the destruction animation (tower topples and goes dark, crystal
## gem shatters into the plinth). It never decides damage by itself: apply() is
## fed the values the simulation settled.

const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const TOON_PART := preload("res://scripts/moba/view/toon_part.gd")
const FX := preload("res://scripts/moba/present/moba_unit_fx.gd")
const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")

const TOWER_STONE := Color("#8a8680")
const TOWER_DARK := Color("#4a3e36")
const COLLAPSE_TIME := 0.9
const FLASH_TIME := 0.12

var kind: StringName = &"tower"
var team := 0
var max_hp := 1200.0
var hp := 1200.0
var destroyed := false

var _root: Node3D
var _gem: TOON_PART
var _flame: TOON_PART
var _pool: MeshInstance3D
var _bar_root: Node3D
var _bar_back: MeshInstance3D
var _bar_fill: MeshInstance3D
var _bar_width := 2.6
var _parts: Array[MeshInstance3D] = []
var _flash_timer := 0.0
var _collapse_t := -1.0
var _clock := 0.0
var _gem_base_y := 2.85


## Configured before add_child() so _ready() builds the right silhouette.
func setup(structure_kind: StringName, structure_team: int) -> void:
	kind = structure_kind
	team = structure_team
	max_hp = VIEW_MAP.structure_hp(kind)
	hp = max_hp


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "Visual"
	add_child(_root)
	if kind == &"crystal":
		_build_crystal()
	else:
		_build_tower()
	_build_bar()
	_parts = FX.collect_parts(_root)
	_apply_bar()
	_apply_look()


## Fed with the simulation's structure state (hp possibly float/int).
func apply(hp_value: float, max_hp_value: float, alive: bool) -> void:
	var new_max := maxf(1.0, max_hp_value)
	if new_max != max_hp:
		max_hp = new_max
	var new_hp := clampf(hp_value, 0.0, max_hp)
	if new_hp < hp - 0.01 and not destroyed:
		flash()
	hp = new_hp
	_apply_bar()
	if destroyed:
		return
	if not alive or hp <= 0.0:
		destroy()


## Collapse without a health change (the crystal itself never gets destroyed
## twice; kept public so the restart flow can reset through reset_state()).
func destroy() -> void:
	if destroyed:
		return
	destroyed = true
	_collapse_t = 0.0
	_bar_root.visible = false
	_flash_timer = FLASH_TIME
	FX.set_flash(_parts, true)
	if _flame != null:
		_flame.visible = false
	if _pool != null:
		_pool.visible = false


func reset_state() -> void:
	destroyed = false
	_collapse_t = -1.0
	_flash_timer = 0.0
	hp = max_hp
	_root.rotation = Vector3.ZERO
	_root.position = Vector3.ZERO
	if _gem != null:
		_gem.scale = Vector3.ONE
		_gem.position = Vector3(0.0, _gem_base_y, 0.0)
	if _flame != null:
		_flame.visible = true
	if _pool != null:
		_pool.visible = true
	_bar_root.visible = true
	FX.set_flash(_parts, false)
	FX.set_fade(_parts, 1.0)
	_apply_bar()


func flash() -> void:
	if destroyed:
		return
	_flash_timer = FLASH_TIME
	FX.set_flash(_parts, true)


func advance(delta: float) -> void:
	_clock += delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			FX.set_flash(_parts, false)
	if _gem != null and not destroyed:
		_gem.rotation.y += delta * 0.8
		_gem.position.y = _gem_base_y + sin(_clock * 2.0) * 0.12
	if _collapse_t >= 0.0:
		_collapse_t += delta
		var u := clampf(_collapse_t / COLLAPSE_TIME, 0.0, 1.0)
		var ease := u * u
		if kind == &"crystal":
			if _gem != null:
				_gem.scale = Vector3.ONE * lerpf(1.0, 0.18, ease)
				_gem.position.y = lerpf(_gem_base_y, 1.55, ease)
				_gem.rotation.y += delta * 6.0
			_root.rotation.y = deg_to_rad(6.0) * ease
		else:
			_root.rotation.z = deg_to_rad(78.0) * ease
			_root.position.y = -0.35 * ease


func bar_ratio() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func bar_fill_width() -> float:
	return _bar_fill.scale.x if _bar_fill != null else 0.0


func _apply_bar() -> void:
	if _bar_fill == null:
		return
	var ratio := bar_ratio()
	# The fill mesh is a unit quad scaled by the ratio; the bar stays one mesh
	# so the HUD and the floating bar always agree on the number.
	_bar_fill.scale = Vector3(ratio, 1.0, 1.0)
	_bar_fill.position.x = -(1.0 - ratio) * _bar_width * 0.5


func _apply_look() -> void:
	var team_col := KIT.team_color(team)
	_bar_fill.material_override = _unshaded(team_col, false)


func _build_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.name = "HealthBar"
	_bar_root.position = Vector3(0.0, VIEW_MAP.structure_bar_height(kind), 0.0)
	# Flat against the fixed pixel camera so it reads as a 2D bar.
	_bar_root.rotation_degrees = Vector3(VIEW_MAP.CAMERA_PITCH_DEG, 0.0, 0.0)
	add_child(_bar_root)
	_bar_width = 3.0 if kind == &"crystal" else 2.4
	var height := 0.32 if kind == &"crystal" else 0.26
	_bar_back = _quad(_bar_width + 0.1, height + 0.1, Color(0.05, 0.03, 0.04, 0.92))
	_bar_root.add_child(_bar_back)
	_bar_fill = _quad(_bar_width, height, KIT.team_color(team))
	_bar_fill.position.z = 0.01
	_bar_root.add_child(_bar_fill)
	_bar_back.position.z = 0.0


func _quad(width: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, height)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _unshaded(color, true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _unshaded(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if transparent and color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_tower() -> void:
	var team_col := KIT.team_color(team)
	var stone := TOON_PART.new()
	stone.name = "Stone"
	stone.material_override = KIT.textured_material("brick", 16.0)
	stone.box(Vector3(2.8, 0.6, 2.8), Vector3(0.0, 0.3, 0.0), TOWER_DARK)
	stone.box(Vector3(2.2, 0.5, 2.2), Vector3(0.0, 0.85, 0.0), TOWER_STONE)
	stone.box(Vector3(1.3, 3.0, 1.3), Vector3(0.0, 2.6, 0.0), TOWER_STONE)
	stone.build()
	_root.add_child(stone)
	var trim := TOON_PART.new()
	trim.name = "Trim"
	trim.box(Vector3(1.44, 0.22, 1.44), Vector3(0.0, 2.9, 0.0), team_col)
	trim.box(Vector3(2.0, 0.25, 2.0), Vector3(0.0, 4.0, 0.0), Palette.IRON)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			trim.box(Vector3(0.36, 0.36, 0.36), Vector3(sx * 0.82, 4.3, sz * 0.82), Palette.IRON)
	trim.cylinder(0.32, 0.46, 0.4, Vector3(0.0, 4.33, 0.0), Palette.RUST_DARK, 8)
	trim.box(Vector3(0.08, 1.7, 0.08), Vector3(0.82, 5.0, 0.82), Palette.VOID)
	trim.box(Vector3(0.55, 0.6, 0.04), Vector3(0.52, 5.5, 0.82), team_col)
	trim.build()
	_root.add_child(trim)
	_flame = TOON_PART.new()
	_flame.name = "Flame"
	_flame.material_override = KIT.flame_material()
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fx := KIT.EMISSIVE | KIT.NO_OUTLINE
	_flame.box(Vector3(0.5, 0.3, 0.5), Vector3(0.0, 4.66, 0.0), Palette.TOXIC, Vector3(0.0, 45.0, 0.0), fx)
	_flame.box(Vector3(0.32, 0.42, 0.32), Vector3(0.0, 4.85, 0.0), Palette.EMBER, Vector3(0.0, 20.0, 0.0), fx)
	_flame.box(Vector3(0.14, 0.28, 0.14), Vector3(0.04, 5.14, 0.0), Palette.EMBER_ASH, Vector3(0.0, 60.0, 0.0), fx)
	_flame.build()
	_root.add_child(_flame)
	_pool = KIT.light_pool(3.2, Palette.EMBER, 0.06, 0.3)
	_root.add_child(_pool)
	var deck_glow := KIT.light_pool(0.95, Palette.EMBER, 0.12, 0.3)
	deck_glow.position.y = 4.14
	_root.add_child(deck_glow)


func _build_crystal() -> void:
	var team_col := KIT.team_color(team)
	var plinth := TOON_PART.new()
	plinth.name = "Plinth"
	plinth.material_override = KIT.textured_material("brick", 16.0)
	plinth.box(Vector3(3.6, 0.5, 3.6), Vector3(0.0, 0.25, 0.0), TOWER_DARK)
	plinth.box(Vector3(2.8, 0.5, 2.8), Vector3(0.0, 0.75, 0.0), TOWER_STONE)
	plinth.box(Vector3(1.8, 0.4, 1.8), Vector3(0.0, 1.2, 0.0), TOWER_DARK)
	plinth.build()
	_root.add_child(plinth)
	var claws := TOON_PART.new()
	claws.name = "Claws"
	claws.box(Vector3(1.9, 0.14, 1.9), Vector3(0.0, 1.45, 0.0), KIT.team_dark(team))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			claws.box(Vector3(0.22, 1.5, 0.22), Vector3(sx * 0.8, 1.95, sz * 0.8),
					Palette.IRON, Vector3(-8.0 * sz, 0.0, 8.0 * sx))
	claws.build()
	_root.add_child(claws)
	_gem = TOON_PART.new()
	_gem.name = "Gem"
	_gem.position = Vector3(0.0, _gem_base_y, 0.0)
	# Forward+'s glow blooms a white-hot gem into a flat pale octagon; keep the
	# crystal silhouette in its team colour and let the light pool carry the glow.
	_gem.sphere(0.62, 2.6, Vector3.ZERO, KIT.team_dark(team), 6, 3, Vector3.ZERO, KIT.HALF_EMISSIVE)
	_gem.build()
	_root.add_child(_gem)
	_pool = KIT.light_pool(4.6, team_col, 0.12)
	_root.add_child(_pool)
