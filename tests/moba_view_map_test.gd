extends TestCase
## Lane <-> world mapping of the sim-driven arena presentation. The render
## scene must place every sim entity where SPIKE_MAP already puts lane
## coordinates, and the structures must sit at the sim's tower / crystal lane x.

const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")
const SPIKE_MAP := preload("res://scripts/moba/spike/spike_map.gd")


func test_lane_and_world_convert_through_the_map_convention() -> void:
	var points := [
		Vector2(-28.0, 0.0), Vector2(0.0, 0.0), Vector2(16.0, 0.0),
		Vector2(26.0, 0.0), Vector2(-11.5, 1.7), Vector2(3.25, -2.0),
	]
	for lane: Vector2 in points:
		var world := VIEW_MAP.lane_to_world(lane)
		eq(world, SPIKE_MAP.lane_to_world(lane.x, lane.y), "same mapping as the printed map")
		var back := VIEW_MAP.world_to_lane(world)
		almost(back.x, lane.x, 0.0001)
		almost(back.y, lane.y, 0.0001)


func test_lane_directions_become_world_headings() -> void:
	var forward := VIEW_MAP.lane_dir_to_world(Vector2(1.0, 0.0))
	almost(forward.length(), 1.0, 0.0001)
	almost(forward.y, 0.0, 0.0001)
	eq(VIEW_MAP.yaw_for_facing(1), VIEW_MAP.yaw_for_lane_dir(Vector2(1.0, 0.0)))
	eq(VIEW_MAP.yaw_for_facing(-1), VIEW_MAP.yaw_for_lane_dir(Vector2(-1.0, 0.0)))
	almost(VIEW_MAP.yaw_for_facing(1), -PI * 0.25, 0.0001, "+x lane points up-right on screen")
	almost(VIEW_MAP.yaw_for_facing(-1), PI * 0.75, 0.0001)
	# The knight rig faces -Z at yaw 0, so the forward yaw must match that model
	# convention: facing -Z is yaw 0.
	var straight := VIEW_MAP.yaw_for_world_dir(Vector3(0.0, 0.0, -1.0))
	almost(straight, 0.0, 0.0001)
	almost(VIEW_MAP.yaw_for_world_dir(Vector3(-1.0, 0.0, 0.0)), PI * 0.5, 0.0001)


func test_structures_sit_at_the_simulated_lane_coordinates() -> void:
	eq(VIEW_MAP.structure_x(&"tower"), 16.0)
	eq(VIEW_MAP.structure_x(&"crystal"), 26.0)
	eq(VIEW_MAP.structure_hp(&"tower"), 1200.0)
	eq(VIEW_MAP.structure_hp(&"crystal"), 2400.0)
	for team in [VIEW_MAP.TEAM_BLUE, VIEW_MAP.TEAM_RED]:
		for kind: StringName in [&"tower", &"crystal"]:
			var lane := VIEW_MAP.structure_lane(kind, team)
			var world := VIEW_MAP.structure_world(kind, team)
			# Lane x must equal the simulation's structure x; the sideways offset
			# is presentation only (keeps the walkable centre line clear).
			eq(absf(lane.x), VIEW_MAP.structure_x(kind))
			almost(absf(VIEW_MAP.world_to_lane(world).x), VIEW_MAP.structure_x(kind), 0.0001)
			eq(signf(VIEW_MAP.world_to_lane(world).x), -1.0 if team == VIEW_MAP.TEAM_BLUE else 1.0)
	# Blue and red structures mirror across the lane centre line.
	eq(VIEW_MAP.structure_lane(&"tower", 0), -VIEW_MAP.structure_lane(&"tower", 1))
	eq(VIEW_MAP.structure_lane(&"crystal", 0), -VIEW_MAP.structure_lane(&"crystal", 1))
	# Both kinds are pushed beside the lane so a unit on the centre line does
	# not clip through the plinth.
	ok(absf(VIEW_MAP.structure_lane(&"tower", 0).y) > 2.0)
	ok(absf(VIEW_MAP.structure_lane(&"crystal", 0).y) > 2.0)


func test_team_helpers_are_original_rustgrave_names() -> void:
	eq(VIEW_MAP.team_name(VIEW_MAP.TEAM_BLUE), "灰卫")
	eq(VIEW_MAP.team_name(VIEW_MAP.TEAM_RED), "锈誓")
	eq(VIEW_MAP.enemy_team(VIEW_MAP.TEAM_BLUE), VIEW_MAP.TEAM_RED)
	eq(VIEW_MAP.enemy_team(VIEW_MAP.TEAM_RED), VIEW_MAP.TEAM_BLUE)
	eq(VIEW_MAP.push_direction(VIEW_MAP.TEAM_BLUE), 1.0)
	eq(VIEW_MAP.push_direction(VIEW_MAP.TEAM_RED), -1.0)


func test_contract_constants_match_the_frozen_sim_rules() -> void:
	eq(VIEW_MAP.HERO_HP, 600.0)
	eq(VIEW_MAP.HERO_SPEED, 4.5)
	eq(VIEW_MAP.HERO_RESPAWN_S, 6.0)
	eq(VIEW_MAP.TOWER_HP, 1200.0)
	eq(VIEW_MAP.CRYSTAL_HP, 2400.0)
	eq(VIEW_MAP.BASE_LANE_X, 28.0)
