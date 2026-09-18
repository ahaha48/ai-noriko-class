# Run only on an ephemeral GitHub-hosted Windows runner; leave all created files intact.
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
$archivePath = Join-Path $repositoryPath 'docs\downloads\AI-NORIKO-Starter-Kit.zip'
$testRoot = Join-Path $env:RUNNER_TEMP ('AI-NORIKO-Setup-Test-' + [Guid]::NewGuid().ToString('N'))
Assert-True (-not (Test-Path -LiteralPath $testRoot)) 'The unique test directory already exists.'
$null = New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop
$originalUserProfile = $env:USERPROFILE
$originalHome = $HOME
$profilePath = [Environment]::GetFolderPath('UserProfile')
Assert-True (Test-Path -LiteralPath $profilePath -PathType Container) 'The runner user profile is unavailable.'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
Add-Type -AssemblyName System.IO.Compression.FileSystem

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
    param([string]$Destination)
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        Assert-True ($entries.Count -eq 56) 'The reviewed kit must contain exactly 56 files; review this test when the kit changes.'
        Assert-True (@(Get-ChildItem -LiteralPath $Destination -File -Recurse -Force).Count -eq 56) 'The extracted file count differs.'
        foreach ($entry in $entries) {
            $target = Join-Path $Destination $entry.FullName.Replace('/', '\')
            Assert-True (Test-Path -LiteralPath $target -PathType Leaf) ('Missing extracted file: ' + $entry.FullName)
            $stream = $entry.Open()
            try { $expected = Get-StreamHash $stream } finally { $stream.Dispose() }
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
Assert-True ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -eq $expectedHash) 'The downloadable CMD and committed ZIP disagree.'

$sentinelPath = Join-Path $testRoot 'existing-sentinel.txt'
Write-NewText $sentinelPath 'preserve-existing-data'
$sentinelHash = (Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash
$goodDestination = Join-Path $testRoot 'valid-extraction'
Expand-NorikoArchive -ArchivePath $archivePath -DestinationPath $goodDestination -ExpectedHash $expectedHash
Assert-ExtractedKit $goodDestination
Write-Host 'PASS: real ZIP; 56 exact files; four UTF-8 Japanese filenames; P21.'

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

# Exercise the real CMD without changing HOME or USERPROFILE. The helper uses the runner's own profile.
$specialDirectory = Join-Path $testRoot "日本語 download's !"
$null = New-Item -ItemType Directory -Path $specialDirectory -ErrorAction Stop
$specialCommand = Join-Path $specialDirectory "AI NORIKO 日本語's ! Setup.cmd"
[IO.File]::Copy($commandPath, $specialCommand, $false)
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
        Assert-True ($process.ExitCode -eq 0) ('Real CMD failed; check the published ZIP/hash and network. Exit: ' + $process.ExitCode)
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
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $runPath 'AI-NORIKO-Starter-Kit.zip') -Algorithm SHA256).Hash -eq $expectedHash) 'The public ZIP differs from the reviewed kit.'
    Assert-ExtractedKit $extractedPath
    Write-NewText (Join-Path $runPath 'ci-preserve-sentinel.txt') 'preserve-earlier-run'
    Write-Host ('PASS: real CMD run ' + $attempt + '; exit 0; NEXT-STEPS; exact kit; special-character download path.')
}
foreach ($runPath in $createdRuns) {
    Assert-True ([IO.File]::ReadAllText((Join-Path $runPath 'ci-preserve-sentinel.txt'), $utf8) -ceq 'preserve-earlier-run') 'A later run modified an earlier run.'
    Assert-ExtractedKit (Join-Path $runPath 'files')
}
Assert-True ($env:USERPROFILE -ceq $originalUserProfile -and $HOME -ceq $originalHome) 'The test changed HOME or USERPROFILE.'
Assert-True ((Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash -eq $sentinelHash) 'The original sentinel changed.'
Write-Host 'PASS: two distinct fresh destinations; all prior files preserved. No cleanup or application installation performed.'
Write-Host ('Test fixtures retained for runner teardown: ' + $testRoot)
