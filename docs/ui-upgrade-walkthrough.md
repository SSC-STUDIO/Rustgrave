# 标题、开屏与六件实物界面验收记录

2026-10-31。本轮在 `5c12a161` 及已有工作区实现上继续完成标题、远厅开屏和六个二级界面。功能逐项本地提交，最终 UI 源码快照为 `1af71861`，未推送。

## 按原计划逐项核对

用户再次要求严格对照六行规格后，检查发现旧版本仍有差项：设置书签只是装饰、条目跨书脊分放、铁牌只有链条在摆、地图钉子提前出现、封面与信封动作不完整。本轮已补齐下表实际行为。

| 界面 | 实物、内容与选中反馈 | 实际动作 |
|---|---|---|
| 暂停菜单 | 两根屏幕顶链吊挂锈铁牌；左侧刻字与标题同款吊灯；右侧真钉行程签，显示章节／目标／锈核 | 放链、回弹，0.24 秒落位后板体与链底一起整数像素微晃，链顶固定；退场精确归位 |
| 设置 | 960×560 摊开账簿；顶沿声音／画面／键位／辅助四根布条本身就是可点击页签；左页分类说明，所有编辑条目在右页；墨线与黄铜珠、开／关印章 | 从下滑上，封面绕书脊切换三个姿态，每帧 0.07 秒；条目名称单行，长页可滚动 |
| 地图 | 1120×640 冷轧钢板；顶沿真实章节冲孔可点击，所选孔烧亮；路线刻在板内，右角档案纸四钉固定 | 0.20 秒落位后，每 0.08 秒安装一枚角钉，并有压入与短促火星；PNG 不预画静态钉头 |
| 操作说明 | 移动／战斗／交互·剑核／系统四张独立旧纸；四枚黄铜钉对准纸孔，按键使用铅字键帽；40px 内容内边距、24px 说明 | 各纸错开 0.06 秒滑入；透明布局载体没有第五张大纸；四纸首屏完整 |
| 教程回看 | 880×520 随身手札，小于设置账簿；左页墨写目录、右页课文与相关键帽 | 同账簿滑上、绕书脊三帧翻开；反复开关或同帧重建不会调用过期滚动目标 |
| 覆盖存档确认 | 640×420 封蜡信笺，默认取消；可以直接点击蜡封，也可以选确认行 | 信笺落下；确认先压低蜡封再白热一闪，关闭闪光仍保留按压；取消三段折成封口信封后撤走；重开撤销旧回调 |

标题的羽化菜单暗斑、下挂锁签、36×51 吊灯与暖光、连续铁水折线和页脚渐暗均保留。冷蓝 `FarVault` 拱顶、高窗光束、熔河暖反光与 1.6 秒可即时跳过的推镜已接入，遵守既有节点与光源预算。

用户允许增加贴图后，使用 `tools/gen_ui_object_textures.py` 本地制作六张原创 PNG：`board / ledger / plate / journal / letter / paper.png`。固定种子、RGBA、透明边缘和 2×2 像素单元可复验，未调用外部生图服务。运行时负责文字、布局、交互、动态附件与动画，不新增 `PointLight2D`。

`ModalRoot/Card/Content/Body/...`、`ConfirmMenu` 与设置查询接口保留。过渡可取消、位移取整，重复开关恢复原位。子界面打开时隐藏暂停铁牌，关闭后归还暂停输入。确认覆盖只进入角色选择，真正启程才用一次写入保存身份、装备、皮肤与符文；写盘失败保留旧档。

## 实际渲染证据

![六件实物最终实际渲染](../screenshots/peek/ui-upgrade/strict-final/six-interface-overview.jpg)

- 最终静态界面：`screenshots/peek/ui-upgrade/strict-final/{960x540,1280x720,2560x1440}/`，每档 13 张，含四页设置与改键状态。已检查六界面概览、辅助／画面页以及大小两端的布局。辅助页截图发现的条目折行已修正并重拍。
- 铁牌动态：`strict-plan-motion/pause/evidence.json` 与 `left-chain-motion-contact.png`，记录落位后板体 x 从 130 到 132、129 再回 130，链顶固定、链底跟随。
- 地图逐钉：`strict-plan-motion/map/evidence.json` 与六个实际时间点渲染，安装数按 0、1、2、3、4、4 递增；刷新新钢板贴图导入缓存后重拍。
- 翻书：`strict-books/cover-contact.jpg`，设置／手札各四个原生姿态，实际渲染不透明封面绕书脊翻过。
- 火漆与折信：`strict-letter/` 的八张原生 1280×720 姿态、`wax_pose_detail.png` 与 `pose_manifest.json`，含按压、白热、三段折叠和封口撤离。
- 标题与开屏：`title-final-retry/` 的 132 张截图与 JSON，以及 `title-bare-final/contact-bare.png`，覆盖不同存档状态、开屏和焦点。标题专项同样在最终源码快照验证。

这些是实际引擎渲染与定时／定姿态记录，未据此宣称连续动画的主观手感或物理手柄已经验收。960×540 沿用项目整数缩放，内容是居中的 640×360，带黑边。

截图与日志位于忽略的 `screenshots/`，是本地交付证据，不随源代码提交。旧 `physical-ui-baked-overview.jpg`、`committed-final/` 和 `strict-final-before-label-fix/` 已被本次严格版取代。一次初始标准截图在标题四张后 180 秒超时、stderr 为空，原因未确定，日志保留于 `strict-final-initial-timeout/`；成功的同源跟踪 fixture 只增加七条定位输出，没有修改状态或动画时序，源文件和清单一并保留。 随后正式 `run_ui_peek.ps1` 在 1280×720 复现成功，13/13 张保存，stderr 为空，日志与图片保留于 `strict-standard-repro/1280x720/`。

## 最终专项验证

测试在隔离检出中执行，使用独立存档与设置。62 个本轮源文件、工具、测试及素材与最终提交逐一核对，文本按 LF 归一后全部一致。记录在 `regression/strict-final/source-manifest.json`。

| 分组 | 独立用例 | 通过断言 |
|---|---:|---:|
| title | 118 | 92,042 |
| modal | 28 | 918 |
| settings | 16 | 134 |
| pause_menu | 7 | 42 |
| physical_secondary | 3 | 94 |
| physical_material | 4 | 112 |
| gate5 | 5 | 135 |
| ui_transition | 6 | 50 |
| letter_gesture | 4 | 48 |
| overwrite_letter | 3 | 30 |
| travel_journal_size | 2 | 8 |
| new_game_handoff | 11 | 303 |
| tester_appearance | 3 | 8 |
| tester_layout | 3 | 7 |
| qhd_fire | 2 | 40 |
| 合计 | **215/215** | **93,971** |

用例名交叉去重为零重复，各组取得完成标记，0 引擎错误。除拒绝写盘用例的预期警告外 stderr 均为空。最终汇总是 `regression/strict-final/strict-final-summary.json`。旧摆动测试失败和名称折行修正前日志另存并排除最终统计。装备布局诊断仍打印 `overlaps=1015`，该方法没有重叠断言；通过计数不代表本轮已修复装备界面。

## 范围与主工作区状态

本轮没有复现历史交接的全仓全绿。较早混合工作区全量运行在 1500 秒超时，执行 1276 例、1235 通过、41 失败；分段合并覆盖当时的 1824 个方法，1778 通过、46 失败，未完成单进程全量全绿。失败涉及关卡可达性／摆放、分镜战斗、教程交接与旧版美术约定，明细保留于 `regression/full-suite-summary.json` 与 `regression/segmented-regression-summary.json`。这是较早混合工作区的记录，不是最终隔离快照全量结果。

主工作区同时存在另一任务的叙事／节点地图、玩家、字幕、标题场景和大量导入修改。地图的并行版本保留了实物外壳，但新增了 `NarrativeCatalog / StageLevel` 等接口；本轮提交的是独立验证过的 UI 地图版本，保留主工作文件及并行修改，未将它们混入提交。**主工作区这些并行改动尚未纳入本轮验收，不能把隔离 UI 通过当成主工作区整体集成通过。** 原有字幕暂存 blob `26998f5840694e41b5e4fb3e3b13dee1b49ae181` 保持不变。

本轮未迁移 HUD、装备、角色选择、试炼、故事／日志及回看余烬的既有外壳。

## 关键本地提交

- `38face0a`：四纸真钉。
- `5629ae80`：可点击火漆、先按压后白热、取消三段折信。
- `9a7e29e6`：真实顶沿书签、右页设置条目、绕书脊翻书及较小手札。
- `61913f16`：铁牌板体微晃、链底跟随、行程签真钉、地图落位后逐钉火星。
- `a411cdbe`：真实弹簧驱动的链端随板／归位回归。
- `12ea91a6`：正式截图工具补辅助页。
- `1af71861`：条目名称单行排版及 29 条跨页检查。

## 复现

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter title -TimeoutSeconds 480
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter modal -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter settings -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter physical -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter letter_gesture -TimeoutSeconds 180
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter travel_journal_size -TimeoutSeconds 180
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter new_game_handoff -TimeoutSeconds 360
python tools/gen_ui_object_textures.py --check
powershell -ExecutionPolicy Bypass -File tools/run_ui_peek.ps1 -Sizes '960x540,1280x720,2560x1440' -Only 'title,menus' -OutDir 'screenshots/peek/ui-upgrade/strict-final'
```

复现时应从上述提交建立干净检出，避免主工作区并行改动影响结果。完整材质与接口规则见 [UI 语言](./ui-language.md)。
