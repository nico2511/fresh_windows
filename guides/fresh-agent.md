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
