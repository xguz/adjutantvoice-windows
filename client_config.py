"""Register AdjutantVoice with MCP clients (used by install.ps1 / uninstall.ps1).

Runs on Windows (venv python) and inside WSL (python3), acting on that side's home dir.

  client_config.py code-add URL              Claude Code: HTTP server in ~/.claude.json
  client_config.py code-remove
  client_config.py md-add SNIPPET            Claude Code: marked block in ~/.claude/CLAUDE.md
  client_config.py md-remove
  client_config.py desktop-add PYTHON BRIDGE Claude Desktop chat: stdio bridge in claude_desktop_config.json
  client_config.py desktop-remove
  client_config.py cursor-add URL            Cursor: HTTP server in ~/.cursor/mcp.json
  client_config.py cursor-remove

For Claude Code, prefer `claude mcp add/remove` when the claude CLI is available; this
is the fallback for installs without it (e.g. the Claude desktop app on Windows).
Each JSON file is backed up once, to <file>.bak-adjutantvoice, before the first edit.
"""
import json
import os
import re
import shutil
import sys
from pathlib import Path

NAME = "adjutantvoice"
START, END = "<!-- adjutantvoice:start -->", "<!-- adjutantvoice:end -->"
HOME = Path.home()
CLAUDE_JSON = HOME / ".claude.json"
CLAUDE_MD = HOME / ".claude" / "CLAUDE.md"
CURSOR_JSON = HOME / ".cursor" / "mcp.json"


def desktop_config_path():
    """Claude Desktop's config; the Microsoft Store/MSIX build keeps it in its package folder."""
    local = Path(os.environ.get("LOCALAPPDATA", HOME / "AppData" / "Local"))
    for pkg in sorted(local.glob("Packages/Claude_*")):
        candidate = pkg / "LocalCache" / "Roaming" / "Claude"
        if candidate.is_dir():
            return candidate / "claude_desktop_config.json"
    roaming = Path(os.environ.get("APPDATA", HOME / "AppData" / "Roaming"))
    return roaming / "Claude" / "claude_desktop_config.json"


def edit_json(path, update):
    data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    backup = path.with_name(path.name + ".bak-adjutantvoice")
    if path.exists() and not backup.exists():
        shutil.copyfile(path, backup)
    update(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def set_server(path, entry):
    edit_json(path, lambda d: d.setdefault("mcpServers", {}).__setitem__(NAME, entry))
    print(f"{path}: mcpServers.{NAME} set")


def remove_server(path):
    if path.exists():
        edit_json(path, lambda d: d.get("mcpServers", {}).pop(NAME, None))
        print(f"{path}: mcpServers.{NAME} removed")


def _strip_block(text):
    return re.sub(rf"\n*{re.escape(START)}.*?{re.escape(END)}\n*", "\n", text, flags=re.S).strip("\n")


def md_add(snippet_path):
    block = Path(snippet_path).read_text(encoding="utf-8").strip("\n")
    current = CLAUDE_MD.read_text(encoding="utf-8") if CLAUDE_MD.exists() else ""
    rest = _strip_block(current)
    CLAUDE_MD.parent.mkdir(parents=True, exist_ok=True)
    CLAUDE_MD.write_text((rest + "\n\n" if rest else "") + block + "\n", encoding="utf-8", newline="\n")
    print(f"{CLAUDE_MD}: AdjutantVoice block {'updated' if START in current else 'added'}")


def md_remove():
    if not CLAUDE_MD.exists():
        return
    rest = _strip_block(CLAUDE_MD.read_text(encoding="utf-8"))
    CLAUDE_MD.write_text(rest + "\n" if rest else "", encoding="utf-8", newline="\n")
    print(f"{CLAUDE_MD}: AdjutantVoice block removed")


COMMANDS = {
    "code-add": lambda url: set_server(CLAUDE_JSON, {"type": "http", "url": url}),
    "code-remove": lambda: remove_server(CLAUDE_JSON),
    "md-add": md_add,
    "md-remove": md_remove,
    "desktop-add": lambda python, bridge: set_server(desktop_config_path(), {"command": python, "args": [bridge]}),
    "desktop-remove": lambda: remove_server(desktop_config_path()),
    "cursor-add": lambda url: set_server(CURSOR_JSON, {"type": "http", "url": url}),
    "cursor-remove": lambda: remove_server(CURSOR_JSON),
}

if __name__ == "__main__":
    COMMANDS[sys.argv[1]](*sys.argv[2:])
