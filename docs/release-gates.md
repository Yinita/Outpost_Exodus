# 发布门槛

当前 **0.16.3-dev源码已验证、未导出**。功能源基线 `4306c2431faf225f742f142836959fe4992a7900`，Main `9920bed4…`；[源码阶段](benchmarks/v0.16.3/source-stage.json)及[root复核](../../source-camera-selection-root-review-v01.json)绑定实际测试字节，不授予新payload整关／小时／性能接受。最新精确Linux技术接受仍属于0.16.2冻结AAAE，旧tag／ZIP／evidence不变。`steam_ready=false`，`performance_acceptance=not_assessed`。

| 要求 | 当前证据与下一步 |
| --- | --- |
| 0.16.3镜头与读档选择 | headless479／0、既有GUI552／0、新镜头GUI248／0，actual waits均0；16px实际canvas净空、严格整数ID与只读操作的完整Sim／RNG／原运输保持。原GUI失败与资源残留保留。这里只证明source，不代表新导出包。 |
| 0.16.3标准包流水线 | 待新源冻结后独立export、smoke、普通／战略各3600帧+120预热（原max600）、package／严格unpack／prepare及必要实际包UI检查；不能借AAAE结果。 |
| 0.16.3完整路线与小时 | 待同一精确新包、同Main七场三图及6次公开重启；游戏／launcher两个独立真实墙钟各≥3600秒。原时钟／路线／经济／磁盘／帧账与真实退出门槛保持，详见下文。 |
| 最新AAAE精确包 | [0.16.2接受](../../outpost-exodus-0.16.2-dev-release-evidence.json)：游戏4016.244577秒／native4018.0584507070016秒，同Main七场胜利、三个wait0；source215／0及collector实际0。已知loaded-selection float/int UI缺口仍在旧ZIP，当前source修复未原地重包。 |
| 原失败与原因 | 首次0.16.2实际失败1／native -11及[71份原件](../../rejected/outpost-exodus-0.16.2-dev-native-x11-disconnect-v01/index.json)保持；[窄审](../../native-v0162-x11-failure-audit-v01/index.json)和[晚期A/B](../../native-v0162-late-state-ab-v01/index.json)未确定原SIGSEGV根因。后次成功不改写原失败。 |
| 存档／素材／图库 | AAAE的普通auto44／44／180、四槽source215与[三图六张未编辑原生图](../../outpost-exodus-0.16.2-dev-steam-gallery-v01/index.json)保持原包范围；新包仍需对应实际绑定。owner美术／权利／商店确认未完成。 |
| Linux及真实目标硬件 | 既有Runtime4有限启动／截图范围保留；默认私有GLX[实际context／清屏探针](../../linux-private-glx-context-v01/index.json)仍llvmpipe，不能称硬件60FPS或最低配置通过。新包目标硬件／干净机器待实际验证。 |
| 原生Windows | 0.16.2 Windows包及离线bound脚本仍仅属原包准备，PS7/Linux解析不是Windows／PowerShell5.1执行。当前版原生Windows待实际验证。 |
| 人类体验与可达性 | 前期微操→后期多营调度、主车保护、继续／停玩原因、听感／可读性／无障碍待真实检查；source GUI、知情AI和看图不代替陌生人类反馈。 |
| 权利与真实Steam流程 | [内容草稿](../../steam-content-survey-v0162-draft-v01/index.json)、[试玩kit](../../playtest-kit-v0162/first-playtest.txt)及[离线五文件staging](../../steampipe-v0162-staging-v01/index.json)不构成审批。AppID／Depot／entity／account仍UNBOUND；没有SteamCMD登录／上传，owner声明、实际调查、商店／构建审核、安装更新待完成。 |

## 新包完整技术门槛保持

1. 七场C/D/R/C/D/R/C全部实际胜利，同一Main／native PID内6次正常title／campaign／new／restart切换；每轮任务身份、argv、EXE／PCK／source、累计tick与最终磁盘proof严格对应。
2. 游戏与launcher分别记录单调真实时间，各自≥3600秒；不拿simulation time、菜单闲置或fixture循环补一小时。普通单关默认900秒、合法60–1800秒；soak默认5400秒，原合法参数范围3600–7200秒不变。标准运行和原阶段timeout／最小窗口不得为失败临时延长，prepare与soak不可合用。
3. 保持正常Main、0.05秒／20Hz、标准UI3x、原actor／AI／rate与规则。真实交付／当地库存／运达／施工／供能与主车+至少4人到场必须成立；退出工程140建材／45燃料／30口粮及6电等原费用／距离／库存检查不变，不注入资源／tick／状态或以新命令绕过停滞。
4. 原257桶逐场与全局frame checker继续核`all=active+excluded`、`active=8 phases之和`、count／sum／hist／endpoint时间守恒、invalid=0、overflow／跨边界与普通保存跨度。正常保存长帧保留，p95／p99只报桶区间；不得补丢帧、放宽checker或自动把FPS测量判为稳定60。
5. 普通Main两代auto保留44／44／180门槛及退出前稳定SHA封存；postterminal生产JSON codec／完整结构／entries顺序／RNG／UI续接必须通过。只有完整真实终局后收集，native／launcher／supervisor／owned显示的实际wait与清理分别留证，未知退出码不写0。

[验证计划](validation-plan.md)与[当前检查点](current-checkpoint.md)区分source、最新接受包及剩余范围。[0.16.1冻结cf](../../outpost-exodus-0.16.1-dev-release-evidence.json)、[0.15冻结6bf](../../outpost-exodus-0.15.0-dev-release-evidence.json)接受与[0.16第四关失败](../../rejected/outpost-exodus-0.16.0-dev-delivery-observation-v01/index.json)均保留原scope，不继承给当前payload。

首发范围仍为单人2D三场战役。Steamworks API本身不是发布必选，[官方说明](https://partner.steamgames.com/doc/sdk/api)；实际发布仍需按真实项目完成[审核](https://partner.steamgames.com/doc/store/review_process)与[发布流程](https://partner.steamgames.com/doc/store/releasing)，离线材料不替代这些结果。
