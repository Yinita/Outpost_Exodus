# 验证计划

当前 **0.15.0-dev — SOURCE CANDIDATE**，没有本版新导出/原生整关/FPS/小时结论。[检查点](current-checkpoint.md)区分当前源码、最近接受0.14包与已结束的AI观察。

## 已有源码证据

接收营阶段在独立候选`4d1b81ae…`执行：同一最终测试字节，旧Guide116/33预期失败（实际退出1），候选116/0；另有营地操作32/0、任务引导137/0、正确隔离营地卡片189/0、SaveStore134/0、完整Guide211/0，共819项通过，子进程退出均0。该阶段结果不标成当前全部代码重新通过819项。

最初营地卡片启动未提供要求的XDG隔离，原176/1和退出1保留，不是生产bug；只修启动环境后189/0。GUI v01与v02均38/0、实际退出0；v01有悬停遮挡，v02只调整探针鼠标与受控故障后的derived-card刷新。原始日志、过程、源码和PNG绑定见[证据索引](benchmarks/v0.15/withdrawal-receiver/index.json)。这些是合法受控fixture、公开付费命令、正常tick及实际source窗口输入，不是原生整关、人类或性能证据。本轮metadata/docs准备没有运行引擎。

本轮施工inspection最终同一测试在旧版12/6预期失败、候选88/0；root在最终HUD布局字节上headless88/0实际退出0，最初错误XDG前缀的拒绝退出2另存。检查覆盖HUD内不查询、移到地图恢复、点击重新校验、真实付费施工阶段、完整Sim/RNG只读、临时选择不入存档及读盘/重启清理。

受控source GUI v01为35/0，但原图发现compact通知与关闭tooltip遮挡；最小布局修正后v02为37/0实际退出0，保留五张图及两张compact视觉复查。v02运行于`a93f8bb…`加记录的HUD差异，最终`c2611a7…`逐运行脚本SHA匹配实际字节，原process不改写。[完整归档](../../source-ui-v015-construction-v01/index.json)保存失败、成功及阶段来源；没有据此声称整关、性能或human通过。

```bash
godot --headless --path . --script res://tests/test_withdrawal_receiver_guidance.gd
godot --headless --path . --script res://tests/test_camp_action_guidance.gd
XDG_DATA_HOME="$PWD/work/camp-readout-data" godot --headless --path . --script res://tests/test_camp_readout.gd
godot --headless --path . --script res://tests/test_save_store.gd
godot --headless --path . --script res://tests/test_guide.gd
XDG_DATA_HOME="$PWD/work/construction-inspection-data/manual-check" godot --headless --path . --script res://tests/test_construction_inspection.gd
```

按各测试规定使用隔离用户目录；证据重跑保留旧日志/输出，不覆盖原记录。Guide查询前后比较完整编码Sim/entry order与精确RNG；不为通过而改变经济、订单、运输或时钟。

## 精确新导出包

黑盒AI观察已结束，本轮两项确定UX缺口已处理；仍须另行决定冻结候选并验证精确新包。使用Godot4.7.2官方Linux/Windows release templates，保持源码干净，构建依赖见`tools/build-requirements.txt`。

```bash
GODOT_TEMPLATES_DIR=/absolute/path/to/templates ./tools/export_release.sh
DISPLAY=:0 python3 tools/smoke_native.py
python3 tools/package_builds.py --performance-report /absolute/path/to/rendered-benchmark.json
DISPLAY=:0 python3 tools/run_native_campaign.py --build-dir /absolute/path/to/actual-unpacked-linux-build --mission ridge --max-seconds 1800 --isolation-root "$PWD/work/native-v015-ridge-fresh"
```

先保留完整32友军/100敌人、正常/战略两缩放各3600测量帧加120预热的独立控制场景，再保留真实路线分阶段帧间隔。使用正常Main、0.05模拟步、界面3倍速度和实际费用；`--prepare-only`只证明启动/短循环，不能代替整关。七场三图/小时还需同一Main、真实墙钟至少3600秒和严格逐关/全局端点守恒，保存完整状态/UI/任务/载货盘上续接及实际退出。沿用现有严格verifier，不补帧、不宽松重解释失败。

## 最近接受包与目标环境

0.14源码`cb82c335…`的[完整外部接受记录](../../outpost-exodus-0.14.0-dev-release-evidence.json)和[收集实际退出](../../outpost-exodus-0.14.0-dev-collection-process.json)保留七场、三图、3898.808814秒；不转移为0.15新包接受。0.14[官方Steam Runtime4检查](../../linux-runtime-compat-v014-v01/index.json)保留headless/rendered子进程0、真实容器OS及截图；错误marker wrapper1与独立复核0分开保留。它没有测试Steam客户端、Windows、Deck或最低硬件。

0.14[黑盒AI](../../blackbox-ai-playtest-v014-v01/index.json)已完成39次输入、8次观察截屏、679.594399秒操作跨度，未完成整关；所谓教程步骤回退与原图不符，不列为已证实缺陷。这不是human或当前0.15新包通过。真人上手/听感/无障碍、Windows、物理干净机器与最低配置仍须独立实际观察。历史计划原字节见[0.14快照](history/v0.14-source-snapshots/index.json)。
