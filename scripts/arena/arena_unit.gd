extends CharacterBody2D
## 竞技场单位基类。不进 group "player" / "enemies"。队伍色在 self_modulate 上。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const BoltScript := preload("res://scripts/arena/arena_bolt.gd")
const GlyphScript := preload("res://scripts/arena/arena_glyph.gd")

var team: String = "enemy"
var unit_kind: String = "minion"
var role: String = "melee"
var unit_id: String = ""
var unit_label: String = ""
var skin_id: String = ""
var facing: float = 1.0
var slot: int = 0
var structure_index: int = -1
var attack_range: float = 28.0
var attack_damage: int = 1
var attack_cooldown: float = 0.8
var move_speed: float = 40.0
var sight_range: float = 140.0
var xp_bounty: int = 4
var ember_bounty: int = 2
var siege_bonus: int = 0
var level: int = 1
var alive: bool = true
var ranged: bool = false
var engage_range: float = 130.0

var health: Health
var hurtbox: Hurtbox
var _cfg: Dictionary = {}
var _immobile := false
var _wish_x := 0.0
var _cd := 0.0
var _react := 0.0
var _skill_cd := 2.0
var _think := 0.0
var _retreating := false
var _heal_acc := 0.0
var _flash := 0.0
var _last_hp := 1
var _last_attacker: Node = null
var _mirroring := false
var _visual: Node2D
var _sprite: CanvasItem
var _base_tint := Color.WHITE
var _bolt: Node = null
var _home := Vector2.ZERO
var _has_home := false
var use_sense := false
var sense_override: Array = []
var _z := 0.0
var _depth_goal := 0.0
var _depth_goal_on := false


func configure(cfg: Dictionary) -> void:
	_cfg = cfg.duplicate(true)
	if is_node_ready():
		_apply_config()


func set_sense(rows: Array) -> void:
	use_sense = true
	sense_override = rows


func set_skill_ready(on: bool) -> void:
	_skill_cd = 0.0 if on else 99.0


func arena_depth() -> float:
	return global_position.y


func arena_z() -> float:
	return _z


func arena_spans_depth() -> bool:
	return unit_kind == "tower" or unit_kind == "crystal"


func move_toward_depth(goal: float) -> void:
	_depth_goal = ArenaCatalog.clamp_depth(goal)
	_depth_goal_on = true


func minimap_entry() -> Dictionary:
	return {
		"id": unit_id,
		"team": team,
		"kind": unit_kind,
		"role": role,
		"x": global_position.x,
		"y": global_position.y,
		"depth": arena_depth(),
		"spans": arena_spans_depth(),
		"alive": alive,
		"label": unit_label,
	}


func hp_ratio() -> float:
	if health == null or health.max_hp <= 0:
		return 1.0
	return clampf(float(health.current) / float(health.max_hp), 0.0, 1.0)


func is_pressing_hero() -> bool:
	return alive and (_state_name() == "fight" or _state_name() == "skill")


func decide_state() -> String:
	return "push"


func goal_x() -> float:
	return global_position.x


func _state_name() -> String:
	return "push"


func _ready() -> void:
	add_to_group("arena_unit")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 0
	collision_mask = 0
	floor_snap_length = 0.0
	floor_constant_speed = true
	_build_combat()
	_apply_config()
	_build_visual()
	_last_hp = health.current if health != null else 1


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if ArenaRun.allows_combat():
		combat_tick(delta)
	else:
		_wish_x = 0.0
	if _immobile:
		velocity = Vector2.ZERO
	else:
		_apply_motion(delta)
		_fountain_heal(delta)
	_decay_flash(delta)


func combat_tick(_delta: float) -> void:
	if unit_kind == "elite":
		_tick_elite(_delta)


func _build_combat() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 20)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)
	health = Health.new()
	health.name = "Health"
	health.quiet = true
	add_child(health)
	health.changed.connect(_on_hp)
	health.died.connect(_on_died)
	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	var hb_shape := CollisionShape2D.new()
	var hb_rect := RectangleShape2D.new()
	hb_rect.size = Vector2(14, 20)
	hb_shape.shape = hb_rect
	hb_shape.position = Vector2(0, -12)
	hurtbox.add_child(hb_shape)
	add_child(hurtbox)
	hurtbox.block_check = Callable(self, "_block_hit")
	hurtbox.hurt.connect(_on_hurt)


func _apply_config() -> void:
	if _cfg.is_empty():
		_apply_role_stats()
		_paint_team()
		return
	team = String(_cfg.get("team", team))
	unit_id = String(_cfg.get("id", unit_id))
	unit_label = String(_cfg.get("label", unit_label))
	unit_kind = String(_cfg.get("kind", unit_kind))
	role = String(_cfg.get("role", role))
	skin_id = String(_cfg.get("skin", skin_id))
	facing = float(_cfg.get("dir", facing))
	slot = int(_cfg.get("slot", slot))
	structure_index = int(_cfg.get("index", structure_index))
	ranged = bool(_cfg.get("ranged", ranged))
	var pos_v: Variant = _cfg.get("pos", null)
	if pos_v is Vector2:
		position = pos_v as Vector2
	_depth_goal = position.y
	_depth_goal_on = true
	if unit_id != "":
		set_name("U_" + unit_id)
	if unit_kind == "elite" or unit_kind == "tower" or unit_kind == "crystal":
		_immobile = true
	_home = position
	_has_home = true
	_apply_role_stats()
	_fit_hurtbox()
	_paint_team()
	if unit_id != "":
		ArenaRun.register_combatant({
			"id": unit_id,
			"team": team,
			"kind": unit_kind,
			"label": unit_label if unit_label != "" else unit_id,
			"is_player": false,
		})


func _apply_role_stats() -> void:
	var stat_role := role
	if unit_kind == "hero":
		stat_role = "hero"
	elif unit_kind == "tower":
		stat_role = "tower"
	elif unit_kind == "crystal":
		stat_role = "crystal"
	elif unit_kind == "elite":
		stat_role = "elite"
	var stat := ArenaCatalog.unit_stat(stat_role)
	var hp := int(stat.get("hp", 4))
	if unit_kind == "minion":
		hp = ArenaCatalog.scaled_max_hp(hp, "minion", ArenaRun.difficulty_id())
	if unit_kind == "hero":
		hp = ArenaCatalog.hero_hp(level)
	attack_damage = int(stat.get("dmg", 1))
	if unit_kind == "hero":
		attack_damage = ArenaCatalog.hero_damage(level)
	if unit_kind == "minion":
		var grown := ArenaCatalog.wave_power(int(_cfg.get("wave", 1)))
		hp = maxi(1, int(round(float(hp) * grown)))
		attack_damage = maxi(1, int(round(float(attack_damage) * grown)))
	attack_range = float(stat.get("range", attack_range))
	if ranged and unit_kind == "hero":
		attack_range = 132.0
	attack_cooldown = float(stat.get("cd", attack_cooldown))
	attack_cooldown *= ArenaCatalog.cooldown_scale(unit_kind, ArenaRun.difficulty_id())
	move_speed = float(stat.get("speed", move_speed))
	sight_range = float(stat.get("sight", sight_range))
	xp_bounty = int(stat.get("xp", xp_bounty))
	ember_bounty = int(stat.get("ember", ember_bounty))
	siege_bonus = int(stat.get("siege", siege_bonus))
	if unit_kind == "minion":
		var grown_siege := ArenaCatalog.wave_power(int(_cfg.get("wave", 1)))
		siege_bonus = int(round(float(siege_bonus) * grown_siege))
	if health != null:
		health.max_hp = maxi(1, hp)
		health.heal_full()
		health.quiet = true
		_last_hp = health.current
	if hurtbox != null:
		hurtbox.team = StringName(team)
	if facing < 0.0:
		_face_sign(-1.0)
	else:
		_face_sign(1.0)


func refresh_combat_stats() -> void:
	if not alive:
		return
	_apply_role_stats()


func apply_growth(new_level: int) -> void:
	level = clampi(new_level, 1, ArenaCatalog.MAX_LEVEL)
	if unit_kind != "hero" or health == null:
		return
	var hp := ArenaCatalog.hero_hp(level)
	var before := health.max_hp
	health.set_max_hp(hp)
	if hp > before and health.current > 0:
		health.heal(hp - before)
	attack_damage = ArenaCatalog.hero_damage(level)


func mirror_hp(hp: int) -> void:
	if health == null:
		return
	_mirroring = true
	if hp <= 0:
		if health.current > 0:
			health.take_damage(health.current + 8, null)
	else:
		var delta := hp - health.current
		if delta > 0:
			health.heal(delta)
		elif delta < 0:
			health.take_damage(-delta, null)
	_mirroring = false


func outgoing_damage(target: Node) -> int:
	var dmg := ArenaCatalog.scaled_damage(attack_damage, unit_kind, ArenaRun.difficulty_id())
	# 1.3 倍在 1 点伤害上会四舍五入回 1。祝福至少再加 1，整队都打得出来。
	if ArenaRun.blessing_time_left(team) > 0.0:
		var boosted := int(round(float(dmg) * ArenaCatalog.BLESSING_DAMAGE))
		dmg = maxi(dmg + 1, boosted)
	if _is_structure(target):
		dmg += siege_bonus
	if unit_kind == "tower" and target != null and _kind_of(target) == "minion":
		dmg = maxi(1, dmg - 1)
	return maxi(1, dmg)


func strike_at(world_point: Vector2, target: Node = null) -> void:
	if not alive:
		return
	if target != null and not ArenaCatalog.depths_touch(self, target, "melee"):
		_cd = _swing_cooldown()
		return
	var dmg := outgoing_damage(target)
	var box := Hitbox.new()
	box.team = StringName(team)
	box.damage = dmg
	box.knockback = Vector2(facing * 70.0, -18.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18, 16)
	shape.shape = rect
	box.add_child(shape)
	add_child(box)
	box.global_position = world_point
	box.force_update_transform()
	var box_shape := box.get_node_or_null("CollisionShape2D") as Node2D
	if box_shape != null:
		box_shape.force_update_transform()
	box.arm(box.knockback)
	if target != null:
		var aimed := target.get_node_or_null("Hurtbox") as Hurtbox
		if aimed != null:
			aimed._on_area_entered(box)
	box.sweep_now()
	_cd = _swing_cooldown()
	var tw := box.create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(box.queue_free)


func launch_bolt(dir: float, target: Node = null) -> void:
	if _bolt != null and is_instance_valid(_bolt):
		return
	var host := get_parent()
	if host == null:
		return
	var bolt: Node = BoltScript.new()
	host.add_child(bolt)
	bolt.call("setup", self, dir, outgoing_damage(target), target)
	_bolt = bolt
	_cd = _swing_cooldown()


func _tick_elite(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_react = maxf(0.0, _react - delta)
	var foe := _nearest_where(true, 0.0, true)
	if foe == null:
		foe = _nearest_where(false, 36.0, false)
	if foe == null or _cd > 0.0 or _react > 0.0:
		return
	_face_toward(_node_x(foe))
	if ranged:
		launch_bolt(facing, foe)
	else:
		strike_at(foe.global_position + Vector2(0, -12), foe)


func _apply_motion(delta: float) -> void:
	velocity.x = move_toward(velocity.x, _wish_x, 700.0 * delta)
	velocity.y = 0.0
	position.x += velocity.x * delta
	if _depth_goal_on:
		var rate := maxf(28.0, move_speed * 0.95)
		if unit_kind == "hero":
			rate = maxf(rate, 86.0)
		position.y = move_toward(position.y, _depth_goal, rate * delta)
	_clamp_arena_body()
	_apply_z_visual()
	_paint_team()


func _clamp_arena_body() -> void:
	var host := get_parent()
	var in_world := host != null and host.is_in_group("game_world")
	if in_world or ArenaRun.active():
		global_position.y = ArenaCatalog.clamp_depth(global_position.y)
	if in_world:
		global_position.x = clampf(global_position.x, 18.0, ArenaCatalog.LANE_RIGHT - 18.0)


func _apply_z_visual() -> void:
	if _visual != null:
		_visual.position.y = -_z
	if hurtbox != null and not arena_spans_depth():
		hurtbox.position.y = -_z


func move_toward_x(goal: float, stop_dist: float) -> void:
	var dx := goal - global_position.x
	if absf(dx) <= stop_dist:
		_wish_x = 0.0
		return
	_face_sign(signf(dx))
	_wish_x = facing * move_speed


func _fountain_heal(delta: float) -> void:
	if health == null or team == ArenaCatalog.TEAM_NEUTRAL:
		return
	var well := ArenaCatalog.fountain_for(team)
	if not ArenaCatalog.near_fountain(global_position, well):
		return
	_heal_acc += ArenaCatalog.FOUNTAIN_HEAL * delta
	var n := int(_heal_acc)
	if n > 0:
		_heal_acc -= float(n)
		health.heal(n)


func _face_toward(x: float) -> void:
	var dx := x - global_position.x
	if absf(dx) > 1.5:
		_face_sign(signf(dx))


func _face_sign(sign: float) -> void:
	facing = -1.0 if sign < 0.0 else 1.0
	if _visual != null:
		_visual.scale = Vector2(facing, 1.0)


func _block_hit(_attacker: Node, _amount: int) -> bool:
	return not ArenaRun.allows_combat()


func _on_hurt(_amount: int, attacker: Node) -> void:
	_last_attacker = attacker


func _on_hp(cur: int, _mx: int) -> void:
	if cur < _last_hp:
		_flash = 0.1
		if not _mirroring:
			ArenaRun.note_tag(unit_id, ArenaRun.attacker_id(_last_attacker))
	_last_hp = cur
	queue_redraw()
	if structure_index >= 0 and not _mirroring:
		ArenaRun.note_structure_state(team, structure_index, cur, ArenaRun.attacker_id(_last_attacker))


func _on_died() -> void:
	if not alive and structure_index < 0:
		return
	alive = false
	_wish_x = 0.0
	if hurtbox != null:
		hurtbox.set_deferred("monitorable", false)
	if structure_index >= 0:
		return
	ArenaRun.report_death({
		"killer_id": ArenaRun.attacker_id(_last_attacker),
		"victim_id": unit_id,
		"victim_team": team,
		"victim_kind": unit_kind,
		"victim_label": unit_label,
		"xp": xp_bounty,
		"ember": ember_bounty,
	})
	if unit_kind == "hero" or unit_kind == "elite":
		visible = false
		return
	queue_free()


func reset_for_match() -> void:
	var at := global_position
	if _has_home:
		at = _home
	arena_revive(at)


func arena_revive(at: Vector2) -> void:
	for child in get_children():
		if child is Hitbox:
			child.queue_free()
	_bolt = null
	global_position = at
	velocity = Vector2.ZERO
	_z = 0.0
	_depth_goal = at.y
	_depth_goal_on = true
	_apply_z_visual()
	alive = true
	visible = true
	_retreating = false
	_cd = 0.35
	if health != null:
		health.heal_full()
		health.grant_iframes(0.7)
		_last_hp = health.current
	if hurtbox != null:
		hurtbox.monitorable = true
		hurtbox.team = StringName(team)
	if unit_kind == "hero":
		apply_growth(ArenaRun.level_of(unit_id))
	queue_redraw()


func _nearest_of_kind(kind_name: String, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for node in _hostiles():
		if node == null or not is_instance_valid(node):
			continue
		if _kind_of(node) != kind_name:
			continue
		if kind_name != "elite" and _team_of(node) == ArenaCatalog.TEAM_NEUTRAL:
			continue
		var d := absf(node.global_position.x - global_position.x)
		if absf(ArenaCatalog.node_depth(node) - arena_depth()) > ArenaCatalog.depth_span():
			continue
		if d < best_d:
			best_d = d
			best = node
	return best


func _nearest_where(heroes_only: bool, extra: float, skip_minions: bool) -> Node2D:
	var best: Node2D = null
	var best_d := sight_range + extra
	for node in _hostiles():
		if node == null or not is_instance_valid(node):
			continue
		var kind := _kind_of(node)
		if kind == "tower" or kind == "crystal":
			continue
		if heroes_only and kind != "hero" and not node.is_in_group("player"):
			continue
		if skip_minions and kind == "minion":
			continue
		if unit_kind == "minion" and (kind == "elite" or _team_of(node) == ArenaCatalog.TEAM_NEUTRAL):
			continue
		var d := absf(node.global_position.x - global_position.x)
		if absf(ArenaCatalog.node_depth(node) - arena_depth()) > ArenaCatalog.depth_span():
			continue
		if d < best_d:
			best_d = d
			best = node
	return best


func _nearest_structure() -> Node2D:
	var best: Node2D = null
	var best_d := attack_range + 8.0
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node):
			continue
		var idx := int(node.get("structure_index"))
		if idx < 0:
			continue
		if not bool(node.get("alive")):
			continue
		var other := String(node.get("team"))
		if not ArenaCatalog.hostile(team, other):
			continue
		if not ArenaRun.structure_vulnerable(other, idx):
			continue
		var body := node as Node2D
		if body == null:
			continue
		var d := absf(body.global_position.x - global_position.x)
		if d < best_d:
			best_d = d
			best = body
	return best


func _hostiles() -> Array:
	var out: Array = []
	if use_sense:
		return out
	var tree := get_tree()
	if tree == null:
		return out
	for node in tree.get_nodes_in_group("arena_unit"):
		if node == self or not is_instance_valid(node):
			continue
		if not bool(node.get("alive")):
			continue
		var other := String(node.get("team"))
		if not ArenaCatalog.hostile(team, other):
			continue
		out.append(node)
	if ArenaCatalog.hostile(team, ArenaCatalog.TEAM_PLAYER):
		for node in tree.get_nodes_in_group("player"):
			if node is Player:
				var knight := node as Player
				if knight.health != null and knight.health.current > 0:
					out.append(knight)
	return out


func _enemy_hero_near() -> bool:
	if use_sense:
		for raw in sense_override:
			if raw is Dictionary:
				var row: Dictionary = raw
				var kind := String(row.get("kind", ""))
				var other := String(row.get("team", ""))
				var dist := float(row.get("dist", 9999.0))
				if kind == "hero" and ArenaCatalog.hostile(team, other) and dist <= engage_range:
					return true
		return false
	var foe := _nearest_where(true, engage_range - sight_range, true)
	return foe != null and absf(foe.global_position.x - global_position.x) <= engage_range


func _kind_of(node: Node) -> String:
	if node.is_in_group("player"):
		return "hero"
	if "unit_kind" in node:
		return String(node.get("unit_kind"))
	return ""


func _team_of(node: Node) -> String:
	if node.is_in_group("player"):
		return ArenaCatalog.TEAM_PLAYER
	if "team" in node:
		return String(node.get("team"))
	return ""


func _node_x(node: Node2D) -> float:
	return node.global_position.x


func _is_structure(target: Node) -> bool:
	if target == null or not ("unit_kind" in target):
		return false
	var kind := String(target.get("unit_kind"))
	return kind == "tower" or kind == "crystal"


func _fit_hurtbox() -> void:
	if hurtbox == null:
		return
	var shape_node := hurtbox.get_child(0) as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return
	var rect := shape_node.shape as RectangleShape2D
	if rect == null:
		return
	if arena_spans_depth():
		rect.size = Vector2(26, 190)
		shape_node.position = Vector2(0, -57)
	else:
		rect.size = Vector2(14, 20)
		shape_node.position = Vector2(0, -12)


func _build_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "Visual"
	_visual.z_index = 0
	add_child(_visual)
	z_index = 0
	if unit_kind == "tower":
		_build_tower_visual()
	elif unit_kind == "crystal":
		_build_crystal_visual()
	elif unit_kind == "hero":
		_build_hero_visual()
	elif unit_kind == "elite":
		_build_glyph()
	else:
		_build_minion_visual()
	_paint_team()
	_face_sign(facing)


func _build_tower_visual() -> void:
	_build_glyph()


func _build_glyph() -> void:
	var glyph: Node2D = GlyphScript.new()
	glyph.name = "Glyph"
	_visual.add_child(glyph)
	glyph.call("bind", self)
	_sprite = glyph


func _build_hero_visual() -> void:
	var skin := StringName(skin_id) if skin_id != "" else SkinCatalog.DEFAULT_SKIN
	var anim := FrameAnimSprite.new()
	anim.name = "Body"
	var idle := SkinCatalog.frames_for(skin, &"idle")
	var run := SkinCatalog.frames_for(skin, &"run")
	if not idle.is_empty():
		anim.register("idle", idle, 10.0, true, SkinCatalog.offset_for(skin, &"idle"))
	if not run.is_empty():
		anim.register("run", run, 12.0, true, SkinCatalog.offset_for(skin, &"run"))
	if anim.has_anim("idle"):
		anim.play("idle")
		_visual.add_child(anim)
		_sprite = anim
		_base_tint = SkinCatalog.tint_of(skin)
		anim.modulate = _base_tint
	else:
		_build_block_visual(Vector2(14, 26), Color(0.8, 0.8, 0.85))
	var sword := Greatsword.new()
	_visual.add_child(sword)
	sword.show_carried()


func _build_minion_visual() -> void:
	var spec: Dictionary = {}
	var raw_spec: Variant = ArenaCatalog.MINION_VISUAL.get(role, {})
	if raw_spec is Dictionary:
		spec = raw_spec
	var char_name := String(spec.get("char", ""))
	var action := String(spec.get("action", "idle"))
	var frames := CharFrames.anim(char_name, action)
	if frames.is_empty():
		_build_block_visual(Vector2(12, 16), Color(0.7, 0.7, 0.7))
		return
	var anim := FrameAnimSprite.new()
	anim.name = "Body"
	var pos_v: Variant = spec.get("pos", Vector2(0, -12))
	var pos := Vector2(0, -12)
	if pos_v is Vector2:
		pos = pos_v as Vector2
	anim.register("walk", frames, float(spec.get("fps", 10.0)), true, pos)
	anim.play("walk")
	var sc := float(spec.get("scale", 1.0))
	anim.scale = Vector2(sc, sc)
	_visual.add_child(anim)
	_sprite = anim


func _build_crystal_visual() -> void:
	_build_glyph()


func _build_block_visual(size: Vector2, color: Color) -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y),
		Vector2(size.x * 0.5, -size.y),
		Vector2(size.x * 0.5, 0),
		Vector2(-size.x * 0.5, 0),
	])
	body.color = color
	_visual.add_child(body)
	_sprite = body


func _paint_team() -> void:
	if _visual == null:
		return
	var tint := Color.WHITE
	if ArenaCatalog.TEAM_TINT.has(team):
		tint = ArenaCatalog.TEAM_TINT[team]
	if unit_kind == "tower" or unit_kind == "crystal" or unit_kind == "elite":
		_visual.self_modulate = Color.WHITE
	else:
		_visual.self_modulate = tint
	var t := 0.5
	if ArenaCatalog.depth_span() > 1.0:
		t = clampf((global_position.y - ArenaCatalog.DEPTH_BACK) / ArenaCatalog.depth_span(), 0.0, 1.0)
	_visual.modulate = Color(lerpf(0.56, 1.14, t), lerpf(0.64, 1.02, t), lerpf(0.96, 0.8, t))


func _decay_flash(delta: float) -> void:
	if _flash <= 0.0 or _sprite == null:
		return
	_flash = maxf(0.0, _flash - delta)
	if _flash > 0.0:
		_sprite.modulate = Color(1.7, 1.7, 1.65)
	else:
		_sprite.modulate = _base_tint


func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 10
	for i in steps:
		var ang := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, color)


func _draw() -> void:
	if not alive:
		return
	var shadow: Dictionary = ArenaCatalog.shadow_metrics(_z)
	var shade := minf(0.86, float(shadow["alpha"]) * 1.6)
	_draw_ellipse(Vector2(0, 2), float(shadow["rx"]) * 1.35, float(shadow["ry"]) * 1.25, Color(0.01, 0.005, 0.01, shade * 0.55))
	_draw_ellipse(Vector2(0, 1), float(shadow["rx"]), float(shadow["ry"]), Color(0.01, 0.004, 0.008, shade))
	if health == null:
		return
	var w := 18.0
	var y := -30.0
	if unit_kind == "tower":
		w = 26.0
		y = -142.0
	elif unit_kind == "crystal":
		w = 24.0
		y = -72.0
	elif unit_kind == "minion":
		y = -22.0
	var k := 0.0
	if health.max_hp > 0:
		k = clampf(float(health.current) / float(health.max_hp), 0.0, 1.0)
	draw_rect(Rect2(-w * 0.5, y, w, 2), Color(0.06, 0.04, 0.05))
	var fill := Color(0.95, 0.38, 0.3)
	if team == ArenaCatalog.TEAM_PLAYER:
		fill = Color(0.45, 0.75, 1.0)
	elif team == ArenaCatalog.TEAM_NEUTRAL:
		fill = Color(1.0, 0.82, 0.35)
	draw_rect(Rect2(-w * 0.5, y, w * k, 2), fill)


func _swing_cooldown() -> float:
	var cd := attack_cooldown
	if unit_kind != "minion":
		return cd
	var board: Dictionary = ArenaRun.scoreboard()
	if float(board.get("elapsed", 0.0)) >= ArenaCatalog.UNREST_AT:
		cd *= ArenaCatalog.UNREST_CD
	return cd


func _react_delay() -> float:
	var diff := ArenaCatalog.difficulty_def(ArenaRun.difficulty_id())
	return float(diff.get("react", 0.2))


func _think_gap() -> float:
	var diff := ArenaCatalog.difficulty_def(ArenaRun.difficulty_id())
	return float(diff.get("think", 0.22))
