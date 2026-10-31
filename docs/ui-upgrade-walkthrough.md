# 标题与实物界面收尾验收记录

日期：2026-10-31。继续本地 `5c12a161` 及前代理遗留的工作区实现，范围为标题、远厅开屏及六个二级界面。改动分批提交在本地 `master`，未推送。

## 交付结果

| 范围 | 当前行为 |
|---|---|
| 标题 | 羽化烟斑压住复杂管线；锁签下挂；36×51 吊灯照暖选中行；连续铁水；页脚渐暗 |
| 远厅与开屏 | 冷蓝拱顶在暖厅后透出；高窗光柱、暖反光；1.6 秒推镜；任意键鼠／手柄按钮可跳过；震屏与闪光设置生效 |
| 暂停 | 双链吊挂铁牌、刻字灯标菜单、纸质行程签；链子位于背景模糊前方 |
| 设置 | 双页账簿、布书签、墨线与黄铜滑块、开关实印／空印；标签和滑条避开中缝 |
| 地图 | 冷轧铁板、发亮章节冲孔、角钉纸签；选章同步正文与剖面 |
| 操作说明 | 四张独立旧纸，错开 0.06 秒进场；24px 说明与键帽，四纸首屏完整；滚轮不会误关闭 |
| 教程 | 左页墨写目录、右页课文与键帽，留出书脊 |
| 覆盖确认 | 默认取消；取消时分帧折回，确认时封蜡白热；进入角色选择时仍保留原存档，直到启程才替换 |

六件实物的布局、文字、输入和动态附件由运行时处理。用户随后允许增加贴图，并指出程序外壳的实物感仍然不足，因此本轮新增六张原创烘焙 PNG：厚铁、冷轧钢、皮革账簿、随身手札、信纸和钉纸。`tools/gen_ui_object_textures.py` 用固定种子的本地绘制制作，未调用外部生图服务；半分辨率绘制后以最近邻放大，保持 2px 视觉单元。保留 `ModalRoot/Card/Content/Body/...`、`ConfirmMenu` 以及设置的查询辅助接口，不增加 `PointLight2D`。HUD、装备、角色选择、试炼、故事／日志和回看余烬继续使用各自已有界面。

真实动画现在共享可取消的过渡句柄，整段位移取整。重新打开会撤销旧退场回调，避免位置漂移或被旧窗口关闭。子界面打开时隐藏暂停铁牌的视觉层，暂停所有权仍由原菜单持有。截图工具等待上一界面退完、当前实物进完，避免残影被误当成最终布局。

## 渲染证据

![六件实物概览](../screenshots/peek/ui-upgrade/physical-ui-overview.jpg)

![与方案基线对照](../screenshots/peek/ui-upgrade/before-after.jpg)

旧基线的残影包含截图时机的影响；这组对照用于复核版式和可读性。

- 标题：`screenshots/peek/ui-upgrade/title-final-retry/`，132 张截图及对应 JSON；四种状态、三档分辨率、开屏与焦点变体。`contact-idle.png`、`contact-intro.png`、`contact-focus.png` 已实际查看。
- 纯场景：`title-bare-final/contact-bare.png`，cold／act2 两张。
- 六件实物：`menus-final/{960x540,1280x720,1920x1080}/`，每档 12 张，尺寸核对记录在 `menus-final/visual-checks.json`；最终贴图版复核在 `menus-baked-final/{960x540,1280x720,1920x1080}/`，每档 8 张，暂停铁牌、设置账簿和 960/1920 两端尺寸已查看。
- 火漆与折纸：`letter-detail/seal-hot.png`、`letter-detail/fold-pose.png` 为固定姿态的真实渲染样张，用于检查绘制；不代表连续动画的主观手感。

标题 JSON 中 14 盏可见吊灯、8 个点光源；idle 点亮数 cold=0、act2=4、keep=14、snuff=0。页脚内容区平均 sRGB 亮度为 0.0244–0.0318。节点数 ≤150、锁签避让及整像素视差由对应测试验证，未把这些说成截图 JSON 的字段。

960×540 沿用项目现有整数缩放：1280×720 设计画布缩为居中的 640×360，带黑边。操作说明已按这个实际内容尺寸调整字号；本批不改缩放策略。

上述截图与日志在被忽略的 `screenshots/` 内，是本地证据，未随源代码提交；可用下面命令重新生成。较早的 `title-final/` 包含一次编辑期间的解析失败日志，最终标题证据应使用 `title-final-retry/`。

## 自动验证

| 最终专项 | 通过用例 |
|---|---:|
| title | 118/118 |
| modal（含真实 Tween 生命周期） | 28/28 |
| settings | 16/16 |
| pause_menu | 7/7 |
| physical_secondary | 3/3 |
| overwrite_letter | 3/3 |
| physical_material | 4/4 |
| tester_appearance | 3/3 |
| tester_layout | 3/3 |
| qhd_fire | 2/2 |
| gate5 | 4/4 |
| 合计 | 191/191 |

专项汇总在 `screenshots/peek/ui-upgrade/regression/ui-focused-summary.json`，记录 191 个专项用例、93,443 条通过断言和 0 引擎错误。启程交接专项为 10/11、195 条通过断言、0 引擎错误；剩余 1 项是旧 Continue 场景导演锁定边界。另对必要的旧基线修复核实了 arena_depth 4/4、ember_recap 3/3、far_view_depth 2/2。扩大字体后的页脚与旅程短注布局、隐藏界面的越界探针、启程保存原子性，以及已有原生炉口贴图的过时断言也在最后一轮修正。

本轮没有复现历史记录的「全量全绿」。当前工作区单次全量在 1500 秒超时：已执行 1276 个用例，1235 通过、41 失败，未取得完成标记，观察到的引擎错误为 0。分段合并覆盖当前声明的 1,824 个方法，其中 1,777 通过、47 个仍失败，0 个有效运行引擎错误；这不是单进程全量通过。失败明细与原始日志保存在 `regression/full-suite-summary.json`、`regression/full-suite/` 和 `regression/segmented-regression-summary.json`。剩余失败涉及关卡可达性／道具摆放、分镜战斗安全、战斗教程交接、炉火与旧美术约定、旧 Continue 场景边界等，与本批已通过的标题和实物专项分开记录。

工作区还有未提交的玩家、字幕、导入与其它测试改动。此全量结果描述当前混合工作区，不能当成本批提交在干净检出中的独立全绿证明。超时后从 `prop_fit_test.gd` 开始补跑剩余部分，分段结果以 `regression/` 中的续跑记录为准。

## 复现

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter title -TimeoutSeconds 480
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter modal -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter settings -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter physical -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter overwrite_letter -TimeoutSeconds 180
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter physical_material -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter new_game_handoff -TimeoutSeconds 360
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter qhd_fire -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter tester_appearance -TimeoutSeconds 240
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -CaseFilter tester_layout -TimeoutSeconds 240
python tools/gen_ui_object_textures.py --check
powershell -ExecutionPolicy Bypass -File tools/run_ui_peek.ps1
powershell -ExecutionPolicy Bypass -File tools/run_title_peek.ps1 -Variants 'cold,act2,keep,snuff' -Sizes '960x540,1280x720,1920x1080' -Shots 'boot,idle,focus' -OutDir 'screenshots/peek/ui-upgrade/title-final-retry'
```

测试与截图使用隔离存档和设置目录。物理手柄、真实触屏以及连续动画的主观手感仍需人工体验；合成输入断言和固定渲染样张不替代这些验证。
