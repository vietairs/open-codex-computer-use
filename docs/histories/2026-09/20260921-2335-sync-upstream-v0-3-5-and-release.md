# 2026-09-21 23:35 同步上游 v0.3.5 并发布 fork 版本 0.3.6-vietairs.1

## 背景

fork 停留在 `v0.2.1`，上游已经发布到 `v0.3.5`，中间累积了 SkyLight 后台点击、App Agent socket 命名空间隔离、真实窗口服务器拖拽、secondary action 映射修复和应用解析排序等变更。fork 自身也带着一批上游没有的能力：锁屏工作守卫与 opt-in 无人值守策略、app-screen session 校验、菜单栏状态项、app-agent socket 代码签名对端认证，以及 Stage Manager 后台点击回退。

这一轮的目标是把上游 `v0.3.5` 合进来，同时一条 fork 能力都不丢，然后给 fork 自己打一个版本。

## 变更

合并 `v0.3.5`，77 个文件、3627 行新增。自动合并处理了绝大部分，只有两个冲突，都是双方各自新增、语义不重叠，因此两边都保留：

- `InputSimulation.swift`：fork 的 `clickBackgrounded`（通过运行时解析 `CGEventSetWindowLocation`，服务于非 AX 回退路径）与上游的 `clickWithSkyLight`（服务于显式 `click_method: sky_click`）在 `ComputerUseService` 里分别有各自的调用点，两个函数都仍然可达。冲突块把两侧函数的收尾大括号共用了，所以除了删除标记还补了一个 `}`。
- `AccessibilitySnapshot.swift`：fork 新增的 `firstAnyWindow` 回退放在上游 `recoveryPolicy` 门之前，并且**不**受 `recoveryPolicy` 约束——读取后台窗口的 AX 树不会抢焦点，所以它在 `.denyActivation` 下也应该生效；上游那条基于激活的 `recoverVisibleWindow` 恢复继续只在 `.allowActivation` 下执行。

版本从 `0.2.1` 跳到 `0.3.6-vietairs.1`，按 `docs/releases/RELEASE_GUIDE.md` 列出的七个版本源全部同步。

## 为什么用 `0.3.6-vietairs.1` 而不是 `0.3.5`

fork 的内容是「上游 0.3.5 加上 fork 自己的能力」，直接复用 `v0.3.5` 会和已经 fetch 下来的上游同名 tag 冲突。选 `0.3.6-vietairs.1` 有三个好处：按 semver 它大于 `0.3.5`、小于将来上游可能发布的 `0.3.6`，语义正确；带 `-vietairs` 前缀段永远不会和上游 tag 撞名；`scripts/validate-github-release-notes.mjs` 的 tag 正则已经接受 prerelease 后缀，无需改动发布校验。

## 验证

- `swift build`：通过。
- `swift test`：221 个测试通过，0 失败（2 个按设计跳过，其中 `SkyClickLiveTests` 需要 `OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST=1`）。其中 fork 自己的测试仍在：`MacSessionGuard` 6 个、`AppScreenSession` 11 个、`ControlActivity` 5 个、peer auth 5 个。
- `scripts/check-docs.sh`、`scripts/check-action-pinning.sh`、全部 shell 与 mjs 语法检查、Linux Python 回归、Windows 与 Linux `go test`：全部通过。

## 已知遗留

`scripts/check-repo-hygiene.sh` 报告缺少 `.editorconfig`、`.markdownlint.json` 和若干 `.github/` 模板与 workflow。这在合并前的 `main` 上同样失败，上游从来没有把这些文件纳入版本控制，因此不是这一轮引入的问题，本轮也没有处理。
