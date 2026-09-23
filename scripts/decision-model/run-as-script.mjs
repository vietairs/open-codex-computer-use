// Tells a CLI module whether node was asked to run it, so tests can import its helpers without starting main().
//
// Node realpaths import.meta.url but leaves process.argv[1] as typed, so comparing the two directly is false whenever
// the script is reached through a symlinked path (a symlinked checkout, or /tmp -> /private/tmp on macOS). main()
// would then never run and the script would exit 0 with no output, which a caller reads as success. Both sides are
// therefore compared as real paths. Node built-ins only.

import { realpathSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * True when `entryPath` (default: process.argv[1]) names the same file as the module at `moduleUrl`.
 * A missing or unresolvable entry path (for example `node -e`) is not this module.
 */
export function invokedAsScript(moduleUrl, entryPath = process.argv[1]) {
  if (!entryPath) return false;
  try {
    return realpathSync(resolve(entryPath)) === realpathSync(fileURLToPath(moduleUrl));
  } catch {
    return false;
  }
}
