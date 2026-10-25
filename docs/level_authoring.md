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

### 2.1 这一关的天（可选）

`ambient()` 只管**第一次进关那一刻**的天。这一关往后会刮什么风、哪一段是另一副天，用这两个函数：

```gdscript
## 配方：allowed 限死这一关会出现的天气，weights 按阶段加权，hold/intensity 给区间。
## 空字典 == 沿用全局阶段权重表（老关卡什么都不用写）。
func weather_recipe() -> Dictionary:
	return {
		"allowed": [WorldClock.Weather.RAIN, WorldClock.Weather.RUST_RAIN, WorldClock.Weather.FOG],
		"weights": {"night": {"rust_rain": 6, "rain": 3}, "*": {"rain": 4, "fog": 2}},
		"hold": Vector2(180.0, 300.0),      # 或直接给 float
		"intensity": Vector2(0.7, 1.0),     # 每次换天在区间里重掷
	}

## 区域：只改一段路上的天。位置是矩形左上角，尺寸是矩形大小。
## 不写 weather 就沿用基础天气（只改强度和风力）；outdoor=true 会在室内关里
## 开一片真的会下雨的露天（自己配 AtmosphereZone），走回室内自动收。
func weather_regions() -> Array:
	return [
		{"name": "GaleGap", "rect": Rect2(2048, 232, 464, 168),
			"weather": WorldClock.Weather.RAIN, "intensity": 1.0, "wind_scale": 1.5},
		{"name": "TowerLee", "rect": Rect2(2512, 236, 288, 164),
			"intensity": 0.4, "wind_scale": 0.35},
	]
```

要点：区域矩形必须落在 `east_limit()` 与 `camera_top()-64 .. 400` 之内（`level_weather_test` 会拒绝越界）；雨滴会自动避开顶板——有实心盖着的那一列，雨从顶板下方开始下；强度 0 = 有云无雨。存档只记基础态，区域覆盖是"此刻站在哪"的产物，读档后由区域重新装配。

## 3. 硬规则（`level_sanity_test` 会拒绝）

1. 地面顶 y = 320；镜头下界 400，所以**不要把可走的地面放在 y > 384**。
2. 台阶链：单跳 **上升 ≤ 32px、横跨 ≤ 72px**；下落可以跨更远（每下落 2px 多跨 1px，最多 160）。出口、**每个**余烬巢和必需压板必须从出生点按这个规则可达。`LevelSanity.is_reachable(..., allow_hook)` 默认 `true` 兼容旧检查；第 3–10 关主线检查显式传 `false`。可选钩锁路线单独检查（锚点在起跳面上方 ≤250px，落台在锚点下方 ≤110px、横向 ≤96px）。跳距按平台边缘计算，顶板不算可站立的主线路面。
3. 所有落地物（巢、碑、压板、门、锈门、出口、路牌、`prop()` 装饰、落地敌人）脚下必须有台面（顶面 −3..+8px 内）。飞行敌人不能嵌在实体里。同类敌人间距 ≥ 24px。
4. 毒池必须躺在坑里（用 `toxin_pit()` 最省事），坑两侧要能一跳（≤32px）爬出来。
5. 锈核拾取只能悬在台面上方 ≤64px，或钩锁锚点 96px 内。
6. 平台不能落在原点；全部在 `east_limit()` 之内。
7. 不依赖钩锁/余烬步通关；热锻可以要求（锈门）。
8. 64/96px 高的实心台如果直接从地面砌起，会被深层净空检查读成「压在台面上的墙」
   （`ledge ... has no headroom`）。把它拆成 32px 一层、上下对齐的叠石，顶面坐标不变，
   跳跃链和测试都不用改；拆开后每一层都只是上一层的台阶。

## 4. 软规则（手感与观感）

- 长度 2400–3200px（竖向关可窄而高）；2–3 个余烬巢，Boss/难点之前必有一个。
- 节奏：教学 → 组合 → 压力 → 喘息 → 高潮 → 出口。每 400–600px 换一种玩法（跳跃 / 机关 / 战斗 / 吊台）。
- 敌人 6–12 个，别把两只喷吐者对着同一段跳跃路。幽魂放在着陆点或狭窄走廊。
- 装饰：地面每 150–250px 有一样东西（火把、碎石、栏杆、树），别让 600px 空着；顶板下垂藤蔓；别在跳跃落点正上方放会遮挡的大装饰。
- 字幕/碑文/路牌全部中文；路牌 2 个字。
- 竖向关（level07）：把地面分成多层台面，吊台 `travel = Vector2(0, -N)`，`camera_top()` 给到最高台面上方 −80 左右；顶板 `enclose(..., ceiling_y)` 相应上移。

### 4.1 主题、玩法变化与支路矩阵

每一章必须有一个能一句话说清的主题，和一个**只有这一章这样做**的玩法变化。
支路不是「再放一枚同名的核」：它要给出世界信息（碑文/路牌）、新的选择，或真正的
捷径；核可以是添头，但不能是唯一的理由。主线顺序固定：单跳 → 冲刺 → 热锻 → 钩锁
→ 余烬步；支路可以写给钩锁/余烬步，但不能把主线卡在它们后面。

| id | 主题/场景 | 玩法变化 | 支路（可选，钩锁优先） | 检查点（x / 台面 y） |
|---|---|---|---|---|
| level02 | 沉钟地窟 · 室内苔水 | 一直向下：竖井、吊台横渡、毒水坑 | 锈门后乘竖向吊台 D 到壁龛读「沉钟纪事 · 数」（世界信息） | 176 / 1664，出口 2440 |
| level03 | 锈城街巷 · 室外死城 | 街面/屋顶双高度：屋顶压板开街面闸门，窄巷压视线 | 塔楼屋顶（钩锁）读「锈城纪事 · 灯」+ 余烬核 | 176、1424、2000（巷口），出口 2760 |
| level04 | 圣殿中庭 · 室内冷紫 | 唱诗台/讲坛的垂直落差 + 断顶廊桥（室内真下雨） | 拱顶高台（钩锁）读「炉约 · 顶」+ 余烬核 | 176、2224（桥中段石）、2384，出口 2928 |
| level05 | 齿轮工坊 · 室内暖石 | 链吊台最多：横渡、竖送、相位换乘 + 双压板 | 长冷却池上方检修龛（钩锁）读「工坊遗训 · 吊」 | 176、1616、2576，出口 2960 |
| level06 | 墓园夜雨 · 室外 | 能见度：坟堆浓雾、长毒沟斜锈雨，骸骨在雾里起身 | 树顶石（钩锁）读「墓志 · 树」+ 余烬核 | 176、2120，出口 2760 |
| level07 | 钟楼 · 室内竖井 | 竖向：四座吊台交替上升，塔顶 256px 窄台 | 顶板壁龛（钩锁）读「守钟人 · 余」+ 选择 | 176、544（-160）、1052（-640），出口 1172 |
| level08 | 熔渣深渊 · 室内热渣 | 渣河跳石 + 火骷髅低空走廊 | 渣河 A 上方排气龛（钩锁）读「熔渣纪事 · 气」 | 176、1792、2440，出口 2920 |
| level09 | 锈城城墙 · 室外风口 | 风口短跳石 + 飞行恶魔/塔顶喷吐者 | 塔楼三哨台（钩锁）读「城墙铭 · 鹰」+ 余烬核 | 176、1544、2536，出口 3096 |
| level10 | 炉心深处 · 室内终局 | 1200px 平地 Boss 竞技场（无坑无台阶） | 入口回廊守夜台（钩锁）读「炉心铭 · 守」——先把结局选择讲清楚 | 176、880，Boss 门 1080，终局门 2440 |

支路的写法约定：锚点挂在支路正上方、落台在锚点下方 ≤110px；从最近的合法起跳面
到锚点 ≤250px；支路台面的名字**不要**以 `Ceiling` 开头（体检把顶板当不可站立面）。
碑文站在支路台面上，核悬在台面上方 ≤64px；两者横向错开，别把核挤进字里。

### 4.2 软锁、检查点与死亡回程

- **主路线**：从出生点到出口、每个余烬巢、必要压板和锈门，必须用
  `LevelSanity.is_reachable(..., allow_hook=false)` 走通；这是第 3 关起的硬检查。
  新增支路必须同时断言 `allow_hook=false` 不可达、`allow_hook=true` 可达。
- **能力顺序**：支路可以要钩锁或余烬步；主路线不能。第 3 关的塔顶支路在拿到钩锁
  之前只是看得见、上不去；第 5 关的系核仍在主路线上（走道 E 的台阶），钩锁只是
  快一点。不要在早期章节的支路里塞主线能力核。
- **检查点**：每章 2–3 个巢，间距尽量 ≤1000px；最后一个巢必须在终点战/终局门之前。
  巢位要在附近敌人的 `aggro_range`（冲锋/射击）、`wake_range`（幽魂）和
  `patrol_range` 的边界之外；level03 的巷口巢、level04 的桥中段巢都有对应断言。
  中段没有安全平面时，宁可把巢放在一块加宽的桥石上，也不要让「安全点」落在
  喷吐者 380px 射程内。
- **死亡回程**：最后一段回程超过约 1000px 时，要么补中段巢，要么用一张单向
  捷径把玩家送回难点前（本作的捷径以吊台/钩点为主，不新增传送）。
- 改完必须跑：`level02..level10` 的 layout/scene、`level_routing`、
  `chapter_progression`、`level_sanity` 与 `level_weather`；体检器会拒绝
  「站不上去的顶面、埋住的台阶、没有净空的实心、落在敌人仇恨圈里的巢」。

### 4.3 引导（不靠长篇提示）

- **地形**：先用高度差把「该往哪走」摆出来——第 3 关的塔楼、第 4 关的唱诗台、
  第 5 关的压板台、第 7 关的吊台、第 9 关的塔楼三，都是站在地面就能看见的剪影。
- **灯光/地标**：室内用壁炬、巢火和吊台链条做光点；室外用塔、门洞、路牌、窗里
  的锈苔做地标。支路锚点本身就是路标，别再写「上面有东西」。
- **敌人**：一个战斗句子只教一个动词。喷吐者教弹反，碎铁犬教冲锋距离，齿盾卫教
  绕背，骸骨教「先看土再走」，火骷髅教低空走廊。别在同一段跳跃路上放两只喷吐者。
- **文字**：路牌 2 个字；碑文两句话内；字幕一句话说完。不要新增教学长文。
- **天气**：局部天气是引导也是压力——第 6 关的雾把「看不见」变成玩法，但雾区
  不能盖住检查点或出口的轮廓；雾/雨区的范围用 `weather_regions()`，存档只记基础态。

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

## 7. 贴图贴合与室内远景（2A 之后的硬规则）

章节 03–10 的装饰不再直接引用素材族原图，全部经 `PropCatalog` 解析；`prop_fit_test`
（`tests/prop_fit_test.gd`）会拒绝以下情况：

1. **贴纸方块**：不透明像素 >92% 且四角都不透明的贴图不能当接地装饰。合法的整块板
   （门洞 `door_arch*`、木门 `door`/`moss_door`、墙块 `wall_block`、压板 `plate`、
   垂挂条 `vine`、告示牌 `warning_plate`、排水拱 `arch`）登记在测试的 `FULL_BLEED`
   里，新增例外必须写清理由。
2. **主题越界**：`prop()/foliage()/hanging()` 只接受 `PropCatalog.THEME_PROPS[theme]`
   里的键；十字墓碑/教堂紫柱不得种进工坊、熔渣、街巷。新键要先进 `DECOR` + 主题白名单。
3. **贴图派生**：70px 的 Kenney 原件、带 tileset 底板的 `gh_*` 件，都必须由
   `tools/gen_theme_tiles.py` 派生成本族 1x 变体
   （`assets/env/props/<family>/<key>.png`）后再用；`path_for()` 会自动优先取变体。
   新增派生逻辑必须保持该脚本幂等，并在 `assets/external/CREDITS.md` 记来源。
4. **整数缩放**：`prop()` 的 scale 只能是 1.0；植被用 `assets/env/normalized/props/`
   的 1x 裁切键（`tree_1_px` / `tree_2_px` / `bush_l_px`），不能靠小数缩放把原图压小。
5. **贴地的“可见底边”**：接地装饰除了 `feet` 落在台面上，贴图最后几行必须有真实不透明
   像素（不能是“画布还有几行、内容已经空了”的透明/稀疏底边）。`gh_furnace`（炉膛/落地
   锻炉）、`gh_skull_arch`（渣口）这类从 tiles.png 切出来的暗底刻件，由
   `tools/gen_theme_tiles.py` 生成像素底座/柱脚拉到画布底；`prop_fit_test` 的
   “grounded set dressing reaches the ground” 用例锁定这一点（墙板浮雕类豁免）。
6. **脚点/挂点**：接地装饰写 `feet`（底边中点，整数像素）；悬挂装饰只写 `hang_top`，
   不加入 `grounded` 组。`prop()` 已经按「最后一行不透明像素」落脚，不要按画布底边算。
7. **地形贴图不当装饰**：`SolidPlatform` 的切块（`slab_a/b/c`、`iron_slab_*`、
   `*_fill*`、`float_*`、`tile_*`）是「平顶 + 断裂底边」的地台素材，单独种在场景里
   就是一块读不懂的方块。要表现塌落的石墙/锈结构，用有轮廓的 `rubble_*`、
   `broken_machine`、`girder_*`、`rock_pile`，或让 `tools/gen_theme_tiles.py`
   把铺石板切成碎片（`slab` 键的族变体已由 `_fracture_slab()` 处理）。
   `prop_fit_test` 的 `test_decor_never_uses_terrain_slab_tiles` 会同时检查第一章的
   `PLAY_DECOR` 与各章实际种下的装饰。
8. **室内远景**（`ThemeBackdrop.THEMES`）：室内主题必须至少一层 `"covers_top": true`，
   真的盖住 640×360 视口的顶部 96px（`wall_*` 平铺墙板或 `truss_*` 顶架）。
   竖井类（钟楼）用 `"tile": true` 的墙板，它的 region 覆盖全部镜头高度，不靠
   `repeat_times`；其它层仍必须 `repeat_times >= 4`。室内主题不加天气（`indoors: true`）。
   新增室内主题要同时登记 `THEMES`、`SIGNATURE_LAYERS`、`IDENTITY_COLOR` 与
   `SIGNATURE_KIND`，否则 `parallax_backdrop_test` 会拒绝。
7. **门/闸门/压板的材质**：`Door`/`RustyGate`/`PressurePlate` 是共享场景，教堂紫贴图
   由 `ChapterLayout.plate_door()/rusty_gate()` 换成当前主题的族变体（只换贴图，
   碰撞与尺寸不变）。不要再去改共享场景的默认贴图。

## 8. 机关工具箱（v3，`scripts/hazards/`）

每章的"专属机关"都从这五个基类里取，不要在章节脚本里手写判定体。全部走
`ChapterLayout` 助手（位置约定与 `platform()`/`step()` 一致），全部进 `hazards` 组并带
`hazard_kind` 元数据，`LevelSanity.hazards(host)` 可枚举，战役 bot 与测试读同一份。

| 基类 | 助手 | 用途 | 要点 |
|---|---|---|---|
| `CyclicHazard` | `cyclic(host, name, pos, skin, props)` | 蒸汽 `steam` / 炉口喷火 `flame` / 渣喷泉 `slag` / 坠钟 `bell` / 冲击波 `shock` | 休止 → 预警 → 判定循环；预警 ≥0.5s；判定体跟着画面走（喷柱升到哪判定到哪，冲击波只在两条前沿窄带里伤人）；`phase` 出生即定；`seconds_until_active()` / `safe_window(t)` 供 bot 读 |
| `CollapsingPlatform` | `collapsing(host, name, pos, width, skin, props)` | 锈梁 / 塌瓦 / 断桥 | 继承 `SolidPlatform`；踩上抖 `shake_time`（0.6s）→ 塌 → `respawn_time` 后长回；骑士还压在原位时不长回 |
| `ForceZone` | `force_zone(host, name, rect, skin, push, props)` | 风道 `wind` / 涌流 `water` / 泥沼 `mud` / 余烬风 `ember` | `push.x` 是目标速度偏移（上限 96，低于跑速 108）、`push.y` 是竖向加速度、`drag` 压低速度；`gust_period` 做阵风（前 0.6s 有风声/风丝预兆）；冲刺不受影响；`toxin_per_second` 给泥沼带毒（毒池 36/s） |
| `ConveyorBelt` | `conveyor(host, name, pos, width, speed, skin, props, height)` | 传送带 | 继承 `SolidPlatform`，用 `constant_linear_velocity` 带人；`speed` 上限 54；`flip_period` 反向前先停转 0.6s |
| `PendulumHazard` | `pendulum(host, name, pivot, length, props)` | 钟舌 / 铁锤 / 压碎机走廊 | 正弦摆动，摆幅 ≤70°、周期 ≥1.8s；每次过最低点重新武装；`head_over(x0, x1, t)` 供 bot 读 |

通用规则（`LevelSanity` 会拒绝，见 `tests/level_sanity_hazards_test.gd`）：

1. 周期机关预警 ≥0.5s，且每个周期里"休止 + 预警"≥1.2s，判定期 ≤1.6s。
2. 喷口 / 落点立在台面上；机关的判定区离余烬巢、压板、出口、门、碑、锈核 ≥40px；外力区不盖这些点。
3. 塌陷台 / 传送带不得是巢、压板、出口、门、碑的支撑，也不能站敌人（敌人会随塌陷掉下去）。
4. 冲刺 i-frames 照常能穿过机关；过场锁玩家时机关时间线冻结并收刀。
5. 首遇提示：每个机关默认带一块 `HintArea`（文案在 `HintService.CATALOG` 的 `steam/flame/slag/bell/shock/collapse/wind/surge/conveyor/pendulum/mud/candle`）。
6. 主线必须能在不吃一次机关伤害的前提下通过（预警 + 安全间隔就是为这个）；机关只在主线上制造"时机"，不制造"必中"。
7. 没有专用音效时自动退回现有音效键（`HazardFx.SFX` 的候选表）；新音效只要加进 `Sfx.LIBRARY` 就会被选中。

外观检查：`tools/hazard_probe.gd`（`scenes/tools/HazardProbe.tscn`，窗口模式运行）逐一推进机关到
休止 / 预警 / 判定早中晚五个时刻并截图；测试见 `tests/{cyclic_hazard,collapsing_platform,force_zone,conveyor_belt,pendulum_hazard}_test.gd`。

`PlayerController.add_environment(push, drag)` 是唯一的外力入口（`ForceZone` 每个物理帧写入，
2 个物理帧没人写就当作离开区域）；不要在别处直接改玩家 `velocity` 来"推"人。

第二章到第十章的专属机关不写在各自的布局常量里。`ChapterLayout.finish()`（level02 在 `build()` 末尾）
调用 `scripts/levels/chapter_overhaul.gd` 的 `dress()`，往已经测过的地形上追加 1–2 个机关和一只变体敌人。
落点必须继续满足上面的净空；不要改已被布局测试锁住的地面坐标，也不要往 `Enemies` 里加节点。
烛光台阶（level04b）平时没有碰撞，骑士走进烛火旁边的感应圈才现形。