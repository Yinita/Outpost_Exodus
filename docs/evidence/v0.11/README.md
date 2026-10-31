# 0.11 预导出源码候选证据边界

本目录保留两项最小源码修复的文字证据：Guide 仅在缺少且能支付设施时求建议落点；FrameSampler 在开始新局时替换 `_cycle_previous` 引用，避免清空与全局端点共用的 Dictionary。最终 `candidate.json` 等版本、测试、素材清单和文档冻结后生成。新 0.11 原生导出、完整路线、同 Main 七轮一小时、完整全局帧表及实际 FPS 仍待验证，不能套用旧包。没有新美术、音频或字体资源；已有 AI 来源缺项和分发权利待确认状态保持。

`query-baseline-v2.json`／`query-candidate-v2.json`、执行前 setup、实际 probe 文本、进程退出记录和 Root 的 paired comparison 均按原字节保留。六个实际保存态各运行八次同步 Guide 查询；完整保存状态／RNG 与完整 Guide 输出保持相同，并通过未包裹的同源 oracle 排除子类观察器改变提示的影响。计时使用 `Time.get_ticks_usec`，是包含观察器开销的同步单调墙钟微秒，不是进程 CPU 时间或渲染 FPS；第一次冷查询保留，状态序列化不在计时内。连通分量 inclusive 耗时包含在 Guide 总耗时里，不能相加。

真实 step 6 保存态的均值为 66.053125→8.651375ms，强制查询／连通分量重建由每次 26→3；Canyon、Delta、Ridge 前营基础设施态分别为 33.21425→8.5855、30.392625→5.677875、29.655875→5.526375ms。已开工出口和中营撤收是绕过该路径的负对照，分别为 2.866875→2.91775 和 0.04975→0.054ms，未显示改善。六份原始 fixture JSON 与 step 6 的原始捕获来源记录也保留；分类依据实际建筑／驻点状态与观察到的调用路径，不只看提示步骤。源码文件名和原始字段中的 cpu 用语不改变墙钟观测的范围，更不能据此宣布整关 FPS 提升。

采样器回归使用同一份 137 检查的新增 callback 测试：旧采样器实际退出 1、四项失败；新采样器实际退出 0、零失败。日志、进程记录、执行前后采样器文本和实际测试文本原样保留。测试直接调用真实 `_on_frame_post_draw` 路径并跨七次局部重置，验证端点／间隔／跨局保留；它是 headless callback 算术和引用生命周期回归，不是另一次实际原生渲染、一小时或性能验证。`sampler-preedit-source-hashes.json` 是编辑前代码快照；旧采样器的实际失败基线也使用新 137 检查测试，不能误写成旧 107 检查。

Root 的 `guide-functional-processes.json` 保留完整 Guide 211/0 和任务 Guide 137/0 的实际终端退出 0、命令、工具身份、日志及源码摘要。完整 Guide 的受控源码推进到胜利约 1590 模拟秒；这是源码正确性回归，不是原生窗口、真实玩家、一小时或 FPS 证据。最终 0.11 headless 编辑器导入原始日志和 Root 实际退出 0（19c531）记录也单独保留，仅证明源码导入。任何另行准备但未运行的 Simulation CPU 探针不列入通过项；本轮修复没有调整 AI、单位数量、模拟步长、路线命令或原验收规则。

`historical-v010-*` 保留旧 `b3f0033a8df1c51d2d43f625133e87c227c4c5eb` 的严格 verifier、监督器 start／wait 结果、真实 PID 观察、七份独立单局 checker JSON，以及外部拒绝归档 index／scope 和失败 collector／checker 原字节。原生路线／时钟／存读盘／七轮一小时组件成功，native 与 launcher 均退出 0；监督器自己的退出状态仍未独立观察，不能从子进程退出推断。七场帧数学分别可核对且都为 `not_assessed`。

旧 0.10 完整全局表仍被拒绝：endpoint 173271 本应产生 173270 个间隔，实际 all.count173264，缺六个跨局间隔；缺失 3318196μs 与六次边界端点差之和精确一致。引用别名导致 `begin_cycle.clear()` 清掉全局前端点。原全局表未修补，未补帧或重构直方图；完整 release collector 实际退出 1，没有成功发布证据或图库输出。外部完整拒绝基线位于 `outputs/rejected/outpost-exodus-0.10.0-dev-global-frame-baseline/`，本目录用原 index／scope 和摘要绑定其原始文件。历史组件成功和单局 checker 结果不等于完整归档已接受，也不等于新的 0.11 载荷证明。最后完整接受的旧候选身份由项目发布门槛文档单独保留。

本目录只有文本／JSON／日志／`.gd.txt` 副本，无 PNG 或 `.import`；探针和历史源码文本不计自有代码行数。最终清单将玩法、打包诊断、GDScript 测试／基准、构建生成工具、其他辅助及 Python 测试分开，并独立记录 UID。Windows 原生执行、干净机器、陌生玩家操作、人工听感／无障碍、最终权利和实际 Steam 商店／内容调查／仓库审核尚未完成；`steam_ready=false`，性能为 `not_assessed`。
