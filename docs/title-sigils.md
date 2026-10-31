# 印记：炉厅记得你来过（`EmberSigils` + `TitleSigilRing`）

> v3.1 标题屏创新。设计一句话：**存档是这一世，印记是每一世**——删档擦不掉炉厅的记忆。

## 它是什么

标题字标外多了一圈铁与余烬。`EmberSigils`（autoload，`scripts/data/ember_sigils.gd`）
只记两件事：

| 事件 | 触发点 | 记录 |
| --- | --- | --- |
| **点燃**（visit） | 标题真正开始一次旅程：`_start()`（继续 / 回看后再入）与新游戏交接处 | `{d: 天戳, k: new/continue, c: 章节 id}` |
| **殁**（death） | `GameEvents.player_died`（autoload 直连，标题不在场也记） | `{d, k: "death", c: 死亡所在章节}` |

数据在 `user://rustgrave_sigils.cfg`，与存档分开；上限点燃 96 条 / 殁 64 条（留最近）。
`headless` 会话（自动化套件、工具）不写生产记录：`record_visit` / `record_death`
在 headless 下是空操作，测试走 `append_raw` + `store_path` 重定向。

## 它长在哪

1. **印记环**（`scripts/ui/title_sigil_ring.gd`，挂在 Masthead 之后、字标之前）：
   - 每次点燃是一枚沿椭圆排布的刻度，从左尾端顺时针爬过 12 点——那里留着
     **第一次点燃的凹口**；最新一枚停在右尾端，带余烬脉动；
   - 刻度按真实日数冷却（30 天凉透）：`HOT → COLD`；
   - 每次「殁」是里圈一粒锈红菱形，最新的一粒更亮；
   - 底部开口 36° 让位给副题，尾端落在副题饰件外侧；冷启动（无记录）整环不画；
   - 悬停某枚刻度 → 页脚写「印记 · 第 N 次点燃 · 章节 · 多久之前」
     （`hover_changed` 信号 → `_on_sigil_hover`）；
   - 开屏时环随字标锻入从 12 点向两侧点亮（`wake()` / `skip_reveal()`）；
   - 纯 `_draw()`，2px 台阶，无 PointLight2D（UI 层光源预算 0 不变）。
2. **私人墓志**：经典句之后追加「炉厅记得 · 你已点燃 N 次」与
   「上次殁于某章 · 多久之前」（`_personal_epitaph_lines()`；第一句永远是 EPITAPH）。
3. **档案卡「旅程」新增印记行**：「第 N 次点燃 · 殁于某章」（`DossierSigil`）。
4. **行尾英文魂注**（`MenuItem.ghost`，灯标行专用）：EMBER / TRIALS / ARENA /
   SYSTEM / CONTROLS / LEAVE，冷铁灰，选中时烧暖并向内收 2px；
   「继续旅程」有行内小注，不挂魂注。

## 测试与截图

- 回归：`tests/ember_sigils_test.gd`（存储往返 / 上限 / 人话时间 / 章名反查 /
  headless 闸门 / 环的显现 / 标题集成：环、墓志、魂注、档案卡 / 冷启动安静）。
- 截图：`tools/title_peek.gd` 照常（`RUSTGRAVE_PEEK_ONSCREEN=1` 供 Linux/Xvfb 用）；
  `.github/workflows/render-title-shots.yml` 在 Linux runner 上渲染
  `docs/shots/title-v4/` 并回推分支。

## 有意不做的事

- 竞技场 / 回火试炼不计「点燃」——印记只属于旅程；
- 删档不清印记（设计核心）；设置里未来可加「遗忘炉厅」按钮，本期不做。
