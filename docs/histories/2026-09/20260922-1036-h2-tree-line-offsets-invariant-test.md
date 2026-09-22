## [2026-09-22 10:36] | Task: 补齐 compact 视图 index invariant 的渲染器驱动测试

### 🤖 Execution Context
* **Agent ID**: `cortex -> fullstack-developer`
* **Base Model**: `claude-opus-5` (controller) / `claude-sonnet-5` (implementer)
* **Runtime**: `Claude Code, macOS 14+, swift test`

### 📥 User Query
> 修复 PR #10 code review 里的 H2：compact 快照的 `treeLineOffsets` 不变量完全没有测试覆盖，
> 补一个由真实 renderer 驱动的测试。

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`

**Key Actions:**
- **[新增测试]**: `testTreeLineOffsetsMatchEveryElementRowFromARealRenderer` 通过真实的 fixture
  renderer 构造快照，断言每个 element index 都有 offset 登记，且
  `treeLines[treeLineOffsets[i]]` 去掉缩进后恰好以 `"i "` 开头；再用
  `.compactActionable` 渲染一遍，确认 compact 行与登记行逐行一致。
- **[可见性调整]**: `SnapshotBuilder.buildFixtureSnapshot` 去掉 `private`，改为 module-internal，
  以便测试目标经由既有的 `@testable import` 直接驱动渲染器。这是本次唯一的生产代码改动。
- **[变异验证]**: 临时把记录点改成 `lines.count`（制造 off-by-one），新测试如期失败；还原后全量
  绿，确认测试非空转。

### 🧠 Design Intent (Why)
compact 视图的全部价值建立在一个前提上：compact 行开头的数字就是 full-tree 的 `element_index`，
从不重新编号。原有 13 个 compact 测试全部手写 `treeLineOffsets` 字面量，等于把这个前提当输入而
不是当被测对象——在记录点引入 off-by-one，或者在 `lines.append` 与 offset 登记之间插一行，整个
套件依然全绿，而这正是该特性要防的缺陷类别。

没有走 `FixtureBridge.writeState` + `SnapshotBuilder.build(for:)` 的端到端路径，是因为它只多覆盖
一次分发跳转，却要写 `NSTemporaryDirectory()` 下的进程间共享文件，可能干扰开发者正在运行的
fixture app；而真正有风险的不变量完全位于 `buildFixtureSnapshot` 内部。

**已知覆盖边界：** 本测试只守住 fixture renderer。走真实 AX 的 `TreeRenderer` 在
`AccessibilitySnapshot.swift` 内有自己的一处 offset 记录点，需要真实 `AXUIElement` 和
Accessibility 授权才能驱动，因此仍未被覆盖。

### 📁 Files Modified
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
