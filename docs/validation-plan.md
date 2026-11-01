# 验证计划与已完成范围

## 0.16.3源码阶段

当前0.16.3-dev功能源基线为 `4306c2431faf225f742f142836959fe4992a7900`，Main `9920bed4…`，其余21个runtime脚本与AAAE逐字一致。[源码阶段记录](benchmarks/v0.16.3/source-stage.json)及[root复核](../../source-camera-selection-root-review-v01.json)绑定本轮实际受测字节，并逐项核对合入后的83份代码清单；不声称本轮重新执行了全部测试文件。

已实际完成headless479／0（loaded-selection61、camera305、运输状态113）、既有四项实绘GUI552／0、新镜头GUI248／0，相关engine／工具／owned server真实退出均0。覆盖logical viewport／zoom四边约束、小图居中、HUD安全定位、真实postdraw／resize、原视角精确load、读档单位整数UI ID及只读操作的原运输／完整Sim／RNG保持。新增GUI的外部16px实际canvas检查和整数ID严格比较未放松，17px只作内部投影guard；root看4张关键图，另23张capture完整解码。

[原GUI首轮6项失败](../../source-camera-viewport-gui-v01/attempt01-results-index.json)、[原退出资源残留与verbose A/B未复现](../../source-camera-ui-leak-ab-v01/index.json)、[旧loaded-ID诊断](../../source-camera-id-diagnostic-v01/index.json)与[原／修反例](../../source-loaded-selection-regression-v02/index.json)保留。后续测试的两处scene retirement等待至少120ms真实墙钟，不屏蔽资源日志。上述检查限于source与引擎派发输入，不是OS XTest、真人、导出包整关或性能接受。**本版已冻结561313a并实际导出新payload，但其余包阶段与整关／小时验收尚待完成。**

## 新payload必须独立完成

冻结新源后使用Godot4.7.2官方模板与`tools/build-requirements.txt`，在新隔离目录运行`tools/export_release.sh`、`tools/smoke_native.py`、原生`--render-diagnostics`、`tools/package_builds.py`及严格unpack。smoke、普通／战略各3600帧+120预热、原max600、实际像素／磁盘续接、三ZIP的hash／CRC／通知／metadata／权限要求保持；prepare只证明启动、短循环和真实盘上续接。

完整路线继续使用`tools/run_native_campaign.py`的原严格验证器，不改成功／失败门槛：

- 七场C/D/R/C/D/R/C必须在同一真实Main／native PID内全部胜利，6次普通title／campaign／new／restart公开切换；各轮任务身份、累计tick连续、真实磁盘UI／save-load／auto及最终proof逐一绑定。
- 游戏与launcher分别使用独立单调真实时间，**两者各≥3600秒**才可称一小时；不得以simulation time、菜单等待补足、快钟或fixture循环替代。普通单关默认900秒、合法60–1800秒；soak默认5400秒，原合法参数范围3600–7200秒不变。标准运行和原路线各阶段timeout／最小窗口不得为失败临时延长，soak与prepare不能合用。
- 保持普通Main的0.05秒模拟步／20Hz与标准UI3倍速，不减少部队、AI、rate或费用，不注入tick／状态／资源／重下运输单救场。必须实际完成原路线、真实卸货／库存与供能；退出工程140建材／45燃料／30口粮及6电、本地支付／运达／施工、主车和至少4人真实到场等原经济与到达检查保持。
- 每轮保存完整报告和最终状态，按实际argv、任务、EXE／PCK与source metadata绑定；所有native／launcher／owned display与监督器的真实wait／清理记录分别保留，未知退出码不能推断为0。只有全部终局成功后才能运行postterminal读回与collector；运行中／中断／失败不得制造接受结果。
- 逐关与全局使用原**257个固定直方图bins**及独立frame checker：`all = active + excluded`、`active = 8 phases之和`，count／sum_usec／hist／endpoint与首尾时间守恒、invalid=0、overflow和跨phase／state边界、普通保存操作跨度与actual max关系均保持。正常保存长帧不能隐藏；p95／p99保留桶区间，不伪造原始帧序列或精确分位数，也不据平均FPS自动判稳定60。

普通Main两代自动存档仍用真实Canyon1x、无save指令／fixture注入，保持44／44／180秒预设门槛：首代primary写入、第二代不同SHA primary出现且backup为primary1；首写backup可与primary1相同，不算第二周期。暂停后、普通退出另存之前稳定SHA封存原槽。benchmark槽按实际结束字节保留，不宣称固定frame300／45秒窗口。

postterminal source检查继续按生产JSON codec核完整schema／entries顺序／状态／RNG及UI续接，区分安全整数恢复、Vector2 float32表示与原始十进制首次解析边界；不承诺未经证明的raw token或解析前IEEE位保真。不修写原报告，不补帧，不以新尝试覆盖旧失败。

## 最新已接受的精确包：0.16.2／AAAE

原source/tag `aaae0064413528b6c135f76d308118465e34831d`／`v0.16.2-dev`、tree `32c02312c7cec6268bd590112a8a1ad25b785388`及其ZIP未随当前source修改。导出、标准smoke／render／package／unpack／prepare和两个普通Main受控Guide场景有[包阶段记录](benchmarks/v0.16.2/package-stage.json)及[原生Guide复核](../../native-guide-v0162-root-review-v01.json)；后者明确平地／高库存fixture、OS输入／F5／正常退出，不充当默认开局整关或真人。

独立attempt02 root85687→c10e11实际0：同Main七场全部胜利，游戏4016.244577秒／native4018.0584507070016秒，native／launcher／server三wait0。source18792→d05d54实际0、四槽215／0；collector59104→3c89f0实际0，逐关与全局帧账、原路线经济和普通auto复核通过。[接受记录](../../outpost-exodus-0.16.2-dev-release-evidence.json)、[实际收集](../../outpost-exodus-0.16.2-dev-collection-process.json)、[auto复核](../../native-auto-cycle-v0162-root-review-v02.json)均仅归该包。AAAE已知loaded-selection float/int membership缺口没有被这次技术接受排除，旧ZIP仍含缺口，当前source已修。

首次root93484→627acf仍为失败1／native -11，原生504.33434769598534秒、C1未胜利。[71份原件](../../rejected/outpost-exodus-0.16.2-dev-native-x11-disconnect-v01/index.json)与[系统窄审](../../native-v0162-x11-failure-audit-v01/index.json)保留X98断连、未知server exit和缺少确定core／函数栈的边界；[标题断屏](../../native-v0162-display-loss-ab-v01/index.json)与[各120秒晚期A/B](../../native-v0162-late-state-ab-v01/index.json)均只复现native1，原SIGSEGV未定因。新coupled监督的成功不改写该失败。

[四槽JSON诊断](../../source-auto-json-diag-v0162-v01/index.json)及[root语义复核](../../source-auto-json-diag-v0162-v01/root-semantic-review.json)记录实际生产解析边界；[前两关](../../native-v0162-attempt02-completed-cycles-review-v01/index.json)、[第三至第五关](../../native-v0162-attempt02-completed-cycles-review-v02/index.json)的增量复核原本只证明已闭合关卡，完整接受另有最终collector。六张[原始图库](../../outpost-exodus-0.16.2-dev-steam-gallery-v01/index.json)及[root图像复核](../../native-v0162-gallery-root-review-v01.json)不是人类、美术或rights批准。

## 历史证据保持原范围

- [0.16.1冻结cf接受](../../outpost-exodus-0.16.1-dev-release-evidence.json)与[实际收集](../../outpost-exodus-0.16.1-dev-collection-process.json)：游戏3979.349975秒／native3981.0773600769753秒，47个卸货事务和四槽215项通过；[独立codec诊断](../../source-auto-json-diag-v0161-v01/index.json)保留原literal208／4失败，不继承为当前包结果。
- [0.15冻结6bf接受](../../outpost-exodus-0.15.0-dev-release-evidence.json)与[收集](../../outpost-exodus-0.15.0-dev-collection-process.json)：游戏3906.965935秒／native3909.00728546601秒，auto33项通过；[知情AI UI](../../native-ui-v015-v01/index.json)、[root复核](../../native-ui-v015-root-review-v01.json)与[Runtime4启动／截图](../../linux-runtime-compat-v015-v01/index.json)保持有限范围，非human／物理最低配置。
- [receiver源码阶段](benchmarks/v0.15/withdrawal-receiver/index.json)的819项headless／38项source GUI，以及[施工阶段](../../source-ui-v015-construction-v01/index.json)的inspection88／GUI37，均不写成本轮全量重测；其XDG错误、旧反例及布局失败原件保留。[0.15源码文档快照](history/v0.15-source-snapshots/index.json)不修改。
- [0.16原第四关失败](../../rejected/outpost-exodus-0.16.0-dev-delivery-observation-v01/index.json)、[0.16.2 Guide原／修阶段](benchmarks/v0.16.2/guide-transport-availability.json)及原helper／观测失败均保留。

## 尚未关闭的范围

陌生人类可玩性、听感／可读性／无障碍、原生Windows／PowerShell5.1、物理干净机器与目标硬件、最低配置及稳定60FPS、owner权利、真实Steam安装／更新／审核仍需实际验证。默认私有GLX[实际探针](../../linux-private-glx-context-v01/index.json)在移除软件强制环境后仍为llvmpipe，即使direct=true也不是物理GPU通过；headless／dummy或改backend不能替代默认包硬件证据。Windows离线脚本及Linux ParseFile不作为Windows执行通过。

旧[黑盒AI观察](../../blackbox-ai-playtest-v014-v01/index.json)为39次输入、8次截屏、679.594399秒，非human且未完成整关；教程回退说法已被原图否定。当前[内容草稿](../../steam-content-survey-v0162-draft-v01/index.json)与历史台账保留来源，不能代替owner或Valve审核。
