# 开发计划与估算

工作名《逐营突围》／Outpost Exodus，正式名称与分发条款待确认。当前为 **0.16.3-dev源码已验证，Linux／Windows实际导出完成，新包验收待完成**；功能源基线 `4306c2431faf225f742f142836959fe4992a7900`。镜头／读档选择修复的[源码阶段记录](benchmarks/v0.16.3/source-stage.json)不构成新包整关、小时或性能接受。最新已接受的精确Linux包仍是0.16.2冻结AAAE，见[接受记录](../../outpost-exodus-0.16.2-dev-release-evidence.json)。`steam_ready=false`，`performance_acceptance=not_assessed`。

## 当前玩法与本轮改进

保持单人、斜俯视2D卡通、三场独立战役。前期小队清路，后期通过道路、本地库存／能源、生产队列、运输与战术暂停协调多个营地，向前建设、向后撤守。仍为23个主要可重绑按键，不新增模拟规则、运输规则或保存字段。

本轮镜头按logical viewport／zoom约束普通移动，显式定位在减少图外区域的同时避开HUD；旧存档视角保留至新操作或真实resize。另将点击／框选／同类选择、Tab、编组与初始选择统一为整数UI ID，修复读档后float ID与WorldView整数membership失配。单位模型和命令不变；旧0.16.2 ZIP仍含该已知选择显示缺口，没有被原地修包。

实际headless479／0、既有实绘GUI552／0、新镜头GUI248／0已完成，见[root源码复核](../../source-camera-selection-root-review-v01.json)。这些是隔离source Main/HUD与引擎事件检查，非导出包、OS XTest、陌生真人、听感或物理性能证据。首轮GUI失败及资源残留、verbose A/B未复现均保留，后续测试补足scene retirement真实120ms等待，未减少断言。先前[Guide修复584／67](benchmarks/v0.16.2/guide-transport-availability.json)仍保持其独立阶段范围。

此前0.15受控后期AI观察建成接收营，但未保住指挥车。它支持继续观察经济管理与关键单位保护的注意力竞争，尚不是确认bug或人类节奏结论。主车入口与镜头改善可发现性，不替玩家下运输或撤退命令。已弃营卡片占用空间、单位密集时的辨认仍列为操作观察，不凭截图直接立项。

## 规模与下一步

[当前代码清单](benchmarks/v0.16.3/code-size.json)：18份玩法脚本8,981物理行；含诊断／测试／工具共83份自有代码27,190物理行、24,815非空行。沿用0.16.2的81文件分组，仅新增两个repo测试；含注释空行，排除引擎／第三方、素材、场景、UID、缓存及work/probes。代码量不表示完成度。

1. 0.16.3已冻结于561313a并完成实际export；下一步完成新payload smoke、普通／战略各3600帧+120预热、三ZIP／严格unpack及prepare。新包再执行七场C/D/R/C/D/R/C、6次公开重启、同Main及两个独立真实墙钟各≥3600秒；原timeout、真实费用／库存／交付／到场／磁盘及257桶逐场和全局帧守恒门槛不变。不能借AAAE接受、source GUI或prepare宣布新包整关通过。
2. 安排陌生人类独立上手，观察前期微操到后期多营调度、指挥车保护、困惑和停止原因；补听感、可读性与无障碍。受控AI观察及root看图不代替真人反馈。
3. 在明确目标硬件上核新包真实路线帧间隔、原生Windows及干净机器。默认私有GLX[实际探针](../../linux-private-glx-context-v01/index.json)仍是llvmpipe；软件显示、Runtime启动或VM功能验证不能代表硬件60FPS、最低配置或原生Windows通过。
4. 审阅素材／音频／名称／权利与商店内容，保留旧台账pins；真实Steam项目、Depot、安装／更新／overlay、上传及审核仍待实际完成。既有[内容草稿](../../steam-content-survey-v0162-draft-v01/index.json)、[试玩kit](../../playtest-kit-v0162/first-playtest.txt)和[离线staging](../../steampipe-v0162-staging-v01/index.json)没有owner、Windows或Steam审批结论。

0.16.2原AAAE第二次独立长测已实际接受：同Main七场三图，游戏4016.244577秒／native4018.0584507070016秒，215项四槽source与collector实际0。首轮native -11及[71份原件](../../rejected/outpost-exodus-0.16.2-dev-native-x11-disconnect-v01/index.json)仍失败、根因未定；后次成功与显式断屏对照不改写它。[0.16.1冻结cf](../../outpost-exodus-0.16.1-dev-release-evidence.json)、[0.15冻结6bf](../../outpost-exodus-0.15.0-dev-release-evidence.json)的接受仅归各自原包，0.16第四关失败亦保留。详见[当前检查点](current-checkpoint.md)。

## 从零规划参考

以下假设1位熟悉游戏开发的全职开发者加AI辅助，包含必要验证工具，是从阶段起点的参考，不是当前剩余工期或代码承诺。

| 阶段 | 自有代码 | 参考周期 |
| --- | --- | --- |
| 推进与撤守灰盒 | 3,000–8,000行 | 3–6周 |
| 完整单关Demo | 12,000–30,000行 | 3–6个月 |
| 3–5关打磨首发 | 40,000–90,000行 | 12–24个月 |

地图增加设计、美术、平衡和验证工作，代码量不随关数线性增加。代码／配置／场景／测试入Git；缓存、构建、玩家存档不入库，大美术源可用LFS。历史统计、原始接受与失败记录不随新版本文档更新改写。
