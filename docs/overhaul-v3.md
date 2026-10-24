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
- **分支**：最初为 `feature/overhaul-v3`（自 `merge/all-branches` 的 `8bfa46f` 基线提交切出）。
  当前续作在独立 `codex/overhaul-v3-completion`，以整合基线 `8b91f22` 开始；原目录的未提交改动不纳入本次提交。

## 1. 基线（P0）

- 工作区的标题 WIP（`dossier_jag` / `keyart_knight_light` / `title_metrics` / 0.2.0 版本号）已做基线提交 `8bfa46f`；
  无关的 `artifacts/taihe-cherry/*.pptx` 未纳入。
- 导入后全量回归：**1182/1182 通过，0 engine errors**（约 305 秒，独立 `%TEMP%` APPDATA）。
  日志：`screenshots/acceptance/overhaul-v3/baseline/stdout.log`（`screenshots/` 为 gitignore 的本地证据目录）。

## 2. 阶段清单

- [x] P0 基线与分支
- [x] P1 机关工具箱（`scripts/hazards/`）+ 敌人变体/脱战/群警戒 + 读档坐标安全 + Boss 连续终结击破势
- [ ] P2 标题活景（`TitleWorld`）+ 版式与动效重做 + `ID_ARENA` 接线
- [ ] P3 第一章（前半微调 + 后半重建）
- [ ] P4 第一幕：level02 / level02b / level03
- [ ] P5 第二幕：level04 / level04b / level05 / level06
- [ ] P6 第三四幕：level07 / level07b / level08 / level09 / level09b / level10
- [ ] P7 系统升级：手柄、辅助选项、显示设置、地图热键、回看余烬总结页、复活 QoL、机关音效、性能预算
- [ ] P8 总验收：战役 bot（机关感知 + 辅助选项）、14 章输入验收、渲染矩阵、性能探针、文档与最终报告

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
- **Boss 韧性已补齐**：5 秒内两次实际造成伤害的玩家剑终结击触发破势；轻击、重击、火焰/剑波、反射物、
  格挡和无敌帧不累计。普通连段不会清掉已有累计。七个 Boss 各自撤回当前近战与预警，停止移动并露出金色空当，
  恢复期 0.8 秒，触发后 1.6 秒免累计；已发射弹体与场地机关仍按原寿命运行。暂停、过场锁、导演冻结时计时停止，
  重试/死亡清空累计。没有新增伤害倍率，也不改变阶段、缩放或攻击表。
- 外观检查工具：`tools/hazard_probe.gd`（`scenes/tools/HazardProbe.tscn`）；证据 `screenshots/acceptance/overhaul-v3/p1/`。
- 全量回归：1237 项，除两处本阶段新增用例的测试写法问题（已修）外全部通过，0 engine errors。
  （前序用例会泄漏导演过场锁，机关遇锁冻结，所以机关测试在 `setup()` 里归一化 `Director._set_lock(false)`。）

### 2026-10-24 续作：Boss 破势验收

- `tests/boss_poise_test.gd`：6/6、111 条断言，覆盖七个 Boss 活动判定立即撤回、前摇/预警取消、实际命中路径、
  格挡/致死优先级、轻击保留累计、过期/冷却、暂停/过场/重置，以及阶段与判定形状不变。
- 全量 `tools/run_tests.ps1`：**1298/1298 通过，0 engine errors**；
  `screenshots/acceptance/overhaul-v3/p1-poise/full-final/summary.json` 确认 `completed=true`、`passed=true`。
- 真实第一章竞技场的渲染夹具 `scenes/tools/BossPoiseAcceptance.tscn`：三张截图已查看，
  `p1-poise/render/report.json` 确认破势、近战撤回、金色空当与恢复均通过，无引擎错误。
  夹具会摆放角色并注入两次真实伤害调用，**不能替代正常输入通关**。
- 整合基线已有标题/第一章、02/02b 地形与手柄默认映射；其余章节与系统仍需按各自门禁完成。
  阶段清单保留未验收项，不沿用附件中未经证据支持的完成标记。
