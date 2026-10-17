param([switch]$Public, [switch]$Force)
. (Join-Path $PSScriptRoot 'Common.ps1')

$info = Get-XQAddonInfo
$versions = Join-Path $info.Root 'Versions'
New-Item -ItemType Directory -Path $versions -Force | Out-Null

$warning = Get-XQPublicationWarning
if ($Public -and $warning) { throw "PUBLIC PACKAGE BLOCKED: $warning" }

# Local builds must not be mistaken for public releases.
$suffix = if ($Public) { '' } else { '-LOCAL-TEST' }
$filename = "XenQuest-v$($info.Version)$suffix.zip"
$output = Join-Path $versions $filename
$hashPath = "$output.sha256.txt"
$tempPath = Join-Path $versions ("." + $filename + ".building")

if ((Test-Path -LiteralPath $output) -and -not $Force) {
    throw "Package already exists: $output. Update ## Version in XenQuest.toc, or pass -Force to rebuild the current version."
}

# Build to a temporary file first so validation cannot leave a broken release ZIP.
if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = $null
try {
    # Explicit entry names avoid Windows .NET Framework producing backslash-based ZIP paths.
    $sourcePrefix = $info.Source.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $sourceFiles = @(Get-ChildItem -LiteralPath $info.Source -Recurse -File -Force)
    if ($sourceFiles.Count -lt $info.LuaFiles) { throw 'Source contains fewer files than the TOC Lua entries.' }

    $archive = [System.IO.Compression.ZipFile]::Open($tempPath, [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($file in $sourceFiles) {
        if (-not $file.FullName.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "File is outside addon source: $($file.FullName)"
        }
        $relative = $file.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
        if (-not $relative -or $relative.StartsWith('/') -or $relative.Contains('../')) {
            throw "Unsafe archive entry: $relative"
        }
        $entryName = 'XenQuest/' + $relative
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
    $archive.Dispose()
    $archive = $null

    # Check the finished archive before replacing an existing ZIP.
    $archive = [System.IO.Compression.ZipFile]::OpenRead($tempPath)
    $entries = @($archive.Entries | Where-Object { $_.FullName -and -not $_.FullName.EndsWith('/') })
    if ($entries.Count -lt $info.LuaFiles) { throw 'Package contains fewer files than expected.' }
    if (@($entries | Where-Object { -not $_.FullName.StartsWith('XenQuest/') }).Count -gt 0) {
        throw 'Wrong ZIP structure: addon files must be inside XenQuest/.'
    }
    if (-not @($entries | Where-Object { $_.FullName -eq 'XenQuest/XenQuest.toc' }).Count) {
        throw 'Packaged ZIP is missing XenQuest/XenQuest.toc.'
    }
    if (@($entries | Where-Object { $_.FullName.Contains('\') }).Count -gt 0) {
        throw 'Wrong ZIP structure: backslashes are not valid entry separators.'
    }
    $numberOfFiles = $entries.Count
    $archive.Dispose()
    $archive = $null

    # Only now replace an earlier build (when -Force is supplied).
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
    Move-Item -LiteralPath $tempPath -Destination $output
    if (Test-Path -LiteralPath $hashPath) { Remove-Item -LiteralPath $hashPath -Force }
    $sha = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    "$sha  $filename" | Set-Content -LiteralPath $hashPath -Encoding ASCII

    Write-Host "PACKAGE: $output" -ForegroundColor Green
    Write-Host "VERSION: $($info.Version) | FILES: $numberOfFiles | TOC Lua entries: $($info.LuaFiles)"
    Write-Host "SHA256: $sha"
    if (-not $Public) { Write-Host 'LOCAL TEST PACKAGE — not designated as a public release.' -ForegroundColor Yellow }
    if ($warning) { Write-Host $warning -ForegroundColor Yellow }
}
finally {
    if ($null -ne $archive) { $archive.Dispose() }
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
}
