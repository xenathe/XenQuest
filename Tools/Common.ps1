Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-XQRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Get-XQAddonInfo {
    $root = Get-XQRoot
    $source = Join-Path $root 'XenQuest'
    $toc = Join-Path $source 'XenQuest.toc'
    if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) {
        throw "Cannot find $toc. Extract your latest addon ZIP so the project contains XenQuest\XenQuest.toc."
    }

    $manifest = Get-Content -LiteralPath $toc -Raw
    if ($manifest -notmatch '(?m)^##\s*Version\s*:\s*([^\r\n]+)') {
        throw 'Missing ## Version: entry in XenQuest.toc.'
    }
    $version = $Matches[1].Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') {
        throw "Unexpected version '$version'. Set a version such as 0.2.13-beta in XenQuest.toc."
    }

    $luaPaths = @($manifest -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[^#].*\.lua$' })
    if ($luaPaths.Count -eq 0) { throw 'No Lua files listed in XenQuest.toc.' }
    foreach ($relative in $luaPaths) {
        if ($relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe manifest path: $relative" }
        $file = Join-Path $source ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Missing Lua file referenced by the TOC: $relative"
        }
    }

    return [PSCustomObject]@{ Root = $root; Source = $source; Toc = $toc; Version = $version; LuaFiles = $luaPaths.Count }
}

function Get-XQGameAddonsPath {
    $root = Get-XQRoot
    $settingsPath = Join-Path $root 'dev.local.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        throw 'Missing dev.local.json. Double-click 01-Configure.cmd once to select your WoW AddOns folder.'
    }
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if (-not $settings.addonsPath) { throw 'dev.local.json does not contain addonsPath.' }
    $addonsPath = [System.IO.Path]::GetFullPath([string]$settings.addonsPath).TrimEnd('\', '/')
    if ((Split-Path -Path $addonsPath -Leaf) -ne 'AddOns') {
        throw "Refusing unsafe destination. Configure an Interface\AddOns directory, not $addonsPath."
    }
    if (-not (Test-Path -LiteralPath $addonsPath -PathType Container)) {
        throw "Configured game AddOns directory does not exist: $addonsPath"
    }
    return $addonsPath
}

function Get-XQPublicationWarning {
    $root = Get-XQRoot
    $source = Join-Path $root 'XenQuest'
    $review = Join-Path $source 'THIRD_PARTY_DATA_REVIEW.md'
    $generatedPresent = (Test-Path -LiteralPath (Join-Path $source 'Data\BulkGuidance.lua') -PathType Leaf) -or
                        (Test-Path -LiteralPath (Join-Path $source 'Data\QuestContext.lua') -PathType Leaf) -or
                        (Test-Path -LiteralPath (Join-Path $source 'Data\TargetMarkerData.lua') -PathType Leaf)
    $unresolvedNotice = $false
    if (Test-Path -LiteralPath $review -PathType Leaf) {
        $unresolvedNotice = (Get-Content -LiteralPath $review -Raw) -match '(?i)NOT CLEARED FOR PUBLIC REDISTRIBUTION|NOT CLEARED'
    }
    $approvalPath = Join-Path $root 'Docs\DATA_RIGHTS_CLEARANCE.txt'
    $approved = (Test-Path -LiteralPath $approvalPath -PathType Leaf) -and
                ((Get-Content -LiteralPath $approvalPath -Raw) -match '(?m)^CLEARED=YES\s*$')
    if ($unresolvedNotice -or ($generatedPresent -and -not $approved)) {
        return 'The bundled QuestieDB-derived guidance/target data has not been documented as cleared for public redistribution. Local testing is allowed; public packaging is blocked. See Docs\RELEASE_PROCESS.md.'
    }
    return $null
}
