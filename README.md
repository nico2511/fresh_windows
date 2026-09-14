# Fresh Windows

Toolbox PowerShell pour **réinstaller / reconfigurer un PC Windows** après formatage (ou en maintenance), avec listes d’apps et profils éditables à distance sur GitHub.

## Projet personnel — pas un pack générique

Les listes d’apps et réglages reflètent **ma** machine (imprimante Brother, Nextcloud, CyberScribe, stack gaming/dev, etc.).  
Si tu forks : **édite les JSON** avant de tout installer, sinon tu vas te retrouver avec des apps qui ne te servent à rien.

Ce n’est **pas** un produit multi-utilisateur ni un « Windows ideal pour tout le monde ».

## Lancer

Ouvre **PowerShell en Administrateur** :

```powershell
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1 | iex
```

Au premier lancement menu, un raccourci **Fresh Windows** est créé sur le Bureau (élévation admin + même ref GitHub).

> Les configs sont lues depuis GitHub (`FRESH_WIN_REF`, défaut `main`). Modifier un JSON local dans le clone ne change rien tant que ce n’est pas pushé.

### Pin de version (commit / tag / branche)

Pour figer launcher **et** configs sur une révision précise :

```powershell
$env:FRESH_WIN_REF = 'abc1234'   # SHA, tag ou branche
irm "https://raw.githubusercontent.com/nico2511/fresh_windows/$env:FRESH_WIN_REF/launcher.ps1" | iex
```

Sans `FRESH_WIN_REF`, tout pointe sur `main` (dernière version).

## Menu

| # | Action |
|---|--------|
| 1 | Apps **Standard** (`configs/apps-standard.json`) |
| 2 | Apps **Gaming** |
| 3 | Apps **Dev** |
| 4 | **Full** = Standard + Gaming + Dev |
| 5 | Navigateurs / extensions (Firefox, Chrome, Brave debloat, BetterZen) |
| 6 | `winget upgrade --all` |
| 7 | **WinUtil** — one-click (Standard + AppX + prefs + Ultimate Perf), presets, GUI |
| 8 | Tâches planifiées (1 clic) : winget quotidien + maintenance hebdo |
| 9 | Carte graphique AMD / NVIDIA (liens + guides) |
| 10 | **Mode jeu** — exécuter la liste générique maintenant |
| 11 | **Mode jeu** — raccourci Bureau, agent systray (sous-menu) |
| 0 | Quitter |

### Mode Jeu (liste générique + agent)

- **`game-mode-kill.json`** : domaines `dev`, `containers`, `ai_local`, `3d`, `video`, `sync_and_io`, `productivity_heavy`. **Pas** calqué sur les listes winget d’installation.
- **`protect.communication`** : Discord, Legcord, etc. — **jamais** tués (Teams / `ms-teams` sont dans la liste kill).
- **`gaming_launchers`** : Steam, Epic, GOG… — si **plusieurs** sont ouverts, le mode jeu **garde le plus actif** et ferme les autres (pas de blocage global « tout protéger »).
- **Lancer le kill** :
  - Menu **10**, ou raccourci Bureau **Mode Jeu** (menu **11**, sans admin),
  - ou `$env:FRESH_WIN_MODE='game-mode'`.
- **Agent** (`scripts/GameMode-WatchAgent.ps1`) : icône barre des tâches, poll ~12 s (`game-mode-watch.json`). Toggle **Détection auto** dans `%LOCALAPPDATA%\FreshWindows\watch-agent-user.json` :
  - CPU hors protégés > ~28 % pendant ~2,5 min → notification + suggestion de kill ;
  - RAM anormale → alerte ;
  - disque saturé longtemps **hors session jeu** → alerte (+ noms type Search/Defender/Update) ;
  - process **Not Responding** → suggestion de kill.
- Modes silencieux : `game-mode-shortcuts`, `game-mode-watch`.

### Navigateurs (menu 5)

1. **Extensions Firefox-based** — ouvre les pages AMO (`extensions-firefox-based.json`)
2. **Extensions Chrome-based** — Web Store (`extensions-chrome-based.json`)
3. **Brave — debloat (WinUtil)** — policies HKLM (Rewards, Wallet, VPN, Leo, News, Talk, Tor, télémétrie…) via `configs/winutil-brave-debloat.json`
4. **Zen — BetterZen** — télécharge [Betterfox `zen/user.js`](https://github.com/yokoffing/Betterfox/blob/main/zen/user.js) dans le profil Zen par défaut (backup `user.js.bak-YYYYMMDD`). Relancer Zen après.

Ne pas utiliser le `user.js` Firefox générique sur Zen : uniquement BetterZen.

### Polices (Cascadia / JetBrains Mono)

Pas dans les listes d’apps : Cascadia vient déjà avec Windows Terminal ; JetBrains Mono n’a d’intérêt que si tu la configures dans Cursor / Terminal. Installer « pour installer » ne sert à rien.

### One-click WinUtil (menu 7)

1. Tweaks **Standard** Chris Titus (+ Hyper-V via config)
2. Debloat **AppX** sûr (`winutil-appx.json` — pas de Calculator / Snipping Tool)
3. Préférences registry (ex. dark mode, game mode)
4. Plan d’alimentation **Ultimate Performance**

### Tâches planifiées (menu 8)

| Tâche | Quand | Effet |
|-------|--------|--------|
| `FreshWindows-WingetUpgrade` | tous les jours 12:00 | `winget upgrade --all` (+ rattrapage si PC éteint) |
| `FreshWindows-WinUtilReapply` | dimanche | WinUtil + ShutUp10 — **fenêtre PowerShell visible** + log `%LOCALAPPDATA%\FreshWindows\logs` |

Les tâches enregistrent la **ref** courante (`FRESH_WIN_REF`) pour rester cohérentes.

## Modes silencieux (sans menu)

```powershell
$env:FRESH_WIN_MODE = 'full'   # ou standard | gaming | dev | …
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1 | iex
```

| Mode | Rôle |
|------|------|
| `standard` / `gaming` / `dev` / `full` | Installs winget (+ téléchargements GitHub si objet JSON) |
| `winutil-oneclick` | Profil one-click complet |
| `maintenance` | Re-apply WinUtil + ShutUp10 (tâche hebdo) |
| `winutil-standard` / `minimal` / `advanced` | Preset WinUtil seul |
| `winutil-appx` | Debloat AppX seul |
| `brave-debloat` | Policies Brave via WinUtil (`WPFTweaksBraveDebloat`) |
| `betterzen` | Applique Betterfox `zen/user.js` au profil Zen |
| `tasks` | Crée les deux tâches planifiées (`winget-task` / `winutil-task` = alias, message d’avertissement) |
| `game-mode` | Fermeture process liste générique (respecte `protect`) |
| `game-mode-shortcuts` | Raccourci Bureau Mode Jeu + scripts locaux |
| `game-mode-watch` | Lance l’agent barre des tâches |
| `winget-upgrade` | `winget upgrade --all` (admin via stub) |
| `powertoys-profile` | Merge du profil PowerToys |
| `shutup10` | Applique le cfg recommandé (quiet) |

En mode silencieux : **exit 0** si tout est OK, **exit 1** si un échec (install, WinUtil, ShutUp10, tâches, etc.). Les erreurs ne sont plus avalées silencieusement (`$ErrorActionPreference = Stop` + bilan explicite).

## Tests

Smoke tests des configs (JSON + format ShutUp10 CLI) :

```powershell
powershell -NoProfile -File .\tests\Validate-Configs.ps1
```

À lancer avant un push si tu touches `configs/`.

## Contenu du dépôt

```
launcher.ps1                 # menu + modes silencieux
configs/
  apps-*.json                # listes winget (+ objets URL GitHub) — stack personnelle
  winutil-oneclick.json
  winutil-appx.json
  winutil-brave-debloat.json # Brave Rewards/Wallet/VPN/Leo…
  powertoys-profile.json
  shutup10-recommended.cfg   # SettingID + TAB + +/-
  game-mode-kill.json        # domaines + protect comm/gaming
  game-mode-watch.json       # seuils agent surveillance
scripts/
  lib/
    Import-CachedScript.ps1   # cache GitHub → %LOCALAPPDATA%\FreshWindows
    Launcher-Core.ps1         # Wait-ForUser, winget, stubs, sync mode jeu
  GameMode-Common.ps1
  Invoke-GameModeKill.ps1
  GameMode-WatchAgent.ps1
  gpu.json
  extensions-*.json
guides/                      # AMD, NVIDIA, ShutUp10
tests/Validate-Configs.ps1
assets/fresh-windows.ico
```

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

### ShutUp10

- Le fichier UI `%LOCALAPPDATA%\OO Software\OO ShutUp10\OOSU10.cfg` **n’est pas** importable en CLI.
- Le profil applyable est `configs/shutup10-recommended.cfg` (lignes `SettingID` + tab + `+`/`-`).
- CLI : `ooshutup10.exe <cfg> /quiet /nosrp /lang:fr`
- Version **gratuite** : Windows Update peut réécrire des réglages → la tâche hebdo les re-applique.

Détails : [guides/shutup10.md](guides/shutup10.md).

## Modifier les listes

1. Éditer les JSON / cfg dans ce repo
2. Lancer `tests\Validate-Configs.ps1`
3. Commit + push sur `main` (ou un tag / commit pour pin)
4. Relancer le launcher

## Prérequis / limites

- Windows 10/11, **PowerShell admin**, **winget**, réseau
- Confiance requise : scripts téléchargés (`launcher` + WinUtil depuis christitus.com)
- Pas de mode hors-ligne
- Stack **personnelle** — adapte avant d’installer

## Licence

Usage perso. Fork / copie / adaptation libre pour ta machine.
