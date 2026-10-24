extends TestCase
## 群警戒与脱战：默认全关（与旧行为一致）；开了之后同伴被唤起、埋着的骸骨起身、
## 骑士跑远时骸骨放弃追击回出生点。

func _host() -> Node2D:
	var host := Node2D.new()
	add_child(host)
	build_floor(host)
	return host


func _enemy(host: Node2D, enemy_name: String, kind: String, pos: Vector2,
		props: Dictionary = {}) -> EnemyBase:
	var layout := ChapterLayout.new()
	add_child(layout)
	return layout.enemy(host, enemy_name, kind, pos, props) as EnemyBase


func test_defaults_change_nothing() -> void:
	var host := _host()
	var a := _enemy(host, "A", "skeleton", Vector2(300, 0))
	var b := _enemy(host, "B", "skeleton", Vector2(340, 0))
	a.set_physics_process(false)
	b.set_physics_process(false)
	await flush(1)
	almost(a.alert_radius, 0.0, 0.0001)
	almost(a.lose_range, 0.0, 0.0001)
	a.begin_telegraph(&"skeleton", 0.3)
	ok(not b.is_alerted(), "no alert radius = nobody is woken")
	almost(b.alert_scale(), 1.0, 0.0001)
	var far := Node2D.new()
	far.global_position = Vector2(9999, 0)
	add_child(far)
	ok(not a.lost_target(far), "lose_range 0 never gives up")


func test_a_telegraph_wakes_peers_inside_the_radius_only() -> void:
	var host := _host()
	var caller := _enemy(host, "Caller", "scrapper", Vector2(300, 0), {"alert_radius": 160.0})
	var near := _enemy(host, "Near", "skeleton", Vector2(380, 0))
	var far := _enemy(host, "Far", "skeleton", Vector2(700, 0))
	for e in [caller, near, far]:
		e.set_physics_process(false)
	await flush(1)
	eq(near.state(), SkeletonEnemy.State.BURIED)
	caller.begin_telegraph(&"scrapper", 0.45)
	ok(near.is_alerted(), "the nearby skeleton heard it")
	eq(near.state(), SkeletonEnemy.State.RISE, "and climbed out of the ground")
	ok(not far.is_alerted(), "the one 400px away did not")
	eq(far.state(), SkeletonEnemy.State.BURIED)
	almost(near.alert_scale(), EnemyBase.ALERT_RANGE_SCALE, 0.0001, "alerted enemies see further")


func test_being_hit_alerts_peers_and_the_alert_expires() -> void:
	var host := _host()
	var player := await spawn_player(host, Vector2(100, -24))
	var victim := _enemy(host, "Victim", "scrapper", Vector2(300, 0), {"alert_radius": 200.0})
	var peer := _enemy(host, "Peer", "scrapper", Vector2(380, 0))
	await flush(2)
	victim.health.take_damage(1, player)
	await flush(2)
	ok(peer.is_alerted(), "a hit raises the alarm")
	await flush(190)
	ok(not peer.is_alerted(), "alerts last %.0fs, then calm" % EnemyBase.ALERT_HOLD)


func test_skeleton_gives_up_and_walks_home_when_the_knight_is_far() -> void:
	var host := _host()
	var bones := _enemy(host, "Bones", "skeleton", Vector2(300, 0), {"lose_range": 140.0})
	bones.set_physics_process(false)
	await flush(2)
	bones._state = SkeletonEnemy.State.WALK
	bones._anchor_x = 100.0
	var player := await spawn_player(host, Vector2(900, -24))
	ok(bones.lost_target(player), "900px away is beyond lose_range")
	bones._tick_walk(player)
	ok(bones.velocity.x < 0.0, "it walks back toward its anchor, not toward the knight (%.0f)" % bones.velocity.x)
	var chaser := _enemy(host, "Chaser", "skeleton", Vector2(300, 0))
	chaser.set_physics_process(false)
	await flush(2)
	chaser._state = SkeletonEnemy.State.WALK
	chaser._anchor_x = 100.0
	chaser._tick_walk(player)
	ok(chaser.velocity.x > 0.0, "without lose_range it chases forever (old behaviour)")
