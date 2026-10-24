extends TestCase

const DRIVER := preload("res://tools/campaign_walkthrough.gd")


func test_cliff_route_visits_upper_wind_before_the_westbound_fold() -> void:
	var goals: Array[Dictionary] = [
		{"name": "EmberNestFold", "feet": Vector2(592, -160)},
		{"name": "EmberNestCliff", "feet": Vector2(176, -320)},
		{"name": "Exit", "feet": Vector2(3320, 320)},
		{"name": "EmberNestGate", "feet": Vector2(2680, 320)},
		{"name": "EmberNestWind", "feet": Vector2(944, -320)},
		{"name": "EmberNestOutpost", "feet": Vector2(1848, 0)},
		{"name": "WindGatePlate", "feet": Vector2(1596, 2)},
		{"name": "EmberNestBridge", "feet": Vector2(1088, 0)},
	]
	var route := DRIVER.ordered_goals("level09b", goals)
	eq(route.size(), goals.size())
	for i in route.size(): eq(route[i].name, DRIVER.GOAL_ORDER["level09b"][i])
	eq(DRIVER.resume_goal_index(route, Vector2(598, -160)), 2,
			"resuming at the fold never backtracks to the now-unreachable upper wind nest")
	eq(DRIVER.resume_goal_index(route, Vector2(1092, 0)), 3)
	eq(DRIVER.resume_goal_index(route, Vector2(96, -340)), -1)


func test_regular_chapters_keep_left_to_right_goals() -> void:
	var goals: Array[Dictionary] = [{"name": "Exit", "feet": Vector2(3000, 320)},
		{"name": "EmberNestStart", "feet": Vector2(176, 320)}]
	var route := DRIVER.ordered_goals("level06", goals)
	eq(route[0].name, "EmberNestStart")
	eq(route[1].name, "Exit")
