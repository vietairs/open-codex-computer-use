# 在 MCP 侧引入本地决策模型（Jev 形态的受限选择读出）

## 目标

在不改变 open-computer-use「MCP tool server」身份的前提下，为主 Agent 增加一个本地的、开源权重的决策工具：把 accessibility tree 裁剪成可执行候选表，用一次前向传播在候选集合上做受限选择读出（constrained-choice logit readout），返回操作、目标元素以及完整的选项概率分布。最终形态是 `decide_next_action` 这个只读 MCP tool，主 Agent 仍然自己发起每一个动作。

## 范围

- 包含：`get_app_state` 的精简可操作候选表模式（P0）、本地评测集与 margin 分离度度量（P1）、`llama-server` sidecar 上的读出原型（P2）、`decide_next_action` 只读 MCP tool 与配套的 host-side cascade 提示词（P3）。
- 不包含：`run_goal` 这类服务端自主目标循环（已否决）；`decide_and_act` 有界代执行（P4，延后，需要单独决策与安全评审）；把模型权重打包进 npm 包；修改现有 lock policy 与 peer auth 机制。

## 背景

- 相关文档：`docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`docs/SUPPLY_CHAIN_SECURITY.md`、`docs/RELIABILITY.md`。
- 相关代码路径：`packages/OpenComputerUseKit/Sources/OpenComputerUseKit/`（`AccessibilitySnapshot.swift`、`ToolDefinitions.swift`、`ComputerUseToolDispatcher.swift`、`ComputerUseService.swift`、`MacSessionGuard.swift`）、`apps/OpenComputerUseLinux/`、`apps/OpenComputerUseWindows/`。
- 方案来源：设计提案 artifact（rev 3，私有）<https://claude.ai/artifact/KPS1j3Y2qvXXpnWbQZ941J>，参考 `browser-use/jev-ultrafast`、SemIf（原 openjev.com）、`awlevin/typesafe-computer-use`。
- 已知约束（均已在仓库内核实）：
  - **不存在开源的 Jev 模型。** SemIf 是研究演示，可迁移的是受限选择读出这个技术，不是权重。
  - **选项标签必须是单 token。** Qwen 系 tokenizer 按字符切分数字，`[12]` 不是一个 token，因此使用单字母标签，候选上限约 52 个；而 `AccessibilitySnapshot.swift` 的 `defaultMaxNodeCount = 1200`。**确定性裁剪才是本项目的难点，推理不是。**
  - **只有 HTTP sidecar 能跨平台。** `Package.swift` 仅声明 `.macOS(.v14)`；Linux/Windows 是独立的 Go 二进制（`main.go` 分别内嵌 `runtime.py` AT-SPI 与 `runtime.ps1` UIA bridge），不含 Swift。内嵌 llama.cpp 与 MLX-Swift 都只能覆盖 macOS。
  - 4B Q4 权重约 2.5–3 GB，叠加 KV cache 需要约 16 GB 统一内存；Intel Mac 与纯 CPU 的 Linux/Windows 机器每步耗时以秒计。

## 风险

- 风险：逐步误差累积。单步 84.5% 在十步任务上约为 19%。
- 缓解方式：工具只做建议、不代执行；由主 Agent 承担校验与恢复；P1 的 gate 要求 margin 能区分对错（AUROC ≥ 0.7），否则整条 cascade 前提不成立。
- 风险：裁剪把正确目标裁掉，模型再准也无用。
- 缓解方式：P1 单独度量「正确目标被裁掉」的比例，超过 5% 直接终止项目。
- 风险：屏幕内容是攻击者可控的决策模型输入，网页或邮件可以在不使用自由文本的情况下把选择引向「发送」。
- 缓解方式：goal 字符串只来自 host；候选表只包含元素元数据；任何代执行能力都不在本计划范围内。
- 风险：sidecar 引入 loopback TCP 这一新的同 uid 攻击面与进程生命周期负担。
- 缓解方式：仅绑定 loopback、由 agent 以净化后的环境拉起、每用户确定性端口、模型路径与 SHA-256 固定、默认不自动下载。
- 风险：fork 需要在每次 upstream 同步时承载新子系统。
- 缓解方式：保持无状态、加法式的工具形态；P0 本身就是独立可用、与模型无关的改进。

## 里程碑

1. **P0 — 精简可操作候选表（无 ML）。** 为 `get_app_state` 增加不带截图、只保留可操作角色、去重、focused 元素优先的裁剪模式。Gate：如果仅此一项就拿到大部分 token 与延迟收益，则在此停止，分类器即为不必要的范围。
2. **P1 — 本地评测集。** 用现有 fixture app 加三个真实 app 收集 200 条决策，附带主 Agent 给出的 ground truth，同时记录每步 margin。Gate：4B top-1 ≥ 80% 且 margin AUROC ≥ 0.7。
3. **P2 — 读出原型。** 在 `llama-server` 上验证受限读出：启动时断言标签为单 token，固定所安装版本的概率语义（pre/post-sampling），用 `cache_prompt` 在同一 prefill 上共享多个 head。Gate：M 系列 16 GB 机器上 p50 决策延迟低于 1.5 s。
4. **P3 — `decide_next_action` 只读工具。** 返回完整分布而非仅 argmax；随工具一起提供 host-side cascade 提示词。Gate：遵循建议的 Agent 完成任务所需步数少于忽略建议的 Agent。

## 验证方式

- 命令：`swift test`（Kit 单测，覆盖裁剪与候选表序列化）、Linux/Windows runtime 的 `go test`、现有 smoke suite。
- 手工检查：在三个真实 app 上对比裁剪前后的候选表，确认正确目标未被裁掉；确认 `get_app_state` 默认行为不变。
- 观测检查：记录每步的候选表、概率分布与决策延迟；P0 的 token 与延迟收益需要与基线对照给出数值。

## 进度记录

- [x] P0：实现精简可操作候选表模式（`get_app_state` 的 `compact` 参数，仅 macOS runtime）。经 code review 修正后 `swift test` 233 条通过。
- [x] P0：在真实 app 上测量收益。Chrome 42% / Finder 30% / Mail 12%（纯文本，未含截图）；延迟无差异。详见 `plans/reports/e2e-measurement-260922-0835-compact-actionable-snapshot.md`。
- [ ] P0 Gate：判断是否继续做分类器。当前读数：仅裁剪树文本只拿到 12–42%，未达提案预期量级；真正的大头是省掉截图，而该项尚未在 e2e 中验证（所有 full 响应都没有截图块）。
- [ ] P1：建立 200 条本地评测集并度量 top-1 与 margin AUROC。
- [ ] P2：完成 `llama-server` 读出原型与延迟测量。
- [ ] P3：落地 `decide_next_action` 与 host-side cascade 提示词。

## 决策记录

- 2026-09-22：**open-computer-use 保持 MCP tool server 身份。** 服务端可以建议、可以执行被指派的动作，但不拥有 goal，不跑自己的规划循环。否决 `run_goal`；`decide_and_act` 有界代执行延后为 P4，需要单独决策。理由：主 Agent（Claude Code、Codex）已经拥有 goal、升级与用户批准三件事，在持有 Accessibility 授权的进程里再放一个策略循环是更差的重复；且本仓库是跟随 upstream 的 fork，有状态子系统的承载成本长期存在。
- 2026-09-22：范围推进到 P3，即工具真正落地，但 P0/P1/P2 的 gate 仍然可以提前终止项目。
- 2026-09-22：模型权重采用首次使用时下载并固定 SHA-256 的方式，不打包进 npm 包，且需通过硬件探测。保留本地推理这一核心属性，代价是首次运行较慢。
- 2026-09-22：先落在 vietairs fork，不向 iFurySt upstream 提案。
- 2026-09-22：当前痛点被判断为成本/延迟与可靠性各占一半。这使 P1 的 margin 分离度 gate 成为承重项：如果 margin 无法区分对错，分类器只会让可靠性更糟，届时应停在 P0。
