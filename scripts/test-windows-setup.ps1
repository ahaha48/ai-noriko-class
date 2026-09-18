# Run only on an ephemeral GitHub-hosted Windows runner; leave all created files intact.
param([switch]$LiveDownload)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True ($env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_OS -eq 'Windows' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted') 'Use an ephemeral GitHub-hosted Windows runner only.'
Assert-True ($PSVersionTable.PSEdition -eq 'Desktop' -and $PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) 'Windows PowerShell 5.1 is required.'
Assert-True (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -and (Test-Path -LiteralPath $env:RUNNER_TEMP -PathType Container)) 'RUNNER_TEMP is unavailable.'

$repositoryPath = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE)
$commandPath = Join-Path $repositoryPath 'docs\downloads\AI-NORIKO-Windows-Setup.cmd'
$inventoryPath = Join-Path $repositoryPath 'docs\downloads\kit-files.json'
$releasePath = Join-Path $repositoryPath 'docs\downloads\release.json'
$testRoot = Join-Path $env:RUNNER_TEMP ('AI-NORIKO-Setup-Test-' + [Guid]::NewGuid().ToString('N'))
Assert-True (-not (Test-Path -LiteralPath $testRoot)) 'The unique test directory already exists.'
$null = New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop
$originalUserProfile = $env:USERPROFILE
$originalHome = $HOME
$profilePath = [Environment]::GetFolderPath('UserProfile')
Assert-True (Test-Path -LiteralPath $profilePath -PathType Container) 'The runner user profile is unavailable.'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$nodeCommand = (Get-Command node.exe -CommandType Application -ErrorAction Stop).Source
Assert-True ((& $nodeCommand --version) -match '^v24\.') 'Node.js 24 is required for the reviewed kit checks.'
$inventory = [IO.File]::ReadAllText($inventoryPath, $utf8) | ConvertFrom-Json
$release = [IO.File]::ReadAllText($releasePath, $utf8) | ConvertFrom-Json
Assert-True (-not [string]::IsNullOrWhiteSpace($inventory.version) -and @($inventory.files).Count -gt 0) 'The versioned kit inventory is empty.'
$inventoryByPath = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
$inventoryWindowsPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($item in $inventory.files) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($item.path) -and -not $item.path.StartsWith('/') -and -not $item.path.StartsWith('AI-NORIKO-Starter-Kit/') -and $item.path -notmatch '(^|/)\.{1,2}(/|$)|\\|[:\x00-\x1f]|//' -and $item.sha256 -match '^[a-fA-F0-9]{64}$' -and [long]$item.bytes -ge 0) 'The kit inventory contains an invalid path, size, or hash.'
    $entryPath = 'AI-NORIKO-Starter-Kit/' + $item.path
    Assert-True ($inventoryWindowsPaths.Add($entryPath)) ('The inventory repeats a Windows path: ' + $item.path)
    $inventoryByPath.Add($entryPath, $item)
}

function Write-NewText {
    param([string]$Path, [string]$Text)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try {
        $bytes = $utf8.GetBytes($Text)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
}

function Get-StreamHash {
    param([IO.Stream]$Stream)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace('-', '') }
    finally { $algorithm.Dispose() }
}

function Assert-ExtractedKit {
    param([string]$Destination, [switch]$AllowGeneratedFiles)
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        Assert-True ($entries.Count -eq $inventoryByPath.Count) 'The ZIP file count differs from kit-files.json.'
        if (-not $AllowGeneratedFiles) {
            Assert-True (@(Get-ChildItem -LiteralPath $Destination -File -Recurse -Force).Count -eq $inventoryByPath.Count) 'The extracted file count differs from kit-files.json.'
        }
        $seenEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($entry in $entries) {
            Assert-True ($seenEntries.Add($entry.FullName) -and $inventoryByPath.ContainsKey($entry.FullName)) ('Unexpected or repeated ZIP entry: ' + $entry.FullName)
            $item = $inventoryByPath[$entry.FullName]
            Assert-True ($entry.Length -eq [long]$item.bytes) ('ZIP size differs from inventory: ' + $entry.FullName)
            $target = Join-Path $Destination $entry.FullName.Replace('/', '\')
            Assert-True (Test-Path -LiteralPath $target -PathType Leaf) ('Missing extracted file: ' + $entry.FullName)
            $stream = $entry.Open()
            try { $expected = Get-StreamHash $stream } finally { $stream.Dispose() }
            Assert-True ($expected -eq $item.sha256) ('ZIP hash differs from inventory: ' + $entry.FullName)
            Assert-True ((Get-Item -LiteralPath $target).Length -eq [long]$item.bytes) ('Extracted size differs from inventory: ' + $entry.FullName)
            Assert-True ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $expected) ('Extracted content differs: ' + $entry.FullName)
        }
        $japaneseNames = @('判断基準テンプレート.md', '導入チェックシート.md', '検証記録テンプレート.md', '社長確認用メモ.md')
        $nonAsciiEntries = @($entries | Where-Object { $_.FullName -match '[^\x00-\x7f]' })
        Assert-True ($nonAsciiEntries.Count -eq 4) 'The four reviewed UTF-8 Japanese filenames were not preserved.'
        foreach ($name in $japaneseNames) {
            $relative = 'AI-NORIKO-Starter-Kit/templates/' + $name
            Assert-True (@($entries | Where-Object { $_.FullName -ceq $relative }).Count -eq 1) ('The UTF-8 archive name differs: ' + $name)
            Assert-True (Test-Path -LiteralPath (Join-Path $Destination $relative) -PathType Leaf) ('The UTF-8 extracted name differs: ' + $name)
        }
        $promptFile = Join-Path $Destination 'AI-NORIKO-Starter-Kit\course\prompts.json'
        $promptData = [IO.File]::ReadAllText($promptFile, $utf8) | ConvertFrom-Json
        Assert-True (@($promptData.prompts).Count -eq 21 -and $promptData.prompts[20].id -ceq 'P21') 'The 21 prompts, including P21, are missing.'
        $packageInfo = [IO.File]::ReadAllText((Join-Path $Destination 'AI-NORIKO-Starter-Kit\package.json'), $utf8) | ConvertFrom-Json
        Assert-True ($packageInfo.version -ceq $inventory.version) 'The kit package version differs from kit-files.json.'
    } finally { $zip.Dispose() }
}

# Parse the actual downloadable file as UTF-8. Never evaluate its terminal exit or main routine here.
$commandText = [IO.File]::ReadAllText($commandPath, $utf8)
$parts = @($commandText -split '(?m)^# POWERSHELL_PAYLOAD\r?$', 2)
Assert-True ($parts.Count -eq 2) 'The CMD PowerShell payload marker is missing.'
$tokens = $null
$parseErrors = $null
$payloadAst = [Management.Automation.Language.Parser]::ParseInput($parts[1], [ref]$tokens, [ref]$parseErrors)
Assert-True (@($parseErrors).Count -eq 0) ('PowerShell payload parse errors: ' + ($parseErrors -join '; '))
$functions = @($payloadAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })
Assert-True ($functions.Count -eq 2 -and @($functions.Name) -contains 'Expand-NorikoArchive' -and @($functions.Name) -contains 'Start-NorikoDownload') 'Unexpected payload functions; review the test before continuing.'
. ([ScriptBlock]::Create(($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n"))

$hashMatch = [regex]::Match($parts[1], "-ExpectedHash '([A-Fa-f0-9]{64})'")
Assert-True $hashMatch.Success 'The downloadable CMD must contain a concrete SHA-256, not the template placeholder.'
$expectedHash = $hashMatch.Groups[1].Value
$urlMatches = [regex]::Matches($parts[1], "Invoke-WebRequest -UseBasicParsing -Uri '([^']+)' -OutFile")
Assert-True ($urlMatches.Count -eq 1) 'The downloadable CMD must have exactly one ZIP download URL.'
$downloadUrl = $urlMatches[0].Groups[1].Value
$immutableRelativePath = 'downloads/releases/' + $inventory.version + '/' + $expectedHash.Substring(0, 12).ToLowerInvariant() + '/AI-NORIKO-Starter-Kit.zip'
Assert-True ($release.version -ceq $inventory.version -and $release.sha256 -eq $expectedHash) 'release.json differs from the inventory version or CMD hash.'
Assert-True ($release.starterKit -ceq $immutableRelativePath) 'release.json does not identify the expected immutable kit path.'
Assert-True ($downloadUrl -ceq ('https://ahaha48.github.io/ai-noriko-class/' + $immutableRelativePath)) 'The CMD does not use the reviewed immutable public URL.'
$archivePath = Join-Path (Join-Path $repositoryPath 'docs') $immutableRelativePath.Replace('/', '\')
Assert-True ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -eq $expectedHash) 'The downloadable CMD and committed ZIP disagree.'
$originalCommandHash = (Get-FileHash -LiteralPath $commandPath -Algorithm SHA256).Hash

$sentinelPath = Join-Path $testRoot 'existing-sentinel.txt'
Write-NewText $sentinelPath 'preserve-existing-data'
$sentinelHash = (Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash
$goodDestination = Join-Path $testRoot 'valid-extraction'
Expand-NorikoArchive -ArchivePath $archivePath -DestinationPath $goodDestination -ExpectedHash $expectedHash
Assert-ExtractedKit $goodDestination
Write-Host ('PASS: immutable ZIP; ' + $inventoryByPath.Count + ' files matching the versioned inventory; four UTF-8 Japanese filenames; P21.')

function Assert-RejectedArchive {
    param([string]$Label, [string]$ZipPath, [string]$Destination, [string]$Hash, [bool]$ExistingDestination = $false)
    $rejected = $false
    try { Expand-NorikoArchive -ArchivePath $ZipPath -DestinationPath $Destination -ExpectedHash $Hash }
    catch { $rejected = $true }
    Assert-True $rejected ('Unsafe archive was accepted: ' + $Label)
    Assert-True ((Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash -eq $sentinelHash) ('Existing sentinel changed: ' + $Label)
    if (-not $ExistingDestination) {
        Assert-True (-not (Test-Path -LiteralPath $Destination)) ('Rejected archive created a destination: ' + $Label)
    }
    Write-Host ('PASS: rejected ' + $Label + '; existing sentinel preserved.')
}

function New-TestArchive {
    param([string]$Label, [string[]]$Names)
    $path = Join-Path $testRoot ($Label + '.zip')
    $fileStream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite)
    $zip = $null
    try {
        $zip = New-Object IO.Compression.ZipArchive($fileStream, [IO.Compression.ZipArchiveMode]::Create, $true, $utf8)
        foreach ($name in $Names) {
            $entry = $zip.CreateEntry($name)
            $entryStream = $entry.Open()
            try {
                $bytes = $utf8.GetBytes('synthetic test fixture')
                $entryStream.Write($bytes, 0, $bytes.Length)
            } finally { $entryStream.Dispose() }
        }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $fileStream.Dispose()
    }
    return $path
}

Assert-RejectedArchive 'existing destination' $archivePath $goodDestination $expectedHash $true
Assert-ExtractedKit $goodDestination
Assert-RejectedArchive 'SHA-256 mismatch' $archivePath (Join-Path $testRoot 'bad-hash') ('0' * 64)
$requiredNames = @('AI-NORIKO-Starter-Kit/package.json', 'AI-NORIKO-Starter-Kit/START_HERE.md', 'AI-NORIKO-Starter-Kit/START-WINDOWS.bat', 'AI-NORIKO-Starter-Kit/src/App.tsx')
$unsafeFixtures = @(
    @{ Label = 'zip-slip'; Names = $requiredNames + @('AI-NORIKO-Starter-Kit/../../existing-sentinel.txt') },
    @{ Label = 'backslash-zip-slip'; Names = $requiredNames + @('AI-NORIKO-Starter-Kit\..\..\existing-sentinel.txt') },
    @{ Label = 'duplicate'; Names = $requiredNames + @('AI-NORIKO-Starter-Kit/package.json') },
    @{ Label = 'case-duplicate'; Names = $requiredNames + @('AI-NORIKO-Starter-Kit/PACKAGE.json') },
    @{ Label = 'missing-required-file'; Names = @($requiredNames | Where-Object { $_ -notlike '*/src/App.tsx' }) },
    @{ Label = 'wrong-root'; Names = $requiredNames + @('Unexpected/README.md') },
    @{ Label = 'reserved-windows-name'; Names = $requiredNames + @('AI-NORIKO-Starter-Kit/CON.txt') }
)
foreach ($fixture in $unsafeFixtures) {
    $fixtureZip = New-TestArchive $fixture.Label $fixture.Names
    $fixtureHash = (Get-FileHash -LiteralPath $fixtureZip -Algorithm SHA256).Hash
    Assert-RejectedArchive $fixture.Label $fixtureZip (Join-Path $testRoot ('rejected-' + $fixture.Label)) $fixtureHash
}

# Branch CI serves only the reviewed ZIP on loopback. Live mode runs an untouched CMD copy.
$httpProcess = $null
try {
    $testCommandText = $commandText
    if (-not $LiveDownload) {
        $serverScriptPath = Join-Path $testRoot 'serve-reviewed-zip.cjs'
        $serverReadyPath = Join-Path $testRoot 'http-port.txt'
        $serverScript = @'
const fs = require('node:fs');
const http = require('node:http');
const { pipeline } = require('node:stream');
const [archive, ready] = process.argv.slice(2);
const size = fs.statSync(archive).size;
const server = http.createServer((request, response) => {
  if (request.method !== 'GET' || request.url !== '/AI-NORIKO-Starter-Kit.zip') {
    response.writeHead(404); response.end(); return;
  }
  response.writeHead(200, { 'Content-Type': 'application/zip', 'Content-Length': size, 'Cache-Control': 'no-store' });
  pipeline(fs.createReadStream(archive), response, () => {});
});
server.listen(0, '127.0.0.1', () => fs.writeFileSync(ready, String(server.address().port), { flag: 'wx' }));
'@
        Write-NewText $serverScriptPath $serverScript
        $serverStart = New-Object Diagnostics.ProcessStartInfo
        $serverStart.FileName = $nodeCommand
        $serverStart.Arguments = '"' + $serverScriptPath + '" "' + $archivePath + '" "' + $serverReadyPath + '"'
        $serverStart.UseShellExecute = $false
        $serverStart.WorkingDirectory = $testRoot
        $httpProcess = New-Object Diagnostics.Process
        $httpProcess.StartInfo = $serverStart
        Assert-True ($httpProcess.Start()) 'Could not start the runner-only ZIP server.'
        for ($wait = 0; $wait -lt 100 -and -not (Test-Path -LiteralPath $serverReadyPath); $wait++) {
            Assert-True (-not $httpProcess.HasExited) 'The runner-only ZIP server stopped before becoming ready.'
            Start-Sleep -Milliseconds 100
        }
        Assert-True (Test-Path -LiteralPath $serverReadyPath -PathType Leaf) 'The runner-only ZIP server did not become ready.'
        $localPort = [int][IO.File]::ReadAllText($serverReadyPath, $utf8)
        Assert-True ($localPort -gt 0 -and $localPort -le 65535) 'The ZIP server returned an invalid port.'
        $localDownloadUrl = 'http://127.0.0.1:' + $localPort + '/AI-NORIKO-Starter-Kit.zip'
        Assert-True ([regex]::Matches($commandText, [regex]::Escape($downloadUrl)).Count -eq 1) 'The original download URL is not unique.'
        $testCommandText = $commandText.Replace($downloadUrl, $localDownloadUrl)
        Assert-True ($testCommandText.Replace($localDownloadUrl, $downloadUrl) -ceq $commandText) 'Local mode must change only the URL in the temporary CMD copy.'
        Write-Host 'Mode: branch CI; loopback ZIP download; original SHA-256 unchanged.'
    } else {
        Write-Host ('Mode: live immutable public download; untouched CMD copy; ' + $downloadUrl)
    }

    # The helper uses the runner profile; the test never redirects HOME or USERPROFILE.
    $specialDirectory = Join-Path $testRoot "日本語 download's !"
    $null = New-Item -ItemType Directory -Path $specialDirectory -ErrorAction Stop
    $specialCommand = Join-Path $specialDirectory "AI NORIKO 日本語's ! Setup.cmd"
    if ($LiveDownload) { [IO.File]::Copy($commandPath, $specialCommand, $false) }
    else { Write-NewText $specialCommand $testCommandText }
    Assert-True (([regex]::Match($testCommandText, "-ExpectedHash '([A-Fa-f0-9]{64})'")).Groups[1].Value -ceq $expectedHash) 'The temporary CMD changed the reviewed SHA-256.'
    $createdRuns = @()
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $before = @(Get-ChildItem -LiteralPath $profilePath -Directory -Filter 'AI-NORIKO-*' | ForEach-Object { $_.FullName })
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
        $startInfo.Arguments = '/d /v:off /s /c ""' + $specialCommand + '""'
        $startInfo.UseShellExecute = $false
        $startInfo.WorkingDirectory = $specialDirectory
        $startInfo.EnvironmentVariables['AI_NORIKO_SETUP_NONINTERACTIVE'] = '1'
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        try {
            Assert-True ($process.Start()) 'Could not start the downloaded CMD.'
            Assert-True ($process.WaitForExit(180000)) 'The real CMD exceeded three minutes.'
            Assert-True ($process.ExitCode -eq 0) ('Real CMD failed; check the ZIP URL/hash and network. Exit: ' + $process.ExitCode)
        } finally { $process.Dispose() }
        $newRuns = @(Get-ChildItem -LiteralPath $profilePath -Directory -Filter 'AI-NORIKO-*' | Where-Object { $before -notcontains $_.FullName })
        Assert-True ($newRuns.Count -eq 1) 'A real CMD run must create exactly one fresh profile folder.'
        $runPath = $newRuns[0].FullName
        Assert-True ($createdRuns -notcontains $runPath) 'A later run reused an earlier destination.'
        $createdRuns += $runPath
        $nextSteps = Join-Path $runPath 'NEXT-STEPS.txt'
        $extractedPath = Join-Path $runPath 'files'
        Assert-True (Test-Path -LiteralPath $nextSteps -PathType Leaf) 'NEXT-STEPS.txt is missing.'
        $nextText = [IO.File]::ReadAllText($nextSteps, $utf8)
        Assert-True ($nextText.Contains((Join-Path $extractedPath 'AI-NORIKO-Starter-Kit')) -and $nextText.Contains('P01')) 'NEXT-STEPS.txt does not identify the kit folder and P01.'
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $runPath 'AI-NORIKO-Starter-Kit.zip') -Algorithm SHA256).Hash -eq $expectedHash) 'The downloaded ZIP differs from the reviewed kit.'
        Assert-ExtractedKit $extractedPath
        Write-NewText (Join-Path $runPath 'ci-preserve-sentinel.txt') 'preserve-earlier-run'
        Write-Host ('PASS: real CMD run ' + $attempt + '; exit 0; NEXT-STEPS; exact kit; special-character download path.')
    }
    foreach ($runPath in $createdRuns) {
        Assert-True ([IO.File]::ReadAllText((Join-Path $runPath 'ci-preserve-sentinel.txt'), $utf8) -ceq 'preserve-earlier-run') 'A later run modified an earlier run.'
        Assert-ExtractedKit (Join-Path $runPath 'files')
    }

    # Build/test a fresh runner-only extraction. No Electron GUI or account integration is launched.
    $npmCommand = (Get-Command npm.cmd -CommandType Application -ErrorAction Stop).Source
    $npmChecks = @(
        @{ Name = 'npm ci'; Arguments = @('ci', '--no-audit', '--no-fund') },
        @{ Name = 'npm test'; Arguments = @('test') },
        @{ Name = 'npm run doctor'; Arguments = @('run', 'doctor') },
        @{ Name = 'npm run check'; Arguments = @('run', 'check') },
        @{ Name = 'npm run build'; Arguments = @('run', 'build') },
        @{ Name = 'npm run smoke'; Arguments = @('run', 'smoke') }
    )
    Push-Location (Join-Path $goodDestination 'AI-NORIKO-Starter-Kit')
    try {
        foreach ($check in $npmChecks) {
            Write-Host ('Running on Windows / Node 24: ' + $check.Name)
            $checkArguments = $check.Arguments
            & $npmCommand @checkArguments
            Assert-True ($LASTEXITCODE -eq 0) ($check.Name + ' failed with exit ' + $LASTEXITCODE)
        }
    } finally { Pop-Location }
    Assert-ExtractedKit $goodDestination -AllowGeneratedFiles
    Assert-True ((Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash -eq $sentinelHash) 'The original sentinel changed.'
    Assert-True ((Get-FileHash -LiteralPath $commandPath -Algorithm SHA256).Hash -eq $originalCommandHash) 'The distributable CMD was modified.'
    Write-Host 'PASS: two distinct destinations; versioned inventory preserved; Windows npm tests, doctor, typecheck, build, and smoke passed.'
    Write-Host ('Test fixtures retained for runner teardown: ' + $testRoot)
} finally {
    if ($null -ne $httpProcess) {
        try {
            if (-not $httpProcess.HasExited) {
                $httpProcess.Kill()
                $httpProcess.WaitForExit()
            }
        } finally { $httpProcess.Dispose() }
    }
    Assert-True ($env:USERPROFILE -ceq $originalUserProfile -and $HOME -ceq $originalHome) 'The test changed HOME or USERPROFILE.'
}
