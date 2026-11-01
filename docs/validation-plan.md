# 验证计划与已完成范围

当前0.16.2-dev精确导出冻结于aaae0064。Guide相关headless584／0、source GUI67／0，旧cf同用例204／43失败保留。[源码修复索引](benchmarks/v0.16.2/guide-transport-availability.json)。新包实际导出、smoke、普通／战略各3600帧+120预热、三ZIP与严格解压已完成；22runtime脚本在文档更新中保持冻结源字节。

实际解压包另用两份明确平地／高库存fixture，经普通菜单load、OS输入、F5与正常退出检查Guide忙／闲状态，两个native及工具均0。相同暂停实例Guide前后完整Sim/RNG与指定UI字段不变，真实主车／A营镜头精确匹配；另成阶段的公开A→B命令实际接受，不宣称该有意命令前后Sim不变。[root原生复核](../../native-guide-v0162-root-review-v01.json)核20张原始PNG并查看关键像素。外部fixture helper首轮缩进解析失败保留，修后37／0只属于fixture生成；此项不充当默认开局、整关、小时、真人或性能验收。[当前包阶段记录](benchmarks/v0.16.2/package-stage.json)列明当前包完整路线／七关／双墙钟及四槽source读回仍待结果。

0.16.1冻结cf精确Linux包七关三图完成：游戏3979.349975秒／native3981.0773600769753秒；native/launcher/supervisor/root均实际0。严格路线经济、全部帧守恒、47卸货事务和215项四槽schema/JSON codec/RNG复核通过。[接受记录](../../outpost-exodus-0.16.1-dev-release-evidence.json)及[真实收集](../../outpost-exodus-0.16.1-dev-collection-process.json)保留范围；原208／4字面对比失败与独立codec边界诊断均保留，不将raw十进制或解析前IEEE位作为已证明不变。

以下0.15记录属于历史精确包，不继承给当前候选。

**0.15.0-dev精确Linux包技术验收已接受**。冻结source `6bf0fe78e9d627fb88a4d3216c66a759feba0fb1` / tree `3b881ee726da2b9d6ccee7236deae31d42a8d488`，本地tag `v0.15.0-dev`指向该源；该历史接受后的文档更新没有重建原包。

## 本版实际包证据

新导出、原生smoke、正常/战略各3600帧加120预热控制场景、package/unpack字节/通知/权限核对和prepare均有实际记录。随后同一实际解压包、同一Main完成七场C/D/R/C/D/R/C；游戏报告3906.965935秒、launcher观察native生命周期3909.00728546601秒分别保留。native、launcher、supervisor实际0，独立自动存档检查33/0，最终collector实际0。

逐关原完整路线、经济/供能/真实到达、任务身份、时钟/完整状态、载货磁盘续接，以及七场和全局帧计数/时间/直方图守恒均由原严格验证器复核。最终[接受记录](../../outpost-exodus-0.15.0-dev-release-evidence.json)与[真实收集过程](../../outpost-exodus-0.15.0-dev-collection-process.json)绑定实际文件，没有借用0.14通过；`performance_acceptance=not_assessed`、`steam_ready=false`。

实际包另有[两场知情AI UI检查](../../native-ui-v015-v01/index.json)及[root截图/过程复查](../../native-ui-v015-root-review-v01.json)，两场native和supervisor退出0；一场普通Canyon自然施工，一场使用已声明的受控receiver存档。退出后截图bridge1等原始记录不改写。官方[Runtime4本版启动/截图](../../linux-runtime-compat-v015-v01/index.json)实际退出0、payload未变，范围限于环境身份与启动/截图。

五张整关原生图库是未编辑1920×1080 PNG，root已逐张查看；这是图像证据审阅，没有追加human、美术/rights或Steam审批。

## 独立源码阶段证据

receiver阶段`4d1b81ae…`有819项headless与38项source GUI；同一反例旧Guide116/33预期失败、修复后116/0。原camp-readout隔离错误176/1、正确重跑189/0、两版GUI探针与原图见[接收营阶段归档](benchmarks/v0.15/withdrawal-receiver/index.json)，不称当前全部源码重新跑了819项。

施工修复最终inspection88/0、source GUI v02 37/0实际退出0；旧版同test12/6、错误XDG拒绝2和v01检查35/0但视觉有遮挡的证据都保留。[施工UI归档](../../source-ui-v015-construction-v01/index.json)明确v02当时为a93加HUD布局差异、随后c261逐runtime匹配，原process未改写。这些检查覆盖纯HUD命中、真实计划恢复/权威点击、既有job阶段、完整Sim/RNG只读及临时选择不入存档。

需要针对源码改动重跑时，按测试要求使用fresh隔离；以下只是现有入口，不代表本次又执行过：

```bash
godot --headless --path . --script res://tests/test_withdrawal_receiver_guidance.gd
XDG_DATA_HOME="$PWD/work/construction-inspection-data/fresh-check" godot --headless --path . --script res://tests/test_construction_inspection.gd
```

## 复现与后续新包

复现已接受包应先在独立目录检出冻结tag/source6bf，保留原ZIP和证据，不把当前文档提交重新标成原包。使用Godot4.7.2官方模板与`tools/build-requirements.txt`。导出入口为`tools/export_release.sh`，再运行`tools/smoke_native.py`、原生`--render-diagnostics`和`tools/package_builds.py`；工具要求干净提交及当前payload对应的真实smoke/render证明。

以后若产生新payload，应使用新隔离与新输出，原生完整路线由`tools/run_native_campaign.py`执行。普通模式保留`--mission canyon|delta|ridge`；七场模式保留`--soak`及真实墙钟≥3600。prepare只证明启动/短循环/盘上续接，不作为整关。保持正常Main、0.05模拟步、实际费用与UI3倍速度；不减少部队、不改时钟换性能，不修写失败或补丢帧。

## 尚未关闭的范围

稳定60FPS、最低硬件、原生Windows、物理干净机器、Steam客户端/安装更新/审核、人工听音/无障碍与人类可玩性仍待实际证据。离线Windows脚本或Linux上的解析准备不作为Windows执行通过。

0.14[黑盒AI观察](../../blackbox-ai-playtest-v014-v01/index.json)是39次输入、8次观察截屏、679.594399秒操作跨度，非human、未完成整关；教程回退说法被原图否定。当前素材旧pins与权利差异见[内容调查草稿](../../steam-content-survey-v015-draft-v01/index.json)，不改写历史来源。冻结6bf的五份候选文档逐字见[0.15历史快照](history/v0.15-source-snapshots/index.json)。
