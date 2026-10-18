# 开场与过场演出

开新游戏时，黑场只走标题那一次淡入，揭开的是第一章的真实墓园，不再盖程序化幻灯片。同一条可跳过的剧本约 44 秒（预算 45）：前 3 分钟的可读性由这一段铺开，**世界观、身份、目标、阻碍各说清**（每类可拆成两拍），其余是画面钉字幕的短句。没有第二段醒来。

## 开场分镜（前 3 分钟可读化 · M1R3）

文本单一源在 `ChapterText.OPENING`（`OpeningCinematic.LINES` 委托它），分镜是**处境 → 誓约/守炉人/净化偶（四拍）→ 伊尔与回声（两拍）→ 名字（一拍）→ 时间线（四拍）→ 异象 → 目标（两拍）→ 阻碍**。每个专名第一次出现就在那句里给白话：

- **处境（0.0s）**：你趴在冷余烬巢旁，死亡动画倒放撑起身体，巨剑先被**种在土里**（`Greatsword.spawn_planted`，剑尖落在地面线上、z 低于你）——"剑先锈了。核里还有人。"火星从剑背应声而起。
- **誓约/守炉人/净化偶（2.8s，四拍）**：镜头退到巢与坟，最近的坟依次冒灰。"那座誓叫炉约：烧名字换灯，立了二百年。""立誓的那批人，叫守炉人。""守炉人造过很多具净化偶——刮锈的人偶。""你不是被选中的；你是最后一具，自己先锈透了。"
- **伊尔与回声（11.5s，两拍）**："伊尔从渣里捡回你，嵌核进剑，点亮你。""你听见的是回声——她封进核之前的话。"——伊尔的动作都发生在封核之前，此后只有回声。
- **名字（16.0s）**："名字刻在剑上，烧进铁里，人就回不来。"
- **时间线（18.5s，四拍）**："炉心是城下的大炉膛，一百年前熄了。""残芯是炉心最后一口火封成的核。""最后一百年，灯靠残芯当灯芯。""灯越来越暗。她把核从座上取下。"——一条时间线，残芯在哪不再自相矛盾。
- **异象（26.0s）**：地下一声钟，每座坟依次冒灰回应，镜头沿走廊往东；"钟响了一声。底下有人在数。"走到一半走廊尽头先应一声低钟、亮一团暖光（`ECHO_AT`）。
- **目标（29.3s，两拍）**：走廊尽头空炉座的光跳两下，刽子手的剪影立在门后；"带剑里的残芯到炉心，替名字问火一句。""这火该不该还？"——全篇的问题在这里第一次说出口，两个结局都要回答它。
- **阻碍（33.4s）**："刽子手守着炉座。他发过誓。"——你已经看见门后那个人，字幕才说他守什么（守座，不是守核）。
- **交接（35.4s）**：章节卡"锈墓・壹 — 腐液回廊"，镜头在卡下直接切回你，不从走廊尽头飞回来。脚边火星、巢边余火先响；等整个 Director 队列清空后才显示移动提示，第一次真实输入即消失。

第一拍的构图按 2.35 倍推近（`ZOOM_CLOSE`）：趴着的人只有约 40px 宽。起身时收刀回背上，跳过 / abort 都走同一条 `_end_rise` 还原——"剑杵进地里"是画面，不是台词。

按 Enter、空格或点击「跳过开场」会跳过整段，包括章节卡。继续游戏、死亡读档、已经看过都不重播。`opening_seen` 和 `wake` 在整段正常结束或跳过时一起点上；死亡或切场中断则两点都不点，也不写结局。

## 章节到达与章间间幕

每次 `chapter_started`，StoryStage 先做一次硬复位（旧锁、旧字幕、旧遮幅、旧镜头、旧提示、未开的 deferred 剧本全部作废）。然后按顺序：

1. **间幕**（仅当上一章→本章的间幕没看过）：`StoryFlow` 的 epilogue（上一章余波 2–3 句）+ teaser（本章钩子 1 句）+ 一句**本章目标**（`ChapterText.objective`，≤16 字）。布景按边界 `staging` 标记画（door/water/canal/town/crypt/workshop/rain/bell/foundry/slag/rampart/wind/heart），只画几何、不建节点，暂停即冻结。
2. **章节卡**：`ChapterLevel.chapter_card()` 从「锈墓・章节 — 地名」生成，显示 2.6 秒。
3. **醒来句**（`ChapterText.wake`，≤30 字）+ **目标一句**（`目标 · …`）。
4. 出口门自己念 `ChapterText.exit_captions`（离场字幕，1–2 句），然后淡入下一关。

间幕的语义（`scripts/levels/chapter_transition.gd`）：

- **一次**：旗标 `interlude_<from>_seen`；进过一次就不再播。
- **可跳过**：Enter / 点「跳过」结束整段；跳过也算看过。
- **暂停冻结**：`Director.suspend()` / `tree.paused` 时布景时钟停走。
- **死亡读档不重播**：旗标在开演时点上；死亡打断也算看过，读档回来不再播。
- **切场硬复位**：`reset_view()` 幂等；新关的间幕/章节卡从干净构图开始。
- **不写未完成章节旗标**：间幕只写自己的旗标，绝不写 `levelNN_done`。
- **结局前后特殊序列**：进第拾肆章前的间幕固定 `heart` 布景并追加 `StoryFlow.SPECIALS.pre_ending` 台词；结局字幕（送剑 / 守火 / 提前离场）从 `ChapterText.ENDINGS` 取，`StoryFlow.post_ending_steps()` 在同一份文本上加收束句。

## 暂停菜单「前情提要」

暂停菜单档案卡多一行「前 情」：`StoryFlow.recap_text()` 按存档里**已通关章节**挑最近 1–2 条 `ChapterText.recap`（≤40 字）拼成一句；还没通关任何章节时显示兜底句「你刚醒。剑里有人。」（`StoryFlow.RECAP_FALLBACK`）。不剧透没走到的章节。

## 章节与关键事件

事件覆盖（全部走 Director，同一条 skip 契约）：

| 事件 | 演出 |
| --- | --- |
| Boss 登场 | 名号卡由 `boss_appeared` 画；`boss_intro_steps` 先把竞技场交出来（1.05×），吼声与冲击环压出体量，再推近到 1.2× 留一拍。第一章的拱门入场由 `Level01StoryBeats.on_boss_gate` 单独负责。 |
| 阶段变化 | `phase_steps` 锁一次镜头、吼叫、相变光环、推近、留一拍；不重复字幕 —— Boss 自己的 `announcement` 已把同一句放在 HUD 上。名号卡若已按时退场，`boss_phase_changed` 会把它短暂重新举起，相数刻度跟着涨。 |
| 击败 | `boss_defeat_steps` 慢放、震屏、镜头给跪下的身体；有下一扇门时再把镜头交给门里的火。第一章的 `on_boss_slain` 用同一语法单独演残芯。 |
| 能力获得 | 拾取：镜头、戒指、冻帧、插座火星、职称一句。嵌核：同一套镜头之后多一张 `tableau id=ability` 的紧凑「新动词」铁牌（如「热锻 / 新 的 动 词」），不压暗世界、不抢输入；能力名由卡报，字幕只念核里的那句职称。Music 的 `ability` stinger 仍在。 |
| 章节过场 | `ChapterLevel.chapter_card()` 从「锈墓・章节 — 地名」生成；第一章的卡在开场里。出口门的离别字幕由 `LevelExit` 从 `ChapterText.exit_captions_of()` 取。 |

## 可恢复性

- **暂停 / 挂起**：Director 的整条时间线（等待、字幕、遮幅、镜头缓动、skip 按钮）与章间布景一起冻结；暂停菜单关闭后从原处继续。
- **跳过**：开场、StoryStage 的关键事件、间幕都 `play(..., true)`；一次确认结束整条并解锁。`skip_step` 会释放镜头、清字幕、清队列、复位冻帧/慢动作。章节卡和 Boss 名号也会立即退场。出口门的离别字幕仍按 Director 默认的逐拍跳过，同样随时可以走完。
- **死亡 / 切场**：`Director.reset_view()` 是硬复位 —— abort 掉正在播放或还在等待的剧本，输入、镜头（1×）、遮幅（同一帧收起）、字幕、提示、名号卡、时间效果一起还原；StoryStage 在 `chapter_started` 与 `player_died` 上调用它，`ChapterTransition` 同步收掉间幕布景。
- **不重播**：开场用 `opening_seen` + `wake`；StoryStage 的一次性事件用持久旗标；间幕用 `interlude_<from>_seen`；死亡读档会回卷旗标，所以 StoryStage 另存本会话记忆。中断（abort）不算看过开场；跳过算看过。New Game 与回标题会清掉会话记忆。
- **交还提示**：开场的移动提示等到 `finished`（队列真正清空）才出现；若后面还压着一段过场，它不会先闪一下再被盖掉。

## 作者接口

Director 步骤 `{"kind": "tableau", "id": "chapter"}`、`"boss"`、`"ability"` 显示卡片；`"world"` 回到游戏。`chapter` / `boss` 用 `title` / `subtitle` 传文字，带 `seconds` 时为可继续的计时拍，不带时即时切画面。`ability` 是紧凑卡，不铺全屏暗底。`ChapterLevel.chapter_card(title)` 从「锈墓・章节 — 地名」生成章节拍。开场不使用分镜 id，它只推动关卡里的 `cam_focus` 和底部字幕。

间幕不使用 tableau：`StoryFlow.arrival_steps(to_id)` 产出纯 Director 步骤，`ChapterTransition` 负责布景；文本改 `docs/story.md` §11 + `StoryFlow.BOUNDARIES`，两边由 `tests/story_flow_test.gd` 比对。

`fx` 步骤支持 `target`（Node2D 或世界坐标），保证余烬、冲击环、残芯脉冲落在剧情对象身上。开场的走廊回声与铁门声是代码驱动的世界音效，跟随 dolly 的时间线，跳过时随 dolly 一起清掉。

章节卡和 Boss 名号使用固定 640×360 构图，画在原有 UI 适配层上。Boss 名号上的余烬是有上限的直接绘制，不持续创建粒子节点。能力卡也是同一张 640×360 画布上的直接绘制，无节点增长。

## 复验

四个演出域各自跑一遍（测试过滤按文件路径子串匹配）：

```powershell
./tools/run_tests.ps1 -CaseFilter opening_cinematic
./tools/run_tests.ps1 -CaseFilter director
./tools/run_tests.ps1 -CaseFilter cinematic_presentation
./tools/run_tests.ps1 -CaseFilter cutscene_safety
./tools/run_tests.ps1 -CaseFilter story_flow
./tools/run_tests.ps1 -CaseFilter chapter_text
```

实际渲染截图用 Godot 打开 `scenes/tools/CinematicAcceptance.tscn`；需要 OpenGL 窗口环境。该工具使用单独的临时存档，把第一章载进画面壳，产出至 `screenshots/acceptance/cinematics/`：骑士、坟、余烬巢三拍、回到可操作的墓园、章节卡、Boss 名号、640×360 下的章节卡，以及 `report.json`。这些是演出播放及视觉夹具，不能代替全流程通关或真实手机验收。原有 OpenGL 退出阶段可能报告纹理 / CanvasItem 资源清理告警；需同时查看渲染日志，不只看截图报告。
