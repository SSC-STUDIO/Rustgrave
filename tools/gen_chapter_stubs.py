"""Create the chapter scene files + placeholder layouts for level03..level10.

Each scene is a root Node2D running ChapterLevel with `layout_path` pointing at
scripts/levels/chapters/levelNN_layout.gd. Existing layout files are left alone
(agents own them); scenes are always (re)written.
"""
import os

CHAPTERS = [
    ("level03", "Level03_RustTown", "锈墓・叁 — 锈城街巷", "town", "下一关是圣殿。"),
    ("level04", "Level04_Cathedral", "锈墓・肆 — 圣殿中庭", "cathedral", ""),
    ("level05", "Level05_Workshop", "锈墓・伍 — 齿轮工坊", "industrial", ""),
    ("level06", "Level06_NightGraveyard", "锈墓・陆 — 墓园夜雨", "graveyard", ""),
    ("level07", "Level07_BellTower", "锈墓・柒 — 钟楼", "cathedral", ""),
    ("level08", "Level08_SlagDepths", "锈墓・捌 — 熔渣深渊", "forge", ""),
    ("level09", "Level09_Ramparts", "锈墓・玖 — 锈城城墙", "town", ""),
    ("level10", "Level10_ForgeCore", "锈墓・拾 — 炉心深处", "forge", ""),
]

SCENE = """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/levels/chapter_level.gd" id="1_level"]

[node name="{node}" type="Node2D"]
script = ExtResource("1_level")
layout_path = "res://scripts/levels/chapters/{lid}_layout.gd"

[node name="Platforms" type="Node2D" parent="."]

[node name="Props" type="Node2D" parent="."]

[node name="Enemies" type="Node2D" parent="."]

[node name="Hooks" type="Node2D" parent="."]

[node name="Pickups" type="Node2D" parent="."]
"""

STUB = '''extends ChapterLayout
## {title} — 占位铺设：一段地面、一个余烬巢、通往下一关的门。
## 由关卡 agent 用真正的关卡替换（保留 level_id/title/entry_spawn 这些元数据函数）。


func level_id() -> String:
	return "{lid}"


func title() -> String:
	return "{title}"


func wake_line() -> String:
	return ""


func entry_spawn() -> Vector2:
	return Vector2(96, 300)


func east_limit() -> int:
	return 1280


func theme() -> String:
	return "{theme}"


func build(host: Node2D) -> void:
	floor_strip(host, "Floor", 0.0, float(east_limit()), "moss", false, false)
	walls(host, "moss")
	nest(host, "EmberNestStart", 176.0)
	waymark(host, Vector2(280, FLOOR_Y), "占位")
	exit_door(host, float(east_limit()) - 120.0, "下一关", PackedStringArray(["……"]), "{lid}_done",
			GameContext.next_level_id("{lid}"))
	finish(host)
'''

os.makedirs("scripts/levels/chapters", exist_ok=True)
for lid, node, title, theme, _ in CHAPTERS:
    scene_path = os.path.join("scenes", "levels", node + ".tscn")
    with open(scene_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(SCENE.format(node=node, lid=lid))
    print("scene", scene_path)
    layout_path = os.path.join("scripts", "levels", "chapters", lid + "_layout.gd")
    if not os.path.exists(layout_path):
        with open(layout_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(STUB.format(lid=lid, title=title, theme=theme))
        print("stub ", layout_path)
