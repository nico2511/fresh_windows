# Désinstallation de Fresh Windows

Ce guide décrit comment retirer Fresh Windows de la machine **sans** désinstaller les applications ni annuler les réglages déjà appliqués par winget, WinUtil ou ShutUp10.

## Ce qui est supprimé

- L’**agent** (systray) et les processus Fresh ciblés par chemin `%LOCALAPPDATA%\FreshWindows\` (Watch Agent, VoiceHost, stubs jeu, `voice_worker` sous `bin\` uniquement) — **pas** les apps tierces type CyberScribe installées ailleurs.
- Les **tâches planifiées** dont le nom commence par `FreshWindows-*`, notamment :
  - `FreshWindows-SyncLocalScripts`
  - `FreshWindows-WatchAgent`
  - `FreshWindows-WingetUpgrade`
  - `FreshWindows-WinUtilReapply`
- Les **raccourcis Bureau** attribués à Fresh (cible vérifiable) : « Fresh Windows » / `FreshWindows.lnk`, `Mode Jeu.lnk` si pointeur Fresh ; homonymes tiers conservés.
- Le dossier **`%LOCALAPPDATA%\FreshWindows`** (scripts mis en cache, configs locales, logs).
- Les dossiers **`%TEMP%\fw-test*`** portant le fichier marqueur **`.fresh-windows-uninstall-owned`** (les autres `fw-test*` sont signalés mais non supprimés).

## Ce qui est conservé

- Les **applications installées via winget** (ou le menu Fresh Windows) : elles ne sont pas désinstallées.
- Les **réglages WinUtil** et **ShutUp10++** déjà appliqués : le script ne les annule pas.
- Les **dossiers de modèles vocaux externes** éventuels (hors `%LOCALAPPDATA%\FreshWindows`), si vous les aviez placés ailleurs pour Piper / STT.

## Via le menu Fresh Windows (recommandé)

1. Lancer le **launcher** en PowerShell **administrateur** (one-liner README ou raccourci Bureau).
2. Choisir **12 — Désinstallation**.
3. Options :
   - **3 — Simulation (DryRun)** : aucune suppression agent/tâches/cache ; depuis un clone local, exécution **en mémoire** ; sinon staging temporaire sous `%TEMP%` (annoncé) supprimé après la simulation.
   - **2 — Désinstallation complète** : confirmation **OUI** requise ; supprime l’installation locale Fresh puis quitte le launcher.
   - **1 — Désinstaller puis réinstaller** : taper exactement **OUI** ; nettoyage vérifié puis relance du launcher **`main`** via un stub temporaire sous `%TEMP%\FreshWindows-Reinstall-*\` (auto-nettoyé, hors cache supprimé).
4. Seule la saisie exacte **OUI** confirme ; toute autre réponse **annule** sans effet.

## Méthode CLI (script du dépôt)

1. Ouvrir **PowerShell en administrateur**.
2. Lancer d’abord une **simulation** (`-DryRun`) : aucun fichier ni tâche n’est supprimé ; le script affiche ce qu’il ferait.
3. Pour une suppression réelle : ajouter **`-Confirmed`** (obligatoire hors DryRun).
4. Pour **réinstaller ensuite** : `-Confirmed -ReinstallAfter` (relance `main` uniquement après vérification du nettoyage).

Depuis une copie locale du dépôt :

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd chemin\vers\fresh_windows\scripts
.\Uninstall-FreshWindows.ps1 -DryRun
# puis, si OK :
.\Uninstall-FreshWindows.ps1 -Confirmed
```

### Sans cloner le dépôt (simulation DryRun)

Télécharger le **wrapper** et la **bibliothèque** dans la même arborescence :

```powershell
$dir = Join-Path $env:TEMP ('FreshWindows-UninstallCli-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path (Join-Path $dir 'lib') -Force | Out-Null
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/scripts/Uninstall-FreshWindows.ps1 -OutFile (Join-Path $dir 'Uninstall-FreshWindows.ps1')
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/scripts/lib/FreshWindows-Uninstall.ps1 -OutFile (Join-Path $dir 'lib/FreshWindows-Uninstall.ps1')
& (Join-Path $dir 'Uninstall-FreshWindows.ps1') -DryRun
```

Suppression réelle (PowerShell **admin**) :

```powershell
& (Join-Path $dir 'Uninstall-FreshWindows.ps1') -Confirmed
```

Réinstallation après nettoyage : ajouter `-Confirmed -ReinstallAfter` (code sortie **5** = relance démarrée, succès `irm` non garanti).

### Vérification non destructive (Windows PS 5.1)

Fichiers à télécharger depuis `main` (sans clone complet) :

| Fichier | Rôle |
|---------|------|
| `scripts/lib/FreshWindows-Uninstall.ps1` | Logique testable hors admin en `-DryRun` |
| `tests/Invoke-UninstallSafeHarness.ps1` | Lance sandbox sous `%TEMP%` + DryRun |

```powershell
powershell -NoProfile -File .\tests\Invoke-UninstallSafeHarness.ps1
```

## Méthode manuelle (sans script)

1. **Arrêter l’agent** : quitter l’icône systray Fresh Agent si présente, ou tuer les processus PowerShell / associés dont la commande contient `FreshWindows` ou `GameMode-Watch` (Gestionnaire des tâches ou `Stop-Process`).
2. **Supprimer les tâches planifiées** : Planificateur de tâches → tâches `FreshWindows-*` → Supprimer (ou `Unregister-ScheduledTask` en admin).
3. **Supprimer les raccourcis** sur le Bureau utilisateur et le Bureau public (`Fresh Windows.lnk`, `FreshWindows.lnk`).
4. **Supprimer le dossier** `%LOCALAPPDATA%\FreshWindows`.
5. **Nettoyer** les dossiers `%TEMP%\fw-test*` le cas échéant.
6. **Vérifier** qu’il ne reste plus de tâche `FreshWindows-*`, plus de dossier `%LOCALAPPDATA%\FreshWindows`, et plus de processus Fresh Windows actif.

## Après la désinstallation

Le launcher `irm …/launcher.ps1 | iex` peut être relancé à tout moment pour réinstaller la toolbox sur la machine. Les apps et tweaks déjà en place restent tels quels.
