<#
.SYNOPSIS
  Install AdjutantVoice as an always-on, windowless MCP server on Windows and
  register it with Claude Code (Windows and WSL), Claude Desktop chat and Cursor.
  Safe to re-run.

.PARAMETER Source
  pip requirement for AdjutantVoice. Defaults to a pinned commit of the fork.
  For a local checkout you are editing, pass e.g. -Source "-e C:\path\to\AdjutantVoice".

.PARAMETER Torch
  PyTorch build: xpu (Intel Arc, default), cuda (NVIDIA) or cpu.
#>
[CmdletBinding()]
param(
    [string]$Source = "git+https://github.com/xguz/AdjutantVoice@917a33702400a7fe149963e0613134074a9c0be3",
    [string]$PythonVersion = "3.11",
    [ValidateSet("xpu", "cuda", "cpu")]
    [string]$Torch = "xpu",
    [switch]$SkipClaude,
    [switch]$SkipWsl,
    [switch]$SkipClaudeMd,
    [switch]$SkipDesktop,
    [switch]$SkipCursor
)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$AvHome = Join-Path $env:USERPROFILE ".adjutantvoice"
$Venv = Join-Path $AvHome "venv"
$Py = Join-Path $Venv "Scripts\python.exe"
$PyW = Join-Path $Venv "Scripts\pythonw.exe"
$EnvFile = Join-Path $AvHome ".env"
$TaskName = "AdjutantVoice MCP"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
# Native commands are judged by exit code only: in Windows PowerShell 5.1, stderr output
# (pip warnings, progress bars) can otherwise turn into terminating errors.
function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    $ErrorActionPreference = "Continue"
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Exe $($Arguments -join ' ')" }
}
function Invoke-Quiet {
    # Returns stdout (stderr discarded); check $LASTEXITCODE afterwards.
    param([string]$Exe, [string[]]$Arguments)
    $ErrorActionPreference = "Continue"
    & $Exe @Arguments 2>$null
}

# --- Prerequisites -----------------------------------------------------------
Step "Checking prerequisites"
if (-not (Get-Command py -ErrorAction SilentlyContinue)) { throw "Python launcher 'py' not found. Install Python $PythonVersion from python.org." }
$null = Invoke-Quiet py @("-$PythonVersion", "-c", "import sys")
if ($LASTEXITCODE -ne 0) { throw "Python $PythonVersion not found (py -$PythonVersion). Install it from python.org." }
if ($Source -like "git+*" -and -not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required to install from $Source." }
if (-not (Get-Command ffplay -ErrorAction SilentlyContinue)) {
    Write-Warning "ffplay not found on PATH: tts_speak won't be able to play audio. Install with: winget install Gyan.FFmpeg"
}
New-Item -ItemType Directory -Force -Path $AvHome | Out-Null

# --- Python environment --------------------------------------------------------
if (-not (Test-Path $Py)) {
    Step "Creating virtual environment in $Venv"
    Invoke-Checked py @("-$PythonVersion", "-m", "venv", $Venv)
}
Invoke-Checked $Py @("-m", "pip", "install", "--quiet", "--upgrade", "pip")

$torchVersion = Invoke-Quiet $Py @("-c", "import torch; print(torch.__version__)")
$wantTag = @{ xpu = "+xpu"; cuda = "+cu"; cpu = "+cpu" }[$Torch]
if ($LASTEXITCODE -ne 0 -or "$torchVersion" -notlike "*$wantTag*") {
    Step "Installing PyTorch ($Torch build) - large download"
    $index = @{
        xpu  = "https://download.pytorch.org/whl/xpu"
        cuda = "https://download.pytorch.org/whl/cu128"
        cpu  = "https://download.pytorch.org/whl/cpu"
    }[$Torch]
    Invoke-Checked $Py @("-m", "pip", "install", "--quiet", "--force-reinstall", "torch", "torchaudio", "--index-url", $index)
} else {
    Step "PyTorch $torchVersion already installed"
}

Step "Installing AdjutantVoice from: $Source"
$sourceArgs = $Source -split " "
Invoke-Checked $Py (@("-m", "pip", "install", "--quiet") + $sourceArgs)
# Make sure the requested revision is what's installed, even if the version number didn't change.
Invoke-Checked $Py (@("-m", "pip", "install", "--quiet", "--no-deps", "--force-reinstall") + $sourceArgs)

$check = Invoke-Quiet $Py @("-c", "import torch; print(torch.__version__, 'xpu available:', torch.xpu.is_available())")
Write-Host "    torch $check"

# --- Config and launcher -------------------------------------------------------
if (-not (Test-Path $EnvFile)) {
    Step "Creating $EnvFile from .env.example"
    Copy-Item (Join-Path $Here ".env.example") $EnvFile
} else {
    Step "Keeping existing $EnvFile"
}
foreach ($f in "run_mcp_server.pyw", "stdio_bridge.py") { Copy-Item (Join-Path $Here $f) (Join-Path $AvHome $f) -Force }

$port = 8222
$portLine = Select-String -Path $EnvFile -Pattern '^\s*AV_MCP_PORT\s*=\s*(\d+)' | Select-Object -Last 1
if ($portLine) { $port = [int]$portLine.Matches[0].Groups[1].Value }
$McpUrl = "http://127.0.0.1:$port/mcp"

Step "Downloading the OmniVoice model if needed (~2 GB on first install)"
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"
Invoke-Checked $Py @("-c", "from huggingface_hub import snapshot_download; snapshot_download('k2-fsa/OmniVoice')")

# --- Scheduled task --------------------------------------------------------------
Step "Registering scheduled task '$TaskName' (runs at logon, windowless)"
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}
$user = "$env:USERDOMAIN\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute $PyW -Argument "`"$(Join-Path $AvHome 'run_mcp_server.pyw')`"" -WorkingDirectory $AvHome
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description "AdjutantVoice TTS MCP server on $McpUrl (config: ~/.adjutantvoice/.env, log: ~/.adjutantvoice/server.log)" | Out-Null
Start-ScheduledTask -TaskName $TaskName

Step "Waiting for the server on port $port"
$deadline = (Get-Date).AddMinutes(5)
$up = $false
while ((Get-Date) -lt $deadline -and -not $up) {
    Start-Sleep -Seconds 2
    $tcp = New-Object Net.Sockets.TcpClient
    try { $tcp.Connect("127.0.0.1", $port); $up = $true } catch { } finally { $tcp.Close() }
}
if (-not $up) { throw "Server did not start within 5 minutes; see $AvHome\server.log" }
Write-Host "    listening on $McpUrl"

# --- Claude Code: Windows ------------------------------------------------------
$helper = Join-Path $Here "client_config.py"
$snippet = Join-Path $Here "CLAUDE.snippet.md"
if (-not $SkipClaude) {
    Step "Registering the MCP server with Claude Code on Windows"
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        $null = Invoke-Quiet claude @("mcp", "remove", "adjutantvoice", "--scope", "user")
        Invoke-Checked claude @("mcp", "add", "--transport", "http", "--scope", "user", "adjutantvoice", $McpUrl)
    } else {
        Invoke-Checked $Py @($helper, "code-add", $McpUrl)
    }
    if (-not $SkipClaudeMd) { Invoke-Checked $Py @($helper, "md-add", $snippet) }
}

# --- Claude Code: WSL ----------------------------------------------------------------
if (-not $SkipClaude -and -not $SkipWsl -and (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Step "Registering the MCP server with Claude Code in WSL"
    $mode = (Invoke-Quiet wsl @("-e", "sh", "-c", "wslinfo --networking-mode")) -join ""
    if ($mode -ne "mirrored") {
        Write-Warning "WSL networking mode is '$mode', not 'mirrored': WSL can't reach Windows' 127.0.0.1. Set networkingMode=mirrored under [wsl2] in %USERPROFILE%\.wslconfig, then run 'wsl --shutdown'."
    }
    $wslHelper = (Invoke-Quiet wsl @("-e", "wslpath", "-a", $helper)) -join ""
    $wslSnippet = (Invoke-Quiet wsl @("-e", "wslpath", "-a", $snippet)) -join ""
    $hasClaude = (Invoke-Quiet wsl @("-e", "bash", "-lc", "command -v claude >/dev/null && echo yes")) -join ""
    if ($hasClaude -eq "yes") {
        Invoke-Checked wsl @("-e", "bash", "-lc", "claude mcp remove adjutantvoice --scope user >/dev/null 2>&1; claude mcp add --transport http --scope user adjutantvoice $McpUrl")
    } else {
        Invoke-Checked wsl @("-e", "python3", $wslHelper, "code-add", $McpUrl)
    }
    if (-not $SkipClaudeMd) { Invoke-Checked wsl @("-e", "python3", $wslHelper, "md-add", $wslSnippet) }
}

# --- Claude Desktop chat -------------------------------------------------------------
# Chat only launches stdio servers, so register the bridge that forwards to the running server.
if (-not $SkipDesktop) {
    Step "Registering the stdio bridge with Claude Desktop chat"
    Invoke-Checked $Py @($helper, "desktop-add", $Py, (Join-Path $AvHome "stdio_bridge.py"))
    Write-Host "    Fully quit Claude Desktop (tray icon > Quit) and reopen it to load the change."
}

# --- Cursor ----------------------------------------------------------------------------
if (-not $SkipCursor -and (Test-Path (Join-Path $env:USERPROFILE ".cursor"))) {
    Step "Registering the MCP server with Cursor"
    Invoke-Checked $Py @($helper, "cursor-add", $McpUrl)
}

Step "Done"
Write-Host "    Config: $EnvFile   Log: $AvHome\server.log"
Write-Host "    New sessions now have the adjutantvoice tools (tts_speak, tts_stream, tts_file)."
