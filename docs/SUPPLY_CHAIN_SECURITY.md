# Supply Chain Security

This document describes the supply-chain security practices the repository
actually uses. It deliberately describes what runs, not what would be nice to
have — a security document advertising controls that do not run is worse than
one that admits it has few.

## Default controls

- Scan npm dependencies for vulnerabilities with `npm audit`.
- Scan every Go module for vulnerabilities with `govulncheck`, with no dependency-count precondition.
- Pin every GitHub Action to an immutable commit SHA rather than a floating version tag.
- Dependency review (`actions/dependency-review-action`) has its configuration prepared but is **not** wired into a live gate. See the limitations below.

## How those map to the repository

- `.github/workflows/supply-chain-security.yml`: the `audit-dependencies` job. On every PR and every push to `main` it runs `npm audit --audit-level=high` (when a `package-lock.json` exists) and `govulncheck` per Go module.
- `.github/dependency-review-config.yml`: the configuration schema for `actions/dependency-review-action`, ready to reuse when that action is wired in. The action itself does **not** run in any workflow today, because no verified SHA pin is available for it.
- `scripts/check-action-pinning.sh`: fails CI when a workflow references a floating tag instead of a SHA. Runs in both `repo-hygiene.yml` and `ci.yml`.

SBOM generation, build provenance attestation and OpenSSF Scorecard are **not
implemented**. Do not assume they are running.

## Why every Go module is scanned

The audit scans every module it enumerates, including modules that declare no
dependencies at all. A module with no third-party requirements is not
uninteresting: it still links the standard library, and the standard library is
where this repository's real exposure has been. `apps/OpenComputerUseLinux` and
`apps/OpenComputerUseWindows` declare zero requirements and ship as the bundled
runtimes inside the npm tarballs; an earlier revision skipped exactly those two
modules on the theory that "no requirements" means "nothing to check", while
they were reporting three call-reachable standard-library advisories under the
toolchain that built them.

For the same reason, the `go-version` pin in `supply-chain-security.yml` is kept
equal to the pins in `ci.yml` and `release.yml`. `govulncheck` reports the
standard library of the toolchain it runs under, so a scanner ahead of the
builder returns a clean result for binaries that ship vulnerable.

## Limitations and assumptions

- `npm audit` depends on a recognizable lockfile being present; without `package-lock.json` the npm audit step skips and prints a notice.
- `govulncheck` reports against the toolchain it runs under, so its results are only as current as the pinned `go-version`.
- Once dependency review is wired in, it works directly on public repositories; private repositories generally need GitHub Advanced Security or an equivalent code-security capability.

## Possible follow-ups

- Add a verified SHA pin for `actions/dependency-review-action` and wire it into the PR gate.
- Generate an SBOM and a signed build provenance attestation for release artifacts.
- Adopt OpenSSF Scorecard for repository-level security posture analysis.
- Push attestation verification down into the deployment platform or admission layer.
