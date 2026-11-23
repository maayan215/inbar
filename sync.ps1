# Pulls the public Google Photos album and writes photos.js (loaded by index.html).
# Run manually, via serve.ps1 (auto, every 24h) or via install-daily-sync.ps1 (Task Scheduler).
param([string]$Out = (Join-Path $PSScriptRoot 'photos.js'))

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# The album share link is NOT stored in this file (it would be public on GitHub). It comes from:
#   1) the ALBUM_URL environment variable (GitHub Actions secret), or
#   2) a local, git-ignored file next to this script: album-url.txt
$albumUrl = $env:ALBUM_URL
if (-not $albumUrl) {
    $f = Join-Path $PSScriptRoot 'album-url.txt'
    if (Test-Path $f) { $albumUrl = (Get-Content $f -Raw).Trim() }
}
if (-not $albumUrl) { throw 'Album link not found. Put the Google Photos share link in album-url.txt (or set the ALBUM_URL environment variable / GitHub secret).' }

$html = (Invoke-WebRequest -Uri $albumUrl -UseBasicParsing -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36').Content

# item shape: ["AF1Qip...id",["https://lh3.googleusercontent.com/pw/...",width,height, ...
$rx = [regex]'\["(AF1Qip[A-Za-z0-9_\-]+)",\["(https://lh3\.googleusercontent\.com/pw/[^"]+)",(\d+),(\d+)'
$seen = @{}
$ms = $rx.Matches($html)
$photos = for ($k = 0; $k -lt $ms.Count; $k++) {
    $m = $ms[$k]
    $id = $m.Groups[1].Value
    if ($seen.ContainsKey($id)) { continue }
    $seen[$id] = 1
    # capture time follows the media block:  ...]]],<takenMs>,"<token>",<tzOffsetMs>,<uploadedMs>
    $end = if ($k + 1 -lt $ms.Count) { $ms[$k + 1].Index } else { [Math]::Min($html.Length, $m.Index + 2500) }
    $seg = $html.Substring($m.Index, $end - $m.Index)
    $d = [regex]::Match($seg, '\]+,(\d{12,13}),"[^"]*",(-?\d+)')
    $p = [ordered]@{ id = $id; url = $m.Groups[2].Value; w = [int]$m.Groups[3].Value; h = [int]$m.Groups[4].Value }
    if ($d.Success) { $p['taken'] = [int64]$d.Groups[1].Value; $p['tz'] = [int64]$d.Groups[2].Value }
    $p
}

if (-not $photos -or @($photos).Count -eq 0) { throw 'No photos found - album page format may have changed. Existing photos.js left untouched.' }

$payload = [ordered]@{
    updated = (Get-Date).ToUniversalTime().ToString('o')
    count   = @($photos).Count
    photos  = @($photos)
}
$json = $payload | ConvertTo-Json -Depth 5 -Compress
[IO.File]::WriteAllText($Out, "window.ALBUM=$json;", (New-Object Text.UTF8Encoding $false))
Write-Host "Synced $(@($photos).Count) photos -> $Out"
