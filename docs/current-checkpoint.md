# 当前开发检查点

当前为 **0.15.0-dev — SOURCE CANDIDATE**，目标仍是高度可玩并达到Steam发布标准的完整游戏。此阶段只完成源码修复、功能回归和文档准备，尚无0.15新导出、原生整关、FPS或小时验收。

## 当前源码证据

已合入撤收接收营修复：Home正向A撤收时，新建附近B不会改变Guide对这趟接收营的描述；指定车辆或接收营不可用时明确提示。只改Guide观察，没有新运输规则、自动改道/改选或费用/模拟变化。

接收营阶段独立候选`4d1b81ae…`通过819项headless功能检查及38项受控source Main/HUD检查；同一最终反例在旧Guide上116/33预期失败、修复后116/0。最初camp-readout因未提供规定XDG隔离退出1（176/1），正确隔离重跑189/0；GUI v01悬停遮挡与v02探针变化分别保留。证据见[接收营归档](benchmarks/v0.15/withdrawal-receiver/index.json)，不代表后续全部源码重新通过819项。

本轮修复两项确定施工UX缺口：HUD悬停只显示中性放置提示，不查询其下的世界tile；点击未完工建筑可查看原job的进度、供料营、指定施工者及取料/送料/到场等已知阶段，可关闭且不写入存档。不推测堵路，不改资源、订单、规则或时钟；营地卡仍按真实camp状态显示。

最终inspection反例在旧版12/6预期失败、候选88/0，root最终headless88/0实际退出0；最早XDG前缀错误拒绝退出2保留。source GUI v01虽35/0，读图发现紧凑通知条与关闭tooltip遮挡，原图不改；最小布局修正后v02为37/0实际退出0，两张compact图已目视确认。v02及root最终headless当时运行于`a93f8bb…`加记录的HUD差异；随后提交`c2611a7…`的运行脚本SHA与实测一致，原process未改写。[完整施工UI归档](../../source-ui-v015-construction-v01/index.json) SHA256 `2128687c943d1ef1bb4efc7eaa47046ddf4d446032586c00891ed309d1f22e14`。以上不是0.15导出整关、FPS、小时或human证据。

当前77个自有代码文件共25,629物理行、23,380非空行；17个玩法脚本8,781物理行。21个runtime脚本与本轮文档准备起点`c2611a7…`逐项SHA相同；相比已接受0.14，Guide、Main、HUD及ConstructionRules不同，Sim保持原字节，见[完整代码及哈希清单](benchmarks/v0.15/code-size.json)。本轮metadata/docs准备没有新跑引擎。

## 最近接受的实际包：0.14

源码`cb82c33596dfb0ffffb11d133e1e7e0c706b7cfa`，tag `v0.14.0-dev`。同一实际解压Linux包、同一Main连续完成Canyon/Delta/Ridge/Canyon/Delta/Ridge/Canyon七场，游戏记录墙钟**3898.808814秒**。载货盘上续接、完整状态/UI/任务身份、逐关经济及全局/逐关帧端点守恒技术验收通过；native、launcher、独立auto33项和最终collector均有实际退出0。`steam_ready=false`、`performance_acceptance=not_assessed`，不代表稳定60FPS或最低硬件通过。

- [完整接受记录](../../outpost-exodus-0.14.0-dev-release-evidence.json)，SHA256 `34fd4db29cf21126868fba4e7def3f598884ba9ddd63e0d8b9a4d5f2ae217b45`。
- [真实收集过程](../../outpost-exodus-0.14.0-dev-collection-process.json)，SHA256 `2f5f675011bd1fb14ac7aa21a9f3728b9495a9eb1062f30677a09423415dd356`。
- 五张未编辑实机图库与原始输出保留在外部`outpost-exodus-0.14.0-dev-steam-gallery/`及`-native-soak-evidence/`，不与受控source UI截图混用。

## Linux Runtime范围与已结束AI观察

[官方Steam Runtime4实际检查](../../linux-runtime-compat-v014-v01/index.json)，SHA256 `0b81dfe8aeee64dfb4d4f7c304546a8fbbc3d1e96e516bc1c61f0fc4f02d2e42`：同一0.14 payload在Steam Runtime4 / Debian13.7 / build4.0.20261021.265997内headless与rendered子进程均退出0，并生成真实截图。原聚合wrapper因错误期待`SMOKE_OK`而退出1；独立复核按实际`CAPTURE_RESULT 0`退出0，原错误记录未修写。

该检查不是Steam客户端/overlay、原生Windows、Deck、物理干净机器或最低硬件验收。

0.14[黑盒AI观察](../../blackbox-ai-playtest-v014-v01/index.json)已结束，SHA256 `a1984c2c7e79c3de420d5d6816ae806b2d340386c4b082fa215c2ebebf8d043e`：39次输入、8次观察截屏、操作跨度679.594399秒，最终画面游戏钟07:45；未完成整关，无human或听音结论。两项确定施工UX缺口已由本轮源码修复和受控检查覆盖；所谓教程步骤6→5回退与原图不符，不列为已确认缺陷。其他单帧观察不据此推导模拟bug或全面可玩性通过。

后续再决定候选冻结与精确0.15包验证，不继承旧包验收。真人上手/听感/无障碍、Windows/干净机器/最低硬件、最终美术与名称权利、真实Steam项目/Depot/审核仍需各自证据。历史0.14源码文档见[逐字快照](history/v0.14-source-snapshots/index.json)。
