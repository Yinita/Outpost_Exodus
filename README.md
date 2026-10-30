# 逐营突围 · Outpost Exodus

单人、2D 卡通废土战役式推进生存策略。向前清理尸群、铺路建营、生产供能；向后撤出人员设备、封关断后，最终完成出口工程并突围。

当前为 **0.3.0-dev**，包含三场实际可玩的独立战役。长期目标是高度可玩并满足 Steam 发布门槛；目前不能视作正式发行版本。

## 运行

使用 **Godot 4.7.2 stable** 打开 `project.godot`，按 F6/F5 运行项目，或在 Linux 运行：

```bash
chmod +x run.sh
./run.sh
```

未在 PATH 安装引擎时：

```bash
GODOT_BIN=/absolute/path/to/godot ./run.sh
```

启动菜单打开“选择战役”，选择裂谷突围、双桥湿地或山脊换防，按左侧可隐藏、可展开的行动引导推进。需要确认完整规则时，在菜单打开“操作与目标”。

## 当前操作

| 操作 | 默认方式 |
| --- | --- |
| 选择 / 多选 | 左键、拖框、Shift 追加 |
| 移动与交战 | 右键目标区域；X 后左键攻击移动 |
| 镜头 | WASD、中键拖动、滚轮缩放 |
| 小地图 | 左键定位镜头、右键向目标下令 |
| 建设 / 指挥 / 生产 / 训练 | B / V / P / N |
| 编队 | Ctrl+1–4 保存；1–4 选择；Tab 切队 |
| 驻点定位 | Home |
| 战术暂停 | Space，暂停时仍可下达指令 |
| 快速保存 / 读取 | F5 / F9 |
| 补给线 / 覆盖范围 | L / O |
| 速度 | + / -，或顶部速度按钮 |
| 菜单 / 帮助 | Esc / H |

23 个主要按键均可在设置中重绑，冲突会提示，界面与帮助随之更新。设置还提供主音量、音乐/音效独立音量、静音、窗口/全屏、分辨率和界面缩放。存档与设置保存在 Godot 的本机用户数据目录，不进入 Git 仓库。

手动存档、自动存档相互独立。每次有效写入会保留上一份有效备份；主文件损坏时，在菜单明确选择“恢复手动备份”。重新开始需确认，并先保存旧局到自动存档。

## 三场独立战役

| 战役 | 地形与决策 | 已验证的公开指令路线 |
| --- | --- | --- |
| 裂谷突围 | 高地与两道关口，先建材或先燃料 | 26.50 分钟，6 人撤出 |
| 双桥湿地 | 南岸废料、北岸原油，两桥影响转运路线 | 27.57 分钟，5 人撤出 |
| 山脊换防 | 北侧高脊与南谷绕行，换防时机影响车队安全 | 29.71 分钟，6 人撤出 |

各关从自己的队伍和库存开始；这些是脚本指令验证，不替代陌生玩家试玩。进行中切关会先确认并把旧局写入自动存档。

## 当前实际规则

- 高地崖壁阻断通行，坡道、桥梁构成合法跨层路线；单位有体积和分散站位。高地提供射程，实体山体/完整建筑遮挡射击，峡谷上方可以射击，近战不能跨崖攻击。
- 工程队实际领取材料、移动到工地施工，道路可以按路段连续铺设。
- 驻点仓库独立储存建材、补给、燃料及原料，工人和车辆实际搬运。
- 本地发电与生产消耗真实资源，自动炮塔和军营需要供能。
- 军营训练步枪兵和工程师；有电的驻点招募工人；工坊制造运输车。训练占用时间、材料和人口。
- 后方追兵推进与警报对应；关口阻碍可拖延并被敌人破坏。
- 撤收会搬运库存和设备，按接收营地的缺口优先补足燃料/口粮，再装建材；再次点击可紧急弃营、留下未装车资源。
- 出口必须实际施工、供能，并让指挥车辆与人员抵达；等待时间不会自动获胜。
- JSON 存档包含任务、施工、训练、随机状态和物流，坏数据在替换当前战役前验证。

## 验证

```bash
godot --headless --path . --script res://tests/test_campaign.gd
XDG_DATA_HOME="$PWD/work/test-ui-data" godot --path . --script res://tests/test_ui.gd
```

第二项需要可用的图形显示。使用真实 HUD 热点与控制器验证操作；不能替代完整人工试玩。具体证据及边界见 [验证计划](docs/validation-plan.md)，距离发行所需的工作见 [发布门槛](docs/release-gates.md)。

## 代码与资源

- `scripts/campaign_simulation.gd`：独立状态模拟、寻路、战斗、经济、任务、撤营与存档。
- `scripts/world_view.gd`：实际状态驱动的 2D 卡通绘制与建筑贴图。
- `scripts/main.gd`：输入、相机、选择、存读档和设置。
- `scripts/hud.gd`：中文 HUD、小地图、建设、生产、训练与指挥界面。
- `scripts/campaign_guide.gd`：依据真实状态观察进度的行动引导。
- `scripts/campaign_save_store.gd`：写入验证、文件备份和失败回滚。
- `assets/buildings-atlas.png`：本项目使用图像生成工具制作的透明建筑图集。不是静态关卡截图。
- `assets/fonts/`：Noto Sans CJK，许可随资源附带。

代码、场景和关卡配置适合使用 Git / GitHub 管理。大体积美术源文件和音频后续配置 Git LFS。导入缓存 `.godot/`、测试工作目录与导出构建已忽略。当前已建立本地 Git 仓库，尚未创建或推送 GitHub 远程仓库。

## 导出

安装对应的官方 Godot 4.7.2 Linux/Windows x86_64 release templates 后，提交当前源码，执行：

```bash
python3 -m venv work/pe-resources-venv
work/pe-resources-venv/bin/pip install -r tools/build-requirements.txt
GODOT_TEMPLATES_DIR=/absolute/path/to/templates ./tools/export_release.sh
DISPLAY=:0 python3 tools/smoke_native.py
python3 tools/package_builds.py --performance-report /absolute/path/to/native-diagnostics/rendered-benchmark.json
```

工具校验模板摘要、记录导出对应的 Git 提交。Linux 原生启动、截图和忙碌场景完整测量通过后，才能打包原生 Linux/Windows 开发版与源码。Windows 图标/版本由固定版本构建工具写入，并独立校验 PE 结构和代码节不变。构建使用正式运行模板，不附带编辑器；验证状态仍是开发版。Windows 尚未在原生 Windows 系统执行，最低配置和陌生玩家试玩仍未完成。


开发测量使用 `--render-diagnostics`，仅允许全新的专用用户目录，避免碰到正常战役。命令与测量边界见 [验证记录](docs/validation-plan.md)。它会在实际原生游戏中运行 32 友军/100 敌人的控制场景并执行一次真实存档，不代表关卡平衡或最低配置。
