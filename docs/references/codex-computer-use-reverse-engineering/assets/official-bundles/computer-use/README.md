# Official Computer Use Bundles

This directory holds official `computer-use` zip packages archived from the local bundled plugin cache, used as input for reverse-engineering analysis and version comparison.

## Current Archive

| File | Size | SHA-256 |
| --- | ---: | --- |
| `1.0.750.zip` | 13 MB | `7afe231e98ddb3b95030c8c56bb178a0217e98fcbb08abf9e1b467fd7ead5b9d` |
| `1.0.755.zip` | 13 MB | `cfabe3f41bfec1ea1d5f99ca2f5424eac98487e9474a099394c372d5df7a6460` |

## Maintenance Conventions

- The zips here are archived purely as raw official artifacts and are not directly used in the build.
- When adding a new zip, update `SHA256SUMS` and this file at the same time.
- Zips in this directory are tracked via Git LFS, to avoid committing large binaries directly as plain Git objects.
