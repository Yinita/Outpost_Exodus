# 营地操作引导修复的源项目验证

基于冻结提交 `07ce021` 的独立 `fix/camp-action-guidance` 分支，仅修改引导与 HUD 的读数、文案和定位目标。Simulation、Main、成本、供能、撤收、运输、任务和胜负规则未改。这里是新的源项目专项记录，不改写 0.13 已接受的导出包证据，也不构成新导出包验收、性能测量或陌生玩家试玩。

## 行为

- 撤收提示写出真实源营与接收营；未选中源营时明确要求先选择它。打包阶段使用实际按钮名“紧急弃营”，定位回源营。定位仍只移动镜头，不自动切换选中营地或下达命令。
- 出口立项前使用实际模拟已有的只读最近营地选择；立项后读取工程记录的 `camp_id`，避免新营或南北错位的更东营地误导库存、道路与供能提示。
- 战术暂停横幅和小窗口标签悬停使用当前暂停绑定，并按运行／暂停状态显示对应动作；较长键名的横幅背景随文字扩展。

`test_mission_guide.gd` 的受控已立项场景补上了实际工程必有的所属营 ID；未改变测试断言。新增测试的营地放置是声明的受控场景；撤收、紧急弃营与出口立项调用原有真实命令。

## 证据范围

`guidance-before.txt` 使用同一 32 项新增测试与 `07ce021` 的原引导脚本，实际退出 1、12 项预期失败。`guidance-after.txt` 为修复后实际退出 0、32/0。旧脚本仅复制到隔离 work 目录，不覆盖基线仓库。其余原始成功日志保留在同目录；完整首关最终回归结果见索引与相应日志。

`native-guidance-ui.txt` 为 1152×648、120% UI 缩放（960×540 逻辑尺寸）的原生源项目检查，54/0，实际退出 0。真实引擎输入验证 J、Backspace，真实悬停和点击验证紧急弃营提示以及只移动镜头的定位。使用 Dummy 音频驱动，不声明音频听感。四张截图全部逐张查看：横幅和关键操作文字可见，源营／接收营未混淆，完整引导弹窗未截掉“先选中源营”和“紧急弃营”。长 Backspace 名称在悬停框内换行，没有裁切。

## 重现

```bash
mkdir -p work
git show 07ce021:scripts/campaign_guide.gd > work/guide-before.gd
./run.sh --headless --script res://tests/test_camp_action_guidance.gd -- --baseline
./run.sh --headless --script res://tests/test_camp_action_guidance.gd
XDG_DATA_HOME="$PWD/work/pause-binding-labels-data" ./run.sh --headless --script res://tests/test_pause_binding_labels.gd
./run.sh --headless --script res://tests/test_mission_guide.gd
./run.sh --headless --script res://tests/test_guide.gd
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/camp-guidance-ui-data" ./run.sh --audio-driver Dummy --script res://tests/test_camp_guidance_ui.gd
```

这些是功能检查；同时运行的测试不能解释为计时实验。原生 Windows、最低配置、实际新导出包及玩家上手验证仍需各自完成。
