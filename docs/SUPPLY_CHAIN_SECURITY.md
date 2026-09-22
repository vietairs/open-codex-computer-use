# 供应链安全

这份文档定义仓库默认采用的供应链安全做法。

## 默认控制项

- 用 `npm audit` 对 npm 依赖做漏洞扫描。
- 用 `govulncheck` 对声明了 `require` 的每个 Go module 做漏洞扫描。
- 所有 GitHub Actions 都固定到不可变的 commit SHA，而不是漂移的版本标签。
- 依赖变更审查（`actions/dependency-review-action`）已预留配置，尚未接入实际 gate，见下文限制。

## 当前对应关系

- `.github/workflows/supply-chain-security.yml`：`audit-dependencies` job，在每个 PR 和 `main` push 上跑 `npm audit --audit-level=high`（仓库存在 `package-lock.json` 时）和逐 Go module 的 `govulncheck`。
- `.github/dependency-review-config.yml`：`actions/dependency-review-action` 的配置 schema，供后续接入该 action 时直接复用；该 action 本身因缺少经校验的 SHA pin，当前**没有**在任何 workflow 里实际运行。
- `scripts/check-action-pinning.sh`：如果 workflow 里出现浮动 tag 而不是 SHA，直接让 CI 失败（在 `repo-hygiene.yml` 和 `ci.yml` 里跑）。

SBOM 生成、build provenance attestation、OpenSSF Scorecard 目前均**未实现**，不要假设它们在跑。

## 限制和前提

- `npm audit` 和 `govulncheck` 的效果依赖仓库里存在可识别的 lockfile / `require` 声明；没有 `package-lock.json` 时 npm 审计会跳过并打印提示。
- Dependency Review 一旦接入，在 public repo 可以直接使用；private repo 通常需要 GitHub Advanced Security 或对应的代码安全能力。

## 后续可以补的事

- 给 `actions/dependency-review-action` 补一个经校验的 SHA pin，接入 PR 门禁。
- 为 release 产物生成 SBOM 和签名 build provenance attestation。
- 引入 OpenSSF Scorecard 做仓库级安全姿态分析。
- 把 attestation 校验继续下沉到部署平台或准入层。
