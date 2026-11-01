# 发布门槛

当前 **0.16.4-dev营地卡候选已实际导出，Linux新包验证已启动，尚未完整接受**，功能commit `6c0ca0ce…`，HUD `f7a8f58c…`。见[本轮源码阶段](benchmarks/v0.16.4/source-stage.json)；最终只47／0，此前75df的189／286／305及GUI26不写成最终字节已跑。最新独立Linux技术接受是0.16.3冻结561原包，不能继承给0.16.4。`steam_ready=false`，`performance_acceptance=not_assessed`。

| 要求 | 当前证据与下一步 |
| --- | --- |
| 0.16.4营地卡候选 | 最终f7／test5e63 headless47／0；此前75df的46+189+286+305及source GUI26保留原字节范围，最终两行tooltip未做大库存hover像素复核。Main／Sim／规则不变。 |
| 0.16.4标准包流水线 | 已冻结94043e81并实际导出，[export记录](../../outpost-exodus-0.16.4-dev-export-stage.json)；Linux smoke／双zoom各3600+120（原max600）／package已启动，unpack／prepare及实际UI仍待完成，不能借561原包结果。 |
| 0.16.4完整路线与小时 | 尚未运行。同Main七场三图、6次公开重启、双独立墙钟各≥3600秒；原时钟／路线／经济／磁盘／帧账及退出门槛保持。 |
| 最新精确Linux技术接受 | [0.16.3冻结561](../../outpost-exodus-0.16.3-dev-release-evidence.json)／[收集过程](../../outpost-exodus-0.16.3-dev-collection-process.json)：七场胜利，游戏3987.523349秒／native3989.0963843020145秒，三wait0、source215／0、collector0，仅原包私有软件normalMain技术范围。 |
| 原失败与原因 | 首次0.16.2实际失败1／native -11及[71份原件](../../rejected/outpost-exodus-0.16.2-dev-native-x11-disconnect-v01/index.json)保持；[窄审](../../native-v0162-x11-failure-audit-v01/index.json)和[晚期A/B](../../native-v0162-late-state-ab-v01/index.json)未确定原SIGSEGV根因。后次成功不改写原失败。 |
| 存档与实际UI | 561原包auto／215source及compact120%／1152×648一例7比较通过。4个nav_wait严格raw差异已定位首次JSONparse1ULP、非模型额外变化；[root诊断](../../source-f9-codec-diag-v0163-v01/root-review.json)不改原failed predicate或宣称raw IEEE无损。本候选仍需新包验证。 |
| Linux及真实目标硬件 | 私有llvmpipe不是硬件性能；[NVIDIA菜单v03](../../native-gpu-v0163-menu-v03/index.json)在provider条件下实际呈现／正常WMclose，不代表整关FPS／最低配置／物理scanout。目标整关硬件待验。 |
| 原生Windows | 0.16.3有实际导出包但未原生执行；脚本与PS7/Linux ParseFile不是Windows／PowerShell5.1通过。0.16.4已导出并验证PE资源，仍未原生执行。 |
| 人类体验与可达性 | 前期微操→后期多营调度、主车保护、继续／停玩原因、听感／可读性／无障碍待真实检查；source GUI、知情AI和看图不代替陌生人类反馈。 |
| 权利与真实Steam流程 | [0.16.3本地staging](../../steampipe-v0163-run-v01/run-index.json)仅stage／verify0／0、owner-required如期拒绝2；AppID／Depot／entity／account仍UNBOUND，无SteamCMD登录／上传／安装验证，owner权利及审核待完成。 |

## 新包完整技术门槛保持

1. 七场C/D/R/C/D/R/C全部实际胜利，同一Main／native PID内6次正常title／campaign／new／restart切换；每轮任务身份、argv、EXE／PCK／source、累计tick与最终磁盘proof严格对应。
2. 游戏与launcher分别记录单调真实时间，各自≥3600秒；不拿simulation time、菜单闲置或fixture循环补一小时。普通单关默认900秒、合法60–1800秒；soak默认5400秒，原合法参数范围3600–7200秒不变。标准运行和原阶段timeout／最小窗口不得为失败临时延长，prepare与soak不可合用。
3. 保持正常Main、0.05秒／20Hz、标准UI3x、原actor／AI／rate与规则。真实交付／当地库存／运达／施工／供能与主车+至少4人到场必须成立；退出工程140建材／45燃料／30口粮及6电等原费用／距离／库存检查不变，不注入资源／tick／状态或以新命令绕过停滞。
4. 原257桶逐场与全局frame checker继续核`all=active+excluded`、`active=8 phases之和`、count／sum／hist／endpoint时间守恒、invalid=0、overflow／跨边界与普通保存跨度。正常保存长帧保留，p95／p99只报桶区间；不得补丢帧、放宽checker或自动把FPS测量判为稳定60。
5. 普通Main两代auto保留44／44／180门槛及退出前稳定SHA封存；postterminal生产JSON codec／完整结构／entries顺序／RNG／UI续接必须通过。只有完整真实终局后收集，native／launcher／supervisor／owned显示的实际wait与清理分别留证，未知退出码不写0。

[验证计划](validation-plan.md)与[当前检查点](current-checkpoint.md)区分source、最新接受包及剩余范围。[0.16.1冻结cf](../../outpost-exodus-0.16.1-dev-release-evidence.json)、[0.15冻结6bf](../../outpost-exodus-0.15.0-dev-release-evidence.json)接受与[0.16第四关失败](../../rejected/outpost-exodus-0.16.0-dev-delivery-observation-v01/index.json)均保留原scope，不继承给当前payload。

首发范围仍为单人2D三场战役。Steamworks API本身不是发布必选，[官方说明](https://partner.steamgames.com/doc/sdk/api)；实际发布仍需按真实项目完成[审核](https://partner.steamgames.com/doc/store/review_process)与[发布流程](https://partner.steamgames.com/doc/store/releasing)，离线材料不替代这些结果。
