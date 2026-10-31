# 标题与启程界面扩充（v3 与实物界面）

> **注意**：下文中 §0–§1.5 的旧版标题屏版式（铁架异形板 + 独立档案石板 + 静态 keyart 光影）**已被 v3 取代**。v3 实时像素活景与新版式完整设计说明见 [`docs/title-live-scene.md`](./title-live-scene.md)（本节 A 保留核心摘要，§2 起的角色选择外观条仍然有效）。

## A. v3 标题活景（P2，已取代下面 §0–§1.5 的版式）

标题屏不再是一张静态 keyart，而是**游戏内实时点光的像素场景** + 一套更轻的版式。
下面的 §0–§1.5 记录的是旧的"铁架 + 档案板"版式，留作历史；§2 起（角色选择外观条等）仍然有效。
兼容清单（测试 / 工具依赖的名字）见 A.7。

### A.1 活景：`TitleWorld`

- 文件：`scenes/ui/TitleWorld.tscn` + `scripts/ui/title_world.gd`（`class_name TitleWorld extends Node2D`），
  部件脚本 `title_chain.gd`（吊链）、`title_lantern.gd`（吊灯：点光 + 加法光晕 + 逐 12fps 的火苗）、
  `title_gear.gd`（预渲染帧的齿轮）、`title_sparks.gd`（余烬 / 飘灰 / 光柱浮尘 / 锈屑 / 蒸汽 / 火星，
  一个画布项里的定长池，零逐帧分配）。
- 渲染方式与游戏世界一致（`GamePresentation`）：`TitleScreen` 里一个 640×360 的 `SubViewport`
  （`world_2d = World2D.new()`、`snap_2d_transforms_to_pixel`、最近邻、`UPDATE_ALWAYS`；标题被隐藏时
  `UPDATE_DISABLED`），经**原来的 `Keyart` TextureRect**（`STRETCH_KEEP_ASPECT_COVERED`）+
  `pixel_smooth.gdshader`（`scale_hint` = 整数缩放，随 `size_changed` 更新）显示。
  活景里不用 `Fx` / `GameContext.world_effects()`（它们挂到 `game_world` 组 / autoload 根，视口不对），
  粒子全部自带；`Fx.additive_mat()` 只借材质。
- 层次（后 → 前，括号里是视差深度，近正远负，骑士层 = 0）：

  | 层 | 说明 |
  |---|---|
  | `FarVault` (−0.45) | 更远的冷蓝灰拱顶、烟囱与高窗光柱；纯绘制剪影与空气透视，不新增点光 |
  | `HallFar` (−0.30) + `PitRiver` | 远处炉厅（冷雾 + 屋顶开口下的天光池 + 远塔 / 吊车臂 / 熔池里的大桶）；熔河是单独的自发光层 |
  | `Beam` (−0.20) | 抖色的光柱（加法，抵消环境光后按 `shaft` 调强度） |
  | `HallMid` (−0.55) | 两根大柱、下方更远的第二座桥、悬管与悬索 |
  | `PitGlow` / `Gears` (+0.55) | 桥下熔池的辉光；大齿轮压在左柱上、小齿轮与它咬合 |
  | `Stage` (0) | 铁桥 + 骑士（`SkinCatalog` 当前外观的待机帧 + `FrameAnimSprite` + 背扛的 `Greatsword`）/ 插地巨剑 / 余烬巢 |
  | `Chains` | 6 条装饰吊链 + 5 盏吊灯（各一个 `PointLight2D`） |
  | `Roof` (+0.5) | 屋顶桁架与撕开的天窗（光柱从这里落下） |
  | `MassLeft` / `MassRight` (+1.0) | 近景机械山体：边缘朝厅内一侧带暖色边光；右山体里是炉门（自发光、随炉温变暗） |
  | `Glow`（CanvasLayer，不受环境光影响） | 远景浮尘、余烬 / 飘灰 / 蒸汽、暗角、闪光 |

  灯 ≤ 8（`PitLight`、`ShaftLight`、`ForgeLight` + 5 盏吊灯，`ForgeLight` 在"守炉"里兼作余烬巢的光、
  在"熄火"里挪到桥心变成那一点将熄的红光）。远景纵深层不增加点光；节点数由标题测试守住预算，
  本轮收尾目标为 ≤150，具体测量以测试与 walkthrough 为准。
- 摄像机：自带 `Camera2D`（呼吸 ±1px / 7s，整数）。鼠标视差是**绕骑士平面的轨道视差**：
  `位置 = 基准 − (鼠标位移 + 开屏推镜偏移) × 深度`，再 `round()` 成整数像素——骑士不动，近景向一边、远景向另一边。
  没动过鼠标时指针居中（截图 / 测试可重复）。
- 齿轮：`tools/gen_title_assets.py` 把每个齿轮渲染成**恰好一个辐条周期**的帧网格
  （大 8×4=32 帧 / 45°，中 8×4 / 45°，小 6×4=24 帧 / 60°），运行时只换帧、从不旋转 Sprite，
  转满一个周期正好回到起始帧（`tests/title_world_test.gd` 守着）。

### A.2 变体：随存档变化

`TitleWorld.state_from_save()`（纯静态，可单测）→ `peek_save()`（读内存或磁盘，不调用 `load_game()`）
→ `build_state(peek)`（纯函数）。标题启动时 `SaveData.data` 还是空的，所以按"内存里有已载入的游戏就用内存，
否则只读地看磁盘上的存档文件"取 `scene / flags / skin / rank / 属性点 / 结局`。

| 变体 | 条件 | 画面 |
|---|---|---|
| `cold` | 无存档 | 冷炉：偏冷偏暗、吊灯全暗、炉门与熔河只剩暗红、齿轮几乎不转、不冒汽，余烬将熄 |
| `journey` | 有存档、无结局 | 按**幕**调色（第 1–3 / 4–7 / 8–11 / 12–14 章 → `act1..act4`：由冷青渐暖到炉红，炉火、齿轮、余烬、蒸汽逐幕加强）；亮灯数 = `ceil(通关章数×5/14)`（通关 0 章 → 0 盏）；"通关"= 章节完成旗标（`StoryFlow.DONE_FLAGS`）或位于存档章节之前 |
| `give`（还火） | 结局 | 炉火稳而暖、灯全亮且不闪；骑士不在了，桥上只剩一把插地的巨剑和几粒飘着的锈屑 |
| `keep`（守炉） | 结局 | 骑士站在桥的炉口端朝火里看，余烬巢点着；整体更暖更亮 |
| `snuff`（熄火） | 结局 | 灯全暗、炉与齿轮熄了；骑士不在，桥心只剩一点将熄的红光 |

没见过的结局 id 按 `give`（已完成）处理。`TitleWorld.forced_state`（静态）可强制某个状态（截图工具 / 测试）。
`TitleWorld.configure(state)` 搭好之后也能切换变体（旧演员被收走）。

### A.3 版式（1280×720 设计空间）

- **字标**居中偏上（`MastheadColumn` → `Masthead` → `TitleLogo`，y=28..138）+ 副题 `Subtitle`。字标用
  `assets/shaders/title_forge.gdshader` 做"锻入"：斜向的前沿自左向右扫过，身后依次是白热 → 余烬 → 字标本色
  （热度量化成几档，保持像素风），沿途迸火星。
- **菜单** `Menu`（`MenuList`，`lamp_style`）：左下一列刻字，不画铁条。光标是 `LampCursor`，
  一盏吊灯从字标下沿垂到选中行左侧，近处的字被灯烤暖。七行 × 52px（触控下限），四组：
  行动（点燃余烬 / 继续旅程）· 模式（回火试炼 / 余烬竞技场）· 系统（设置 / 操作说明）· 离开；
  组间距 16。`RAIL_X=72`、`RAIL_TOP=254`，"离开"行中心 y=640。
  刻字后方 `MenuShade` 用羽化烟雾压暗局部管线；字加 1px 暗描边。回火试炼未解锁时，
  「第七章后解锁」挂在行下方的 `LockTag` 小铁签上（6px 短链 + 10px 小字），不再写在行右端。
  `TitleLampCursor` 的已有 12×17 灯帧放大到 3 倍（36×51 设计像素），暖光衰减半径为 136px；
  选中行比邻行暖，字形保持原尺寸。
  聚焦（键盘 / 悬停）：灯闪一下，并在灯位迸一簇火星（`UiSparks`，`TitleSparks` 放大两倍落在 2px 栅格上）+
  场景吊灯一闪、镜头整体推 1–2px（`TitleWorld.nudge`）+ 这一行在炉厅里自己的反应
  （`TitleWorld.react_to`：炉火一涌 / 锻锤敲一下 / 火盆加亮 / 云影放缓 / 破旗一掀 / 魂光升起，见
  [`title-live-scene.md`](./title-live-scene.md) §6.3）。
  有结局的存档里第二行写作「回看余烬」，选中**打开总结页**（`ember_recap.gd`，OrnatePanel 卡片 + `MenuList`）：
  继续旅程 / 重温序章 / 重温结局（`Boards.replay_list`，回放时总结页先藏起来、播完恢复）/ 余烬竞技场 /
  回火试炼（未解锁置灰）/ 返回 / 再入某章（已通关章节按 `StoryFlow.DONE_FLAGS` 数；从该章入口出生点出发）。
  旅程列里的「回看余烬」按钮（`RecapButton`）随时打开同一页（悬停 / 聚焦时页脚写它的说明、左缘迸火星）。
  按钮外观是 `RecapStrip` 画的一行刻字（聚焦时左端一粒余烬、字变成暖色）。旅程列的 `TitleChip` 同样不铺底板。
  总结页是半透明玻璃卡（`CARD_ALPHA = 0.78`，外壳与档案板同一透明度），打开时标题菜单淡出 0.22s、关闭时淡回：
  左列是铁条菜单（题头「行程入口」，可滚动，与上方题头同一条左缘）；右侧是**旅程档案板**（`DossierCard`，题头「旅程档案」）：
  结局印记（`SealMark`，颜色随结局：还火金 / 守炉橙 / 熄火灰紫，没有结局是暗铜空章）→ 结局标题 → 前情 → 章节刻度条
  （`ChapterRail`，每章一粒菱形，已通关烧成余烬，幕间立竖线）→ 已过章数 → 结局三格（看过的亮出名字，没见过的写「？？」）。
  前情不再放在滚动区里：列表滚动时它不跟着走，章节行不会被它顶到折叠线以下。
  打磨细节：标题屏的灯用弹簧落到选中行，并按垂直速度轻轻荡开；确认时字上扫过一道白热闪光（`MenuItem.flash()`）。
  总结页等仍用铁条的菜单：选中条右移 4px、条外一圈炉温光晕。禁用行（未解锁的试炼）悬停时页脚交代解锁条件；
  页脚说明换行走交叉淡入淡出；副题两侧有余烬菱形饰（`SubtitleFlanks`）；字标锻入收尾有一道落锤白热；
  墓志句垫柔和底衬、顶部一道锈线（右端余烬钉）；菜单落位用 `TRANS_BACK` 带回弹。
- **旅程短注** `JourneyColumn`（x=1000..1208，y=188..280，高 92）：`JourneyHeader` / `JourneyCount`（`04 / 14`）、
  当前章名 `JourneyChapter`、横向 `JourneyGauge`（14 格，跟吊灯一起呼吸）、`RecapButton`（回看余烬）。
  平时淡，焦点在「继续旅程」上才亮。阶位 / 外观 / 试炼 / 竞技场不折在标题上。
- **档案卡**：悬停旅程列或按 **Tab** 展开（再按 Tab / 移开收起）。节点名沿用旧版：`DossierWrap`（`TitleCard`）→
  `Dossier`（PanelContainer）→ `DossierRank / DossierSkin / DossierTrials / DossierArena / DossierChapter`、
  `DossierRecap`、`TrialLockHint`（未解锁时）、`DossierHint`、`DossierFoot`。平时收起（不可见，但节点与文字都在）。
- **墓志** `Inscription/EpitaphRow/Epitaph`：底部一行，**慢速打字机轮换**（每字 0.085s、停 5.5s、淡出换句），
  第一句永远是 `EPITAPH`，其余取 `ChapterText.TITLE_LINES`。右端对齐到右边距，
  与"离开"行同一条中心线（y=640）。
- **页脚** `CreditBand`：署名靠左，右侧 `FooterHint` 随菜单焦点写**当前行的一句说明**
  （`TitleScreen.MENU_HINTS`，每句 ≤ 24 字，例如竞技场行「余烬竞技场 · 3v3 推线，摧毁敌方水晶」；没有焦点时回落为操作提示），
  一行小字，没有边框底板；`FooterShade` 从 y=648 渐暗到屏幕底缘，致谢缩成
  「致谢 ansimuz · Kenney · Fusion Pixel」，避开熔河亮色。`UpdateNotice`（有新版本时）在页脚上方。
- 不重叠保证：`tests/title_screen_test.gd` 在 1280×720 / 1920×1080 / 2560×1080（非 16:9）三种窗口里，
  把每个窗口的 UI 变换套上，量 `Masthead / Subtitle / Menu / JourneyColumn / Epitaph / CreditBand /
  UpdateNotice` 的物理像素：两两不重叠、都落在内容矩形里；展开的档案卡不压字标 / 菜单 / 墓志。
  几何探针：`tools/title_metrics.gd`（`scenes/tools/TitleMetrics.tscn`）。

### A.4 动效

- **开屏**（小于 3 秒，不是输入门禁，`_skip_intro()` 一把跳过）：黑幕退去，从远厅拱顶向桥面推进
  （`DOLLY_FROM=(0,-26)`，1.6 秒缓出，幅度随 `Settings.shake_scale`）→ 吊灯由远及近按亮灯数点亮
  （`TitleWorld.play_intro`）→ 镜头落位时字标锻入 + 火星 → 副题淡入 → 菜单逐条落位（淡入 + 左移 28px 归位）→
  旅程列 / 墓志 / 页脚收尾，墓志开始打字。
  跳过时 `_dolly` 立即归零、视差层落在整像素；不留下仍在改位置的开屏 tween。
- **确认入场**（继续 / 新游戏 / 试炼 / 竞技场）：白热闪光 + 镜头朝骑士前推 5px（近景向外、远景向内）+
  吊灯一闪 + 选中条上一簇火星 + `Director.fade_to`（保持原有淡出换关）。
- **离开**（`_quit_sequence`）：菜单条逐格熄灭，吊灯一盏盏灭掉（每盏 0.2s），整个炉厅暗下去，
  只剩巨剑的剪影在黑里亮着，然后浮出"余 烬 熄 灭。"再退出；任何按键 / 点击跳到退出。
- 音频钩子：`Sfx.has_method(&"set_title_bed")` 才调用（标题打开 `true`，`_exit_tree` 里 `false`），
  本任务不生成音频。

### A.5 `USE_LIVE_SCENE` 回退

`TitleScreen.USE_LIVE_SCENE`（常量，默认 `true`）；实例变量 `live_scene_enabled` 默认取它（测试在 `add_child`
之前改）。置 `false`：同一个 `Keyart` 节点显示旧的静态 `title_keyart.png`，不建视口，旧的暗角 / 骑士光影 /
余烬 / 角饰照旧（`keyart_knight_light.gd` 只在回退模式用），新版式、开屏与离开动画照常走。

### A.6 竞技场入口修复

以前 `_on_chosen` 没有 `ID_ARENA` 分支（按了没反应）。现在：`_menu.active = false` → `Sfx.play(&"gate")` →
确认特效 → `ArenaRun.start()`（失败则还给玩家菜单并播拒绝音）。`TitleScreen.arena_start`（Callable）是测试接缝，
默认走真正的 `ArenaRun.start()`。

### A.7 兼容清单与资产

- 场景 `res://scenes/ui/TitleScreen.tscn` 仍是主场景；常量 `ID_NEW / ID_CONTINUE / ID_TRIAL / ID_ARENA /
  ID_SETTINGS / ID_CONTROLS / ID_QUIT / ID_KEEP / ID_OVERWRITE / ID_UPDATE`、`RAIL_X / RAIL_TOP`；
  公共 API `intro_playing() / is_quitting() / quit_finished() / quit_on_finish / open_confirm() /
  close_confirm() / confirm_open() / character_select_screen() / _on_chosen(id) / _on_confirm_chosen(id)`；
  节点 `Menu`（七个 `MenuItem`，id 与档位不变）、`Keyart`、`Masthead`、`MastheadColumn`、`Inscription/EpitaphRow/Epitaph`、
  `Dossier*`、`TrialLockHint`、`QuitCaption`、`ConfirmMenu`、`OverwriteConfirm`、`WindowBackdrop/Black`、
  `CreditBand`、`BootCurtain`。继续格默认选中（有存档时）。
- 新增只读句柄：`world()`、`look()`、`design_rect(control)`、`dossier_open()`、`epitaph_line()`、
  `recap_page()`、`recap_open()`、`footer_hint_text()`；静态 `TitleScreen.hint_for(id)`、
  `TitleScreen.chapter_entry_spawn(chapter_id)`（再入某章的落点：第一、二章用 `ENTRY_SPAWN_OVERRIDES`，
  其余读各章 layout 的 `entry_spawn()`；`tests/title_screen_test.gd` 对照源常量防漂移）。
- 暂停菜单（`PauseMenu`）新增第七格「故 事」（`ID_STORY`，紧跟在「地图」后面）：`journal_screen.gd` 的覆盖层，
  四页——现在（所在章节 + 现在要做什么 + 前情）/ 人物 / 名词 / 重看（`Boards.replay_list(存档旗标)`，只列看过的，
  选一项回放；回放时本页与暂停卡片先藏起来，播完恢复，不写「看过」旗标）。人物与名词只列已出场的（`ChapterText.CAST_FIRST_CHAPTER` / `TERM_FIRST_CHAPTER`）。←→ 或手柄肩键切页，↑↓ 滚动 / 选择，Esc 返回。
  没通关任何一章用 `StoryFlow.RECAP_FALLBACK`；标题回看页与故事页共用 `board_replay.gd` 接线。
- 资产生成：`python tools/gen_title_assets.py`（可带子集名，如 `gears hall`）→ `assets/title/*.png`；
  工具库 `tools/title_px.py`、场景层 `tools/gen_title_hall.py`。新增 / 重生成 PNG 之后要跑一次
  `godot --headless --path . --import`。
- 截图：`tools/run_title_peek.ps1`（`tools/title_peek.gd`）窗口模式抓开屏帧 / 空闲 / 聚焦 / 各变体 / 多尺寸，
  存档与设置都隔离在输出目录下（`APPDATA` 也被重定向）。证据目录 `screenshots/acceptance/overhaul-v3/title/`。

### A.8 二级界面：炉厅里的六件实物

`ui_modal.gd` 的 `object` 选项由 `ui_object.gd` 选择运行时材质：暂停吊挂铁牌（1020×640）、
设置锻炉账簿（960×560）、地图铁板（1120×640）、操作说明四张纸（1120×620 的透明载体）、
教程随身手札（880×580）和覆盖确认封蜡信笺（640×420）。这些是 `Modal.build` 的设计尺寸，
最终布局仍受容器与显示适配控制。完整材质、选中语言及进退场规则见 [ui-language.md](./ui-language.md)。

铁牌复用标题吊灯；书页使用墨水目录、黄铜珠滑条与开关印章；纸页不透明，键帽印成小铅字。
四纸按 0.06 秒错峰落位，地图四角钉子按顺序固定，确认时蜡封短暂白热。背景用屏幕拷贝、
轻微模糊与低于 0.8 alpha 的纱幕，保留底下炉厅／战场；不新增 PNG 或 `PointLight2D`。
位移取整，正文不做缩放与旋转。

兼容节点 `ModalRoot/Card/Content/Body/...`、设置的 `slider_for / tab_button / toggle_for / key_button_for`
及 `ConfirmMenu` 保持。确认覆盖默认仍选取消，确认后先打开角色选择，真正启程才沿原流程创建新存档。
HUD、角色选择、装备、试炼与故事／日志维持既有外观；下面 §2 的外观条接口继续有效。

## 0. 标题屏菜单架（已被 v3 取代）

> **历史记录，不代表当前版式**：当前为左下刻字 + 吊灯光标（`MenuList.lamp_style = true`），详见上文 A.3 与 [`title-live-scene.md`](./title-live-scene.md)。

七格，按"行动 / 模式 / 系统 / 离开"分组：

1. 点燃余烬（主行动箭头板）
2. 继续旅程（主行动箭头板，无存档置灰）
   —— 铆钉横线 ——
3. 回火试炼（模式组，燕尾次档板；未解锁置灰）
4. 余烬竞技场（模式组，燕尾次档板）
5. 设置
6. 操作说明
7. 离开锈墓（角标 ghost）

整架 `RAIL_TOP=220`、间距收紧（12/10/6/16/6/12），底部不再压署名带。
试炼解锁提示从架下（会压署名带）挪进右侧档案并自动换行。
"有新版本"不再动态插入菜单架（第 8 行会把整架顶出屏幕），改为档案里一个小号
「有新版本 · 查看」按钮；档案长文本（上次行程复述）单行省略。

## 1. 标题屏：右侧「行程档案」（已被 v3 取代）

> **已被灯标短注取代**：右侧是一条淡的 `JourneyColumn`（横向 14 格 + 章名 + 回看），悬停或按 `Tab` 才展开完整档案卡 `DossierWrap/Dossier`。详见 [`docs/title-live-scene.md`](./title-live-scene.md)。

`title_screen.gd` 在原有"字标 + 左侧铁架 + 墓志/署名带"之外新增 `Dossier` 石板（右侧，StonePanel）：

- **余烬阶位**：`EmberRank.summary(SaveData.ember_xp)` + 可分配点数；无存档显示占位文案。
- **当前外观**：`SkinCatalog.name_of(SaveData.skin_id)`。
- **回火试炼**：读 `TrialRecords.all()` 的记录条数。
- **余烬竞技场**：`ArenaRun.read_records()` 的最佳分 / 场次（未玩过显示"未踏足"）。
- **上次行程**：存档 scene → `GameContext.LEVELS` 反查章节 → `ChapterText.recap_of()`（没有 recap 用标题）。
- 底部一行提示：Tab / Esc / 存档点在烬巢；有版本时下方出现小号「有新版本 · 查看」。

节点名（测试/后续扩展）：`Dossier`、`DossierRank`、`DossierSkin`、`DossierTrials`、`DossierChapter`。
无存档时面板不隐藏，四行都显示占位，避免标题屏"空"。

## 1.1 右栏与左栏的构图呼应

- 档案不再是"一块石头板 + 几行字"：外层 `DossierWrap` 定位，**左边立一根竖脊**
  （`DossierSpine`，与左侧铁架的脊同款：2px 锈线 + 端头铆钉 + 中段菱形铁花）；
- 每行标签前挂 10×2 的横钉（`Tick*`），与 MenuItem 的选中 tick 同一语汇；
- 标题行左右各一道 `stub_rule` 短角铁，下面一条 `rivet_rule` 铆钉横线；
- 底部弹性留白后收一道 `stub_rule` + “档案随存档更新”小注，和铁架底部收口呼应；
- 档案顶部与左架对齐（都从 `RAIL_TOP=220` 开始）；**右边缘到屏幕的距离 = 左栏脊到屏幕的距离（`SPINE_X=92`）**：
  面板落在 x 828..1188，两列左右对称；
- 面板高度 344（底 564），压在墓志条（590 起）上方，保证右下角「失败的净化偶，自己先锈透了。」
  完整显示；内容最小高度 268，行/试炼提示/更新提示/收口小注都放得下；
- 档案行值单行省略；阶位行压成“4 阶 · 灰烬骑士 · 点 3”，不再被裁成省略号。

## 1.2 按背景构图优化

keyart 的结构是：中央天井光柱 + 左右垂链 + 两侧齿轮/管线 + 中段铁桥。布局据此做了三件事：

1. **两列都从"天花板梁"垂下来**：左菜单架和右档案各加一根 `Ornaments.chain()`
   （2px 长短环交替 + 上下吊扣，纯代码绘制，不新增贴图），链底接各自竖脊，
   和背景里的垂链同语汇；
2. **光影方向一致**：光从天井中央打下来，所以左列影子落向左、右列影子落向右
   （`RailShadow` / `DossierShadow`，黑色 26–28% alpha、偏移 5–6px），
   不再像两块平贴在画上的板；
3. **用画面边界对齐**：左架右缘贴住光柱左缘、右档案左缘贴住光柱右缘，
   中段留给骑士与铁桥；两列同顶（224）同底（568）、左右外边距都是 92。

## 1.2.1 重叠修复（重要）

- 并行改动曾把 `Plate.Shape.DOSSIER` 高度改到 **402**、右栏 wrap 同步拉长，
  导致右栏底边（y=626）压住右下的墓志句（y=590..622）——就是画面上的"UI 重叠"。
- 已把板高恢复 **344**、wrap 高恢复 344、竖脊 308；右栏底停在 **544**，
  墓志顶在 **590**，中间留 46px；底注内缩到板内 8px。
- 新增回归测试 `test_no_overlap_between_dossier_and_epitaph()`：
  断言右栏底不越过墓志顶、`DossierFoot` 完整落在右栏矩形内；
  `test_quit_aligns_with_epitaph()` 继续守住 606 基线。
- 行距 8→12、底部 content margin 22→26，右栏下半段不再空一大截。

## 1.3 布局续调：底行动对齐墓志 + 右栏参差边缘

- **"离开锈墓"下移**：操作说明后加一段 20px 空隙 + 一道 260px 短锈线，再留 52px，
  让 ghost 行动的中心落在 **606**，与右下墓志句中心（590..622）**同一基线**；
  左侧 `title_screen_test` 新增 `test_quit_aligns_with_epitaph` 锁住这个约束。
- **右栏左缘参差**：`scripts/ui/dossier_jag.gd` 在板身左缘（x=68 之外）再画两块
  箭头状铁舌（82–140px / 236–294px，最远伸出 38/26px），黑边 + 锈边 + 抖动内芯 +
  尖端余烬铆钉，和主板自带的 44px 大箭头拼成参差轮廓，照应左架的主/次/ghost 板；
  铆钉以 3.6s 呼吸，只重绘这个装饰层，不重绘板身。
- 右栏内容底部加弹性留白，"档案随存档更新"压到板底边，不再悬在中段。

## 1.4 动画适配

- **吊链摆动**：两条 `Ornaments.chain` 以 0.65 rad/s、±2px 的整数像素横移，
  像素链环不发虚；`_process` 在开屏期间也跑，所以淡入时链子就是活的。
- **开屏**：链条 / 右栏 / 右栏脊 / 参差铁舌 / 骑士光影与脊柱同一批（`BOOT_FADE*0.9`）
  淡入，不再"啪"地出现；`_skip_intro()` 用 `Transitions.snap_visible` 一次落位。
- **退场**：`_quit_sequence` 本来就把 TitleScreen 的直系画布子树一起压暗，
  新增的右栏/链/骑士光/铁舌都在其中，逐格熄灭 + 黑幕节奏不变。
- **持续光影**：骑士暖雾/高光/光柱浮尘 4.8s 呼吸，铁舌铆钉 3.6s 呼吸。

## 1.5 不规则右栏 + 中央骑士光影（已被 v3 取代）

> **已被 v3 取代**：`keyart_knight_light.gd` 仅在 `TitleScreen.USE_LIVE_SCENE = false` 回退模式下启用；默认由 `TitleWorld` 实时像素场景渲染。

- **右栏不再用方板**：`Plate.Shape.DOSSIER`（340×344，切角 14，右端箭头凸起 44）
  生成整块大板贴图，`flip_h` 后箭头朝画面中央，与左架主板右向箭头互为镜像；
  右缘仍落在 92px 对称线上，阴影也用同一张板形（`DossierShadow`，偏移 6,7）。
  内容区由透明 `PanelContainer` 按 `arrow + 18` 内缩，节点名/测试口径不变。
- **中央骑士光影**：`scripts/ui/keyart_knight_light.gd`，纯代码绘制、不新增贴图：
  - 背后三层像素暖雾（阶梯椭圆，4.8s 呼吸）；
  - 剑尖/肩头呼吸高光 + 一道很淡的大轮廓光；
  - 天井光柱两缕边光 + 光柱里缓慢明灭的浮尘；
  - 铁桥上的三层落影（压暗椭圆）。
  叠放顺序：keyart → 暗角 → 骑士光影 → 前景余烬 → 标题/菜单，保证光在 UI 之下、余烬之上。

## 2. 角色选择：外观条（皮肤 + 刻印进 loadout）

`character_select_screen.gd` 底部新增 `AppearanceStrip`（两行）：

- `SkinRow`：4 个皮肤按钮（`SkinBtn_<id>`）；默认皮肤跟随当前起源，手动选过之后不再被起源切换覆盖。
- `RuneRow`：`无` + 4 个刻印按钮（`RuneBtn_<id>` / `RuneBtn_none`）。
- 选择写进 `get_selected_loadout()` 的 `skin` / `rune`；`embark_requested` 带出，
  标题屏 `_on_char_select_embark` 在 `init_new_game` 之后 `SaveData.set_skin()` + `persist_profile()`。
- 卡片高度 646 → 700，外观条两行各 26px，不压 footer 按钮。

## 3. 测试与截图

- `tests/appearance_ui_test.gd`：外观条节点齐全、默认跟随起源、选择进 loadout、启程信号带 skin/rune。
- `tests/title_screen_test.gd` 新增：有存档时档案显示 4 阶/皮肤名/试炼行/章节行；无存档时占位。
- 本轮实物交互回归新增 `tests/physical_secondary_test.gd`；模态路径、暂停状态与设置控件接口由对应专项测试守住。
- 旧版截图：`screenshots/peek/v3-ui/title_dossier.png`、`char_select_appearance.png`。本轮通过数与截图证据见本轮 walkthrough，旧版记录不作为本轮验收结果。
