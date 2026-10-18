extends TestCase
## Ready must not restore shadows on the authored lights used by transient combat FX.


func test_authored_glow_stays_shadowless_after_ready_and_reapply() -> void:
	var glow := WorldLight.new()
	glow.follow = &"authored"
	glow.lit = true
	glow.shadow_enabled = false
	add_child(glow)
	await flush(1)
	ok(glow.enabled, "authored light is visible")
	ok(not glow.shadow_enabled, "ready preserves the shadowless authored presentation")
	glow.apply(true)
	glow.apply(false)
	ok(not glow.shadow_enabled, "clock and flicker refresh do not reintroduce shadows")


func test_real_slash_glow_is_shadowless_through_parry() -> void:
	ok(SlashArc.sheet_available(), "imported slash asset exists")
	var arc := SlashArc.new()
	add_child(arc)
	arc.set_process(false)
	var glow := arc.get_node_or_null("SlashGlow") as WorldLight
	ok(glow != null, "real slash creates its glow")
	if glow == null:
		return
	ok(not glow.shadow_enabled, "slash cannot cast a room-sized combat shadow")
	arc._on_parried(null, null)
	glow.apply(true)
	ok(glow.enabled and not glow.shadow_enabled, "parry brightens without adding shadows")


func test_nest_keeps_environmental_shadows() -> void:
	var glow := WorldLight.new()
	glow.follow = &"nest"
	glow.lit = true
	add_child(glow)
	await flush(1)
	ok(glow.shadow_enabled, "rest-point light still carves environmental silhouettes")
