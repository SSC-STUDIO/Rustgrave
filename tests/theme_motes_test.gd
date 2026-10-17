extends TestCase
## ThemeMotes is presentation only: a capped pool that recycles around the camera.


func test_every_flavour_is_capped_and_configurable() -> void:
	for id in ThemeMotes.FLAVORS:
		var motes := ThemeMotes.new()
		motes.flavor = id
		add_child(motes)
		ok(motes.mote_count() > 0 and motes.mote_count() <= ThemeMotes.MAX_MOTES, "%s pool size %d" % [id, motes.mote_count()])
		eq(motes.flavor, id)
		motes.queue_free()


func test_unknown_flavour_falls_back_to_embers() -> void:
	var motes := ThemeMotes.new()
	motes.flavor = "nope"
	add_child(motes)
	eq(motes.flavor, "embers", "a typo is visible as embers, not silent")
	ok(not ThemeMotes.has_flavor("nope"))
	ok(ThemeMotes.has_flavor("sparks"))


func test_first_step_scatters_the_pool_into_the_view() -> void:
	var motes := ThemeMotes.new()
	motes.flavor = "embers"
	add_child(motes)
	var origin := Vector2(1000.0, 200.0)
	motes.step(0.016, origin)
	ok(motes.live_count() >= motes.mote_count() - 2, "embers fill the view on the first frame (%d/%d)" % [motes.live_count(), motes.mote_count()])
	var seen_alpha := 0
	for i in motes.mote_count():
		if motes.mote_alpha(i) > 0.05:
			seen_alpha += 1
	ok(seen_alpha > 4, "motes carry staggered ages, not one fade-in (%d visible)" % seen_alpha)


func test_embers_rise_and_cinders_fall() -> void:
	var origin := Vector2(500.0, 100.0)
	var embers := ThemeMotes.new()
	embers.flavor = "embers"
	add_child(embers)
	embers.step(0.016, origin)
	var before := embers._pos.duplicate()
	for _i in 30:
		embers.step(0.05, origin)
	var rose := 0
	for i in embers.mote_count():
		if embers._age[i] > 0.0 and embers._pos[i].y < before[i].y:
			rose += 1
	ok(rose > embers.mote_count() / 2, "most embers climbed (%d)" % rose)
	var cinders := ThemeMotes.new()
	cinders.flavor = "cinders"
	add_child(cinders)
	cinders.step(0.016, origin)
	var start := cinders._pos.duplicate()
	for _i in 10:
		cinders.step(0.05, origin)
	var fell := 0
	for i in cinders.mote_count():
		if cinders._age[i] > 0.0 and cinders._pos[i].y > start[i].y:
			fell += 1
	ok(fell > cinders.mote_count() / 2, "most cinders sank (%d)" % fell)


func test_sparks_come_in_bursts_and_burn_out() -> void:
	var sparks := ThemeMotes.new()
	sparks.flavor = "sparks"
	add_child(sparks)
	var origin := Vector2(300.0, 180.0)
	eq(sparks.live_count(), 0, "no sparks before the first burst")
	var peak := 0
	for _i in 120:
		sparks.step(0.05, origin)
		peak = maxi(peak, sparks.live_count())
	ok(peak >= 3, "a burst threw sparks (peak %d)" % peak)
	for _i in 60:
		sparks.step(0.05, origin)
		peak = maxi(peak, sparks.live_count())
	ok(sparks.live_count() <= ThemeMotes.MAX_MOTES)


func test_recycles_motes_that_leave_the_view() -> void:
	var motes := ThemeMotes.new()
	motes.flavor = "dust"
	add_child(motes)
	motes.step(0.016, Vector2(0.0, 0.0))
	# The camera jumps a chapter away. Everything is far outside the margin now.
	var far := Vector2(5000.0, 0.0)
	motes.step(0.016, far)
	motes.step(0.016, far)
	var inside := 0
	for i in motes.mote_count():
		if motes._age[i] < motes._life[i] and absf(motes._pos[i].x - far.x) <= ThemeMotes.MARGIN.x:
			inside += 1
	ok(inside >= motes.mote_count() - 2, "the pool re-seeds around the new camera (%d)" % inside)


func test_chapter_layouts_declare_valid_flavours() -> void:
	for id in ["level04", "level05", "level07", "level08", "level10"]:
		var layout := (load(GameContext.LAYOUTS[id]) as GDScript).new() as ChapterLayout
		ok(ThemeMotes.has_flavor(layout.motes()), "%s names a real flavour (%s)" % [id, layout.motes()])
		layout.free()


func test_outdoor_chapters_set_their_signature_sky() -> void:
	for id in ["level03", "level06", "level09"]:
		var layout := (load(GameContext.LAYOUTS[id]) as GDScript).new() as ChapterLayout
		var amb := layout.ambient()
		ok(amb.has("time") and amb.has("weather"), "%s sets a time and weather" % id)
		ok(["haze", "rain", "fog", "ember_wind", "rust_rain", "clear"].has(String(amb["weather"])),
				"%s weather id is real (%s)" % [id, amb["weather"]])
		layout.free()
	var night := (load(GameContext.LAYOUTS["level06"]) as GDScript).new() as ChapterLayout
	eq(WorldClock.phase_at(float(night.ambient()["time"])), WorldClock.Phase.NIGHT, "墓园夜雨 opens at night")
	eq(night.ambient()["weather"], "rain")
	night.free()


func test_apply_ambient_moves_the_clock_once() -> void:
	WorldClock.reset()
	ChapterLevel.apply_ambient({"time": 0.82, "weather": "rain", "hold": 500.0})
	eq(WorldClock.phase, WorldClock.Phase.NIGHT)
	eq(WorldClock.weather, WorldClock.Weather.RAIN)
	ChapterLevel.apply_ambient({})
	eq(WorldClock.weather, WorldClock.Weather.RAIN, "an empty ambient leaves the clock alone")
	WorldClock.reset()


## 特效不遮挡（docs/art-spec.md「特效不遮挡原则」）：环境浮尘是氛围层，
## z_index 必须低于玩法层（角色 0）、高于 backdrop（CanvasLayer -10），
## 永远不横穿脸、敌人前摇、台缘或地面陷阱。
func test_motes_stay_below_the_play_layer() -> void:
	var motes := ThemeMotes.new()
	add_child(motes)
	eq(motes.z_index, ThemeMotes.DEPTH_Z)
	ok(motes.z_index < 0, "motes draw behind the knight (z=0), not across the silhouette")
	ok(motes.z_index >= -5, "motes stay above the backdrop canvas (layer -10)")
	var seen := 0
	for id in ThemeMotes.FLAVORS:
		var probe := ThemeMotes.new()
		probe.flavor = id
		add_child(probe)
		if probe.z_index == ThemeMotes.DEPTH_Z:
			seen += 1
		probe.queue_free()
	eq(seen, ThemeMotes.FLAVORS.size(), "every flavour keeps the same presentation depth")
	ok(ThemeMotes.MAX_MOTES <= 40, "the pool stays capped; it is atmosphere, not a screen wash")
