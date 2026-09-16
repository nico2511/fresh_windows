# Fresh Windows

Toolbox PowerShell pour remettre **ton** Windows d’aplomb après formatage ou en entretien. Les listes d’apps et les réglages vivent sur GitHub : tu modifies les JSON, tu relances le script.

> **Projet perso** — pas un pack « pour tout le monde ». Si tu forks, édite les JSON avant d’installer.

---

## Guide simple

### Démarrer (une fois)

1. Ouvre **PowerShell en administrateur**.
2. Colle :

```powershell
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1 | iex
```

3. Un raccourci **Fresh Windows** apparaît sur le Bureau au premier menu.

Tout est téléchargé depuis GitHub (`main` par défaut). Pas besoin de cloner le repo pour l’usage courant.

### Après un formatage — ordre conseillé

| Étape | Menu | En bref |
|-------|------|---------|
| 1 | **4** Full | Installe tes apps (standard + gaming + dev) |
| 2 | **7** WinUtil | Profil **one-click** (tweaks + debloat + perfs) |
| 3 | **8** → 1 | Active les **tâches planifiées** (mises à jour + maintenance dimanche) |
| 4 | **11** → 1 ou 2 | Raccourci **Mode jeu** + option agent barre des tâches |
| 5 | **5** | Extensions navigateurs / Brave debloat / Zen si besoin |

### Menu — l’essentiel

| # | Tu veux… |
|---|----------|
| 1–4 | Installer des apps (winget) |
| 5 | Navigateurs & extensions |
| 6 | Mettre à jour toutes les apps (`winget upgrade`) |
| 7 | Tweaks Windows (WinUtil + ShutUp10) |
| 8 | Automatiser updates + maintenance hebdo |
| 9 | Liens / guides GPU AMD ou NVIDIA |
| 10 | **Mode jeu** : fermer apps lourdes tout de suite |
| 11 | Installer raccourci Mode jeu + **agent** (icône près de l’horloge) |
| 0 | Quitter |

**Mode jeu** : ferme dev, IA, 3D, vidéo, sync… **sans** toucher Legcord/Discord. Si plusieurs launchers (Steam, Epic…) sont ouverts, seul le plus actif reste. Teams est fermé.

**Agent** (menu 11) : alertes légères (CPU, RAM, disque) et accès rapide au menu Fresh Windows. Toggle « Détection auto » dans le clic droit sur l’icône.

### Sans le menu (raccourci script)

```powershell
$env:FRESH_WIN_MODE = 'full'    # ou : standard | gaming | dev | maintenance | game-mode | …
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1 | iex
```

`exit 0` = OK, `exit 1` = une étape a échoué.

### Figer une version (optionnel)

```powershell
$env:FRESH_WIN_REF = 'abc1234'   # commit, tag ou branche
irm "https://raw.githubusercontent.com/nico2511/fresh_windows/$env:FRESH_WIN_REF/launcher.ps1" | iex
```

---

## Documentation technique

### Architecture

- **`launcher.ps1`** — point d’entrée (`irm | iex`), menu, installs winget, modes silencieux.
- **`scripts/lib/`** — modules dot-sourcés (clone local ou cache `%LOCALAPPDATA%\FreshWindows` si lancement distant) :
  - `Import-CachedScript.ps1` — téléchargement par `FRESH_WIN_REF` + epoch libs (`FreshWindowsLibEpoch` dans `launcher.ps1`, pour invalider le cache quand la ref reste `main`)
  - `Launcher-Core.ps1` — pause, winget upgrade, stubs, sync scripts mode jeu
  - `Launcher-WinUtil.ps1` — Chris Titus WinUtil, O&O ShutUp10, maintenance hebdo
  - `Launcher-Tasks.ps1` — tâches planifiées
  - `Launcher-GpuMenus.ps1` — menus AMD / NVIDIA
- **`scripts/GameMode-*.ps1`** — kill liste + agent systray (copiés en local via menu 11).
- **`configs/*.json`** — listes winget, presets WinUtil, mode jeu, extensions, GPU.

Ordre de chargement des libs : `Import-CachedScript` → `Core` → `WinUtil` → `Tasks` → `GpuMenus`.

### Menu détaillé

| # | Action |
|---|--------|
| 1 | `apps-standard.json` |
| 2 | `apps-gaming.json` |
| 3 | `apps-dev.json` |
| 4 | Full = 1 + 2 + 3 |
| 5 | Sous-menu extensions / Brave debloat / BetterZen |
| 6 | `Invoke-WingetUpgradeAll` |
| 7 | Sous-menu WinUtil (one-click, presets, AppX, ShutUp10 GUI, WinUtil GUI) |
| 8 | Sous-menu tâches + maintenance immédiate |
| 9 | `gpu.json` + guides |
| 10 | `Invoke-GameModeKill` (admin, recharge `GameMode-Common` si ref change) |
| 11 | `Open-GameModeSetupMenu` — raccourci, startup agent, lancer agent |
| 0 | Quitter |

#### Menu 5 — navigateurs

1. Extensions Firefox (`extensions-firefox-based.json`)
2. Extensions Chrome (`extensions-chrome-based.json`)
3. Brave debloat → `winutil-brave-debloat.json`
4. BetterZen → [Betterfox `zen/user.js`](https://github.com/yokoffing/Betterfox/blob/main/zen/user.js) (pas le `user.js` Firefox générique)

#### Menu 7 — WinUtil one-click

1. WinUtil `-Config` → `winutil-oneclick.json` (Standard + AppX + Hyper-V…)
2. `Invoke-WinUtilPreferences` (dark, game mode, fichiers, Bing, DNS Quad9)
3. `Enable-UltimatePerformance`

### Mode jeu

**`configs/game-mode-kill.json`**

- **`domains`** : `dev`, `containers`, `ai_local`, `3d`, `video`, `sync_and_io`, `productivity_heavy`, `messaging`, `ai_agents` (noms de process Windows, indépendants des listes winget).
- **`protect.communication`** : Discord, Legcord, Slack, Zoom — jamais tués.
- **`gaming_launchers`** : si plusieurs launchers ouverts, `Stop-IdleGamingLaunchers` garde le plus actif (RAM/CPU).
- Kill : Teams (`productivity_heavy`) ; Signal, WhatsApp, Telegram, Skype (`messaging`) ; Codex, Claude Code, Hermes, OpenClaw (ex-Clawdbot), DeepSeek Harness (`ai_agents`).

**`configs/game-mode-watch.json`** — seuils agent (poll ~12 s).

**Paramètres utilisateur** : `%LOCALAPPDATA%\FreshWindows\watch-agent-user.json` (`autoSuggestKill`, `monitorEnabled`).

**Scripts locaux** : `%LOCALAPPDATA%\FreshWindows\` + `scripts.ref` (ref GitHub). Menu 11 ou agent → « Mettre à jour scripts locaux ».

**Agent au démarrage** : raccourci Startup + tâche `FreshWindows-WatchAgent` (AtLogOn, Limited, délai 45 s). Le stub `Launch-GameModeWatch.ps1` re-télécharge `GameMode-WatchAgent.ps1` s’il a disparu.

### Tâches planifiées

| Tâche | Planification | Commande |
|-------|----------------|----------|
| `FreshWindows-WingetUpgrade` | Quotidien 12:00 | `Get-WingetUpgradePowerShellCommand` |
| `FreshWindows-WinUtilReapply` | Dimanche 12:00 | `FRESH_WIN_MODE=maintenance` via `irm` launcher |

La ref `FRESH_WIN_REF` est figée dans l’action de la tâche au moment de l’enregistrement. Logs maintenance : `%LOCALAPPDATA%\FreshWindows\logs\maintenance-*.log`.

### Modes silencieux (`FRESH_WIN_MODE`)

| Mode | Rôle |
|------|------|
| `standard` / `gaming` / `dev` / `full` | Installs winget (+ objets URL GitHub) |
| `winutil-oneclick` | Profil one-click |
| `maintenance` | WinUtil one-click + ShutUp10 quiet |
| `winutil-standard` / `minimal` / `advanced` | Presets WinUtil |
| `winutil-appx` | Debloat AppX (`winutil-appx.json`) |
| `brave-debloat` | `winutil-brave-debloat.json` |
| `betterzen` | Betterfox Zen `user.js` |
| `tasks` | Crée les deux tâches (`winget-task` / `winutil-task` → alias) |
| `game-mode` | Kill liste + launchers inactifs |
| `game-mode-shortcuts` | Sync scripts + raccourci Bureau |
| `game-mode-watch` | Lance l’agent systray |
| `winget-upgrade` | `winget upgrade --all` |
| `powertoys-profile` | Merge `powertoys-profile.json` |
| `shutup10` | `shutup10-recommended.cfg` quiet |

### ShutUp10

- Le `OOSU10.cfg` UI **n’est pas** importable en CLI.
- Profil CLI : `configs/shutup10-recommended.cfg` (`SettingID` + TAB + `+`/`-`).
- Commande : `ooshutup10.exe <cfg> /quiet /nosrp /lang:fr`
- Version gratuite : Windows Update peut réécrire des réglages → tâche hebdo.

Voir [guides/shutup10.md](guides/shutup10.md).

### Apps hors winget

```json
{
  "name": "CyberScribe",
  "url": "https://github.com/.../CyberScribe.exe",
  "destDir": "%LOCALAPPDATA%\\Programs\\CyberScribe",
  "fileName": "CyberScribe.exe",
  "shortcut": true
}
```

### Arborescence

```
launcher.ps1
configs/
  apps-*.json
  winutil-*.json
  game-mode-kill.json
  game-mode-watch.json
  powertoys-profile.json
  shutup10-recommended.cfg
  gpu.json
  extensions-*.json
scripts/
  lib/                    # voir Architecture
  GameMode-Common.ps1
  Invoke-GameModeKill.ps1
  GameMode-WatchAgent.ps1
guides/
tests/
  Validate-Configs.ps1
  Run-AllTests.ps1
  Launcher-Core.Tests.ps1
assets/fresh-windows.ico
```

### Tests

```powershell
powershell -NoProfile -File .\tests\Validate-Configs.ps1
powershell -NoProfile -File .\tests\Run-AllTests.ps1   # + Pester si installé
```

### Workflow Git

1. Éditer JSON / cfg
2. `tests\Validate-Configs.ps1` (ou `Run-AllTests.ps1`)
3. Commit + push
4. Relancer le launcher (ou menu 11 / sync agent pour scripts locaux)

### Prérequis et limites

- Windows 10/11, PowerShell **admin**, winget, réseau
- Scripts tiers : WinUtil (`christitus.com/win`), ShutUp10 (O&O)
- Pas de mode hors-ligne pour le launcher `irm`
- Listes = stack personnelle (Brother, Nextcloud, CyberScribe, etc.)

### Notes diverses

- Polices : Cascadia = Windows Terminal ; JetBrains Mono seulement si configurée dans l’éditeur.
- Pas de Microsoft PC Manager dans les listes par défaut (optionnel via winget `Microsoft.PCManager`).

## Licence

Usage perso. Fork et adaptation libres pour ta machine.
