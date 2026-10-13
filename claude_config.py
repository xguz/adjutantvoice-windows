"""Edit the current user's Claude Code config for AdjutantVoice (used by install/uninstall.ps1).

Runs on Windows (venv python) and inside WSL (python3), acting on that side's home dir.

  claude_config.py mcp-add URL        add/replace the "adjutantvoice" HTTP MCP server in ~/.claude.json
  claude_config.py mcp-remove         remove it
  claude_config.py md-add SNIPPET     add/replace the marked block in ~/.claude/CLAUDE.md
  claude_config.py md-remove          remove the marked block

Prefer `claude mcp add/remove` when the claude CLI is available; this is the fallback
for installs without it (e.g. the Claude desktop app on Windows). Backs up ~/.claude.json
once, to ~/.claude.json.bak-adjutantvoice.
"""
import json
import os
import re
import shutil
import sys
from pathlib import Path

NAME = "adjutantvoice"
START, END = "<!-- adjutantvoice:start -->", "<!-- adjutantvoice:end -->"
CLAUDE_JSON = Path.home() / ".claude.json"
CLAUDE_MD = Path.home() / ".claude" / "CLAUDE.md"


def _edit_claude_json(update):
    data = json.loads(CLAUDE_JSON.read_text(encoding="utf-8")) if CLAUDE_JSON.exists() else {}
    backup = CLAUDE_JSON.with_name(CLAUDE_JSON.name + ".bak-adjutantvoice")
    if CLAUDE_JSON.exists() and not backup.exists():
        shutil.copyfile(CLAUDE_JSON, backup)
    update(data)
    tmp = CLAUDE_JSON.with_name(CLAUDE_JSON.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    os.replace(tmp, CLAUDE_JSON)


def mcp_add(url):
    _edit_claude_json(lambda d: d.setdefault("mcpServers", {}).__setitem__(NAME, {"type": "http", "url": url}))
    print(f"{CLAUDE_JSON}: mcpServers.{NAME} -> {url}")


def mcp_remove():
    _edit_claude_json(lambda d: d.get("mcpServers", {}).pop(NAME, None))
    print(f"{CLAUDE_JSON}: removed mcpServers.{NAME}")


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


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    {"mcp-add": mcp_add, "mcp-remove": mcp_remove, "md-add": md_add, "md-remove": md_remove}[cmd](*args)
