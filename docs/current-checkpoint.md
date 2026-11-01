# 当前开发检查点

当前开发版 **0.16.2-dev** 的精确导出冻结于 `aaae0064413528b6c135f76d308118465e34831d` / tree `32c02312c7cec6268bd590112a8a1ad25b785388`。新包导出、原生smoke、标准双缩放渲染、三ZIP、严格解压和两个受控普通原生Guide场景已通过。当前文档更新不改变22runtime脚本；完整战役／七场与双墙钟长测尚待当前包实际完成。单人、2D卡通、三场独立战役；`steam_ready=false`，`performance_acceptance=not_assessed`。

## 当前引导修复

Home仍在向A撤收、而更前方B已建好时，旧引导要求撤收A，唯一主车尚忙使实际命令必被拒绝。现在只读真实主车与绑定记录，说明当前起讫点、返程／装车／末班运输及等待原因，定位实际车辆；记录无效时明确检查，空闲后恢复原可执行提示。不改Sim/Main/HUD/SaveStore/readout、订单、资源、RNG、存档字段或按键。

同一最终测试原cf Guide204／43失败，修复后204／0；相关headless合计584／0。受控source GUI67／0，实际native与工具均0，三张PNG由root逐张查看；输入是引擎派发至真实HUD/Main，非OS XTest或真人。完整状态与选择／运输保持、默认及小窗口120%UI、正常Main退出均覆盖。[修复证据](benchmarks/v0.16.2/guide-transport-availability.json)。功能验证后仅更新版本／文档，runtime/test字节未变。

新精确解压包另从普通菜单加载两份明确平地／高库存fixture，使用真实OS鼠标键盘展开／定位、F5保存、空闲后公开A→B下单和正常菜单退出。忙／闲两个native与工具实际0；相同暂停实例Guide操作前后完整Sim/RNG及选营／选人／编组／速度／覆盖层不变，保存镜头匹配真实主车／A营。另成阶段的有意撤营实际接受，不声称其前后Sim不变。20张原始PNG均完整解码，root查看展开／定位／下单关键图，见[原生root复核](../../native-guide-v0162-root-review-v01.json)。外部fixture helper首轮解析失败保留，修后37／0仅属fixture构造；不是默认开局整关或真人证据。

## 0.16.2实际包阶段

导出tool72663终局9e412f实际0；pipeline10163终局4572d8实际0，smoke／benchmark／package三阶段均0。普通／战略各3600帧+120预热、原max600，软件Mesa测量用567.755738秒，两个视角真实保存读回有效；不等同目标硬件或稳定60FPS。

[三包checksums](../../outpost-exodus-0.16.2-dev-checksums.json) SHA `707b7b00b1327b8c38f8aa24bbf7bf0a096a5a05647c93df5767c46c8b0682a4`。root8741终局2e94bd实际0，三ZIP／872源码文件／CRC／通知／元数据／权限逐项核对，并从Linux ZIP创建全新副本。EXE `d9f79ab8…`、双PCK `0eeaf196…`、WindowsEXE `9c1644a5…`。[阶段证据](benchmarks/v0.16.2/package-stage.json)绑定完整SHA与原始记录。

普通Canyon1x两代自动存档已实际通过原44／44／180秒门槛：首代下界44.940392976秒、第二代间隔下界44.975124021秒、第二代从开始点击的上界90.1105907秒。暂停后退出前封存两槽，backup保留primary1；native／observer均实际0。root重算原始单调时钟、48文件SHA并查看00:45运行／01:30暂停原图，见[普通auto复核](../../native-auto-cycle-v0162-root-review-v02.json)。benchmark最终两槽也已在原native退出后原字节封存，不宣称frame300或固定45秒保留窗口。

本版四槽独立no-tick诊断已实际完成：root93591终局87fea1引擎／工具0，纯Python分类12e7d0实际0。完整结构、数组entries顺序与RNG字符串一致；308／308／154／154项float→int均为可精确表示的安全整数，32／27／0／0项Vector2坐标表示变化均保留同一float32位模式。原始十进制到Godot首次解析的尾差另列，不宣称raw token或解析前IEEE位保真；相对实际Godot解析后的非Vector2数值差异为0。[本版诊断](../../source-auto-json-diag-v0162-v01/index.json)及[root语义复核](../../source-auto-json-diag-v0162-v01/root-semantic-review.json)保留全量导出、原槽与类型树。此项不是完整postterminal source probe、Main UI验证或原生长测接受；那些入口仍须完整成功终局。

当前新包prepare实际完成0（root30641终局627907），范围只到启动／短循环／真实磁盘续接。随后原七场长测root93484／f07504实际以627acf终局1：launcher1、native -11，原生进程实际504.33434769598534秒，第一场Canyon尚未胜利。末次进度是出口施工道路窗口，sim1479.1，原营3次／中营4次真实交付。没有完整native report或小时接受。

原合并日志记录X98连接断开、SIGSEGV与退出清理错误；Xvfb3103833及监督器3103827也已消失，未产生server-wait记录，原server工具15220返回Unknown。缓冲合并日志不足以证明线程先后；目前没有可用core／函数栈，也没有显示服务退出信号或发送者的确定证据，不能归因于Guide或工具宿主。[71份原失败快照](../../rejected/outpost-exodus-0.16.2-dev-native-x11-disconnect-v01/index.json)逐字保留，原失败不改为通过。后续先诊断显示／原生退出路径与监督生命周期；任何重新验证都使用新隔离目录，保留七关／双墙钟、真实费用／库存／三交付与原超时门槛。

后续[标题界面短A/B](../../native-v0162-display-loss-ab-v01/index.json)与[真实晚期存档A/B](../../native-v0162-late-state-ab-v01/index.json)已实际完成。晚期两例普通加载同一封存sim1455.5存档，经公开UI付12建材下达6格道路，各完成至少120外部秒；正常观察期均未崩溃，末次F5均playing、道路完工且出口建成供能。之后只对各自owned显示服务显式SIGTERM，两版native均退出1、server0，未复现原-11。A例多约42.8秒暖跑，两例不是同tick或性能配对；设置误点、只读准备错误和裁切截图被拒绝的原件保留。这些对照没有证明原X98为何退出。

新的私有显示与strict launcher改为同一owner监督，增加真实wait／信号／周期身份与内存观察；24非main验证函数及原main控制流保持，新增仅旁路I/O。新prepare原86431终局4118fe实际0，native／launcher／server三wait均0且全部回收。随后root85687／fb1671已启动全新 `native-soak-v0162-full-attempt02`，使用同一aaae包与原7场、游戏与进程各≥3600秒门槛，私有99、五秒心跳；尚待实际终局与独立复核。[阶段证据](benchmarks/v0.16.2/package-stage.json)绑定新启动及原失败，两者不互相覆盖。

## 已接受的0.16.1精确包

冻结source/tag `cf678b720daad2ceb1c3a40ce4949a5343c39d82` / `v0.16.1-dev`，tree `8f05ea33bbe71d44b74979d1a2a479d1005c10b9`。同Main七场C/D/R/C/D/R/C真实胜利，游戏报告3979.349975秒、launcher观察native3981.0773600769753秒。root68652终局031dd7实际0，native/launcher/supervisor均0，原进程已退出。

独立严格路线／经济／七场与全局帧守恒、47个卸货事务及四份封存存档读回通过。source probe215／0、collector/root11394终局016715实际0。按生产JSON codec规则检查完整编码状态和RNG；[独立边界诊断](../../source-auto-json-diag-v0161-v01/index.json)说明数字解析与Vector2类型恢复，原literal208／4失败保留，不作raw十进制或解析前IEEE位保真承诺。

[接受记录](../../outpost-exodus-0.16.1-dev-release-evidence.json)，SHA `44ef0f2af687317fce03e4741e1945c35834b4b989b62cc1e28fa758410eda94`；[实际收集过程](../../outpost-exodus-0.16.1-dev-collection-process.json)，[五张原始实机图](../../outpost-exodus-0.16.1-dev-steam-gallery/index.json)。普通两代自动存档保留原44／44／180秒门槛并验证SHA换代与退出前封存。软件Mesa渲染数据仅代表受控环境，不评最低硬件或稳定60FPS。

## 规模与下一步

[代码统计](benchmarks/v0.16.2/code-size.json)：18个玩法等脚本8,875物理行；81个自有文件26,560物理行、24,227非空行。排除引擎、第三方、素材、场景、UID、缓存及外部探针。

下一步跟踪原coupled新长测85687的实际进程与终局，再审新元数据来源下的严格帧账／路线／完整source／collector。原SIGSEGV仍未定因，不能用单项或新尝试覆盖原失败。Windows原生、陌生玩家体验／听感／可读性／无障碍、目标硬件、权利及真实Steam项目／安装更新审核仍待完成。[本版试玩说明](../../playtest-kit-v0162/first-playtest.txt)与[0.16.2来源补充](../../steam-content-survey-v0162-draft-v01/index.json)绑定真实新包，没有预填人类或Valve结果。Windows bound脚本仅PS7/Linux ParseFile实际通过，不是Windows执行。[本地SteamPipe staging](../../steampipe-v0162-staging-v01/index.json)只含每平台EXE+PCK+三通知；AppID/Depot/entity/account仍UNBOUND，没有登录、SteamCMD执行或上传。

## 历史

0.16原包第四关超时失败及[111份原件](../../rejected/outpost-exodus-0.16.0-dev-delivery-observation-v01/index.json)保留。0.15冻结6bf原包的七场／小时接受仍只属于原包。既有历史快照、素材台账、旧pins与所有原始日志不改写。
