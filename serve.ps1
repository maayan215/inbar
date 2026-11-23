# Tiny local web server for the site. Whenever photos.js is requested and is older than
# 24 hours, it re-syncs the Google Photos album first - so the site updates itself daily
# for as long as this script is running.
#   Normal:            powershell -ExecutionPolicy Bypass -File serve.ps1
#   Phone on same Wi-Fi: run PowerShell AS ADMINISTRATOR, then
#                        powershell -ExecutionPolicy Bypass -File serve.ps1 -Lan
#                      (first time only, also allow the port through the firewall:
#                        netsh advfirewall firewall add rule name="Inbar site" dir=in action=allow protocol=TCP localport=8080)
param([int]$Port = 8080, [int]$MaxAgeHours = 24, [switch]$Lan)

$root = $PSScriptRoot
$photos = Join-Path $root 'photos.js'
$mime = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
    '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.svg' = 'image/svg+xml'; '.json' = 'application/json'
    '.ico' = 'image/x-icon'; '.woff2' = 'font/woff2'
}

function Update-IfStale {
    if (-not (Test-Path $photos) -or ((Get-Date) - (Get-Item $photos).LastWriteTime).TotalHours -ge $MaxAgeHours) {
        try { & (Join-Path $root 'sync.ps1') } catch { Write-Warning "Album sync failed, serving last known photos: $_" }
    }
}

Update-IfStale
$listener = New-Object Net.HttpListener
$listener.Prefixes.Add($(if ($Lan) { "http://+:$Port/" } else { "http://localhost:$Port/" }))
try { $listener.Start() } catch {
    $ex = $_.Exception; if ($ex.InnerException) { $ex = $ex.InnerException }
    $code = if ($ex -is [Net.HttpListenerException]) { $ex.ErrorCode } else { 0 }
    Write-Host "Could not start the web server on port $Port." -ForegroundColor Yellow
    Write-Host "  Reason: $($ex.Message)  (code $code)" -ForegroundColor Yellow
    switch ($code) {
        5   { Write-Host "  -> Access denied: open PowerShell 'as Administrator' (needed for -Lan)." }
        183 { Write-Host "  -> That port is already used by another copy of this site or another program. Close it, or pick another port, e.g.  -Port 8081  (and allow 8081 in the firewall)." }
        32  { Write-Host "  -> That port is already in use. Close the other program, or pick another port, e.g.  -Port 8081." }
        default { Write-Host "  -> Try a different port, e.g.  -Port 8081  (and allow it in the firewall)." }
    }
    exit 1
}
Write-Host "Serving $root  (album re-syncs every $MaxAgeHours h)"
Write-Host "  On this PC:  http://localhost:$Port/"
if ($Lan) {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -ExpandProperty IPAddress
    foreach ($ip in $ips) { Write-Host "  On your phone (same Wi-Fi):  http://${ip}:$Port/" -ForegroundColor Green }
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try {
            $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
            if ($rel -eq '') { $rel = 'index.html' }
            if ($rel -eq 'photos.js') { Update-IfStale }
            $file = [IO.Path]::GetFullPath((Join-Path $root $rel))
            if ($file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $file -PathType Leaf) -and ($rel -notmatch '\.ps1$')) {
                $bytes = [IO.File]::ReadAllBytes($file)
                $ext = [IO.Path]::GetExtension($file).ToLower()
                $ctx.Response.ContentType = $(if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' })
                if ($rel -eq 'photos.js') { $ctx.Response.Headers.Add('Cache-Control', 'no-cache') }
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $ctx.Response.StatusCode = 404
            }
        } catch { $ctx.Response.StatusCode = 500 }
        finally { $ctx.Response.Close() }
    }
} finally { $listener.Stop() }
