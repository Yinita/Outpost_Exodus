# 发布门槛

目标仍是高度可玩的完整游戏并达到Steam发布标准。**当前0.16.0-dev仅为源码候选**：新增主车状态/选择功能有source113/0和GUI64/0，既有16/0与88/0回归通过。**尚无0.16精确包、整关、三图或一小时验收**；`steam_ready=false`、`performance_acceptance=not_assessed`。

| 要求 | 当前证据与边界 |
| --- | --- |
| 主车状态与选择定位 | 0.16候选纯当前值读取，真实主车身份/健康/失效、选择不改运输订单与Sim/RNG；source113/0、私有source GUI64/0，实际退出0。无新声音、存档字段或按键。 |
| 既有暂停与工地UI | 本轮仅重跑相关headless16/0及88/0；不声称全部旧测试重跑。 |
| 0.16精确包与原生整关 | 尚未导出或验收。提交审查后重新绑定精确包和实际运行，不继承0.15。 |
| 0.15旧包三图与一小时技术长测 | 冻结6bf原包同Main七场，游戏墙钟3906.965935秒，native/launcher/supervisor/auto33/collector实际0；只属于该旧包。 |
| 帧时、最低配置、稳定60FPS | 性能接受未评定。私有软件显示及旧包帧记录不能单独关闭此门槛。 |
| Linux分发兼容 | 0.15旧包有官方Runtime4有限启动/截图实际0；不是0.16、SDK编译、Steam客户端、Deck或干净机器验收。 |
| 原生Windows与干净机器 | 待验。0.15导出/PE/脚本或Linux解析不等于Windows执行，不能作为0.16运行证据。 |
| 陌生玩家与早微操/晚宏观节奏 | 待真人试玩。0.15受控后期AI建成接收营但主车失守，不是撤退通过；当前源码GUI同样不是人类观察。 |
| 人工听感、辨识度与无障碍 | 待人工验收；本轮静音检查无听感结论。 |
| 美术、字体、音频、名称与分发权利 | 来源/通知已记录；历史source pins与台账不改写，最终权利和分发条款待确认。 |
| 商店展示与真实游戏截图 | 旧0.15五张实机图保留原包来源，无0.16实际包图库；未作美术/商店/权利批准或提交。 |
| Steam项目、上传、审核与发行 | 仅有离线准备；AppID/Depot、真实客户端安装/更新/overlay与审核待完成。 |

## 对象与记录边界

本轮源码UI原图/日志见[root归档](../../source-ui-v016-command-evidence-v01/index.json)：v01前置条件错误、v02退出清理警告和v03最终64/0分别保留，不改写旧结果。当前候选仍保留23个主要可重绑按键，不新增模拟、声音或存档规则。

[0.15完整接受记录](../../outpost-exodus-0.15.0-dev-release-evidence.json)与[实际收集退出](../../outpost-exodus-0.15.0-dev-collection-process.json)绑定冻结`6bf0fe78e9d627fb88a4d3216c66a759feba0fb1`及原精确ZIP。游戏墙钟3906.965935秒、launcher进程3909.00728546601秒分别记录；原接受包、统计、历史与素材pins不变。

当前候选代码与旧包不同。未来精确0.16包需重新绑定提交、模板、EXE/PCK/ZIP和fresh隔离原生检查；本轮不提前宣布接受。真人、听感、Windows、最低配置和真实Steam流程各自保留实际环境与结果。

[当前检查点](current-checkpoint.md)集中说明源码与旧包范围；既有[内容调查草稿](../../steam-content-survey-v015-draft-v01/index.json)和[0.15通知绑定](../../steam-content-survey-v015-package-binding-v01.json)仍待owner审阅。官方参考：[Steam审核](https://partner.steamgames.com/doc/store/review_process)、[商店图](https://partner.steamgames.com/doc/store/assets/standard)、[内容调查](https://partner.steamgames.com/doc/gettingstarted/contentsurvey)。
