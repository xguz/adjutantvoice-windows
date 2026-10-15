"""Health check for the AdjutantVoice MCP server (run with the venv's pythonw.exe).

Run every few minutes by the "AdjutantVoice Watchdog" scheduled task. Restarts the
server when it stops answering on its port -- including when the process is still
running but no longer accepting connections, which the server task can't detect.
Log: ~/.adjutantvoice/watchdog.log
"""
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

import psutil

AV_HOME = Path.home() / ".adjutantvoice"
LOG = AV_HOME / "watchdog.log"
STATE = AV_HOME / "watchdog.state.json"
TASK = "AdjutantVoice MCP"
FAILURES_BEFORE_RESTART = 2
# Don't judge a server that is still starting up.
STARTUP_GRACE_SECONDS = int(os.environ.get("AV_WATCHDOG_GRACE_SECONDS", "180"))
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def log(msg):
    if LOG.exists() and LOG.stat().st_size > 256 * 1024:
        LOG.replace(LOG.with_name(LOG.name + ".1"))
    with LOG.open("a", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")


def load_failures():
    try:
        return json.loads(STATE.read_text(encoding="utf-8"))["failures"]
    except (OSError, ValueError, KeyError):
        return 0


def save_failures(n):
    STATE.write_text(json.dumps({"failures": n}), encoding="utf-8")


def answers(port):
    """True if anything answers HTTP on the MCP endpoint (any status code counts)."""
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/mcp", timeout=10)
    except urllib.error.HTTPError:
        pass  # it answered -- just not a valid MCP request, which is fine
    except OSError:
        return False
    return True


def is_server(info):
    """python(w).exe running run_mcp_server.pyw as its script -- not just any
    process that mentions the file somewhere in its command line."""
    args = info["cmdline"] or []
    return (
        (info["name"] or "").lower() in ("python.exe", "pythonw.exe")
        and len(args) >= 2
        and Path(args[1]).name == "run_mcp_server.pyw"
    )


def server_processes():
    """The launcher processes plus their children (the model worker)."""
    procs = []
    for p in psutil.process_iter(["name", "cmdline"]):
        try:
            if is_server(p.info):
                procs.append(p)
                procs.extend(p.children(recursive=True))
        except psutil.Error:
            pass
    return list({p.pid: p for p in procs}.values())


def restart(procs):
    for p in procs:
        try:
            p.kill()
        except psutil.Error:
            pass
    psutil.wait_procs(procs, timeout=10)
    subprocess.run(["schtasks", "/End", "/TN", TASK], capture_output=True, creationflags=NO_WINDOW)
    result = subprocess.run(["schtasks", "/Run", "/TN", TASK], capture_output=True, text=True, creationflags=NO_WINDOW)
    return result.returncode == 0


def main():
    from adjutantvoice.config import settings  # cheap: doesn't import torch

    port = settings.mcp_port
    failures = load_failures()

    if answers(port):
        if failures:
            log(f"OK: server answering on port {port} again")
            save_failures(0)
        return

    procs = server_processes()
    youngest = min((time.time() - p.create_time() for p in procs), default=None)
    if youngest is not None and youngest < STARTUP_GRACE_SECONDS:
        log(f"server started {youngest:.0f}s ago and isn't answering yet; waiting")
        return

    failures += 1
    state = f"{len(procs)} server process(es) running" if procs else "no server process"
    if failures < FAILURES_BEFORE_RESTART:
        log(f"no answer on port {port} ({state}); check {failures}/{FAILURES_BEFORE_RESTART}")
        save_failures(failures)
        return

    ok = restart(procs)
    log(f"no answer on port {port} ({state}) for {failures} checks: "
        f"killed {len(procs)} process(es), {'restarted' if ok else 'FAILED to restart'} task '{TASK}'")
    save_failures(0)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # never die silently: there's no console under pythonw
        log(f"watchdog error: {type(exc).__name__}: {exc}")
