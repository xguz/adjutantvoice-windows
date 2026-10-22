"""Windowless launcher for the AdjutantVoice tray icon (run with the venv's pythonw.exe).

Started at logon by the "AdjutantVoice Tray" scheduled task. Output goes to
~/.adjutantvoice/tray.log.
"""
import logging
import sys
from pathlib import Path

if __name__ == "__main__":
    log_path = Path.home() / ".adjutantvoice" / "tray.log"
    log = open(log_path, "w", buffering=1, encoding="utf-8")
    sys.stdout = sys.stderr = log
    logging.basicConfig(level=logging.INFO, stream=log, format="%(asctime)s %(levelname)s %(message)s")

    from adjutantvoice.tray import main

    main()
