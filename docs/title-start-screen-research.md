# 开始界面市场调研与打磨映射（2026-10-31）

> 目的：在 v3 活景标题（`TitleWorld` + `TitleScreen`）上做一轮**执行层**打磨，不重做视觉方向。
> 本文记录调研证据、采用/不采用的决定，以及每条决定落到哪个文件/测试。
> 现行版式与动效说明见 [`title-live-scene.md`](./title-live-scene.md)。

---

## 1. 方法与局限

- 本环境 `web_fetch` 对所有域名解析失败（返回 non-public IP），因此调研通过搜索引擎摘要 +
  从 shell 抓取 Steam 商店/新闻 API、FromSoftware 官方在线手册、厂商无障碍页面、Fandom
  MediaWiki API、Game Accessibility Guidelines 等完成。
- **只把能从页面正文/补丁说明确认的机制写进“采用”项**；未验证的菜单顺序、槽位数、
  具体图标等内容标 `n/v`，不凭记忆补细节。
- 调研对象偏 2D 动作/银河城与有代表性的 AAA：Hollow Knight、Blasphemous 1/2、Dead Cells、
  Hades 1、Nine Sols、GRIME、Ender Lilies/Magnolia、Salt and Sanctuary、The Last Faith、
  Momodora、Katana ZERO、Hyper Light Drifter、Ori、Elden Ring、Sekiro、God of War
  Ragnarök、Celeste、Cuphead、Deltarune 等。
- 结论以“能不能改善 Rustgrave 的单存档、中文、键鼠/手柄/触屏、1280×720 设计层”为准，
  不照搬 4 槽、语言菜单、待机播片等不匹配的机制。

---

## 2. 证据表（节选）

| 观察到的做法 | 来源 | Rustgrave 的处理 |
|---|---|---|
| FromSoft 标题菜单 **CONTINUE 置顶**，首次游玩 CONTINUE/LOAD GAME 不可选；标题下角有版本号；自动存档有图标 | [Elden Ring 官方手册](https://www.fromsoftware.jp/manual/eldenring/win/start.html)、[Sekiro 官方手册](https://www.fromsoftware.jp/manual/sekiroshadowsdietwice/xone/start.html) | 保留 7 行顺序与默认光标；**Continue 行显示章节/进度**，无存档行写明「尚无存档」；不做存档槽 |
| Hades 自动存档有印记；版本号在主菜单、进游戏时淡出；4 槽在 New Game 时选定、Hell Mode 锁定 | [Hades 存档](https://hades.fandom.com/wiki/Saving_your_Progress)、[版本淡出补丁](https://store.steampowered.com/news/app/1145360/view/4050393736357316989) | Continue 行 + 页脚写“上次行程”的真话；单存档，不引入槽位 |
| Celeste 对“重置全部按键”改为 **按住确认**；按键重绑冲突修复 | [Celeste v1.4](https://store.steampowered.com/news/app/504230/view/4026755437314204797) | 覆盖存档的**火漆按住 0.45s** 才生效；键盘仍走菜单行两步确认 |
| Dead Cells 把闪屏/震屏/粒子/血腥/配色做成独立无障碍块；Hades II 有命名 Accessibility 菜单与 Zoom In | [Dead Cells Assist/Accessibility](https://deadcells.fandom.com/wiki/Assist_Mode_and_Accessibility)、[Hades II Zoom In](https://store.steampowered.com/news/app/1145350/view/1829528821318255) | 保留「设置 → 辅助」；本轮修 **文本缩放全局双重覆盖**，标题的闪屏/推镜继续受 `flash_scale/shake_scale` 控制 |
| 盐与避难所补丁加入「退出到桌面」与「Logo 可跳过」 | [Salt & Sanctuary v1.0.1.0](https://store.steampowered.com/news/app/283640/view/6539831519492928579) | 标题退出不加二次确认；页脚写清「退出游戏」；开演任何输入可跳过，并修“同一输入的 release 跳过整段退场” |
| Ender Lilies 待机一段时间播放序章影片（attract mode） | [Ender Lilies 1.1.0](https://store.steampowered.com/news/app/1369630/view/4516534149069316217) | **不采用**：活景本身持续演出；attract 会干扰输入/测试/录制 |
| Blasphemous II 后补重排主菜单选项；Hades EA 反复改菜单 | [Blasphemous II 补丁](https://store.steampowered.com/news/app/2114740/view/1784506359177799)、[Hades 菜单清理](https://store.steampowered.com/news/app/1145360/view/4038024692305372930) | **不采用 7→5 合并**：设置/操作说明需一步可达；四组留白已表达分组 |
| 九 Sols 在任意结局后往主菜单追加 Battle Memories；Cuphead 允许换整套标题屏 | [Nine Sols](https://store.steampowered.com/news/app/1809540/view/1783872412136185)、[Cuphead 1.3.4](https://store.steampowered.com/news/app/268910/view/4584121659785435376) | 已有 cold/journey/give/keep/snuff/true_break 变体；本轮补 `true_break` 的测试/文档/截图，不新增入口 |
| 菜单设计别让演出变成进游戏的过路费；开始游戏不应穿过多层菜单 | [GamesRadar 主菜单专题](https://www.gamesradar.com/the-hidden-value-of-video-game-main-menus-and-the-design-secrets-that-compel-you-to-hit-play/)、[GAG 全表](https://gameaccessibilityguidelines.com/full-list/) | 开演非输入门禁、任何输入立即落位、默认光标 Continue；不加“按任意键”门槛 |
| 标清/超宽/高 DPI 需要显式策略 | [Hollow Knight 21:9](https://store.steampowered.com/news/app/367520/view/1823825466498013) | 移除会半倍缩小 UI 的 1024×768 预设；记录 1080p UI 1.5× 的已知限制 |
| 版本号/制作信息放在标题屏可帮助支持与透明 | [Elden Ring 版本补丁](https://store.steampowered.com/news/app/1245620/view/1842212951300120)、[Hades 版本淡出](https://store.steampowered.com/news/app/1145360/view/4050393736357316989) | 页脚列出完整素材/字体署名；版本常量未由发布流程设置，本轮不加常显版本号 |

---

## 3. 采用 / 不采用

### 3.1 采用

1. **Continue 是默认，但无存档要诚实**：有档时行右侧写章节/进度，无档时写「尚无存档」并压暗；
   默认光标仍在 Continue（有档）/New（无档）。
2. **把“上次行程”放在玩家看得到的地方**：行内小注 + 页脚一句话，而不是只藏在 Tab 档案里。
3. **破坏性动作防误触**：覆盖存档默认停在取消；火漆必须按住 0.45s；键盘仍是两步确认。
4. **辅助设置要真的生效**：修掉 `UiKit.label` 的全局字号覆盖，让 85/100/135% 的比例一致；
   标题的副题/墓志/档案在 135% 下重新排版。
5. **任何输入跳过开演**：保持现有非门禁设计；修退场被同一输入的 release 跳过。
6. **致谢可读且完整**：页脚署名补全，提高到 ≥4.5:1；不再用“精简到 35 字”牺牲署名。
7. **输入路径完整**：手柄 Y / 触屏点按旅程短注也能开档案；Tab 仍是键盘路径。
8. **结局变体可验证**：`true_break` 进测试/文档/截图矩阵，不新增菜单入口。

### 3.2 不采用

| 项 | 理由 |
|---|---|
| 语言切换 | 仓库没有 i18n/翻译资源；加假入口是空功能 |
| 4 存档槽 / 存档卡 | 单存档是现有产品语义；Continue 行状态已足够 |
| 退出确认弹窗 | 标题屏退出语义明确，退场动画就是仪式；市场证据也支持标题退出不确认 |
| 待机 attract | 与活景持续演出重复，且会打乱输入/测试/录制 |
| 7→5 菜单合并 | 设置/操作说明一步可达优先；四组留白已表达分组 |
| 1080p 原生 UI 重排 | 需要改 1280×720 虚拟画布为物理分辨率 UI 层，牵动 HUD/暂停/触控/输入；单独立项 |
| 常显版本号 | `application/config/version` 未设置（当前 0.0.0）；发布元数据由发布流程决定 |

---

## 4. 调研 → 实施映射

| 调研结论 | 实施位置 | 验证 |
|---|---|---|
| Continue 行状态/空档说明 | `scripts/ui/title_screen.gd`（`continue_note/continue_hint`、`_continue_item`） | `title_screen_test` 新用例 |
| 回看入口去重 | `title_screen.gd`（`RecapButton.visible`） | 冷/结局/有档无结局三种状态 |
| 覆盖存档按住确认 | `title_screen.gd`（SealButton hold）+ `ui_object.gd`（火漆上移/缩小） | 短按不确认/长按确认；键盘路径不变 |
| 文本缩放单一来源 | `scripts/ui/ui_kit.gd`（删 16px 覆盖）+ `title_screen.gd`（`_refresh_text_layout`） | `comfort_options_test` + 标题 85/100/135% 布局测试 |
| 退场不被同输入跳过 | `title_screen.gd`（`quit_skip_grace` + 只认 pressed） | release/press 新用例 |
| 旅程短注可读 | `title_screen.gd`（`JourneyShade`、`JOURNEY_DIM/LIT`、字号） | 实拍对比度 ≥4.5:1 |
| 页脚完整署名/对比度 | `title_screen.gd`（credits 文案/颜色/字号） | 新用例 + 实拍 |
| 确认信墨色/焦点层级 | `title_screen.gd`（ink 覆盖/火漆标签） | 新用例 + 截图 |
| 手柄/触屏档案 | `title_screen.gd`（`JourneyButton`、Joy Y） | 三路径测试 |
| 1024×768 预设 | `display_fit.gd`（换 1280×1024） | `display_resolution_test` |
| 最小窗口 | `display_fit.gd` + peek wrapper 的 `RUSTGRAVE_ALLOW_SMALL_WINDOW` | 预设/常量测试；960 诊断截图仍可跑 |
| 锻造口 16 帧 | `scripts/ui/title_world.gd` | `title_world_test` |
| true_break | `title_world.gd` 已有变体；测试/文档/截图补齐 | `title_world_test` + 截图矩阵 |

---

## 5. 验收与证据

- 测试：`tools/run_tests.ps1 -CaseFilter title_`（更新后 ≥130 用例）、`comfort`、`display`、
  `m5_tier5` 等关联组，最后全量 `tools/run_tests.ps1`，要求 0 engine errors。
- 几何：`scenes/tools/TitleMetrics.tscn` 在 1280×720 / 1920×1080 / 2560×1080 输出
  `0 problem(s)`。
- 截图：`screenshots/acceptance/title-polish-2026-10-31/`（cold/act2/keep/true_break ×
  960/1280/1920/2560/3440 + focus），`screenshots/peek/title-polish-2026-10-31/`
  （title/confirm/settings）。至少人工审：1920 cold、1920 keep、1280 confirm、135% 设置。
- 真实输入：键鼠/手柄/触屏各走一次“选择→继续/离开→跳过退场/开档案”，并测损坏存档。
- 对比度：新截图用 Pillow/WCAG 抽样，旅程短注/页脚/确认正文 ≥4.5:1；记录在验收记录中。

---

## 6. 已知限制

- 1920×1080 下 UI 为 1.5× 分数缩放（世界 3×、QHD 素材），是 1280×720 虚拟画布经
  `canvas_items` 放大的结果；1440p 为整数 2×，960×540 仅诊断。原生 UI 需单独立项。
- 4K 世界渲染密度上限为 4（QHD 缓冲放大），本轮不动。
- 3440×1440 在 INTEGER 模式下有 440px 黑边；可用设置里的 EXPAND 模式，本轮不默认化。
- 单存档、无语言切换；`true_break` 标题变体的入口/存档语义沿用现有结局流程。
