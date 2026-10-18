extends TestCase
## 能力集 × 14 章可达性矩阵（契约 §3.3）。
##
## 对 GameContext.LEVEL_ORDER 的每一章，用 LevelSanity.is_reachable 跑：
##   base       （无能力；主线必须可用——docs/level_authoring.md 硬规则）
##   hookshot   （允许钩锁：只可能扩大可达集，不允许成为主线前提）
##   ember_step （余烬步；LevelSanity 目前没有二段跳模型，几何结果 = base，
##               这里如实打印并在报告里注明）
##   full       （钩锁 + 余烬步）
## 断言每章 spawn→exit 可达（章节关要求 base 就可达），每个存档点→exit 可达
## （respawn 不软锁）。level01/level02 是教程/非数据驱动关，允许钩锁参与主路线，
## 只记录不 gates。真实 roster 存在时，再按每个角色的 ability_set 跑一遍
## （feature-detect；不存在则跳过）。
##
## 输出审计行：[LOADOUT ROUTE] / [LOADOUT ROUTE CKPT] / [LOADOUT ROUTE CHAR]。

const SETS := {
	"base": [],
	"hookshot": [&"hookshot"],
	"ember": [&"ember_step"],
	"full": [&"hookshot", &"ember_step"],
}
const SET_ORDER: Array[String] = ["base", "hookshot", "ember", "full"]


func setup() -> void:
	SaveData.save_path = "user://test_loadout_route.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	LoadoutBridge.test_roster_override = []
	LoadoutBridge.reset_roster_cache()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.flags.clear()
	Director.abort()
	WorldClock.set_zone(WorldClock.Zone.OUTDOORS)


func _load_level(path: String) -> Node:
	var packed := load(path) as PackedScene
	ok(packed != null, "%s loads" % path)
	if packed == null:
		return null
	var level := packed.instantiate()
	add_child(level)
	await flush(2)
	Director.abort()
	return level


func _spawn_of(level: Node, id: String) -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		return player.global_position
	if GameContext.LAYOUTS.has(id):
		return ChapterLayout.entry_spawn_of(id)
	return Vector2(96, 300)


func _goal_of(level: Node) -> Node2D:
	var fallback: Node2D
	for node in LevelSanity._descendants(level):
		if node is LevelExit:
			return node as Node2D
		if node is ForgeHeart and fallback == null:
			fallback = node as Node2D
	return fallback


func _nests_of(level: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node in LevelSanity._descendants(level):
		if node is EmberNest:
			out.append(node as Node2D)
	return out


func _allow_hook(set_name: String) -> bool:
	return (SETS[set_name] as Array).has(&"hookshot")


## 真实 roster 的角色能力集（feature-detect）。返回 [[char_id, abilities, hook_allowed], ...]。
func _roster_character_rows() -> Array:
	var rows: Array = []
	if not LoadoutBridge.character_available():
		return rows
	for char_id in LoadoutBridge.character_ids():
		var def := LoadoutBridge.character_def(char_id)
		var abilities: Array = def.get("ability_set", [])
		var hook := abilities.has(&"hookshot")
		rows.append([char_id, abilities, hook])
	return rows


## 主路线矩阵：spawn → exit。章节关 base 必须可达；hook/ember/full 只允许更宽。
func test_spawn_to_exit_for_every_ability_set() -> void:
	var character_rows := _roster_character_rows()
	var roster_note := "roster" if not character_rows.is_empty() else "no-roster"
	for id in GameContext.LEVEL_ORDER:
		var level := await _load_level(String(GameContext.LEVELS[id]))
		if level == null:
			continue
		var spawn := _spawn_of(level, id)
		var goal := _goal_of(level)
		var is_chapter := GameContext.LAYOUTS.has(id)
		if goal == null:
			# level01/02 是教程/世界场景（不进 LAYOUTS）；它们由别的线维护，
			# 临时构建失败只记录，不当作 loadout 主路线矩阵的失败，避免跨线噪音。
			print("[LOADOUT ROUTE] %s NO-GOAL chapter=%s skipped" % [id, str(is_chapter)])
			if is_chapter:
				ok(false, "%s must have a main-route goal (exit/forge heart)" % id)
			level.free()
			await flush(1)
			continue
		var goal_feet := LevelSanity.feet_of(goal)
		var row := {}
		for set_name in SET_ORDER:
			row[set_name] = LevelSanity.is_reachable(level, spawn, goal_feet, _allow_hook(set_name))
			if is_chapter:
				ok(bool(row[set_name]), "%s: %s reaches the exit" % [id, set_name])
		# 单调性：base 可达则宽松能力集必须也可达（防止 is_reachable 被能力弄丢）。
		if bool(row["base"]):
			ok(bool(row["hookshot"]) and bool(row["ember"]) and bool(row["full"]),
					"%s: wider ability sets are supersets of base" % id)
		# 主路线不能要求能力：章节关的 minimal 必须是 base。
		var minimal := "none"
		for set_name in SET_ORDER:
			if bool(row[set_name]):
				minimal = set_name
				break
		if is_chapter:
			eq(minimal, "base", "%s: the main route is clearable without optional abilities" % id)
		var nests := _nests_of(level)
		var hook_required := minimal in ["hookshot", "full"]
		print("[LOADOUT ROUTE] %s base=%s hookshot=%s ember=%s full=%s minimal=%s hook_required=%s nests=%d" % [
				id, _on_off(bool(row["base"])), _on_off(bool(row["hookshot"])),
				_on_off(bool(row["ember"])), _on_off(bool(row["full"])),
				minimal, str(hook_required), nests.size()])
		# 真实 roster 的角色矩阵：每章只加载一次，顺便跑掉。
		for character in character_rows:
			var char_id: StringName = character[0]
			var abilities: Array = character[1]
			var char_ok := LevelSanity.is_reachable(level, spawn, goal_feet, bool(character[2]))
			if is_chapter:
				ok(char_ok, "%s: character %s reaches the exit with %s" % [id, char_id, str(abilities)])
		level.free()
		await flush(1)
	if character_rows.is_empty():
		print("[LOADOUT ROUTE CHAR] roster not delivered (%s) - character matrix skipped, blueprint matrix green" % roster_note)
		ok(true, "no external roster: ability-set blueprint matrix is the merge gate")
	else:
		for character in character_rows:
			print("[LOADOUT ROUTE CHAR] char=%s abilities=%s hook=%s" % [
					character[0], str(character[1]), str(character[2])])


## respawn 矩阵：每个存档点 → exit（base 与 full 两套；respawn 后不许软锁）。
func test_checkpoints_to_exit_for_ability_sets() -> void:
	for id in GameContext.LEVEL_ORDER:
		var level := await _load_level(String(GameContext.LEVELS[id]))
		if level == null:
			continue
		var goal := _goal_of(level)
		var nests := _nests_of(level)
		var is_chapter := GameContext.LAYOUTS.has(id)
		if goal == null:
			print("[LOADOUT ROUTE CKPT] %s NO-GOAL chapter=%s skipped" % [id, str(is_chapter)])
			if is_chapter:
				ok(false, "%s must have a main-route goal" % id)
			level.free()
			await flush(1)
			continue
		if is_chapter:
			ok(not nests.is_empty(), "%s has at least one checkpoint" % id)
		var goal_feet := LevelSanity.feet_of(goal)
		var ok_base := 0
		var ok_full := 0
		for nest in nests:
			var nest_feet := LevelSanity.feet_of(nest)
			var base_ok := LevelSanity.is_reachable(level, nest_feet, goal_feet, false)
			var full_ok := LevelSanity.is_reachable(level, nest_feet, goal_feet, true)
			if base_ok:
				ok_base += 1
			if full_ok:
				ok_full += 1
			if is_chapter:
				ok(base_ok, "%s: respawn at %s still reaches the exit without abilities" % [id, nest.name])
				ok(full_ok, "%s: respawn at %s still reaches the exit with full abilities" % [id, nest.name])
		var gate := "no" if not is_chapter else "yes"
		print("[LOADOUT ROUTE CKPT] %s base=%d/%d full=%d/%d gated=%s" % [
				id, ok_base, nests.size(), ok_full, nests.size(), gate])
		level.free()
		await flush(1)


func _on_off(value: bool) -> String:
	return "1" if value else "0"
