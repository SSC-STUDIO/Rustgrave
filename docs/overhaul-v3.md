# 锈墓全面改造 v3：实施与验收清单

本页记录标题活景、14章重做和系统升级的当前状态。**截至2026-10-25，七位原创Boss、14章新游戏输入、140张关卡图、性能/音频审计及最终无过滤全量1462/1462均已完成。** 章节细节见 `docs/level-redesign/`，规范见 `docs/level_authoring.md`，历次验收见 `docs/acceptance.md`。

## 工作区与不变契约

当前整合分支为 `codex/overhaul-v3-completion`，工作区 `C:/Users/Administrator/.codex/worktrees/overhaul-v3-completion/Rustgrave`，起点 `8b91f22`。原 OneDrive 工作区的未提交改动不纳入。每个完整功能、修正和验收文档单独提交；截图与日志留在忽略的 `screenshots/` 中，未推送或发布。

故事及14章顺序保持不变；主线只要求普通单跳、冲刺、热锻，钩锁与额外跳跃属于可选支路。第一章继续使用手摆场景，不登记到 `GameContext.LAYOUTS`；旧 `Props/EmberNest`、`EmberNestEast`、`Door`、`RustyGate`、`ForgeHeart`、`ScrapPile`、`Pickups/EmberCore` 等存档路径保留。新存档实现兼容v2迁移，不能以当前写入版本号推断兼容性。

## 阶段状态

| 阶段 | 当前结果 | 证据与剩余边界 |
| --- | --- | --- |
| P0 | 完成 | 标题WIP基线 `8bfa46f`，排除无关pptx；当时全量1182/1182 |
| P1 | 完成实现与全量验证 | 五种机关、布局/体检/提示、敌人变体与脱战群警戒、读档安全、Boss破势；`p1-poise/full-final` 1298/1298、0引擎错误 |
| P2 | 完成实现与定向渲染 | 活景/回退、版式/动效、14盏可见进度灯、守火坐姿、真实遮挡、竞技场入口；`docs/title-live-scene.md`，标题/性能专项报告 |
| P3 | 完成重建与定向验收 | 第一章后半偏殿/工坊/长阶/炉厅；新游戏基本能力双路线已通过，见下表 |
| P4 | 完成三章实现与定向验收 | 02/02b/03蓝图、地形、机关、遭遇、恢复修正和双分辨率机位；新游戏基本能力渲染输入已通过 |
| P5 | 完成四章实现与定向验收 | 04/04b/05/06；补唱诗阶梯、地窖东西回路净空和传送带真实速度导航 |
| P6 | 完成六章实现与定向验收 | 07/07b/08/09/09b/10；补折返次序、斜坡接地、熄灭浇口安全查询、Herald世界区域坐标 |
| P7 | 完成实现与专项验收 | 手柄、五项辅助、显示、地图、总结与复战、复活、音频、预算；Start与次级绑定冲突另作修正 |
| P8 | 完成最终整合验收与文档 | 无过滤全量1462/1462、新游戏14章/七Boss、140张机位图、15处性能采样、音频审计与证据索引全部通过；硬件/真人边界见末节 |

并行阶段采用逐章定向门禁，再做整合全量。历史未在每次合入前完成全套的事实保留，不追认成“每阶段全量先通过”。先前 `full-final` 是1405/1406、0引擎错误、`passed=false`，唯一失败为修正前第三章恢复布局；它不是最终通过证据。

## 原始要求与实现索引

### P1 机关、敌人、存档与Boss

- `scripts/hazards/`：CyclicHazard、CollapsingPlatform、ForceZone、ConveyorBelt、PendulumHazard；每类独立测试。`ChapterLayout` 提供对应装配助手，PlayerController以 `add_environment` 接受环境外力。
- `LevelSanity` 与 `TraversalModel` 检查危险区、支撑和路径；周期机关预警至少0.5秒，安全物不落在判定区/塌陷台/传送带上。出生相位固定，机器人读取 `safe_window()` 等真实时序。
- `HazardFx` / `HintService` 提供首遇提示及音效。`EnemyVariants` 负责装甲/疾行碎铁犬、重盾卫、散射喷吐者、爆裂骸骨；EnemyBase处理脱战与群警戒。
- `SpawnSafety` 接入第一章、第二章及通用章节：不安全读档坐标回退到安全巢或缺省出生点；迁移回归保护旧存档。
- 七个Boss的实际玩家剑终结击在5秒内累计两次触发破势：收回当前近战/预警，0.8秒恢复、1.6秒免累计。暂停/过场/重置有测试；不改变伤害、阶段、攻击ID和判定形状。`boss_poise` 6/6、111断言；真实场景金色破势图是注入两次伤害的表现夹具。

### P2 标题

`TitleWorld` 在640×360 SubViewport渲染，经 `Keyart` 兼容节点和像素缩放输出。包含真实骑士/巨剑、视差锻厅、逐帧齿轮、吊灯/链环、8个点光、真实遮挡、光柱和粒子、整像素相机呼吸与鼠标视差。无存档、四幕、送剑、守火、熄灭按真实存档状态构建，14盏灯逐章点亮；守火有独立坐姿。

`TitleScreen` 提供白热锻造Logo、四组铁条菜单、14格旅程刻度/Tab档案、墓志打字机和致谢，开场/进关/退出联动炉厅光与音频。`ID_ARENA` 接 `ArenaRun.start()`；保留原Menu/ID/确认/过场接口。`USE_LIVE_SCENE` 可回退keyart。三档分辨率四变体的live/keyart矩阵与阴影/进度补图分别记录；几何指标不能替代看图。

### P3—P6 章节

每章蓝图、节点/存档契约、三处遭遇、专属机关、单向回巢、奖励挑战、巢间距、Boss场和首遇测试详见同名文档。机位证据是固定骑士/相机的真实渲染，机关与AI是否运行以各章记录为准。

| 章节 | 重做内容 | 当前机位证据（相对 `screenshots/acceptance/overhaul-v3/`） |
| --- | --- | --- |
| 01 | 前半保留教学；后半压板偏殿、火口工坊、下沉长阶、抬台双炉口竞技场 | `level01/`；`docs/level-redesign/level01.md` |
| 02 | 螺旋下探、坠钟预警、空钟笼竞技场；下沉大厅基本单跳恢复 | `level02-recovery/{720p,1080p}/` |
| 02b | 双水位、涌流、抽水井/检修台、绞盘排水场；坑岸与吊台交接净空 | `level02b-recovery/{720p-final,1080p-final}/` |
| 03 | 街面/屋顶环线、塌瓦落物、下沉巷/市场/高庭；门上砖楣保留压板意义 | `level03-resume/`、`level03-recovery/`、`level03-route-fix/` |
| 04 | 环形唱诗回廊、钟鸣波/壁龛、上下场地；清除末阶头顶回廊 | `level04/`、`level04-stair-fix/` |
| 04b | 暗室烛光限时阶梯与地窖竞技场；东攀与西返实体输入均通过 | `level04b/`、`level04b-route-fix/` |
| 05 | 320/224/112三层机械迷宫、传送带、独立蒸汽廊、五吊台 | `level05/` |
| 06 | 环绕陵墓双路线、带毒锈泥、雾中骸骨和回巢路 | `level06/` |
| 07 | 竖井、东西侧室、钟舌摆锤、七吊台和单向安全降落 | `level07/` |
| 07b | 阶梯铸造线、与吊台时钟同步的熔注、真实斜坡钟模场 | `level07b/` |
| 08 | 三渣河/四喷泉岛、低空火骷髅、上行台/回廊；天空下缘渐隐 | `level08/sky-edge-final/`，20张最终材质图 |
| 09 | 塔楼辐射支路、阵风道/可恢复坑岸、塔顶奖励 | `level09/` |
| 09b | 崖壁折返、余烬风、塌桥与落石分离、前哨/Herald场 | `level09b/` |
| 10 | 上下环殿、柱台/炉台、随Nightmare阶段联动的炉心脉冲 | `level10/`；最新东西阶净空补图 `finale-continue-fix/{720,1080}/` |

上表保留各章实施时的历史图组。当前统一重拍为 `final-matrix/<chapter>/{1280x720,1920x1080}/`，完整14章×五机位×双分辨率共140张；竖井/崖道在分辨率目录下另分y机位。`final-matrix/manifest.json` 为 `complete=true`，记录每张实际尺寸与SHA256，0引擎错误。14张双分辨率联系表全部打开审阅，路线、落脚、机关与七位原创Boss显示正常；作为最终统一构图证据优先于历史图组。夹具点亮巢并固定/无敌骑士，真实AI与机关运行；不作为正常输入通关证据。`evidence-imports.json` 保留早期外部worktree来源。

### 七位Boss原创美术

七位Boss已全部替换为独立设计的原创像素帧：闭面葬甲刽子手、悬挂裂钟、潜水绞盘甲、管风琴指挥及三种唱诗面具、四层铸模甲、机械长喙钢翼、窑骨炉心骸马。共459帧，三份绘制源稿保存在仓库；隔离重画459/459逐像素一致，跨Boss无完全相同帧。轮廓、装备和动作逐个审阅；实际战斗状态选择对应前摇/判定/收招/倒地帧。原判定、阶段和攻击ID保留。详细设计、源稿、权属和夹具证据见 `docs/original-bosses.md`。

### P7 系统

详见 `docs/system-options.md`。设置独立于战役存档，辅助默认均100%；显示支持持久化分辨率/垂直同步/三种缩放。地图M/Back可直开，过场禁开；总结页包含结局、14章/试炼/竞技场记录和指定Boss复战，复战隔离战役写入。死亡确认可跳过等待，HUD提示余烬巢复位。

手柄全局映射、输入设备提示、设置重绑已实现。Start/Esc保留给暂停/子页返回，B仍是技能1；重绑检测主次token并只交换冲突项，持久化、旧配置、恢复默认及真实按键唯一触发有回归。`p7-secondary/` 中gamepad9/9、settings16/16、pause6/6，0引擎错误。

机关新增14个专用提示/判定音效，标题床为24秒循环；生成器与音频数值验证只证明解码/峰值/直流/接缝。系统预算守卫限制每章机关≤32、Light2D≤64、世界节点≤6000；标题≤8点光/250节点。`systems/` 八张双分辨率图覆盖默认/135%字体、显示页、总结页，已检查内容与返回按钮；成绩是展示夹具。

## P8 输入与性能证据

| 范围 | 当前结果 | 限制 |
| --- | --- | --- |
| 第一章重燃→第二章、第一章熄灭 | `input-20261024-201053-832/{rekindle,snuff}.json`均PASS；`basic_abilities=true`、`resumed=false`、各1次真实死亡、0引擎错误，辅助均100% | headless固定60Hz加速；不是14章通关 |
| 历史01—09b整合调试 | 正常输入已依次越过前13章路线并抵达Herald门前，修复沿途真实净空/时序问题 | 从合法存档恢复的多轮调试，不能拼接宣称一轮通关 |
| Nightmare局部实战 | 三阶段、击杀、真实熔渣致死、复活、标题Continue及持久化均PASS；headless/rendered各一轮，33/33定向测试 | 开始前摆到竞技场巢并省略入口门，明确是局部夹具；未证明合法战役到达 |
| 标题与14章性能探针 | CPU监视器和渲染回调分别采样，记录原始样本、窗口/视口/GPU/运行范围及离群值 | 离屏Windows OpenGL回调不等于实体屏幕FPS，不把CPU监视器相加当帧时长 |

首轮 `full-authoritative-final/` 为1451/1453、0引擎错误，`passed=false`：水渠导航跳过真实中间台阶，键位测试直接改内存绑定却假定当前设备为键盘。前者现经过真实台阶并计入下落刹车净空；后者通过设置页的真实抓键入口验证设备切换与即时刷新，未改产品提示规则。后续补齐连续桥、低顶板台阶、完整杂物支撑与窄瓮落脚的真实输入回归，导航20/20、恢复12/12。`full-authoritative-verified/`、`full-authoritative-complete/`、`full-final-certified/` 的中途运行有superseded记录，均不计为最终通过。

`full-final-frozen/` 终结为1456/1457、0引擎错误、`passed=false`：墓园“泥沼外不增毒”测试继承全局天气，锈雨会按原规则在干地独立增毒。`3651425` 用晴天隔离泥沼边界，并新增锈雨仍会增毒的实际角色回归；章节11/11、0引擎错误，游戏天气/毒素/布局未改。随后 `full-final-weather-fixed/` 已终结1458/1458、0引擎错误。清单审计又发现四类机关缺统一safe_window接口，`f7bcff7`补齐只读查询并把塌台最低抖动预警提升到0.5秒；当前关卡使用0.6/0.7/0.8/1.4秒，实际时序不变。最终取代上述历史全量的是 `full-final-window-contract/`：**1462/1462、0引擎错误**，终结行与summary同时通过。

首次新游戏完整渲染输入 `input-20261024-222123-500/rekindle.json`（2次死亡、665帧机关等候）及校验副本 `input-final/rekindle/` 保留为历史通过记录。后续导航变化暴露的失败局也原样保留，不拼接为新游戏通过。

接口补齐前通过的新游戏完整渲染输入为 `input-20261024-234119-947/rekindle.json`：`passed=true`、`campaign=true`、`input_only=true`、`basic_abilities=true`、`resumed=false`、`rendered=true`，5次真实死亡、0引擎错误。记录139个里程碑、第一章后13个有序章节入口、七Boss实际击杀、梦魇三阶段、真实熔渣致死、复活及标题Continue后Boss缺席、最终出口/字幕与game_complete持久化。公开辅助仍为受伤0.5/弹反1.5/毒素0.5，机关等候628帧，主线没有钩锁或额外跳跃。

115张实际PNG逐张解码并确认为1920×1080；`input-final/rekindle-verified/` 按文件校验归档121个文件，包含报告、日志、render-manifest、运行来源和12图联系表。联系表逐格查看，Boss出口图只表示击杀后的到达，击杀由里程碑与正常输入日志验证；新游戏/完成截图可能处于淡变中。来源为启动提交d1f61ca，归档时只追加过文档；后续墓园修改仅为测试。不能据此证明真人手感或实体显示器性能。

渲染第一章熄灭分支 `input-20261024-222748-442/snuff.json` 也通过：`resumed=false`、基本能力、1次真实死亡、0引擎错误，三项辅助均100%。原件与校验后的 `input-final/snuff/` 副本同时保留。这是第一章提前结局，不是14章路线。

最终接口提交`f7bcff7`重新从标题新游戏完成14章渲染输入：原件 `input-20261025-002258-602/rekindle.json`，归档 `input-final/rekindle-window-contract/`；138个里程碑、115张1920×1080 PNG、3次真实死亡、机关等候645帧、0引擎错误，`resumed=false`。启动前记录源码与两份驱动哈希，七Boss击杀、梦魇三阶段、致死/复活/Continue及最终出口/字幕与game_complete均独立验证；公开辅助为受伤0.5/弹反1.5/毒素0.5。归档副本逐文件校验，未拼接历史恢复局。

标题守火及14章入口共15次1080p/8秒采样，原始样本、进程条件、JSON/PNG哈希在 `final-performance/`，源`83e430c`。`render-runtime-compatibility.json`逐字核对后续运行时差异：仅四个未被现有运行时调用的只读safe_window方法和对当前关卡无影响的最低抖动值；布局、画法、素材、既有调用均相同。因此沿用已审阅构图与停放机位采样，不称两棵源码树逐字相同。p95为3.349–5.001ms；钟楼有一次1160.905ms长停顿，来源未确定，详见性能报告。固定机位、并发负载和离屏窗口不用于声称实体显示器性能或全程无卡顿。

## 最终门禁（2026-10-25）

证据根为 `screenshots/acceptance/overhaul-v3/`；`final-evidence-index.json` 校验下列原件的SHA256、实际PNG尺寸、报告状态和必需套件覆盖。源代码与本页提交到Git，图像/日志保留为本机ignored证据。

| 门禁 | 最终结果 | 证据 |
| --- | --- | --- |
| 无过滤全量 | **1462/1462，28740条断言，0引擎错误**；`passed=true`、`completed=true`，无章节/用例过滤 | `full-final-window-contract/`，源`f7bcff7` |
| 新游戏14章渲染输入 | 14章、七Boss实际击杀、梦魇三阶段、致死/复活/Continue/最终出口与持久化通过；3次死亡、0引擎错误 | `input-final/rekindle-window-contract/`；原件`../input-20261025-002258-602/` |
| 第一章熄灭 | 新游戏、基本能力、三项辅助100%、1次死亡、0引擎错误 | `input-final/snuff/`；这是提前结局 |
| 章节构图 | 14章×5机位×2分辨率＝140张，14份联系表逐张审阅 | `final-matrix/manifest.json`、`visual-review.json` |
| 原创Boss | 7位、459张透明像素帧、459/459源稿重现、跨Boss零完全相同帧 | `original-bosses/original-assets-review.json`、`seven-original-bosses.png` |
| 标题 / 系统UI | 标题24张主矩阵+4张补图；系统默认/135%字体/显示/总结页共8张 | `title-perf/capture-manifest.json`、`systems/report.json` |
| 实测入口性能 | 标题+14章共15次1080p、至少8秒采样；p95 3.349–5.001ms，保留钟楼1160.905ms离群值 | `final-performance/`、`render-runtime-compatibility.json` |
| 音频数值审计 | 14个机关音效+1条标题循环，0硬失败/削波/DC异常/缺失/未解析引用，循环接缝通过 | `audio-hazard-verified.*`、`audio-title-verified.*` |

全量stderr保留防护分支与Control锚点warning，以及退出时3个ObjectDB实例泄漏warning；未把warning改称失败，也不声称日志零告警。数值音频审计不代表人耳混音验收。

### 原始清单逐项核对

| 要求 | 当前实现与直接证据 |
| --- | --- |
| 五类机关、环境外力、安全窗口、提示 | `scripts/hazards/`、`ChapterLayout`、`PlayerController.add_environment`；五类专测、Sanity/Traversal、首遇与预算回归；`f7bcff7`补齐四个只读查询，四类25/25定向通过 |
| 敌人变体、脱战群警戒、Boss破势、v2读档安全 | EnemyVariants/EnemyBase/BossPoise/SpawnSafety与对应正反例及迁移套件；七Boss真实判定撤回回归 |
| 标题实时场景、进度变体、回退、版式和竞技场入口 | TitleWorld/TitleScreen、三分辨率live/keyart图、14灯/阴影/坐姿补图、title_metrics、ID_ARENA/交互回归 |
| 第一章后半与其余13章蓝图/地形/遭遇/捷径/奖励/机关/Boss场 | `docs/level-redesign/level*.md`共14份，逐章layout及恢复物理用例、全部Sanity/route_audit/progression、140张构图和新游戏输入 |
| 七Boss独立设计与自行绘制 | `docs/original-bosses.md`、三份可编辑绘制源稿、七套真实战斗状态美术回归、459帧重绘及轮廓/装备审阅；旧角色帧不供Boss使用 |
| 手柄映射/重绑/设备提示、五项辅助、显示持久化 | gamepad/settings/key-labels/combat-rules/display-fit/resolution与UI实图；保留默认平衡和Start/Esc返回规则 |
| 地图、回看余烬/复战、复活QoL、音频和预算 | map/pause/ember_recap/trial/death_respawn/audio_library/system_budget套件，真实Start事件、8张系统UI图与音频数值审计 |
| 升级bot、基本能力、完整验收和文档 | 只读机关策略与真实输入驱动，新游戏14章/熄灭分支、统一构图/性能/证据索引；authoring/acceptance/本页/性能报告同步 |

故事与章节顺序、原存档节点和v2迁移、基础能力、Boss判定/攻击ID均由全量及真实场景验证。历史逐章门禁替代每阶段全量的流程偏差仍保留在上文；最终全量不追认历史流程。未扩展多槽、完整i18n、Boss Director迁移或新玩家招式。

## 未验证项

真机触屏/刘海、实体手柄手感、真人战斗与路线手感、音频主观混音、实体显示器的呈现/同步与性能均未验证。它们不由自动化、固定机位或数值音频检查替代。本任务不扩展多槽、完整i18n、Boss Director迁移或新玩家招式。
