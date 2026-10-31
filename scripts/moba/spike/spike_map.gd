extends Node3D
## Mid-lane slice of the arena for the render spike. Terrain is authored in a
## lane frame (x along the mid lane with blue at -x, z along the river) and
## turned 45 degrees so blue sits bottom-left and red top-right on screen.
## Terrain is merged per material; props stay world-axis aligned so their edges
## land on clean pixel rows and columns.

const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const TOON_PART := preload("res://scripts/moba/view/toon_part.gd")

const HALF := 34.0
const RIVER_HALF := 3.2
const LANE_HALF := 2.5
const BRIDGE_HALF := 2.6
const LANE_YAW := PI * 0.25
const WALL_HEIGHT := 1.6
const GROUND_DEPTH := 1.2
const LAVA_TOP := -0.4
## Blockers are grown by the hero radius so walkability is a point test.
const UNIT_RADIUS := 0.35
const SIDES: Array[float] = [-1.0, 1.0]

const GROUND := Color("#6e5a48")
const MOSS := Color("#5e5c42")
const LANE := Color("#968878")
const BANK := Color("#4a3e36")
const CURB := Color("#6e6258")
const WALL := Color("#6e6258")
const WALL_CAP := Color("#a89a8a")
const BUSH := Color("#4c7a5e")
const BUSH_DARK := Color("#2f5241")
const ROCK := Color("#6e6258")
const ROCK_DARK := Color("#4a3e36")
const TOWER_STONE := Color("#8a8680")
const TOWER_DARK := Color("#4a3e36")
const BRIDGE_DECK := Color("#6e5040")
const IRON_RAIL := Color("#3a3a3a")

## Lane frame [x, z, size_x, size_z]; point-symmetric pairs.
const WALLS := [
	[-22.0, 8.0, 6.0, 1.6], [22.0, -8.0, 6.0, 1.6],
	[-12.0, 10.5, 1.6, 5.0], [12.0, -10.5, 1.6, 5.0],
	[-17.0, -9.0, 5.0, 1.6], [17.0, 9.0, 5.0, 1.6],
	[-8.0, -12.0, 1.6, 4.5], [8.0, 12.0, 1.6, 4.5],
	[-27.5, -8.0, 1.6, 4.0], [27.5, 8.0, 1.6, 4.0],
]
## Lane frame [x, z, width, depth]. Bushes are walk-through.
const BUSHES := [
	[-9.0, 5.6, 3.6, 1.8], [9.0, -5.6, 3.6, 1.8],
	[-20.5, -5.6, 3.0, 1.6], [20.5, 5.6, 3.0, 1.6],
	[-5.6, -7.5, 1.8, 3.2], [5.6, 7.5, 1.8, 3.2],
]
## Lane frame [x, z]; rocks inside the river sit in the lava.
const ROCKS := [
	[-1.6, 9.5], [1.6, -9.5],
	[-31.0, 7.0], [31.0, -7.0],
	[-13.5, -14.0], [13.5, 14.0],
	[-24.0, 13.0], [24.0, -13.0],
]

## Lane-frame rectangles (x, z) the hero cannot enter.
var blockers: Array[Rect2] = []

var _ground: TOON_PART
var _lava: TOON_PART
var _stone: TOON_PART
var _paving: TOON_PART
var _trim: TOON_PART


func _ready() -> void:
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	terrain.basis = Basis(Vector3.UP, LANE_YAW)
	add_child(terrain)
	_ground = _part(terrain, "Ground", KIT.textured_material("dirt", 12.0))
	_lava = _part(terrain, "Lava", KIT.lava_material())
	_lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stone = _part(terrain, "Stone", KIT.textured_material("brick", 16.0))
	_paving = _part(terrain, "Paving", KIT.textured_material("flagstone", 16.0))
	_trim = _part(terrain, "Trim", null)
	_build_ground()
	_build_river()
	_build_lane()
	for spec in WALLS:
		_build_wall(spec)
	for part: TOON_PART in [_ground, _lava, _stone, _paving, _trim]:
		part.build()
	_build_bushes()
	_build_rocks()
	# Towers and crystals are not terrain: MobaStructureView builds them at the
	# simulation's lane positions and animates their health/destruction, so the
	# map stays a static, merged-geometry backdrop.


func is_walkable(world_pos: Vector3) -> bool:
	var p := to_lane(world_pos)
	if absf(p.x) > HALF - 1.0 or absf(p.y) > HALF - 1.0:
		return false
	for rect in blockers:
		if rect.has_point(p):
			return false
	return true


## World position -> lane frame (x along the lane, z along the river).
static func to_lane(world: Vector3) -> Vector2:
	var local := Basis(Vector3.UP, LANE_YAW).transposed() * world
	return Vector2(local.x, local.z)


static func lane_to_world(x: float, z: float, y: float = 0.0) -> Vector3:
	return Basis(Vector3.UP, LANE_YAW) * Vector3(x, y, z)


func _build_ground() -> void:
	var half_width := HALF - RIVER_HALF
	for side: float in SIDES:
		var center := Vector3(side * (RIVER_HALF + half_width * 0.5), -GROUND_DEPTH * 0.5, 0.0)
		_ground.box(Vector3(half_width, GROUND_DEPTH, HALF * 2.0), center, GROUND, Vector3.ZERO, KIT.NO_OUTLINE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4051
	var placed := 0
	while placed < 7:
		var x := rng.randf_range(RIVER_HALF + 3.0, HALF - 3.0)
		var z := rng.randf_range(-HALF + 3.0, HALF - 3.0)
		if absf(z) < LANE_HALF + 2.5:
			continue
		# Overlapping slabs give a ragged patch instead of a rug-like rectangle.
		for i in 3:
			var size := Vector3(rng.randf_range(0.8, 2.2), 0.02, rng.randf_range(0.6, 1.6))
			var offset := Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.7, 0.7))
			var yaw := Vector3(0.0, rng.randf_range(0.0, 90.0), 0.0)
			for side: float in SIDES:
				var center := Vector3((x + offset.x) * side, 0.01, (z + offset.y) * side)
				_ground.box(size, center, MOSS, yaw, KIT.NO_OUTLINE)
		placed += 1


func _build_river() -> void:
	var lava_height := GROUND_DEPTH + LAVA_TOP
	var lava_center := Vector3(0.0, -GROUND_DEPTH + lava_height * 0.5, 0.0)
	_lava.box(Vector3(RIVER_HALF * 2.0, lava_height, HALF * 2.0), lava_center, Palette.EMBER, Vector3.ZERO, KIT.NO_OUTLINE)
	for side: float in SIDES:
		var liner := Vector3(side * (RIVER_HALF - 0.075), -0.45, 0.0)
		_stone.box(Vector3(0.15, 0.9, HALF * 2.0), liner, BANK, Vector3.ZERO, KIT.NO_OUTLINE)
	var z0 := BRIDGE_HALF + 0.3
	while z0 < HALF - 0.5:
		var z1 := minf(z0 + 1.88, HALF)
		for side: float in SIDES:
			for bank: float in SIDES:
				var center := Vector3(side * (RIVER_HALF + 0.3), 0.15, bank * (z0 + z1) * 0.5)
				_stone.box(Vector3(0.6, 0.3, z1 - z0), center, BANK)
		z0 += 2.0
	var reach := RIVER_HALF + 0.6 + UNIT_RADIUS
	var open_half := BRIDGE_HALF - UNIT_RADIUS
	var span := HALF - open_half
	blockers.append(Rect2(-reach, open_half, reach * 2.0, span))
	blockers.append(Rect2(-reach, -HALF, reach * 2.0, span))


func _build_lane() -> void:
	var deck_half := RIVER_HALF + 0.9
	var lane_end := 31.5
	var length := lane_end - deck_half
	for side: float in SIDES:
		var strip := Vector3(side * (deck_half + length * 0.5), 0.015, 0.0)
		_paving.box(Vector3(length, 0.03, LANE_HALF * 2.0), strip, LANE, Vector3.ZERO, KIT.NO_OUTLINE)
	var curb_end := 26.6
	var x0 := deck_half
	while x0 < curb_end - 0.5:
		var x1 := minf(x0 + 2.8, curb_end)
		for side: float in SIDES:
			for edge: float in SIDES:
				var curb := Vector3(side * (x0 + x1) * 0.5, 0.04, edge * (LANE_HALF + 0.1))
				_trim.box(Vector3(x1 - x0, 0.08, 0.2), curb, CURB, Vector3.ZERO, KIT.NO_OUTLINE)
		x0 += 3.0
	_paving.box(Vector3(deck_half * 2.0, 0.3, BRIDGE_HALF * 2.0), Vector3(0.0, -0.11, 0.0), BRIDGE_DECK)
	for edge: float in SIDES:
		var z := edge * (BRIDGE_HALF - 0.1)
		_trim.box(Vector3(deck_half * 2.0, 0.1, 0.1), Vector3(0.0, 0.75, z), IRON_RAIL)
		for i in 5:
			var x := lerpf(-deck_half + 0.2, deck_half - 0.2, float(i) / 4.0)
			_trim.box(Vector3(0.18, 0.75, 0.18), Vector3(x, 0.415, z), IRON_RAIL)


func _build_wall(spec: Array) -> void:
	var x: float = spec[0]
	var z: float = spec[1]
	var sx: float = spec[2]
	var sz: float = spec[3]
	_stone.box(Vector3(sx + 0.3, 0.3, sz + 0.3), Vector3(x, 0.15, z), BANK)
	_stone.box(Vector3(sx, WALL_HEIGHT, sz), Vector3(x, WALL_HEIGHT * 0.5, z), WALL)
	_trim.box(Vector3(sx + 0.2, 0.16, sz + 0.2), Vector3(x, WALL_HEIGHT + 0.08, z), WALL_CAP)
	_block(x, z, sx * 0.5 + 0.15, sz * 0.5 + 0.15)


func _build_bushes() -> void:
	var part := _part(self, "Bushes", null)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	for spec in BUSHES:
		var cx: float = spec[0]
		var cz: float = spec[1]
		var w: float = spec[2]
		var d: float = spec[3]
		var count := int(w * d * 1.3) + 3
		for i in count:
			var r := rng.randf_range(0.45, 0.75)
			var lx := cx + rng.randf_range(-0.5, 0.5) * maxf(w - r, 0.0)
			var lz := cz + rng.randf_range(-0.5, 0.5) * maxf(d - r, 0.0)
			var color := BUSH if i % 2 == 0 else BUSH_DARK
			var spin := Vector3(0.0, rng.randf_range(0.0, 60.0), 0.0)
			part.sphere(r, r * 1.6, lane_to_world(lx, lz, r * 0.55), color, 6, 3, spin)
		for i in 3:
			var lx := cx + rng.randf_range(-0.45, 0.45) * w
			var lz := cz + rng.randf_range(-0.45, 0.45) * d
			var lean := Vector3(rng.randf_range(-15.0, 15.0), rng.randf_range(0.0, 180.0), 0.0)
			part.prism(Vector3(0.22, 0.6, 0.08), lane_to_world(lx, lz, 0.75), BUSH, lean)
	part.build()


func _build_rocks() -> void:
	var part := _part(self, "Rocks", null)
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	for spec in ROCKS:
		var lx: float = spec[0]
		var lz: float = spec[1]
		var in_river := absf(lx) < RIVER_HALF
		var base_y := LAVA_TOP if in_river else 0.0
		var big := Vector3(rng.randf_range(1.1, 1.6), rng.randf_range(0.7, 1.1), rng.randf_range(0.9, 1.3))
		var big_rot := Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(0.0, 90.0), rng.randf_range(-8.0, 8.0))
		part.box(big, lane_to_world(lx, lz, base_y + big.y * 0.4), ROCK, big_rot)
		var small := big * rng.randf_range(0.45, 0.6)
		var off := Vector2(rng.randf_range(0.5, 0.8), 0.0).rotated(rng.randf_range(0.0, TAU))
		var small_rot := Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(0.0, 90.0), rng.randf_range(-12.0, 12.0))
		part.box(small, lane_to_world(lx + off.x, lz + off.y, base_y + small.y * 0.35), ROCK_DARK, small_rot)
		if rng.randf() < 0.5:
			part.sphere(0.35, 0.5, lane_to_world(lx - off.x * 0.8, lz - off.y * 0.8, base_y + 0.12), ROCK_DARK, 5, 2)
		if not in_river:
			_block(lx, lz, 0.75, 0.75)
	part.build()


func _part(parent: Node3D, part_name: String, material: Material) -> TOON_PART:
	var part := TOON_PART.new()
	part.name = part_name
	if material != null:
		part.material_override = material
	parent.add_child(part)
	return part


func _block(x: float, z: float, half_x: float, half_z: float) -> void:
	var hx := half_x + UNIT_RADIUS
	var hz := half_z + UNIT_RADIUS
	blockers.append(Rect2(x - hx, z - hz, hx * 2.0, hz * 2.0))
