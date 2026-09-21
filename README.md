# Fresh Windows

Toolbox PowerShell pour réinstaller et entretenir Windows après un formatage. Les listes d’applications, tweaks et réglages sont versionnés en JSON sur GitHub : tu modifies, tu pousses, tu relances.

```powershell
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1 | iex
```

PowerShell **administrateur** requis. Au premier lancement, un raccourci **Fresh Windows** est créé sur le Bureau.

![Menu Fresh Windows](Docs/sc.jpg)

---

## Démarrage rapide

| Étape | Menu | Action |
|------:|:----:|--------|
| 1 | **5** | Full setup — apps standard + gaming + dev |
| 2 | **8** | Tweaks one-click (WinUtil + AppX + perfs) |
| 3 | **9** | Tâches planifiées (winget, maintenance, sync) |
| 4 | **11** | Mode jeu (lancer / raccourci / agent) |
| 5 | **6** | Extensions navigateurs + profil Brave (si besoin) |

---

## Menu

| # | Section | Description |
|---|---------|-------------|
| 1 | Apps standard | Navigateur, utilitaires, sécurité, bureautique |
| 2 | Apps gaming | Launchers, overlays, outils GPU |
| 3 | Apps dev | Éditeurs, runtimes, CLI |
| 4 | Apps custom | Paquets utilisateur détectés automatiquement |
| 5 | Full setup | Enchaîne 1 + 2 + 3 |
| 6 | Navigateurs | Extensions Firefox/Chrome + policies Brave |
| 7 | Winget upgrade | Met à jour toutes les apps winget |
| 8 | Tweaks | One-click, ShutUp10, presets WinUtil |
| 9 | Tâches | MAJ quotidienne + maintenance hebdo + sync scripts |
| 10 | GPU | AMD Adrenalin / Ryzen Master, NVIDIA / NVCleanstall |
| 11 | Mode jeu | Kill list, raccourci Bureau, agent systray |
| 0 | Quitter | — |

---

## Paquets d’applications

Trois paquets intégrés vivent dans `configs/` :

- `apps-standard.json`
- `apps-gaming.json`
- `apps-dev.json`

### Paquets custom

Le 4ᵉ type de paquet est **auto-détecté**. Dépose un fichier `*.json` (même format que les paquets intégrés) dans l’un de ces emplacements :

| Emplacement | Portée |
|-------------|--------|
| `configs/apps-custom/` | Repo / fork (partagé via GitHub) |
| `%LOCALAPPDATA%\FreshWindows\apps-custom\` | Machine locale uniquement |

Le menu **4** liste les paquets trouvés. Un paquet local du même nom remplace la version distante.

**Trouver un ID winget** : [winstall.app](https://winstall.app) ou `winget search NomDeLApp`.

Exemple minimal :

```json
[
  "7zip.7zip",
  "Microsoft.PowerToys"
]
```

Apps hors catalogue winget (exe / zip) :

```json
{
  "name": "MonApp",
  "url": "https://example.com/MonApp.exe",
  "destDir": "%LOCALAPPDATA%\\Programs\\MonApp",
  "fileName": "MonApp.exe",
  "shortcut": true
}
```

---

## Mode silencieux

```powershell
$env:FRESH_WIN_MODE = 'full'   # standard | gaming | dev | custom | custom:mon-paquet | …
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1 | iex
```

`exit 0` = succès, `exit 1` = au moins une étape en échec.

| Mode | Rôle |
|------|------|
| `standard` / `gaming` / `dev` / `full` | Installs winget (+ téléchargements URL) |
| `custom` | Tous les paquets custom détectés |
| `custom:nom` | Un paquet custom précis |
| `winutil-oneclick` / `maintenance` | Tweaks WinUtil (+ ShutUp10 en maintenance) |
| `winutil-standard` / `minimal` / `advanced` | Presets WinUtil |
| `winutil-appx` | Debloat AppX |
| `brave-optimize` / `betterzen` | Policies Brave / Betterfox Zen |
| `tasks` | Enregistre les tâches planifiées |
| `game-mode` / `game-mode-shortcuts` / `game-mode-watch` | Mode jeu |
| `winget-upgrade` | `winget upgrade --all` |
| `powertoys-profile` / `shutup10` | Profils dédiés |

### Figer une version

```powershell
$env:FRESH_WIN_REF = 'abc1234'   # commit, tag ou branche
irm "https://raw.githubusercontent.com/nico2511/fresh_windows/$env:FRESH_WIN_REF/launcher.ps1" | iex
```

---

## Architecture

| Chemin | Rôle |
|--------|------|
| `launcher.ps1` | Point d’entrée (`irm \| iex`), menu, installs |
| `scripts/lib/` | Modules (Core, WinUtil, Tasks, GPU) |
| `scripts/GameMode-*.ps1` | Mode jeu + agent systray |
| `configs/*.json` | Listes apps, tweaks, extensions, GPU |
| `configs/apps-custom/` | Paquets utilisateur (auto-listés) |
| `guides/` | Guides NVIDIA / AMD / ShutUp10 |

Ordre de chargement des libs : `Import-CachedScript` → `Core` → `WinUtil` → `Tasks` → `GpuMenus`.

Lancement distant : cache sous `%LOCALAPPDATA%\FreshWindows` (epoch `FreshWindowsLibEpoch` pour invalider quand `FRESH_WIN_REF` reste `main`).

---

## Mode jeu

Ferme les processus hors session jeu (dev, IA locale, sync, tray sécurité, messagerie hors Discord/Legcord…). **Ne tue jamais** la famille de launcher d’une session active. Sans session claire → aucun launcher tué. Active **Ultimate Performance** au lancement.

Config : `configs/game-mode-kill.json` (domaines, protections, familles de launchers) et `configs/game-mode-watch.json` (seuils agent).

Scripts locaux : `%LOCALAPPDATA%\FreshWindows\` + marqueur `scripts.ref`. Agent au logon via la tâche `FreshWindows-WatchAgent`.

---

## Tâches planifiées

| Tâche | Quand | Action |
|-------|-------|--------|
| `FreshWindows-WingetUpgrade` | Quotidien 12:00 | `winget upgrade --all` |
| `FreshWindows-WinUtilReapply` | Dimanche 12:00 | Mode `maintenance` |
| `FreshWindows-SyncLocalScripts` | Dimanche 12:30 | Resync scripts mode jeu |

La ref `FRESH_WIN_REF` est figée dans la tâche à l’enregistrement. Logs : `%LOCALAPPDATA%\FreshWindows\logs\`.

---

## Navigateurs & tweaks

**Brave** — à l’install, policies sous `HKLM\SOFTWARE\Policies\BraveSoftware\Brave` (coupe Rewards/Wallet/VPN/Leo/News ; garde Shields, Sync, Tor). Vérif : `brave://policy`.

**Zen** — Betterfox `user.js` écrit à l’install.

**Everything** — service et démarrage auto désactivés après install.

**ShutUp10** — winget `OO-Software.ShutUp10` + profil CLI `configs/shutup10-recommended.cfg`. Voir [guides/shutup10.md](guides/shutup10.md).

**GPU** — menu 10 + [guides/nvidia-nvcleanstall.md](guides/nvidia-nvcleanstall.md) / [guides/amd-adrenalin.md](guides/amd-adrenalin.md). DDU et NVCleanstall sont dans les listes apps ; le nettoyage pilote propre se fait en mode sans échec (voir guide NVIDIA).

---

## Tests

```powershell
powershell -NoProfile -File .\tests\Validate-Configs.ps1
powershell -NoProfile -File .\tests\Run-AllTests.ps1
```

---

## Prérequis

- Windows 10 / 11
- PowerShell administrateur
- winget + réseau
- Pas de mode hors-ligne pour le lancement `irm`

Les listes par défaut reflètent une stack personnelle : fork et adapte les JSON avant une install massive.

## Licence

Usage perso. Fork et adaptation libres pour ta machine.
