extends TestCase
## docs/combat-rules.md 与 CombatRules 逐项比对 + 帧表 + 取消规则 + 预输入。
## 数字漂移（改代码没改文档，或反过来）会在这里失败。

const DOC := "res://docs/combat-rules.md"
const DT := 1.0 / 60.0

var melee: MeleeCombat


func setup() -> void:
	melee = MeleeCombat.new()
	var hb := Area2D.new()
	hb.name = "Hitbox"
	hb.set_script(load("res://scripts/combat/hitbox.gd"))
	melee.add_child(hb)
	add_child(melee)
	melee.set_physics_process(false)


# ---------------------------------------------------------------------------
# 文档 <-> 代码
# ---------------------------------------------------------------------------
func _doc() -> String:
	var f := FileAccess.open(DOC, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _floats(tokens: PackedStringArray) -> Array:
	var out: Array = []
	for t in tokens:
		out.append(float(t))
	return out


func _same(a: Array, b: Array, eps: float = 0.0006) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(float(a[i]) - float(b[i])) > eps:
			return false
	return true


func _expected_rules() -> Dictionary:
	return {
		"SWING_WINDUP": CombatRules.SWING_WINDUP, "SWING_ACTIVE": CombatRules.SWING_ACTIVE,
		"SWING_RECOVERY": CombatRules.SWING_RECOVERY, "SWING_DAMAGE": CombatRules.SWING_DAMAGE,
		"SWING_COOLDOWN": [CombatRules.SWING_COOLDOWN], "ATTACK_BUFFER": [CombatRules.ATTACK_BUFFER],
		"LINK_EARLY": [CombatRules.LINK_EARLY], "LATE_LINK_GRACE": [CombatRules.LATE_LINK_GRACE],
		"SWING_MOVE_SCALE": [CombatRules.SWING_MOVE_SCALE],
		"DASH_DURATION": [CombatRules.DASH_DURATION], "DASH_IFRAMES": [CombatRules.DASH_IFRAMES],
		"DASH_COOLDOWN": [CombatRules.DASH_COOLDOWN], "DASH_BUFFER": [CombatRules.DASH_BUFFER],
		"COYOTE_TIME": [CombatRules.COYOTE_TIME], "JUMP_BUFFER": [CombatRules.JUMP_BUFFER],
		"HIT_IFRAMES": [CombatRules.HIT_IFRAMES],
		"DASH_CANCEL_FROM": [CombatRules.DASH_CANCEL_FROM],
		"DASH_CANCEL_FROM_CONNECTED": [CombatRules.DASH_CANCEL_FROM_CONNECTED],
		"JUMP_CANCEL_FROM": [CombatRules.JUMP_CANCEL_FROM],
		"JUMP_CANCEL_FROM_CONNECTED": [CombatRules.JUMP_CANCEL_FROM_CONNECTED],
		"PARRY_PURIFY": [CombatRules.PARRY_PURIFY], "PARRY_RESONANCE": [CombatRules.PARRY_RESONANCE],
		"PARRY_SLOWMO_MS": [CombatRules.PARRY_SLOWMO_MS], "RIPOSTE_TIME": [CombatRules.RIPOSTE_TIME],
		"RIPOSTE_MULT": [CombatRules.RIPOSTE_MULT], "RIPOSTE_STAGGER": [CombatRules.RIPOSTE_STAGGER],
		"OVERFLOW_TICK": [CombatRules.OVERFLOW_TICK], "TELEGRAPH_MIN": [CombatRules.TELEGRAPH_MIN],
	}


func test_doc_rules_block_matches_code() -> void:
	var text := _doc()
	ok(text != "", "docs/combat-rules.md is readable")
	var start := text.find("```rules")
	ok(start >= 0, "doc has a ```rules block")
	if start < 0:
		return
	var body := text.substr(start + 8)
	body = body.substr(0, body.find("```"))
	var seen: Dictionary = {}
	for line in body.split("\n", false):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() < 2:
			continue
		seen[parts[0]] = _floats(parts.slice(1))
	var expected := _expected_rules()
	for key in expected:
		ok(seen.has(key), "doc lists %s" % key)
		if seen.has(key):
			ok(_same(seen[key], expected[key]), "%s: doc %s vs code %s" % [key, str(seen[key]), str(expected[key])])
	for key in seen:
		ok(expected.has(key), "doc rule %s has a code counterpart" % key)


func _table_rows(text: String, first_cells: Array, cell_count: int) -> Array:
	var rows: Array = []
	for line in text.split("\n", false):
		var s := line.strip_edges()
		if not s.begins_with("|"):
			continue
		var cells := s.trim_prefix("|").trim_suffix("|").split("|")
		var trimmed: Array = []
		for c in cells:
			trimmed.append(String(c).strip_edges())
		if trimmed.size() == cell_count and trimmed[0] in first_cells:
			rows.append(trimmed)
	return rows


func test_doc_hit_matrix_matches_code() -> void:
	var rows := _table_rows(_doc(), CombatRules.MATERIALS.map(func(m: StringName) -> String: return String(m)), 13)
	eq(rows.size(), CombatRules.MATERIALS.size() * CombatRules.WEIGHTS.size(), "one doc row per material x weight")
	for row in rows:
		var feel := CombatRules.feel(StringName(row[0]), StringName(row[1]))
		eq(int(row[2]), int(feel["stop_ms"]), "%s/%s stop_ms" % [row[0], row[1]])
		almost(float(row[3]), float(feel["stop_scale"]), 0.0006, "%s/%s stop_scale" % [row[0], row[1]])
		almost(float(row[4]), float(feel["shake_px"]), 0.0006, "%s/%s shake_px" % [row[0], row[1]])
		eq(int(row[5]), int(feel["shake_ms"]), "%s/%s shake_ms" % [row[0], row[1]])
		eq(StringName(row[6]), feel["spark"], "%s/%s spark" % [row[0], row[1]])
		eq(StringName(row[7]), feel["debris"], "%s/%s debris" % [row[0], row[1]])
		eq(row[8] == "yes", bool(feel["ring"]), "%s/%s ring" % [row[0], row[1]])
		almost(float(row[9]), float(feel["knock"]), 0.0006, "%s/%s knock" % [row[0], row[1]])
		almost(float(row[10]), float(feel["lock"]), 0.0006, "%s/%s lock" % [row[0], row[1]])
		almost(float(row[11]), float(feel["recoil"]), 0.0006, "%s/%s recoil" % [row[0], row[1]])
		eq(StringName(row[12]), feel["sfx"], "%s/%s sfx" % [row[0], row[1]])


func test_doc_telegraph_table_matches_code() -> void:
	var kinds: Array = CombatRules.TELEGRAPH.keys().map(func(k: StringName) -> String: return String(k))
	var rows := _table_rows(_doc(), kinds, 5)
	eq(rows.size(), CombatRules.TELEGRAPH.size(), "one doc row per enemy kind")
	for row in rows:
		var entry: Dictionary = CombatRules.TELEGRAPH[StringName(row[0])]
		almost(float(row[1]), float(entry["time"]), 0.0006, "%s telegraph time" % row[0])
		almost(float(row[2]), float(entry["punish"]), 0.0006, "%s punish" % row[0])
		eq(StringName(row[3]), entry["cue"], "%s cue" % row[0])
		eq(StringName(row[4]), entry["signature"], "%s signature" % row[0])


func test_runtime_defaults_mirror_the_rules() -> void:
	var ctrl := PlayerController.new()
	almost(ctrl.dash_duration, CombatRules.DASH_DURATION)
	almost(ctrl.iframe_duration, CombatRules.DASH_IFRAMES)
	almost(ctrl.dash_cooldown, CombatRules.DASH_COOLDOWN)
	almost(ctrl.dash_buffer_time, CombatRules.DASH_BUFFER)
	almost(ctrl.coyote_time, CombatRules.COYOTE_TIME)
	almost(ctrl.jump_buffer_time, CombatRules.JUMP_BUFFER)
	ok(ctrl.iframe_duration >= ctrl.dash_duration - 0.0001, "i-frames cover the whole dash")
	ctrl.free()
	almost(melee.cooldown, CombatRules.SWING_COOLDOWN)
	almost(melee.windup_time, float(CombatRules.SWING_WINDUP[0]))
	almost(MeleeCombat.ATTACK_BUFFER_TIME, CombatRules.ATTACK_BUFFER)
	almost(MeleeCombat.LINK_EARLY_TIME, CombatRules.LINK_EARLY)
	var hp := Health.new()
	almost(hp.hit_iframe_time, CombatRules.HIT_IFRAMES)
	hp.free()
	var tox := ToxinMeter.new()
	almost(tox.overflow_interval, CombatRules.OVERFLOW_TICK)
	eq(ToxinMeter.band_for(ToxinMeter.BAND_WARM, 100.0), &"warm")
	tox.free()
	almost(Resonance.DURATION, CombatRules.PARRY_RESONANCE)


# ---------------------------------------------------------------------------
# 帧表
# ---------------------------------------------------------------------------
func _measure(index: int) -> Array:
	melee.cancel_attack()
	melee._combo_index = index
	melee._cooldown = 0.0
	var step := 0.002
	ok(melee.start_swing(), "swing %d starts" % index)
	var spans := [0.0, 0.0, 0.0]
	var phases := ["windup", "active", "recovery"]
	for p in 3:
		var guard := 0
		while melee.phase_name() == phases[p] and guard < 2000:
			melee.tick(step)
			spans[p] += step
			guard += 1
	return spans


func test_attack_pose_holds_windup_and_strikes_on_the_active_frame() -> void:
	eq(Player.attack_frame_index(4, "windup", 0.0), 0, "first swing holds the chamber")
	eq(Player.attack_frame_index(4, "windup", 1.0), 0, "four frames have no separate lift before the strike")
	eq(Player.attack_frame_index(4, "active", 0.4), 1, "the active frame is the downward slash")
	eq(Player.attack_frame_index(4, "recovery", 0.0), 2)
	eq(Player.attack_frame_index(4, "recovery", 1.0), 3, "recovery ends on the follow-through")
	eq(Player.attack_frame_index(6, "windup", 0.2), 0)
	eq(Player.attack_frame_index(6, "windup", 0.9), 1, "a longer swing lifts just before it connects")
	eq(Player.attack_frame_index(6, "active", 0.0), 2)
	eq(Player.attack_frame_index(6, "recovery", 1.0), 5)
	eq(Player.attack_frame_index(1, "active", 0.5), 0)


func test_swing_frame_table_is_what_the_rules_say() -> void:
	for index in 3:
		var spans := _measure(index)
		almost(spans[0], float(CombatRules.SWING_WINDUP[index]), 0.004, "swing %d windup" % index)
		almost(spans[1], float(CombatRules.SWING_ACTIVE[index]), 0.004, "swing %d active" % index)
		almost(spans[2], float(CombatRules.SWING_RECOVERY[index]), 0.004, "swing %d recovery" % index)
		almost(CombatRules.swing_total(index),
				float(CombatRules.SWING_WINDUP[index]) + float(CombatRules.SWING_ACTIVE[index])
				+ float(CombatRules.SWING_RECOVERY[index]), 0.0001)
	ok(float(CombatRules.SWING_DAMAGE[2]) > float(CombatRules.SWING_DAMAGE[0]), "the finisher hits harder")


# ---------------------------------------------------------------------------
# 取消规则
# ---------------------------------------------------------------------------
func _to_phase(phase: String) -> void:
	for i in 600:
		if melee.phase_name() == phase:
			return
		melee.tick(0.002)
	ok(false, "phase reached: " + phase)


func test_nothing_cancels_windup_or_active() -> void:
	ok(melee.start_swing())
	var timer_before := melee._timer
	ok(not melee.can_dash_cancel(), "windup: dash cannot cancel")
	ok(not melee.can_jump_cancel(), "windup: jump cannot cancel")
	ok(not melee.cancel_recovery(), "windup: cancel_recovery refuses")
	eq(melee.phase_name(), "windup")
	almost(melee._timer, timer_before, 0.0001, "windup not shortened")
	_to_phase("active")
	melee.hitbox.connected = true  # 命中也不能在判定期取消
	timer_before = melee._timer
	ok(not melee.can_dash_cancel(), "active: even a connected swing cannot dash-cancel")
	ok(not melee.can_jump_cancel(), "active: jump cannot cancel")
	ok(not melee.cancel_recovery(), "active: cancel_recovery refuses")
	eq(melee.phase_name(), "active")
	almost(melee._timer, timer_before, 0.0001, "active not shortened")


func test_a_buffered_press_never_shortens_a_committed_phase() -> void:
	ok(melee.request_attack())
	ok(not melee.request_attack(), "windup cannot queue")
	var windup_left := melee._timer
	melee.request_attack()
	almost(melee._timer, windup_left, 0.0001, "windup untouched by presses")
	_to_phase("active")
	var active_left := melee._timer
	for i in 3:
		melee.request_attack()
	almost(melee._timer, active_left, 0.0001, "active untouched by presses")
	_to_phase("recovery")
	var recovery_left := melee._timer
	melee.request_attack()
	almost(melee._timer, recovery_left, 0.0001, "recovery untouched by a queued link")
	ok(melee._link_buffered)
	ok(not melee.can_dash_cancel(), "a queued link opens no dash window")


func test_whiffed_swing_dash_window_opens_at_sixty_percent_of_recovery() -> void:
	ok(melee.start_swing())
	_to_phase("recovery")
	ok(not melee.swing_connected())
	ok(not melee.can_dash_cancel(), "recovery start: whiffs are committed")
	var total := float(CombatRules.SWING_RECOVERY[0])
	melee.tick(total * 0.55)
	ok(melee.recovery_progress() < CombatRules.DASH_CANCEL_FROM)
	ok(not melee.can_dash_cancel(), "55%: still committed")
	ok(not melee.can_jump_cancel(), "55%: jump window still shut")
	melee.tick(total * 0.10)
	ok(melee.recovery_progress() >= CombatRules.DASH_CANCEL_FROM)
	ok(melee.can_dash_cancel(), "65%: dash may cancel")
	ok(melee.can_jump_cancel(), "65%: jump may cancel the last 40%")


func test_connected_swing_dash_window_opens_at_the_start_of_recovery() -> void:
	ok(melee.start_swing())
	_to_phase("active")
	melee.hitbox.connected = true
	_to_phase("recovery")
	ok(melee.swing_connected())
	ok(melee.can_dash_cancel(), "a landed blow can dash out immediately")
	ok(melee.can_jump_cancel(), "a landed blow can jump-cancel from the start of recovery")
	ok(melee.cancel_recovery(), "cancelling recovery succeeds")
	eq(melee.phase_name(), "idle")
	eq(melee._combo_index, 0, "cancel resets the chain")
	ok(not melee._link_buffered, "cancel drops the queued link")


func test_parry_counts_as_connected() -> void:
	ok(melee.start_swing())
	_to_phase("active")
	const PROJ := preload("res://scenes/combat/Projectile.tscn")
	var shooter := Node2D.new()
	shooter.position = Vector2(200, 0)
	add_child(shooter)
	var bolt: Projectile = PROJ.instantiate()
	add_child(bolt)
	bolt.setup(Vector2(20, 0), Vector2.LEFT, 10.0, &"enemy", shooter)
	ok(melee.try_deflect(bolt), "parry window accepts the bolt")
	_to_phase("recovery")
	ok(melee.swing_connected(), "a parry opens the early dash window")
	ok(melee.can_dash_cancel())


func test_window_closes_for_the_next_swing() -> void:
	ok(melee.start_swing())
	_to_phase("active")
	melee.hitbox.connected = true
	_to_phase("idle")
	melee._cooldown = 0.0
	ok(melee.start_swing())
	_to_phase("active")
	ok(not melee.swing_connected(), "connected resets for the next swing")
	_to_phase("recovery")
	ok(not melee.can_dash_cancel(), "the new swing is a whiff until proven otherwise")


# ---------------------------------------------------------------------------
# 补接 / 事件线程按键
# ---------------------------------------------------------------------------
func test_press_just_after_recovery_still_links_the_chain() -> void:
	ok(melee.start_swing())
	_to_phase("idle")
	ok(melee._cooldown > 0.0, "idle cooldown is still running")
	ok(melee.request_attack(), "late press accepted")
	eq(melee.phase_name(), "windup", "late link starts the next swing at once")
	eq(melee._combo_index, 1, "...as the second blow, not a fresh first")
	_to_phase("recovery")
	_to_phase("idle")
	melee.tick(CombatRules.LATE_LINK_GRACE + 0.02)
	ok(melee.request_attack(), "after the grace the press is only buffered")
	eq(melee.phase_name(), "idle")
	ok(melee._attack_buffer > 0.0)


func test_third_blow_has_no_late_link() -> void:
	melee._combo_index = 2
	ok(melee.start_swing())
	_to_phase("idle")
	melee.tick(0.01)
	ok(melee.request_attack())
	eq(melee._combo_index, 0, "a finished chain never skips ahead: the next press is a fresh first blow")
	ok(melee._late_next == 0, "no late-link state after the finisher")


func _press_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"attack"
	ev.pressed = true
	return ev


func test_event_latched_press_survives_a_gap_between_physics_ticks() -> void:
	melee._input(_press_event())
	melee.tick(DT)
	eq(melee.phase_name(), "windup", "a tap that Input polling would miss still starts the swing")


func test_stale_latched_press_is_ignored() -> void:
	melee._press_latched_tick = Engine.get_physics_frames() - (MeleeCombat.LATCH_TICKS + 5)
	melee.tick(DT)
	eq(melee.phase_name(), "idle", "an old press from before a pause cannot fire later")


func test_latched_press_is_single_use() -> void:
	melee._input(_press_event())
	melee.tick(DT)
	eq(melee.phase_name(), "windup")
	melee.cancel_attack()
	melee._cooldown = 0.0
	melee.tick(DT)
	eq(melee.phase_name(), "idle", "one tap makes one swing")


# ---------------------------------------------------------------------------
# 冲刺闸门（真实骑士）
# ---------------------------------------------------------------------------
func _knight() -> Player:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var p := await spawn_player(arena)
	p.set_physics_process(false)
	p.melee.set_physics_process(false)
	return p


func _latch_dash(p: Player) -> void:
	p.controller._dash_latched_tick = Engine.get_physics_frames()


func test_dash_waits_for_the_window_and_then_cancels_recovery() -> void:
	var p := await _knight()
	var ctrl := p.controller
	ok(p.melee.start_swing())
	_latch_dash(p)
	ctrl.physics_tick(p, DT, CombatRules.SWING_MOVE_SCALE)
	ok(not ctrl.is_dashing(), "windup: the press is held, not obeyed")
	ok(ctrl.dash_buffered() > 0.0, "...and kept in the buffer")
	for i in 80:
		if p.melee.phase_name() == "recovery":
			break
		p.melee.tick(DT)
		ctrl.physics_tick(p, DT, CombatRules.SWING_MOVE_SCALE)
		ok(not ctrl.is_dashing(), "no dash leaks out before recovery")
	eq(p.melee.phase_name(), "recovery")
	for i in 40:
		if p.melee.recovery_progress() >= 0.3:
			break
		p.melee.tick(DT)
		p.controller.physics_tick(p, DT, CombatRules.SWING_MOVE_SCALE)
	_latch_dash(p)
	var fired := false
	for i in 40:
		p.melee.tick(DT)
		ctrl.physics_tick(p, DT, CombatRules.SWING_MOVE_SCALE)
		if ctrl.is_dashing():
			fired = true
			break
	ok(fired, "dash fires once the whiff window opens")
	eq(p.melee.phase_name(), "idle", "the dash ended the recovery")
	ok(not ctrl._commit_lock, "commit lock lifted")
	almost(ctrl.dash_buffered(), 0.0, 0.0001, "buffer consumed")


func test_connected_swing_dashes_from_the_first_recovery_frame() -> void:
	var p := await _knight()
	ok(p.melee.start_swing())
	for i in 60:
		if p.melee.phase_name() == "active":
			break
		p.melee.tick(DT)
	p.melee.hitbox.connected = true
	for i in 60:
		if p.melee.phase_name() == "recovery":
			break
		p.melee.tick(DT)
	eq(p.melee.phase_name(), "recovery")
	_latch_dash(p)
	p.controller.physics_tick(p, DT, CombatRules.SWING_MOVE_SCALE)
	ok(p.controller.is_dashing(), "hit-and-run: dash out of recovery right away")
	eq(p.melee.phase_name(), "idle")
	ok(p.controller.is_invincible(), "the dash carries i-frames")


func test_dash_press_that_comes_too_early_expires() -> void:
	var p := await _knight()
	ok(p.melee.start_swing())
	for i in 90:
		if p.melee.phase_name() == "recovery":
			break
		p.melee.tick(DT)
	eq(p.melee.phase_name(), "recovery")
	_latch_dash(p)
	var window := float(CombatRules.SWING_RECOVERY[0]) * CombatRules.DASH_CANCEL_FROM
	ok(window > CombatRules.DASH_BUFFER, "the window opens later than the buffer lasts")
	for i in ceili((CombatRules.DASH_BUFFER + 0.03) / DT):
		p.melee.tick(DT)
		p.controller.physics_tick(p, DT, CombatRules.SWING_MOVE_SCALE)
	ok(not p.controller.is_dashing(), "a press made 0.2 s early is gone")
	for i in 20:
		p.melee.tick(DT)
		p.controller.physics_tick(p, DT, CombatRules.SWING_MOVE_SCALE)
	ok(not p.controller.is_dashing(), "and it does not come back when the window finally opens")


func test_jump_cancels_only_the_last_forty_percent_of_recovery() -> void:
	var p := await _knight()
	ok(p.melee.start_swing())
	for i in 90:
		if p.melee.phase_name() == "recovery":
			break
		p.melee.tick(DT)
	eq(p.melee.phase_name(), "recovery")
	p.controller._do_jump(p, false)
	eq(p.melee.phase_name(), "recovery", "early jump launches but the swing stays committed")
	ok(p.velocity.y < -100.0, "the jump itself is never swallowed")
	p.melee.tick(float(CombatRules.SWING_RECOVERY[0]) * 0.7)
	ok(p.melee.can_jump_cancel())
	p.controller._do_jump(p, true)
	eq(p.melee.phase_name(), "idle", "a late jump ends the swing and restores air control")


func test_swing_move_scale_matches_the_rules() -> void:
	almost(CombatRules.SWING_MOVE_SCALE, 0.42)
	var p := await _knight()
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	ok(src.contains("CombatRules.SWING_MOVE_SCALE"), "player.gd reads the swing slow-down from CombatRules")
	p.queue_free()


# ---------------------------------------------------------------------------
# 读招表与敌人状态机的实际常量对齐（表不是孤立的文档）
# ---------------------------------------------------------------------------
func test_telegraph_table_matches_enemy_behaviour_constants() -> void:
	var tg := CombatRules.TELEGRAPH
	# 喷吐者
	almost(SpitterEnemy.CHARGE_TIME, float(tg[&"spitter"]["time"]), 0.0001, "spitter charge")
	almost(SpitterEnemy.EXHALE_TIME, float(tg[&"spitter"]["punish"]), 0.0001, "spitter exhale")
	# 碎甲者
	almost(ScrapperEnemy.MISS_STUN_TIME, float(tg[&"scrapper"]["punish"]), 0.0001, "scrapper miss stun")
	var scrapper := ScrapperEnemy.new()
	almost(scrapper.windup_time, float(tg[&"scrapper"]["time"]), 0.0001, "scrapper windup")
	scrapper.free()
	# 骸骨
	almost(SkeletonEnemy.BITE_WINDUP, float(tg[&"skeleton"]["time"]), 0.0001, "skeleton lean")
	almost(SkeletonEnemy.BITE_RECOVERY, float(tg[&"skeleton"]["punish"]), 0.0001, "skeleton open mouth")
	# 幽魂
	almost(GhostEnemy.ATTACK_WINDUP, float(tg[&"ghost"]["time"]), 0.0001, "ghost wail ring")
	almost(GhostEnemy.ATTACK_RECOVERY, float(tg[&"ghost"]["punish"]), 0.0001, "ghost freeze")
	# 火骷髅
	almost(FireSkullEnemy.FLARE_TIME, float(tg[&"fire_skull"]["time"]), 0.0001, "skull flare")
	almost(FireSkullEnemy.RETREAT_PAUSE, float(tg[&"fire_skull"]["punish"]), 0.0001, "skull pause")
	# 飞行恶魔
	almost(FlyingDemonEnemy.ATTACK_WINDUP, float(tg[&"flying_demon"]["time"]), 0.0001, "demon flap")
	almost(FlyingDemonEnemy.RECOVERY_TIME, float(tg[&"flying_demon"]["punish"]), 0.0001, "demon hover")
	# 齿轮盾卫
	var guard := GearShieldEnemy.new()
	almost(guard.charge_time, float(tg[&"gear_shield"]["time"]), 0.0001, "guard arm raise")
	almost(guard.stagger_time, float(tg[&"gear_shield"]["punish"]), 0.0001, "guard shield break")
	guard.free()
	# 刽子手
	almost(ExecutionerBoss.SLASH_WINDUP, float(tg[&"executioner"]["time"]), 0.0001, "executioner axe zone")
	almost(ExecutionerBoss.SLASH_RECOVERY, float(tg[&"executioner"]["punish"]), 0.0001, "executioner recovery")
	# 梦魇（一阶段；二阶段的收紧值由 CombatRules 单独给出）
	var nightmare_script := load("res://scripts/enemies/nightmare_boss.gd") as Script
	var nightmare := nightmare_script.new() as Node
	almost(float(nightmare.get("windup_time")), float(tg[&"nightmare"]["time"]), 0.0001, "nightmare windup")
	almost(float(nightmare.get("rest_time")), float(tg[&"nightmare"]["punish"]), 0.0001, "nightmare rest")
	nightmare.free()
	almost(CombatRules.NIGHTMARE_P2_WINDUP, 0.58, 0.0001)
	almost(CombatRules.NIGHTMARE_P2_REST, 0.90, 0.0001)
	ok(CombatRules.NIGHTMARE_P2_WINDUP >= CombatRules.TELEGRAPH_MIN, "even the tightened windup stays readable")
	ok(CombatRules.NIGHTMARE_P2_SPEED_K > 1.0, "phase two charges harder")
	almost(CombatRules.EXECUTIONER_P2_FOLLOWUP, 0.55, 0.0001)
	# 表本身：每个暗号够长、每个破绽都真的留得出来。
	for kind in tg:
		ok(float(tg[kind]["time"]) >= CombatRules.TELEGRAPH_MIN, "%s telegraph >= 0.25 s" % kind)
		ok(float(tg[kind]["punish"]) > 0.0, "%s leaves a punish window" % kind)
		ok(StringName(tg[kind]["signature"]) != &"", "%s has a named signature" % kind)
