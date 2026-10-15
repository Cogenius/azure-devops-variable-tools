import * as fs from 'fs';
import * as os from 'os';
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
    let fileListPath: string | undefined;
    try {
        const patterns = tl.getDelimitedInput('jsonfiles', '\n', true)
            .map(p => p.trim())
            .filter(p => p.length > 0);
        const defaultRoot = tl.getVariable('System.DefaultWorkingDirectory') || process.cwd();

        const files = tl.findMatch(defaultRoot, patterns)
            .filter(f => tl.stats(f).isFile());

        console.log(`Found ${files.length} file(s) matching ${patterns.join(', ')}`);
        if (files.length === 0) {
            tl.setResult(tl.TaskResult.Failed, 'There were no files found. You must specify at least one file to load.');
            return;
        }

        const tempDir = tl.getVariable('Agent.TempDirectory') || os.tmpdir();
        fileListPath = path.join(tempDir, `cogenius-variable-load-${process.pid}-${Date.now()}.txt`);
        fs.writeFileSync(fileListPath, files.join('\n'), { encoding: 'utf8' });

        const exitCode = await tl.tool(findPowerShell())
            .arg(['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass'])
            .arg(['-File', path.join(__dirname, 'load-variables.ps1')])
            .arg(['-FileListPath', fileListPath])
            .exec({ ignoreReturnCode: true });

        if (exitCode !== 0) {
            tl.setResult(tl.TaskResult.Failed, `Loading variables failed with exit code ${exitCode}.`);
            return;
        }
        tl.setResult(tl.TaskResult.Succeeded, 'Variables loaded.');
    } catch (err) {
        tl.setResult(tl.TaskResult.Failed, err instanceof Error ? err.message : String(err));
    } finally {
        if (fileListPath && fs.existsSync(fileListPath)) {
            fs.unlinkSync(fileListPath);
        }
    }
}

run();
