import * as path from 'path';
import * as tl from 'azure-pipelines-task-lib/task';

function findPowerShell(): string {
    const pwsh = tl.which('pwsh', false);
    if (pwsh) {
        return pwsh;
    }
    if (process.platform === 'win32') {
        const windowsPowerShell = tl.which('powershell', false);
        if (windowsPowerShell) {
            return windowsPowerShell;
        }
    }
    throw new Error('PowerShell 7+ (pwsh) was not found on the PATH of this agent. Install PowerShell: https://aka.ms/install-powershell');
}

async function run(): Promise<void> {
    try {
        const prefixes = tl.getInput('prefixes', true)!;
        const outPath = tl.getPathInput('outpath', true)!;

        const exitCode = await tl.tool(findPowerShell())
            .arg(['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass'])
            .arg(['-File', path.join(__dirname, 'save-variables.ps1')])
            .arg(['-Prefixes', prefixes, '-OutPath', outPath])
            .exec({ ignoreReturnCode: true });

        if (exitCode !== 0) {
            tl.setResult(tl.TaskResult.Failed, `Saving variables failed with exit code ${exitCode}.`);
            return;
        }
        tl.setResult(tl.TaskResult.Succeeded, 'Variables saved.');
    } catch (err) {
        tl.setResult(tl.TaskResult.Failed, err instanceof Error ? err.message : String(err));
    }
}

run();
