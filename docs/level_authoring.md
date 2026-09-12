# 关卡制作手册（章节关卡 level03–level10）

本手册说明现有章节的制作与维护约定。修改前检查工作区；每个独立功能验证后单独提交，只暂存对应文件。公共逻辑修改须同时检查已有章节与存档兼容性。

## 0. 世界观速览

Rustgrave（锈墓）：炉火熄灭之后，地下之城沉入岩层，一切循环变成锈。你是**余烬骑士**，剑上能嵌「锈核」：窑核→热锻（熔锈门）、系核→钩锁（勾锚点）、余烬核→余烬步（二段跳）。第一关是墓园走廊（腐液回廊），第二关是苔水地窟（沉钟地窟）。玩家到第三关时**一定有热锻**，钩锁/余烬步不保证（关卡可以给可选捷径，但主路线不能依赖它们）。文风：短句、冷、有金属和灰的气味；字幕一句话说完；碑文两句以内。

章节顺序与主题（已注册，勿改）：

| id | 场景 | 标题 | 主题 `theme()` | 一句话 |
|---|---|---|---|---|
| level03 | Level03_RustTown | 锈墓・叁 — 锈城街巷 | town（室外） | 地窟通到地面上的死城，窗里有灯，街上没人 |
| level04 | Level04_Cathedral | 锈墓・肆 — 圣殿中庭 | cathedral（室内） | 炉约的圣殿，吊灯还亮，石像鬼在数人 |
| level05 | Level05_Workshop | 锈墓・伍 — 齿轮工坊 | industrial（有顶） | 造锈核的工坊，吊台与压板机关最多的一关 |
| level06 | Level06_NightGraveyard | 锈墓・陆 — 墓园夜雨 | graveyard（室外） | 回到墓园的另一侧，锈雨、幽魂、骸骨从土里起来 |
| level07 | Level07_BellTower | 锈墓・柒 — 钟楼 | cathedral（室内） | 竖向：一路向上，吊台接吊台 |
| level08 | Level08_SlagDepths | 锈墓・捌 — 熔渣深渊 | forge（室内） | 毒池最多、最热的一关，火骷髅 |
| level09 | Level09_Ramparts | 锈墓・玖 — 锈城城墙 | town（室外） | 城墙上的长路，风大，跳跃与飞行敌人 |
| level10 | Level10_ForgeCore | 锈墓・拾 — 炉心深处 | forge（室内） | 终关：梦魇 Boss，之后是终局门 |

## 1. 关卡文件

- `scripts/levels/chapters/levelNN_layout.gd` —— 已完成的关卡本体。**不要加 `class_name`**。
- `tests/levelNN_layout_test.gd` —— 关卡专属测试。
- 截图输出目录 `screenshots/peek/levelNN/`（工具会建）。

场景文件 `scenes/levels/LevelNN_*.tscn` 已经指向对应 layout。沿用现有像素素材；新增文件需要时运行 Godot 导入。

## 2. 写法

```gdscript
extends ChapterLayout

func level_id() -> String: return "level05"
func title() -> String: return "锈墓・伍 — 齿轮工坊"
func wake_line() -> String: return "齿轮还在转。没有人给它们上油。"
func entry_spawn() -> Vector2: return Vector2(96, 300)   # 上一关的门把你放在这里
func default_spawn() -> Vector2: return entry_spawn()
func east_limit() -> int: return 2880                       # 关卡总宽（镜头右界）
func camera_top() -> int: return -48                       # 竖向关可给更负的值，如 -720
func theme() -> String: return "industrial"

func build(host: Node2D) -> void:
	# 地形
	floor_strip(host, "FloorA", 0.0, 480.0, "stone", false, true)
	toxin_pit(host, "PitA", 480.0, 720.0)                 # 坑底 352，液面 336..368
	step(host, "StoneA1", Vector2(528, 288), 48.0)         # 悬空踏台（16 厚）
	floor_strip(host, "FloorB", 720.0, 1600.0, "stone")
	enclose(host, "stone", -32.0)                          # 左右墙 + 顶板（室内）；室外用 walls(host)
	lift(host, "LiftA", Vector2(1616, 296), Vector2(160, 0), 5.6, 64.0)   # 链吊台
	# 机关
	plate_door(host, "GateA", Vector2(1008, 264), Vector2(1120, 256))    # 压板脚点 / 门左上角
	rusty_gate(host, "RustGate", Vector2(1808, 256))                     # 需要热锻
	hook(host, "Hook1", Vector2(1512, 56))
	# 存档点与叙事
	nest(host, "EmberNestStart", 176.0)                    # 巢在台面 y=320 上；第二个参数可给别的台面 y
	stele(host, "SteleA", Vector2(264, 320), "工坊遗训 · 齿", "……")
	waymark(host, Vector2(352, 320), "工坊")
	# 敌人：落地敌人给脚点（台面 y），飞行/穿墙敌人给悬停中心
	enemy(host, "Spitter1", "spitter", Vector2(968, 264))
	enemy(host, "Ghost1", "ghost", Vector2(800, 236))
	# 装饰
	torch(host, 412.0)                                     # 壁炬，板底贴台面
	prop(host, "rubble", Vector2(560, 352))                # 接地装饰：脚点 = 底边中点
	hanging(host, "vine", Vector2(200, 0))                 # 悬挂装饰：顶部中点
	foliage(host, "tree_2", Vector2(268, 320), 0.46)       # 会摆的树/灌木
	# 出口（自动接下一关；终关传 "" 并写结局字幕）
	exit_door(host, 2760.0, "工坊后门", PackedStringArray(["……"]), "level05_done",
			GameContext.next_level_id(level_id()))
	finish(host)                                           # 背景 + 室内区，最后调
```

共用的铺设函数都在 `scripts/levels/chapter_layout.gd`，先读一遍。可用敌人键：`spitter`（喷吐者，落地，射弹）、`scrapper`（碎铁犬，落地，冲锋）、`gear_shield`（齿盾卫，落地，正面免伤）、`flying_demon`（飞行）、`ghost`（幽魂，穿墙，从背后凝出）、`executioner`（第一关 Boss，慎用）、`skeleton`（骸骨，落地，从土里起来，起身期间无判定）、`fire_skull`（火骷髅，悬停、蓄势、扑击）、`nightmare_boss`（终关两阶段 Boss，只给 level10）。平台皮肤：`ground`（草顶土）、`floating`（教堂浮石）、`stone`（石板路）、`moss` / `moss_float`（青苔砖）；`tone` 参数可整体调色（熔炉关可把 moss 压成琥珀：`Color(1.0, 0.8, 0.6)`）。

## 3. 硬规则（`level_sanity_test` 会拒绝）

1. 地面顶 y = 320；镜头下界 400，所以**不要把可走的地面放在 y > 384**。
2. 台阶链：单跳 **上升 ≤ 32px、横跨 ≤ 72px**；下落可以跨更远（每下落 2px 多跨 1px，最多 160）。出口、**每个**余烬巢和必需压板必须从出生点按这个规则可达。`LevelSanity.is_reachable(..., allow_hook)` 默认 `true` 兼容旧检查；第 3–10 关主线检查显式传 `false`。可选钩锁路线单独检查（锚点在起跳面上方 ≤250px，落台在锚点下方 ≤110px、横向 ≤96px）。跳距按平台边缘计算，顶板不算可站立的主线路面。
3. 所有落地物（巢、碑、压板、门、锈门、出口、路牌、`prop()` 装饰、落地敌人）脚下必须有台面（顶面 −3..+8px 内）。飞行敌人不能嵌在实体里。同类敌人间距 ≥ 24px。
4. 毒池必须躺在坑里（用 `toxin_pit()` 最省事），坑两侧要能一跳（≤32px）爬出来。
5. 锈核拾取只能悬在台面上方 ≤64px，或钩锁锚点 96px 内。
6. 平台不能落在原点；全部在 `east_limit()` 之内。
7. 不依赖钩锁/余烬步通关；热锻可以要求（锈门）。

## 4. 软规则（手感与观感）

- 长度 2400–3200px（竖向关可窄而高）；2–3 个余烬巢，Boss/难点之前必有一个。
- 节奏：教学 → 组合 → 压力 → 喘息 → 高潮 → 出口。每 400–600px 换一种玩法（跳跃 / 机关 / 战斗 / 吊台）。
- 敌人 6–12 个，别把两只喷吐者对着同一段跳跃路。幽魂放在着陆点或狭窄走廊。
- 装饰：地面每 150–250px 有一样东西（火把、碎石、栏杆、树），别让 600px 空着；顶板下垂藤蔓；别在跳跃落点正上方放会遮挡的大装饰。
- 字幕/碑文/路牌全部中文；路牌 2 个字。
- 竖向关（level07）：把地面分成多层台面，吊台 `travel = Vector2(0, -N)`，`camera_top()` 给到最高台面上方 −80 左右；顶板 `enclose(..., ceiling_y)` 相应上移。

## 5. 工作流

1. 读 `scripts/levels/chapter_layout.gd`、`scripts/levels/level02_layout.gd`（第二关范例）和本手册。
2. 写你的 layout。
3. 体检（只看你这一关）：
   `$env:RUSTGRAVE_LEVEL_FILTER='levelNN'; powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter level_sanity -TimeoutSeconds 240`
   看输出里 `[FAIL]` 下面的每一条，修到 `OK`。
4. 你的专属测试：`powershell ... tools/run_tests.ps1 -CaseFilter levelNN_layout`（用 `Level02` 的 `tests/level02_layout_test.gd` 作范本：在一个加了 `game_world` 组、`scene_file_path` 指向你场景的空 `Node2D` 上 `load("res://scripts/levels/chapters/levelNN_layout.gd").new().build(host)`，断言你的关键台阶链、机关接线、敌人落点）。
5. 看图：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_peek_live.ps1 -Level levelNN -OutDir screenshots/peek/levelNN -Spots 320,960,1600,2240,2880 -Hold 2 -Lit`（`-Spots` 给镜头中心 x，一屏 640 宽；`-Active` 让敌人动起来）。用读文件工具打开 PNG 逐张看：有没有悬空、埋地、遮挡、空荡、颜色打架。改完再截。
6. 运行全量测试及正常输入验收，检查跌落脱困、入口、机关、难点、存档点与出口。每个完整改动验证后立即 Git 提交；记录实际结果和截图路径。

## 6. 常见坑

- `.tscn` 里不能写 `#` 注释。
- GDScript 常量不能被子类覆写，所以元数据用函数。
- 压板 `plate_door()` 的第一个位置是压板**所在台面的脚点**（函数自己减 6）；门位置是门的**左上角**（门 16×64，底在 y+64，所以地面上的门 y=256）。
- `nest(host, name, x, feet_y)` 的 feet_y 是台面 y（巢原点会自动上移 14）。
- 出生点 `entry_spawn()` 下方必须有地面（可以是掉落进来，但别掉进毒池）。
- 几何可达不是实际通关证据。实心高台东侧需要回程石阶；毒池上方踏点要留出至少 32px 的坑底头部净空。第四关唱诗台、第五关淬火槽的回归测试覆盖这两类困路。
- 检查点安全要实际运行敌人 AI 验证：骑士在巢旁静止至少 6 秒，确认不会唤醒相邻战斗区。钟楼入口骸骨使用 96px 唤醒距离；中层幽魂分属上下层，避免穿墙追到复活点。
- 高层使用 16px 薄台面，避免填充实体堵住下层。钟楼镜头上界为 −832、顶板为 −800、出口台面为 −640；室内区域和背景必须覆盖全高。用 `run_peek_live.ps1 -Level level07 -CamY -650` 检查塔顶。
- 出口门 48 宽、64 高，`x` 是门底中点；别贴着右墙（留 ≥ 80px）。
- PowerShell 5.1 对中文很不友好：不要用 `Set-Content`/`Out-File` 改含中文的文件，用编辑工具。
