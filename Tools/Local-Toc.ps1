# Generate the effective manifest WITHOUT changing the Git-tracked XenQuest.toc.
# Third-party-derived guidance datasets exist only in local developer installs.
Set-StrictMode -Version Latest

function Get-XQEffectiveToc {
    param([Parameter(Mandatory=$true)]$AddonInfo)

    $lines = @(Get-Content -LiteralPath $AddonInfo.Toc)
    $optional = @(
        'Data/BulkGuidance.lua',
        'Data/QuestContext.lua'
    )
    $extra = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relative in $optional) {
        $absolute = Join-Path $AddonInfo.Source ($relative.Replace('/', '\'))
        if (Test-Path -LiteralPath $absolute -PathType Leaf) {
            $extra.Add($relative)
        }
    }

    # Never allow the committed/base TOC to reference files Git intentionally excludes.
    foreach ($line in $lines) {
        if ($optional -contains $line.Trim()) {
            throw 'The source XenQuest.toc must NOT list local-only BulkGuidance.lua or QuestContext.lua. They are inserted automatically during install and packaging.'
        }
    }

    $result = New-Object 'System.Collections.Generic.List[string]'
    $inserted = $false
    foreach ($line in $lines) {
        if ($line.Trim() -eq 'ObjectiveGuidance.lua') {
            foreach ($entry in $extra) { $result.Add($entry) }
            $inserted = $true
        }
        $result.Add($line)
    }
    if (-not $inserted) {
        throw 'Cannot generate TOC: ObjectiveGuidance.lua was not found in XenQuest.toc.'
    }

    # Use consistent CRLF in game, no BOM (compatible with WoW's TOC loader).
    $text = ($result.ToArray() -join "`r`n") + "`r`n"
    $count = @($result | Where-Object { $_.Trim() -match '^[^#].*\.lua$' }).Count
    return [PSCustomObject]@{
        Text = $text
        OptionalCount = $extra.Count
        LuaFiles = $count
    }
}
