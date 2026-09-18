@echo off
setlocal DisableDelayedExpansion
set "AI_NORIKO_EXTRACTOR=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "$text = [IO.File]::ReadAllText($env:AI_NORIKO_EXTRACTOR, [Text.Encoding]::UTF8); & ([ScriptBlock]::Create(($text -split '(?m)^# POWERSHELL_PAYLOAD\r?$', 2)[1]))"
set "AI_NORIKO_EXIT=%ERRORLEVEL%"
if "%AI_NORIKO_SETUP_NONINTERACTIVE%"=="1" exit /b %AI_NORIKO_EXIT%
echo.
pause
exit /b %AI_NORIKO_EXIT%
# POWERSHELL_PAYLOAD
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding

# This helper only downloads/extracts data. It never executes files from the ZIP.
function Expand-NorikoArchive {
    param([string]$ArchivePath, [string]$DestinationPath, [string]$ExpectedHash)
    if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'ZIPの照合に失敗しました。講義ページから補助ファイルを再ダウンロードしてください。'
    }
    if (Test-Path -LiteralPath $DestinationPath) { throw '展開先が既にあります。上書きせず停止しました。' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [IO.Path]::GetFullPath($DestinationPath).TrimEnd('\') + '\'
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -eq 0 -or $archive.Entries.Count -gt 1000) { throw 'ZIPの構成が想定と異なります。' }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        [long]$total = 0
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if (-not $name.StartsWith('AI-NORIKO-Starter-Kit/', [StringComparison]::Ordinal) -or
                $name -match '(^|/)\.{1,2}(/|$)' -or $name -match '[:\x00-\x1f<>"|?*]' -or $name.Contains('//')) {
                throw 'ZIP内に不正なパスがあります。展開を中止しました。'
            }
            foreach ($part in $name.TrimEnd('/').Split('/')) {
                if ($part -match '[ .]$' -or $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') {
                    throw 'Windowsで使用できないファイル名があります。'
                }
            }
            if ((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000) { throw 'リンク形式のファイルは展開しません。' }
            $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $name.Replace('/', '\')))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or $target.Length -ge 240) {
                throw '展開先のパスが長すぎるか不正です。講師に確認してください。'
            }
            if (-not $seen.Add($target.TrimEnd('\'))) { throw 'ZIP内に重複ファイルがあります。' }
            $total += $entry.Length
            if ($total -gt 100MB) { throw 'ZIPの展開サイズが想定を超えています。' }
        }
        foreach ($required in @('package.json', 'START_HERE.md', 'START-WINDOWS.bat', 'src/App.tsx')) {
            $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, 'AI-NORIKO-Starter-Kit', $required))
            if (-not $seen.Contains($target)) { throw 'アプリ本体の必須ファイルがありません。' }
        }
        [void][IO.Directory]::CreateDirectory($DestinationPath)
        foreach ($entry in $archive.Entries) {
            $target = [IO.Path]::Combine($root, $entry.FullName.Replace('/', '\'))
            if ($entry.FullName.EndsWith('/')) {
                [void][IO.Directory]::CreateDirectory($target)
                continue
            }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $inputStream = $entry.Open()
            try {
                $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
                try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
            } finally { $inputStream.Dispose() }
        }
    } finally { $archive.Dispose() }
}

function Start-NorikoDownload {
    $stage = '準備'
    $runPath = $null
    try {
        if ($PSVersionTable.PSVersion -lt [Version]'5.1') { throw 'Windows PowerShell 5.1以上が必要です。' }
        Write-Host 'AI NORIKO / Windows用 ダウンロード・展開' -ForegroundColor Cyan
        Write-Host '行うこと：講義サイトからZIPを取得・照合・新しいフォルダに展開します。'
        Write-Host 'アプリ起動、追加ソフト導入、ログイン、既存ファイルの変更はしません。'
        $profilePath = [Environment]::GetFolderPath('UserProfile')
        if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) {
            throw 'ユーザーフォルダを確認できません。'
        }
        $runName = 'AI-NORIKO-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
        $runPath = Join-Path $profilePath $runName
        if (Test-Path -LiteralPath $runPath) { throw '同名フォルダがあります。上書きせず停止しました。' }
        $null = New-Item -ItemType Directory -Path $runPath -ErrorAction Stop
        $zipPath = Join-Path $runPath 'AI-NORIKO-Starter-Kit.zip'
        $extractPath = Join-Path $runPath 'files'
        $stage = 'ダウンロード'
        Write-Host '[1/3] キットをダウンロードしています。'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri 'https://ahaha48.github.io/ai-noriko-class/downloads/releases/1.2.0/9c4efcee8b26/AI-NORIKO-Starter-Kit.zip' -OutFile $zipPath -TimeoutSec 120
        $stage = '照合・展開'
        Write-Host '[2/3] ファイルを照合し、安全な新規フォルダに展開しています。'
        Expand-NorikoArchive -ArchivePath $zipPath -DestinationPath $extractPath -ExpectedHash '9c4efcee8b269e4ab8f90c7226d9686839b89b0f6517bd91938e459f8ba07d73'
        $kitPath = Join-Path $extractPath 'AI-NORIKO-Starter-Kit'
        $stage = '次の手順の保存'
        [IO.File]::WriteAllText((Join-Path $runPath 'NEXT-STEPS.txt'), "Codexで開くフォルダ：`r`n$kitPath`r`n`r`nそのプロジェクトのチャットへP01を送ります。`r`nhttps://ahaha48.github.io/ai-noriko-class/#P01`r`n", (New-Object Text.UTF8Encoding($true)))
        Write-Host '[3/3] 展開が完了しました。' -ForegroundColor Green
        Write-Host ''
        Write-Host '次：Codexの「プロジェクトを追加」で、以下のフォルダを選びます。'
        Write-Host $kitPath -ForegroundColor Cyan
        Write-Host 'そのプロジェクトのチャットへ、講義ページのP01を貼り付けてください。'
        Write-Host '展開の完了です。AI NORIKOの初回セットアップはP01で行います。'
        if ($env:AI_NORIKO_SETUP_NONINTERACTIVE -ne '1') {
            try { Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"' + $kitPath + '"') }
            catch { Write-Host 'フォルダ表示ができませんでした。上の保存先をエクスプローラーで開いてください。' }
        }
        return 0
    } catch {
        Write-Host ''
        Write-Host ('停止した段階：' + $stage) -ForegroundColor Yellow
        Write-Host $_.Exception.Message
        Write-Host '保護設定を解除したり、管理者として強行実行せず、講師にこの画面を伝えてください。'
        Write-Host 'ネット接続を確認するか、講義ページの通常のZIPから手動展開してください。'
        if ($runPath) { Write-Host ('今回の保存先（途中のファイルは残します）：' + $runPath) }
        return 1
    }
}

exit (Start-NorikoDownload)
