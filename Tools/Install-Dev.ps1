param([switch]$DryRun, [switch]$SkipBackup)
. (Join-Path $PSScriptRoot 'Common.ps1')
$info = Get-XQAddonInfo
$addons = Get-XQGameAddonsPath
$target = Join-Path $addons 'XenQuest'
$sourceAbsolute = [System.IO.Path]::GetFullPath($info.Source).TrimEnd('\', '/')
$targetAbsolute = [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
if ($sourceAbsolute -eq $targetAbsolute) { throw 'The development folder cannot be the game AddOns folder.' }

Write-Host "SOURCE: $($info.Source)" -ForegroundColor Cyan
Write-Host "TARGET: $target"
Write-Host "VERSION: $($info.Version)"
if ($DryRun) {
    Write-Host 'Dry run: no files will be copied or deleted.' -ForegroundColor Yellow
    & robocopy.exe $info.Source $target /MIR /L /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "Robocopy dry-run failed: $LASTEXITCODE" }
    return
}

# Backup only the named XenQuest folder, never the entire WoW directory.
# /MIR deletes obsolete files in TARGET, so make a backup first by default.
if ((Test-Path -LiteralPath $target -PathType Container) -and -not $SkipBackup) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $backups = Join-Path $info.Root 'Backups'
    New-Item -ItemType Directory -Path $backups -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupZip = Join-Path $backups "XenQuest-before-install-$stamp.zip"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($target, $backupZip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    Write-Host "Previous install backed up: $backupZip"
}

# WARNING: /MIR mirrors the project addon folder and deletes stale target-only files.
# All SavedVariables are in WTF, not inside Interface\AddOns\XenQuest.
& robocopy.exe $info.Source $target /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "WoW install sync failed: Robocopy exit code $LASTEXITCODE" }
Write-Host 'XenQuest synced successfully. Use /reload in WoW to apply the changes.' -ForegroundColor Green
