# 当前开发检查点

当前源码 **0.16.2-dev候选，尚未导出**。单人、2D卡通、三场独立战役。`steam_ready=false`，`performance_acceptance=not_assessed`。

## 当前引导修复

Home仍在向A撤收、而更前方B已建好时，旧引导要求撤收A，唯一主车尚忙使实际命令必被拒绝。现在只读真实主车与绑定记录，说明当前起讫点、返程／装车／末班运输及等待原因，定位实际车辆；记录无效时明确检查，空闲后恢复原可执行提示。不改Sim/Main/HUD/SaveStore/readout、订单、资源、RNG、存档字段或按键。

同一最终测试原cf Guide204／43失败，修复后204／0；相关headless合计584／0。受控source GUI67／0，实际native与工具均0，三张PNG由root逐张查看；输入是引擎派发至真实HUD/Main，非OS XTest或真人。完整状态与选择／运输保持、默认及小窗口120%UI、正常Main退出均覆盖。[修复证据](benchmarks/v0.16.2/guide-transport-availability.json)。功能验证后仅更新版本／文档，runtime/test字节未变。

## 已接受的0.16.1精确包

冻结source/tag `cf678b720daad2ceb1c3a40ce4949a5343c39d82` / `v0.16.1-dev`，tree `8f05ea33bbe71d44b74979d1a2a479d1005c10b9`。同Main七场C/D/R/C/D/R/C真实胜利，游戏报告3979.349975秒、launcher观察native3981.0773600769753秒。root68652终局031dd7实际0，native/launcher/supervisor均0，原进程已退出。

独立严格路线／经济／七场与全局帧守恒、47个卸货事务及四份封存存档读回通过。source probe215／0、collector/root11394终局016715实际0。按生产JSON codec规则检查完整编码状态和RNG；[独立边界诊断](../../source-auto-json-diag-v0161-v01/index.json)说明数字解析与Vector2类型恢复，原literal208／4失败保留，不作raw十进制或解析前IEEE位保真承诺。

[接受记录](../../outpost-exodus-0.16.1-dev-release-evidence.json)，SHA `44ef0f2af687317fce03e4741e1945c35834b4b989b62cc1e28fa758410eda94`；[实际收集过程](../../outpost-exodus-0.16.1-dev-collection-process.json)，[五张原始实机图](../../outpost-exodus-0.16.1-dev-steam-gallery/index.json)。普通两代自动存档保留原44／44／180秒门槛并验证SHA换代与退出前封存。软件Mesa渲染数据仅代表受控环境，不评最低硬件或稳定60FPS。

## 规模与下一步

[代码统计](benchmarks/v0.16.2/code-size.json)：18个玩法等脚本8,875物理行；81个自有文件26,560物理行、24,227非空行。排除引擎、第三方、素材、场景、UID、缓存及外部探针。

下一步导出精确0.16.2并绑定实际包验证。Windows原生、陌生玩家体验／听感／可读性／无障碍、目标硬件、权利及真实Steam项目／安装更新审核仍待完成。[本版试玩说明](../../playtest-kit-v0161/first-playtest.txt)与[0.16.1来源补充](../../steam-content-survey-v0161-draft-v01/index.json)均为待owner使用／确认的材料，没有预填人类或Valve结果。

## 历史

0.16原包第四关超时失败及[111份原件](../../rejected/outpost-exodus-0.16.0-dev-delivery-observation-v01/index.json)保留。0.15冻结6bf原包的七场／小时接受仍只属于原包。既有历史快照、素材台账、旧pins与所有原始日志不改写。
