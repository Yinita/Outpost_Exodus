# 发布门槛

目标仍是高度可玩的完整游戏并达到Steam发布标准。**0.15.0-dev精确Linux包技术验收已接受**，冻结source `6bf0fe78…` / 本地tag `v0.15.0-dev`；`steam_ready=false`、`performance_acceptance=not_assessed`。本次文档更新不更改版本、运行代码或已接受包。

| 要求 | 当前证据与边界 |
| --- | --- |
| 真实推进、付费建设/出口、供能、追兵、撤营、封关 | 本版实际Linux包同Main完成七场三图，游戏报告3906.965935秒，严格技术验收通过。 |
| 任务身份、载货盘上存读档、主备与失败保护 | 逐关完整状态/时钟/经济/盘上续接及独立auto33/0通过，native/launcher/supervisor/collector有真实退出0。 |
| 三图与一小时技术长测 | Canyon/Delta/Ridge/Canyon/Delta/Ridge/Canyon七场，游戏与launcher两种真实墙钟均≥3600；逐关及全局帧守恒通过。不是继承0.14。 |
| 接收营与施工UI | receiver阶段819/38和本轮inspection88/0、source GUI37/0分别记录；精确包另有普通Canyon及受控receiver两场知情AI观察，无新增目标阻塞。 |
| 帧时、最低配置、稳定60FPS | 性能接受未评定。保留真实路线阶段帧与独立控制场景原始间隔；算术/均值/完成长测不能单独关闭此门槛。 |
| Linux分发兼容 | 本版官方Runtime4完成实际OS身份/启动/截图，退出0、payload不变；无Steam客户端、Deck、SDK编译或物理干净机器结论。 |
| 原生Windows与干净机器 | 待验。已导出并核对ZIP、图标/版本及PE结构；离线检查脚本、Linux解析或容器不作为Windows运行证据。 |
| 陌生玩家与早微操/晚宏观节奏 | 待人类试玩。旧14黑盒AI与新15知情AI观察范围分开，不等于human或全面可玩性接受。 |
| 人工听感、辨识度与无障碍 | 最终人工验收待完成，截图操作没有听音结论。 |
| 美术、字体、音频、名称与分发权利 | 来源/通知有记录；历史source pins不改写，当前内容调查差异外部保留；最终权利与自有分发条款待确认。 |
| 商店展示与真实游戏截图 | 本版五张未编辑1920×1080原生图已全部查看；未作美术/商店/rights审批，未提交。 |
| Steam项目、上传、审核与发行 | 只有离线准备材料；AppID/Depot、真实客户端安装/更新/overlay及审核仍待实际完成。 |

## 已接受对象与后续变更

[完整接受记录](../../outpost-exodus-0.15.0-dev-release-evidence.json)与[实际收集退出](../../outpost-exodus-0.15.0-dev-collection-process.json)绑定冻结6bf及精确ZIP。游戏报告墙钟3906.965935秒；launcher观察native进程3909.00728546601秒，两种口径不混用。当前文档提交不是新的游戏包，也不自动扩展既有验收。

以后运行代码或payload改变，需要重新绑定提交、模板、EXE/PCK和ZIP，并使用fresh隔离完成必要原生验证。保留正常Main、0.05模拟步、真实费用/部队/运输与原严格checker；失败不补帧、不改成功报告、不放宽门槛。

## 人工与平台验收

试玩需记录首次理解、真实操作、预期/结果、困惑与停止原因，特别观察拥堵、供能、撤收和多处调度。AI观察、自动路线和受控点击分别标注；Windows、干净机器、最低配置、人工听音与无障碍各自记录实际环境。

[当前检查点](current-checkpoint.md)集中链接新包、UI、Runtime和源码阶段原件。[内容调查草稿](../../steam-content-survey-v015-draft-v01/index.json)及[包通知绑定](../../steam-content-survey-v015-package-binding-v01.json)仍待owner审阅；教程回退读图错误不列为确认bug。官方参考：[Steam审核](https://partner.steamgames.com/doc/store/review_process)、[商店图](https://partner.steamgames.com/doc/store/assets/standard)、[内容调查](https://partner.steamgames.com/doc/gettingstarted/contentsurvey)。冻结前原文见[0.15源码快照](history/v0.15-source-snapshots/index.json)。
