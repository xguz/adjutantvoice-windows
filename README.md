# adjutantvoice-windows

Runs [AdjutantVoice](https://github.com/xguz/AdjutantVoice) (OmniVoice text-to-speech) as an always-on, windowless MCP server on Windows, and connects it to Claude Code (Windows and WSL), Claude Desktop chat and Cursor, so the assistant can speak on your speakers.

Built and tested on an Intel Arc 140V laptop (Core Ultra 7 258V, 32 GB, Windows 11). It uses the [xguz/AdjutantVoice](https://github.com/xguz/AdjutantVoice) fork, which adds non-CUDA support, an idle-stopping worker process, and Windows fixes on top of [voidhaze/AdjutantVoice](https://github.com/voidhaze/AdjutantVoice).

## What you get

- **Scheduled task "AdjutantVoice MCP"** starts the server at logon, without a window, listening on `127.0.0.1:8222` only. It runs in your session, so audio reaches your speakers.
- **Model loaded on demand:** the server listens within seconds of logon; the model runs in a worker process started by the first request, which exits after 5 idle minutes. The server alone uses about 0.1 GB; a warm worker uses about 2 GB of RAM with the default OpenVINO backend (about 5.5 GB with PyTorch), shared with the Intel GPU.
- **Watchdog:** a second task, "AdjutantVoice Watchdog", checks every 3 minutes that the server answers on its port. After two failed checks in a row it kills the server and its worker and restarts the task. This catches the case the server task can't see: a process that is still running but no longer accepting connections.
- **Claude Code:** the `adjutantvoice` MCP server is registered at user scope on Windows and in WSL, so every session gets `tts_speak`, `tts_stream` and `tts_file`.
- **Claude Desktop chat:** chat only launches stdio MCP servers, so it gets `stdio_bridge.py`, a small proxy that forwards to the running server. Chat and Code share one server and one model.
- **Cursor:** registered in `~/.cursor/mcp.json` as an HTTP server (only if Cursor is installed).
- **Spoken announcements:** a short block in your user-level `CLAUDE.md` asks Claude to say one sentence when it finishes a longer task or needs you.
- **Tray icon** ("AdjutantVoice Tray" task, started at logon) to pause, mute, skip and set the volume; see [Playback controls](#playback-controls).

## Playback controls

Spoken messages queue up and play one at a time, in the order they arrived, 2 s apart. `tts_speak` returns as soon as a message is queued, so Claude isn't held up while it plays.

The tray icon shows the state: blue idle, green speaking, amber paused, grey muted, red server not reachable.

| Control | What it does |
|---|---|
| **Left-click the icon** | Opens a small panel above it with a **volume slider**, Pause/Resume, Skip and Mute, and the message playing. Click elsewhere or press Esc to close it. Right-click for the full menu |
| **Pause**, **Resume** | Freezes the current message and holds the queue; nothing is lost |
| **Skip current** | Stops the message that's playing; the queue carries on |
| **Clear queue** | Drops the messages waiting to play |
| **Mute** | Stops the current message, drops the queue, and drops new messages until unmuted (Claude is told they weren't spoken) |
| **Volume** | The slider in the left-click panel, or presets (10 / 25 / 50 / 75 / 100 %) in the right-click menu |
| **Recent messages** | Click one to play it again |
| **Open control page** | `http://127.0.0.1:8222/control` in your browser: status, buttons, volume slider, history |
| **Restart server**, **Open log**, **Open config** | Shortcuts |

Volume and mute are remembered across restarts (`~/.adjutantvoice/player_state.json`). Quitting the tray icon doesn't stop the server; it comes back at the next logon, or run `schtasks /Run /TN "AdjutantVoice Tray"`.

## Requirements

- Windows 11 with an Intel Arc GPU (default), or an NVIDIA GPU (`-Torch cuda`). CPU works but takes minutes per sentence.
- Python 3.11 from python.org (with the `py` launcher), and git.
- ffmpeg for audio playback: `winget install Gyan.FFmpeg`
- For WSL: WSL 2 with mirrored networking (`networkingMode=mirrored` under `[wsl2]` in `%USERPROFILE%\.wslconfig`). The installer only warns if it's missing; it never edits `.wslconfig`.

## Install

Run in a regular PowerShell window (not from inside a packaged app, which can redirect `AppData` writes):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

It's safe to re-run, for example after changing the port or updating the pinned AdjutantVoice commit. Options:

| Option | Effect |
|---|---|
| `-Source "-e C:\path\to\AdjutantVoice"` | Install a local checkout in editable mode instead of the pinned commit |
| `-Backend torch` | Write `AV_BACKEND=torch` to a new `.env` instead of `openvino` (an existing `.env` is never changed) |
| `-Torch cuda` / `-Torch cpu` | Use an NVIDIA or CPU PyTorch build instead of Intel XPU |
| `-SkipWsl` | Don't touch WSL |
| `-SkipClaude` | Don't register with Claude Code at all |
| `-SkipClaudeMd` | Register the MCP server but don't add the announcements block to `CLAUDE.md` |
| `-SkipDesktop` | Don't register with Claude Desktop chat |
| `-SkipCursor` | Don't register with Cursor |

First install downloads PyTorch (~1 GB) and the OmniVoice model (~2 GB).

Afterwards, **fully quit Claude Desktop** (tray icon > Quit) and reopen it so chat loads the bridge, and reload Cursor's window (or toggle the server in Cursor Settings > MCP).

Every config file the installer edits is backed up once, next to it, as `<file>.bak-adjutantvoice`. Claude Desktop from the Microsoft Store keeps its config under `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\`; the installer finds it there.

## Spoken announcements

Claude Code gets them automatically from the block the installer adds to `~/.claude/CLAUDE.md` ([CLAUDE.snippet.md](CLAUDE.snippet.md)). The other clients have no instructions file the installer can safely edit, so paste instructions yourself:

- **Claude Desktop chat:** Settings > Profile > personal preferences (or a Project's instructions). In chat every reply is "done", so ask for less, e.g. *"You can speak aloud with the adjutantvoice tts_speak tool. Use it only when I ask, or with one short sentence when a long task finishes."*
- **Cursor:** Cursor Settings > Rules > User Rules, with the bullet list from [CLAUDE.snippet.md](CLAUDE.snippet.md). For a single project, put it in `.cursor/rules/` or `AGENTS.md` instead.

## Configure

Edit `%USERPROFILE%\.adjutantvoice\.env` (created from [.env.example](.env.example)), then restart the server:

```powershell
schtasks /End /TN "AdjutantVoice MCP"; schtasks /Run /TN "AdjutantVoice MCP"
```

| Setting | Default here | Notes |
|---|---|---|
| `AV_NUM_STEP` | `24` | Decoding steps. 32 = OmniVoice default; 16 is about twice as fast as 32 |
| `AV_IDLE_UNLOAD_SECONDS` | `300` | Stop the model worker after this long idle; `0` keeps it loaded |
| `AV_DTYPE` | `float16` | `float32` is ~3x slower on Intel XPU with no audible gain |
| `AV_MCP_PORT` | `8222` | Re-run `install.ps1` after changing it so Claude Code gets the new URL |

Logs in `%USERPROFILE%\.adjutantvoice\`:

| File | Contents |
|---|---|
| `server.log` | Current server run; the previous run is kept as `server.log.1` |
| `watchdog.log` | Only failed checks, restarts and recoveries; nothing while healthy |
| `tray.log` | Tray icon (recreated at each start) |

## Troubleshooting

If a Claude Code session says it couldn't reconnect to `adjutantvoice`, the server was probably down for a moment; the watchdog brings it back within about 6 minutes. Reconnect from the session's MCP servers menu, or start a new session. To restart it yourself right away:

```powershell
schtasks /End /TN "AdjutantVoice MCP"; schtasks /Run /TN "AdjutantVoice MCP"
```

Then check `watchdog.log` and `server.log.1` for what happened.

If a request fails with *"didn't finish loading the model within 240s"*, *"took longer than 240s"* or *"only X GB of memory is available"*, the machine is short on RAM: the model needs about 2 GB once running with OpenVINO (about 6.5 GB with PyTorch). The watchdog can't fix that, since the server itself is fine. Close memory-heavy apps (browser tabs, games, a large WSL VM) and try again. Tune `AV_MIN_AVAILABLE_MEMORY_GB` and `AV_WORKER_TIMEOUT_SECONDS` in `.env` to fail sooner or wait longer.

## Performance (Arc 140V, 24 steps)

| | OpenVINO backend (default) | PyTorch backend |
|---|---|---|
| Model worker memory | ~2.0-2.3 GB | ~5.5 GB |
| Worker start (warm caches) | ~2 s | ~25-30 s |
| Short phrase, warm | ~4.5 s | ~4-5 s |
| Long sentence (~130 characters), warm | ~6 s | ~6-8 s |

The OpenVINO backend runs a PyTorch-free port of OmniVoice on Intel's OpenVINO runtime; `install.ps1` runs the one-time `av openvino export` (about a minute). Its parity with OmniVoice was checked bit for bit; see the fork's [docs/OPENVINO.md](https://github.com/xguz/AdjutantVoice/blob/main/docs/OPENVINO.md). The first time a new sentence length is decoded, OpenVINO compiles the audio decoder for that shape (an extra 1-3 s once). Re-run `av openvino export` after creating a new voice clone. Switch back with `AV_BACKEND=torch` in `.env`.

For the PyTorch backend, the launcher turns on the Intel driver's on-disk kernel cache (`%USERPROFILE%\.adjutantvoice\kernel_cache`, ~1.1 GB), which measured ~0.9 GB less memory per model start and a few seconds faster first speech.

The server runs at normal priority; Task Scheduler's default (below normal) made speech slower whenever the machine was busy.

Anything else using a lot of memory slows it down sharply, because the GPU shares system RAM: with a game running, or with under ~2 GB free (e.g. a large WSL VM plus a browser), the first request has taken 1.5-3.5 minutes and warm requests ~20 s.

## Intel GPU notes

On Intel XPU (torch 2.14.1+xpu), fp32 `softmax` / `log_softmax` return wrong values when the last dimension is 2^k+1. OmniVoice's audio vocabulary is exactly 1025 tokens, so without a workaround every generation comes out as noise. The fork works around it; see [voidhaze/AdjutantVoice#2](https://github.com/voidhaze/AdjutantVoice/pull/2) and [intel/torch-xpu-ops#4772](https://github.com/intel/torch-xpu-ops/issues/4772).

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1            # task + all client registrations
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveVenv
```

Your `.env`, voice clones and the Hugging Face model cache are kept.

## Files

| File | Purpose |
|---|---|
| `install.ps1` / `uninstall.ps1` | Set up / remove everything above |
| `run_mcp_server.pyw` | Windowless launcher started by the scheduled task |
| `watchdog.pyw` | Health check run by the watchdog task |
| `run_tray.pyw` | Windowless launcher for the tray icon (`av tray`) |
| `.env.example` | Default settings |
| `CLAUDE.snippet.md` | Announcements block added to `~/.claude/CLAUDE.md` |
| `stdio_bridge.py` | stdio-to-HTTP proxy that Claude Desktop chat launches |
| `client_config.py` | Adds/removes the server in Claude Code (`~/.claude.json`, when the `claude` CLI isn't available), Claude Desktop and Cursor configs, and the `CLAUDE.md` block; also used inside WSL |
