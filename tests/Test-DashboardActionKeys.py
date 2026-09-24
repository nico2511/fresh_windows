#!/usr/bin/env python3
"""Verifie que chaque ActionKey du dashboard existe dans FreshAgentDashboardActionMap."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DASH = ROOT / "scripts/lib/FreshAgent-Dashboard.ps1"
WATCH = ROOT / "scripts/GameMode-WatchAgent.ps1"

KEY_RE = re.compile(r"-ActionKey\s+'([^']+)'")
MAP_KEY_RE = re.compile(r"^\s+([A-Za-z0-9]+)\s*=")


def extract_dashboard_keys(text: str) -> set[str]:
    keys = set(KEY_RE.findall(text))
    keys.add("QuitAgent")  # Tag manuel sur btnQuit
    return keys


def extract_map_keys(text: str) -> set[str]:
    start = text.find("$script:FreshAgentDashboardActionMap = @{")
    if start < 0:
        raise SystemExit("FreshAgentDashboardActionMap introuvable")
    block = text[start:]
    end = block.find("\n        }")
    if end < 0:
        raise SystemExit("fin map introuvable")
    block = block[:end]
    keys = set()
    for line in block.splitlines():
        m = MAP_KEY_RE.match(line)
        if m:
            keys.add(m.group(1))
    return keys


def main() -> int:
    dash = DASH.read_text(encoding="utf-8")
    watch = WATCH.read_text(encoding="utf-8")
    ui_keys = extract_dashboard_keys(dash)
    map_keys = extract_map_keys(watch)
    missing = sorted(ui_keys - map_keys)
    extra = sorted(map_keys - ui_keys)
    if missing:
        print("FAIL: ActionKeys UI sans entree map:", ", ".join(missing))
        return 1
    if extra:
        print("WARN: cles map non utilisees par UI:", ", ".join(extra))
    print(f"OK: {len(ui_keys)} ActionKeys dashboard couvertes par la map")
    return 0


if __name__ == "__main__":
    sys.exit(main())
