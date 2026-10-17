extends TestCase


func setup() -> void:
	WorldClock.reset()
	WorldClock.menu_hold = false
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)


func teardown() -> void:
	WorldClock.reset()


func test_zone_transition_shares_weight_without_changing_blend_mode() -> void:
	var host := Node2D.new()
	add_child(host)
	var backdrop := CanvasLayer.new()
	host.add_child(backdrop)
	var atmosphere := WorldAtmosphere.new()
	host.add_child(atmosphere)
	atmosphere.build(host, backdrop)
	var light := WorldLight.new()
	light.follow = &"indoor"
	light.lit = true
	host.add_child(light)
	light.apply(true)
	var outside_radius := light.texture_scale
	var outside_energy := light.energy
	var mode := light.blend_mode
	WorldClock.set_zone(WorldClock.Zone.INDOORS)
	atmosphere.advance(0.10)
	light.apply()
	ok(atmosphere.indoor_weight > 0.0 and atmosphere.indoor_weight < 1.0, "zone transition is gradual")
	ok(light.texture_scale > outside_radius, "doorway radius follows the shared transition")
	ok(light.energy > outside_energy, "room energy follows the same transition")
	eq(light.blend_mode, mode, "zone crossing never swaps canvas blend operations")
	var tint := host.get_node("MoodTint") as CanvasModulate
	var distant := backdrop.get_node("BackdropTint") as CanvasModulate
	ok(distant.color.v < tint.color.v, "backdrop remains subordinate to the play canvas")
	atmosphere.advance(5.0)
	ok(atmosphere.indoor_weight > 0.99, "room transition settles")


func test_decorative_torch_uses_shared_local_light() -> void:
	var torch := TorchLight.new()
	add_child(torch)
	var light := torch.get_node("FlameGlow") as WorldLight
	ok(light != null, "torch uses the same local-light presentation")
	eq(light.follow, &"torch")
	ok(not light.shadow_enabled, "decorative torches do not add full shadow passes")


## 轮廓对比度（docs/art-spec.md「轮廓对比度」）：backdrop 永远比玩法层暗一档。
## 玩家最低明度 0.227（披风）在 MoodTint 之前，所以 backdrop tint 压暗后必须
## 仍然明显低于玩法层色调——远景不抢角色。
func test_backdrop_stays_subordinate_at_every_phase() -> void:
	for time_val in [0.05, 0.28, 0.55, 0.80]:
		WorldClock.set_time(time_val)
		var host := Node2D.new()
		add_child(host)
		var backdrop := CanvasLayer.new()
		host.add_child(backdrop)
		var atmosphere := WorldAtmosphere.new()
		host.add_child(atmosphere)
		atmosphere.build(host, backdrop)
		var tint := host.get_node("MoodTint") as CanvasModulate
		var distant := backdrop.get_node("BackdropTint") as CanvasModulate
		ok(distant.color.v < tint.color.v,
				"time %.2f: backdrop %.3f < play %.3f" % [time_val, distant.color.v, tint.color.v])
		var ambient: Color = WorldClock.outdoor_tint()
		almost(distant.color.v, ambient.darkened(ThemeBackdrop.BACKDROP_SUBORDINATE).v, 0.02,
				"time %.2f: backdrop is exactly one 0.24 step below ambient" % time_val)
		host.queue_free()
	WorldClock.set_time(0.80)
	WorldClock.set_weather(WorldClock.Weather.HAZE, true)


func test_torch_wall_has_a_broken_crown_not_a_box() -> void:
	var torch := TorchLight.new()
	torch.position = Vector2(1296, 230)
	add_child(torch)
	var wall := torch.get_node_or_null("TorchSprite") as Node2D
	ok(wall != null, "wall plate container exists")
	if wall == null:
		return
	eq(wall.position, Vector2(-32, -96), "container keeps the old centered 64×192 footprint")
	var strips: Array[Sprite2D] = []
	for child in wall.get_children():
		if child is Sprite2D:
			strips.append(child)
	eq(strips.size(), 8, "64px plate is sliced into 8px columns")
	var tops := PackedFloat32Array()
	var bottoms := PackedFloat32Array()
	for s in strips:
		ok(s.region_enabled, "each column is a region of the shared plate")
		almost(s.region_rect.size.x, 8.0, 0.01)
		tops.append(s.position.y)
		bottoms.append(s.position.y + s.region_rect.size.y)
		ok(s.region_rect.position.y <= 48.0, "crown never cuts into the torch flame (y≈96+)")
		ok(s.region_rect.position.y + s.region_rect.size.y == 192.0, "columns keep the full lower wall")
	var distinct := {}
	for t in tops:
		distinct[t] = true
	ok(distinct.size() >= 3, "crown is jagged, not a straight top edge")
	for b in bottoms:
		almost(b, 192.0, 0.01, "all columns share one footing")
	ok(strips[0].region_rect.position.y >= 8.0 and strips[7].region_rect.position.y >= 8.0,
			"outer corners have crumbled")
	var again := TorchLight.new()
	again.position = Vector2(1296, 230)
	add_child(again)
	eq(again.crown_profile(8), torch.crown_profile(8), "profile is deterministic per placement")
	var elsewhere := TorchLight.new()
	elsewhere.position = Vector2(1730, 230)
	add_child(elsewhere)
	ok(elsewhere.crown_profile(8) != torch.crown_profile(8), "different placements break differently")
