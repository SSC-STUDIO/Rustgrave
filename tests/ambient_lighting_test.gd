extends TestCase
## 场景氛围灯：必须真的会发光。
##
## 之前的实现直接 `PointLight2D.new()` 却从不赋 texture —— 没有贴图的 PointLight2D
## 一声不响什么都不画，六盏灯全是隐形的空操作。这条测试把它钉住：
## 每盏灯都得是 WorldLight、有贴图、亮度和半径都落在配置值上。


func setup() -> void:
	WorldClock.reset()


func teardown() -> void:
	WorldClock.reset()


func test_every_ambient_light_actually_emits() -> void:
	var host := Node2D.new()
	add_child(host)
	var lighting := AmbientLighting.create_for_level(host)
	eq(lighting.name, "AmbientLighting")
	# 六种光各来一盏。
	var types := [AmbientLighting.LightType.TORCH, AmbientLighting.LightType.EMBER,
			AmbientLighting.LightType.TOXIC, AmbientLighting.LightType.MOONBEAM,
			AmbientLighting.LightType.FURNACE, AmbientLighting.LightType.SPOTLIGHT]
	for i in types.size():
		var light := lighting.add_light(Vector2(64.0 * i, 0.0), types[i])
		ok(light != null, "light %d was created" % i)
		if light == null:
			continue
		ok(light is WorldLight, "light %d is a WorldLight, not a bare PointLight2D" % i)
		ok(light.texture != null, "light %d has a real texture (otherwise it draws nothing)" % i)
		ok(light.enabled, "light %d is enabled" % i)
		ok(light.energy > 0.001, "light %d emits energy" % i)
		var cfg: Dictionary = AmbientLighting.LIGHT_CONFIGS[types[i]]
		almost(light.energy, float(cfg["energy"]), 0.01, "light %d uses its configured energy" % i)
		almost(light.texture_scale * WorldLight.TEX_SIZE * 0.5, float(cfg["radius"]), 1.0,
				"light %d uses its configured radius" % i)
	eq(lighting.light_count(), types.size(), "all six lights are registered")
	host.free()
	await flush(1)


func test_light_cap_rejects_extras() -> void:
	var host := Node2D.new()
	add_child(host)
	var lighting := AmbientLighting.create_for_level(host)
	for i in AmbientLighting.MAX_LIGHTS:
		ok(lighting.add_light(Vector2(float(i) * 16.0, 0.0), AmbientLighting.LightType.TORCH) != null,
				"light %d fits under the cap" % i)
	eq(lighting.add_light(Vector2.ZERO, AmbientLighting.LightType.TORCH), null,
			"the cap rejects one more light")
	eq(lighting.light_count(), AmbientLighting.MAX_LIGHTS, "count stays at the cap")
	lighting.clear_lights()
	eq(lighting.light_count(), 0, "clear_lights empties the list")
	host.free()
	await flush(1)


func test_flicker_stays_inside_its_band() -> void:
	var host := Node2D.new()
	add_child(host)
	var lighting := AmbientLighting.create_for_level(host)
	var light := lighting.add_light(Vector2.ZERO, AmbientLighting.LightType.FURNACE)
	var base := float(AmbientLighting.LIGHT_CONFIGS[AmbientLighting.LightType.FURNACE]["energy"])
	var amount := float(AmbientLighting.LIGHT_CONFIGS[AmbientLighting.LightType.FURNACE]["flicker_amount"])
	var lo := base * (1.0 - amount) - 0.02
	var hi := base + 0.02
	for i in 20:
		lighting.call("_process", 0.05)
		await flush(1)
		var got := light.energy
		ok(got >= lo and got <= hi, "flicker %d stays in [%.2f, %.2f] (got %.2f)" % [i, lo, hi, got])
	host.free()
	await flush(1)
