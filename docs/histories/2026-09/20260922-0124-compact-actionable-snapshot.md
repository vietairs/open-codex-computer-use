## [2026-09-22 01:24] | Task: 为 get_app_state 增加 compact 可操作视图

### 🤖 Execution Context
* **Agent ID**: `claude-code (cortex pipeline, --auto --counsel)`
* **Base Model**: `claude-opus-5`
* **Runtime**: `Claude Code, macOS 27.2`

### 📥 User Query
> 调研用 openjev / browser-use jev-ultrafast 那套 classifier 思路改造 open-computer-use，并在批准后执行到可合并状态。经过提案评审，第一阶段（P0）确定为「零 ML 的精简可操作候选表」。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`

**Key Actions:**
- **新增 compact 视图**：`SnapshotTextStyle` 增加 `compactActionable`，只渲染暴露了 accessibility action 的元素，拉平缩进，focused 元素优先。
- **索引稳定性**：新增 `treeLineOffsets`（元素 index → 其在 `treeLines` 中的行位置），compact 视图直接复用完整树已经渲染好的那一行，因此 `element_index` 与完整树完全一致，action tools 无需任何改动。
- **省略截图**：`snapshotResult` 在 compact 模式下不附加 PNG，否则省 token 的目的会被截图抵消。
- **工具契约**：`get_app_state` 增加可选 `compact` 布尔参数，dispatcher 增加容错的 `optionalBool`（接受 bool / "true" / "false" / 1 / 0）。
- **测试**：新增 5 条单测覆盖过滤、索引保持、缩进拉平、无可操作元素的显式提示、以及完整树行为未被改变。

### 🧠 Design Intent (Why)
这是本地决策模型提案的 P0，也是它的前置条件：把 1200 节点的 AX tree 裁剪到可操作候选，是后续受限选择读出的难点所在。把它单独做成一个不依赖任何模型的特性，可以先拿到 token 与延迟收益，并在不引入 sidecar、权重下载、硬件门槛和信任边界变化的前提下验证裁剪本身是否会丢掉正确目标。

刻意**不做**同名行去重：列表里两个「删除」按钮是不同的目标，丢掉正确目标比多打印一行近似重复严重得多。

### 🔁 Code review 后的修正

opus 级 code review 发现四处问题，均已修复并补测（测试总数 228 → 233）：

- **focused 元素查找不确定**：一个 `AXUIElement` 可能同时对应真实行与为它生成的 synthetic text 行，而 `Dictionary.values` 无序，因此同一个 UI 在不同运行下可能匹配到没有 action、不会进入 compact 视图的 synthetic 行，导致 focused 元素既不置顶也不带标记。改为跳过 synthetic 记录并取最小匹配 index。
- **可操作判定过窄**：`set_value` 只要求 `AXValue` 可写，不需要任何 action，因此只按 `rawActions` 过滤会把 agent 真正要输入的文本框删掉；fixture 模式下 `rawActions` 存的是 secondary actions，而派发按 identifier 进行，同样误判。改为按角色（文本输入类）与 fixture identifier 放宽。
- **排序谓词不满足严格弱序**：两个都等于 focusedIndex 时返回 `true`。当前不可达，但改为分区构造以免日后触发标准库陷阱。
- **`optionalBool` 静默吞掉非法值**：`compact: "yes"` 会静默返回完整树加截图，即对「最省」请求给出最贵的回答。改为与同文件其它解析器一致抛出 `invalidArguments`。

### ⚠️ 已知缺口
`compact` 目前只在 macOS Swift runtime 实现。Linux / Windows 的 Go runtime 各自维护 tool schema，尚未支持该参数。在 P0 的收益被测量出来之前，不先铺开到三个 runtime。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/20260922-local-decision-model-mcp-tool.md`
