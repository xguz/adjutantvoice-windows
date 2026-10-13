# adjutantvoice-windows

Runs [AdjutantVoice](https://github.com/xguz/AdjutantVoice) (OmniVoice text-to-speech) as an always-on, windowless MCP server on Windows, and connects it to Claude Code on Windows and in WSL, so Claude can speak on your speakers.

Built and tested on an Intel Arc 140V laptop (Core Ultra 7 258V, 32 GB, Windows 11). It uses the [xguz/AdjutantVoice](https://github.com/xguz/AdjutantVoice) fork, which adds non-CUDA support, an idle-stopping worker process, and Windows fixes on top of [voidhaze/AdjutantVoice](https://github.com/voidhaze/AdjutantVoice).

## What you get

- **Scheduled task "AdjutantVoice MCP"** starts the server at logon, without a window, listening on `127.0.0.1:8222` only. It runs in your session, so audio reaches your speakers.
- **Model loaded on demand:** the model runs in a worker process that exits after 5 idle minutes. The server alone uses about 0.1 GB; a warm worker uses about 6.5 GB of RAM (shared with the Intel GPU).
- **Claude Code integration:** the `adjutantvoice` MCP server is registered at user scope on Windows and in WSL, so every session gets `tts_speak`, `tts_stream` and `tts_file`.
- **Spoken announcements:** a short block in your user-level `CLAUDE.md` asks Claude to say one sentence when it finishes a longer task or needs you.

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
| `-Torch cuda` / `-Torch cpu` | Use an NVIDIA or CPU PyTorch build instead of Intel XPU |
| `-SkipWsl` | Don't touch WSL |
| `-SkipClaude` | Don't register with Claude Code at all |
| `-SkipClaudeMd` | Register the MCP server but don't add the announcements block to `CLAUDE.md` |

First install downloads PyTorch (~1 GB) and the OmniVoice model (~2 GB).

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

Log: `%USERPROFILE%\.adjutantvoice\server.log` (recreated at each start).

## Performance (Arc 140V, fp16, 24 steps)

| | |
|---|---|
| Short phrase, warm | ~4-5 s |
| Long sentence (~130 characters), warm | ~6-8 s |
| First request after an idle stop | ~30-35 s (Python imports ~13 s, model load ~7 s, first-generation GPU warm-up ~10-15 s) |

Running a game at the same time slows both down: the GPU and its memory are shared.

## Intel GPU notes

On Intel XPU (torch 2.14.1+xpu), fp32 `softmax` / `log_softmax` return wrong values when the last dimension is 2^k+1. OmniVoice's audio vocabulary is exactly 1025 tokens, so without a workaround every generation comes out as noise. The fork works around it; see [voidhaze/AdjutantVoice#2](https://github.com/voidhaze/AdjutantVoice/pull/2) and [intel/torch-xpu-ops#4772](https://github.com/intel/torch-xpu-ops/issues/4772).

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1            # task + Claude Code registrations
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveVenv
```

Your `.env`, voice clones and the Hugging Face model cache are kept.

## Files

| File | Purpose |
|---|---|
| `install.ps1` / `uninstall.ps1` | Set up / remove everything above |
| `run_mcp_server.pyw` | Windowless launcher started by the scheduled task |
| `.env.example` | Default settings |
| `CLAUDE.snippet.md` | Announcements block added to `~/.claude/CLAUDE.md` |
| `claude_config.py` | Edits `~/.claude.json` and `CLAUDE.md` when the `claude` CLI isn't available (Windows desktop app); also used inside WSL |
