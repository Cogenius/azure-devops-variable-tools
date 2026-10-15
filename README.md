# Cogenius Variable tools for Azure DevOps

Save pipeline variables (for example the GitVersion or Build variables) to JSON files in one pipeline, stage or job, and load them again in another, such as a release pipeline or a later stage.

**Runs on Windows, Linux and macOS agents.** The tasks use the Node 20 task handler and execute PowerShell through `pwsh`.

## Tasks included

| Task | YAML name | Description |
| --- | --- | --- |
| **Cogenius Variable Save** | `CogeniusVariableSave@1` | Writes every variable whose name starts with one of the configured prefixes to `meta-<prefix>.json`. |
| **Cogenius Variable Load** | `CogeniusVariableLoad@1` | Reads one or more `meta-*.json` files and sets every entry as a pipeline variable. |

## Usage

### Save variables in your build

```yaml
steps:
  - task: CogeniusVariableSave@1
    inputs:
      prefixes: 'GITVERSION,BUILD'                    # comma separated, case-insensitive
      outpath: '$(Build.ArtifactStagingDirectory)'    # default

  - publish: '$(Build.ArtifactStagingDirectory)'
    artifact: drop
```

### Load them again later

```yaml
steps:
  - download: current
    artifact: drop

  - task: CogeniusVariableLoad@1
    inputs:
      jsonfiles: '**/meta-*.json'   # one or more file matching patterns, one per line

  - pwsh: Write-Host "Version: $(GITVERSION_FULLSEMVER)"
```

Relative patterns are resolved against `$(System.DefaultWorkingDirectory)`. In classic release pipelines this is the folder that holds the downloaded artifacts.

The JSON format is compatible with files created by the original `variabledehydration` task:

```json
[
  { "Name": "GITVERSION_FULLSEMVER", "Value": "1.2.3" },
  { "Name": "BUILD_BUILDNUMBER", "Value": "20261015.1" }
]
```

## Requirements

- Azure DevOps Services, or Azure DevOps Server 2022 or later.
- Agent version 3.232.1 or later, which supports the Node 20 handler.
- PowerShell 7+ (`pwsh`) on the `PATH` of Linux and macOS agents. Microsoft-hosted agents already include it. On Windows, the tasks use `pwsh` when it is available and otherwise fall back to Windows PowerShell 5.1.

## Notes

- Secret variables are not exposed as environment variables by Azure Pipelines, so they are never saved.
- Read-only system variables, such as `BUILD_BUILDNUMBER` in a release, cannot be overwritten. The agent logs a warning for these and continues.

## Development

```bash
npm ci
npm run install:tasks     # production dependencies inside each task folder (packaged in the .vsix)
npm run build             # compile tasks/*/v1/index.ts
npm test                  # Pester 5 tests (requires pwsh), also runs the compiled tasks end-to-end
npm run package           # creates dist/*.vsix with tfx-cli
```

Set the extension and task versions with `npm run version:set -- 1.2.3`. CI does this automatically from GitVersion. The task major version is tied to its folder (`v1`), so a breaking task change needs a new `v2` folder.

### Publishing

The GitHub Actions workflow (`.github/workflows/build.yml`):

- Tests on Ubuntu, Windows and macOS.
- Packages a `.vsix` on every push.
- Publishes to the Visual Studio Marketplace when a `v*` tag is pushed, or when the workflow is run manually with *publish* selected.

Publishing requires:

1. A Marketplace publisher with ID `Cogenius`.
2. A GitHub environment named `marketplace` with an `AZURE_DEVOPS_EXT_PAT` secret. The secret is an Azure DevOps PAT with the **Marketplace (Publish)** scope and *All accessible organizations*.
3. To make the extension public, set `"public": true` in `vss-extension.json`. Public extensions require a verified publisher.

## Credits

Based on [Azure DevOps Variable Tools](https://github.com/nkdAgility/azure-devops-variable-tools) by naked Agility (Martin Hinshelwood), licensed under MIT.
