extends RefCounted
## Lane frame <-> world mapping shared by the sim-driven arena presentation.
##
## MobaSim plays out on a single lane: `x` runs along the lane in metres with
## blue at -x and red at +x, `y` is the sideways offset across the lane. The
## render spike authored its map in exactly that lane frame, turned 45 degrees
## so blue sits bottom-left on screen, so every view converts through
## SPIKE_MAP.lane_to_world()/to_lane() instead of inventing a second mapping.
##
## Constants for the structures and the hero come straight from the frozen sim
## contract: towers at lane x = -16 / +16, crystals at lane x = -26 / +26.
## The structures sit slightly beside the walkable lane so units walking down
## the centre line pass them instead of clipping through the plinths; their
## lane x is what has to agree with the simulation.

const SPIKE_MAP := preload("res://scripts/moba/spike/spike_map.gd")

const TOWER_LANE_X := 16.0
const CRYSTAL_LANE_X := 26.0
const BASE_LANE_X := 28.0
## Sideways offsets, mirrored per team (blue sits on -y, red on +y). The
## structures' lane x is what the simulation settles; the lateral offset is a
## presentation choice so units walking the lane centre line and the hero's
## 1.9 m swing both clear / reach the plinths instead of clipping through them.
const TOWER_LATERAL := 3.0
const CRYSTAL_LATERAL := 2.6

const TOWER_HP := 1200.0
const CRYSTAL_HP := 2400.0
const HERO_HP := 600.0
const HERO_SPEED := 4.5
const HERO_RESPAWN_S := 6.0

## PixelCamera keeps this fixed; the floating 3D health bars are built flat
## against the camera plane so they read as 2D bars above the structures.
const CAMERA_PITCH_DEG := -55.0

const TEAM_BLUE := 0
const TEAM_RED := 1
const TEAM_NAMES: Array[String] = ["灰卫", "锈誓"]


static func lane_to_world(lane: Vector2, y_metres: float = 0.0) -> Vector3:
	return SPIKE_MAP.lane_to_world(lane.x, lane.y, y_metres)


static func world_to_lane(world: Vector3) -> Vector2:
	return SPIKE_MAP.to_lane(world)


## Lane-frame direction -> world-space direction (never normalised: the caller
## decides whether it wants a unit heading or just the sign).
static func lane_dir_to_world(dir: Vector2) -> Vector3:
	return SPIKE_MAP.lane_to_world(dir.x, dir.y) - SPIKE_MAP.lane_to_world(0.0, 0.0)


## Yaw for a unit whose local forward is -Z, matching the procedural rigs
## (LowPolyKnight.face_towards uses the same convention).
static func yaw_for_world_dir(dir: Vector3) -> float:
	if Vector2(dir.x, dir.z).length_squared() < 0.000001:
		return 0.0
	return atan2(-dir.x, -dir.z)


static func yaw_for_lane_dir(dir: Vector2) -> float:
	return yaw_for_world_dir(lane_dir_to_world(dir))


## MobaSim stores `facing` as an int along the lane (-1 toward -x, +1 toward +x).
static func yaw_for_facing(facing: int) -> float:
	return yaw_for_lane_dir(Vector2(signf(float(facing)) if facing != 0 else 1.0, 0.0))


static func structure_x(kind: StringName) -> float:
	return CRYSTAL_LANE_X if kind == &"crystal" else TOWER_LANE_X


static func structure_lane(kind: StringName, team: int) -> Vector2:
	var side := -1.0 if team == TEAM_BLUE else 1.0
	var lateral := CRYSTAL_LATERAL if kind == &"crystal" else TOWER_LATERAL
	return Vector2(side * structure_x(kind), side * lateral)


static func structure_world(kind: StringName, team: int, y_metres: float = 0.0) -> Vector3:
	return lane_to_world(structure_lane(kind, team), y_metres)


static func structure_hp(kind: StringName) -> float:
	return CRYSTAL_HP if kind == &"crystal" else TOWER_HP


static func team_name(team: int) -> String:
	return TEAM_NAMES[clampi(team, 0, TEAM_NAMES.size() - 1)]


static func enemy_team(team: int) -> int:
	return TEAM_RED if team == TEAM_BLUE else TEAM_BLUE


## Lane x the hero is pushing toward when it belongs to `team`.
static func push_direction(team: int) -> float:
	return 1.0 if team == TEAM_BLUE else -1.0


## Height of the floating 3D health bar above each structure kind.
static func structure_bar_height(kind: StringName) -> float:
	return 4.9 if kind == &"crystal" else 6.1
