param(
    [switch]$Public,
    [switch]$Force,
    [switch]$NativeOnly
)
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Local-Toc.ps1')

$info = Get-XQAddonInfo
if ($NativeOnly -and -not $Public) {
    throw 'NativeOnly is a public-archive packaging mode. Specify both -Public -NativeOnly.'
}

# These files must never leave this development workspace in a native-only ZIP.
$privateData = @(
    'Data/BulkGuidance.lua',
    'Data/QuestContext.lua',
    'Data/TargetMarkerData.lua'
)

# Curated release assets: arbitrary files appearing in the addon directory are
# not implicitly suitable for redistribution.
$publicLua = @(
    'QuestItems.lua', 'QuestItemButtons.lua', 'BlizzardUI.lua',
    'Navigation.lua', 'Data/QuestGuidance.lua', 'NativeLearning.lua',
    'ObjectiveGuidance.lua', 'TargetMarkers.lua', 'TooltipProbe.lua', 'Core.lua'
)
$publicMedia = @(
    'Media/CUSTOM_FONT_README.txt',
    'Media/CompletionShimmer.tga',
    'Media/NavigationArrow3D.tga',
    'Media/NavigationArrowIso.tga',
    'Media/NavigationArrowIso64.tga',
    'Media/NavigationArrowIso64Ice.tga',
    'Media/QuestRing.tga',
    'Media/QuestTargetSword.tga',
    'Media/RoundedCorner.tga',
    'Media/SettingsGear.tga',
    'Media/TrackedArrowGold.tga',
    'Media/TrackedArrowIce.tga',
    'Media/TrackedArrowPremiumGold.tga',
    'Media/TrackedArrowPremiumIce.tga',
    'Media/XenQuestLogo.tga'
)
$publicDocs = @('LICENSE', 'README.md', 'README.txt', 'RELEASE_NOTES.md',
    'CHANGES.txt', 'DATA_PROVENANCE.md')
$publicAllowlist = @('XenQuest.toc') + $publicLua + $publicMedia + $publicDocs
$excludedLocalFiles = $privateData + @('THIRD_PARTY_DATA_REVIEW.md','Media/custom.ttf','Media/QuestTargetSkull.tga')

$warning = Get-XQPublicationWarning
if ($Public -and -not $NativeOnly -and $warning) {
    throw "PUBLIC PACKAGE BLOCKED: $warning"
}

if ($NativeOnly) {
    $rawToc = Get-Content -LiteralPath $info.Toc -Raw
    $tocLua = @($rawToc -split "`r?`n" | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^[^#].*\.lua$' })
    if ($tocLua.Count -ne $publicLua.Count) {
        throw "Native-only TOC must declare the $($publicLua.Count) audited modules; got $($tocLua.Count)."
    }
    for ($i = 0; $i -lt $publicLua.Count; $i++) {
        if ($tocLua[$i] -cne $publicLua[$i]) {
            throw "Native-only TOC module order is unreviewed at index $i ($($tocLua[$i]))."
        }
    }
    foreach ($blocked in $privateData) {
        if ($rawToc.Contains($blocked)) { throw "Native-only TOC references excluded data: $blocked" }
    }
    # Use the BASE manifest. The local installer intentionally inserts the
    # third-party modules for development; it must NOT do that here.
    $effective = [PSCustomObject]@{
        Text = ($rawToc -replace "`r?`n", "`r`n").TrimEnd() + "`r`n"
        LuaFiles = $tocLua.Count
        OptionalCount = 0
    }
} else {
    $effective = Get-XQEffectiveToc -AddonInfo $info
}

$versions = Join-Path $info.Root 'Versions'
New-Item -ItemType Directory -Path $versions -Force | Out-Null
$suffix = if ($Public) { '' } else { '-LOCAL-TEST' }
$filename = "XenQuest-v$($info.Version)$suffix.zip"
$output = Join-Path $versions $filename
$hashPath = "$output.sha256.txt"
$tempPath = Join-Path $versions ('.' + $filename + '.building')
if ((Test-Path -LiteralPath $output) -and -not $Force) {
    throw "Package already exists: $output. Update the version, or use -Force to rebuild."
}
if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }

$prefix = $info.Source.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$sourceFiles = @(Get-ChildItem -LiteralPath $info.Source -Recurse -File -Force)
$selected = New-Object 'System.Collections.Generic.List[object]'
$seen = @{}
foreach ($file in $sourceFiles) {
    if (-not $file.FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "File is outside addon folder: $($file.FullName)"
    }
    $relative = $file.FullName.Substring($prefix.Length).Replace('\', '/')
    if (-not $relative -or $relative.StartsWith('/') -or $relative.Contains('..') -or $relative.Contains(':')) {
        throw "Unsafe archive path: $relative"
    }
    if ($NativeOnly) {
        if ($excludedLocalFiles -contains $relative) { continue }
        if ($publicAllowlist -notcontains $relative) {
            throw "Native-only package blocked: unreviewed addon file $relative. Review the file and update the release allowlist intentionally."
        }
    }
    if ($seen.ContainsKey($relative.ToLowerInvariant())) { throw "Duplicate archive path: $relative" }
    $seen[$relative.ToLowerInvariant()] = $true
    $selected.Add([PSCustomObject]@{ File=$file; Relative=$relative })
}
if ($NativeOnly) {
    foreach ($required in $publicAllowlist) {
        if (-not $seen.ContainsKey($required.ToLowerInvariant())) {
            throw "Native-only public asset missing: $required"
        }
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = $null
try {
    $archive = [System.IO.Compression.ZipFile]::Open($tempPath, [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($item in $selected) {
        $entryName = 'XenQuest/' + $item.Relative
        if ($item.Relative -ieq 'XenQuest.toc') {
            $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            $writer = [System.IO.StreamWriter]::new($entry.Open(), $utf8NoBom)
            try { $writer.Write($effective.Text) } finally { $writer.Dispose() }
        } else {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $item.File.FullName, $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    $archive.Dispose(); $archive = $null

    $archive = [System.IO.Compression.ZipFile]::OpenRead($tempPath)
    $entries = @($archive.Entries | Where-Object { $_.FullName -and -not $_.FullName.EndsWith('/') })
    if ($entries.Count -lt $effective.LuaFiles) { throw 'ZIP is missing source files.' }
    foreach ($entry in $entries) {
        if (-not $entry.FullName.StartsWith('XenQuest/') -or $entry.FullName.Contains('\')) {
            throw "Invalid ZIP entry: $($entry.FullName)"
        }
        if ($NativeOnly -and $publicAllowlist -notcontains $entry.FullName.Substring(9)) {
            throw "Native-only ZIP has unapproved entry: $($entry.FullName)"
        }
    }
    foreach ($line in $effective.Text -split "`r?`n") {
        $name = $line.Trim()
        if ($name -match '^[^#].*\.lua$' -and
            -not @($entries | Where-Object { $_.FullName -ceq ('XenQuest/' + $name) }).Count) {
            throw "TOC Lua not in ZIP: $name"
        }
    }
    if ($NativeOnly) {
        foreach ($blocked in $privateData) {
            if (@($entries | Where-Object { $_.FullName -eq ('XenQuest/' + $blocked) }).Count -gt 0) {
                throw "Excluded dataset leaked into ZIP: $blocked"
            }
        }
        if (@($entries | Where-Object { $_.FullName -eq 'XenQuest/Media/custom.ttf' }).Count -gt 0) {
            throw 'Unlicensed optional font leaked into ZIP.'
        }
    }
    $count = $entries.Count
    $archive.Dispose(); $archive = $null

    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
    Move-Item -LiteralPath $tempPath -Destination $output
    if (Test-Path -LiteralPath $hashPath) { Remove-Item -LiteralPath $hashPath -Force }
    $sha = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    "$sha  $filename" | Set-Content -LiteralPath $hashPath -Encoding ASCII
    Write-Host "PACKAGE: $output" -ForegroundColor Green
    Write-Host "VERSION: $($info.Version) | FILES: $count | TOC Lua entries: $($effective.LuaFiles)"
    Write-Host "SHA256: $sha"
    if ($NativeOnly) {
        Write-Host 'NATIVE-ONLY PACKAGE. Derived QuestieDB datasets were excluded.' -ForegroundColor Green
        Write-Host 'Test this exact archive in WoW Forever and verify artwork rights before publishing.' -ForegroundColor Yellow
    } elseif (-not $Public) {
        Write-Host 'LOCAL TEST PACKAGE — not designated as a public release.' -ForegroundColor Yellow
    }
    if ($warning -and -not $NativeOnly) { Write-Host $warning -ForegroundColor Yellow }
}
finally {
    if ($null -ne $archive) { $archive.Dispose() }
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
}
