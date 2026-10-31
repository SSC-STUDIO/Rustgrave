class_name TitleLayout
extends RefCounted
## Shared 3D coordinate contract of the forge-hall title screen.
##
## Every position is in metres, +Y is up and the camera looks down -Z. The iron
## bridge deck is the origin plane: the knight's feet stand exactly on
## (0, 0, 0) and the deck's top face is y = DECK_Y = 0. Geometry is built around
## this contract by `scripts/title3d/kit/*_builder.gd`; the props, camera and
## lighting modules read the same constants instead of hard-coding positions.
##
## Composition (all inside the hall volume):
##   - camera sits outside the open front of the hall at +Z, the far wall is at
##     z = HALL_BACK_Z = -30, and the hall is HALL_FRONT_Z = +6 deep enough to
##     let the bridge read as a diorama stage;
##   - a lava chasm (PIT) splits the hall left/right at x = +-PIT_HALF_X: the
##     iron bridge spans it along X, the side machine decks +-8.5..16 m are the
##     river banks;
##   - the forge works in the right bank (FORGE_*), the big/small gear pair is
##     bolted to the left bank (GEAR_*), the broken banners and the conveyor
##     rails hang above the stage;
##   - the roof is a truss deck at ROOF_Y with one ragged skylight
##     (SKYLIGHT_*) that spills a light shaft (BEAM_FROM -> BEAM_TO).
##
## Pixel contract: the title renders into 640x360 texels (2x supersampled), a
## 30 degree vertical perspective camera framing VIEW_HEIGHT = 13.5 m on the
## focus plane z = 0. That makes one render texel exactly WORLD_PER_TEXEL =
## 0.0375 m on that plane, which the kit uses for 1 texel outlines.
##
## This file is pure data: no nodes, no autoloads, safe to read at parse time.

# ---------------------------------------------------------------------------
# Pixel / camera contract
# ---------------------------------------------------------------------------
const RENDER_TEXEL_WIDTH := 640
const RENDER_TEXEL_HEIGHT := 360
const SUPERSAMPLE := 2
## Vertical field of view of the title camera, in degrees.
const CAMERA_FOV := 30.0
## World metres covered vertically by the 360 render texels on the focus plane.
const VIEW_HEIGHT := 13.5
## Metres per render texel on the focus plane (VIEW_HEIGHT / RENDER_TEXEL_HEIGHT).
const WORLD_PER_TEXEL := 0.0375
## Suggested camera back-off from the focus plane: (VIEW_HEIGHT / 2) / tan(FOV / 2).
const CAMERA_DISTANCE := 25.152
## Suggested look target on the hero plane (the 2D camera centre mapped to 3D).
const CAMERA_TARGET := Vector3(0.0, 4.3, 0.0)
const CAMERA_NEAR := 0.1
const CAMERA_FAR := 120.0

# ---------------------------------------------------------------------------
# Stage: knight and bridge
# ---------------------------------------------------------------------------
## Top face of the iron bridge deck; the knight's feet rest here.
const DECK_Y := 0.0
## Hero point: knight's feet, the camera focus of the title shot.
const KNIGHT_POS := Vector3(0.0, 0.0, 0.0)
## Nominal knight height in metres (low-poly title knight, hood included).
const KNIGHT_HEIGHT := 1.8
## Yaw of the knight at rest; 0 = facing the camera (+Z), 180 = facing the forge.
const KNIGHT_YAW_DEG := 0.0

## Centre of the bridge slab. The slab is a box of size BRIDGE_SIZE centred
## here, so its top face is always DECK_Y (see bridge_top()).
const BRIDGE_CENTER := Vector3(0.0, -0.35, 0.0)
## Full size of the bridge slab: X span (crosses the chasm), Y thickness, Z depth.
const BRIDGE_SIZE := Vector3(17.0, 0.7, 7.2)
const BRIDGE_TOP_Y := 0.0
const BRIDGE_HALF_X := 8.5
const BRIDGE_FRONT_Z := 3.6
const BRIDGE_BACK_Z := -3.6
const RAIL_HEIGHT := 1.2
const RAIL_THICKNESS := 0.14
## Chain drop anchor X positions under the deck (bridge builder).
const BRIDGE_CHAIN_XS := [-7.5, -2.5, 2.5, 7.5]

# ---------------------------------------------------------------------------
# Hall shell
# ---------------------------------------------------------------------------
## Full interior width (x runs -HALL_HALF_W .. +HALL_HALF_W).
const HALL_W := 32.0
const HALL_HALF_W := 16.0
const HALL_H := 15.0
## Full depth of the hall volume: HALL_FRONT_Z .. HALL_BACK_Z.
const HALL_D := 36.0
## Open front plane of the hall (behind the camera is outside the building).
const HALL_FRONT_Z := 6.0
## Inner face of the far wall; the hall reaches it at -HALL_D from the front.
const HALL_BACK_Z := -30.0
const HALL_CENTER := Vector3(0.0, 7.5, -12.0)
const ROOF_Y := 15.0
const ROOF_THICKNESS := 0.8
const WALL_THICKNESS := 0.8
## Raised machine decks that form the two banks of the lava chasm.
const SIDE_DECK_Y := 0.0
const SIDE_DECK_INNER_X := 8.5
const SIDE_DECK_OUTER_X := 16.0
## Arcade columns on the side walls.
const PILLAR_X := 14.2
const PILLAR_Z_START := -4.0
const PILLAR_SPACING := 6.5
const PILLAR_COUNT := 4
## Roof trusses, spaced along Z under the roof deck.
const ROOF_TRUSS_Y := 14.2
const ROOF_TRUSS_Z_START := 2.0
const ROOF_TRUSS_SPACING := 5.0
const ROOF_TRUSS_COUNT := 7
## Overhead crane rails (the travelling hoist / sword conveyor share them).
const CRANE_Y := 11.4
const CRANE_HALF_X := 12.6
const CRANE_Z_FROM := 3.0
const CRANE_Z_TO := -18.0

# ---------------------------------------------------------------------------
# Far wall openings, skylight, light shafts
# ---------------------------------------------------------------------------
## Three tall windows on the far wall (cool backlight, three shafts).
const WINDOW_XS := [-8.0, 0.0, 8.0]
const WINDOW_Y := 9.4
const WINDOW_SIZE := Vector2(3.0, 6.4)
const WINDOW_Z := -29.4
## Ragged skylight hole in the roof deck, and the shaft it spills.
const SKYLIGHT_CENTER := Vector3(3.5, 15.0, -12.0)
const SKYLIGHT_SIZE := Vector2(6.0, 4.5)
## The visible skylight shaft: high under the hole down to the bridge deck.
const BEAM_FROM := Vector3(3.5, 14.8, -12.0)
const BEAM_TO := Vector3(-2.3, 0.05, 0.6)
## Sun direction the light rig bakes as a DirectionalLight3D ("travel" vector,
## i.e. light moves toward this direction; the source is behind the far wall).
const SUN_DIRECTION := Vector3(-0.286, -0.736, 0.613)
## Equivalent DirectionalLight3D.rotation_degrees (Godot YXZ euler order).
## The 155 degree yaw is what turns the light around: its -Z axis ends up along
## SUN_DIRECTION, so the sun sits behind the far wall and the raking light comes
## through the window holes toward the camera.
const SUN_ROTATION_DEG := Vector3(-47.4, 155.0, 0.0)

# ---------------------------------------------------------------------------
# Lava chasm
# ---------------------------------------------------------------------------
## Solid pit floor under the lava.
const PIT_Y := -6.0
## Molten surface height.
const LAVA_Y := -5.55
## The chasm runs the full hall depth; the bridge crosses it along X.
const PIT_HALF_X := 8.5
const LAVA_Z_FRONT := 12.0
const LAVA_Z_BACK := -22.0
const PIT_CENTER := Vector3(0.0, -5.55, -7.0)
## Stone apron between the end of the lava and the far wall.
const FAR_FLOOR_Y := -2.0
const FAR_FLOOR_Z := -22.0
## Far catwalk where the ghosts patrol.
const FAR_CATWALK_Y := 1.2
const FAR_CATWALK_Z := -24.0
const FAR_CATWALK_HALF_X := 10.0
const GHOST_A := Vector3(-9.0, 1.35, -24.0)
const GHOST_B := Vector3(9.0, 1.35, -24.0)
## Ember-soul spawn box over the molten river, and where they escape (skylight).
const SOULS_MIN := Vector3(-7.5, -5.4, -18.0)
const SOULS_MAX := Vector3(7.5, -5.4, -4.0)
const SOULS_EXIT := Vector3(3.5, 14.4, -12.0)

# ---------------------------------------------------------------------------
# 14 chain lanterns: two rows of 7 (progress lamps)
# ---------------------------------------------------------------------------
const LANTERN_COUNT := 14
const LANTERN_PER_ROW := 7
## Seven X positions used by both rows; row A (front/near) then row B (back).
const LANTERN_XS := [-7.5, -5.0, -2.5, 0.0, 2.5, 5.0, 7.5]
const LANTERN_FRONT_Z := 2.2
const LANTERN_BACK_Z := -2.8
## Chain anchor rail under the roof trusses.
const LANTERN_TOP_Y := 11.2
## Resting lantern body centre (the playable lift is LANTERN_LIFT above this).
const LANTERN_HANG_Y := 6.8
const LANTERN_LIFT := 1.4
const LANTERN_RADIUS := 0.46

# ---------------------------------------------------------------------------
# Left bank: gear pair
# ---------------------------------------------------------------------------
## Gears stand in the XY plane (thickness along Z) so the camera reads the teeth.
const GEAR_BIG := Vector3(-11.0, 3.7, -3.0)
const GEAR_BIG_RADIUS := 2.6
const GEAR_BIG_TEETH := 16
const GEAR_SMALL := Vector3(-8.9, 7.15, -3.0)
const GEAR_SMALL_RADIUS := 1.5
const GEAR_SMALL_TEETH := 12
const GEAR_DEPTH := 0.7

# ---------------------------------------------------------------------------
# Right bank: forge, mouth, stack
# ---------------------------------------------------------------------------
const FORGE_CENTER := Vector3(12.2, 3.8, -9.6)
const FORGE_SIZE := Vector3(6.4, 7.6, 6.4)
## Glowing mouth on the +Z face of the forge (faces the camera).
const FORGE_MOUTH := Vector3(12.2, 2.8, -6.35)
const FORGE_MOUTH_SIZE := Vector3(3.0, 2.6, 0.4)
## Suggested omni light anchor just in front of the mouth.
const FORGE_LIGHT_POS := Vector3(11.2, 2.6, -5.0)
const FORGE_MOUTH_COLOR := Color("#ff8c2a")
const FORGE_STACK_BASE := Vector3(12.6, 7.6, -11.6)
const FORGE_STACK_TOP_Y := 17.2
const FORGE_STACK_RADIUS := 1.25

# ---------------------------------------------------------------------------
# Prop anchors consumed by the title-props module
# ---------------------------------------------------------------------------
## Two bridge braziers stand left/front of the knight, on the deck.
const BRAZIER_LEFT := Vector3(-2.6, 0.0, 1.6)
const BRAZIER_RIGHT := Vector3(-0.9, 0.0, 1.6)
## Planted greatsword (the "give" ending) and the bench stool ("keep" ending).
const GREATSWORD_POS := Vector3(0.6, 0.0, -0.5)
const KEEP_BENCH := Vector3(5.2, 0.0, -1.0)
## Far anvil/striker, on the right machine deck away from the forge.
const HAMMER_POS := Vector3(10.6, 1.35, -15.5)
## Crucible hoist rail: from its parking spot on the right deck out over the lava.
const CRUCIBLE_RAIL_FROM := Vector3(10.5, 9.4, -9.0)
const CRUCIBLE_RAIL_TO := Vector3(2.0, 9.4, -9.0)
const CRUCIBLE_POUR := Vector3(2.0, 9.4, -9.0)
## Sword conveyor: greatswords ride the rail toward the forge mouth.
const SWORD_CHAIN_FROM := Vector3(-5.0, 8.8, -8.0)
const SWORD_CHAIN_TO := Vector3(11.4, 8.8, -8.0)
## Torn banners hanging above the bridge, left and right of the stage.
const BANNER_LEFT := Vector3(-8.6, 10.8, -5.5)
const BANNER_RIGHT := Vector3(8.6, 10.8, -5.5)
const BANNER_SIZE := Vector2(2.4, 6.2)

# ---------------------------------------------------------------------------
# Helpers (pure maths, no nodes)
# ---------------------------------------------------------------------------

## Top face of the bridge slab; must equal DECK_Y.
static func bridge_top() -> float:
	return BRIDGE_CENTER.y + BRIDGE_SIZE.y * 0.5


## Metres per render texel on the focus plane (z = 0).
static func world_per_texel() -> float:
	return VIEW_HEIGHT / float(RENDER_TEXEL_HEIGHT)


## Camera back-off that frames VIEW_HEIGHT with CAMERA_FOV on the focus plane.
static func camera_distance() -> float:
	return (VIEW_HEIGHT * 0.5) / tan(deg_to_rad(CAMERA_FOV * 0.5))


## True when a point lies inside the buildable hall volume.
static func in_hall(p: Vector3) -> bool:
	return absf(p.x) <= HALL_HALF_W and p.y >= PIT_Y and p.y <= ROOF_Y \
		and p.z <= HALL_FRONT_Z and p.z >= HALL_BACK_Z


## 14 lantern body centres: row A (front, z = LANTERN_FRONT_Z) then row B.
static func lantern_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for row in 2:
		var z := LANTERN_FRONT_Z if row == 0 else LANTERN_BACK_Z
		for i in LANTERN_PER_ROW:
			out.append(Vector3(LANTERN_XS[i], LANTERN_HANG_Y, z))
	return out


## 14 chain anchor points on the lantern rail above each lantern.
static func lantern_anchors() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for row in 2:
		var z := LANTERN_FRONT_Z if row == 0 else LANTERN_BACK_Z
		for i in LANTERN_PER_ROW:
			out.append(Vector3(LANTERN_XS[i], LANTERN_TOP_Y, z))
	return out


## The two bridge brazier feet.
static func braziers() -> Array[Vector3]:
	return [BRAZIER_LEFT, BRAZIER_RIGHT]
