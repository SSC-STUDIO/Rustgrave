extends TestCase
## 1D 刽子手演出（UPGRADE_PLAN「1D Boss 演出」）：
##   · 2× 整数画幅、脚点仍在地面、碰撞 / 受击盒与画幅同步；
##   · 背光 + 接地阴影存在且加法亮度有上限；
##   · 跨门宣布只发一次 boss_intro_started / boss_appeared，名号卡不锁输入；
##   · 竞技场两座锻炉火膛 + 中央暖池给 Boss 打光，二阶段转炽红；
##   · 进场剧本可跳过并交还镜头 / 输入；倒地后舞台灯熄灭、残芯解锁；
##   · 演出的灯 / 相变从不自己开剧本、从不锁输入。

const BOSS_SCENE := preload("res://scenes/enemies/ExecutionerBoss.tscn")


func setup() -> void:
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	StoryStage.forget()
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	Engine.time_scale = 1.0
	var presentation := Director.get_node_or_null("CinematicPresentation")
	if presentation != null:
		presentation.dismiss(true)


func teardown() -> void:
	Director.abort()
	Director.resume()
	Director.choice_hold = false
	if get_tree().paused:
		get_tree().paused = false
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	StoryStage.forget()
	Engine.time_scale = 1.0
	var presentation := Director.get_node_or_null("CinematicPresentation")
	if presentation != null:
		presentation.dismiss(true)


## 东翼给火膛按 x 坐标起名（ArenaHearth1790 之类），测试照样从常量取。
func _hearth_name(x: float) -> String:
	return "ArenaHearth%d" % int(x)


func _spawn_boss(arena: Node2D) -> ExecutionerBoss:
	var boss := BOSS_SCENE.instantiate() as ExecutionerBoss
	boss.position = Vector2(320, 0)
	arena.add_child(boss)
	await flush(2)
	return boss


## level01_layout_test._make_host 的同款最小宿主（东翼要求 Platforms/Hooks/Pickups/Props）。
func _make_host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	for folder in ["Platforms", "Hooks", "Pickups", "Props"]:
		var node := Node2D.new()
		node.name = folder
		host.add_child(node)
	var wall := Node2D.new()
	wall.name = "WallRight"
	host.get_node("Platforms").add_child(wall)
	return host


## 建一座真实东翼：返回 [host, wing, boss]。
func _build_arena() -> Array:
	var host := _make_host()
	var wing := Level01EastWing.new()
	add_child(wing)
	var boss := wing.build(host)
	await flush(2)
	return [host, wing, boss]


# --- 1. 可读性：画幅 / 脚点 / 碰撞盒 / 背光 --------------------------------------

func test_boss_silhouette_is_integer_double_scale_pinned_to_the_floor() -> void:
	eq(ExecutionerBoss.BOSS_SCALE, 2, "boss art uses an integer 2x scale (art-spec)")
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn_boss(arena)
	var anim := boss.get_node_or_null("Visual/BodySprite") as FrameAnimSprite
	ok(anim != null, "the boss wears the executioner frame animation")
	if anim != null:
		eq(anim.scale, Vector2(2, 2), "silhouette is drawn at 2x, not stretched")
		ok(anim.scale.x == floorf(anim.scale.x) and anim.scale.y == floorf(anim.scale.y),
				"no fractional pixel scale")
		almost(boss.drawn_feet_offset(), 0.0, 1.0, "drawn feet sit on the node origin (floor y)")
		ok(anim.flip_h, "the frame keeps its authored left-facing flip contract")
	# 碰撞 / 受击盒跟着画幅放大，但脚点仍在 y=0 —— 判定关系不变。
	var body := boss.get_node("CollisionShape2D") as CollisionShape2D
	var body_rect := body.shape as RectangleShape2D
	eq(body_rect.size, ExecutionerBoss.BOSS_BODY_SIZE)
	almost(body.position.y + body_rect.size.y * 0.5, 0.0, 0.01, "body feet stay on y=0")
	var hurt := boss.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	var hurt_rect := hurt.shape as RectangleShape2D
	eq(hurt_rect.size, ExecutionerBoss.BOSS_HURT_SIZE)
	almost(boss.hurtbox.position.y + hurt_rect.size.y * 0.5, 0.0, 0.01, "hurtbox feet stay on y=0")
	almost(boss.body_clearance().y, ExecutionerBoss.BOSS_BODY_SIZE.y, 0.01)
	ok(boss.body_clearance().x > GearShieldEnemy.BODY_SIZE.x * 0.5,
			"the wider cloak pushes the knight out further, matching the silhouette")
	arena.queue_free()
	await flush(2)


## Lead 复核点：2× 是唯一的放大幅度，且判定 / 落点框必须跟着画幅走，
## 不能出现「看得见的斧」和「打得中的盒」两套尺寸。
func test_slash_zone_and_hitbox_scale_with_the_drawn_axe() -> void:
	eq(ExecutionerBoss.SLASH_ZONE_OFFSET,
			Vector2(22.0 * ExecutionerBoss.BOSS_SCALE, -18.0),
			"zone offset reaches the 2x axe's landing spot")
	eq(ExecutionerBoss.SLASH_ZONE_SIZE,
			Vector2(36.0 * ExecutionerBoss.BOSS_SCALE, 28.0),
			"zone width follows the drawn axe, height stays the knight's body band")
	# 贴地：底边落在台面上方 4px（和 1× 时同一贴地约定）。
	almost(ExecutionerBoss.SLASH_ZONE_OFFSET.y + ExecutionerBoss.SLASH_ZONE_SIZE.y * 0.5,
			-4.0, 0.01, "the landing zone still hugs the floor line")
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn_boss(arena)
	boss.set_physics_process(false)
	boss._shield_facing = 1
	boss._begin_slash()
	boss._tick_charge(0.53)  # 前摇走完，斧已落地
	ok(boss._slash_box != null and boss._slash_box.monitoring, "the axe hitbox is live")
	if boss._slash_box != null:
		var shape := (boss._slash_box.get_child(0) as CollisionShape2D).shape as RectangleShape2D
		eq(shape.size, ExecutionerBoss.SLASH_ZONE_SIZE, "hitbox is exactly the drawn landing zone")
		var center := boss._slash_box.global_position - boss.global_position
		almost(center.x, ExecutionerBoss.SLASH_ZONE_OFFSET.x, 0.01)
		almost(center.y, ExecutionerBoss.SLASH_ZONE_OFFSET.y, 0.01)
	arena.queue_free()
	await flush(2)


## Lead 复核点：Boss 的暗帧必须抬进可读区间（有内部层次），但白闪收尾仍回到
## 这个「可读暗色」而不是洗成纯白；二阶段再往炉火色偏。
func test_boss_body_lift_keeps_internal_detail_and_never_flashes_to_white() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn_boss(arena)
	var visual := boss.get_node("Visual") as CanvasItem
	eq(visual.modulate, ExecutionerBoss.BODY_LIFT, "the dark frame is lifted into a readable range")
	ok(visual.modulate.r > 1.0 and visual.modulate.g > 1.0,
			"lift is a positive modulate, so internal highlights multiply up")
	ok(visual.modulate.r < 3.0, "lift stays below clipping")
	eq(boss._flash_restore_color(), ExecutionerBoss.BODY_LIFT,
			"hit flash restores the readable dark tone, not pure white")
	boss.health.take_damage(7, null)
	ok(boss.is_enraged())
	await flush(2)
	eq(boss._flash_restore_color(), ExecutionerBoss.BODY_LIFT_HOT,
			"phase two restores a hotter body tone")
	arena.queue_free()
	await flush(2)


func test_boss_presence_carries_a_capped_backlight_and_a_contact_shadow() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn_boss(arena)
	var presence := boss.get_node_or_null("BossPresence") as Node2D
	ok(presence != null, "boss carries a presentation rig")
	var back := presence.get_node_or_null("Backlight") as Sprite2D if presence != null else null
	ok(back != null, "the silhouette is backlit by an additive halo")
	if back != null:
		ok(back.z_index < 0, "backlight sits behind the body (cannot wash the silhouette)")
		ok(back.material is CanvasItemMaterial, "backlight is additive")
		ok(back.texture != null)
	var shadow := presence.get_node_or_null("ContactShadow") as Node2D if presence != null else null
	ok(shadow != null, "feet get a ground-contact shadow")
	# Lead 复核点：身后暖背光 + 正面冷补光，暗袍子才读得出兜帽 / 甲片层次。
	var cool := presence.get_node_or_null("PresenceCool") as PointLight2D if presence != null else null
	ok(cool != null and cool.enabled and cool.energy > 0.0,
			"a cool front fill survives on the body, not just a warm rim")
	var fill := presence.get_node_or_null("PresenceFill") as PointLight2D if presence != null else null
	ok(fill != null and fill.enabled and fill.energy > 0.0, "the warm underfill is lit too")
	ok(boss.presence_alpha() > 0.0, "the arena boss is visibly backlit while he stands guard")
	ok(boss.presence_alpha() <= 0.46 + 0.001, "additive halo stays under the occlusion cap")
	ok(not boss.presence_hot(), "phase one backlight is the warm forge tone")
	arena.queue_free()
	await flush(2)


# --- 2. 进场：两个事件各一次、名号卡不抢输入 -------------------------------------

## StoryStage 用 `boss_name.contains("刽子手")` 判断「第一章的拱门入场自己演」。
## 旧标题带着字间空格（"炉 约 刽 子 手"），匹配不上，于是通用 Boss 登场会叠在
## 拱门入场前面变成两段连播。标题不带空格之后，第一章只跑 on_boss_gate 这一段。
func test_boss_title_is_recognised_as_scripted_elsewhere() -> void:
	var title := String(ExecutionerBoss.BOSS_TITLE)
	ok(title.contains("刽子手"), "chapter 1's title matches StoryStage.BOSS_SCRIPTED_ELSEWHERE")
	ok(StoryStage.BOSS_SCRIPTED_ELSEWHERE.has("刽子手"), "the tag contract is still in StoryStage")
	# 名号卡显示不受影响：CinematicPresentation 会把 "·" 前的内容压成标题。
	var parts := title.split("·", false, 1)
	eq(String(parts[0]).replace(" ", ""), "炉约刽子手", "the nameplate still reads 炉约刽子手")
	eq(String(parts[1]).strip_edges(), "铸渣残躯", "the subtitle survives the split")


## 守芯者站在拱门后的灯下，不在门前踱步：不靠近就不该移动位置。
func test_boss_holds_his_post_between_the_hearths() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := BOSS_SCENE.instantiate() as ExecutionerBoss
	boss.position = Vector2(Level01EastWing.ARENA_CENTER_X, 0)
	arena.add_child(boss)
	await flush(4)
	var start := boss.global_position
	for _i in 60:
		await get_tree().physics_frame
	almost(boss.global_position.x, start.x, 0.5, "the executioner does not wander off his post")
	arena.queue_free()
	await flush(2)


func test_gate_entry_announces_intro_and_nameplate_exactly_once() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn_boss(arena)
	var intros: Array = []
	var appeared: Array = []
	var on_intro := func(name_: String) -> void: intros.append(name_)
	var on_appear := func(name_: String, cur: int, _max: int) -> void: appeared.append([name_, cur])
	GameEvents.boss_intro_started.connect(on_intro)
	GameEvents.boss_appeared.connect(on_appear)
	boss.announce()
	boss.announce()
	boss.health.take_damage(1, null)  # 伤害也会 announce，但守卫只放行一次
	eq(intros.size(), 1, "boss_intro_started fires exactly once")
	eq(appeared.size(), 1, "boss_appeared fires exactly once")
	eq(intros[0], ExecutionerBoss.BOSS_TITLE)
	ok(not Director.is_input_locked(), "the nameplate flourish never takes the knight's input")
	await flush(2)
	var presentation := Director.get_node_or_null("CinematicPresentation")
	ok(presentation != null)
	eq(presentation.active_shot, "boss", "boss_appeared raises the existing boss title tableau")
	GameEvents.boss_intro_started.disconnect(on_intro)
	GameEvents.boss_appeared.disconnect(on_appear)
	presentation.dismiss(true)
	arena.queue_free()
	await flush(2)


# --- 3. 竞技场灯：火膛 + 暖池、二阶段转炽、倒地熄灭 ------------------------------

func test_arena_hearths_frame_the_boss_and_go_out_when_he_falls() -> void:
	var built := await _build_arena()
	var host: Node2D = built[0]
	var wing: Level01EastWing = built[1]
	var boss: ExecutionerBoss = built[2]
	ok(boss != null, "fresh arena builds the executioner")
	eq(wing.arena_hearth_count(), 2, "two forge hearths frame the duelling spot")
	var layer := host.get_node_or_null("ArenaPresentation") as Node2D
	ok(layer != null, "arena lighting lives in its own presentation layer")
	var left := layer.get_node_or_null(_hearth_name(Level01EastWing.ARENA_HEARTH_LEFT_X)) as TorchLight if layer != null else null
	var right := layer.get_node_or_null(_hearth_name(Level01EastWing.ARENA_HEARTH_RIGHT_X)) as TorchLight if layer != null else null
	ok(left != null and right != null, "hearths flank the boss")
	if left != null and right != null:
		ok(left.position.x < boss.position.x and right.position.x > boss.position.x)
		almost(left.position.y + Level01EastWing.HEARTH_ART_H, Level01Static.GROUND_TOP, 0.01,
				"hearth art stands on the paved floor")
		ok(left.is_in_group("grounded") and left.has_meta("feet"))
		var left_light := left.get_node_or_null("FlameGlow") as WorldLight
		ok(left_light != null and left_light.lit, "the hearth light is lit")
		if left_light != null:
			eq(left_light.blend_mode, Light2D.BLEND_MODE_ADD, "arena light is additive")
			ok(left_light.authored_radius <= 160.0, "arena light radius is capped")
	var pool := layer.get_node_or_null("ArenaPool") as WorldLight if layer != null else null
	ok(pool != null and pool.lit, "the nave floor carries a warm centre pool")
	ok(wing.arena_light_energy() > 0.3, "the stage is lit before the fight")
	# 倒地：舞台灯暗下去，残芯成为唯一的光。
	boss.health.take_damage(99, null)
	ok(wing.arena_lights_dimmed(), "the stage starts going dark the moment he falls")
	Engine.time_scale = 1.0
	await get_tree().create_timer(2.2).timeout
	ok(wing.arena_light_energy() < 0.02, "hearth lights are off after the death beat")
	host.queue_free()
	await flush(2)


func test_phase_two_turns_the_arena_hot_without_taking_input() -> void:
	var built := await _build_arena()
	var host: Node2D = built[0]
	var wing: Level01EastWing = built[1]
	var boss: ExecutionerBoss = built[2]
	boss._set_blocking(false)
	boss.health.take_damage(7, null)
	ok(boss.is_enraged(), "half HP enters phase two")
	ok(boss.presence_hot(), "the backlight turns ember-red with the phase")
	ok(not Director.playing, "the phase beat never starts a Director script by itself")
	ok(not Director.is_input_locked(), "the arena light shift never takes the knight's input")
	await flush(4)
	ok(wing.arena_lights_hot(), "the stage shifts to the hot phase")
	var layer := host.get_node_or_null("ArenaPresentation") as Node2D
	var left := layer.get_node_or_null(_hearth_name(Level01EastWing.ARENA_HEARTH_LEFT_X)) as TorchLight if layer != null else null
	ok(left != null)
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.7).timeout
	ok(wing.arena_light_energy() > 0.7, "phase two hearths burn brighter")
	if left != null:
		var left_light := left.get_node_or_null("FlameGlow") as WorldLight
		if left_light != null:
			ok(left_light.color.r > left_light.color.b + 0.5, "hearth colour goes hot red-orange")
	ok(Engine.time_scale == 1.0, "Juice's phase slow-motion resolves and never sticks")
	host.queue_free()
	await flush(2)


# --- 4. 进场剧本 → 跳过 → 死亡 → 残芯交接 --------------------------------------

## 倒地那一拍：Boss 本体立刻消失，但 2× 尸体帧动画留在世界里播完。
func test_death_leaves_a_double_scale_corpse_animation() -> void:
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var boss := await _spawn_boss(arena)
	boss.health.take_damage(99, null)
	await flush(2)
	ok(not is_instance_valid(boss), "the boss body is released the frame it dies")
	var corpse: Sprite2D = null
	for child in arena.get_children():
		if String(child.name) != "WorldEffects":
			continue
		for frame_node in child.get_children():
			if frame_node is Sprite2D and (frame_node as Sprite2D).texture != null:
				corpse = frame_node as Sprite2D
	ok(corpse != null, "the death beat spawns a corpse frame animation")
	if corpse != null:
		eq(corpse.scale, Vector2(2, 2), "the corpse plays at the boss's 2x scale")
		ok(corpse.flip_h or true)
		ok(corpse.position.y < 0.0, "the corpse is pinned around the boss's feet")
	arena.queue_free()
	await flush(2)


func test_arena_entry_is_skippable_and_death_hands_the_heart_over() -> void:
	var built := await _build_arena()
	var host: Node2D = built[0]
	var wing: Level01EastWing = built[1]
	var boss: ExecutionerBoss = built[2]
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player := await spawn_player(arena, Vector2(300, -24))
	var cam := GameCamera.new()
	arena.add_child(cam)
	await flush(1)
	var beats := Level01StoryBeats.new()
	add_child(beats)
	beats.bind(host, player, boss)
	wing.boss_gate_entered.connect(beats.on_boss_gate)
	wing.boss_slain.connect(beats.on_boss_slain)
	# 跨进拱门 = 东翼宣布 + 玩家侧演出（和 Level01Static 的接线一致）。
	wing._on_boss_gate(player)
	ok(boss.is_announced(), "crossing the gate announces the boss")
	ok(Director.playing, "the entrance beat runs")
	ok(Director.is_input_locked(), "the entrance takes the knight's input")
	ok(player.cutscene_locked, "the knight is locked with the Director")
	# 铁门砸下 → 炉火涌起 → 镜头才推近竞技场。
	await get_tree().create_timer(0.35).timeout
	ok(cam._focused, "the camera is held by the arena shot")
	ok(wing._arena_surge > 0.0, "the furnace lights surge with the gate slam")
	Director.skip_step()
	ok(not Director.playing, "one accept skips the whole entrance")
	ok(not Director.is_input_locked(), "the input comes back")
	ok(not cam._focused, "the camera comes back")
	ok(not player.cutscene_locked, "the knight is released")
	ok(SaveData.has_flag("boss_intro"), "a skipped entrance still counts as told")
	var presentation := Director.get_node_or_null("CinematicPresentation")
	presentation.dismiss(true)
	# 打空他的血：死亡演出 + 舞台暗场 + 残芯解锁。
	var heart := host.get_node("Props/ForgeHeart") as ForgeHeart
	ok(not heart.unlocked, "the heart is locked while the boss lives")
	boss.health.take_damage(99, null)
	ok(wing.arena_lights_dimmed(), "the arena dims on the death beat")
	ok(Director.playing, "the defeat beat stages the hand-off to the heart")
	Engine.time_scale = 1.0
	Director.skip_step()
	ok(not Director.playing)
	ok(not Director.is_input_locked())
	ok(not cam._focused, "the camera is released after the defeat beat is skipped")
	ok(SaveData.has_flag("boss_dead"), "the executioner's death persists")
	ok(heart.unlocked, "the forge heart is interactable after the boss")
	ok(heart.can_interact(player), "the knight can claim the heart next")
	# 存档里的旗标就是章末交接：残芯 → level02 的路由永远由 ForgeHeart 负责，
	# 这里只验证它已经拿到开启条件（不改 LevelExit / ForgeHeart 逻辑）。
	ok(Level01EastWing.should_unlock_forge(), "a flagged run now lights the heart")
	ok(not Level01EastWing.should_spawn_executioner(), "a flagged run never respawns him")
	beats.queue_free()
	host.queue_free()
	cam.queue_free()
	arena.queue_free()
	await flush(2)


## 演出灯 / 相变只走 signals + tween：暂停时它们不该把 Director 卡在 playing 里。
func test_phase_tween_does_not_hold_the_tree_paused_or_a_script() -> void:
	var built := await _build_arena()
	var host: Node2D = built[0]
	var boss: ExecutionerBoss = built[2]
	boss.health.take_damage(7, null)
	ok(not Director.playing)
	ok(not get_tree().paused, "presentation never pauses the tree")
	Engine.time_scale = 1.0
	await flush(4)
	ok(not Director.is_input_locked())
	host.queue_free()
	await flush(2)
