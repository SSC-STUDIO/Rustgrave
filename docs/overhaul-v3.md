# 锈墓全面改造 v3（标题活景 + 14 章重做 + 系统升级）

> 本页是 v3 改造的唯一清单与验收记录（沿用 `docs/UPGRADE_PLAN.md` 的做法）。
> 数值/流程细节仍以 `docs/combat-rules.md`、`docs/level_authoring.md`、`docs/art-spec.md` 为准；
> 改动必须落到玩家能看见、听见、操作到的内容。

## 0. 方向与底线

- **标题**：静态 keyart 换成游戏内实时像素场景（真实骑士精灵 + 背扛巨剑、PointLight2D、多层视差、粒子），
  随存档进度/结局变化；版式与动效整体重做。`TitleScreen.USE_LIVE_SCENE` 可回退 keyart。
- **关卡**：14 章全部重排地形/遭遇/路线；每章新增 1–2 个专属机关/危险和少量敌人变体；
  第一章前半微调、后半重建。**玩家能力不变**（主线仍只需单跳/冲刺/热锻）。
- **底线**：故事与 14 章顺序、存档 v2 兼容不变；level01 的裸路径持久化节点
  （`Props/EmberNest`、`Props/EmberNestEast`、`Props/Door`、`Props/RustyGate`、`Props/ForgeHeart`、
  `Pickups/EmberCore`、`Props/ScrapPile`）不改名。
- **门禁**：每阶段全量 `tools/run_tests.ps1` + `LevelSanity` + 渲染机位截图通过才进下一阶段；一阶段一提交。
- **分支**：`feature/overhaul-v3`（自 `merge/all-branches` 的 `8bfa46f` 基线提交切出）。

## 1. 基线（P0）

- 工作区的标题 WIP（`dossier_jag` / `keyart_knight_light` / `title_metrics` / 0.2.0 版本号）已做基线提交 `8bfa46f`；
  无关的 `artifacts/taihe-cherry/*.pptx` 未纳入。
- 导入后全量回归：**1182/1182 通过，0 engine errors**（约 305 秒，独立 `%TEMP%` APPDATA）。
  日志：`screenshots/acceptance/overhaul-v3/baseline/stdout.log`（`screenshots/` 为 gitignore 的本地证据目录）。

## 2. 阶段清单

- [x] P0 基线与分支
- [x] P1 机关工具箱（`scripts/hazards/`）+ 敌人变体/脱战/群警戒 + 读档坐标安全（Boss 韧性延后，见 §4）
- [x] P2 标题活景（`TitleWorld`）+ 版式与动效重做 + `ID_ARENA` 接线
- [x] P3 第一章（前半微调 + 后半重建）
- [x] P4 第一幕：level02 / level02b / level03
- [x] P5 第二幕：level04 / level04b / level05 / level06
- [x] P6 第三四幕：level07 / level07b / level08 / level09 / level09b / level10
- [x] P7 系统升级：手柄、辅助选项、显示设置、地图热键、回看余烬总结页、复活 QoL、机关音效、性能预算
- [x] P8 全量测试已通过（1396/1396）。标题三档截图已存。14 章输入验收见 §5

## 3. 验收总则

1. 每个改动要有证据：测试通过 + 实际渲染截图（`tools/run_peek_live.ps1`）或输入验收日志。
2. 证据归档到 `screenshots/acceptance/overhaul-v3/<阶段>/`；`docs/acceptance.md` 只记路径与结论。
3. 无法验证的项如实列出：真机触屏、手柄实机手感、真人试玩手感、实体显示器性能。
4. 新机关的硬规则（`LevelSanity` 拒绝）：预警 ≥0.5s；余烬巢/压板/出口/落脚区无判定；相位在出生时固定；
   塌陷台不得是巢/压板/出口的唯一支撑；风/涌流区不覆盖余烬巢。

## 4. 决策与变更记录

### 并行推进快照（P2 起）

- 主分支 `feature/overhaul-v3` 已含 P0 / P1（提交 `d2bd684`）与通用简报 `docs/overhaul-v3-brief.md`（`124059e`）。
- 十个并行 worktree 已建好（均自 `124059e` 切出，已拷入 `.godot` 导入缓存并验证能跑测试）：
  `C:\dev\rg-title`（标题）、`rg-level01`（第一章）、`rg-systems`（P7 系统）、`rg-g1`（02 / 02b）、`rg-g2`（03 / 04）、
  `rg-g3`（04b / 05）、`rg-g4`（06 / 07）、`rg-g5`（07b / 08）、`rg-g6`（09 / 09b）、`rg-g7`（10）；分支名 `feature/overhaul-v3-<名字>`。
- 各 agent 的任务书在 `docs/overhaul-v3-agents/<名字>.md`（未提交，随主工作区）。
- 待办：全量回归复核（P1 修完两处测试写法后只复跑了相关文件）；启动各 agent；逐个合并回 `feature/overhaul-v3`；
  再做 P8（战役 bot 升级与 14 章输入验收、渲染矩阵、最终文档）。
- 阻塞记录：本轮后段 Shell 工具被环境 hook（`enforce-agent-api.sh` 返回非法 JSON）拦截，之后的命令（测试 / git / 启动 agent）都等该问题解除后再继续。

### P1（机关工具箱 / 敌人 / 存档安全）

- 五个机关基类（`CyclicHazard` / `CollapsingPlatform` / `ForceZone` / `ConveyorBelt` / `PendulumHazard`）
  + `HazardFx`（音效键解析、首遇提示、像素绘制助手）落在 `scripts/hazards/`；`ChapterLayout` 增加
  `cyclic/collapsing/force_zone/conveyor/pendulum` 助手；规则与参数写进 `docs/level_authoring.md` §8。
- `PlayerController.add_environment(push, drag)` 是唯一外力入口（风 / 涌流 / 泥沼）；没有外力时行为与旧版逐位一致。
- `LevelSanity` 新增 `_check_hazards`（预警/安全间隔/净空/塌陷台与传送带不得当休息点/外力区不盖巢）与
  `LevelSanity.hazards(host)`；`TopSeg.kind` 标记塌陷台与传送带。
- 敌人：`EnemyVariants`（装甲碎铁犬、疾行碎铁犬、重盾卫、散射喷吐者、爆裂骸骨）；`EnemyBase` 增加
  `variant` / `alert_radius`（群警戒）/ `lose_range`（骸骨脱战回巢），默认全 0，与旧行为一致。
- `SpawnSafety`：读档 / 重生坐标落进实心或机关判定区时，退到最后点亮的巢 → 任意巢 → 缺省出生点；
  已接进 `Level01Static` / `Level02Undercroft` / `ChapterLevel`。
- **延后：Boss 韧性（连续终结击打断）**。七个 Boss 各自持有状态机（Executioner / Nightmare 仍是 assist 模式），
  "打断"需要逐个 Boss 的钩子，收益小于风险；改为在 Boss 竞技场里用地形与机关制造压力。若后续要做，
  入口是 `BossDirector` 的 `auto_drive` 五个 Boss。
- 外观检查工具：`tools/hazard_probe.gd`（`scenes/tools/HazardProbe.tscn`）；证据 `screenshots/acceptance/overhaul-v3/p1/`。
- 全量回归：1237 项，除两处本阶段新增用例的测试写法问题（已修）外全部通过，0 engine errors。
  （前序用例会泄漏导演过场锁，机关遇锁冻结，所以机关测试在 `setup()` 里归一化 `Director._set_lock(false)`。）

## 5. P2–P8 落地与未验证项

### 已落地

- **标题。** `TitleScreen.USE_LIVE_SCENE` 打开时，640×360 的 `TitleWorld` 画在原来的 `Keyart` 节点上。锻造字标、左下菜单、旅程刻度、开场/进关/退出和炉厅环境床都在 `title_screen.gd`。`ID_ARENA` 调用 `ArenaRun.start()`。标题右侧「回看余烬」打开总结页（结局、已过章节、试炼、竞技场、再入某一章）。「继续」仍然直接读档。
- **黑屏。** 标题脚本引用 `TitleWorld` 等类。这些类要写在 `.godot/global_script_class_cache.cfg` 里，游戏进程启动时才认。缓存里已经有 `TitleCard` / `TitleChain` / `TitleChip` / `TitleGauge` / `TitleGear` / `TitleLantern` / `TitleSparks` / `TitleWorld`。若编辑器用旧的文件系统索引把缓存覆盖掉，标题会再次解析失败，窗口只剩清屏色。处理：关掉黑窗口，让编辑器重新扫描 `scripts/ui`，再运行。
- **第一章。** 东翼 `EAST_LIMIT` 3760，四段（压板偏殿、锻核工坊、中殿长阶、炉厅竞技场）在 `level01_east_layout.gd`。持久化节点名没改。
- **第二到十章。** 不挪被测试锁住的地面。`scripts/levels/chapter_overhaul.gd` 在 `ChapterLayout.finish()`（level02 在 `build()` 末尾）追加每章 1–2 个专属机关，并给第一只对得上的敌人套变体。蓝图在 `docs/level-redesign/level02.md` … `level10.md`。
- **系统。** 手柄默认键在 `Settings._install_gamepad()`（不覆盖键盘改键）。提示在最近一次输入来自手柄时改画键帽。辅助选项（受伤、弹反窗口、毒素、字幕速度、文本缩放）默认 1.0，不改变现有平衡。设置里可以切分辨率、垂直同步；三种缩放策略仍收成同一条整数画布（`display_fit_test` 锁着这件事）。地图热键是 M / Select，动作名 `world_map`。死亡 0.4 秒后按跳跃可跳过，并提示余烬巢已复位。机关音效键指向现有采样，专用文件以后换上即可。`frame_cost_probe.gd --level=title` 采标题机位。
- **战役 bot。** `tools/campaign_walkthrough.gd` 会在周期机关和摆锤前站住等安全窗，并用辅助选项（受伤 0.6、弹反 1.4、毒素 0.6）走第二章之后的路线。Boss 战本身仍由 `BossFixture` 覆盖。

### 明确没做

多存档槽、完整 i18n、Executioner / Nightmare 迁到 Director、新的玩家招式、Boss 韧性（连续终结击打断）。第二章到第十章没有重挖被测试锁住的地面；专属机关是加在现有路线上的。

### 已跑过的门

- 全量 `tools/run_tests.ps1`：**1396/1396 通过，0 engine errors**（约 473 秒，独立 `%TEMP%` APPDATA）。P0 基线是 1182/1182。
- 布局测试 `layout_test`：**151/151 通过**。`chapter_overhaul_test` 对第二到十章调用 `LevelSanity.check`，通过。`comfort_options_test` 2/2 通过。
- 标题活景截图：`tools/run_title_peek.ps1`，变体 cold / give / keep / snuff，窗口 960×540、1280×720、1920×1080，各一张 idle。12 张都 `saved=true`，在 `screenshots/acceptance/overhaul-v3/title/`。

### 还不能当成通过的项

- 14 章输入验收没有走完。headless `-Campaign -Fast -Ending rekindle` 能打死第一章刽子手、死亡读档、进入第二章，并走到空钟前的余烬巢。空钟一直是 18 血：通用近战脚本砍不中它，90 秒后停在 `hollow_bell_dead`（最近一次日志 `screenshots/acceptance/input-20261024-183711-811`）。Boss 战的正确性由各 Boss 测试和 `BossFixture` 覆盖，不把这次未打死写成通关。
- 每章 5 机位 × 2 分辨率的渲染矩阵、`frame_cost_probe` 的标题机位实跑。
- 真机触屏、手柄实机手感、真人试玩手感、实体显示器上的帧时间。

输入验收和渲染矩阵没跑完之前，不要把「14 章亲手通关」写成通过。全量测试通过不等于那两件事通过。
