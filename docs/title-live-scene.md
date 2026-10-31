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
- `scripts/ui/title_lantern.gd`（`TitleLantern extends TitleChain`）：14 个链端铁笼吊灯（`assets/title/lantern.png` 灭/亮两帧）均保留加法光晕；其中 5 个使用 `PointLight2D` 光池，火苗按 12fps 阶梯闪烁。
- `scripts/ui/title_gear.gd`（`TitleGear extends Sprite2D`）：预渲染旋转帧网格（大齿轮 8×4=32 帧覆盖 45°、中齿轮 8×4=32 帧覆盖 45°、小齿轮 6×4=24 帧覆盖 60°），运行时只切帧不旋转 Sprite，严守像素网格且跨周期无缝循环。
- `scripts/ui/title_sparks.gd`（`TitleSparks extends Node2D`）：单画布项定长粒子池（零逐帧分配），承载上升余烬（`EMBER`）、下落灰烬（`ASH`）、光柱浮尘（`DUST`）、送剑锈屑（`SPECK`）、焦点/确认迸发火星（`SPARK`）以及 6 帧蒸汽团（`STEAM`）。

从远到近的图层与轨道视差深度（`depth`，骑士桥面层为 `0`，正值近景、负值远景）：

| 节点名 | Z-Index | 视差深度 `depth` | 作用与材质 |
|---|---|---|---|
| `Ambient` (`CanvasModulate`) | — | — | 全局环境底色，按变体/幕次与开屏/退场亮度插值 |
| `Void` (`Polygon2D`) | 0 | — | 铺底深色背景（`#0A080F`） |
| `FarVault` (`Node2D`) | 0，先绘制 | `-0.45` | 冷蓝灰远厅拱肋、两座烟囱、三扇高窗与三道光柱；2px 栅格，6fps 更新，无子节点或点光源 |
| `HallFar` (`Sprite2D`) | 0，后绘制 | `-0.30` | 远处锻厅背景（`assets/title/hall_far.png`）；运行时 shader 只让上方暗色空气透出更远的拱厅，保留亮桁架和下方暖厅 |
| `FarHaze` (`Node2D`) | 0 | `-0.42` | 薄雾、远窗和 y=340→180 向上渐隐的暖反光，连接冷远景与熔河 |
| `PitRiver` (`Sprite2D`) | 0 | `-0.30` | 桥下熔河（`pit_river.png`，`LIGHT_MODE_UNSHADED` 自发光，随炉温变色） |
| `Beam` (`Sprite2D`) | 0 | `-0.20` | 天窗斜落光柱（`beam.png`，`BLEND_MODE_ADD` + `UNSHADED`） |
| `HallMid` (`Sprite2D`) | 1 | `-0.55` | 中景巨柱、下层远桥与管线（`hall_mid.png`） |
| `PitGlow` (`Sprite2D`) | 2 | `-0.10` | 桥下炉心辉光（`glow.png`，加法混合） |
| `Gears` (`GearBig` / `GearSmall`) | 2 | `+0.55` | 左侧咬合大小齿轮（`gear_big.png` / `gear_small.png`） |
| `Stage` (`Bridge` + 角色/巨剑/余烬巢) | 10 | `0.00` | 中央铁桥（`bridge.png`，桥面 `DECK_Y = 266`）与桥上叙事主体 |
| `Chains` (`Chain0..5` + `Lantern0..13`) | 20（吊灯局部 `+25`） | `-0.10 .. +0.70` | 6 条装饰铁链与 14 盏进度吊灯；灯笼排在世界 `x=80..483`、顶 `y=38`，置于前景机壳前，避开 Logo/菜单/右栏；每通关一章点亮一盏 |
| `Roof` (`Sprite2D`) | 30 | `+0.50` | 顶部桁架与天窗裂口（`roof.png`） |
| `MassLeft` / `MassRight` (`Sprite2D`) | 40 | `+1.00` | 左右近景机械山体；右侧含自发光炉门 `ForgeMouth` 与前景齿轮 `GearFront` |
| `PitLight` / `ShaftLight` / `ForgeLight` | — | — | 3 盏环境光与 5 个吊灯光池共 **8 盏点光**；光柱、炉门及 2 个吊灯光池开启阴影，桥身/炉柱/骑士有真实 `LightOccluder2D` |
| `Glow` (`CanvasLayer` layer `1`) | — | `-0.20 / +0.45` | 不受 `CanvasModulate` 压暗的 `Motes`、`Sparks`、`Vignette` 与入场白热 `Flash` |
| `Camera` (`Camera2D`) | — | — | 居中于 `(320, 180)`，7s 周期 `±1px` 整数像素垂直呼吸 |

---

## 2. 存档进度变体表（`TitleWorld.state_from_save()` / `configure()`）

`TitleWorld.peek_save()` 在未调用 `SaveData.load_game()` 的冷启动状态下直接只读解析内存或磁盘存档（`user://rustgrave_save.cfg` 及 `.bak`），再交由纯函数 `TitleWorld.build_state(peek)` 计算场景状态字典：

| 变体 ID (`variant`) | 触发条件 | 调色档 (`grade_id`) | 桥面主体 | 吊灯亮起数 (`lit` / 14) | 齿轮 / 炉火 / 粒子表现 |
|---|---|---|---|---|---|
| `&"cold"` | 无存档（`has_save == false`） | `&"cold"` | 骑士立于桥心（`x=326`），背负巨剑待机 | `0` | 冷灰蓝环境光、炉门微弱暗红、齿轮极慢（`0.12×`）、无蒸汽、极少余烬 |
| `&"journey"` | 有存档且无结局 | `&"act1" .. &"act4"`（按章节下标分四幕：1–3 / 4–7 / 8–11 / 12–14 章） | 骑士穿戴当前存档皮肤（`SaveData.skin_id` 或起源默认皮肤）立于桥心，背负巨剑微摆 | `clampi(cleared, 0, 14)`，精确 N/14 | 由第一幕冷青逐幕升温至第四幕炽热炉红；齿轮转速（`0.45× → 1.30×`）、炉火、余烬、蒸汽随幕次递进 |
| `&"give"`（送剑） | `ending == "give"`（或未知非空结局回退） | `&"give"` | 骑士离去，桥心只留插地巨剑（`Greatsword.spawn_planted`） | `14`（全亮、火焰平稳 `flicker=0.15`） | 炉火温暖稳定，剑周飘浮锈屑粒子（`SPECK`） |
| `&"keep"`（守火） | `ending == "keep"` | `&"keep"` | 骑士坐在右侧炉边铁凳（`KEEP_X = 420`），使用各皮肤独立的 48×48 坐姿；旁有余烬巢（`EmberNest`） | `14`（全亮） | 炉火与炉口光最盛（`furnace=1.2, forge=1.3`），余烬密集升腾 |
| `&"snuff"`（熄灭） | `ending == "snuff"` | `&"snuff"` | 骑士与巨剑俱无，桥面空寂 | `0`（全灭） | 炉门熄灭、齿轮停转（`0.0×`）、无余烬无蒸汽，仅桥心留一盏微弱呼吸的残红点光 |

> 通关章数判定：遍历 `GameContext.LEVEL_ORDER`（14 章），读取 `StoryFlow.DONE_FLAGS`（第一章 `boss_dead`、第二章 `undercroft_done`、其余 `levelNN_done`），或位于当前存档章节之前的章节均计为已通关。

---

## 3. 版式与动效（1280×720 设计层）

### 3.1 四大区域布局

1. **顶部字标（`MastheadColumn` / `Masthead` / `TitleLogo` + `Subtitle`）**：
   - 居中偏上（`y = 28..178`），不遮挡画面中段的铁桥与骑士。
   - 挂载 `assets/shaders/title_forge.gdshader`：开屏时斜向白热前沿从左向右扫过，量化为 4 阶像素热区（白热 → 余烬橙 → 字标本色），沿途由 `UiSparks` 迸出火星；副题「锈 墓 · 余 烬 骑 士」随后淡入。
2. **左下刻字菜单（`Menu`，`MenuList.lamp_style = true`）**：
   - 起点 `RAIL_X = 72, RAIL_TOP = 254`，7 个 `MenuItem`（每行高 `52px` 满足触控下限），按**行动**（点燃余烬 / 继续旅程或回看余烬）、**模式**（回火试炼 / 余烬竞技场）、**系统**（设置 / 操作说明）、**离开**（离开锈墓）四组排列，组间 `16px` 留白。刻字下方是羽化的 `MenuShade` 烟斑，中心约压暗 35%，没有硬面板边。
   - 三档宽度递减：主行动 `344px`、模式与系统 `304px`、离开 `248px`（全部严格停在画面中线 `x = 640` 左侧）。宽度是触控区，不是条身。
   - 光标是 `LampCursor`：一根链子从字标下沿垂下来，36×51px 的灯笼停在选中行左侧，252px 暖光池随确认闪光扩大。离灯近的字被烤暖，136px 外光照归零，选中行底下一条烧着的细线。聚焦时灯闪一下、迸火星，并联动 `TitleWorld.nudge()` 使厅里的吊灯闪亮、镜头微推 `1~2px`。
   - 锁定试炼的解锁条件放在该行下沿的 `LockTag` 小铁签里，不再挤在行右端；锁定行保留清晰冷灰字和 1px 暗描边。
   - **有存档时默认选中第 2 项「继续旅程」**（索引 `1`）。
3. **右侧旅程刻度列（`JourneyColumn`）与可展开档案卡（`DossierWrap/Dossier`）**：
   - 收起态是右上一条短注 `JourneyColumn`（`Rect2(1000, 188, 208, 92)`），平时很淡，焦点停在「继续旅程」才亮，并跟厅里 14 盏吊灯同一档呼吸。内容只有四行：`旅 程` + `04 / 14`、当前章名、`TitleGauge` 的横向 14 格（`use_horizontal()`，幕界仍用 `ACT_STARTS`，亮格数和当前格的接口不变）、`回看余烬`。没有竖排章号，也没有 `ChipRank / ChipSkin / ChipTrials / ChipArena`。阶位、外观、试炼、竞技场只在 Tab 展开的档案卡里。无存档时章名是「尚无旅程」，14 格全冷。
   - 鼠标悬停旅程列或按 **`Tab` 键**滑出展开 `DossierWrap/Dossier`（`Rect2(820, 184, 388, 424)`），完整保留 `DossierRank`、`DossierSkin`、`DossierTrials`、`DossierArena`、`DossierChapter`、`DossierRecap`、`TrialLockHint`、`DossierFoot` 等节点。
4. **底部打字机墓志（`Inscription/EpitaphRow/Epitaph`）与页脚（`CreditBand`）**：
   - 墓志位于 `Rect2(584, 624, 404, 32)`，中心线 `y = 640` 与左下「离开锈墓」行中心线对齐。没有底板、顶线和钉子，只有右下炉影里一块径向暗斑，字本身压得很淡。以 `0.085s/字` 打字机逐字显现，首句恒为 `没用上的人偶，自己先锈透了。`，停留 `5.5s` 后淡出轮换。
   - 页脚位于 `Rect2(72, 688, 1136, 28)`：致谢缩成「致谢 ansimuz · Kenney · Fusion Pixel」，文字 alpha 0.72；`FooterShade` 从 y=648 到底部渐暗，压住熔河亮纹。右侧导航提示仍是余烬色。标题屏不用四角角标；上下是一层软渐变，不再用左右硬遮罩。字标底下在活景里加一张加色光斑（`LogoWash`，`glow.png`），不新增 `PointLight2D`。

### 3.2 开场、进关与退场动效

- **开场（`_play_intro`）**：黑幕 0.5s 退去；视差推镜从 `DOLLY_FROM=(0,-26)` 在 1.6s 内降到桥面，所有图层每帧取整。0.30s 起，当前进度允许点亮的吊灯按短链高灯→长链低灯依次亮起（每盏 0.16s）。1.60s 落位时闷锤响起、字标开始 0.80s 锻入并迸五簇火星；1.95s 起菜单逐行落位（间隔 0.07s、单行 0.26s），旅程列与页脚跟上，整段约 2.8s。任意键盘、鼠标按下或手柄按钮在 `_input` 阶段立即跳过，同一次输入仍交给菜单。`skip_intro()` 同步杀掉推镜 tween、清零 `_dolly`、恢复存档灯数。
- **舒适性**：新增推镜、鼠标视差和镜头呼吸跟随 `Settings.shake_scale`；字标落锤闪光、灯标耀斑和场景白热跟随 `Settings.flash_scale`，关闭时不播放这些效果。
- **确认进关（`_confirm_effect`）**：触发 `TitleWorld.enter_push(5.0, 0.55)`（白热闪光 + 镜头向骑士推进 5px + 吊灯齐闪）+ 选中条火星迸发 + `gate` 音效 + `Director.fade_to`。
- **竞技场入口修复（`ID_ARENA`）**：在 `_on_chosen` 中接入 `_start_arena()` → `ArenaRun.start()`（支持 `arena_start` 测试接缝）；启动成功即切入竞技场，若返回 `false` 则恢复菜单激活并播放 `ui_denied`。
- **退出（`_quit_sequence`）**：菜单行自上而下逐格熄灭，活景调用 `TitleWorld.quit_out(0.2)` 将亮着的吊灯逐盏吹灭、环境光压暗，只留巨剑剪影在黑暗中微亮，随后浮现 `QuitCaption`（「余 烬 熄 灭。」）再退出；期间任意按键/点击立即调用 `_finish_quit()`。

---

## 4. 可调常量速查

### `scripts/ui/title_world.gd`

| 常量 | 默认值 | 说明 |
|---|---|---|
| `MAX_LIGHTS` | `8` | 视口内 `PointLight2D` 预算上限（3 环境光 + 5 吊灯） |
| `LANTERN_COUNT` / `CHAPTERS` | `14` / `14` | 可见吊灯总数与战役总章数 |
| `LIGHT_POOL_FIXTURES` | `[1,4,7,10,13]` | 带物理光池的吊灯索引；其中 4、10 开启投影 |
| `DECK_Y` / `KNIGHT_X` / `KEEP_X` | `266.0` / `326.0` / `420.0` | 铁桥桥面 Y、骑士默认 X、守火结局骑士 X |
| `PARALLAX` / `POINTER_EASE` | `Vector2(9.0, 4.5)` / `3.2` | 深度 `1.0` 层的最大鼠标整像素偏移与平滑系数 |
| `DOLLY_FROM` / `DOLLY_TIME` | `Vector2(0, -26)` / `1.6` | 开屏抬高起点与推镜时间（秒） |
| `BREATH_PERIOD` | `7.0` | 摄像机 `±1px` 呼吸周期（秒） |
| `GRADES` | 8 组字典 | `cold`、`act1..act4`、`give`、`keep`、`snuff` 的环境色、炉温、光柱、粒子与齿轮倍率 |

### `scripts/ui/title_screen.gd`

| 常量 | 默认值 | 说明 |
|---|---|---|
| `USE_LIVE_SCENE` | `true` | 是否启用实时像素场景（`false` 回退静态 keyart） |
| `RAIL_X` / `RAIL_TOP` / `GROUP_GAP` | `72.0` / `254.0` / `16.0` | 左下菜单列起点与组间距（离开行中心 `QUIT_CENTER_Y = 640.0`） |
| `JOURNEY_X/Y/W/H` | `1000, 188, 208, 92` | 右侧短注矩形（计数、章名、横轨、回看） |
| `CARD_RECT` | `Rect2(820, 184, 388, 424)` | 展开态完整档案卡矩形 |
| `EPITAPH_RECT` / `FOOTER_RECT` | `Rect2(584, 624, 404, 32)` / `Rect2(72, 688, 1136, 28)` | 墓志与页脚矩形 |
| `BOOT_FADE` / `LOGO_AT` / `LOGO_TIME` / `MENU_AT` | `0.5` / `1.60` / `0.80` / `1.95` | 开屏动画各阶段时间点（秒） |
| `EPITAPH_CHAR` / `EPITAPH_HOLD` / `EPITAPH_FADE` | `0.085` / `5.5` / `0.7` | 墓志打字机单字间隔、停留与淡出时长 |

---

## 5. 测试与工具清单

### 自动化测试

- `tests/title_world_test.gd`：
  - 14 章 → 4 幕划分、通关章数 → 14 盏吊灯精确 N/14 映射；
  - `build_state()` 与 `state_from_save()` 在无存档、各幕旅程、三种结局（`give`/`keep`/`snuff`）及未知结局下的取值；
  - 8 种状态（`cold`、`act1..4`、`give`、`keep`、`snuff`）全部在 headless 下构建无错，点光源数 `≤ 8`、节点数 `≤ 250`；
  - 全部皮肤（`SkinCatalog.ids()`）待机帧、染色、偏移与背负巨剑校验；
  - 各变体桥上演员切换、守火坐姿、真实遮挡节点与 `configure()` 动态热切换；
  - 齿轮整周期无缝循环、冷炉慢转与熄灭停转；
  - 鼠标视差与相机呼吸严格落在整数像素；
  - 开屏逐盏亮灯、跳过开屏、退场逐盏灭灯；
  - 粒子池容量上限与连续 300 帧零节点增长；
  - `Keyart` 视口挂载、隐藏停渲、`USE_LIVE_SCENE = false` 静态回退、`bed_title` 音频特性探测。
- `tests/title_screen_test.gd`：
  - 左下刻字菜单三档宽度、52px 触控高度、四组间距、不过中线（`< 640`），吊灯光标跟着选中行走；
  - 键鼠共享同一选中态、聚焦联动活景微推与闪亮；
  - 回火试炼锁态提示、余烬竞技场 `ID_ARENA` 派发与真实 `ArenaRun.start()` 接线；
  - 旅程刻度点亮、`Tab` 展开/收起档案卡、墓志打字机轮换；
  - 离开行与墓志同基线（`y = 640`），档案卡与各区块在 `1280×720`、`1920×1080`、`2560×1080` 下零重叠且不越界；
  - 退场动画吊灯逐盏熄灭与跳过收尾。
  - 菜单烟斑、锁定铁签避让、灯标尺寸、页脚暗渐变与任意按下跳过开屏。
- `tests/title_elements_test.gd`：铁水连续折线、远厅实际绘制顺序、视差深度、节点与点光预算、推镜终态和镜头舒适性设置；压力用例见 `title_dolly_adversarial_test.gd`、`title_vault_adversarial_test.gd`、`title_elements_adversarial_test.gd`。
- 关联回归套件：`tests/title_flow_adversarial_test.gd`、`tests/display_resolution_test.gd`、`tests/ui_transition_test.gd`、`tests/modal_screens_test.gd`、`tests/m5_tier5_adversarial_ui_test.gd`、`tests/character_select_test.gd`、`tests/pause_menu_test.gd`。

### 诊断与截图工具

- **几何探针**：`scenes/tools/TitleMetrics.tscn`（`tools/title_metrics.gd`），headless 打印所有区块矩形、重叠检查与多分辨率边界检查。
- **多分辨率/多变体截图工具**：`scenes/tools/TitlePeek.tscn`（`tools/title_peek.gd` + `tools/run_title_peek.ps1`），窗口模式抓取 `960×540`、`1280×720`、`1920×1080` 下 `cold / act1..act4 / give / keep / snuff` 各变体的开屏帧、空闲态与菜单聚焦态。`-Keyart` 走与 `USE_LIVE_SCENE=false` 相同的实例回退路径；`-Bare` 隐藏 UI；`-ShadowPair` 冻结时间并成对抓取阴影开/关效果。
  - 每张图等待窗口与渲染缓冲连续 3 帧达到目标尺寸，PNG 文件名与 JSON 记录模式、实际尺寸、灯数/亮灯数/遮挡体/骑士姿态；静态模式记录 `has_live_viewport=false`。
  - wrapper 使用隔离存档/设置和离屏窗口，启动后恢复调用进程的 `APPDATA` 与更新检查环境变量。
- **渲染与 CPU 监测**：`scenes/tools/FrameCostProbe.tscn`（`tools/frame_cost_probe.gd` + `tools/run_frame_cost_probe.ps1`），支持 `-Level title -Variant cold|give|keep|snuff`、`-Keyart` 及章节 `-Level level08 -Active`。章节使用实际入口相机，固定无敌玩家，`-Active` 保留敌人子树运行；默认关闭敌人子树。
  - 验证实际分辨率，关闭进程 VSync/帧率上限，预热 2 秒，默认采样 4 秒 `RenderingServer.frame_post_draw` 回调的单调时钟间隔；采样期间不读回纹理，结束后保存 PNG。
  - JSON 分别输出回调间隔 mean/p50/p95/max、回调数/秒、`TIME_PROCESS` 与 `TIME_PHYSICS_PROCESS` 均值、draw calls、实际可处理节点类直方图和原始间隔样本；不再把两个 CPU monitor 相加命名为帧耗时。
  - 离屏回调频率不是实体显示器呈现 FPS；没有 GPU timer 或逐脚本归因。固定入口/静止玩家不能证明全程移动、战斗或最坏场景性能，其他任务的并行 headless 工作也可能影响结果。

```powershell
./tools/run_title_peek.ps1 -Variants 'cold,give,keep,snuff' -Sizes '960x540,1280x720,1920x1080' -Shots idle -OutDir screenshots/acceptance/overhaul-v3/title-perf/live
./tools/run_title_peek.ps1 -Variants 'cold,give,keep,snuff' -Sizes '960x540,1280x720,1920x1080' -Shots idle -Keyart -OutDir screenshots/acceptance/overhaul-v3/title-perf/keyart
./tools/run_frame_cost_probe.ps1 -Level title -Variant keep -Win 1920x1080
./tools/run_frame_cost_probe.ps1 -Level level08 -Active -Win 1920x1080
```

本轮实跑矩阵、硬件、测试与限制见 [`title-perf-acceptance.md`](./title-perf-acceptance.md)。

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
| `PointLight2D` | ≤ 8 | 8（3 盏环境光 + 5 个吊灯光池（吊灯总数 14））；新增元素 0 盏 |
| 节点总数 | ≤ 250 | 基础约 56（无演员；含 `BridgeFront` 与 `RiverCurrent`）+ 演员最多 10（守炉：骑士 5 + 余烬巢 5，巢火是 `title_flame.gd` 粒子火焰道具——本体 + Glow）+ 新增 15（`FarProps` 1 + 坩埚 2 + 锻锤 2 + 亡魂 2；送剑链 2；`Banners` 1 + 旗 2；火盆 2；魂光 1）≈ 81；`title_elements_test` 另设 ≤ 150 的余量线 |
| 每件元素 | ≤ 3 节点 | 本体 + 至多一个 `Glow`（破旗 1 个） |
| 视差基准 | 整像素 | 新宿主（`FarProps` -0.30、`SwordChain` +0.50、`Banners` +0.30、`Souls` -0.30）都走 `_register`，基准 `Vector2.ZERO`；`gears()[0]` 仍跟随调色；吊灯总数是 14 盏，其中 5 盏带物理光池；菜单仍是 7 行、竞技场在索引 3 |
