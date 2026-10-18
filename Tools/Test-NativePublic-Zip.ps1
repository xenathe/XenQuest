param([string]$ZipPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $ZipPath) {
    $info = Get-XQAddonInfo
    $ZipPath = Join-Path $info.Root "Versions\XenQuest-v$($info.Version).zip"
}
$ZipPath = [System.IO.Path]::GetFullPath($ZipPath)
if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw "ZIP not found: $ZipPath" }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    $names = @($archive.Entries | Where-Object { $_.FullName -and -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName })
    if ($names -notcontains 'XenQuest/XenQuest.toc' -or $names -notcontains 'XenQuest/NativeLearning.lua') {
        throw 'Not a native-only XenQuest package.'
    }
    foreach ($name in $names) {
        if (-not $name.StartsWith('XenQuest/') -or $name.Contains('\') -or $name.Contains('../') -or $name.Contains(':')) {
            throw "Invalid ZIP path: $name"
        }
    }
    foreach ($name in @('XenQuest/Data/BulkGuidance.lua','XenQuest/Data/QuestContext.lua',
                         'XenQuest/Data/TargetMarkerData.lua','XenQuest/Media/custom.ttf',
                         'XenQuest/Media/QuestTargetSkull.tga')) {
        if ($names -contains $name) { throw "Native-only test ZIP includes excluded file: $name" }
    }
}
finally { $archive.Dispose() }
$addons = Get-XQGameAddonsPath
$dest = Join-Path $addons 'XenQuest'
$root = Get-XQRoot
if (Test-Path -LiteralPath $dest -PathType Container) {
    $backups = Join-Path $root 'Backups'
    New-Item -ItemType Directory -Path $backups -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backup = Join-Path $backups "XenQuest-before-native-zip-test-$timestamp.zip"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($dest,$backup,[System.IO.Compression.CompressionLevel]::Optimal,$true)
    Write-Host "Backed up previous installed addon to $backup"
    Remove-Item -LiteralPath $dest -Recurse -Force
}
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath,$addons)
Write-Host 'NATIVE-ONLY ZIP INSTALLED. Restart WoW or type /reload. WoW SavedVariables are unaffected.' -ForegroundColor Green
Write-Host 'Do NOT run 02-Install-to-WoW.cmd before this test; it re-installs your local developer datasets.' -ForegroundColor Yellow
