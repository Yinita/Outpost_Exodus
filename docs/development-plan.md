# 开发计划与估算

工作名《逐营突围》／Outpost Exodus，正式名称与分发条款待确认。当前为 **0.16.4-dev营地卡候选已实际导出，Linux新包验证已启动、尚未完整接受**，功能commit `6c0ca0ce…`。见[本轮阶段记录](benchmarks/v0.16.4/source-stage.json)；最终f7仅47／0，此前75df的readout189／HUD286／camera305与GUI26保留原字节范围，不作最终全量通过。最新独立技术接受是0.16.3冻结561的[精确Linux原包](../../outpost-exodus-0.16.3-dev-release-evidence.json)及[收集过程](../../outpost-exodus-0.16.3-dev-collection-process.json)，不继承给本候选。`steam_ready=false`，`performance_acceptance=not_assessed`。

## 当前玩法与本轮改进

保持单人、斜俯视2D卡通、三场独立战役。前期小队清路，后期通过道路、本地库存／能源、生产队列、运输与战术暂停协调多个营地，向前建设、向后撤守。仍为23个主要可重绑按键，不新增模拟规则、运输规则或保存字段。

0.16.3阶段镜头按logical viewport／zoom约束普通移动，显式定位在减少图外区域的同时避开HUD；旧存档视角保留至新操作或真实resize。另将点击／框选／同类选择、Tab、编组与初始选择统一为整数UI ID，修复读档后float ID与WorldView整数membership失配。单位模型和命令不变；旧0.16.2 ZIP仍含该已知选择显示缺口，没有被原地修包。

0.16.3源码阶段实际headless479／0、既有实绘GUI552／0、新镜头GUI248／0已完成，见[root源码复核](../../source-camera-selection-root-review-v01.json)。这些是隔离source Main/HUD与引擎事件检查，非导出包、OS XTest、陌生真人、听感或物理性能证据。首轮GUI失败及资源残留、verbose A/B未复现均保留，后续测试补足scene retirement真实120ms等待，未减少断言。先前[Guide修复584／67](benchmarks/v0.16.2/guide-transport-availability.json)仍保持其独立阶段范围。

此前0.15受控后期AI观察建成接收营，但未保住指挥车。它支持继续观察经济管理与关键单位保护的注意力竞争，尚不是确认bug或人类节奏结论。主车入口与镜头改善可发现性，不替玩家下运输或撤退命令。本候选只整理弃营卡52／91px布局、实际输入保留区与鲜读状态；仍有末班运输的卡不折叠，选中弃营展开，遗留库存进入tooltip。单位密集时辨认仍需实际操作观察，不扩展模拟规则。

## 规模与下一步

[当前代码清单](benchmarks/v0.16.4/code-size.json)：18份玩法脚本9,030物理行；含诊断／测试／工具共84份自有代码27,464物理行、25,085非空行。沿用0.16.3的83文件分组，新增营地卡repo测试；含注释空行，排除引擎／第三方、素材、场景、UID、缓存及work/probes。代码量不表示完成度。

1. 完成0.16.4最终f7 tooltip的实际像素／操作复核；此前75df的826项headless与26项source GUI不移作最终字节结果。随后新冻结payload独立走export／smoke／普通及战略各3600帧+120预热（max600）／package／严格unpack／prepare，再完成同Main七场C/D/R/C/D/R/C、6次公开重启、两个独立墙钟各≥3600秒及原经济／到场／磁盘／257桶逐关和全局守恒、普通两代auto与四槽source／collector。0.16.3原包已实际完成这些Linux私有软件技术检查；本候选尚未开始包验证。
2. 安排陌生人类独立上手，观察前期微操到后期多营调度、指挥车保护、困惑和停止原因；补听感、可读性与无障碍。受控AI观察及root看图不代替真人反馈。
3. 在明确目标硬件上核新包真实路线帧间隔、原生Windows及干净机器。默认私有GLX[实际探针](../../linux-private-glx-context-v01/index.json)仍是llvmpipe；[owned NVIDIA菜单诊断v03](../../native-gpu-v0163-menu-v03/index.json)虽已实际0并在provider预建atom条件下正常WMclose，仍不是整关硬件或FPS结果；软件显示、Runtime启动或VM功能验证亦不能代表硬件60FPS、最低配置或原生Windows通过。
4. 审阅素材／音频／名称／权利与商店内容，保留旧台账pins；真实Steam项目、Depot、安装／更新／overlay、上传及审核仍待实际完成。既有[内容草稿](../../steam-content-survey-v0162-draft-v01/index.json)、[试玩kit](../../playtest-kit-v0162/first-playtest.txt)和[0.16.3本地staging](../../steampipe-v0163-run-v01/run-index.json)只有本地stage／verify0／0与owner-required拒绝2，没有owner、Windows或Steam审批结论。

0.16.3冻结561原包游戏3987.523349秒／native3989.0963843020145秒，七场／215source／collector及正常退出均实际通过。其[compact一例](../../native-controls-v0163-compact-run-v01/root-review.json)有7项UI比较与实际120%／1152×648切换，不证明所有窗口。F9的4个`nav_wait`变化已[root定位](../../source-f9-codec-diag-v0163-v01/root-review.json)为首次JSON解析1ULP，模型阶段无额外改变；原raw严格predicate仍失败，不归为camera／Sim-load新bug，也不声称raw IEEE无损。

0.16.2原AAAE第二次独立长测已实际接受：同Main七场三图，游戏4016.244577秒／native4018.0584507070016秒，215项四槽source与collector实际0。首轮native -11及[71份原件](../../rejected/outpost-exodus-0.16.2-dev-native-x11-disconnect-v01/index.json)仍失败、根因未定；后次成功与显式断屏对照不改写它。[0.16.1冻结cf](../../outpost-exodus-0.16.1-dev-release-evidence.json)、[0.15冻结6bf](../../outpost-exodus-0.15.0-dev-release-evidence.json)的接受仅归各自原包，0.16第四关失败亦保留。详见[当前检查点](current-checkpoint.md)。

## 从零规划参考

以下假设1位熟悉游戏开发的全职开发者加AI辅助，包含必要验证工具，是从阶段起点的参考，不是当前剩余工期或代码承诺。

| 阶段 | 自有代码 | 参考周期 |
| --- | --- | --- |
| 推进与撤守灰盒 | 3,000–8,000行 | 3–6周 |
| 完整单关Demo | 12,000–30,000行 | 3–6个月 |
| 3–5关打磨首发 | 40,000–90,000行 | 12–24个月 |

地图增加设计、美术、平衡和验证工作，代码量不随关数线性增加。代码／配置／场景／测试入Git；缓存、构建、玩家存档不入库，大美术源可用LFS。历史统计、原始接受与失败记录不随新版本文档更新改写。
