class_name LoreStele
extends Interactable
## Ancient stone stele etched with lore of the Cinder Compact.

@export var lore_title: String = "炉约碑铭"
@export_multiline var lore_text: String = "记忆凝成硬块，仇与誓变成会走动的废铁。"

const STELE_TEX := "res://assets/env/statue_keeper.png"


func _ready() -> void:
	super._ready()
	prompt = "E 辨认碑文"
	# 原点 = 碑底中点，摆在台面 y 上就是站着。旧偏移 (-6,-6) 让 36px 高的碑有 30px
	# 埋进地里，三块碑都只露一个头。
	# 取 32×40 的 1:1 子矩形、按同尺寸绘制：scale 正好 1。以前 size=28×36 配 32×40
	# 的 region，得到 0.875/0.9 的小数缩放，像素边缘会糊。
	ensure_sprite(STELE_TEX, Vector2(32, 40), Vector2(-16, -40), Palette.RUST_DARK, Rect2(0, 0, 32, 40))


func get_prompt(_actor: Node) -> String:
	return "E 辨认 [%s]" % lore_title


func interact(_actor: Node) -> void:
	Sfx.play(&"ui_select", 0.04, -3.0)
	GameEvents.announcement.emit("【%s】%s" % [lore_title, lore_text])
	if not Director.playing:
		Director.play([
			{"kind": "caption", "text": "【%s】\n“%s”" % [lore_title, lore_text], "hold": 2.8}
		])
