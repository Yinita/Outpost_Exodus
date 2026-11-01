# 当前开发检查点

## 当前0.16.4-dev：营地卡UI源码候选，尚未导出

功能已合入 `6c0ca0ce02e9e1a8eec6c8e38fd3a63f5d9045e1`，只改HUD和新增repo测试／UID；Main、Sim、CampReadout、命令、营地顺序与页容量及存档schema不变。未选中且无实际末班运输的弃营使用52px卡，其他卡91px；输入保留区跟随实际卡片／间隙，弃营实时只读状态保留末班运输和遗留库存。见[本轮源码阶段](benchmarks/v0.16.4/source-stage.json)。

最终HUD `f7a8f58c…`／test `5e63d350…`只有受影响headless **47／0**。此前HUD `75df0b6…`实际通过46／0、readout189／0、HUDcache286／0、camera305／0及source GUI26／0；最终差别仅两行tooltip，这些较广检查没有在f7上重跑，没有最终大库存hover像素证据。[代码清单](benchmarks/v0.16.4/code-size.json)为18份玩法脚本9,030物理行；84份自有代码27,464物理行／25,085非空行。**0.16.4没有新导出、包验证、整关／小时或collector结果，不能继承0.16.3接受。**

## 最近独立接受精确包：0.16.3-dev／561

0.16.3功能源基线为 `4306c2431faf225f742f142836959fe4992a7900`，Main SHA为 `9920bed445f6d5cb8c5a09aaa7eb2b7501c04ebf36a0d4a8d394e3bc7021a962`。该轮只改变Main的镜头与UI选择行为，其余21个runtime脚本与AAAE逐字一致；83份自有代码清单所列字节与受测工作树匹配，实际执行范围见下文。见[源码阶段记录](benchmarks/v0.16.3/source-stage.json)及[root逐项复核](../../source-camera-selection-root-review-v01.json)。**冻结561的精确Linux包已独立完成整关／小时及最终collector技术接受**，不是继承0.16.2结果；接受仅限声明的私有软件环境，不构成完整UI或物理性能验收。`steam_ready=false`，`performance_acceptance=not_assessed`。

冻结payload源为 `561313a910d7b4f2954260a79b34cd4030c0857a`，tree `0ec913a95502b8345d2493a026eadbc4c0b7ee1c`；尚无0.16.3tag。pipeline三个阶段实际wait均0，私有显示正常退出0且回收；普通／战略各3600帧+120预热及实际save/read有效。三ZIP的879份源码、Linux8／Windows7成员、notice、CRC、metadata及Linux执行位／逐字回读已核对，见[checksums](../../outpost-exodus-0.16.3-dev-checksums.json)与[root解压复核](../../native-v0163-unpack-root-review-v01.json)。这些是llvmpipe软件功能测量，不是物理GPU或稳定60FPS证明。新包[coupled prepare](../../native-v0163-coupled-run-v01/root-prepare-execution-process.json)已通过：root17010／9cf327实际0，native／launcher／server三wait均0，全部PID及99socket／lock回收。七场C/D/R/C/D/R/C与6次公开重启已终局，游戏墙钟3987.523349秒／launcher独立观测native3989.0963843020145秒，三个实际wait均0，见[root终局](../../native-v0163-coupled-run-v01/root-soak-tool-terminal.json)。[全部七场及全局257桶帧账](../../native-v0163-frame-review-v01/index.json)、[普通Canyon1x两代auto](../../native-auto-cycle-v0163-root-review-v02.json)、[215项四槽source读回](../../postterminal-v0163-candidate-v02/source-auto-result.json)及[正式接受记录](../../outpost-exodus-0.16.3-dev-release-evidence.json)及[实际collector过程](../../outpost-exodus-0.16.3-dev-collection-process.json)均实际通过，source engine／工具与collector工具退出0。四槽按既有Godot JSON codec域比较；[本版语义复核](../../source-auto-json-diag-v0163-v01/root-semantic-review.json)保留rawparse76及顶层object顺序边界，不宣称原数字token或解析前IEEE无损。

[0.16.3标准包GUI复核](../../native-controls-v0163-run-v02/root-control-review.json)正常退出0、28图完整解码，10项具体比较通过；[compact实际一例](../../native-controls-v0163-compact-run-v01/root-review.json)通过普通Settings改120%、1152×648切换及7项完整暂停Sim／RNG／UI比较，native／server0。F9的4个`nav_wait`差异经[独立诊断root复核](../../source-f9-codec-diag-v0163-v01/root-review.json)定位于首次JSON解析的1ULP转换，模型阶段无额外变化，完整parsed／derived匹配native-after；原raw严格predicate仍失败，不能宣称raw IEEE无损，也不作为新camera／Sim-load bug。Guide modal内F5 freshness失败、定位返回后保存通过及v01三wait未知／stale cleanup原件保留。净空校准仅支持对应单点，不泛化所有resize。

普通平移、拖拽和缩放现在按真实logical viewport／zoom限位，小地图轴居中；显式定位优先减少图外区域，必要时用有界偏移避开HUD。17px内部guard保持原16px实际canvas净空要求，postdraw复核新布局；手动移动结束定位。旧存档镜头／zoom精确保留，直到新镜头操作或真实视口变化。

同时修复读档后的选择ID表示：旧JSON中的单位ID可为float，点击／框选／同类选择等曾把它直接放入UI数组，与WorldView的整数ID membership失配。现在选择、Tab、编组和初始选择统一使用int，单位模型、订单、资源、RNG及保存schema不变。[原缺口诊断](../../source-camera-id-diagnostic-v01/index.json)证明旧b527与4add均存在此问题；**AAAE旧ZIP未改，仍含该缺口**。

实际源码验证分别为headless **479／0**（loaded selection61、camera305、运输状态113）、既有四项实绘GUI **552／0**、新增镜头GUI **248／0**，相关引擎、工具与自有显示服务均实际退出0。源码GUI使用引擎派发输入，覆盖1920×1080／100%与1152×648／120%、真实postdraw／resize、严格整数选择及16px净空；不是OS XTest、真人或导出包验收。root查看4张新增关键图，另23张capture完整解码。[首轮6项GUI失败](../../source-camera-viewport-gui-v01/attempt01-results-index.json)、[退出资源残留及verbose A/B未复现](../../source-camera-ui-leak-ab-v01/index.json)均保留；测试随后补足两次scene retirement的120ms真实墙钟等待，未屏蔽资源日志或减少断言。

[0.16.3历史代码统计](benchmarks/v0.16.3/code-size.json)：18份玩法脚本8,981物理行；83份自有代码27,190物理行、24,815非空行。含注释／空行，排除引擎、第三方、素材、场景、UID、缓存与work/probes；代码量不表示完成度。

## 前版已接受精确包：0.16.2-dev／AAAE

冻结source/tag为 `aaae0064413528b6c135f76d308118465e34831d`／`v0.16.2-dev`，tree `32c02312c7cec6268bd590112a8a1ad25b785388`。其导出、原生smoke、普通／战略各3600帧+120预热、三ZIP、严格解压及受控普通Main Guide忙／闲场景均有实际记录。[包阶段记录](benchmarks/v0.16.2/package-stage.json)、[三包checksums](../../outpost-exodus-0.16.2-dev-checksums.json)与[Guide原生复核](../../native-guide-v0162-root-review-v01.json)只属于该精确包，既有tag、ZIP和证据均未随源码修复改变。

第二次独立长测使用同Main完成七场C/D/R/C/D/R/C、6次公开重启；游戏真实墙钟4016.244577秒、launcher观察native生命周期4018.0584507070016秒，三个实际wait均0。七场／全局帧账、严格路线经济、真实费用／库存／交付／到场，以及215项四槽source读回通过。见[接受记录](../../outpost-exodus-0.16.2-dev-release-evidence.json)与[实际收集过程](../../outpost-exodus-0.16.2-dev-collection-process.json)。两个独立时钟各≥3600秒，不是运行两小时，也不证明人类体验、Windows或目标硬件性能。

普通Canyon1x两代auto保留原44／44／180秒门槛，暂停后退出前封存主备原字节，backup保持primary1，见[普通auto复核](../../native-auto-cycle-v0162-root-review-v02.json)。四槽[JSON边界诊断](../../source-auto-json-diag-v0162-v01/index.json)及[root语义复核](../../source-auto-json-diag-v0162-v01/root-semantic-review.json)保留完整结构／entries顺序／RNG与Vector2 float32核对范围，不宣称raw十进制或解析前IEEE位保真。

首次长测仍是失败：root93484→627acf实际1，launcher1、native -11，native实际504.33434769598534秒，C1尚未胜利。X98断连／SIGSEGV合并日志、原server缺wait及工具Unknown均保留；没有足以确定根因的core／函数栈或显示退出信号发送者证据。[71份原失败](../../rejected/outpost-exodus-0.16.2-dev-native-x11-disconnect-v01/index.json)没有被后次成功覆盖。[系统窄审](../../native-v0162-x11-failure-audit-v01/index.json)、[标题断屏A/B](../../native-v0162-display-loss-ab-v01/index.json)与[真实晚期120秒A/B](../../native-v0162-late-state-ab-v01/index.json)只补诊断：两版显式owned display loss均native1，未复现原-11，原SIGSEGV仍未定因。

[六张原生图库](../../outpost-exodus-0.16.2-dev-steam-gallery-v01/index.json)来自同一AAAE包前三场已闭合关卡，未编辑；[root图库复核](../../native-v0162-gallery-root-review-v01.json)记录逐图查看、解码及SHA。它们不是概念图、真人试玩或owner美术／权利／商店审批。

## 剩余发布工作

0.16.4仍须用新冻结payload独立完成标准export／smoke／双3600+120 render／package／unpack、prepare、七场／6次公开重启／双独立≥3600秒、真实费用库存到场与磁盘／257桶帧账、普通auto及source collector，不能借原包结果。先补本候选最终tooltip字节的实际像素／操作范围，再继续陌生真人、原生Windows、目标硬件整关性能和Steam owner实际测试。[验证计划](validation-plan.md)及[发布门槛](release-gates.md)保留原规则。

默认私有GLX链路已[实际清除软件强制变量后探测](../../linux-private-glx-context-v01/index.json)，仍为llvmpipe；`GLX_IS_DIRECT=1`也不是硬件证明，不能称稳定60FPS或最低配置通过。另有[owned NVIDIA菜单呈现诊断v03](../../native-gpu-v0163-menu-v03/index.json)实际0，advertised WMclose在provider预建atom条件下通过；仅菜单呈现／正常退出，不是整关硬件、FPS或物理scanout验收。陌生人类的前期微操→后期多营调度、主车保护、听感／可读性／无障碍、原生Windows、真实目标硬件、权利与Steam安装／更新／审核仍待完成。[Windows可行性](../../windows-native-environment-feasibility-v01/facts.json)和[VM准备](../../windows-native-vm-preparation-v01/profile.json)没有实际Windows执行结论；[试玩材料](../../playtest-kit-v0162/first-playtest.txt)、[内容调查草稿](../../steam-content-survey-v0162-draft-v01/index.json)与[0.16.3五文件本地staging](../../steampipe-v0163-run-v01/run-index.json)没有预填owner或Valve结果；stage／verify退出0／0、owner-required如期拒绝2，AppID／Depot／entity／account仍UNBOUND、未登录或上传。

本版[本地SteamPipe staging](../../steampipe-v0163-run-v01/run-index.json)已实际完成：归档／源码核对与每平台5文件复制返回0，离线VDF／哈希校验返回0；缺少真实owner值的检查实际返回2并拒绝继续。10件运行与通知文件已准备，AppID／Depot／entity／account仍未知，没有SteamCMD、登录、上传或平台安装测试。

## 历史范围

- [0.16.1冻结cf接受](../../outpost-exodus-0.16.1-dev-release-evidence.json)及[实际收集](../../outpost-exodus-0.16.1-dev-collection-process.json)：七场三图，游戏3979.349975秒／native3981.0773600769753秒，source215／0；[codec诊断](../../source-auto-json-diag-v0161-v01/index.json)保留原literal208／4失败，不能移作新包结果。
- [0.16原第四关超时及111份原件](../../rejected/outpost-exodus-0.16.0-dev-delivery-observation-v01/index.json)保持失败；卸货见证修复没有重写原运行。
- [0.15冻结6bf接受](../../outpost-exodus-0.15.0-dev-release-evidence.json)及[实际收集](../../outpost-exodus-0.15.0-dev-collection-process.json)只归原包；[旧源码文档快照](history/v0.15-source-snapshots/index.json)、历史台账pins和原日志不改。
- 先前[主车运输可用性Guide修复](benchmarks/v0.16.2/guide-transport-availability.json)的584项headless／67项source GUI、旧cf204／43反例和原生受控fixture范围保留，不合并为本轮全量重测。
