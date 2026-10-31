# 验证计划

本页描述当前0.14候选的验证方式；具体结果以带源码/制品哈希、实际进程和范围的记录为准。[当前检查点](current-checkpoint.md)区分源项目、旧包和新包，发行要求见[发布门槛](release-gates.md)。

## 已完成的本版源码检查

- 独立碰撞候选：首阻挡体381、路径194、导航151、到站2329、战役170、完整Guide211，均0失败、实际退出0。
- 两份真实107单位Ridge保存态，Sim-only及Sim+Guide各400步；1604次完整编码状态/RNG/Guide精确比较相同。
- 原固定CPU探针按baseline/candidate/candidate/baseline顺序运行；每角色两次，保留首步，源码哈希前后固定。无原生FPS或统计显著性结论。
- 引导修复同一回归在旧源码32项/12失败，在修复源码32/0；原始失败日志保留。
- 最终合并源码：381/0、32/0、16/0、原生专项55/0、完整首关211/0，实际退出均0；原生小窗口1152×648@120%截图独立保留。

[碰撞原始证据](benchmarks/v0.14/first-blocker-rejection/index.json)、[合并原始证据](benchmarks/v0.14/integration/index.json)、[引导分支原始证据](benchmarks/camp-action-guidance-fix/index.json)具有不同精确范围，不把阶段结果改写成最终源码结果。

## 常用功能命令

```bash
godot --headless --path . --script res://tests/test_campaign.gd
godot --headless --path . --script res://tests/test_first_blocker_rejection.gd
godot --headless --path . --script res://tests/test_camp_action_guidance.gd
XDG_DATA_HOME="$PWD/work/pause-binding-labels-data" godot --headless --path . --script res://tests/test_pause_binding_labels.gd
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/camp-guidance-ui-data" godot --path . --audio-driver Dummy --script res://tests/test_camp_guidance_ui.gd
```

涉及用户目录的测试使用专用开发数据，不替换玩家存档。重复证据运行时先使用新的工作树或保留已有受控目录/输出，避免覆盖原始记录。GUI检查是实际源项目渲染与控制器输入，不是人类试玩。

## 导出和独立原生验证

安装 Godot 4.7.2官方Linux/Windows x86_64 release templates，提交源码，保持工作树干净。构建依赖见 `tools/build-requirements.txt`。

```bash
GODOT_TEMPLATES_DIR=/absolute/path/to/templates ./tools/export_release.sh
DISPLAY=:0 python3 tools/smoke_native.py
python3 tools/package_builds.py --performance-report /absolute/path/to/rendered-benchmark.json
```

原生控制场景应从实际导出的文件运行完整32友军/100敌人、正常/战略两缩放，每组3600测量帧加120预热；仅作控制场景观察。整关验证使用正常Main、真实经济、0.05固定模拟步和界面3倍速度，在隔离目录中启动：

```bash
DISPLAY=:0 python3 tools/run_native_campaign.py   --build-dir /absolute/path/to/actual-unpacked-linux-build   --mission ridge   --isolation-root "$PWD/work/native-v014-ridge-fresh"
```

`--prepare-only`仅证明启动和短主循环。完整路线与七场/三图/小时分别验收；保留真实EXE/PCK/ZIP来源、进程argv/PID/start ticks、墙钟与实际wait退出、载货盘上续接及完整状态/UI/任务身份。沿用严格帧守恒检查器，不丢跨局间隔。最近0.13接受记录见[evidence](evidence/v0.14/prior-v013-release-evidence.json)，不能用于0.14新包验收。

## 尚需真人与目标平台

陌生玩家、听感/无障碍、最低硬件、Windows原生和干净机器分别保留真实观察。外部 `outputs/playtest-kit-v013/` 可辅助首次试玩及可选宏观练习；该工具包不包含已经发生的真人结果。Windows PE可导出且可独立检查，Linux不能证明Windows执行。
