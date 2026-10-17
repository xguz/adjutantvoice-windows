<#
.SYNOPSIS
  Remove the AdjutantVoice scheduled task and the Claude Code, Claude Desktop and Cursor
  registrations installed by install.ps1.

.PARAMETER RemoveVenv
  Also delete ~/.adjutantvoice/venv and the GPU kernel cache. Your .env and voice clones are always kept,
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
$WatchdogTaskName = "AdjutantVoice Watchdog"
$helper = Join-Path $Here "client_config.py"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Stop-AdjutantVoiceServer {
    # python(w).exe running run_mcp_server.pyw as its script, plus all descendants (the model worker).
    $all = @(Get-CimInstance Win32_Process)
    $ids = @($all | Where-Object {
            $_.Name -in "python.exe", "pythonw.exe" -and $_.CommandLine -match '^"?[^"]*pythonw?\.exe"?\s+"?[^"]*\\run_mcp_server\.pyw"?\s*$'
        } | ForEach-Object { $_.ProcessId })
    do {
        $more = @($all | Where-Object { $ids -contains $_.ParentProcessId -and $ids -notcontains $_.ProcessId } | ForEach-Object { $_.ProcessId })
        $ids += $more
    } while ($more.Count -gt 0)
    foreach ($id in $ids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
}

Step "Removing scheduled tasks '$WatchdogTaskName' and '$TaskName'"
# Watchdog first, so it can't restart the server while we remove it.
foreach ($name in $WatchdogTaskName, $TaskName) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
    }
}
# Stopping the task can leave the windowless server (and its model worker) running.
Stop-AdjutantVoiceServer

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

foreach ($f in "run_mcp_server.pyw", "stdio_bridge.py", "watchdog.pyw", "watchdog.state.json") { Remove-Item (Join-Path $AvHome $f) -ErrorAction SilentlyContinue }
if ($RemoveVenv) {
    Step "Deleting $AvHome\venv and the GPU kernel cache"
    Remove-Item -Recurse -Force (Join-Path $AvHome "venv")
    Remove-Item -Recurse -Force (Join-Path $AvHome "kernel_cache") -ErrorAction SilentlyContinue
}

Step "Done. Kept: $AvHome\.env, voice clones, and the Hugging Face model cache."
