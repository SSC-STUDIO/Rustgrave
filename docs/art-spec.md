# Rustgrave — 像素美术规格（第三步）

给像素画师或 Aseprite / 像素 AI 使用。下面英文块为原始 Prompt，请原样复制。

## Art Asset Specification Prompt（原文，请原样复制）

```
Generate a 2D pixel art asset sheet for an action game.

Resolution: 64x64 pixels for the protagonist (Idle, Run, Slash, Deflect).

Tileset Size: 16x16 pixel tiles, arranged in a 256x256 grid.

Palette Restriction (GB-style + Rust): Maximum of 16 colors. Dominant colors: #3A3A3A (Shadow), #8B4513 (Rust Dark), #CD5C5C (Rust Light), #FF8C00 (Toxic Glow), #4A6B6B (Teal/Water).

Style Guide: No anti-aliasing, use sharp jagged edges (chunky pixels) to emphasize the "rusty" and "broken" theme. The protagonist should have a long tattered cloak to emphasize movement during combat.
```

## 硬性规格

| 资源 | 尺寸 | 备注 |
| --- | --- | --- |
| 主角精灵 | 64×64 | 动作至少：Idle / Run / Slash / Deflect（弹反即挥砍判定帧） |
| 建议额外帧 | 64×64 | Jump, Fall, Dash, Hurt, Land, Interact |
| 地砖 | 16×16 | 禁止半像素 |
| 图块集画布 | 256×256 | 16×16 网格 = 16×16 个 tile |
| 敌人 | 32×32 或 48×32 | 与 16 网格对齐 |
| 投射物 | 8×8 或 16×8 | 锯齿金属碎片 / 熔渣弹 |
| UI | 以 16 为基数 | 视口 640×360，整数倍放大 |

## 技术约束

- **禁止抗锯齿**、禁止半透明混合描边、禁止高斯模糊。
- 边缘用硬锯齿（chunky pixels）表现锈蚀与断裂。
- 主角必须有 **长破披风**，跑、斩、冲时披风是读动作的主要剪影。
- 引擎导入：Filter = **Nearest**，Mipmaps 关，不要压缩成失真格式。
- 角色脚底锚点放在 64×64 画布底部中心，预留 1–2 像素给落地尘。

## 像素密度与对齐（显式规范，代码执行中）

| 项 | 规范 | 代码执行点 |
| --- | --- | --- |
| 世界分辨率 | **640×360**，`GameCamera.zoom = 1`，原生像素渲染 | `docs/architecture.md`；`PresentationMetrics.WORLD_SIZE` |
| 台面网格 | **8px** 网格是构建单位；地形 / 悬浮台 / 墙体贴片都是 16px tile 的整数倍，禁止半像素 | `SolidPlatform.WORLD = 16.0`（`scripts/world/solid_platform.gd:126`）；`RuinPlate.STRIP_W = 8`（`scripts/world/ruin_plate.gd:9`） |
| 精灵缩放 | 接地装饰 **只允许 1x 整数倍**；拒绝小数缩放 | `Level01Env.plant_texture()` 用 1x 裁切图（`scripts/levels/level01_env.gd:19-22`），测试 `tests/wind_sway_test.gd:188` |
| 纹理过滤 | 全部 `TEXTURE_FILTER_NEAREST`，mipmaps 关，无压缩失真 | 每个 Sprite2D 都显式设置（如 `solid_platform.gd:263`） |
| 坐标取整 | 环境粒子的世界坐标每帧 `roundf()`，不得出现亚像素漂移 | `theme_motes.gd:226`、`wind_fx.gd:122`、`leaf_shed.gd:138`、`weather_fx.gd:232` |

## 色板（16 色，GB-style + Rust）

前 5 个为需求指定的主色；其余 11 个为项目补全色，用于阴影、高光、混凝土与雾，仍计入 16 色上限。

| # | Hex | 名称 | 用途 |
| --- | --- | --- | --- |
| 0 | `#1A1412` | Void | 最深洞穴、轮廓 |
| 1 | `#3A3A3A` | **Shadow** | 指定。钢梁暗部、盔甲 |
| 2 | `#5E5A56` | Iron | 中性金属 |
| 3 | `#8A8680` | Concrete | 混凝土、尘 |
| 4 | `#C8C2B8` | Pale Metal | 边缘高光（极少使用） |
| 5 | `#4A2A18` | Rust Shadow | 锈的最暗层 |
| 6 | `#8B4513` | **Rust Dark** | 指定。主体锈层 |
| 7 | `#A0522D` | Rust Mid | 过渡 |
| 8 | `#CD5C5C` | **Rust Light** | 指定。新断面、披风衬里 |
| 9 | `#E8B090` | Ember Ash | 余烬、皮肤高光 |
| 10 | `#7A3A00` | Toxic Dark | 泥浆深处 |
| 11 | `#FF8C00` | **Toxic Glow** | 指定。毒素、应急灯 |
| 12 | `#FFC14A` | Ember | 炉心、斩击闪光 |
| 13 | `#2A4040` | Teal Deep | 积水暗部 |
| 14 | `#4A6B6B` | **Teal/Water** | 指定。积水、滤芯、UI 安全色 |
| 15 | `#7FA8A0` | Fog Teal | 雾、远景、净化光 |

当前脚手架用 ColorRect / Polygon2D 占位，只使用指定主色 + Void，待正式像素替换。
运行时调色板的唯一代码来源是 `scripts/data/palette.gd`（`Palette.VOID` … `Palette.FOG`），
新代码不得引入调色板外的裸色值；关卡/背景的 `Color(...)` 参数一律由
`tools/gen_theme_tiles.py` 的 gradient-map 从同一族色阶派生（见「素材来源」）。

## 每章身份色（Identity Color）

除背景底色外，每章必须有一个可辨识的身份色锚点，写在地形 / 微粒 / 光上：

| 章节 | 主题 | 身份色锚点 | 落点 |
| --- | --- | --- | --- |
| level01 墓园 | graveyard | 锈月橙 + 烟紫夜 | `parallax_sky_rust.png` 锈月派生板（原 `parallax_sky.png` 品红板保留为回落）+ `parallax_mountains_rust.png`；锈块装饰 `iron_slab_a` |
| level02 地窟 | undercroft | 青黑苔绿 | `MOSS_TONE`（青苔砖）、`TOXIN_TINT` 酸黄 |
| level03 街巷 | town | 暖街灯黄 | `night-town-*` 原板 + `WARM_RAMP` 砖 |
| level04 圣殿 | cathedral | 冷紫石 | `GOTHIC_CASTLE` 殿墙 + 烛火微粒 `candle` |
| level05 工坊 | industrial | 暖灰铁 | `iron_*` 铁板 + 弧光火花微粒 `sparks` |
| level06 墓园夜 | graveyard | 锈橙 + 雨青 | 同 level01 锈月派生板（`parallax_sky_rust` / `parallax_mountains_rust`）+ `rust_rain` 混色 |
| level07 钟楼 | belltower | 橄榄城砖 | `tower_wall.png` 竖井 + 沉尘微粒 `dust` |
| level08 熔渣 | forge | 炉口红 | `forge_*` 底板 + 升焰微粒 `embers` |
| level09 城墙 | ramparts | 雾青 | `wall_clouds/wall_town` 底板 + 女墙剪影 |
| level10 炉心 | forge_core | 暗红 | `core_hall.png` + 落烬微粒 `cinders` |

`ThemeBackdrop.THEMES`（`scripts/levels/theme_backdrop.gd:30`）与 `PropCatalog.FAMILY`
（`scripts/levels/prop_catalog.gd:107`）是主题 → 底板 / 材质族的唯一登记处；新增章节
必须同时登记两者，否则 `ThemeBackdrop.build()` 会回落到 undercroft。

## Boss 剪影例外（第一章刽子手）

全项目只允许一处非 1× 的角色帧：第一章 Boss「刽子手」以 **整数 2×** 绘制
（`ExecutionerBoss.BOSS_SCALE := 2`，只作用于内部 `FrameAnimSprite.scale`，
节点 / Visual 变换保持 1×，脚点仍在 y=0；无小数缩放、无拉伸）。

- 原因：仓库里唯一的刽子手素材是 100×100 的齿轮盾卫帧。1× 时他的剪影只有约
  62px（≈1.4 只骷髅），本章高潮会被读成杂兵；本轮不引入新的 Boss 角色素材。
- 判定与画面同步放大：身体碰撞 56×96、受击盒 72×120、挥斧落点框 72×28 仍贴地
  （底边 −4），同一个常量同时驱动地面红框与 `Hitbox` 尺寸；读招表不变。
- 代价：2×2 的源像素块与 1× 素材并置时可见，640×360 原生分辨率下读作
  「一个高大暗影」。新增 Boss 应优先配与体型匹配的独立帧，不沿用此例外。
- 可读性：帧素材本身接近纯黑，`Visual.modulate` 提亮（暗相位 2.45/2.15/1.95，
  二阶段偏炉火色）+ 有上限的背光 / 暖底光 / 冷前光 / 接地影，让兜帽、眼、骨臂
  与斧柄在暗背景里仍可读；骑士仍比他亮 1.7 倍以上（Boss 永远是房间最暗剪影）。

## 角色接地（Foot Pinning）

- **所有接地装饰 / 道具 / 敌人 / 存档点**的节点原点就是脚点：脚点（底边中点）
  必须坐在台面顶 y 上，且 y 取整数。
  `Level01Env.plant_texture()`（`scripts/levels/level01_env.gd:114-154`）把脚点写进
  `set_meta("feet", …)` 并加入 `grounded` 组；`ChapterLayout.prop()`
  （`scripts/levels/chapter_layout.gd:385-412`）同样写 `feet` 元数据。
- 树木 / 灌木建在「脚点枢轴」上（`Sway_*` 节点），枢轴即脚点，精灵画在枢轴上方，
  这样风摆绕脚而不是绕中心。
- 平台接地物必须**踩在实心台面上**：`LevelSanity._check_grounded_decor`
  （`scripts/levels/level_sanity.gd:242`）检查每个 `grounded` 组成员的脚点
  −3..+8px 内有台面顶；飘浮即判失败。`ChapterLayout.prop()` 不接受未注册脚点。
- 有生命的树不遮路：`Level01Static.PLAY_DECOR` 与关卡 decor 之间不得互相重叠
  （`tests/wind_sway_test.gd:188` 断言的 spans 两两不相交）。

## 轮廓对比度（Silhouette Contrast）

- 角色与背景之间至少 **2 档明度差**（背景底 ≈ 0.10–0.16，角色 ≈ 0.30–0.55）。
  玩家剪影：斗篷 `#3A3A3A`(0.227)、身体 `#CD5C5C`(0.804)、脸 `#3A3A3A`、
  护目镜 `#4A6B6B`(0.29,0.42,0.42)（`scenes/player/Player.tscn`）；最低明度
  0.227 对背景 ≤0.16，差 ≥0.06（≈1 档）；对角色身体差 ≥0.3（≈3 档）。
- 背景永远比角色暗：`WorldAtmosphere._apply()`（`scripts/world/world_atmosphere.gd:60-73`）
  给底板 CanvasLayer 额外 `darkened(0.24)`，所以远景永远输给玩法层。
- 前景只允许剪影：`Level01Parallax.SIL_TINT` 明度 0.14–0.24，
  `Level01Parallax.SIL_FEET_MIN/MAX`（300..340）保证剪影落在地脚带，
  不进可交互高度；石碑 / 雕像不进剪影层（`scripts/levels/level01_parallax.gd:46-58`）。
- 同一图层内：`ThemeBackdrop` 的每层 `tint` 明度按 scroll 递增
  （sky 0.13 → far 0.18 → mid 0.4 → near 0.62），形成 4 级层次对比。
- 派生锈月板同样受这条约束（`tests/level01_backdrop_test.gd` 锁定）：
  `parallax_sky_rust.png` 不透明像素平均明度 0.10–0.22，月亮核心 < 0.455
  （玩家躯干 `#CD5C5C`），`parallax_mountains_rust.png` 平均明度 < 0.14、
  峰尖暖脊 < 0.455——远山始终最先输给角色。地平线暖雾（`HorizonHaze`）与
  月光束（`Moonbeams`）都是 backdrop CanvasLayer（layer < 0）内的加法光，
  alpha ≤ 0.20，永远不盖住角色/平台。

## 素材来源与许可（可溯）

新增素材只允许三种来源，禁止随意下载替换：

1. **程序化生成**：`tools/gen_theme_tiles.py`（地形 / 底板 / 道具族）、
   `tools/gen_ui_kit.py`（UI）、`tools/gen_moss_tiles.py`（地窟苔砖）、
   `tools/normalize_art.py`（1x 重采样）。
2. **已有外站素材的裁切 / 渐变映射**：只从 `assets/external/` 里的
   Gothicvania（ansimuz）、Kenney（CC0）、OGA 工业视差（CC0）、
   CodeManu FX（CC0）派生；许可与出处见 `assets/external/CREDITS.md`。
3. **在本文登记**：任何手绘 / 新来源的素材必须写明作者、许可、来源 URL 与
   派生工具，写进 `assets/external/CREDITS.md` 后才能在代码里引用。

新贴图必须落在 `assets/env/` 并随 `.import` 入库；`gen_theme_tiles.py` 重跑
必须是幂等的（当前实现如此，已验证 `git status` 无残留改动）。

## 环境层次（远 / 中 / 近 / 雾 / 光 / 局部照明）

每个章节 backdrop 至少要有：**1 层天 / 1 层远 / 1 层近 / 1 层独有元素**，
且每个主题至少一个独有视觉元素（不能只换底色）：

| 主题 | 独有元素 |
| --- | --- |
| graveyard | 哥特墓园三板（锈月派生：月亮 / 锈山 / 原墓园）+ 灰烬暖尘云带 + 地平线暖雾 + 2–3 条月光束 + 剪影带 |
| undercroft | 城堡内景拱窗 + 重复石柱剪影 |
| forge | 炉口天空底板 `forge_sky` + 4 层剪影 |
| forge_core | 烧红的殿厅 `core_hall` + 暗红柱影 |
| cathedral | 哥特城堡殿墙 + 冷紫柱影 |
| belltower | `tower_wall` 双向平铺竖井（箭窗透光） |
| town | 夜城 6 层板（天 / 云 / 山 / 林 / 远屋 / 近屋） |
| ramparts | 墙下雾城 `wall_town` + 青云 `wall_clouds` |
| industrial | 工业剪影 3 层板（暖灰） |

实现约束见 `scripts/levels/theme_backdrop.gd`：室内主题不加天气 / 风尘
（`build()` 的 `_indoors` 分支），室外主题由 `ThemeBackdrop` 挂 `WeatherFx` +
`WindFx`；graveyard 复用 `Level01Parallax`（云 / 雾 / 月 / 前景草）。
每层 Parallax2D 必须有 `repeat_times ≥ 4` 以盖住 640 视口 + 128 pad
（`Level01Parallax.cover_layer()`，测试见 `tests/parallax_backdrop_test.gd`）。

### Level01 / Level06 锈月夜空板（派生，不改原板）

墓园包的 `parallax_sky.png` 是设计上的品红月夜，和标题的锈橙身份冲突；
`parallax_mountains.png` 的紫罗兰山体、两层紫罗兰云带同样抢色。这**四张原板
全部保留入库不动**，另出四张派生板：

| 派生板 | 来源 | 处理 | 结果 |
| --- | --- | --- | --- |
| `assets/env/parallax_sky_rust.png` | `parallax_sky.png` | 亮度 → 锈色阶（Void → Rust Shadow → Rust Dark → Rust Mid → Ember），下半天空向锈色收拢 | 暗锈血月 / 烟紫夜空 / 地平线转暖 |
| `assets/env/parallax_mountains_rust.png` | `parallax_mountains.png` | 扁平紫山体压到近 Void 暖灰，只留峰尖余烬山脊 | 能读成剪影、又不再是紫色带 |
| `assets/env/parallax_clouds_rust.png` | `parallax_clouds_px.png` | 紫罗兰厚涂云的亮度 → soot → 暖灰 → 暖尘 | 被锈月照亮的灰烬云带 |
| `assets/env/parallax_clouds_low_rust.png` | `parallax_clouds_low_px.png` | 同上（低云带） | 同一场阴云的两层灰烬色 |

派生板只换颜色与色阶，轮廓、alpha、尺寸全部沿用原板；云量 / 漂移 / 雾幕仍由
`WorldClock` 控制（「一朵风，多种 Telling」不变）。运行时光照强度、云量、风化
数值都不变，所以昼夜/天气交叉仍按原来的混合曲线走。

生成入口是 `tools/gen_theme_tiles.py`（`rust_moon_plates()`，确定性、幂等；
重复跑只重写这四张 PNG）。运行时 `scripts/levels/level01_parallax.gd` 的
`sky_plate_path()` / `mountains_plate_path()` / `plate_path()` 只在 graveyard
主题换派生板，派生 PNG 缺失时回落原板（启动不依赖派生素材；回落紫云板时
自动换回旧的提亮紫乘数）；许可链见 `assets/external/CREDITS.md`。验收：
`tests/level01_backdrop_test.gd` 锁定「派生板是暖色、平均明度留在背景带、
月亮核心低于玩家躯干明度、云是灰烬而不是霓虹紫」。

## 特效不遮挡原则（FX Occlusion）

命中火花、剑光、弹反炸亮是**表现层**，绝不许盖住角色轮廓、敌人前摇、
台缘与地面陷阱。规则：

1. 玩家 / 敌人本体的 z 固定为 0（默认），飞行动物祖先 `z_index` 由宿主负责。
2. 一次性弧光 `SlashArc.z_index = 10`（`scripts/combat/slash_arc.gd:56`）：
   只覆盖挥砍判定区，尺寸固定 64×47 单帧，不做全屏拉伸。
3. 命中火花 `Fx.FX_Z = 100` 的 `HitSpark` 走 `GameContext.world_effects()`
   的 `WorldEffects` 节点，缩放固定 0.5（600px 母版 → 100px 世界像素），
   不放大覆盖角色。
4. `CineFx.glow_pulse` 的故事光晕 `z_index = 60`，`WorldEffects` 内，
   半径上限由 `GLOW_CAP = 3` 限流。
5. `ThemeMotes.z_index = 4`、`WeatherFx` 层 4、`WindFx.z_index = 1`、
   `RainGroundFx.z_index = 2`、`ToxinPool` 蒸汽 z=2 —— 都在角色之下，
   不遮挡轮廓。
6. 判定形状（hurtbox / hitbox）与精灵无关，特效永不改变判定。
7. 测试 `tests/theme_motes_test.gd`、`tests/weather_fx_test.gd`、
   `tests/world_atmosphere_test.gd` 锁定这些不变量。

## 世界历史细节（Set Dressing）

损坏机械、墓碑、生活残留、锈蚀管道、炉火、遗弃设施统一从 `PropCatalog.DECOR`
（`scripts/levels/prop_catalog.gd:12-56`）取键，禁止在 layout 里写死路径：

| 类别 | 键 | 素材 |
| --- | --- | --- |
| 墓碑 / 坟 | `grave_cross`、`stone_1..4`、`statue`、`bones` | 十字墓碑、墓石、守墓者、骨渣 |
| 损坏机械 | `beam`、`beam_bolts`、`beam_narrow`、`metal_panel`、`skull_arch` | 钢梁 / 螺栓梁 / 金属板 / 骷髅炉口 |
| 锈蚀管道 | `vine`（工业关用作电缆，`CABLE_TINT`） | 16×64 垂线 |
| 炉火 | `TorchLight`（wall / furnace 两种）、`EmberNest` | 壁炬、砖炉膛、余烬巢 |
| 遗弃设施 | `door_arch`、`door_arch_wall`、`door_arch_town`、`balustrade*`、`window` | 门洞、女墙、尖窗 |
| 生活残留 | `rubble_dry*`、`rock_pile`、`plate`、`slab`、`rubble`、`stair` | 干石渣、碎石堆、石板、苔阶 |

`PropCatalog.THEME_PROPS`（`prop_catalog.gd:61-104`）是主题白名单：
哥特教堂柱不得种在工坊地面，墓园十字不得种进熔炉——`ChapterLayout.prop()`
对越界键直接 `push_warning` 并拒绝。材质族 `FAMILY` 决定重着色副本
（`assets/env/props/<family>/<key>.png`，由 `gen_theme_tiles.py` 写入）。

## 主角剪影要点

- 头小、剑极大（剑长约身长 1.3–1.6 倍），强调 Weight & Momentum。
- 披风尾端撕成 2–3 片破布，Idle 时轻微下垂，Slash 时甩向反方向。
- 不要把角色画“帅而干净”；表面应有锈斑与补丁。

## 图块集分区建议（256×256）

```
[0,0]    地面 / 锈铁地板
[4,0]    混凝土墙与裂隙
[8,0]    齿轮、管道、铆钉装饰
[12,0]   危险：栅栏、熔渣、毒素边缘
[0,8]    背景钢梁（可作装饰 tile）
[8,8]    门、压力板、废料堆、插座台
```

脚手架里的测试关使用 16px 几何占位，等待此规格的正式 tile 替换。
