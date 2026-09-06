extends ChapterLayout
## 锈墓・拾 — 炉心深处 — 占位铺设：一段地面、一个余烬巢、通往下一关的门。
## 由关卡 agent 用真正的关卡替换（保留 level_id/title/entry_spawn 这些元数据函数）。


func level_id() -> String:
	return "level10"


func title() -> String:
	return "锈墓・拾 — 炉心深处"


func wake_line() -> String:
	return ""


func entry_spawn() -> Vector2:
	return Vector2(96, 300)


func east_limit() -> int:
	return 1280


func theme() -> String:
	return "forge"


func build(host: Node2D) -> void:
	floor_strip(host, "Floor", 0.0, float(east_limit()), "moss", false, false)
	walls(host, "moss")
	nest(host, "EmberNestStart", 176.0)
	waymark(host, Vector2(280, FLOOR_Y), "占位")
	exit_door(host, float(east_limit()) - 120.0, "下一关", PackedStringArray(["……"]), "level10_done",
			GameContext.next_level_id("level10"))
	finish(host)
