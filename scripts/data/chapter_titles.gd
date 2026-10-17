class_name ChapterTitles
extends RefCounted
## 章节显示名的单一口径：开场章节卡、暂停菜单档案卡、章节播报都从这里取。
##
## 这个脚本是叶子节点——只有常量、没有 preload、没有全局类引用。HUD 的暂停菜单
## preload 链（HUD.tscn → hud.gd → PauseMenu.tscn → pause_menu.gd）经过这里时不会
## 把关卡场景拖回加载图，也就不会形成 PackedScene 循环。

const LEVEL01 := "锈墓・壹 — 腐液回廊"
const LEVEL02 := "锈墓・贰 — 沉钟地窟"
const LEVEL03 := "锈墓・叁 — 锈城街巷"
const LEVEL04 := "锈墓・肆 — 圣殿中庭"
const LEVEL05 := "锈墓・伍 — 齿轮工坊"
const LEVEL06 := "锈墓・陆 — 墓园夜雨"
const LEVEL07 := "锈墓・柒 — 钟楼"
const LEVEL08 := "锈墓・捌 — 熔渣深渊"
const LEVEL09 := "锈墓・玖 — 锈城城墙"
const LEVEL10 := "锈墓・拾 — 炉心深处"
