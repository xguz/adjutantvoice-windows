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
    try:  # keep the previous run's log for post-mortems
        if log_path.exists():
            log_path.replace(log_path.with_name("server.log.1"))
    except OSError:
        # Still open by a process that is shutting down (e.g. right after the
        # watchdog killed the old server): Windows refuses the rename. Append
        # instead of crashing before anything is logged.
        pass
    log = open(log_path, "a", buffering=1, encoding="utf-8")
    sys.stdout = sys.stderr = log
    os.dup2(log.fileno(), 1)
    os.dup2(log.fileno(), 2)
    os.environ["AV_LOG_FILE"] = str(log_path)  # picked up by the model worker process
    os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

    # Keep the Intel GPU driver's compiled kernels on disk (the worker inherits this).
    # Measured on an Arc 140V: ~0.9 GB less memory per model start and a few seconds
    # faster first speech, because the driver loads cached kernels instead of running
    # its compiler. Costs ~1.1 GB of disk (deleted by uninstall.ps1 -RemoveVenv).
    cache = Path.home() / ".adjutantvoice" / "kernel_cache"
    for var, sub in (("NEO_CACHE_DIR", "neo"), ("SYCL_CACHE_DIR", "sycl")):
        (cache / sub).mkdir(parents=True, exist_ok=True)
        os.environ.setdefault(var, str(cache / sub))
    os.environ.setdefault("NEO_CACHE_PERSISTENT", "1")
    os.environ.setdefault("SYCL_CACHE_PERSISTENT", "1")

    from adjutantvoice.mcp import start

    start()
