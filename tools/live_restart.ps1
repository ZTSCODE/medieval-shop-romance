# Tells a game running in live mode (tools/run_live.cmd) to save, restart itself and return to the journey.
# Use after changing scripts; text and content files are picked up without this.
$flag = Join-Path (Split-Path -Parent $PSScriptRoot) "work\live\restart.flag"
New-Item -ItemType Directory -Force (Split-Path -Parent $flag) | Out-Null
Set-Content -Path $flag -Value (Get-Date -Format o) -Encoding utf8
Write-Output "restart requested"
