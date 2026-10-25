# 标题活景与 v3 版式设计（`TitleWorld` + `TitleScreen`）

> 对应任务：v3 改造 P2（标题活景 + 版式与动效重做 + `ID_ARENA` 修复）。
> 旧版"铁架异形板 + 独立档案石板 + 静态 keyart"说明见 [`docs/title-and-loadout-ui.md`](./title-and-loadout-ui.md)（其中 §0–§1.5 已标注**已被 v3 取代**）。

---

## 1. 渲染架构与场景结构

### 1.1 视口与显示链路

- **主场景**：`scenes/ui/TitleScreen.tscn`（`scripts/ui/title_screen.gd`，`class_name TitleScreen extends Control`），位于根窗口下，通过 `PresentationMetrics.bind_control(self)` 绑定到 1280×720 设计层的整数内容矩形；内容矩形外由 `WindowBackdrop/Black`（`CanvasLayer` layer `-10`）垫纯黑底边。
- **世界视口**：`TitleScreen` 内建 `WorldViewport`（`SubViewport`，640×360，`world_2d = World2D.new()`，`disable_3d = true`，`snap_2d_transforms_to_pixel = true`，`DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST`，可见时 `UPDATE_ALWAYS`、隐藏时 `UPDATE_DISABLED`）。
- **`Keyart` 节点兼容**：`Keyart` 仍为 `TextureRect`（`STRETCH_KEEP_ASPECT_COVERED`），直接显示 `WorldViewport.get_texture()`，并挂载 `assets/shaders/pixel_smooth.gdshader`（`scale_hint` 随根窗口 `size_changed` 实时更新为整数缩放倍数）。
- **静态回退**：`TitleScreen.USE_LIVE_SCENE := true`（实例开关 `live_scene_enabled`）。置为 `false` 时不创建 `WorldViewport`，同一个 `Keyart` 节点回退显示 `res://assets/kenney_clean/backgrounds/title_keyart.png` 与旧版暗角/光影/余烬。
- **时钟与音频**：标题屏保持 `WorldClock.hold_for_menu()`（退出标题屏时 `release_menu()`），显式声明 `Music.set_state(&"calm")` 与 `Music.set_theme(&"title")`；特性探测 `Sfx.has_method(&"set_title_bed")` 或 `Sfx.LIBRARY.has(&"bed_title")` 启动炉厅环境床。

### 1.2 `TitleWorld` 节点层次（640×360 世界坐标）

场景文件 `scenes/ui/TitleWorld.tscn`（`scripts/ui/title_world.gd`，`class_name TitleWorld extends Node2D`），配套组件：

- `scripts/ui/title_chain.gd`（`TitleChain`）：程序化整像素逐环绘制吊链（正面环与侧面环交替），随正弦整像素摆动。
- `scripts/ui/title_lantern.gd`（`TitleLantern extends TitleChain`）：链端挂铁笼吊灯（`assets/title/lantern.png` 两帧：灭/亮）、`PointLight2D` 与加法混合光晕 `Halo`，火苗按 12fps 阶梯闪烁。
- `scripts/ui/title_gear.gd`（`TitleGear extends Sprite2D`）：预渲染旋转帧网格（大齿轮 8×4=32 帧覆盖 45°、中齿轮 8×4=32 帧覆盖 45°、小齿轮 6×4=24 帧覆盖 60°），运行时只切帧不旋转 Sprite，严守像素网格且跨周期无缝循环。
- `scripts/ui/title_sparks.gd`（`TitleSparks extends Node2D`）：单画布项定长粒子池（零逐帧分配），承载上升余烬（`EMBER`）、下落灰烬（`ASH`）、光柱浮尘（`DUST`）、送剑锈屑（`SPECK`）、焦点/确认迸发火星（`SPARK`）以及 6 帧蒸汽团（`STEAM`）。

从远到近的图层与轨道视差深度（`depth`，骑士桥面层为 `0`，正值近景、负值远景）：

| 节点名 | Z-Index | 视差深度 `depth` | 作用与材质 |
|---|---|---|---|
| `Ambient` (`CanvasModulate`) | — | — | 全局环境底色，按变体/幕次与开屏/退场亮度插值 |
| `Void` (`Polygon2D`) | 0 | — | 铺底深色背景（`#0A080F`） |
| `HallFar` (`Sprite2D`) | 0 | `-0.30` | 远处锻厅背景（`assets/title/hall_far.png`：雾霭、双排塔影与烟囱、天车吊缆与吊斗、远景齿轮、双层栈道与竖梯、沿墙管道、远处炉口群、天窗光池） |
| `PitRiver` (`Sprite2D`) | 0 | `-0.30` | 桥下熔河（`pit_river.png`，`LIGHT_MODE_UNSHADED` 自发光，随炉温变色） |
| `RiverCurrent` (`Sprite2D`) | 0 | `-0.30` | 熔河的流动层：无缝流纹 `river_current.png`（`tools/gen_river_current.py`）经 `river_flow.gdshader` 整像素慢卷（加色、不受点光），流速与亮度随炉温 |
| `Beam` (`Sprite2D`) | 0 | `-0.20` | 天窗斜落光柱（`beam.png`，`BLEND_MODE_ADD` + `UNSHADED`） |
| `HallMid` (`Sprite2D`) | 1 | `-0.55` | 中景巨柱、下层远桥与管线（`hall_mid.png`） |
| `PitGlow` (`Sprite2D`) | 2 | `-0.10` | 桥下炉心辉光（`glow.png`，加法混合） |
| `Gears` (`GearBig` / `GearSmall`) | 2 | `+0.55` | 左侧咬合大小齿轮（`gear_big.png` / `gear_small.png`） |
| `Stage` (`Bridge` + `BridgeFront` + `Braziers` + 角色/巨剑/余烬巢) | 10 | `0.00` | 中央铁桥（`bridge.png`，桥面 `DECK_Y = 266`）；`BridgeFront`（z 5）是近侧栏杆带（`bridge_front.png`，`tools/gen_bridge_front.py` 从桥图切出），画在演员前面——骑士 / 火盆 / 余烬巢都站在栏杆后面；桥头两座火盆（§6.1）与桥上叙事主体 |
| `Chains` (`Chain0..5` + `Lantern0..4`) | 20 | `-0.10 .. +0.70` | 6 条铁链与 5 盏进度吊灯（按离骑士由近到远排列点亮顺序） |
| `FarProps` (`Crucible` / `Hammer` / `Ghosts`) | 2 | `-0.30` | 远景三件：吊运坩埚、远处锻锤、亡魂巡行（§6.1；各带一个加色 `Glow` 子节点） |
| `SwordChain` | 25 | `+0.50` | 送剑链：屋架下的传送链，剑送向炉口（§6.1） |
| `Banners` (`Banner0..1`) | 15 | `+0.30` | 两面破旗（§6.1） |
| `Roof` (`Sprite2D`) | 30 | `+0.50` | 顶部桁架与天窗裂口（`roof.png`） |
| `MassLeft` / `MassRight` (`Sprite2D`) | 40 | `+1.00` | 左右近景机械山体；右侧含自发光炉门 `ForgeMouth` 与前景齿轮 `GearFront` |
| `PitLight` / `ShaftLight` / `ForgeLight` | — | — | 3 盏环境 `PointLight2D`（连同 5 盏吊灯共 **8 盏点光**，0 阴影，符合 `≤8` 预算） |
| `Glow` (`CanvasLayer` layer `1`) | — | `-0.30 / -0.20 / +0.45` | 不受 `CanvasModulate` 压暗的 `Motes`、`Sparks`、`Souls`（魂光，加色）、`Vignette` 与入场白热 `Flash` |
| `Camera` (`Camera2D`) | — | — | 居中于 `(320, 180)`，7s 周期 `±1px` 整数像素垂直呼吸 |

---

## 2. 存档进度变体表（`TitleWorld.state_from_save()` / `configure()`）

`TitleWorld.peek_save()` 在未调用 `SaveData.load_game()` 的冷启动状态下直接只读解析内存或磁盘存档（`user://rustgrave_save.cfg` 及 `.bak`），再交由纯函数 `TitleWorld.build_state(peek)` 计算场景状态字典：

| 变体 ID (`variant`) | 触发条件 | 调色档 (`grade_id`) | 桥面主体 | 吊灯亮起数 (`lit` / 5) | 齿轮 / 炉火 / 粒子表现 |
|---|---|---|---|---|---|
| `&"cold"` | 无存档（`has_save == false`） | `&"cold"` | 骑士立于桥心（`x=326`），背负巨剑待机 | `0` | 冷灰蓝环境光、炉门微弱暗红、齿轮极慢（`0.12×`）、无蒸汽、极少余烬 |
| `&"journey"` | 有存档且无结局 | `&"act1" .. &"act4"`（按章节下标分四幕：1–3 / 4–7 / 8–11 / 12–14 章） | 骑士穿戴当前存档皮肤（`SaveData.skin_id` 或起源默认皮肤）立于桥心，背负巨剑微摆 | `ceili(cleared * 5.0 / 14.0)`（0 章为 0 盏，1–2 章 1 盏……12–14 章 5 盏） | 由第一幕冷青逐幕升温至第四幕炽热炉红；齿轮转速（`0.45× → 1.30×`）、炉火、余烬、蒸汽随幕次递进 |
| `&"give"`（还火） | `ending == "give"`（或未知非空结局回退） | `&"give"` | 骑士离去，桥心只留插地巨剑（`Greatsword.spawn_planted`） | `5`（全亮、火焰平稳 `flicker=0.15`） | 炉火温暖稳定，剑周飘浮锈屑粒子（`SPECK`） |
| `&"keep"`（守炉） | `ending == "keep"` | `&"keep"` | 骑士移至右侧炉口端（`KEEP_X = 420`），身旁点燃一座余烬巢（`EmberNest`） | `5`（全亮） | 炉火与炉口光最盛（`furnace=1.2, forge=1.3`），余烬密集升腾 |
| `&"snuff"`（熄火） | `ending == "snuff"` | `&"snuff"` | 骑士与巨剑俱无，桥面空寂 | `0`（全灭） | 炉门熄灭、齿轮停转（`0.0×`）、无余烬无蒸汽，仅桥心留一盏微弱呼吸的残红点光 |

> 通关章数判定：遍历 `GameContext.LEVEL_ORDER`（14 章），读取 `StoryFlow.DONE_FLAGS`（第一章 `boss_dead`、第二章 `undercroft_done`、其余 `levelNN_done`），或位于当前存档章节之前的章节均计为已通关。

---

## 3. 版式与动效（1280×720 设计层）

### 3.1 四大区域布局

1. **顶部字标（`MastheadColumn` / `Masthead` / `TitleLogo` + `Subtitle`）**：
   - 居中偏上（`y = 28..178`），不遮挡画面中段的铁桥与骑士。
   - 挂载 `assets/shaders/title_forge.gdshader`：开屏时斜向白热前沿从左向右扫过，量化为 4 阶像素热区（白热 → 余烬橙 → 字标本色），沿途由 `UiSparks` 迸出火星；副题「锈 墓 · 余 烬 骑 士」随后淡入。
2. **左下极简铁条菜单（`Menu`，`MenuList.strip_style = true`）**：
   - 起点 `RAIL_X = 72, RAIL_TOP = 254`，7 个 `MenuItem`（每行高 `52px` 满足触控下限），按**行动**（点燃余烬 / 继续旅程或回看余烬）、**模式**（回火试炼 / 余烬竞技场）、**系统**（设置 / 操作说明）、**离开**（离开锈墓）四组排列，组间 `16px` 留白。
   - 三档宽度递减：主行动 `344px`、模式与系统 `304px`、离开 `248px`（全部严格停在画面中线 `x = 640` 左侧）。
   - 聚焦时左侧灯口烧亮、余烬光标滑入、条上迸发火星，并联动 `TitleWorld.nudge()` 使吊灯闪亮、镜头微推 `1~2px`；再加每一行自己的场景反应（`TitleWorld.react_to`，见 §6.3）与页脚说明（§6.4）。
   - **有存档时默认选中第 2 项「继续旅程」**（索引 `1`）。有结局的存档里这一行写作「回看余烬」，选中打开总结页（`ember_recap.gd`：继续旅程 / 重温序章 · 结局 / 模式入口 / 再入某章），不再直接读档；旅程列里的「回看余烬」按钮打开同一页。
3. **右侧旅程刻度列（`JourneyColumn`）与可展开档案卡（`DossierWrap/Dossier`）**：
   - 收起态位于右侧 `Rect2(1000, 188, 208, 420)`：顶部显示通关计数 `XX / 14`、当前章节标题与两行前情提要；中段为 `TitleGauge`（14 枚章节菱形刻度，已通关亮余烬色、当前章 8fps 呼吸搏动，幕界标注「醒 / 债 / 铸 / 炉」）；底部为 2×2 `TitleChip` 数据芯片（阶 / 装 / 试 / 竞）。
   - 鼠标悬停旅程列或按 **`Tab` 键**滑出展开 `DossierWrap/Dossier`（`Rect2(820, 184, 388, 424)`），完整保留 `DossierRank`、`DossierSkin`、`DossierTrials`、`DossierArena`、`DossierChapter`、`DossierRecap`、`TrialLockHint`、`DossierFoot` 等节点。
4. **底部打字机墓志（`Inscription/EpitaphRow/Epitaph`）与页脚（`CreditBand`）**：
   - 墓志位于 `Rect2(688, 624, 520, 32)`，中心线 `y = 640` 与左下「离开锈墓」行中心线严格对齐；以 `0.085s/字` 打字机逐字显现，首句恒为 `TitleScreen.EPITAPH`（`没用上的人偶，自己先锈透了。`），停留 `5.5s` 后淡出轮换 `ChapterText.TITLE_LINES` 的句子。
   - 页脚位于 `Rect2(72, 688, 1136, 28)`：细横线之下左侧为美术/音频/字体致谢，右侧（节点 `FooterHint`，余烬色）**随菜单焦点写一句当前行的说明**（`TitleScreen.MENU_HINTS`，见 §6.4）；没有焦点 / 没有说明时回落为操作提示 `↑↓ 选择 · Enter 确认 · Tab 档案`。

### 3.2 开场、进关与退场动效

- **开场（`_play_intro`）**：`BootCurtain` 纯黑幕 0.5s 退去 → `TitleWorld.play_intro()` 吊灯按通关数逐盏点亮 → 0.45s 字标锻造扫光 + 5 次火星迸发 → 副题淡入 → 1.45s 起菜单 7 行依次向右落位（每行间隔 0.07s）→ 旅程列、墓志、页脚浮现。开场不是输入门禁，任意确认操作调用 `_skip_intro()` 立即落位终态并执行。
- **确认进关（`_confirm_effect`）**：触发 `TitleWorld.enter_push(5.0, 0.55)`（白热闪光 + 镜头向骑士推进 5px + 吊灯齐闪）+ 选中条火星迸发 + `gate` 音效 + `Director.fade_to`。
- **竞技场入口修复（`ID_ARENA`）**：在 `_on_chosen` 中接入 `_start_arena()` → `ArenaRun.start()`（支持 `arena_start` 测试接缝）；启动成功即切入竞技场，若返回 `false` 则恢复菜单激活并播放 `ui_denied`。
- **退出（`_quit_sequence`）**：菜单行自上而下逐格熄灭，活景调用 `TitleWorld.quit_out(0.2)` 将亮着的吊灯逐盏吹灭、环境光压暗，只留巨剑剪影在黑暗中微亮，随后浮现 `QuitCaption`（「余 烬 熄 灭。」）再退出；期间任意按键/点击立即调用 `_finish_quit()`。

---

## 4. 可调常量速查

### `scripts/ui/title_world.gd`

| 常量 | 默认值 | 说明 |
|---|---|---|
| `MAX_LIGHTS` | `8` | 视口内 `PointLight2D` 预算上限（3 环境光 + 5 吊灯） |
| `LANTERN_COUNT` / `CHAPTERS` | `5` / `14` | 吊灯总数与战役总章数 |
| `DECK_Y` / `KNIGHT_X` / `KEEP_X` | `266.0` / `326.0` / `420.0` | 铁桥桥面 Y、骑士默认 X、守炉结局骑士 X |
| `PARALLAX` / `POINTER_EASE` | `Vector2(9.0, 4.5)` / `3.2` | 深度 `1.0` 层的最大鼠标整像素偏移与平滑系数 |
| `BREATH_PERIOD` | `7.0` | 摄像机 `±1px` 呼吸周期（秒） |
| `GRADES` | 8 组字典 | `cold`、`act1..act4`、`give`、`keep`、`snuff` 的环境色、炉温、光柱、粒子与齿轮倍率 |

### `scripts/ui/title_screen.gd`

| 常量 | 默认值 | 说明 |
|---|---|---|
| `USE_LIVE_SCENE` | `true` | 是否启用实时像素场景（`false` 回退静态 keyart） |
| `RAIL_X` / `RAIL_TOP` / `GROUP_GAP` | `72.0` / `254.0` / `16.0` | 左下菜单列起点与组间距（离开行中心 `QUIT_CENTER_Y = 640.0`） |
| `JOURNEY_X/Y/W/H` | `1000, 188, 208, 420` | 右侧旅程刻度列矩形 |
| `CARD_RECT` | `Rect2(820, 184, 388, 424)` | 展开态完整档案卡矩形 |
| `EPITAPH_RECT` / `FOOTER_RECT` | `Rect2(688, 624, 520, 32)` / `Rect2(72, 688, 1136, 28)` | 墓志与页脚矩形 |
| `BOOT_FADE` / `LOGO_AT` / `LOGO_TIME` / `MENU_AT` | `0.5` / `0.45` / `0.95` / `1.45` | 开屏动画各阶段时间点（秒） |
| `EPITAPH_CHAR` / `EPITAPH_HOLD` / `EPITAPH_FADE` | `0.085` / `5.5` / `0.7` | 墓志打字机单字间隔、停留与淡出时长 |
| `MENU_HINTS` / `RECAP_HINT` / `FOOTER_DEFAULT` | 见 §6.4 | 页脚右侧按菜单焦点显示的一句话说明（每句 ≤ 24 字） |

### `scripts/ui/title_world.gd`（新增元素）

| 常量 | 默认值 | 说明 |
|---|---|---|
| `HAMMER_POS` | `Vector2(392, 241)` | 远处锻锤（垫墩顶面中心）所在位置 |
| `BANNER_XS` / `BANNER_TOP` | `[148, 508]` / `52` | 两面破旗的 x 与旗杆 y |
| `CLOUD_DEPTH` / `CLOUD_PERIOD` / `CLOUD_SLOW` | `0.30` / `11.0` / `0.30` | 光柱云影最深遮掉的比例 / 一次呼吸秒数 / 聚焦「设置」时的速度倍率 |
| `GAZE_FIRST` / `GAZE_PERIOD` / `GAZE_HOLD` | `7.0` / `19.0` / `4.6` | 骑士第一次转身望炉的时刻 / 之后的间隔 / 每次望多久（秒） |
| `BRAZIER_FIRST_AT` / `BRAZIER_SECOND_AT` | `1` / `7` | 通关几章点亮第一座 / 第二座火盆 |
| `REACTIONS` | 七个菜单 id | 有聚焦反应的菜单行（§6.3） |

---

## 5. 测试与工具清单

### 自动化测试

- `tests/title_world_test.gd`（19 个用例）：
  - 14 章 → 4 幕划分与通关章数 → 5 盏吊灯单调映射；
  - `build_state()` 与 `state_from_save()` 在无存档、各幕旅程、三种结局（`give`/`keep`/`snuff`）及未知结局下的取值；
  - 8 种状态（`cold`、`act1..4`、`give`、`keep`、`snuff`）全部在 headless 下构建无错，点光源数 `≤ 8`、节点数 `≤ 250`；
  - 全部皮肤（`SkinCatalog.ids()`）待机帧、染色、偏移与背负巨剑校验；
  - 各变体桥上演员切换与 `configure()` 动态热切换；
  - 齿轮整周期无缝循环、冷炉慢转与熄火停转；
  - 鼠标视差与相机呼吸严格落在整数像素；
  - 开屏逐盏亮灯、跳过开屏、退场逐盏灭灯；
  - 粒子池容量上限与连续 300 帧零节点增长；
  - `Keyart` 视口挂载、隐藏停渲、`USE_LIVE_SCENE = false` 静态回退、`bed_title` 音频特性探测。
- `tests/title_elements_test.gd`：新增元素与聚焦联动（§6）——`prop_plan` 逐变体、火盆随进度点亮且守炉最亮、各变体灯 ≤ 8 / 节点 ≤ 250 / 每件 ≤ 3 节点 / 无 `PointLight2D` / 光感是加色精灵、场景与 plan 一致、`configure()` 热切换、送剑链停空 + 魂光升出屋顶、熄火全暗全停、坩埚走 / 倒 / 回、锻锤砸坯料、送剑进炉、破旗整像素、亡魂走动、骑士转身、云影明暗、七个菜单 id 的 `react_to` 各有可观察变化且会自己衰减、页脚每个 id 有 ≤ 24 字的说明。
- `tests/journal_page_test.gd`：暂停菜单「故事」页与标题「回看余烬」总结页（内容、重看只列看过的、回放时覆盖层藏起 / 恢复、不写旗标、Esc 返回、空存档兜底句）。
- `tests/title_screen_test.gd`（21 个用例 + 回看余烬 3 个）：
  - 左下铁条菜单三档宽度、52px 触控高度、四组间距、不过中线（`< 640`）；
  - 键鼠共享同一选中态、聚焦联动活景微推与闪亮；
  - 回火试炼锁态提示、余烬竞技场 `ID_ARENA` 派发与真实 `ArenaRun.start()` 接线；
  - 旅程刻度点亮、`Tab` 展开/收起档案卡、墓志打字机轮换；
  - 离开行与墓志同基线（`y = 640`），档案卡与各区块在 `1280×720`、`1920×1080`、`2560×1080` 下零重叠且不越界；
  - 退场动画吊灯逐盏熄灭与跳过收尾。
- 关联回归套件：`tests/title_flow_adversarial_test.gd`、`tests/display_resolution_test.gd`、`tests/ui_transition_test.gd`、`tests/modal_screens_test.gd`、`tests/m5_tier5_adversarial_ui_test.gd`、`tests/character_select_test.gd`、`tests/pause_menu_test.gd`。

### 诊断与截图工具

- **几何探针**：`scenes/tools/TitleMetrics.tscn`（`tools/title_metrics.gd`），headless 打印所有区块矩形、重叠检查与多分辨率边界检查。
- **多分辨率/多变体截图工具**：`scenes/tools/TitlePeek.tscn`（`tools/title_peek.gd` + `tools/run_title_peek.ps1`），窗口模式抓取 `960×540`、`1280×720`、`1920×1080` 下 `cold / act1..act4 / give / keep / snuff` 各变体的开屏帧、空闲态与菜单聚焦态截图，输出至 `screenshots/acceptance/overhaul-v3/title/`。

---

## 6. 新增元素、预算与菜单聚焦联动（剧情分镜 · 标题活景 · 3v3 升级）

> 状态：代码与测试已写，**终端被钩子拦截，Godot 导入 / 测试 / 截图均未验证**（见交付报告）。位置、色值、速度都是按素材尺寸推算的第一版，截图验收时可能要微调（调的都是 §4 里那几个常量或各脚本顶部的 `const`）。

### 6.1 新增元素

每件 1–3 个节点（本体自己 `_draw` 整像素 + 至多一个加色 `Glow` 子节点），**一律不加 `PointLight2D`**（灯光预算已满）。共同底座 `scripts/ui/title_prop.gd`：时间自己走（`advance(dt)`，大步长拆成 ≤ 0.1s 的小步，测试直接喂 delta）、`TitleWorld` 每帧推进来 `heat`（炉温 × 开屏 / 退场亮度，≈ 0 = 冷死不动）与 `lift`（`1 / 环境色`，抵消 `CanvasModulate` 的压暗，自发光的部分乘它才读得出来）。新脚本都不加 `class_name`，`title_world.gd` 用 `preload` 常量引用。

| 元素 | 脚本 / 节点 | 位置（视差深度 / z） | 画法与行为 | 受什么影响 |
|---|---|---|---|---|
| 吊运坩埚 | `title_crucible.gd`：`Crucible` + `Glow`（2） | `FarProps`（-0.30 / 2）；导轨 y=60，装料位 x=572（躲在右侧烟囱塔后），倒料位 x=352 | 一轮约 22s：装料 → 走向熔河 → 倾转 → 倒出一道 2px 铁水柱落到河面（y=336）→ 回正 → 走回去。落河发 `poured`：溅火星 + 炉光闪 + 炉火一涌；倒的过程每 0.55s 发 `splashed`（小簇火星） | 速度 = 炉温（0.25–1.3×）；炉温 < 0.06（熄火）停在原地、不发光 |
| 远处锻锤 | `title_hammer.gd`：`Hammer` + `Glow`（2） | `FarProps`；垫墩在 `HAMMER_POS`（392, 241） | 杠杆锤，一轮 3.7s：抬起 → 保持 → 加速砸下 → 落砧（`struck`：9 粒火星 + 炉光闪）→ 反弹；砧上坯料落砧瞬间白热，随后 0.45/s 暗成橙红；`strike_now()` = 立刻敲一下。本体与锤头是烘焙贴图（`hammer_body.png` / `hammer_head.png`，`tools/gen_title_hammer.py`：锈斑 / 锈水痕 / 崩角 / 铆钉都烤在图里），运行时只贴图；杠杆臂角度每帧变，仍是代码线 | 速度 = 炉温（0.3–1.3×）；熄火不动，坯料冷 |
| 送剑链 | `title_sword_chain.gd`：`SwordChain` + `Glow`（2） | 根节点（+0.50 / 25）；导轨 y=66，x 200→462，再沿竖链垂到 y=176（被炉房外墙挡住） | 三把刻名巨剑（剑身中线 4 道刻痕，炉子烧着时发橙）等距挂在链上，约 6px/s 缓缓送向炉口；每把进炉发 `delivered`（火星 + 炉光闪 + 光团）；从导轨左端挂上时淡入 | 模式：`RUN` 运转（速度 = 炉温）/ `EMPTY` 还火结局：剑一把不剩、链停空 / `STILL` 熄火结局：剑挂着、链停住 |
| 魂光 | `title_souls.gd`：`Souls`（1，加色） | `Glow` 层（-0.30） | 16 个池，淡蓝光点从熔河（y 334–352）升起；普通 5–8s 只浮起 40–110px 就淡掉（魂还困着），**还火结局**一路升到屋顶豁口（x≈232）、顺着光柱出去 | `souls_rate`（见 §6.2）；聚焦「离开锈墓」多放 6 个 |
| 破旗 | `title_banner.gd`：`Banner0..1`（各 1，另有宿主 `Banners`） | `Banners`（+0.30 / 15）；x=148 / 508，旗杆 y=52 | 11 条 4px 横条，越往下横向位移越大（8 帧/秒一档、整像素），两侧锯齿撕口、下沿撕成四缕、半截剑徽记、下沿一道炉火烤出的暖光 | 摆幅 0.8–3.0px = 炉温；聚焦「操作说明」一阵风 +3px |
| 桥头火盆 | `title_braziers.gd`：`Braziers` + `Glow`（2） | `Stage` 里桥面之后、演员之前（z -1）；x=272 / 306，脚点 y=266（左缘躲开 mass_left 视差右推后的 x=249，右盆贴在骑士 x=326 左侧） | `assets/title/brazier_furnace.png` 下半截（`Rect2(0,60,32,36)`；`tools/gen_brazier_furnace.py` 把原素材自带的贴图火挖掉、碗口撒了炭床）+ **粒子火焰**（每盆 26 粒定长池：炉口升起、浮力加速、受穿堂风与 ~30s 周期的阵风推斜，白热核心 → 余烬 → 锈红渐冷，顶上散两粒烟）+ 加色光晕；冷盆压暗、炭里一点红 | `prop_plan.braziers`（§6.2）；聚焦「余烬竞技场」加亮（冷盆也跳起一点火） |
| 光柱云影 | 无新节点（`TitleWorld` 直接调 `Beam` 与 `ShaftLight`） | — | 两条慢正弦叠出云影：光柱 alpha 与 `ShaftLight` 能量在 `1 - 0.30 .. 1` 间起伏，一次呼吸约 11s | 聚焦「设置」放缓到 0.3×（焦点移走即恢复） |
| 亡魂巡行 | `title_ghosts.gd`：`Ghosts` + `Glow`（2） | `FarProps`；对岸栈桥 y=241，x 120→560 绕圈 | 至多 3 个披风剪影（兜帽里两点幽光、两步轮换），7px/s 往炉口方向走，右端消失在炉房后面、再从左侧机房后面绕出来；每只提一盏灯（暖光点 + 加色光晕，**不是** `PointLight2D`） | `prop_plan.ghosts`（§6.2） |
| 骑士转身望炉 | 无新节点（`Visual.scale.x` 镜像） | `Stage/Knight` | 平时**背朝炉火**（朝左）站着，开屏 7s 后第一次转身望炉，之后每 19s 一次、每次 4.6s，转身时炉光轻闪；`keep` 结局他一直朝着炉火（不转）；退场前先转回朝右（留下的巨剑剪影是没镜像的那一幅） | 仅 `cold` / `journey`（`prop_plan.knight_turns`） |

### 6.2 随存档变体的状态（`TitleWorld.prop_plan(state)`，纯函数，测试直接读）

| 变体 | 链 | 亡魂 | 魂光（名额 / 走向） | 火盆（第一座 / 第二座） | 骑士 |
|---|---|---|---|---|---|
| `cold` 无存档 | 运转（极慢） | 1 | 15%（2 个）/ 困在河上 | 冷 / 冷 | 会转身 |
| `journey` 进行中 | 运转 | `clamp(幕, 1, 3)` | `0.2 + 0.035 × 通关章数`，≤ 70% / 困在河上 | 通关 ≥ 1 章亮第一座、≥ 7 章亮第二座；亮度 0.6 → 1.0 随幕次 | 会转身 |
| `give` 还火 | **停空**（剑一把不剩） | 0 | 100%（16 个）/ **升出屋顶** | 0.9 / 0.9 稳稳亮着 | 不在 |
| `keep` 守炉 | 运转 | 3 | 30% / 困在河上 | **1.3 / 1.3 最亮** | 一直朝着炉火 |
| `snuff` 熄火 | **停住**（剑还挂着，刻痕是冷的） | 0 | 0 | 冷 / 冷 | 不在；坩埚、锻锤、旗布全停 / 垂 |

### 6.3 菜单聚焦联动（`TitleWorld.react_to(menu_id) -> bool`）

`TitleScreen._on_focus_changed` 在原有的 `nudge()`（吊灯闪一下 + 镜头推 1–2px）之后调它；开屏动画期间、以及搭菜单时默认选中那一下都不触发（`_ui_ready`）。未知 id 返回 `false`、什么都不改。聚焦持续的反应（目前只有「设置」放缓云影）在焦点移到别的行时恢复。

| 菜单 id | 行 | 场景反应 | 可观察状态（`reaction_state()`） | 衰减 |
|---|---|---|---|---|
| `new` | 点燃余烬 | 炉火一涌：坑灯 / 炉口灯 / 炉温一起涨，炉口迸 14 粒火星 | `surge` = 1 | 0.9/s |
| `continue` | 继续旅程 / 回看余烬 | 骑士转身望炉；五盏吊灯由近及远依次闪亮 | `wave_active`、`gazing` | 波 0.9s；望 4.6s |
| `trial` | 回火试炼 | 远处锻锤立刻敲一下 | `strike_requests` + 1 | — |
| `arena` | 余烬竞技场 | 桥头火盆加亮（冷盆也跳起一点火） | `brazier_boost` = 1 | 0.55/s |
| `settings` | 设置 | 光柱云影放缓到 0.3× | `cloud_target` = 0.3（`cloud_speed` 1.2/s 追过去） | 焦点移走即恢复 |
| `controls` | 操作说明 | 一阵风：两面破旗摆幅 +3px | `gust` = 1 | 0.5/s |
| `quit` | 离开锈墓 | 魂光多放 6 个、更亮 | `soul_boost` = 1、`souls().target_count()` + 6 | 0.35/s；多放的 4s |

### 6.4 页脚说明（`TitleScreen.MENU_HINTS`，每句 ≤ 24 字，`tests/title_elements_test.gd` 逐条核）

| 菜单 id | 说明 |
|---|---|
| `new` | 点燃余烬 · 选出身，开始新的旅程 |
| `continue` | 继续旅程 · 回到上次的余烬巢（有结局时写作 `RECAP_HINT`：回看余烬 · 翻看行程，重温序章与结局） |
| `trial` | 回火试炼 · 单场挑战，刷新最佳成绩 |
| `arena` | 余烬竞技场 · 3v3 推线，摧毁敌方水晶 |
| `settings` | 设置 · 音量、画面、键位与辅助 |
| `controls` | 操作说明 · 当前键位与手柄按键 |
| `quit` | 离开锈墓 · 退出游戏 |

### 6.5 预算

| 项目 | 上限 | 现状（静态估算，**未跑测试核实**） |
|---|---|---|
| `PointLight2D` | ≤ 8 | 8（3 盏环境光 + 5 盏吊灯）；新增元素 0 盏 |
| 节点总数 | ≤ 250 | 基础约 56（无演员；含 `BridgeFront` 与 `RiverCurrent`）+ 演员最多 10（守炉：骑士 5 + 余烬巢 5，巢火是 `title_flame.gd` 粒子火焰道具——本体 + Glow）+ 新增 15（`FarProps` 1 + 坩埚 2 + 锻锤 2 + 亡魂 2；送剑链 2；`Banners` 1 + 旗 2；火盆 2；魂光 1）≈ 81；`title_elements_test` 另设 ≤ 150 的余量线 |
| 每件元素 | ≤ 3 节点 | 本体 + 至多一个 `Glow`（破旗 1 个） |
| 视差基准 | 整像素 | 新宿主（`FarProps` -0.30、`SwordChain` +0.50、`Banners` +0.30、`Souls` -0.30）都走 `_register`，基准 `Vector2.ZERO`；`gears()[0]` 仍跟随调色；吊灯仍是 5 盏；菜单仍是 7 行、竞技场在索引 3 |
