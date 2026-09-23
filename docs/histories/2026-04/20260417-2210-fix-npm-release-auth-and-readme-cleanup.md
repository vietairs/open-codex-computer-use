## [2026-04-17 22:10] | Task: Fix npm release auth and clean up npm README

### 📥 User Request

> Remove `If you want the server without the visual cursor overlay:` and the code block below it from the npm package page; see the release all the way through to where it can actually be published from a git tag, bumping the version or re-publishing again along the way if needed.

### 🔧 What Changed

- **Clean up the npm README template**: removed the extra "disable visual cursor overlay" MCP config example from the generated package README, keeping only the default install and MCP config instructions.
- **Add an npm publish auth fallback**: added a `Configure npm token fallback` step to `release.yml`; if the repo has an `NPM_TOKEN` secret configured, it's written to `NODE_AUTH_TOKEN` for `npm publish` to use.
- **Sync repo docs**: updated the release instructions in the root README and `docs/CICD.md` to say "prefer compatibility with Trusted Publishing, while also supporting an `NPM_TOKEN` secret fallback."

### 🧠 Design Intent (Why)

Hands-on testing found that the GitHub Actions build already runs cleanly, but npm publish would fail at the publish step for packages that didn't have a Trusted Publisher individually configured. For this repo, the safest goal isn't to insist on a single path, but to guarantee that the `git tag` release main path can reliably publish all three packages.

At the same time, the npm package page is aimed at end installers, so the README should stick to the default success path as much as possible, without piling on extra optional env-var branches that might make new users think they still need to change the overlay config.

### 📌 Key Files

- `.github/workflows/release.yml`
- `scripts/npm/build-packages.mjs`
- `README.md`
- `docs/CICD.md`
