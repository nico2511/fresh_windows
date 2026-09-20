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

![Menu Fresh Windows](Docs/sc.jpg)

Tout est téléchargé depuis GitHub (`main` par défaut). Pas besoin de cloner le repo pour l’usage courant.

### Après un formatage — ordre conseillé

| Étape | Menu | En bref |
|-------|------|---------|
| 1 | **4** Full | Installe tes apps (Zen/Brave déjà optimisés à l’install) |
| 2 | **7** Tweaks | Profil **one-click** (tweaks + AppX + perfs) |
| 3 | **8** → 1 | Active les **tâches planifiées** (winget + maintenance + sync scripts) |
| 4 | **10** | Mode jeu : lancer / raccourci Bureau / agent barre des tâches |
| 5 | **5** | Extensions navigateurs (si besoin) + réappliquer/retirer profil Brave |

### Menu — l’essentiel

| # | Tu veux… |
|---|----------|
| 1–4 | Installer des apps (winget + GitHub) |
| 5 | Navigateurs & extensions (+ profil Brave) |
| 6 | Mettre à jour toutes les apps (`winget upgrade`) |
| 7 | Tweaks Windows (one-click, ShutUp10, presets) |
| 8 | Automatiser updates + maintenance + sync scripts |
| 9 | GPU AMD (Adrenalin / Ryzen Master) ou NVIDIA |
| 10 | **Mode jeu** (lancer / raccourci / agent) |
| 0 | Quitter |

**Mode jeu** : ferme ce qui consomme sans servir la session (dev, IA locale, sync, Bitwarden tray, messagerie hors Discord/Legcord…). **Ne tue jamais** la famille de launcher d’une session active (ex. FIFA / EA). Sans session claire → aucun launcher tué. Active / vérifie **Ultimate Performance** au lancement. Pas d’IA pendant le mode jeu (Ollama est dans la kill list).

**Agent** (menu 10 → 3) : une seule tâche `FreshWindows-WatchAgent` au logon (plus de double Startup + tâche). Mutex anti-doublon. Alertes légères (CPU, RAM, disque) + accès rapide Fresh Windows.

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
- **`scripts/GameMode-*.ps1`** — kill liste + agent systray (copiés en local via menu 10).
- **`configs/*.json`** — listes winget, presets WinUtil, mode jeu, Brave, extensions, GPU.

Ordre de chargement des libs : `Import-CachedScript` → `Core` → `WinUtil` → `Tasks` → `GpuMenus`.

### Menu détaillé

| # | Action |
|---|--------|
| 1 | `apps-standard.json` |
| 2 | `apps-gaming.json` |
| 3 | `apps-dev.json` |
| 4 | Full = 1 + 2 + 3 |
| 5 | Extensions FF/Chrome + réappliquer/retirer profil Brave |
| 6 | `Invoke-WingetUpgradeAll` |
| 7 | One-click / ShutUp10 / WinUtil GUI / presets (plus d’AppX seul) |
| 8 | Tâches + maintenance immédiate |
| 9 | `gpu.json` + guides (+ Ryzen Master selon CPU) |
| 10 | Sous-menu mode jeu : lancer / raccourci / agent |
| 0 | Quitter |

#### Menu 5 — navigateurs

1. Extensions Firefox (`extensions-firefox-based.json`)
2. Extensions Chrome (`extensions-chrome-based.json`)
3. Profil Brave — réappliquer / retirer (`brave-optimize.json`)

**Zen** : à l’install `Zen-Team.Zen-Browser`, Betterfox `zen/user.js` est écrit (profil créé si besoin).

**Brave** : à l’install `Brave.Brave`, policies Fresh sous `HKLM\SOFTWARE\Policies\BraveSoftware\Brave`.

| Couper | Garder |
|--------|--------|
| Rewards, Wallet, VPN, Leo, News, Talk, télémétrie | Shields, **Sync**, **Tor** |

Vérif : `brave://policy`. Undo via menu 5 → 3 → retirer.

**Everything** : post-install, service + démarrage auto désactivés (lancement manuel seulement).

#### Menu 7 — Tweaks

1. WinUtil `-Config` → `winutil-oneclick.json` + prefs + Ultimate Performance
2. OO ShutUp10 (winget `OO-Software.ShutUp10` uniquement — plus de portable)
3. WinUtil GUI
4. Presets Standard / Minimal / Advanced

### Mode jeu

**`configs/game-mode-kill.json`**

- **`domains`** : `dev`, `containers`, `ai_local`, `3d`, `video`, `sync_and_io`, `productivity_heavy`, `security_tray` (Bitwarden), `messaging`, `ai_agents`.
- **`protect.communication`** : Discord, Legcord, Slack, Zoom — jamais tués.
- **`gaming_launcher_families`** : familles `steam`, `ea`, `epic`, … Heuristique : ne tue une famille idle **que** si une autre a une session jeu active ; sans session claire → **aucun** launcher tué.
- Ultimate Performance : vérifié / activé au lancement du mode jeu (pas de recreate systématique).

**`configs/game-mode-watch.json`** — seuils agent (poll ~12 s).

**Paramètres utilisateur** : `%LOCALAPPDATA%\FreshWindows\watch-agent-user.json` (`autoSuggestKill`, `monitorEnabled`).

**Scripts locaux** : `%LOCALAPPDATA%\FreshWindows\` + `scripts.ref`. Menu 10, agent, ou tâche hebdo `FreshWindows-SyncLocalScripts`.

**Agent au démarrage** : tâche `FreshWindows-WatchAgent` (AtLogOn, Limited, délai 45 s) uniquement. Le stub `Launch-GameModeWatch.ps1` re-télécharge l’agent s’il a disparu.

### Tâches planifiées

| Tâche | Planification | Commande |
|-------|----------------|----------|
| `FreshWindows-WingetUpgrade` | Quotidien 12:00 | `winget upgrade --all` |
| `FreshWindows-WinUtilReapply` | Dimanche 12:00 | `FRESH_WIN_MODE=maintenance` |
| `FreshWindows-SyncLocalScripts` | Dimanche 12:30 | Resync scripts Mode jeu locaux |

La ref `FRESH_WIN_REF` est figée dans l’action de la tâche au moment de l’enregistrement. Logs maintenance : `%LOCALAPPDATA%\FreshWindows\logs\maintenance-*.log`.

### Modes silencieux (`FRESH_WIN_MODE`)

| Mode | Rôle |
|------|------|
| `standard` / `gaming` / `dev` / `full` | Installs winget (+ objets URL GitHub / zip) |
| `winutil-oneclick` | Profil one-click |
| `maintenance` | WinUtil one-click + ShutUp10 quiet |
| `winutil-standard` / `minimal` / `advanced` | Presets WinUtil |
| `winutil-appx` | Debloat AppX (`winutil-appx.json`) |
| `brave-optimize` / `brave-debloat` | Policies Brave Fresh |
| `betterzen` | Betterfox Zen `user.js` (+ profil si besoin) |
| `tasks` | Crée les tâches planifiées |
| `game-mode` | Kill liste + launchers idle (heuristique familles) |
| `game-mode-shortcuts` | Sync scripts + raccourci Bureau |
| `game-mode-watch` | Lance l’agent systray |
| `winget-upgrade` | `winget upgrade --all` |
| `powertoys-profile` | Merge `powertoys-profile.json` |
| `shutup10` | `shutup10-recommended.cfg` quiet |

### ShutUp10

- Winget uniquement : `OO-Software.ShutUp10` (plus de téléchargement portable O&O).
- Le `OOSU10.cfg` UI **n’est pas** importable en CLI.
- Profil CLI : `configs/shutup10-recommended.cfg` (`SettingID` + TAB + `+`/`-`).
- Commande : `ooshutup10.exe <cfg> /quiet /nosrp /lang:fr`

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

Archives zip :

```json
{
  "name": "CyberScribeNote",
  "url": "https://github.com/nico2511/CyberScribeNote/releases/latest/download/CyberScribeNote-win.zip",
  "destDir": "%LOCALAPPDATA%\\Programs\\CyberScribeNote",
  "fileName": "CyberScribeNote-win.zip",
  "archive": true,
  "shortcutExe": "CyberScribeNote.exe",
  "shortcut": true
}
```

Apps standard notables : UniGetUI `Devolutions.UniGetUI`, CyberScribe + CyberScribeNote.

### Arborescence

```
launcher.ps1
configs/
  apps-*.json
  winutil-*.json
  brave-optimize.json
  game-mode-kill.json
  game-mode-watch.json
  powertoys-profile.json
  shutup10-recommended.cfg
  gpu.json
  extensions-*.json
scripts/
  lib/
  GameMode-Common.ps1
  Invoke-GameModeKill.ps1
  GameMode-WatchAgent.ps1
guides/
tests/
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
4. Relancer le launcher (ou menu 10 / sync agent / tâche hebdo pour scripts locaux)

### Prérequis et limites

- Windows 10/11, PowerShell **admin**, winget, réseau
- Scripts tiers : WinUtil (`christitus.com/win`), ShutUp10 (O&O via winget)
- Pas de mode hors-ligne pour le launcher `irm`
- Listes = stack personnelle (Brother, Nextcloud, CyberScribe, CyberScribeNote, etc.)

### Notes diverses

- Polices : Cascadia = Windows Terminal ; JetBrains Mono seulement si configurée dans l’éditeur.
- Pas de Microsoft PC Manager dans les listes par défaut (optionnel via winget `Microsoft.PCManager`).
- Ryzen Master : URL selon motif CPU dans `gpu.json` ; sinon page AMD.

## Licence

Usage perso. Fork et adaptation libres pour ta machine.
