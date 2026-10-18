# 水池 / 夜雾（用户反馈修复）

## 1. 毒液坑：人不再"站在水面上"

### 问题
- 坑内攀爬石阶的顶面与水面同高（都 336），骑士落在石阶上等于站在水面：身体与池水判定
  框几乎不重叠，`ToxinPool` 收不到 `body_entered` → 不掉毒。
- 水体精灵画在角色之后（z=0），人看起来是"干着站在水里"，透过水也看不到浸没感。

### 现在
- 水面 `PIT_WATER_Y = 328`（比岸 320 低 8px），比坑内石阶（336）高 8px；水体
  `PIT_WATER_SIZE = (112, 40)` 盖住坑底 352。相关常量只在 `level01_east_wing.gd` 一处，
  `level01_static.gd` 用它们设置 `Props/ToxinPool` 位置与尺寸。
- `ToxinPool.z_index = 3`：池水画在角色/坑内石阶之上，下水后腿与腰被水色压住。
- 站上没入水面的石阶也会被判定在池中，按 `toxin_per_second` 累积毒素；HP 只在毒素满溢时
  扣（设计如此，不是"无效"）。
- 回归：`tests/interactables_test.gd` 新增 `test_submerged_climb_stone_wades_in_the_sludge`
  （几何常量 + 真实物理两层断言）；`tests/level01_layout_test.gd` 断言水面比石阶高 8px。
  过滤跑：`interactables` 12/12、`level01_layout` 22/22。

## 2. 夜雾不再盖住天空

- 旧 `FogVeil` 是整屏 `ColorRect`，夜里连月亮/远山都被压成白雾。
- 现在 `Level01Parallax._add_fog_veil` 用 `GradientTexture2D` 生成竖向渐变：
  屏幕 38% 以上透明，72% 处开始明显，底边最浓；颜色与 alpha 仍由
  `WorldClock.fog_veil_alpha()` 与章节 palette 驱动。
- 雾带（far/near/ground）与天气强度不变；天空、月亮、远山保持清晰。
- 验证截图：`screenshots/peek/water/fog_night_gradient.png`（Level01、夜、浓雾）。

## 3. 回归范围

- `level01_layout`、`interactables`、`hit_feedback` 全绿。
- 旧存档兼容：只改显示/几何常量，不改 `SaveData` 结构。
