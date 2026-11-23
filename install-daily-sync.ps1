# OPTIONAL: registers a Windows Scheduled Task that re-syncs the Google Photos album every 24h
# (so photos.js stays fresh even when serve.ps1 isn't running, e.g. if you open index.html directly
# or host the folder somewhere). Remove it any time with:  Unregister-ScheduledTask -TaskName InbarAlbumSync -Confirm:$false
$sync = Join-Path $PSScriptRoot 'sync.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$sync`""
$trigger = New-ScheduledTaskTrigger -Daily -At 4am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName 'InbarAlbumSync' -Action $action -Trigger $trigger -Settings $settings -Description 'Daily Google Photos album sync for the Inbar site' -Force
Write-Host 'Registered: InbarAlbumSync (daily 04:00, runs missed syncs on next start)'
