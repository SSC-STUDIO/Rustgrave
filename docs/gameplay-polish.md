# 战斗手感与公平性打磨（2026-10-16）

## 行为

- `MeleeCombat.request_attack()` 接收单次攻击请求：空闲冷却最多缓冲 0.16 秒；前两刀判定期最后 0.12 秒和后摇可预输入下一刀。队列最多一刀，第三刀封顶，按住攻击不自动连击。
- 保留三段挥砍的前摇、判定期、后摇、伤害与弹反窗。暂停清除预输入，过场和死亡同时关闭攻击判定；恢复后必须释放再重新按下。
- 盾卫按弹丸来向识别盾面：正面反弹破盾，背面命中扣血。反弹瞄准来源敌人的 Hurtbox，避免瞄准脚底导致弹丸先撞地。
- 刽子手两阶段均为 0.52 秒前摇、0.16 秒伤害期、0.65 秒无盾收斧期；收斧期间停止发射，死亡立即关闭分离的斧头判定。
- 梦魇保留 0.7 秒冲锋前摇，最后 0.2 秒锁向；蓄力姿态、音效与冲锋方向一致。喘息时间和召唤上限不变。
- 操作面板同步连段提示，复用现有动画和音效；无新增关卡、成长系统或存档字段。

## 验证记录

所有路径相对仓库根目录；`screenshots/` 是保留在本地的忽略目录，不包含在 Git 提交中。

| 检查 | 已观察结果 | 日志 / 截图 |
| --- | --- | --- |
| 当前工作区完整回归 | 390/390，通过，0 个引擎错误 | `screenshots/acceptance/gameplay-polish/full-suite-final/` |
| 隔离提交检出完整回归（da2ec3a） | 374/374，通过，0 个引擎错误 | `screenshots/acceptance/gameplay-polish/committed-suite-final/` |
| 首章复燃 / 熄灭双路线 | 均从新存档开始，通过，分别 1 次死亡 | `screenshots/acceptance/input-20261016-180516-719/` |
| 十章基础能力输入通关 | 从新存档开始，通过，10 次死亡；梦魇两阶段、死亡重载、Continue、最终出口均验证 | `screenshots/acceptance/input-20261016-182433-095/` |
| 键盘战斗输入 | 盾卫反弹及破盾追击、刽子手收招受击、梦魇锁向及喘息追击通过；7 张截图，0 个引擎错误 | `screenshots/acceptance/combat-keyboard-20261016-181656-621/` |
| 强制触控战斗输入 | 同上，通过；实际 ScreenTouch 事件，7 张截图，0 个引擎错误 | `screenshots/acceptance/combat-touch-20261016-181731-626/` |
| 鼠标战斗输入 | 同上，通过；实际鼠标左键攻击事件，7 张截图，0 个引擎错误 | `screenshots/acceptance/combat-mouse-20261016-182752-859/` |
| 隔离检出键盘战斗 | 通过，0 个引擎错误 | 管理检出目录的 `screenshots/acceptance/combat-keyboard-20261016-182018-252/` |
| CI 配置 / 安装器 | CircleCI CLI 验证有效；实际下载官方 Godot 4.7.1 并通过 SHA512、版本检查 | `.circleci/config.yml`、`tools/install_godot_ci.ps1` |
| 测试失败门禁 | 空测试集 / 缺少完成标记、超时探针均返回失败 | `screenshots/acceptance/gameplay-polish/empty-suite-probe/`、`timeout-probe/` |

两份回归的数量差异来自实施前已有但未提交的测试与功能。原有工作区差异保留；混合修改文件只提交本轮增量。隔离检出用于检查实际提交，而不是把工作区额外内容当作提交内容。

通关驱动只发送正常移动、跳跃、冲刺、攻击、交互和菜单输入；读取关卡几何及状态以选择动作，不传送、不直接扣血、不授予能力。战斗验收只在开场建立固定竞技场，之后用键盘、鼠标或触控事件驱动。两者的报告与截图分别保存。强制触控依赖实施前已有的未提交触控文件，干净提交检出会明确报告缺少触控实现，不会静默改用键盘。

自动输入通关与离屏截图不能证明人工手感或手机实机体验。旧通关驱动在 Godot GL 退出时仍可能记录 Texture / RID 回收错误；其既有脚本明确过滤这两类退出诊断，JSON 中的运行期错误为空。严格完整回归与新增战斗验收不忽略引擎错误。早期失败尝试的日志保留，没有作为成功证据。

## 复现

```powershell
./tools/run_tests.ps1 -ArtifactsDir screenshots/acceptance/regression
./tools/run_input_acceptance.ps1 -Ending both -Fast -Rendered
./tools/run_input_acceptance.ps1 -Campaign -BasicAbilities -Ending rekindle -Fast -Rendered
./tools/run_combat_acceptance.ps1
./tools/run_combat_acceptance.ps1 -Mouse
./tools/run_combat_acceptance.ps1 -Touch
circleci config validate .circleci/config.yml
```

CI 使用 Windows executor、固定的 Godot 版本和官方 SHA512 清单。首次资源导入用于建立依赖缓存，随后严格导入必须无错误；完整回归必须出现完成标记且无超时、引擎错误。CI 仅上传指定的导入日志、测试日志和 JSON 摘要，不上传用户存档。SHA512 检查用于验证下载字节，信任来源仍是官方 GitHub 发布及 HTTPS。

本轮未推送、发布或修改签名配置，远端 CircleCI 未执行。Codex Security 差异扫描的固定提交范围及结果另由插件保留报告。
