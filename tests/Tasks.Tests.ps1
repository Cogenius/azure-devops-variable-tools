BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:saveTask = Join-Path $repoRoot 'tasks/CogeniusVariableSave/v1'
    $script:loadTask = Join-Path $repoRoot 'tasks/CogeniusVariableLoad/v1'
    $script:saveScript = Join-Path $saveTask 'save-variables.ps1'
    $script:loadScript = Join-Path $loadTask 'load-variables.ps1'

    function Invoke-Script([string] $Script, [string[]] $Arguments) {
        $output = & (Get-Process -Id $PID).Path -NoLogo -NoProfile -NonInteractive -File $Script @Arguments 2>&1
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output | ForEach-Object { "$_" }) }
    }

    function Invoke-NodeTask([string] $TaskDir, [hashtable] $Environment) {
        $saved = @{}
        foreach ($key in $Environment.Keys) {
            $saved[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $Environment[$key])
        }
        try {
            $output = & node (Join-Path $TaskDir 'index.js') 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output | ForEach-Object { "$_" }) }
        }
        finally {
            foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
        }
    }
}

Describe 'save-variables.ps1' {
    BeforeEach {
        $script:out = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
        $env:CGTEST_ALPHA = 'one'
        $env:CGTEST_BETA = "two;with]special%chars"
        $env:OTHERTEST_GAMMA = 'three'
    }
    AfterEach {
        Remove-Item Env:CGTEST_ALPHA, Env:CGTEST_BETA, Env:OTHERTEST_GAMMA -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
    }

    It 'writes one meta file per prefix containing only matching variables' {
        $r = Invoke-Script $saveScript @('-Prefixes', 'CGTEST, OTHERTEST', '-OutPath', $out)
        $r.ExitCode | Should -Be 0

        $cg = Get-Content (Join-Path $out 'meta-cgtest.json') -Raw | ConvertFrom-Json
        @($cg).Count | Should -Be 2
        ($cg | Where-Object Name -eq 'CGTEST_BETA').Value | Should -Be "two;with]special%chars"

        $other = @(Get-Content (Join-Path $out 'meta-othertest.json') -Raw | ConvertFrom-Json)
        $other.Count | Should -Be 1
        $other[0].Name | Should -Be 'OTHERTEST_GAMMA'
    }

    It 'matches prefixes case-insensitively' {
        $r = Invoke-Script $saveScript @('-Prefixes', 'cgtest', '-OutPath', $out)
        $r.ExitCode | Should -Be 0
        @(Get-Content (Join-Path $out 'meta-cgtest.json') -Raw | ConvertFrom-Json).Count | Should -Be 2
    }

    It 'does not create a file when nothing matches' {
        $r = Invoke-Script $saveScript @('-Prefixes', 'NOPE_DOES_NOT_EXIST', '-OutPath', $out)
        $r.ExitCode | Should -Be 0
        Test-Path (Join-Path $out 'meta-nope_does_not_exist.json') | Should -BeFalse
        ($r.Output -join "`n") | Should -Match 'No variable names matched'
    }

    It 'fails when no prefixes are given' {
        $r = Invoke-Script $saveScript @('-Prefixes', ' , ', '-OutPath', $out)
        $r.ExitCode | Should -Be 1
        ($r.Output -join "`n") | Should -Match '##vso\[task.logissue type=error\]'
    }
}

Describe 'load-variables.ps1' {
    It 'sets a variable for every entry in the legacy sample files' {
        $files = Get-ChildItem (Join-Path $PSScriptRoot 'data') -Filter 'meta-*.json' | ForEach-Object FullName
        $list = New-TemporaryFile
        try {
            Set-Content $list $files
            $r = Invoke-Script $loadScript @('-FileListPath', $list.FullName)
        }
        finally { Remove-Item $list }
        $r.ExitCode | Should -Be 0
        $expected = ($files | ForEach-Object { @(Get-Content $_ -Raw | ConvertFrom-Json) }).Count
        @($r.Output | Where-Object { $_ -like '##vso`[task.setvariable variable=*' }).Count | Should -Be $expected
        $r.Output | Should -Contain '##vso[task.setvariable variable=BUILD_DEFINITIONVERSION]8'
    }

    It 'escapes special characters and handles a single-object file' {
        $tmp = New-Item -ItemType Directory (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid()))
        try {
            $file = Join-Path $tmp 'meta-single.json'
            Set-Content $file '{ "Name": "A;B]", "Value": "50% done\nnext ]" }'
            $r = Invoke-Script $loadScript @('-Path', $file)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Contain '##vso[task.setvariable variable=A%3BB%5D]50%AZP25 done%0Anext ]'
        }
        finally { Remove-Item -Recurse -Force $tmp }
    }

    It 'fails on invalid JSON' {
        $tmp = New-Item -ItemType Directory (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid()))
        try {
            $file = Join-Path $tmp 'meta-bad.json'
            Set-Content $file 'not json'
            $r = Invoke-Script $loadScript @('-Path', $file)
            $r.ExitCode | Should -Be 1
            ($r.Output -join "`n") | Should -Match '##vso\[task.logissue type=error\]'
        }
        finally { Remove-Item -Recurse -Force $tmp }
    }
}

Describe 'Node task wrappers (end-to-end)' -Skip:(-not (Test-Path (Join-Path $PSScriptRoot '../tasks/CogeniusVariableSave/v1/index.js'))) {
    BeforeAll {
        $script:work = New-Item -ItemType Directory (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid()))
        $script:staging = Join-Path $work 'staging'
    }
    AfterAll { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }

    It 'CogeniusVariableSave writes meta files and succeeds' {
        $r = Invoke-NodeTask $saveTask @{
            INPUT_PREFIXES               = 'E2ETEST'
            INPUT_OUTPATH                = $staging
            E2ETEST_VALUE                = 'hello world'
            AGENT_TEMPDIRECTORY          = $work
            SYSTEM_DEFAULTWORKINGDIRECTORY = $work
        }
        $r.ExitCode | Should -Be 0
        ($r.Output -join "`n") | Should -Match 'task.complete result=Succeeded'
        Test-Path (Join-Path $staging 'meta-e2etest.json') | Should -BeTrue
    }

    It 'CogeniusVariableLoad finds files with a ** glob and sets variables' {
        $r = Invoke-NodeTask $loadTask @{
            INPUT_JSONFILES              = '**/meta-*.json'
            AGENT_TEMPDIRECTORY          = $work
            SYSTEM_DEFAULTWORKINGDIRECTORY = $work
        }
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Contain '##vso[task.setvariable variable=E2ETEST_VALUE]hello world'
        ($r.Output -join "`n") | Should -Match 'task.complete result=Succeeded'
        @(Get-ChildItem $work -Filter 'cogenius-variable-load-*').Count | Should -Be 0
    }

    It 'CogeniusVariableLoad fails when no files match' {
        $r = Invoke-NodeTask $loadTask @{
            INPUT_JSONFILES              = '**/does-not-exist-*.json'
            AGENT_TEMPDIRECTORY          = $work
            SYSTEM_DEFAULTWORKINGDIRECTORY = $work
        }
        ($r.Output -join "`n") | Should -Match 'task.complete result=Failed'
    }
}
