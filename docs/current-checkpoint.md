# 当前开发检查点

## 当前源码：0.16.3-dev，已验证、未导出

当前功能源基线为 `4306c2431faf225f742f142836959fe4992a7900`，Main SHA为 `9920bed445f6d5cb8c5a09aaa7eb2b7501c04ebf36a0d4a8d394e3bc7021a962`。本轮只改变Main的镜头与UI选择行为，其余21个runtime脚本与AAAE逐字一致；83份自有代码清单所列字节与受测工作树匹配，实际执行范围见下文。见[源码阶段记录](benchmarks/v0.16.3/source-stage.json)及[root逐项复核](../../source-camera-selection-root-review-v01.json)。**0.16.3尚无新导出、整关／小时或性能验收**，不能继承0.16.2包的接受结果。`steam_ready=false`，`performance_acceptance=not_assessed`。

普通平移、拖拽和缩放现在按真实logical viewport／zoom限位，小地图轴居中；显式定位优先减少图外区域，必要时用有界偏移避开HUD。17px内部guard保持原16px实际canvas净空要求，postdraw复核新布局；手动移动结束定位。旧存档镜头／zoom精确保留，直到新镜头操作或真实视口变化。

同时修复读档后的选择ID表示：旧JSON中的单位ID可为float，点击／框选／同类选择等曾把它直接放入UI数组，与WorldView的整数ID membership失配。现在选择、Tab、编组和初始选择统一使用int，单位模型、订单、资源、RNG及保存schema不变。[原缺口诊断](../../source-camera-id-diagnostic-v01/index.json)证明旧b527与4add均存在此问题；**AAAE旧ZIP未改，仍含该缺口**。

实际源码验证分别为headless **479／0**（loaded selection61、camera305、运输状态113）、既有四项实绘GUI **552／0**、新增镜头GUI **248／0**，相关引擎、工具与自有显示服务均实际退出0。源码GUI使用引擎派发输入，覆盖1920×1080／100%与1152×648／120%、真实postdraw／resize、严格整数选择及16px净空；不是OS XTest、真人或导出包验收。root查看4张新增关键图，另23张capture完整解码。[首轮6项GUI失败](../../source-camera-viewport-gui-v01/attempt01-results-index.json)、[退出资源残留及verbose A/B未复现](../../source-camera-ui-leak-ab-v01/index.json)均保留；测试随后补足两次scene retirement的120ms真实墙钟等待，未屏蔽资源日志或减少断言。

[代码统计](benchmarks/v0.16.3/code-size.json)：18份玩法脚本8,981物理行；83份自有代码27,190物理行、24,815非空行。含注释／空行，排除引擎、第三方、素材、场景、UID、缓存与work/probes；代码量不表示完成度。

## 最新已接受精确包：0.16.2-dev／AAAE

冻结source/tag为 `aaae0064413528b6c135f76d308118465e34831d`／`v0.16.2-dev`，tree `32c02312c7cec6268bd590112a8a1ad25b785388`。其导出、原生smoke、普通／战略各3600帧+120预热、三ZIP、严格解压及受控普通Main Guide忙／闲场景均有实际记录。[包阶段记录](benchmarks/v0.16.2/package-stage.json)、[三包checksums](../../outpost-exodus-0.16.2-dev-checksums.json)与[Guide原生复核](../../native-guide-v0162-root-review-v01.json)只属于该精确包，既有tag、ZIP和证据均未随源码修复改变。

第二次独立长测使用同Main完成七场C/D/R/C/D/R/C、6次公开重启；游戏真实墙钟4016.244577秒、launcher观察native生命周期4018.0584507070016秒，三个实际wait均0。七场／全局帧账、严格路线经济、真实费用／库存／交付／到场，以及215项四槽source读回通过。见[接受记录](../../outpost-exodus-0.16.2-dev-release-evidence.json)与[实际收集过程](../../outpost-exodus-0.16.2-dev-collection-process.json)。两个独立时钟各≥3600秒，不是运行两小时，也不证明人类体验、Windows或目标硬件性能。

普通Canyon1x两代auto保留原44／44／180秒门槛，暂停后退出前封存主备原字节，backup保持primary1，见[普通auto复核](../../native-auto-cycle-v0162-root-review-v02.json)。四槽[JSON边界诊断](../../source-auto-json-diag-v0162-v01/index.json)及[root语义复核](../../source-auto-json-diag-v0162-v01/root-semantic-review.json)保留完整结构／entries顺序／RNG与Vector2 float32核对范围，不宣称raw十进制或解析前IEEE位保真。

首次长测仍是失败：root93484→627acf实际1，launcher1、native -11，native实际504.33434769598534秒，C1尚未胜利。X98断连／SIGSEGV合并日志、原server缺wait及工具Unknown均保留；没有足以确定根因的core／函数栈或显示退出信号发送者证据。[71份原失败](../../rejected/outpost-exodus-0.16.2-dev-native-x11-disconnect-v01/index.json)没有被后次成功覆盖。[系统窄审](../../native-v0162-x11-failure-audit-v01/index.json)、[标题断屏A/B](../../native-v0162-display-loss-ab-v01/index.json)与[真实晚期120秒A/B](../../native-v0162-late-state-ab-v01/index.json)只补诊断：两版显式owned display loss均native1，未复现原-11，原SIGSEGV仍未定因。

[六张原生图库](../../outpost-exodus-0.16.2-dev-steam-gallery-v01/index.json)来自同一AAAE包前三场已闭合关卡，未编辑；[root图库复核](../../native-v0162-gallery-root-review-v01.json)记录逐图查看、解码及SHA。它们不是概念图、真人试玩或owner美术／权利／商店审批。

## 剩余发布工作

0.16.3须先冻结新源，再以新目录完成标准export→smoke→双视角render→package／严格unpack／prepare及新包必要UI检查，随后保持同Main七场、6次公开重启、双独立≥3600秒、原路线超时／经济／到场／磁盘与257桶逐场及全局帧守恒门槛。[验证计划](validation-plan.md)和[发布门槛](release-gates.md)列明范围；source阶段通过不能代替新payload的实际接受。

默认私有GLX链路已[实际清除软件强制变量后探测](../../linux-private-glx-context-v01/index.json)，仍为llvmpipe；`GLX_IS_DIRECT=1`也不是硬件证明，不能称稳定60FPS或最低配置通过。陌生人类的前期微操→后期多营调度、主车保护、听感／可读性／无障碍、原生Windows、真实目标硬件、权利与Steam安装／更新／审核仍待完成。[Windows可行性](../../windows-native-environment-feasibility-v01/facts.json)和[VM准备](../../windows-native-vm-preparation-v01/profile.json)没有实际Windows执行结论；[试玩材料](../../playtest-kit-v0162/first-playtest.txt)、[内容调查草稿](../../steam-content-survey-v0162-draft-v01/index.json)与[五文件SteamPipe staging](../../steampipe-v0162-staging-v01/index.json)没有预填owner或Valve结果，AppID／Depot／entity／account仍UNBOUND、未登录或上传。

## 历史范围

- [0.16.1冻结cf接受](../../outpost-exodus-0.16.1-dev-release-evidence.json)及[实际收集](../../outpost-exodus-0.16.1-dev-collection-process.json)：七场三图，游戏3979.349975秒／native3981.0773600769753秒，source215／0；[codec诊断](../../source-auto-json-diag-v0161-v01/index.json)保留原literal208／4失败，不能移作新包结果。
- [0.16原第四关超时及111份原件](../../rejected/outpost-exodus-0.16.0-dev-delivery-observation-v01/index.json)保持失败；卸货见证修复没有重写原运行。
- [0.15冻结6bf接受](../../outpost-exodus-0.15.0-dev-release-evidence.json)及[实际收集](../../outpost-exodus-0.15.0-dev-collection-process.json)只归原包；[旧源码文档快照](history/v0.15-source-snapshots/index.json)、历史台账pins和原日志不改。
- 先前[主车运输可用性Guide修复](benchmarks/v0.16.2/guide-transport-availability.json)的584项headless／67项source GUI、旧cf204／43反例和原生受控fixture范围保留，不合并为本轮全量重测。
