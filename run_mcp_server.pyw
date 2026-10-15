"""Windowless launcher for the AdjutantVoice MCP server (run with the venv's pythonw.exe).

Started at logon by the "AdjutantVoice MCP" scheduled task. Settings come from
~/.adjutantvoice/.env; output goes to ~/.adjutantvoice/server.log (previous run: server.log.1).
"""
import os
import sys
from pathlib import Path

# The guard matters: the model worker is started with multiprocessing "spawn",
# which re-imports this file as __mp_main__ in the child.
if __name__ == "__main__":
    log_path = Path.home() / ".adjutantvoice" / "server.log"
    if log_path.exists():  # keep the previous run's log for post-mortems
        log_path.replace(log_path.with_name("server.log.1"))
    log = open(log_path, "w", buffering=1, encoding="utf-8")
    sys.stdout = sys.stderr = log
    os.dup2(log.fileno(), 1)
    os.dup2(log.fileno(), 2)
    os.environ["AV_LOG_FILE"] = str(log_path)  # picked up by the model worker process
    os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

    from adjutantvoice.mcp import start

    start()
