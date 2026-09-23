#!/usr/bin/env python3
"""Audit statique Fresh Agent (repo) — executable sans PowerShell."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
CONFIGS = ROOT / "configs"

SYNC_MANIFEST = SCRIPTS / "lib" / "FreshAgent-Config.ps1"
REGISTRY = CONFIGS / "skills" / "registry.json"

REQUIRED_AI = [
    "scripts/ai/Ollama-Manager.ps1",
    "scripts/ai/FreshAgent-OllamaBridge.ps1",
    "scripts/ai/FreshAgent-BackgroundWorker.ps1",
    "scripts/ai/Windows-Stt.ps1",
    "scripts/ai/FreshAgent-Tts.ps1",
]

REQUIRED_LIB = [
    "scripts/lib/FreshAgent-Config.ps1",
    "scripts/lib/FreshAgent-SkillsEngine.ps1",
    "scripts/lib/FreshAgent-SkillHandlers.ps1",
    "scripts/lib/FreshAgent-Profiles.ps1",
]


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)


def ok(msg: str) -> None:
    print(f"OK: {msg}")


def main() -> int:
    errors = 0

    for rel in REQUIRED_LIB + REQUIRED_AI:
        p = ROOT / rel.replace("/", "\\") if False else ROOT / rel
        if not p.is_file():
            fail(f"missing file {rel}")
            errors += 1
        else:
            ok(rel)

    if REGISTRY.is_file():
        reg = json.loads(REGISTRY.read_text(encoding="utf-8"))
        for entry in reg.get("skills") or []:
            sid = entry.get("id")
            rel = entry.get("file")
            if not rel:
                fail(f"skill {sid} has no file")
                errors += 1
                continue
            skill_path = (CONFIGS / "skills" / rel).resolve()
            if not skill_path.is_file():
                skill_path = CONFIGS / "skills" / Path(rel.replace("\\", "/"))
            if not skill_path.is_file():
                fail(f"skill {sid} missing {skill_path.relative_to(ROOT)}")
                errors += 1
    else:
        fail("registry.json missing")
        errors += 1

    if SYNC_MANIFEST.is_file():
        text = SYNC_MANIFEST.read_text(encoding="utf-8")
        for rel in [
            "ai/FreshAgent-BackgroundWorker.ps1",
            "ai/Ollama-Manager.ps1",
            "lib/FreshAgent-SkillsEngine.ps1",
        ]:
            if rel not in text:
                fail(f"Sync-FreshAgentLocalAssets missing {rel}")
                errors += 1
            else:
                ok(f"sync list mentions {rel}")
    else:
        fail("FreshAgent-Config.ps1 missing")
        errors += 1

    watch = SCRIPTS / "GameMode-WatchAgent.ps1"
    if watch.is_file():
        wt = watch.read_text(encoding="utf-8")
        if "FreshAgent-BackgroundWorker.ps1" not in wt:
            fail("WatchAgent does not reference BackgroundWorker")
            errors += 1
        if re.search(r"-Command',\s*`$inner", wt):
            fail("WatchAgent still uses fragile -Command inline for Ollama bg")
            errors += 1
        else:
            ok("WatchAgent Ollama bg uses -File worker")
    else:
        fail("GameMode-WatchAgent.ps1 missing")
        errors += 1

    if errors:
        print(f"\n{errors} error(s)", file=sys.stderr)
        return 1
    print("\nAudit Fresh Agent: all checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
