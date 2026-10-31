# 当前开发检查点

**0.15.0-dev精确Linux包技术验收已接受**。验收对象是冻结源码`6bf0fe78e9d627fb88a4d3216c66a759feba0fb1`、tree `3b881ee726da2b9d6ccee7236deae31d42a8d488`对应的实际下载包，本地tag `v0.15.0-dev`指向该提交。本次仅更新文档，不重建或重标记已接受包，也不为文档升版。

## 本版实际包与技术证据

同一解压Linux包、同一Main连续完成Canyon/Delta/Ridge/Canyon/Delta/Ridge/Canyon七场。native PID为1947852，Main instance ID为32161924451。**游戏报告墙钟3906.965935秒**；launcher独立观测的native进程生命周期为**3909.00728546601秒**，两种口径分别保留，不互相替代。

native、launcher、supervisor均有实际退出0，33项独立自动存档检查33/0，最终严格collector实际退出0。逐关任务身份、真实费用/运输/供能/出口、载货盘上续接、完整状态与时钟，以及七场和全局帧端点/时间/直方图守恒均通过原严格检查。该接受来自本版精确包，没有继承0.14。

- [完整接受记录](../../outpost-exodus-0.15.0-dev-release-evidence.json)，SHA256 `a9fc2c281fec0e8896af582fffb3c95e3b7d100e5eee22af67dc8121b2f23158`。
- [真实收集过程](../../outpost-exodus-0.15.0-dev-collection-process.json)，SHA256 `de52cb86c14f5fb1b5d9b8f626fb79ab7cb93b96d5851d724f9131baae357576`。
- [本版checksums](../../outpost-exodus-0.15.0-dev-checksums.json)绑定source/Linux/Windows三ZIP；Windows导出与结构检查没有转化为Windows执行结论。

`steam_ready=false`、`performance_acceptance=not_assessed`。控制场景正常/战略两缩放各3600帧加120预热、实际整关分阶段帧记录均已保留；帧算术、均值或小时完成不能证明稳定60FPS、最低硬件或普遍无泄漏。

五张未编辑1920×1080原生游戏图保留在外部`outpost-exodus-0.15.0-dev-steam-gallery/`，原始输出在`-native-soak-evidence/`。root已逐张查看全部五图；这不是美术、商店或权利审批，也不是human试玩。

## 源码阶段与实际UI观察

接收营阶段独立候选`4d1b81ae…`有819项headless与38项受控source GUI证据；同一反例旧Guide116/33预期失败、修复后116/0。最初camp-readout隔离错误176/1及正确重跑189/0、GUI v01/v02探针差异均保留在[接收营归档](benchmarks/v0.15/withdrawal-receiver/index.json)。这些是该阶段证据，不标成后续源码全量重跑。

本轮工地详情/悬停修复的最终inspection为88/0，source GUI v02为37/0，实际退出均0；旧版同test12/6预期失败、错误XDG前缀拒绝2、GUI v01虽35/0但读图发现遮挡的原件全部保留。[施工UI归档](../../source-ui-v015-construction-v01/index.json)说明v02运行于`a93f8bb…`加HUD差异、最终`c2611a7…`字节匹配的来源，未改原process。详情只读原job，不改费用、订单或模拟，不写入存档。

同一本版实际包另完成[两场有界知情AI UI观察](../../native-ui-v015-v01/index.json)及[root目标复查](../../native-ui-v015-root-review-v01.json)：两场native与监督器均实际退出0，普通Canyon自然施工与受控接收营存档分开标注。原退出后截图bridge1、操作坐标误述及普通范围tooltip短暂遮挡保留；不称独立黑盒、人类或全部tooltip问题已解决。

0.14[黑盒AI原始观察](../../blackbox-ai-playtest-v014-v01/index.json)已结束：39次输入、8次观察截屏、679.594399秒操作跨度，未完成整关。两项确定施工UX缺口促成本版修复；教程步骤回退说法与原图不符，不列为确认bug。

## 分发与仍缺的门槛

[本版官方Steam Runtime4检查](../../linux-runtime-compat-v015-v01/index.json) SHA256 `68d3556097938fec01186fa8b84f6f797153c1b67e2f1b5b09572dda3dd75745`：实际包在官方Runtime4环境完成OS身份、headless启动与rendered截图，真实前台过程退出0，payload未变。Runtime归档来源引用旧原件；这不是SDK编译、Steam客户端/overlay、Runtime内整关、Deck或最低硬件验收。

当前77个自有代码文件25,629物理行、23,380非空行；17个玩法脚本8,781物理行。21个runtime脚本逐项SHA均匹配15冻结6bf，见[完整代码清单](benchmarks/v0.15/code-size.json)。本轮文档准备没有运行引擎或测试。

素材台账历史source pins不改写；当前差异与通知绑定见[内容调查草稿](../../steam-content-survey-v015-draft-v01/index.json)和[本版包通知核对](../../steam-content-survey-v015-package-binding-v01.json)，均未提交或批准。真人上手/听感/无障碍、原生Windows、干净机器/最低硬件、最终权利及真实Steam项目/安装/审核仍待实际证据。离线Windows检查材料或未来Linux解析不能记作Windows执行通过。

冻结6bf的五份原候选文档逐字保留在[0.15历史快照](history/v0.15-source-snapshots/index.json)，其中旧“待验证”仅描述导出前阶段；0.14快照及所有旧证据不变。
