# Fresh Agent (systray)

Agent **Fresh Windows** : mode jeu, skills, panneau dashboard. Chantier voix/IA reconstruit (voice_worker asset + router + overlay).

## Core vs voix / IA

| Composant | Defaut | Notes |
|-----------|--------|-------|
| Mode jeu / session | Oui | Independant de l'IA |
| Skills (menu / panneau) | Oui | Sans Ollama |
| Ecoute vocale | OFF au boot | Boutons **Ecoute ON / OFF** |
| Ollama tool calling | OFF | `agent-ai.enabled` |
| TTS | edge-tts (neural FR) | Secours Windows SAPI |

## Fichiers locaux (%LOCALAPPDATA%\\FreshWindows)

| Fichier | Role |
|---------|------|
| `agent-ai.user.json` | Override IA / TTS / voix |
| `bin/voice_worker.exe` | Asset STT (telecharge au besoin) |
| `skills-apps.user.json` | Aliases apps perso |
| `inventory.json` | Jeux Steam, navigateur |
| `configs/skills/router/fr-pc.json` | Patterns vocaux → skills |

## Developpement local (sans casser la prod)

```powershell
cd D:\Git\FreshWindows
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-FreshAgentDev.ps1
# profil isole : %LOCALAPPDATA%\FreshWindows-Dev
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Stop-FreshAgentDev.ps1
```

Sync prod AppData :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Dev-SyncFreshAgentFromRepo.ps1
```

## Panneau

- **Clic gauche** : Jeu / Skills / IA / Fresh Windows
- **Jeu** + **Skills** + **Fresh Windows** : core stable
- **IA** : Ecoute ON/OFF, Ollama optionnel, TTS

Feedback voix/skills : **overlay** discret (pas de ballons invasifs).

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-AllTests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-SkillsRegistry.ps1
```
