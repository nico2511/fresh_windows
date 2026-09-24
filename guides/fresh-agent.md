# Fresh Agent (systray)

Agent **Fresh Windows** dans la barre des taches : mode jeu, skills, IA optionnelle (Ollama), STT Windows, TTS, RAG guides.

## Core vs IA

| Composant | Sans Ollama | Avec IA ON |
|-----------|-------------|------------|
| Mode jeu / session | Oui | Oui |
| Skills (menu) | Oui | Oui |
| Tool calling Ollama | Non | Oui |
| STT Windows | Oui | Oui (routage IA) |
| RAG guides | Non* | Oui si RAG ON |

\* L'inventaire machine peut rester injecte sans RAG (`includeInventoryInPrompt`).

## Fichiers locaux (%LOCALAPPDATA%\\FreshWindows)

| Fichier | Role |
|---------|------|
| `agent-ai.user.json` | Override IA / TTS / RAG (prioritaire sur le repo) |
| `skills-apps.user.json` | Aliases apps perso |
| `inventory.json` | Jeux Steam, navigateur (non ecrase par sync) |
| `game-session.state.json` | Etat session jeu |
| `ai-history.jsonl` | Historique IA |
| `fresh-agent.log` | Logs agent (rotation ~2 Mo) |
| `configs/` | Copie sync des JSON repo (skills, agent-ai schema) |

Le sync **ne supprime pas** les fichiers user ci-dessus.

## Une seule instance / agent invisible

- Log : `%LOCALAPPDATA%\FreshWindows\watch-agent.log` — chercher `Mutex acquis`, `NotifyIcon visible`, ou `Autre instance active (PID ...)`.
- Si relance bloquee sans icone : tuer les processus fantomes puis relancer :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\FreshWindows\Stop-FreshWatchAgent.ps1"
& "$env:LOCALAPPDATA\FreshWindows\Start-WatchAgent.cmd"
```

(Equivalent manuel : `Get-CimInstance Win32_Process` + `Stop-Process` sur les lignes de commande `GameMode-WatchAgent|Launch-GameModeWatch`.)

## Panneau (UI)

- **Clic gauche** sur l’icone systray : fenetre **Fresh Agent** (onglets Jeu / Skills / IA / Fresh Windows).
- Cases a cocher : IA, RAG, detection auto, surveillance — sans sous-menus.
- **Clic droit** : menu contextuel complet (raccourci « Ouvrir le panneau » en tete).

## Sync

- Menu systray : **Mettre a jour scripts locaux**
- Tache planifiee : `FreshWindows-SyncLocalScripts` (dimanche)
- Script local : `%LOCALAPPDATA%\FreshWindows\Sync-FreshWindowsAgent.ps1`

**Premiere install** (fichier sync absent) — une ligne :

```powershell
$fresh = Join-Path $env:LOCALAPPDATA 'FreshWindows'; New-Item -ItemType Directory -Path $fresh -Force | Out-Null; $ref='main'; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nico2511/fresh_windows/$ref/scripts/Sync-FreshWindowsAgent.ps1" -OutFile (Join-Path $fresh 'Sync-FreshWindowsAgent.ps1') -UseBasicParsing; powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fresh 'Sync-FreshWindowsAgent.ps1') -RepoRef $ref
```

## STT

Defaut : **API Windows** (`System.Speech`), pas CyberScribe. Menu **Ecouter**.

## Developpement local (clone Git)

Mettre a jour `main`, copier le repo vers AppData, tester :

```powershell
cd D:\Git\FreshWindows
git pull origin main
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Dev-SyncFreshAgentFromRepo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Parse-Scripts.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-AllTests.ps1
```

Puis relancer l’agent (tuer l’instance precedente si besoin) :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\FreshWindows\Stop-FreshWatchAgent.ps1"
& "$env:LOCALAPPDATA\FreshWindows\Start-WatchAgent.cmd"
```

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-AllTests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-SkillsRegistry.ps1
```
