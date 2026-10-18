# 标题与启程界面扩充（v3）

## 0. 标题屏菜单架（重做后）

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

## 1. 标题屏：右侧「行程档案」

`title_screen.gd` 在原有"字标 + 左侧铁架 + 墓志/署名带"之外新增 `Dossier` 石板（右侧，StonePanel）：

- **余烬阶位**：`EmberRank.summary(SaveData.ember_xp)` + 可分配点数；无存档显示占位文案。
- **当前外观**：`SkinCatalog.name_of(SaveData.skin_id)`。
- **回火试炼**：读 `TrialRecords.all()` 的记录条数。
- **余烬竞技场**：`ArenaRun.read_records()` 的最佳分 / 场次（未玩过显示"未踏足"）。
- **上次行程**：存档 scene → `GameContext.LEVELS` 反查章节 → `ChapterText.recap_of()`（没有 recap 用标题）。
- 底部一行提示：Tab / Esc / 存档点在烬巢；有版本时下方出现小号「有新版本 · 查看」。

节点名（测试/后续扩展）：`Dossier`、`DossierRank`、`DossierSkin`、`DossierTrials`、`DossierChapter`。
无存档时面板不隐藏，四行都显示占位，避免标题屏"空"。

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
- 回归：`title_flow` 5/5、`modal_screens` 5/5、`character_select` 10/10、`pause` 4/4、`settings` 16/16、`hud` 16/16。
- 截图：`screenshots/peek/v3-ui/title_dossier.png`、`char_select_appearance.png`。
