<#
.SYNOPSIS
  Remove the AdjutantVoice scheduled task and the Claude Code, Claude Desktop and Cursor
  registrations installed by install.ps1.

.PARAMETER RemoveVenv
  Also delete ~/.adjutantvoice/venv. Your .env and voice clones in ~/.adjutantvoice are always kept,
  as is the downloaded model in the Hugging Face cache (~/.cache/huggingface).
#>
[CmdletBinding()]
param(
    [switch]$RemoveVenv
)

$ErrorActionPreference = "Continue"  # best effort: keep going if a piece is already gone
$Here = $PSScriptRoot
$AvHome = Join-Path $env:USERPROFILE ".adjutantvoice"
$Py = Join-Path $AvHome "venv\Scripts\python.exe"
$TaskName = "AdjutantVoice MCP"
$helper = Join-Path $Here "client_config.py"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

Step "Removing scheduled task '$TaskName'"
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}
# Stopping the task can leave the windowless server (and its model worker) running.
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" |
    Where-Object { $_.CommandLine -like "*run_mcp_server.pyw*" -or ($_.CommandLine -like "*multiprocessing*" -and $_.ExecutablePath -like "*\.adjutantvoice\venv\*") } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Step "Removing Claude Code, Claude Desktop and Cursor registrations on Windows"
if (Get-Command claude -ErrorAction SilentlyContinue) {
    & claude mcp remove adjutantvoice --scope user
} elseif (Test-Path $Py) {
    & $Py $helper code-remove
} else {
    & py -3 $helper code-remove
}
$hostPy = if (Test-Path $Py) { $Py } else { "py" }
foreach ($cmd in "md-remove", "desktop-remove", "cursor-remove") {
    if ($hostPy -eq "py") { & py -3 $helper $cmd } else { & $hostPy $helper $cmd }
}

if (Get-Command wsl -ErrorAction SilentlyContinue) {
    Step "Removing Claude Code registration in WSL"
    $wslHelper = (& wsl -e wslpath -a $helper) -join ""
    & wsl -e bash -lc "command -v claude >/dev/null && claude mcp remove adjutantvoice --scope user || python3 '$wslHelper' code-remove"
    & wsl -e python3 $wslHelper md-remove
}

foreach ($f in "run_mcp_server.pyw", "stdio_bridge.py") { Remove-Item (Join-Path $AvHome $f) -ErrorAction SilentlyContinue }
if ($RemoveVenv) {
    Step "Deleting $AvHome\venv"
    Remove-Item -Recurse -Force (Join-Path $AvHome "venv")
}

Step "Done. Kept: $AvHome\.env, voice clones, and the Hugging Face model cache."
