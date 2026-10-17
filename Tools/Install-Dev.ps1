param([switch]$DryRun, [switch]$SkipBackup)
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Local-Toc.ps1')

$info = Get-XQAddonInfo
$effective = Get-XQEffectiveToc -AddonInfo $info
$addons = Get-XQGameAddonsPath
$target = Join-Path $addons 'XenQuest'
$sourceAbsolute = [System.IO.Path]::GetFullPath($info.Source).TrimEnd('\', '/')
$targetAbsolute = [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
if ($sourceAbsolute -eq $targetAbsolute) { throw 'The development folder cannot be the game AddOns folder.' }

Write-Host "SOURCE: $($info.Source)" -ForegroundColor Cyan
Write-Host "TARGET: $target"
Write-Host "VERSION: $($info.Version) | LOCAL DATA MODULES: $($effective.OptionalCount)"

# TOC is generated separately: exclude only this one file from Robocopy to
# keep the dry run accurate even when local optional datasets are present.
$gameToc = Join-Path $target 'XenQuest.toc'
if ($DryRun) {
    Write-Host 'Dry run: no files will be copied or deleted.' -ForegroundColor Yellow
    & robocopy.exe $info.Source $target /MIR /L /XF XenQuest.toc /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "Robocopy dry-run failed: $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $gameToc -PathType Leaf) -or
        (Get-Content -LiteralPath $gameToc -Raw) -ne $effective.Text) {
        Write-Host 'TOC: would refresh the generated game manifest.' -ForegroundColor Yellow
    }
    return
}

# /MIR deletes target-only files. Always make a backup before changing the install.
if ((Test-Path -LiteralPath $target -PathType Container) -and -not $SkipBackup) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $backups = Join-Path $info.Root 'Backups'
    New-Item -ItemType Directory -Path $backups -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupZip = Join-Path $backups "XenQuest-before-install-$stamp.zip"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($target, $backupZip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    Write-Host "Previous install backed up: $backupZip"
}

& robocopy.exe $info.Source $target /MIR /XF XenQuest.toc /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "WoW install sync failed: Robocopy exit code $LASTEXITCODE" }

# Only the WoW installation receives the local/extended manifest.
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($gameToc, $effective.Text, $utf8NoBom)
Write-Host "XenQuest synced successfully ($($effective.LuaFiles) Lua modules). Use /reload in WoW." -ForegroundColor Green
