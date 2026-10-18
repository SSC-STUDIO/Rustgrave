# 竞技场（Arena）—— 垂直切片

## 已交付：限时生存切片（Round 8）

目标：先把「模式入口 / 独立记录 / 不写战役档 / 计时计分 / 结算回标题」这条骨架跑通，
再用后续迭代把"3v3 推线"逐件塞进来。

- 入口：标题屏右侧 `行程档案` 里的 `ArenaEntry` 按钮（不占六格菜单，标题屏菜单测试不受影响）。
- 场景：`scenes/levels/Arena_Duel.tscn` + `scripts/levels/arena_duel.gd`
  - 900px 宽单屏场地、地面 + 两块浮台、左右墙；
  - 玩家出生在左侧，`HUD.tscn` 正常显示心/毒素/技能条；
  - 每隔 `WAVE_INTERVAL=6s` 从右侧刷一个敌人（scrapper / spitter / ghost），同屏上限 4。
- 运行时：`scripts/autoload/arena_run.gd`（Autoload `ArenaRun`）
  - `start()`：`GameContext.pending_world_path = Arena_Duel` + `Director.fade_to` 表现层；
  - 90 秒倒计时、击杀加分（scrapper 20 / spitter 30 / ghost 35）、右上角 `ArenaHud` 条；
  - 存活到 0 秒 = 胜；`GameEvents.player_died` = 负；结算条 2.5s 后回标题；
  - 记录写独立文件 `user://rustgrave_arena.cfg`（best_score / best_kills / runs），
    损坏/缺文件回退默认，**绝不写战役 SaveData**（`SaveData._trial_active()` 已包含
    `ArenaRun.blocks_campaign_save()`）。
- 规则数据：`scripts/data/arena_catalog.gd`（场景/时长/波次/敌表/格式化）。
- 测试：`tests/arena_run_test.gd` 4/4（规则/记录/不锁战役档/标题入口）；
  回归 `save` 29/29、`save_migration` 6/6、`player` 27/27、`equipment` 61/61 等。
- 截图：`screenshots/peek/arena/arena_duel.png`（右上角"竞技场·剩余·击杀·得分"）。

## 尚未交付：真正的 3v3 推线

这一版**不是**王者式 3v3，以下都还没做，属于后续迭代：

1. 兵线：小兵波次 AI、对线推进、补刀经济；
2. 防御塔/水晶：塔的索敌优先级、射程、拆塔与水晶胜负条件；
3. 队伍：玩家 + 2 AI 队友 vs 3 AI 敌方，AI 集结/撤退/抢目标；
4. 地图：多线/野区/草丛/回城/商店；
5. 竞技 HUD：双方比分、塔数、击杀播报、复活倒计时、技能冷却盘、触控技能键；
6. 赛季/段位/匹配（单机无需匹配，但可以有段位计分）。

下一步建议顺序：D1 队伍战斗地基（team 已支持）→ D2 塔/水晶 → D3 兵线与 3v3。
