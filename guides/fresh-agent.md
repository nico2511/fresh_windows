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
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -match 'GameMode-WatchAgent|Launch-GameModeWatch' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
& "$env:LOCALAPPDATA\FreshWindows\Start-WatchAgent.cmd"
```

## Panneau (UI)

- **Clic gauche** sur l’icone systray : fenetre **Fresh Agent** (onglets Jeu / Skills / IA / Fresh Windows).
- Cases a cocher : IA, RAG, detection auto, surveillance — sans sous-menus.
- **Clic droit** : menu contextuel complet (raccourci « Ouvrir le panneau » en tete).

## Sync

- Menu systray : **Mettre a jour scripts locaux**
- Tache planifiee : `FreshWindows-SyncLocalScripts` (dimanche)
- Script : `scripts/Sync-FreshWindowsAgent.ps1` (registry skills dynamique)

## STT

Defaut : **API Windows** (`System.Speech`), pas CyberScribe. Menu **Ecouter**.

## Tests

```powershell
powershell -NoProfile -File .\tests\Run-AllTests.ps1
powershell -NoProfile -File .\tests\Validate-SkillsRegistry.ps1
```
