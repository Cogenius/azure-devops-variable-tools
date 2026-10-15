# Copilot instructions — Cogenius Variable tools for Azure DevOps

## What this repo is
An Azure DevOps extension (publisher `Cogenius`, ID `cogenius-variable-tools`) with two pipeline tasks:

- `CogeniusVariableSave@1` (`tasks/CogeniusVariableSave/v1`) writes environment variables that match the given prefixes to `meta-<prefix>.json`.
- `CogeniusVariableLoad@1` (`tasks/CogeniusVariableLoad/v1`) reads `meta-*.json` files and emits `##vso[task.setvariable]` for each entry.

The tasks must run on **Windows, Linux and macOS** agents.

## Architecture
- Each task has three parts:
  - `task.json`, which uses the `Node20_1` handler.
  - `index.ts`, a thin TypeScript wrapper built on `azure-pipelines-task-lib`.
  - A PowerShell script that holds the logic.
- The wrapper reads inputs, resolves globs (with `tl.findMatch`), finds `pwsh`, and runs the script. On Windows it falls back to `powershell.exe`. The wrapper sets the task result from the script's exit code.
- The PowerShell scripts must **not** depend on `VstsTaskSdk`. They get their inputs through parameters and log with `Write-Host "##vso[...]"`. They exit `0` on success and `1` on failure.
- Every task folder is self-contained because it is packaged as is. It has its own `package.json`, `package-lock.json`, and production `node_modules`. Shared code is duplicated, not imported across folders.

## Cross-platform rules
- Scripts must work on Windows PowerShell 5.1 **and** PowerShell 7+ on Linux and macOS.
- Use `Join-Path` and `-LiteralPath`. Never hard-code `\` separators. Default globs use `/`.
- Environment variable names are case-sensitive on Linux, so match them case-insensitively, for example with `-like`.
- Write files as UTF-8 without BOM, using `[IO.File]::WriteAllText` with `UTF8Encoding($false)`.
- Escape values in logging commands:
  - Data: `%`→`%AZP25`, CR→`%0D`, LF→`%0A`.
  - Properties: also `;`→`%3B` and `]`→`%5D`.
- Keep the JSON format (`[{ "Name": ..., "Value": ... }]`) backwards compatible with the original nkdAgility tasks.

## Build, test, package
```bash
npm ci && npm run install:tasks   # root dev deps + per-task production deps
npm run build                     # tsc -> tasks/*/v*/index.js (gitignored)
npm test                          # Pester 5 (tests/Tasks.Tests.ps1), includes end-to-end runs of index.js
npm run package                   # tfx -> dist/*.vsix
```
- Run `npm run build` before `npm test` so the end-to-end wrapper tests are not skipped.
- To test on Linux locally, use Docker, for example `node:20-bookworm` with pwsh installed.

## Versioning and release
- Versioning uses GitVersion 6 (`GitVersion.yml`, GitFlow workflow, `develop` and `master`).
- `node scripts/set-version.js X.Y.Z` stamps the version into `vss-extension.json` and the minor/patch of every `task.json`. The task **major** version stays tied to its folder (`v1`). A breaking task change needs a new `vN` folder and a matching `Major`.
- Do not change task `id` GUIDs or `name` values. Pipelines that already use the tasks depend on them.
- `.github/workflows/build.yml` has three jobs:
  - test: Ubuntu, Windows and macOS.
  - package: builds the `.vsix` artifact.
  - publish: runs on `v*` tags or a manual dispatch, using the `AZURE_DEVOPS_EXT_PAT` secret in the `marketplace` environment.

## Conventions
- When you change a task's inputs or behavior, update `task.json`, the script, the tests, and `README.md`. The README is also the Marketplace page, and `docs/index.md` mirrors it.
- Add or extend Pester tests for every behavior change, and keep them platform-neutral.
- Keep the MIT attribution to naked Agility in `LICENSE.txt` and in the README credits.
