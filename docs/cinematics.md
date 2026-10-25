# 开场与过场演出

剧情怎么讲：**全屏分镜**负责「讲清世界和因果」（序章、13 段章间、三个结局、滚动字幕），**关内字幕 + 镜头**负责「钉在画面上的短句」（醒来、目标、Boss、拾核）。故事本身见 [docs/story.md](story.md)，文本单一源在 `scripts/data/chapter_text.gd`（章内）与 `scripts/data/storyboards.gd` / `scripts/data/story_flow.gd`（分镜）。

## 1. 分镜系统（三层）

| 层 | 文件 | 管什么 |
| --- | --- | --- |
| 数据 | `scripts/data/storyboards.gd`（`Boards`） | 纯数据 + 纯函数：`id → [镜头]`。镜头 = 布景 `set` + 演员 `actors` + 运镜 `cam` + 粒子 `fx` + 台词 `lines` + 可选插图 `art`。台词全部来自 `ChapterText` / `StoryFlow`，这里只配画面 |
| 舞台 | `scripts/ui/storyboard_stage.gd` | 640×360 的实时拼图：`ThemeBackdrop` 主题图层 + 标题大厅 + 程序化像素演员（骑士用真实帧动画）+ 余烬 / 灰 / 尘粒子 + 整像素推拉平移。镜头有插图且文件在时改用插图（演员不画，粒子保留） |
| 播放器 | `scripts/ui/storyboard_player.gd` | CanvasLayer 层 13（UI 层 1280×720 单位，舞台放大 2 倍）：说话人名牌 + 打字机、上下转场、跳过按钮、滚动字幕；输入、暂停冻结、abort、看过旗标 |

分镜 id：`prologue`（序章）、`interlude_<from>`（13 段章间，`<from>` 是上一章 id）、`ending_give` / `ending_keep` / `ending_snuff`、`credits`（滚动字幕）。

接入 Director：步骤 `{"kind": "board", "id": ..., "skip_all": bool}`。步骤等分镜播完才进下一步；`Director.estimate_seconds` 把它算成 `Boards.seconds_of(id)`；`abort()` / `reset_view()` 收起分镜。其余新接口：

- `Director.board()`：常驻的播放器；`Director.board_active()`：有分镜在演（含故事页回放）。
- `Director.board_blocks_pause()`：非回放的分镜在演时为真，`PauseMenu.open()` 据此**不开暂停菜单**（菜单会盖住分镜，分镜自己有跳过）。
- `caption` 步骤可带 `who`（说话人）；不带时按「说话人：内容」前缀自动拆名牌（只认 `ChapterText.SPEAKERS`）。

### 画面词汇

- 布景 `set`：`ThemeBackdrop` 的主题名（graveyard / undercroft / forge / forge_core / cathedral / belltower / ramparts / town / industrial）+ `title_hall`（标题大厅）+ `dark`（纯黑）。不认识的布景退成纯黑，不报错。
- 演员 `[kind, x(0..1), scale]`：`knight`（当前外观的真实待机帧 + 背剑）`seed` `flame` `souls` `swords` `gate` `figure` `yir` `ash_guard` `ring`。
- 运镜：`still push pan_right pan_left rise`。粒子：`embers ash dust none`。
- 词汇表在 `storyboard_stage.gd` 的 `ACTOR_KINDS / CAMS / FXS / EXTRA_SETS`，`tests/storyboard_test.gd` 把每个镜头逐个对一遍——加新演员 / 布景要两边一起改。

### 操作与跳过语义

| 分镜 | Enter / 点击 | 按住 Enter（0.8 秒）/ 点「跳过 ▸▸」 | Esc |
| --- | --- | --- | --- |
| 序章、结局、滚动字幕（逐句） | 先写完这句，再推下一句 | 跳过**整段分镜** | 不开暂停菜单 |
| 章间（`interlude_*`） | 一次就跳过整段 | — | 不开暂停菜单 |
| 故事页回放（`replay`） | 同逐句 | 同逐句 | 跳过整段 |

- **输入宽限**：分镜开始后 0.35 秒内的 Enter 不算（刚按下的交互键 / 菜单确认键不能一帧把它跳过）；按住计时要先松开过一次才开始。
- **分镜自己决定 Enter 的含义**，哪怕外面这条剧本是 `skip_to_end`：`Director.skip_step` 在等分镜时直接把 Enter 转给播放器，**序章里的 Enter 不会连同后面的场内开场一起吞掉**（`tests/storyboard_test.gd` 锁着）。
- **跳过算看过**：整段播完或被跳过，播放器写 `board_seen_<id>` 旗标（故事页「回放」只列看过的）；**回放不写旗标**；**abort（切场 / 死亡 / 回标题）不算看过**，`board_finished(id, false)`。
- **暂停冻结**：`tree.paused` 或 `Director.suspend()` 时播放器的整个时钟（含骑士待机动画、粒子、打字机）停走；回放（`replay`）自己读键，暂停中也能播。回放的层号抬到 24，盖在暂停菜单（20–22）之上。
- **接在上一段后面**（结局 → 滚动字幕）从黑幕直接续上，不闪出场景。

## 2. 新游戏：序章 → 场内开场 → 章节卡

```
标题淡入 → [序章分镜 8 镜头，约 38 秒，逐句]
        → 醒来七拍（关内，约 23 秒）→ 章节卡「锈墓・壹 — 腐液回廊」→ 交还操作
```

同一条可跳过的剧本（`OpeningCinematic.steps()`，整段预算 72 秒、下限 50 秒；关内部分预算 30 秒）：

0. `lock` → **board `prologue`**（`skip_all: false`，骑士这时已趴在黑幕后面）
1. 关内：你趴在冷余烬巢旁，死亡动画倒放撑起身体，巨剑先**种在土里**，起身时拔回背上。
2. 七拍字幕（`ChapterText.OPENING`，每句 ≤22 字，台词写成「伊尔：……」带名牌）：处境 → 剑里的声音 → 回声（封进火种之前说的话）→ 异象（钟、坟冒灰、镜头东移）→ 目标 → 路线 → 阻碍（刽子手立在门后）。
3. 章节卡（2.6 秒）→ `letterbox` 收 → `cam_release` → `unlock`；移动提示等队列真正清空后才出现。

序章 8 镜头（每个专名第一次出现就在那句里给白话；台词见 `storyboards.gd`，镜像在 story.md §9）：城与炉 → 炉约 / 守炉人 → 名字烧掉、魂困在铁里 → 炉心熄 / 火种 → 炉座当灯芯 → 伊尔自述 → 伊尔叫醒你（余烬骑士）→ 代价。

旗标语义（`opening_seen` + `wake` 一起点）：

- **跳过算看过**：Enter / 点按钮跳过（关内部分一次 Enter 跳过整段）→ 整条剧本走完 `script_finished` → 点旗。序章被单独跳过（按住 Enter）只结束序章这一步，关内部分接着演。
- **死亡 / 切场中断不算看过**：abort 只发 `finished`，不点旗、不写结局；下次新游戏重新播序章。
- 继续游戏、读档、已醒过、已有结局：不播。

## 3. 章节到达与章间

每次 `chapter_started`（`ChapterLevel` 与第二章 `Level02Undercroft` 都发），StoryStage 先做一次硬复位（旧锁、旧字幕、旧遮幅、旧镜头、旧提示、未开的 deferred 剧本全部作废），然后**严格按这个顺序**：

1. **章间分镜**（`interlude_<上一章>`，仅当没看过）：epilogue（上一章余波 2–3 句）→ teaser（下一站 1 句）→（终章前）两个选择的代价。`StoryFlow.arrival_steps(to)` = `lock → board → unlock`，**不含目标**。
2. **章节卡**：`ChapterLevel.chapter_card()` 从「锈墓・章节 — 地名」生成，2.6 秒。
3. **醒来句**（`ChapterText.wake`，≤30 字）。
4. **目标一句**（`目标 · …`，`ChapterText.objective`，≤16 字）。**目标只在这里念一次**；HUD 的目标条（`ObjectiveTracker`，Tab 查看 / 章首 5 秒）是另一条实时提示，演出期间被遮幅压下，不重复念。
5. 出口门自己念 `ChapterText.exit_captions`（离场字幕），然后淡入下一关。

2–4 是 `ChapterLevel._wake` / `Level02Undercroft._wake` 的同一份 `play_when_clear` 剧本，排在 Director 队列里章间分镜的后面（分镜占着屏幕时它们只会入队，跳过分镜不会吞掉章节卡）。

第二章（沉钟地窟）有自己的场景脚本；它现在也发 `GameEvents.chapter_started("level02")`，所以 01→02 的章间会播；它的章节卡 / 醒来句 / 目标和其他章同一套语义（`StoryStage.once("l2_wake")`，死亡读档是「回来」不是「到达」）。

章间执行器 `scripts/levels/chapter_transition.gd`：

- **一次**：旗标 `interlude_<from>_seen`，开演那一刻点上（`StoryStage.once`，同时记本会话记忆）。
- **死亡读档不重播**：读档会把旗标回卷到上一次存档；本会话记忆补这个缺口（只在真实一局里——`wake` 已点——才认）。回标题 / 新游戏清掉记忆。
- **从未开演的不算看过**：暂停 / 淡变期间排队、被 abort 掉的章间，旗标没点，之后照常播。
- **跳过也算看过**：章间是 `skip_all`，一次 Enter / 点击整段跳过。
- **模式门**：`live()` 在回火试炼（`TrialRun.active()`）与余烬竞技场（`ArenaRun.active()`，经节点 + `has_method` 防御读取）里为假：这两种模式**不出章间分镜 / 章节卡 / 几何遮罩**。测试跑器里也默认 inert（`test_enabled` 打开）。
- **兜底**：某条边界没有分镜时退回 `lock → 全部台词字幕 → unlock` + 几何布景 `StagingArt`（13 种 staging，暂停冻结）。现在 13 条都有分镜，兜底只留给以后新增的边界。
- `abort()` / `reset_view()` 一起收掉分镜层与兜底遮罩；不写任何章节完成旗标。

## 4. 结局

结局选择菜单（层 25，`choice_hold` 期间暂停菜单不响应 Esc）→ 选完：

- **还火 / 守炉**（`LevelExit.confirm_ending`）：写 `SaveData.ending`、解锁试炼、发 `ending_chosen`（Music 切 `ending` 曲 + stinger；StoryStage 收提示；`ChapterTransition` 复位）→ `ending_play_steps`：`lock → fx heart_pulse → fx ash_fall / ember_rise → board ending_<kind> → board credits → wait → unlock` → 存档（此时 `board_seen_*` 旗标随之落盘）→ 淡出回标题。
- **熄火**（`ForgeHeart`，第一章炉座前）：同一套结局分镜 + 滚动字幕；播完补一次 `persist_story`，让「看过」旗标落盘。**续火**不是结局，只是一句两行字幕然后去第二章。
- 结局字幕全部由分镜念出：`ending_<kind>` = `ChapterText.ENDINGS[kind].lines` + 一句收束（`StoryFlow.SPECIALS.post_ending`，熄火的「再没有人替名字问一句」不再丢）。三张结局插图挂在和画面一致的那一镜：还火挂「散成铁屑」，守炉挂「守下去」，熄火挂「炉门里一点红」。
- 分镜期间 Esc **不开暂停菜单**（`Director.board_blocks_pause()`），所以菜单不会盖住结局，也不会出现「菜单开着、结局还在背后走」；跳过用按住 Enter / 点「跳过」。分镜间的 0.5 秒收尾淡出里允许暂停，Director 挂起后整条剧本冻住。

## 5. Boss 名号卡

名号卡由 `boss_appeared` 画（名号字符串在各 Boss 脚本里，**不改**）。卡面上沿多一行白话（`ChapterText.boss_intro`，如「守 座 的 人」）：`CinematicPresentation` 按玩家所在章读它，相变重举卡时一并重画；不在战役关卡里 / 这一章没有 Boss 介绍时不画。Boss 的身份交代靠到达分镜里伊尔的话。

## 6. 关键插图（7 张）

分镜的 `art` 槽对应 `assets/story/<id>.png`（或 `.jpg`，`.png` 优先）。7 个 id：

| 文件名（不含扩展名） | 挂在 | 画面 |
| --- | --- | --- |
| `prologue_city` | 序章第 1 镜 | 锈墓：建在大炉子上的城，炉口的火 |
| `prologue_names` | 序章第 2 镜 | 炉约：刻名的剑被魂群送进炉里烧 |
| `prologue_yir` | 序章第 6 镜 | 最后一个守炉人伊尔把自己封进火种、嵌进剑 |
| `prologue_knight` | 序章第 7 镜 | 伊尔从熔渣里捡回、修好生锈的人偶骑士，火种在剑里亮起 |
| `ending_give` | 还火「散成铁屑」那一镜 | 魂光成柱升起，伊尔回头，骑士碎成铁屑 |
| `ending_keep` | 守炉「守下去」那一镜 | 骑士坐在炉火前拄剑守着，城还亮着 |
| `ending_snuff` | 熄火「一点红」那一镜 | 全城黑暗，炉门里一点红，剑躺在地上 |

**插图不在仓库里也能通关**：文件不存在 / 还没导入 / 加载失败时，舞台静默退回实时拼的同一镜头（布景 + 程序化演员），不报错、不留空画面。

**把图放进仓库**（图像生成工具把文件存在 Cursor 项目目录，不在仓库里）：

1. 7 个文件在 `C:\Users\Administrator\.cursor\projects\c-Users-Administrator-OneDrive-Documents-My-Program-Rustgrave\assets\`，文件名 `<id>.jpg`（1024×576，16:9）。
2. 拷到仓库的 `assets/story/`（没有就新建）：

   ```powershell
   $src = "C:\Users\Administrator\.cursor\projects\c-Users-Administrator-OneDrive-Documents-My-Program-Rustgrave\assets"
   $dst = "C:\Users\Administrator\OneDrive\Documents\My-Program\Rustgrave\assets\story"
   New-Item -ItemType Directory -Force -Path $dst | Out-Null
   Copy-Item "$src\prologue_city.jpg" "$dst\prologue_city.jpg"
   Copy-Item "$src\prologue_names.jpg" "$dst\prologue_names.jpg"
   Copy-Item "$src\prologue_yir.jpg" "$dst\prologue_yir.jpg"
   Copy-Item "$src\prologue_knight.jpg" "$dst\prologue_knight.jpg"
   Copy-Item "$src\ending_give.jpg" "$dst\ending_give.jpg"
   Copy-Item "$src\ending_keep.jpg" "$dst\ending_keep.jpg"
   Copy-Item "$src\ending_snuff.jpg" "$dst\ending_snuff.jpg"
   & "C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Users\Administrator\OneDrive\Documents\My-Program\Rustgrave" --import
   ```
3. 上面最后一行就是导入（`godot --headless --import`）。它生成 `.import`；把 `assets/story/*.jpg` 和对应 `.import` 一起提交。默认的 Texture2D 导入设置即可。舞台把 1024×576 整张缩进字幕条上方（约画面上方 65%），左右留黑边，推近只有 4%，避免剑和人被字幕板裁掉，也避免线性过滤把像素放大糊掉。
4. 重新导出手绘 / 修图版时换成 `.png`、保持同名即可，不用改代码。

## 7. 测试跑器里的 board 占位

测试跑器（`run_tests.tscn`）里，`board` 步骤默认只是一小段等待（`Director.TEST_BOARD_STUB_SECONDS` = 0.3 秒，等同 `wait`）：否则每个走序章 / 章间的用例都要真等几十秒，而且分镜的输入宽限会吞掉用例里立刻按下的确认键。要测真播放的用例置位 `Director.test_boards = true`（`tests/story_flow_test.gd`、`tests/storyboard_test.gd` 这样做），或直接 `new` 一个 `StoryboardPlayer`。`ChapterTransition` 在测试跑器里也默认 inert，`test_enabled` 打开。

## 8. 章节与关键事件

事件覆盖（全部走 Director，同一条 skip 契约）：

| 事件 | 演出 |
| --- | --- |
| Boss 登场 | 名号卡由 `boss_appeared` 画；`boss_intro_steps` 先把竞技场交出来（1.05×），吼声与冲击环压出体量，再推近到 1.2× 留一拍。第一章的拱门入场由 `Level01StoryBeats.on_boss_gate` 单独负责。 |
| 阶段变化 | `phase_steps` 锁一次镜头、吼叫、相变光环、推近、留一拍；不重复字幕 —— Boss 自己的 `announcement` 已把同一句放在 HUD 上。名号卡若已按时退场，`boss_phase_changed` 会把它短暂重新举起，相数刻度跟着涨。 |
| 击败 | `boss_defeat_steps` 慢放、震屏、镜头给跪下的身体；有下一扇门时再把镜头交给门里的火。第一章的 `on_boss_slain` 用同一语法单独演炉座。 |
| 能力获得 | 拾取：镜头、戒指、冻帧、插座火星、职称一句。嵌核：同一套镜头之后多一张 `tableau id=ability` 的紧凑「新动词」铁牌，不压暗世界、不抢输入；字幕只念核里的那句职称。 |
| 章节过场 | `ChapterLevel.chapter_card()` 从「锈墓・章节 — 地名」生成；第一章的卡在开场里。出口门的离别字幕由 `LevelExit` 从 `ChapterText.exit_captions_of()` 取。 |

## 9. 可恢复性

- **暂停 / 挂起**：Director 的整条时间线（等待、字幕、遮幅、镜头缓动、skip 按钮）与分镜、几何布景一起冻结；暂停菜单关闭后从原处继续。分镜在演时不开暂停菜单。
- **跳过**：开场、StoryStage 的关键事件、章间都 `play(..., true)`；一次确认结束整条并解锁（分镜里的 Enter 先归分镜）。`skip_step` 会释放镜头、清字幕、清队列、复位冻帧 / 慢动作。出口门的离别字幕与结局仍按 Director 默认的逐拍跳过。
- **死亡 / 切场**：`Director.reset_view()` 是硬复位 —— abort 掉正在播放或还在等待的剧本，输入、镜头（1×）、遮幅（同一帧收起）、字幕、提示、名号卡、分镜层、时间效果一起还原；StoryStage 在 `chapter_started` 与 `player_died` 上调用它，`ChapterTransition` 同步收掉布景。
- **不重播**：开场用 `opening_seen` + `wake`；StoryStage 的一次性事件用持久旗标；章间用 `interlude_<from>_seen`；死亡读档会回卷旗标，所以 StoryStage 另存本会话记忆。中断（abort）不算看过开场 / 分镜；跳过算看过。New Game 与回标题会清掉会话记忆。
- **交还提示**：开场的移动提示等到 `finished`（队列真正清空）才出现。

## 10. 作者接口

Director 步骤：`board`（`id`、`skip_all`）、`tableau`（`chapter` / `boss` / `ability` / `world`）、`caption`（`text`、`hold`、可选 `who`）、`cam_focus`、`cam_release`、`letterbox`、`sfx`、`fx`、`wait`、`lock`、`unlock`、`anim`。`fx` 支持 `target`（Node2D 或世界坐标）。

- 新增 / 改章间：`docs/story.md` §11 + `StoryFlow.BOUNDARIES`（两边由 `tests/story_flow_test.gd` 比对）；画面配在 `storyboards.gd` 的 `INTERLUDE_VISUALS`。
- 新增 / 改序章与结局画面：`storyboards.gd` 的 `_prologue()` / `ENDING_VISUALS`，改字同步 `docs/story.md` §9。
- 章节卡和 Boss 名号使用固定 640×360 构图，画在原有 UI 适配层上；Boss 名号上的余烬是有上限的直接绘制，不持续创建粒子节点。

## 11. 复验

演出域各自跑一遍（测试过滤按文件路径子串匹配）：

```powershell
./tools/run_tests.ps1 -CaseFilter storyboard
./tools/run_tests.ps1 -CaseFilter story_flow
./tools/run_tests.ps1 -CaseFilter interlude_overlay
./tools/run_tests.ps1 -CaseFilter opening_cinematic
./tools/run_tests.ps1 -CaseFilter chapter_text
./tools/run_tests.ps1 -CaseFilter director
./tools/run_tests.ps1 -CaseFilter cinematic_presentation
./tools/run_tests.ps1 -CaseFilter cutscene_safety
./tools/run_tests.ps1 -CaseFilter level02_scene
```

实际渲染截图用 Godot 打开 `scenes/tools/CinematicAcceptance.tscn`；需要 OpenGL 窗口环境。该工具使用单独的临时存档，产出至 `screenshots/acceptance/cinematics/`。这些是演出播放及视觉夹具，不能代替全流程通关或真实手机验收。分镜的逐段截图 / 序章到结局的全流程目前**未验证**（当时终端被钩子拦截，只做了静态实现）。
