#!/usr/bin/env python3
"""Run the pinned ai-template spine tool. See spine-kit/README.md."""
import runpy
import sys
from pathlib import Path

if sys.version_info < (3, 11):
    raise SystemExit("Spine tooling requires Python 3.11+; invoke with py -3.11 on Windows.")
kit = Path(__file__).resolve().parent / "spine-kit"
sys.path.insert(0, str(kit))
runpy.run_path(str(kit / "hats.py"), run_name="__main__")
