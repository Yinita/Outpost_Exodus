# 逐营突围 · Outpost Exodus

单人、2D 卡通废土战役式生存策略。向前清理尸群、铺路建营、生产供能；向后搬走人员物资、封关断后，最终完成出口工程并突围。

当前开发源码为 **0.16.4-dev UI源码候选**，已合入营地卡优先级整理：没有末班运输的未选中弃营压为52px，选中、运作、撤收和仍有运输的营地保持91px；只占用实际可见卡片和间隙，弃营状态鲜读，遗留库存可在tooltip查看。Main、Sim、命令与存档schema不变。[源码阶段记录](docs/benchmarks/v0.16.4/source-stage.json)区分最终f7的47／0与此前75df的readout189／HUD286／camera305及26项source GUI；后者没有在最终两行tooltip字节上重跑，也没有最终大库存hover像素证据。**0.16.4已从94043e81冻结源实际导出Linux／Windows候选，Linux smoke／渲染／打包验证已启动，完整新包接受仍待完成。** 见[实际导出记录](../outpost-exodus-0.16.4-dev-export-stage.json)。

最近独立技术接受的精确Linux包为 **0.16.3-dev／冻结561313a**：同Main七场三图、6次公开重启，游戏3987.523349秒／native3989.0963843020145秒，native／launcher／server均正常退出0；普通两代auto、逐关及全局257桶帧账、215项四槽source和collector实际通过。见[正式接受记录](../outpost-exodus-0.16.3-dev-release-evidence.json)与[实际收集过程](../outpost-exodus-0.16.3-dev-collection-process.json)。范围仅该原包的Linux私有软件normalMain技术检查，`steam_ready=false`、`performance_acceptance=not_assessed`；不包含整关硬件、Windows、真人或真实Steam验收。

此前通过技术验收的Linux包 **0.16.2-dev**，本地tag/source `aaae0064…`：同Main七场三图，游戏4016.244577秒／native4018.0584507070016秒，48次真实卸货、逐场与全局帧账及215项四槽读回通过，游戏／启动器／私有显示均正常退出0。[包接受记录](../outpost-exodus-0.16.2-dev-release-evidence.json)及[收集过程](../outpost-exodus-0.16.2-dev-collection-process.json)只属于该原包。上述ID反馈缺口也存在于该版本；原ZIP未修改，0.16.3修复不能反向算入旧包。首次SIGSEGV与显示丢失原因仍未定，失败原件保留。`steam_ready=false`，Windows原生、目标硬件及真人体验仍待验证。

已接受的0.16.1精确Linux包冻结于 `cf678b72…`，同Main七场三图完成，游戏墙钟3979.349975秒，启动器独立观测native3981.0773600769753秒；实际退出均0，七场帧账及四份存档读回复核通过。验收仅属于该原包，见[接受记录](../outpost-exodus-0.16.1-dev-release-evidence.json)和[收集过程](../outpost-exodus-0.16.1-dev-collection-process.json)。`steam_ready=false`、`performance_acceptance=not_assessed`；[当前检查点](docs/current-checkpoint.md)记录剩余范围。

## 运行

使用 **Godot 4.7.2 stable** 打开 `project.godot`，按 F5 运行。Linux 安装引擎后也可执行：

```bash
./run.sh
```

引擎不在 PATH 时：

```bash
GODOT_BIN=/absolute/path/to/godot ./run.sh
```

在菜单选择一场独立战役，展开行动引导开始。游戏运行不依赖 Python；构建与开发验证工具才使用 Python。

## 三场独立战役

| 战役 | 主要决策 |
| --- | --- |
| 裂谷突围 | 高地与两道关口，先建材或先燃料 |
| 双桥湿地 | 南岸废料、北岸原油，两桥影响转运 |
| 山脊换防 | 北侧高脊与南谷绕行，决定车队换防时机 |

每关从自己的队伍和库存开始。先用小队清路、夺取补给，再连接道路、建设驻点和设施；前方营地需要实际接收物资才能运作。后方追兵持续推进，撤营由运输车真实装卸，紧急弃营会留下未装车物资。出口必须付费施工、持续供能，指挥车与至少4名幸存者实际抵达后才能获胜。

高地崖壁阻挡通行，坡道与桥梁连接各层。高地提供射程，实体山体和完整建筑遮挡射击；近战不能隔崖攻击。道路、工地、本地库存、训练队列、运输和电力均读取同一份真实战役状态。

## 默认操作

| 操作 | 方式 |
| --- | --- |
| 选择、多选 | 左键、拖框、Shift 追加 |
| 移动、交战 | 右键；X 后左键攻击移动 |
| 镜头 | WASD、中键拖动、滚轮缩放 |
| 小地图 | 左键定位、右键向目标下令 |
| 建设、指挥、生产、训练 | B、V、P、N |
| 编队 | Ctrl+1–4 保存；1–4 选择；Tab 切队 |
| 驻点定位、切换运作驻点 | Home、Shift+Home |
| 选择并定位指挥车 | 点击目标面板的“指挥车 … 选择”，保持现有任务 |
| 战术暂停 | Space；暂停时仍可下令 |
| 快速保存、读取 | F5、F9 |
| 补给线、范围 | L、O |
| 速度、帮助、菜单 | + / -、H、Esc |

仍有23个主要按键可重绑，界面与帮助随之更新；指挥车入口使用鼠标，没有新增快捷键。设置提供音量、全屏、分辨率与界面缩放。切出窗口时战役暂停，返回后明确继续。

手动、自动存档相互独立，各有上一份有效备份。坏存档在替换当前战役前验证；保存失败会保留当前局面并提供重试。存档与设置保存在本机 Godot 用户目录，不进入 Git。

## 当前源码与已接受包

0.16.3阶段运行时代码只改Main，另外21个runtime脚本与已接受aaae源码逐字相同。相机操作、精确旧视角读回、编组／Tab／单位选择已分别验证完整Sim/RNG保持；四个明确的公开移动命令则与独立Sim执行同一命令的完整状态比较。17逻辑像素的内部净空保护原有16像素实际canvas判定，没有用容差隐藏边界失败。root已查看[四张受控源码GUI原图](../source-camera-viewport-gui-v02/results-index.json)，这些历史存档场景不作当前导出包或普通整关证明。

0.16.3原包[标准控件复核](../native-controls-v0163-run-v02/root-control-review.json)有10项比较通过、28图完整解码；[compact一例](../native-controls-v0163-compact-run-v01/root-review.json)通过普通Settings切120%、1152×648切换及7项完整暂停Sim／RNG／UI比较，native／server正常退出0。[F9独立诊断复核](../source-f9-codec-diag-v0163-v01/root-review.json)把4个`nav_wait`差异定位到首次JSON解析的1ULP转换，模型阶段没有额外改变、完整parsed／derived匹配native-after；原raw严格predicate仍失败，不宣称raw IEEE无损，也不作为新camera／Sim-load bug。Guide modal内F5 freshness失败与定位返回后保存通过均保留；单点净空不外推其他布局。

以下Guide与打包记录属于各自原版本；0.16.3 Main阶段范围以[0.16.3源码复核](../source-camera-selection-root-review-v01.json)为准。

当前引导只读取真实主车及撤收记录，区分返程取货、装车和末班运输，避免要求玩家执行必被拒绝的下一段撤营。记录无效时明确提示检查，主车空闲后恢复原操作提示。Sim/Main/HUD/SaveStore/readout字节保持基点一致，没有新增按键或存档字段。

同一最终用例：原cf Guide204项／43失败，修复后204／0；连同camp-action、完整默认Guide路线和三图付费开局共584／0。source GUI67／0覆盖默认1440×810、小窗口1152×648及120%UI、定位／展开、完整Sim/RNG和现有运输订单不变，实际正常退出。[修复索引](docs/benchmarks/v0.16.2/guide-transport-availability.json)保留源码阶段原件。

新包另用普通Main菜单载入两份明确声明的平地／高库存受控存档，通过真实OS输入展开、定位和F5保存。相同暂停原生实例的Guide操作前后，完整Sim/RNG与选营、选人、编组、速度和覆盖层均不变，镜头匹配真实主车／A营；空闲场景另从界面成功下达A到B撤营。两次native与工具均正常退出0，20张原始PNG完整解码，root查看关键图像。[原生检查](../native-guide-v0162-root-review-v01.json)不代表默认开局整关、小时长测或真人体验。

0.16.1的[实机图库](../outpost-exodus-0.16.1-dev-steam-gallery/index.json)、[普通自动存档观察](../native-auto-cycle-v0161-root-review-v02.json)及[215项四槽读回](../postterminal-v0161-candidate-v02/source-auto-result.json)均绑定原精确包。存档按既有Godot JSON codec规范化比较，独立诊断保留类型／Vector2位模式与原始十进制边界；原208／4字面对比失败不改写，不宣称原数字token或解析前IEEE位保真。[诊断](../source-auto-json-diag-v0161-v01/index.json)。

0.16.2另有[六张原始实机图](../outpost-exodus-0.16.2-dev-steam-gallery-v01/index.json)，来自新attempt02前三场已结束关卡；root已逐张查看、完整解码并核对source／copy哈希。[图库复核](../native-v0162-gallery-root-review-v01.json)只证明当前包图像的来源与内容，不替代美术审阅或真人体验。此前前五场的35次卸货及逐关帧账增量复核保留，完整七场接受另以上述实际终态及收集记录为准。

0.16旧包第四关运输观察超时退出1的[原失败记录](../rejected/outpost-exodus-0.16.0-dev-delivery-observation-v01/index.json)保持失败。0.15冻结6bf的历史接受记录、所有原包及素材台账pins也保持不变，不继承给当前0.16.2。

## 开发与素材

采用 Godot 4 + 带类型的 GDScript，模拟、显示与命令输入分开。玩法、界面、输入、绘制及音频共18个脚本、**9,030物理行**；含测试、诊断和工具共84个自有代码文件、**27,464物理行、25,085非空行**。排除引擎、第三方库、素材、场景、UID、缓存及外部探针，见[逐文件清单](docs/benchmarks/v0.16.4/code-size.json)。代码量不是完成度或包验收。

建筑图集由图像生成工具制作，角色/地形与部分声音采用程序绘制或生成，Noto 字体附带 OFL 通知。具体来源与待确认事项见[素材台账](docs/asset-inventory.json)；旧source pins保留为历史，当前18素材源、22runtime脚本及实际包差异见[0.16.2内容事实草稿](../steam-content-survey-v0162-draft-v01/index.json)。未知生成记录保持未知，权利与正式调查由owner确认；本地准备不等于提交。自有代码与美术的最终分发条款仍待确定。

[既有0.16.2试玩说明](../playtest-kit-v0162/first-playtest.txt)和空白反馈表绑定实际包，尚无真人结果。[0.16.3本地SteamPipe staging](../steampipe-v0163-run-v01/run-index.json)为每平台五个运行／通知文件；stage／verify实际0／0，owner-required模式因真实身份未绑定如期拒绝2。AppID／Depot等仍UNBOUND，没有登录、上传或Steam安装验证。

已建立本地 Git，尚未创建或推送 GitHub 远程仓库。可先用私有仓库开发，代码/场景/关卡/测试纳入 Git，大体积美术源文件使用 Git LFS。`.godot/`、`work/`、构建和本机存档不入库；`docs/.gdignore` 避免把文档截图当游戏资源导入。

开发、验证与打包方式见[开发计划](docs/development-plan.md)及[验证计划](docs/validation-plan.md)。冻结6bf的五份源码候选文档逐字保留在[0.15历史快照](docs/history/v0.15-source-snapshots/index.json)，其中的“待验证”描述导出前阶段；0.14快照与所有原始包证据保持原样。
