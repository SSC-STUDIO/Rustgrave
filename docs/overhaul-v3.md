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
- [ ] P1 机关工具箱（`scripts/hazards/`）+ 敌人变体/脱战/群警戒/Boss 韧性 + 读档坐标安全
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

（随实现追加。）
