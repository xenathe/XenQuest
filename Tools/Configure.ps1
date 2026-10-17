. (Join-Path $PSScriptRoot 'Common.ps1')
$info = Get-XQAddonInfo
Write-Host "XenQuest development project: $($info.Root)" -ForegroundColor Cyan
Write-Host "Addon version: $($info.Version)"
Write-Host ''
Write-Host 'Enter the full path to the AddOns directory for the WoW client you actually play.'
Write-Host 'Example: C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns'
$inputPath = (Read-Host 'WoW AddOns folder').Trim().Trim('"')
if (-not $inputPath) { throw 'No path entered; configuration was not changed.' }
$resolved = [System.IO.Path]::GetFullPath($inputPath).TrimEnd('\', '/')
if ((Split-Path -Path $resolved -Leaf) -ne 'AddOns') { throw 'Please specify the AddOns directory itself.' }
if (-not (Test-Path -LiteralPath $resolved -PathType Container)) { throw "Directory not found: $resolved" }
@{ addonsPath = $resolved } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $info.Root 'dev.local.json') -Encoding UTF8
Write-Host ''
Write-Host "Saved local game location: $resolved" -ForegroundColor Green
Write-Host 'Next: double-click 02-Install-to-WoW.cmd whenever you want to test.'
