extends TestCase
## Headless tests for the 3D title props (`scripts/title3d/props/*.gd`).
##
## Every prop is built into a throw-away Node3D, configured exactly the way
## TitleWorld3D does it — setup({world, grade, state}) -> configure(TitleState.prop_plan)
## -> apply_grade(TitleState.grade) -> advance(dt) each frame — then advanced with
## fixed deltas. Assertions:
##   · every script builds and no node is added/removed while advancing (300 frames);
##   · the pure state contract from docs/title-live-scene.md §6 holds (N/14 lanterns,
##     meshing gears, sword-chain modes, brazier/ghost/soul mapping, knight poses);
##   · one-shot `fired(kind, payload)` events land in their documented time window;
##   · two instances fed the same dt sequence end in exactly the same state.
##
## The props are duck-typed on purpose (no class_name, like the 2D title scripts), so
## the locals here are untyped Variants.

const STATE := preload("res://scripts/title3d/title_state.gd")
const PROP_DIR := "res://scripts/title3d/props/"
const PROPS: Array[String] = [
	"gears", "lanterns", "banners", "hammer", "crucible", "sword_chain",
	"ghosts", "souls", "braziers", "knight_actor", "embers", "steam",
]
const ALL_VARIANTS: Array[StringName] = [
	&"cold", &"journey", &"give", &"keep", &"snuff",
]

var _holder: Node3D


func setup() -> void:
	_holder = Node3D.new()
	_holder.name = "PropsUnderTest"
	add_child(_holder)


func teardown() -> void:
	if is_instance_valid(_holder):
		_holder.free()
		_holder = null


# ------------------------------------------------------------------ fixtures ---

func _state(variant: StringName) -> Dictionary:
	return _state_for(variant, 0, 0)


## `variant`, plus optional journey act/cleared override for the act grade tests.
func _state_for(variant: StringName, act: int, cleared: int) -> Dictionary:
	var s := {
		"variant": variant,
		"has_save": variant != &"cold",
		"ending": "" if variant in [&"cold", &"journey"] else String(variant),
		"cleared": 0,
		"act": 0,
		"lit": 0,
	}
	match variant:
		&"cold":
			s["lit"] = 0
		&"journey":
			s["cleared"] = 5 if act == 0 else cleared
			s["act"] = 2 if act == 0 else act
			s["lit"] = s["cleared"]
		&"give", &"keep", &"true_break":
			s["lit"] = 14
		&"snuff":
			s["lit"] = 0
	return s


func grade_of(variant: StringName, act: int = 0, cleared: int = 0) -> Dictionary:
	return STATE.grade(_state_for(variant, act, cleared))


func plan_of(variant: StringName, act: int = 0, cleared: int = 0) -> Dictionary:
	return STATE.prop_plan(_state_for(variant, act, cleared))


# ------------------------------------------------------------------ helpers ---

## Build one prop the same way TitleWorld3D does.
func _build_prop(prop_id: String):
	var path := PROP_DIR + prop_id + ".gd"
	if not ResourceLoader.exists(path):
		ok(false, "missing prop script: " + path)
		return null
	var script: GDScript = load(path)
	if script == null:
		ok(false, "could not load prop script: " + path)
		return null
	var prop = script.new()
	if prop == null:
		ok(false, "could not instantiate prop: " + prop_id)
		return null
	prop.name = prop_id.to_pascal_case()
	_holder.add_child(prop)
	return prop


func _configure(prop, variant: StringName, act: int = 0, cleared: int = 0) -> void:
	var state := _state_for(variant, act, cleared)
	prop.setup({"world": null, "grade": STATE.grade(state), "state": state})
	prop.configure(STATE.prop_plan(state))
	prop.apply_grade(STATE.grade(state))


## Build + configure in one call.
func _make(prop_id: String, variant: StringName = &"cold", act: int = 0, cleared: int = 0):
	var prop = _build_prop(prop_id)
	if prop == null:
		return null
	_configure(prop, variant, act, cleared)
	return prop


## Feed `seconds` through advance() at a fixed frame rate.
func _advance_for(prop, seconds: float, fps: float = 60.0) -> void:
	var step := 1.0 / fps
	var left := seconds
	while left > 0.0:
		var dt := minf(step, left)
		left -= dt
		prop.advance(dt)


## Collect every `fired(kind, payload)` from a prop.
func _record_events(prop) -> Array:
	var events: Array = []
	prop.fired.connect(func(kind, payload) -> void:
		events.append({"kind": kind, "payload": payload}))
	return events


func _event_count(events: Array, kind: StringName) -> int:
	var n := 0
	for e in events:
		if e["kind"] == kind:
			n += 1
	return n


## Props are configured hot when the title switches variant (back from a screen, the
## peek tool): configure()/apply_grade() must only flip state, never rebuild the rig.
func test_plan_hot_switch_keeps_nodes() -> void:
	var lanterns = _make("lanterns", &"cold")
	var chain = _make("sword_chain", &"cold")
	if lanterns == null or chain == null:
		return
	var lantern_nodes: int = lanterns.node_count()
	var chain_nodes: int = chain.node_count()
	for variant in [&"journey", &"give", &"keep", &"snuff", &"journey", &"cold"]:
		lanterns.configure(plan_of(variant))
		lanterns.apply_grade(grade_of(variant))
		chain.configure(plan_of(variant))
		chain.apply_grade(grade_of(variant))
		lanterns.advance(0.3)
		chain.advance(0.3)
		var grade: Dictionary = grade_of(variant)
		eq(lanterns.lit_count(), int(grade["lantern_lit"]),
				"hot switch to %s did not light the right lanterns" % variant)
		eq(chain.mode(), int(grade["chain_mode"]),
				"hot switch to %s did not apply the chain mode" % variant)
	eq(lanterns.node_count(), lantern_nodes, "hot switch rebuilt the lantern rig")
	eq(chain.node_count(), chain_nodes, "hot switch rebuilt the sword chain")
	lanterns.free()
	chain.free()


## Node budget of the whole props layer (measured: 232, one merged body per rig).
func test_prop_node_budget() -> void:
	var total := 0
	var worst := 0
	var worst_id := ""
	for prop_id in PROPS:
		var prop = _make(prop_id, &"journey")
		if prop == null:
			continue
		var n: int = prop.node_count()
		total += n
		if n > worst:
			worst = n
			worst_id = prop_id
		prop.free()
	ok(total <= 260, "props layer node budget exceeded: %d (max 260)" % total)
	ok(worst <= 80, "single prop %s built %d nodes (max 80)" % [worst_id, worst])


# --------------------------------------------------------------------- base ---

func test_prop_scripts_exist() -> void:
	for prop_id in PROPS:
		ok(ResourceLoader.exists(PROP_DIR + prop_id + ".gd"),
				"missing title prop script: " + prop_id + ".gd")


## The contract TitleWorld3D relies on: every prop is drivable the same way, and the
## menu-reaction methods the world calls exist with these names.
func test_title_world_wiring_contract() -> void:
	for prop_id in PROPS:
		var prop = _build_prop(prop_id)
		if prop == null:
			continue
		for method in ["setup", "configure", "apply_grade", "advance", "surge"]:
			ok(prop.has_method(method), "%s is missing %s()" % [prop_id, method])
		ok(prop.has_signal("fired"), prop_id + " is missing the fired signal")
		prop.free()
	var reactions := {
		"lanterns": ["set_lit", "quit_out", "lantern_pulse"],
		"hammer": ["strike_now"],
		"braziers": ["boost_braziers", "surge"],
		"banners": ["gust"],
		"souls": ["soul_boost"],
		"knight_actor": ["gaze", "pose"],
	}
	for prop_id in reactions:
		var prop = _build_prop(prop_id)
		if prop == null:
			continue
		for method in reactions[prop_id]:
			ok(prop.has_method(method), "%s is missing %s()" % [prop_id, method])
		prop.free()


func test_each_prop_builds_and_node_count_is_stable() -> void:
	for prop_id in PROPS:
		var prop = _make(prop_id, &"journey")
		if prop == null:
			continue
		ok(prop.node_count() > 0, prop_id + " built no nodes")
		var before: int = prop.node_count()
		_advance_for(prop, 300.0 / 60.0)
		eq(prop.node_count(), before, prop_id + " added/removed nodes while advancing")
		prop.free()


func test_each_prop_survives_every_variant() -> void:
	for prop_id in PROPS:
		for variant in ALL_VARIANTS:
			var prop = _make(prop_id, variant)
			if prop == null:
				continue
			var before: int = prop.node_count()
			_advance_for(prop, 2.0)
			eq(prop.node_count(), before,
					"%s changed its node count in variant %s" % [prop_id, variant])
			prop.free()


func test_advance_is_deterministic() -> void:
	for prop_id in ["gears", "lanterns", "hammer", "crucible", "souls", "ghosts",
			"sword_chain", "knight_actor"]:
		var a = _make(prop_id, &"journey", 3, 8)
		var b = _make(prop_id, &"journey", 3, 8)
		if a == null or b == null:
			continue
		var steps: Array[float] = [0.016, 0.033, 0.1, 0.25, 0.37, 0.5, 0.016, 1.3, 2.0]
		for dt in steps:
			a.advance(dt)
			b.advance(dt)
		eq(a.state_snapshot(), b.state_snapshot(),
				prop_id + " state drifted between identical runs")
		a.free()
		b.free()


func test_big_delta_is_split_into_small_steps() -> void:
	# A 2.0 s jump is split into <= 0.1 s steps, so it must land on the same cycle
	# position and strike count as 120 x 1/60 s ticks (floats differ in the last bits).
	var a = _make("hammer", &"journey")
	var b = _make("hammer", &"journey")
	if a == null or b == null:
		return
	a.advance(2.0)
	_advance_for(b, 2.0)
	eq(a.strikes(), b.strikes(), "big-delta advance changed the strike count")
	almost(a.head(), b.head(), 0.02, "big-delta advance changed the hammer phase")
	almost(a.billet_level(), b.billet_level(), 0.05,
			"big-delta advance changed the billet temperature")
	a.free()
	b.free()


# -------------------------------------------------------------------- gears ---

func test_gears_mesh_ratio() -> void:
	var gears = _make("gears", &"journey", 4, 14)
	if gears == null:
		return
	gears.advance(3.0)
	var big: float = gears.big_angle()
	var small: float = gears.small_angle()
	var expected: float = gears.small_angle_for(big)
	ok(is_equal_approx(fposmod(small, TAU), fposmod(expected, TAU)),
			"small gear angle is not locked to the big one")
	var teeth: Vector2i = gears.teeth_counts()
	var before := small
	gears.advance(0.5)
	var delta := fposmod(gears.small_angle() - before + PI, TAU) - PI
	ok(delta < 0.0, "small gear turns the same way as the big one")
	eq(teeth, Vector2i(16, 12), "gear tooth counts should be the layout 16/12 pair")
	gears.free()


func test_gears_speed_follows_grade() -> void:
	var cold = _make("gears", &"cold")
	var act4 = _make("gears", &"journey", 4, 14)
	var snuff = _make("gears", &"snuff")
	if cold == null or act4 == null or snuff == null:
		return
	almost(cold.speed_mult(), 0.12, 0.0001, "cold gear_speed should be 0.12")
	almost(act4.speed_mult(), 1.30, 0.0001, "act4 gear_speed should be 1.30")
	almost(snuff.speed_mult(), 0.0, 0.0001, "snuff gear_speed should be 0")
	var before: float = snuff.big_angle()
	snuff.advance(5.0)
	almost(snuff.big_angle(), before, 0.0001, "snuffed gears must not turn")
	var cold_before: float = cold.big_angle()
	cold.advance(5.0)
	ok(cold.big_angle() != cold_before, "cold gears must still creep")
	cold.free()
	act4.free()
	snuff.free()


# ----------------------------------------------------------------- lanterns ---

func test_lanterns_n_of_14_mapping() -> void:
	for n in [0, 1, 5, 7, 13, 14]:
		var lant = _make("lanterns", &"cold")
		if lant == null:
			return
		eq(lant.lantern_count(), 14, "lantern fixture count")
		eq(lant.chain_count(), 6, "decorative chain count")
		lant.apply_grade(_tuned_grade(&"cold", int(n)))
		eq(lant.lit_count(), n, "lantern_lit=%d must light exactly %d/14" % [n, n])
		_advance_for(lant, 1.0)
		eq(lant.glowing_count(), n, "lanterns still fading after 1 s for N=%d" % n)
		lant.free()


func test_lanterns_follow_grade_and_pulse() -> void:
	var give = _make("lanterns", &"give")
	if give == null:
		return
	eq(give.lit_count(), 14, "give ending must light all 14 lanterns")
	_advance_for(give, 1.0)
	var alpha_before: float = give.halo_alpha(0)
	give.lantern_pulse(1.0)
	_advance_for(give, 0.1)
	ok(give.halo_alpha(0) > alpha_before, "lantern_pulse() should brighten a lit lantern")
	give.quit_out(0.1)
	# 2D parity: the first lamp goes out on the call, the rest follow on the stagger.
	eq(give.lit_count(), 13, "quit_out() must douse the first lantern immediately")
	_advance_for(give, 2.5)
	eq(give.lit_count(), 0, "quit_out() should douse every lantern")
	give.free()
	var snuff = _make("lanterns", &"snuff")
	if snuff != null:
		eq(snuff.lit_count(), 0, "snuff ending must light no lantern")
		snuff.free()


func _tuned_grade(variant: StringName, lantern_lit: int) -> Dictionary:
	var grade := grade_of(variant)
	grade["lantern_lit"] = lantern_lit
	return grade


# ----------------------------------------------------------- hammer/crucible ---

func test_hammer_strikes_within_cycle() -> void:
	var hammer = _make("hammer", &"journey")
	if hammer == null:
		return
	var events := _record_events(hammer)
	_advance_for(hammer, 3.7)
	ok(_event_count(events, &"strike") >= 1, "hammer must strike at least once in 3.7 s")
	ok(hammer.strikes() >= 1, "hammer strike counter")
	ok(hammer.billet_level() > 0.2, "the billet must be hot right after a strike")
	var frozen = _make("hammer", &"snuff")
	if frozen != null:
		_advance_for(frozen, 8.0)
		eq(frozen.strikes(), 0, "a snuffed forge must freeze the hammer")
		ok(frozen.is_frozen(), "hammer should report frozen at snuff heat")
		frozen.free()
	# strike_now() lands shortly after (the 'trial' menu reaction)
	hammer.advance(1.0)
	hammer.strike_now()
	var events2 := _record_events(hammer)
	_advance_for(hammer, 2.6)
	ok(_event_count(events2, &"strike") >= 1,
			"strike_now() should produce a strike shortly after")
	hammer.free()


func test_crucible_pours_within_cycle() -> void:
	var crucible = _make("crucible", &"journey", 1, 1)
	if crucible == null:
		return
	var events := _record_events(crucible)
	_advance_for(crucible, 22.0)
	ok(_event_count(events, &"poured") >= 1, "crucible must pour at least once in 22 s")
	ok(crucible.pour_count() >= 1, "crucible pour counter")
	ok(crucible.stream_length() >= 0.0, "stream length must be non-negative")
	var frozen = _make("crucible", &"snuff")
	if frozen != null:
		_advance_for(frozen, 10.0)
		eq(frozen.pour_count(), 0, "a snuffed forge must freeze the crucible")
		frozen.free()
	crucible.free()


# -------------------------------------------------------------- sword chain ---

func test_sword_chain_modes() -> void:
	# RUN: the chain moves and all three swords hang
	var run = _make("sword_chain", &"journey")
	if run == null:
		return
	eq(run.mode(), 0, "journey variant must run the chain")
	eq(run.visible_swords(), 3, "RUN draws all three swords")
	_advance_for(run, 2.0)
	ok(run.roll() > 0.0, "RUN must advance the chain")
	ok(run.is_moving(), "RUN should report moving")
	# deliver at least one sword into the mouth (one full loop at heat 0.75)
	var events := _record_events(run)
	_advance_for(run, 45.0)
	ok(_event_count(events, &"delivered") >= 1, "a running chain must deliver a sword")
	ok(run.runes_lit(), "a running hot chain keeps the name runes glowing")
	run.free()
	# EMPTY ('give'): no swords, chain stopped
	var empty = _make("sword_chain", &"give")
	if empty == null:
		return
	eq(empty.mode(), 1, "give variant must empty the chain")
	eq(empty.visible_swords(), 0, "EMPTY draws no swords")
	var roll_before: float = empty.roll()
	_advance_for(empty, 3.0)
	almost(empty.roll(), roll_before, 0.0001, "EMPTY must not move the chain")
	# STILL ('snuff'): swords stay, chain stopped
	var still = _make("sword_chain", &"snuff")
	if still != null:
		eq(still.mode(), 2, "snuff variant must freeze the chain")
		eq(still.visible_swords(), 3, "STILL keeps the swords hanging")
		var still_roll: float = still.roll()
		_advance_for(still, 3.0)
		almost(still.roll(), still_roll, 0.0001, "STILL must not move the chain")
		ok(not still.runes_lit(), "STILL must keep the name runes cold")
		still.free()
	empty.free()


# ------------------------------------------------------------ banners/ghosts ---

func test_banners_gust() -> void:
	var banners = _make("banners", &"journey")
	if banners == null:
		return
	eq(banners.banner_count(), 2, "two banners")
	var calm: float = banners.amplitude()
	banners.gust()
	ok(banners.amplitude() > calm, "gust() must widen the swing")
	ok(banners.gust_level() > 0.5, "gust level must jump")
	_advance_for(banners, 4.0)
	almost(banners.gust_level(), 0.0, 0.02, "gust must decay")
	banners.free()


func test_ghosts_count_and_patrol() -> void:
	for n in [0, 1, 3]:
		var ghosts = _make("ghosts", &"journey")
		if ghosts == null:
			return
		ghosts.apply_grade(_grade_with(&"journey", {"ghost_count": n}))
		eq(ghosts.visible_count(), n, "ghost_count=%d must show exactly %d silhouettes" % [n, n])
		if n > 0:
			var before: float = ghosts.walked()
			_advance_for(ghosts, 2.0)
			ok(ghosts.walked() > before, "hot hall ghosts must patrol")
		ghosts.free()


func _grade_with(variant: StringName, overrides: Dictionary) -> Dictionary:
	var grade := grade_of(variant)
	for key in overrides:
		grade[key] = overrides[key]
	return grade


# -------------------------------------------------------------------- souls ---

func test_souls_pool_and_escape() -> void:
	var keep = _make("souls", &"keep")
	if keep == null:
		return
	_advance_for(keep, 3.0)
	eq(keep.live_count(), 5, "keep ending souls_goal should be 5 alive")
	ok(not keep.is_escaping(), "trapped souls must not escape")
	keep.soul_boost(6)
	ok(keep.target_count() > 5, "soul_boost() must raise the live target")
	_advance_for(keep, 4.5)
	almost(keep.target_count(), 5, 1.0, "the soul boost must expire")
	var give = _make("souls", &"give")
	if give == null:
		return
	_advance_for(give, 3.0)
	ok(give.is_escaping(), "give ending souls must escape")
	ok(give.live_count() > 0, "give ending souls must be on screen")
	var start_high: float = give.highest_y()
	_advance_for(give, 12.0)
	ok(give.highest_y() > start_high, "escaping souls must climb toward the skylight")
	keep.free()
	give.free()
	var snuff = _make("souls", &"snuff")
	if snuff != null:
		_advance_for(snuff, 2.0)
		eq(snuff.live_count(), 0, "snuff ending shows no souls")
		eq(snuff.target_count(), 0, "snuff ending target count is zero")
		snuff.free()


# ----------------------------------------------------------------- braziers ---

func test_braziers_levels_and_boost() -> void:
	var keep = _make("braziers", &"keep")
	if keep == null:
		return
	eq(keep.lit_count(), 2, "keep ending lights both braziers")
	ok(keep.brightest() > 1.2, "keep ending braziers are the brightest")
	var base: float = keep.level_of(0)
	keep.boost_braziers()
	ok(keep.level_of(0) > base, "boost_braziers() must flare the bowl")
	_advance_for(keep, 3.0)
	ok(keep.boost() < 0.05, "brazier boost must decay")
	var cold = _make("braziers", &"cold")
	if cold == null:
		return
	eq(cold.lit_count(), 0, "cold variant has no lit brazier")
	cold.boost_braziers()
	ok(cold.level_of(0) > 0.05, "boost must jump a cold bowl alight for a moment")
	cold.surge(1.0)
	ok(cold.boost() > 0.0, "surge must kick the braziers too")
	_advance_for(cold, 1.0)
	keep.free()
	cold.free()


# ------------------------------------------------------------- embers/steam ---

func test_ember_and_steam_rates() -> void:
	var embers_act4 = _make("embers", &"journey", 4, 14)
	if embers_act4 == null:
		return
	eq(embers_act4.emitter_count(), 2, "embers needs two emitters")
	ok(embers_act4.emitting(), "act4 embers must emit")
	ok(embers_act4.mouth_ratio() > 0.5, "act4 forge mouth should be near full rate")
	almost(embers_act4.rate(), 1.35, 0.0001, "act4 ember_rate")
	var embers_snuff = _make("embers", &"snuff")
	if embers_snuff != null:
		ok(not embers_snuff.emitting(), "snuff embers must be off")
		eq(embers_snuff.mouth_ratio(), 0.0, "snuff embers ratio is zero")
		embers_snuff.free()
	var steam_act4 = _make("steam", &"journey", 4, 14)
	if steam_act4 == null:
		return
	eq(steam_act4.emitter_count(), 2, "steam needs two emitters")
	ok(steam_act4.emitting(), "act4 steam must emit")
	almost(steam_act4.stack_ratio(), 1.0, 0.0001, "act4 steam_rate is 1.0")
	var steam_cold = _make("steam", &"cold")
	if steam_cold != null:
		ok(not steam_cold.emitting(), "cold hall has no steam")
		steam_cold.free()
	embers_act4.free()
	steam_act4.free()


# ------------------------------------------------------------------- knight ---

func test_knight_poses() -> void:
	# stand: cold / journey
	var stand = _make("knight_actor", &"journey")
	if stand == null:
		return
	eq(stand.pose(), &"stand", "journey knight must stand")
	ok(stand.knight_visible(), "stand pose shows the knight")
	ok(stand.back_sword_visible(), "stand pose carries the greatsword on the back")
	ok(not stand.planted_visible(), "stand pose has no planted sword")
	# seated: keep ending at the bench, always looking at the fire
	var seated = _make("knight_actor", &"keep")
	if seated == null:
		return
	eq(seated.pose(), &"seated", "keep ending knight must sit")
	ok(seated.knight_visible(), "seated pose shows the knight")
	ok(seated.gazing(), "keep ending knight is always gazing at the forge")
	# planted: give ending, the knight is gone and the greatsword stands in the bridge
	var planted = _make("knight_actor", &"give")
	if planted == null:
		return
	eq(planted.pose(), &"planted", "give ending must leave the planted sword")
	ok(not planted.knight_visible(), "give ending has no knight on the bridge")
	ok(planted.planted_visible(), "give ending shows the planted greatsword")
	# absent: snuff ending, empty bridge
	var absent = _make("knight_actor", &"snuff")
	if absent == null:
		return
	eq(absent.pose(), &"absent", "snuff ending must be absent")
	ok(not absent.knight_visible(), "snuff ending has no knight")
	ok(not absent.planted_visible(), "snuff ending has no planted sword either")
	stand.free()
	seated.free()
	planted.free()
	absent.free()


func test_knight_gaze_clock() -> void:
	var knight = _make("knight_actor", &"journey")
	if knight == null:
		return
	eq(knight.pose(), &"stand")
	_advance_for(knight, 6.5)
	ok(not knight.gazing(), "the knight must not gaze before the first 7 s")
	_advance_for(knight, 1.0)
	ok(knight.gazing(), "the knight must look at the forge ~7 s after start")
	var yaw_during: float = knight.yaw_deg()
	_advance_for(knight, 5.0)
	ok(not knight.gazing(), "the gaze must end after 4.6 s")
	ok(absf(yaw_during) > 90.0, "the gaze turn must swing the body toward the forge")
	# the 'continue' menu reaction starts an immediate gaze
	knight.gaze(4.6)
	ok(knight.gazing(), "gaze(seconds) must start a gaze")
	_advance_for(knight, 5.0)
	ok(not knight.gazing(), "gaze(seconds) must end after its hold")
	knight.free()
