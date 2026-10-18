class_name ChapterTitles
extends RefCounted
## 章节显示名的旧常量 API（LEVEL01…LEVEL10），内部委托 ChapterText。
##
## 14 章统一重编后，常量名仍对旧 id（LEVEL03 是 level03 的标题，显示为「肆」）；
## 新章（level02b/04b/07b/09b）不占用旧常量名，取标题请用 ChapterText.title_of(id)。
## 保留常量是为了让 HUD 暂停菜单 / 地图 / 旧 UI 测试不用大面积改口径。
##
## 这个脚本仍是叶子节点：只用常量/静态变量，没有 preload、不引用场景，避免 HUD 的
## 暂停菜单 preload 链（HUD.tscn → hud.gd → PauseMenu.tscn → pause_menu.gd）把关卡
## 场景拖回加载图，也就不会形成 PackedScene 循环。

static var LEVEL01: String = ChapterText.title_of("level01")
static var LEVEL02: String = ChapterText.title_of("level02")
static var LEVEL03: String = ChapterText.title_of("level03")
static var LEVEL04: String = ChapterText.title_of("level04")
static var LEVEL05: String = ChapterText.title_of("level05")
static var LEVEL06: String = ChapterText.title_of("level06")
static var LEVEL07: String = ChapterText.title_of("level07")
static var LEVEL08: String = ChapterText.title_of("level08")
static var LEVEL09: String = ChapterText.title_of("level09")
static var LEVEL10: String = ChapterText.title_of("level10")


## 任意 id 的显示名（新章用这个，别再加常量）。
static func title_of(level_id: String) -> String:
	return ChapterText.title_of(level_id)
